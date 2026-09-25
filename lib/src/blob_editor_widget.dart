import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'document.dart';
import 'ops.dart';
import 'render.dart';
import 'validate.dart';
import 'chrome.dart';
import 'video_poster.dart';

const _kPrimary = Color(0xFFF10EA0);
const _kSecondary = Color(0xFFE95214);

/// Drop-in BLOB composition editor. Picks from gallery when no [sourceAsset].
class BlobEditor extends StatefulWidget {
  const BlobEditor({
    super.key,
    this.sourceAsset,
    this.document,
    this.primary = _kPrimary,
    this.onPrimary = Colors.white,
    this.secondary = _kSecondary,
    this.onSecondary = Colors.white,
    this.blocky = false,
    this.themeMode = BlobThemeMode.system,
    this.onRemoveBackground,
    required this.onExport,
    this.onCancel,
  });

  /// Pre-supplied media. If null (and no usable [document] media), opens gallery.
  final ImageProvider? sourceAsset;

  /// Initial composition JSON map (edit / remix).
  final Map<String, dynamic>? document;

  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;

  /// `true` = sharp / square chrome; `false` = Blobby soft radii (default).
  final bool blocky;

  /// light | dark | system (follow platform). Default: system.
  final BlobThemeMode themeMode;

  /// Host/worker subject segmentation → mask PNG bytes, or null to cancel.
  final Future<Uint8List?> Function(String assetId)? onRemoveBackground;

  final void Function(ExportPayload payload) onExport;
  final VoidCallback? onCancel;

  @override
  State<BlobEditor> createState() => _BlobEditorState();
}

class _BlobEditorState extends State<BlobEditor> {
  CompositionDocument? _doc;
  /// Bottom previews: only update when a gesture/tool commit finishes.
  CompositionDocument? _previewDoc;
  /// Live canvas doc — updated during gestures without rebuilding previews.
  final ValueNotifier<CompositionDocument?> _liveDoc = ValueNotifier(null);
  final List<CompositionDocument> _past = [];
  final List<CompositionDocument> _future = [];
  final Map<String, ui.Image> _images = {};
  /// Local filesystem paths for video assets (frame extract on scrub).
  final Map<String, String> _videoPaths = {};
  /// Decoded GIF frame lists keyed by asset id.
  final Map<String, List<ui.Image>> _gifFrames = {};
  final Map<String, List<int>> _gifDelays = {};
  String _assetId = 'local_0';
  String? _selectedId;
  bool _exporting = false;
  bool _picking = false;
  double _playheadMs = 0;
  bool _playing = false;
  Timer? _playTimer;
  Timer? _scrubDebounce;
  int _scrubToken = 0;
  /// Bumps when scrub frame bitmap changes — stage listens without full rebuild.
  final ValueNotifier<int> _frameTick = ValueNotifier(0);
  final ValueNotifier<double> _playheadTick = ValueNotifier(0);
  String? _brushMode; // 'add' | 'remove'
  bool _removingBg = false;
  Offset? _lastFocal;
  double _baseScale = 1;
  double _baseRotation = 0;
  /// Snapshot at gesture start for undo coalescing.
  CompositionDocument? _gestureStart;

  /// Outer / panel chrome (not buttons).
  BorderRadius get _radius =>
      widget.blocky ? BorderRadius.zero : BorderRadius.circular(12);
  /// Buttons / chips only.
  BorderRadius get _pill =>
      widget.blocky ? BorderRadius.zero : BorderRadius.circular(999);

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _scrubDebounce?.cancel();
    _frameTick.dispose();
    _playheadTick.dispose();
    unawaited(releaseVideoPoster());
    _liveDoc.dispose();
    super.dispose();
  }

  void _setDoc(CompositionDocument doc, {bool preview = true}) {
    _doc = doc;
    _liveDoc.value = doc;
    if (preview) _previewDoc = doc;
  }

  Future<void> _boot() async {
    if (widget.document != null) {
      final doc = validateDocument(widget.document!);
      if (widget.sourceAsset != null) {
        final image = await _decodeProvider(widget.sourceAsset!);
        final media = doc.objects.whereType<MediaObject>().isEmpty
            ? null
            : doc.objects.whereType<MediaObject>().first;
        if (media != null) _assetId = media.assetId;
        if (!mounted) return;
        setState(() {
          _images[_assetId] = image;
          _setDoc(doc);
          _selectedId = doc.objects.isNotEmpty ? doc.objects.first.id : null;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _setDoc(doc);
        _selectedId = doc.objects.isNotEmpty ? doc.objects.first.id : null;
      });
      return;
    }

    if (widget.sourceAsset != null) {
      await _applyImage(await _decodeProvider(widget.sourceAsset!));
      return;
    }

    await _pickGallery();
  }

  Future<ui.Image> _decodeProvider(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      completer.complete(info.image);
    }, onError: (e, s) {
      stream.removeListener(listener);
      completer.completeError(e, s);
    });
    stream.addListener(listener);
    return completer.future;
  }

  Future<void> _applyImage(
    ui.Image image, {
    MediaKind kind = MediaKind.image,
    double? durationMs,
    String? videoPath,
    Uint8List? gifBytes,
  }) async {
    _assetId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    var dur = kind == MediaKind.image
        ? 0.0
        : (durationMs ?? 0).clamp(0, maxDurationMs).toDouble();

    if (kind == MediaKind.gif && gifBytes != null) {
      final decoded = await decodeGifFrames(gifBytes);
      if (decoded.frames.isNotEmpty) {
        _gifFrames
          ..clear()
          ..[_assetId] = decoded.frames;
        _gifDelays
          ..clear()
          ..[_assetId] = decoded.delaysMs;
        image = decoded.frames.first;
        if (dur <= 0) dur = decoded.totalMs;
      }
    }

    final doc = createFromSource(
      _assetId,
      image.width.toDouble(),
      image.height.toDouble(),
      kind: kind,
      durationMs: dur,
    );
    if (!mounted) return;
    setState(() {
      _images
        ..clear()
        ..[_assetId] = image;
      _videoPaths.clear();
      if (videoPath != null) _videoPaths[_assetId] = videoPath;
      if (kind != MediaKind.gif) {
        _gifFrames.clear();
        _gifDelays.clear();
      }
      _setDoc(doc);
      _selectedId = doc.objects.first.id;
      _playheadMs = 0;
      _playing = false;
      _playTimer?.cancel();
      _past.clear();
      _future.clear();
    });
    await _syncFrameAtPlayhead();
  }

  Future<ui.Image> _posterFromVideoPath(String path, {double timeMs = 0}) =>
      videoPosterImage(path, timeMs: timeMs);

  /// Map composition playhead → update primary media bitmap (video/gif).
  Future<void> _syncFrameAtPlayhead({bool accurate = true}) async {
    final doc = _doc;
    if (doc == null || doc.durationMs <= 0) return;
    final primary = doc.objects.whereType<MediaObject>();
    if (primary.isEmpty) return;
    final media = primary.first;
    final token = ++_scrubToken;
    final t = _playheadMs.clamp(0.0, doc.durationMs).toDouble();

    if (media.kind == MediaKind.video) {
      final path = _videoPaths[media.assetId];
      if (path == null) return;
      final sourceT = (mapCompToSource(media.keep, t) ?? t).toDouble();
      final frame = await videoPosterImage(
        path,
        timeMs: sourceT,
        maxWidth: kScrubMaxWidth,
        accurate: accurate,
      );
      if (!mounted || token != _scrubToken) return;
      _images[media.assetId] = frame;
      _frameTick.value++;
      return;
    }

    if (media.kind == MediaKind.gif) {
      final frames = _gifFrames[media.assetId];
      final delays = _gifDelays[media.assetId];
      if (frames == null || delays == null || frames.isEmpty) return;
      final sourceT = (mapCompToSource(media.keep, t) ?? t).toDouble();
      final frame = gifFrameAt(frames, delays, sourceT);
      if (!mounted || token != _scrubToken) return;
      _images[media.assetId] = frame;
      _frameTick.value++;
    }
  }

  void _setPlayhead(double ms, {bool syncFrame = true, bool immediate = false, bool accurate = true}) {
    final doc = _doc;
    final max = doc?.durationMs ?? 0;
    final next = ms.clamp(0, max > 0 ? max : 0).toDouble();
    _playheadMs = next;
    _playheadTick.value = next;
    if (!syncFrame) return;
    if (immediate) {
      unawaited(_syncFrameAtPlayhead(accurate: accurate));
      return;
    }
    // During drag: lighter debounce, still accurate seek
    _scrubDebounce?.cancel();
    _scrubDebounce = Timer(const Duration(milliseconds: 40), () {
      unawaited(_syncFrameAtPlayhead(accurate: accurate));
    });
  }

  void _togglePlay() {
    final doc = _doc;
    if (doc == null || doc.durationMs <= 0) return;
    if (_playing) {
      _playTimer?.cancel();
      setState(() => _playing = false);
      // Snap to precise frame when pausing
      unawaited(_syncFrameAtPlayhead(accurate: true));
      return;
    }
    setState(() => _playing = true);
    // Play uses coarse keyframe path for smoothness
    const step = kPlayBucketMs;
    _playTimer = Timer.periodic(const Duration(milliseconds: step), (_) {
      final d = _doc;
      if (d == null) return;
      final next = _playheadMs + step;
      if (next >= d.durationMs) {
        _playTimer?.cancel();
        _setPlayhead(0, immediate: true, accurate: true);
        setState(() => _playing = false);
        return;
      }
      _setPlayhead(next, immediate: true, accurate: false);
    });
  }

  Future<void> _pickGallery() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await ImagePicker().pickMedia();
      if (file == null) {
        widget.onCancel?.call();
        return;
      }
      final path = file.path.toLowerCase();
      final mime = file.mimeType ?? '';
      var kind = MediaKind.image;
      if (mime.contains('video') ||
          path.endsWith('.mp4') ||
          path.endsWith('.webm') ||
          path.endsWith('.mov') ||
          path.endsWith('.mkv')) {
        kind = MediaKind.video;
      } else if (mime.contains('gif') || path.endsWith('.gif')) {
        kind = MediaKind.gif;
      }

      if (kind == MediaKind.video) {
        final dur = await videoDurationMs(file.path);
        final poster = await _posterFromVideoPath(file.path);
        await _applyImage(
          poster,
          kind: kind,
          durationMs: dur > 0 ? dur : 3000,
          videoPath: file.path,
        );
      } else if (kind == MediaKind.gif) {
        final bytes = await file.readAsBytes();
        await _applyImage(
          await _decodeProvider(MemoryImage(bytes)),
          kind: kind,
          gifBytes: bytes,
        );
      } else {
        final bytes = await file.readAsBytes();
        await _applyImage(
          await _decodeProvider(MemoryImage(bytes)),
          kind: kind,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickOverlay() async {
    final doc = _doc;
    if (doc == null) return;
    final hasVideo =
        doc.objects.any((o) => o is MediaObject && o.kind == MediaKind.video);
    if (hasVideo) return;

    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || _doc == null) return;
    final path = file.path.toLowerCase();
    final mime = file.mimeType ?? '';
    var kind = MediaKind.image;
    if (mime.contains('gif') || path.endsWith('.gif')) {
      kind = MediaKind.gif;
    }

    final id = newObjectId('ov');
    late final ui.Image image;
    if (kind == MediaKind.gif) {
      final bytes = await file.readAsBytes();
      final decoded = await decodeGifFrames(bytes);
      if (decoded.frames.isNotEmpty) {
        _gifFrames[id] = decoded.frames;
        _gifDelays[id] = decoded.delaysMs;
        image = decoded.frames.first;
      } else {
        image = await _decodeProvider(MemoryImage(bytes));
      }
    } else {
      image = await _decodeProvider(MemoryImage(await file.readAsBytes()));
    }
    setState(() => _images[id] = image);
    try {
      _push(
        addMedia(
          _doc!,
          assetId: id,
          kind: kind,
          naturalWidth: image.width.toDouble(),
          naturalHeight: image.height.toDouble(),
        ),
      );
    } catch (_) {
      /* overlay rejected */
    }
  }

  Future<void> _removeBackground(MediaObject media) async {
    final cb = widget.onRemoveBackground;
    if (cb == null || _doc == null) return;
    setState(() => _removingBg = true);
    try {
      final bytes = await cb(media.assetId);
      if (bytes == null || !mounted) return;
      final maskId = media.maskAssetId ?? newObjectId('mask');
      final image = await _decodeProvider(MemoryImage(bytes));
      setState(() => _images[maskId] = image);
      _push(applyMask(_doc!, media.id, maskId));
    } finally {
      if (mounted) setState(() => _removingBg = false);
    }
  }

  /// ponytail: soft-circle brush into mask bitmap (images only).
  Future<void> _paintBrush(MediaObject media, Offset canvasPt, String mode) async {
    final src = _images[media.assetId];
    if (src == null || _doc == null) return;
    final nw = src.width;
    final nh = src.height;
    final maskId = media.maskAssetId ?? newObjectId('mask');
    final existing = _images[maskId];

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (existing != null) {
      canvas.drawImage(existing, Offset.zero, Paint());
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, nw.toDouble(), nh.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }
    final lx = (canvasPt.dx - media.transform.x) / media.transform.scaleX + nw / 2;
    final ly = (canvasPt.dy - media.transform.y) / media.transform.scaleY + nh / 2;
    final r = 28 / math.max(media.transform.scaleX, 0.01);
    canvas.drawCircle(
      Offset(lx, ly),
      r,
      Paint()
        ..blendMode = mode == 'add' ? BlendMode.srcOver : BlendMode.clear
        ..color = const Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    final painted = await picture.toImage(nw, nh);
    setState(() => _images[maskId] = painted);
    _live(applyMask(_doc!, media.id, maskId));
  }

  void _push(CompositionDocument next, {bool preview = true}) {
    if (_doc != null) _past.add(_doc!);
    _future.clear();
    setState(() => _setDoc(next, preview: preview));
  }

  /// Live edit (slider / typing) — canvas only, previews stay frozen.
  void _live(CompositionDocument next) {
    setState(() => _setDoc(next, preview: false));
  }

  void _commitPreview() {
    setState(() => _previewDoc = _doc);
  }

  void _undo() {
    if (_past.isEmpty || _doc == null) return;
    _future.insert(0, _doc!);
    setState(() => _setDoc(_past.removeLast()));
  }

  void _redo() {
    if (_future.isEmpty) return;
    if (_doc != null) _past.add(_doc!);
    setState(() => _setDoc(_future.removeAt(0)));
  }

  Future<void> _doExport() async {
    final doc = _doc;
    if (doc == null || _images.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final payload = await renderExports(doc, (id) => _images[id]);
      widget.onExport(payload);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome = BlobChromeColors.resolve(
      widget.themeMode,
      MediaQuery.platformBrightnessOf(context),
    );
    final doc = _doc;
    if (doc == null || _images.isEmpty) {
      return BlobGlass(
        colors: chrome,
        borderRadius: _radius,
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 280,
          child: DefaultTextStyle(
            style: TextStyle(color: chrome.foreground),
            child: Center(
              child: _picking
                  ? CircularProgressIndicator(color: widget.primary)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Pick an image, GIF, or video to start',
                          style: TextStyle(color: chrome.muted),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          style: _filledStyle(),
                          onPressed: _pickGallery,
                          child: const Text('Choose media'),
                        ),
                        if (widget.onCancel != null) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: chrome.foreground,
                            ),
                            onPressed: widget.onCancel,
                            child: const Text('Cancel'),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      );
    }

    final bgColor = doc.canvas.background == 'transparent'
        ? (chrome == BlobChromeColors.dark
            ? const Color(0x14FFFFFF)
            : const Color(0x14000000))
        : Color(
            0xFF000000 |
                int.parse(doc.canvas.background.substring(1), radix: 16),
          );

    return BlobGlass(
      colors: chrome,
      borderRadius: _radius,
      padding: const EdgeInsets.all(12),
      child: DefaultTextStyle(
        style: TextStyle(color: chrome.foreground),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Wide multi-column only when height is bounded (Expanded host).
            // Portrait tablet in a ListView is wide but unbounded → IntrinsicHeight
            // + nested LayoutBuilder asserts during layout.
            final wide =
                constraints.maxWidth >= 720 && constraints.hasBoundedHeight;
            final double stageSide;
            if (wide) {
              final centerW = constraints.maxWidth - 168 - 140 - 24;
              stageSide = math.min(
                560,
                math.min(centerW.clamp(120, 560), constraints.maxHeight),
              );
            } else {
              stageSide = math.min(
                constraints.maxWidth.isFinite ? constraints.maxWidth : 320,
                560,
              );
            }
            final stage = _buildStage(doc, bgColor, side: stageSide);
            final controls = _buildControls(doc, chrome);
            final previews = _PreviewRow(
              doc: _previewDoc ?? doc,
              images: Map.of(_images),
              axis: wide ? Axis.vertical : Axis.horizontal,
            );
            final toolbar = _buildToolbar(doc, chrome);

            if (!wide) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  stage,
                  if (controls != null) ...[
                    const SizedBox(height: 8),
                    controls,
                  ],
                  const SizedBox(height: 8),
                  previews,
                  const SizedBox(height: 8),
                  toolbar,
                ],
              );
            }

            final row = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 168,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (controls != null) ...[
                          controls,
                          const SizedBox(height: 8),
                        ],
                        toolbar,
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: stageSide,
                      height: stageSide,
                      child: stage,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  child: SingleChildScrollView(child: previews),
                ),
              ],
            );

            return SizedBox(height: constraints.maxHeight, child: row);
          },
        ),
      ),
    );
  }

  Widget _buildStage(CompositionDocument doc, Color bgColor, {required double side}) {
    final viewScale = side / canvasSize;
    return SizedBox(
      width: side,
      height: side,
      child: ClipRRect(
        borderRadius:
            widget.blocky ? BorderRadius.zero : BorderRadius.circular(8),
        child: ColoredBox(
          color: bgColor,
          child: GestureDetector(
            onScaleStart: (d) {
              final live = _liveDoc.value ?? doc;
              if (_brushMode != null) {
                final sel = _selectedObject(live);
                if (sel is MediaObject && sel.kind == MediaKind.image) {
                  final canvasPt = Offset(
                    d.localFocalPoint.dx / viewScale,
                    d.localFocalPoint.dy / viewScale,
                  );
                  unawaited(_paintBrush(sel, canvasPt, _brushMode!));
                }
                return;
              }
              _gestureStart = live;
              _lastFocal = d.localFocalPoint;
              // Prefer existing selection; else hit-test; else first media.
              var id = _selectedId;
              id ??= _hitTest(live, d.localFocalPoint, viewScale);
              if (id == null) {
                final media = live.objects.whereType<MediaObject>();
                if (media.isNotEmpty) id = media.first.id;
              }
              _selectedId = id;
              CompositionObject? obj;
              for (final o in live.objects) {
                if (o.id == id) obj = o;
              }
              if (obj != null) {
                _baseScale = obj.transform.scaleX;
                _baseRotation = obj.transform.rotation;
              }
            },
            onScaleUpdate: (d) {
              if (_brushMode != null) {
                final live = _liveDoc.value ?? doc;
                final sel = _selectedObject(live);
                if (sel is MediaObject && sel.kind == MediaKind.image) {
                  final canvasPt = Offset(
                    d.localFocalPoint.dx / viewScale,
                    d.localFocalPoint.dy / viewScale,
                  );
                  unawaited(_paintBrush(sel, canvasPt, _brushMode!));
                }
                return;
              }
              final id = _selectedId;
              final current = _liveDoc.value ?? _doc;
              if (id == null || _lastFocal == null || current == null) {
                return;
              }
              final dx =
                  (d.localFocalPoint.dx - _lastFocal!.dx) / viewScale;
              final dy =
                  (d.localFocalPoint.dy - _lastFocal!.dy) / viewScale;
              _lastFocal = d.localFocalPoint;
              CompositionObject? obj;
              for (final o in current.objects) {
                if (o.id == id) obj = o;
              }
              if (obj == null) return;
              // Canvas-only update — no setState, no preview rebuild.
              final next = updateTransform(
                current,
                id,
                x: obj.transform.x + dx,
                y: obj.transform.y + dy,
                scaleX: _baseScale * d.scale,
                scaleY: _baseScale * d.scale,
                rotation:
                    _baseRotation + d.rotation * 180 / 3.1415926535,
              );
              _doc = next;
              _liveDoc.value = next;
            },
            onScaleEnd: (_) {
              if (_brushMode != null) {
                _commitPreview();
                return;
              }
              if (_gestureStart != null && _doc != null) {
                _past.add(_gestureStart!);
                _future.clear();
                _gestureStart = null;
              }
              // Commit previews once the gesture finishes.
              setState(() => _previewDoc = _doc);
            },
            child: ListenableBuilder(
              listenable: Listenable.merge([_liveDoc, _frameTick, _playheadTick]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _CompositionPainter(
                    doc: _liveDoc.value ?? doc,
                    images: Map.of(_images),
                    playheadMs: _playheadMs,
                  ),
                  size: Size(side, side),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildControls(CompositionDocument doc, BlobChromeColors chrome) {
    final sel = _selectedObject(doc);
    final medias = doc.objects.whereType<MediaObject>();
    final primaryMedia = medias.isEmpty ? null : medias.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (doc.durationMs > 0) ...[
          ValueListenableBuilder<double>(
            valueListenable: _playheadTick,
            builder: (context, playhead, _) {
              return Row(
                children: [
                  IconButton(
                    tooltip: _playing ? 'Pause' : 'Play',
                    iconSize: 28,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      foregroundColor: chrome.foreground,
                    ),
                    onPressed: _togglePlay,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  ),
                  Expanded(
                    child: Text(
                      'Timeline ${(playhead / 1000).toStringAsFixed(1)}s / ${(doc.durationMs / 1000).toStringAsFixed(1)}s',
                      style: TextStyle(fontSize: 12, color: chrome.muted),
                    ),
                  ),
                ],
              );
            },
          ),
          ValueListenableBuilder<double>(
            valueListenable: _playheadTick,
            builder: (context, playhead, _) {
              return Slider(
                min: 0,
                max: doc.durationMs,
                value: playhead.clamp(0, doc.durationMs),
                onChanged: (v) {
                  if (_playing) {
                    _playTimer?.cancel();
                    setState(() => _playing = false);
                  }
                  _setPlayhead(v);
                },
                onChangeEnd: (v) => _setPlayhead(v, immediate: true),
              );
            },
          ),
          Wrap(
            spacing: 6,
            children: [
              _chip(
                'Trim end→playhead',
                primaryMedia == null
                    ? null
                    : () {
                        final keep = primaryMedia.keep ??
                            TimeRange(startMs: 0, endMs: doc.durationMs);
                        final end = math.max(
                          keep.startMs + 100,
                          keep.startMs + _playheadMs,
                        );
                        _push(syncDurationFromPrimary(
                          setTrim(doc, primaryMedia.id, keep.startMs, end),
                        ));
                      },
                chrome,
              ),
              _chip(
                'Trim start→playhead',
                primaryMedia == null
                    ? null
                    : () {
                        final keep = primaryMedia.keep ??
                            TimeRange(startMs: 0, endMs: doc.durationMs);
                        final start = keep.startMs + _playheadMs;
                        _push(syncDurationFromPrimary(
                          setTrim(
                            doc,
                            primaryMedia.id,
                            start,
                            math.max(start + 100, keep.endMs),
                          ),
                        ));
                      },
                chrome,
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        if (sel != null) ...[
          _TransformInspector(
            obj: sel,
            chrome: chrome,
            panelRadius: _radius,
            onChange: (scale, rotation) {
              final current = _doc ?? doc;
              final o = _selectedObject(current);
              if (o == null) return;
              _live(
                updateTransform(
                  current,
                  o.id,
                  scaleX: scale,
                  scaleY: scale,
                  rotation: rotation,
                ),
              );
            },
            onCommit: () {
              if (_doc != null) {
                _past.add(_previewDoc ?? _doc!);
                _future.clear();
              }
              _commitPreview();
            },
          ),
          if (sel is TextObject) ...[
            const SizedBox(height: 8),
            _TextInspector(
              obj: sel,
              chrome: chrome,
              panelRadius: _radius,
              pill: _pill,
              onChange: (patch) {
                final t = _selectedText(_doc ?? doc);
                if (t == null) return;
                _live(
                  updateText(
                    _doc ?? doc,
                    t.id,
                    text: patch.text,
                    fontSize: patch.fontSize,
                    style: patch.style,
                  ),
                );
              },
              onCommit: () {
                if (_doc != null) {
                  _past.add(_previewDoc ?? _doc!);
                  _future.clear();
                }
                _commitPreview();
              },
            ),
          ],
          if (sel is MediaObject) ...[
            const SizedBox(height: 8),
            BlobGlass(
              colors: chrome,
              borderRadius: _radius,
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Crop', style: TextStyle(fontSize: 12, color: chrome.muted)),
                  ..._cropSliders(doc, sel, chrome),
                  if (sel.kind == MediaKind.image) ...[
                    const SizedBox(height: 6),
                    Text('Cutout', style: TextStyle(fontSize: 12, color: chrome.muted)),
                    Wrap(
                      spacing: 6,
                      children: [
                        _chip(
                          _removingBg ? 'Removing…' : 'Remove BG',
                          (_removingBg || widget.onRemoveBackground == null)
                              ? null
                              : () => unawaited(_removeBackground(sel)),
                          chrome,
                        ),
                        _chip(
                          sel.outline == null ? 'White border' : 'Clear border',
                          () => _push(setOutline(
                            doc,
                            sel.id,
                            sel.outline == null
                                ? const OutlineStyle(color: '#ffffff', width: 8)
                                : null,
                          )),
                          chrome,
                        ),
                        _chip(
                          _brushMode == 'add' ? 'Brush+ ON' : 'Brush add',
                          () => setState(() =>
                              _brushMode = _brushMode == 'add' ? null : 'add'),
                          chrome,
                        ),
                        _chip(
                          _brushMode == 'remove' ? 'Brush− ON' : 'Brush remove',
                          () => setState(() => _brushMode =
                              _brushMode == 'remove' ? null : 'remove'),
                          chrome,
                        ),
                        _chip(
                          'Clear mask',
                          () {
                            setState(() => _brushMode = null);
                            _push(applyMask(doc, sel.id, null));
                          },
                          chrome,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
        if (doc.objects.whereType<MediaObject>().any((m) => m.kind == MediaKind.video)) ...[
          const SizedBox(height: 8),
          BlobGlass(
            colors: chrome,
            borderRadius: _radius,
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Remove original sound',
                    style: TextStyle(color: chrome.foreground, fontSize: 13),
                  ),
                ),
                Switch(
                  value: doc.audio?.muteSource ?? true,
                  onChanged: (v) => _push(setMuteSource(doc, v)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _cropSliders(
    CompositionDocument doc,
    MediaObject sel,
    BlobChromeColors chrome,
  ) {
    final c = sel.crop;
    if (c == null) return const [];
    final img = _images[sel.assetId];
    final maxW = (img?.width ?? c.width + c.x).toDouble();
    final maxH = (img?.height ?? c.height + c.y).toDouble();
    Widget row(String label, double value, double max, void Function(double) onChange) {
      return Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: TextStyle(fontSize: 10, color: chrome.muted)),
          ),
          Expanded(
            child: Slider(
              min: 0,
              max: math.max(max, 1),
              value: value.clamp(0, math.max(max, 1)),
              onChanged: onChange,
              onChangeEnd: (_) => _commitPreview(),
            ),
          ),
        ],
      );
    }
    return [
      row('X', c.x, maxW, (v) {
        _live(updateCrop(
          doc,
          sel.id,
          c.copyWith(x: v, width: math.min(c.width, maxW - v)),
        ));
      }),
      row('Y', c.y, maxH, (v) {
        _live(updateCrop(
          doc,
          sel.id,
          c.copyWith(y: v, height: math.min(c.height, maxH - v)),
        ));
      }),
      row('W', c.width, maxW - c.x, (v) {
        _live(updateCrop(doc, sel.id, c.copyWith(width: math.max(1, v))));
      }),
      row('H', c.height, maxH - c.y, (v) {
        _live(updateCrop(doc, sel.id, c.copyWith(height: math.max(1, v))));
      }),
    ];
  }

  Widget _buildToolbar(CompositionDocument doc, BlobChromeColors chrome) {
    final isVideo =
        doc.objects.any((o) => o is MediaObject && o.kind == MediaKind.video);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _chip('Undo', _past.isNotEmpty ? _undo : null, chrome),
        _chip('Redo', _future.isNotEmpty ? _redo : null, chrome),
        _chip('Text', _addText, chrome),
        if (!isVideo) _chip('Overlay', _pickOverlay, chrome),
        if (!isVideo) ...[
          _chip(
            'Clear bg',
            () => _push(setBackground(doc, 'transparent')),
            chrome,
          ),
          _BgButton(
            current: doc.canvas.background,
            chrome: chrome,
            pill: _pill,
            onPick: (hex) => _push(setBackground(doc, hex)),
          ),
        ],
        if (widget.onCancel != null)
          _chip('Cancel', widget.onCancel, chrome, ghost: true),
        FilledButton(
          style: _filledStyle(),
          onPressed: _exporting ? null : _doExport,
          child: Text(_exporting ? 'Export…' : 'Export'),
        ),
      ],
    );
  }

  CompositionObject? _selectedObject(CompositionDocument doc) {
    final id = _selectedId;
    if (id == null) return null;
    for (final o in doc.objects) {
      if (o.id == id) return o;
    }
    return null;
  }

  TextObject? _selectedText(CompositionDocument doc) {
    final o = _selectedObject(doc);
    return o is TextObject ? o : null;
  }

  void _addText() {
    final current = _doc;
    if (current == null) return;
    final next = addText(current);
    final id = next.objects.last.id;
    _push(next);
    setState(() => _selectedId = id);
  }

  /// Rough hit-test in view coords → object id (topmost wins).
  String? _hitTest(CompositionDocument doc, Offset local, double viewScale) {
    final x = local.dx / viewScale;
    final y = local.dy / viewScale;
    for (final o in doc.objects.reversed) {
      final t = o.transform;
      final dx = x - t.x;
      final dy = y - t.y;
      if (o is MediaObject) {
        final w = (o.crop?.width ?? 200) * t.scaleX;
        final h = (o.crop?.height ?? 200) * t.scaleY;
        if (dx.abs() <= w / 2 && dy.abs() <= h / 2) return o.id;
      } else if (o is TextObject) {
        final w = o.fontSize * o.text.length * 0.55 * t.scaleX;
        final h = o.fontSize * 1.2 * t.scaleY;
        if (dx.abs() <= w / 2 && dy.abs() <= h / 2) return o.id;
      }
    }
    return null;
  }

  ButtonStyle _filledStyle() => FilledButton.styleFrom(
        backgroundColor: widget.primary,
        foregroundColor: widget.onPrimary,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: _pill),
      );

  Widget _chip(
    String label,
    VoidCallback? onPressed,
    BlobChromeColors chrome, {
    bool ghost = false,
  }) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: chrome.foreground,
        backgroundColor: ghost ? null : chrome.btn,
        shape: RoundedRectangleBorder(
          borderRadius: _pill,
          side: BorderSide(color: chrome.btnBorder),
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

class _CompositionPainter extends CustomPainter {
  _CompositionPainter({
    required this.doc,
    required this.images,
    this.playheadMs = 0,
  });

  final CompositionDocument doc;
  final Map<String, ui.Image> images;
  final double playheadMs;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / canvasSize;
    canvas.scale(s, s);
    paintComposition(
      canvas,
      doc,
      (id) => images[id],
      tMs: playheadMs,
    );
  }

  @override
  bool shouldRepaint(covariant _CompositionPainter old) =>
      old.doc != doc || old.images != images || old.playheadMs != playheadMs;
}

class _PreviewRow extends StatefulWidget {
  const _PreviewRow({
    required this.doc,
    required this.images,
    this.axis = Axis.horizontal,
  });

  final CompositionDocument doc;
  final Map<String, ui.Image> images;
  final Axis axis;

  @override
  State<_PreviewRow> createState() => _PreviewRowState();
}

class _PreviewRowState extends State<_PreviewRow> {
  Uint8List? chat;
  Uint8List? thumb;
  Uint8List? full;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant _PreviewRow old) {
    super.didUpdateWidget(old);
    if (old.doc != widget.doc) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final p = await renderExports(
      widget.doc,
      (id) => widget.images[id],
    );
    if (!mounted) return;
    setState(() {
      chat = p.chat;
      thumb = p.thumbnail;
      full = p.full;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    Widget cell(String label, Uint8List? bytes, int size) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Container(
            width: size.clamp(0, vertical ? 112 : 96).toDouble(),
            height: size.clamp(0, vertical ? 112 : 96).toDouble(),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.black12),
            ),
            child: bytes == null
                ? const SizedBox.shrink()
                : Image.memory(bytes, fit: BoxFit.contain),
          ),
        ],
      );
    }

    final kids = [
      cell('Chat 128', chat, vertical ? 48 : 64),
      cell('Thumb 256', thumb, vertical ? 72 : 80),
      cell('Full 1024', full, vertical ? 96 : 96),
    ];

    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < kids.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            kids[i],
          ],
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: kids,
    );
  }
}

class _TransformInspector extends StatelessWidget {
  const _TransformInspector({
    required this.obj,
    required this.chrome,
    required this.panelRadius,
    required this.onChange,
    required this.onCommit,
  });

  final CompositionObject obj;
  final BlobChromeColors chrome;
  final BorderRadius panelRadius;
  final void Function(double scale, double rotation) onChange;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final scale = obj.transform.scaleX;
    final rotation = ((obj.transform.rotation % 360) + 360) % 360;
    return BlobGlass(
      colors: chrome,
      borderRadius: panelRadius,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Scale ${scale.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 12, color: chrome.muted),
          ),
          Slider(
            min: 0.05,
            max: 10,
            activeColor: const Color(0xFFF10EA0),
            value: scale.clamp(0.05, 10),
            onChanged: (v) => onChange(v, obj.transform.rotation),
            onChangeEnd: (_) => onCommit(),
          ),
          Text(
            'Rotate ${rotation.round()}°',
            style: TextStyle(fontSize: 12, color: chrome.muted),
          ),
          Slider(
            min: 0,
            max: 360,
            activeColor: const Color(0xFFF10EA0),
            value: rotation,
            onChanged: (v) => onChange(obj.transform.scaleX, v),
            onChangeEnd: (_) => onCommit(),
          ),
        ],
      ),
    );
  }
}

class _TextPatch {
  const _TextPatch({this.text, this.fontSize, this.style});
  final String? text;
  final double? fontSize;
  final ObjectTextStyle? style;
}

class _TextInspector extends StatefulWidget {
  const _TextInspector({
    required this.obj,
    required this.chrome,
    required this.panelRadius,
    required this.pill,
    required this.onChange,
    required this.onCommit,
  });

  final TextObject obj;
  final BlobChromeColors chrome;
  final BorderRadius panelRadius;
  final BorderRadius pill;
  final void Function(_TextPatch patch) onChange;
  final VoidCallback onCommit;

  @override
  State<_TextInspector> createState() => _TextInspectorState();
}

class _TextInspectorState extends State<_TextInspector> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.obj.text);
  }

  @override
  void didUpdateWidget(covariant _TextInspector old) {
    super.didUpdateWidget(old);
    if (old.obj.id != widget.obj.id || old.obj.text != widget.obj.text) {
      if (_ctrl.text != widget.obj.text) {
        _ctrl.text = widget.obj.text;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _parse(String hex, Color fallback) {
    if (hex.length == 7 && hex.startsWith('#')) {
      return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final obj = widget.obj;
    return BlobGlass(
      colors: widget.chrome,
      borderRadius: widget.panelRadius,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            style: GoogleFonts.anton(
              fontSize: 20,
              color: widget.chrome.foreground,
            ),
            cursorColor: widget.chrome.foreground,
            decoration: InputDecoration(
              labelText: 'Text',
              labelStyle: TextStyle(color: widget.chrome.muted),
              isDense: true,
              border: OutlineInputBorder(borderRadius: widget.pill),
              enabledBorder: OutlineInputBorder(
                borderRadius: widget.pill,
                borderSide: BorderSide(color: widget.chrome.btnBorder),
              ),
            ),
            onChanged: (v) => widget.onChange(_TextPatch(text: v)),
            onEditingComplete: widget.onCommit,
            onSubmitted: (_) => widget.onCommit(),
          ),
          const SizedBox(height: 8),
          Text(
            'Size ${obj.fontSize.round()}',
            style: TextStyle(fontSize: 12, color: widget.chrome.muted),
          ),
          Slider(
            min: 24,
            max: 220,
            activeColor: const Color(0xFFF10EA0),
            value: obj.fontSize.clamp(24, 220),
            onChanged: (v) => widget.onChange(_TextPatch(fontSize: v)),
            onChangeEnd: (_) => widget.onCommit(),
          ),
          Row(
            children: [
              Text('Fill', style: TextStyle(color: widget.chrome.muted)),
              const SizedBox(width: 8),
              for (final hex in const [
                '#ffffff',
                '#000000',
                '#f10ea0',
                '#e95214',
                '#ffff00',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      widget.onChange(
                        _TextPatch(style: obj.style.copyWith(fill: hex)),
                      );
                      widget.onCommit();
                    },
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: _parse(hex, Colors.white),
                      child: obj.style.fill.toLowerCase() == hex
                          ? const Icon(Icons.check, size: 14, color: Colors.blue)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Outline', style: TextStyle(color: widget.chrome.muted)),
              const SizedBox(width: 8),
              for (final hex in const [
                '#000000',
                '#ffffff',
                '#f10ea0',
                '#e95214',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: () {
                      widget.onChange(
                        _TextPatch(style: obj.style.copyWith(stroke: hex)),
                      );
                      widget.onCommit();
                    },
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: _parse(hex, Colors.black),
                      child: obj.style.stroke.toLowerCase() == hex
                          ? const Icon(Icons.check, size: 14, color: Colors.blue)
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          Text(
            'Outline ${obj.style.strokeWidth.round()}',
            style: TextStyle(fontSize: 12, color: widget.chrome.muted),
          ),
          Slider(
            min: 0,
            max: 24,
            activeColor: const Color(0xFFF10EA0),
            value: obj.style.strokeWidth.clamp(0, 24),
            onChanged: (v) => widget.onChange(
              _TextPatch(style: obj.style.copyWith(strokeWidth: v)),
            ),
            onChangeEnd: (_) => widget.onCommit(),
          ),
        ],
      ),
    );
  }
}

class _BgButton extends StatelessWidget {
  const _BgButton({
    required this.current,
    required this.chrome,
    required this.pill,
    required this.onPick,
  });

  final String current;
  final BlobChromeColors chrome;
  final BorderRadius pill;
  final void Function(String hex) onPick;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: chrome.foreground,
        backgroundColor: chrome.btn,
        shape: RoundedRectangleBorder(
          borderRadius: pill,
          side: BorderSide(color: chrome.btnBorder),
        ),
      ),
      onPressed: () async {
        // ponytail: fixed palette instead of full color picker dependency
        const presets = ['#ffffff', '#000000', '#f10ea0', '#e95214', '#3b82f6'];
        final picked = await showModalBottomSheet<String>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final hex in presets)
                  ListTile(
                    tileColor: Theme.of(ctx).colorScheme.surface,
                    leading: CircleAvatar(
                      backgroundColor: Color(
                        0xFF000000 | int.parse(hex.substring(1), radix: 16),
                      ),
                    ),
                    title: Text(hex),
                    onTap: () => Navigator.pop(ctx, hex),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Text(current == 'transparent' ? 'Bg' : 'Bg $current'),
    );
  }
}
