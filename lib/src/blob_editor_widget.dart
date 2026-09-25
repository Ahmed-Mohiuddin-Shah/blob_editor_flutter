import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

enum _ToolId { transform, crop, cutout, text, canvas }

const _toolTitles = {
  _ToolId.transform: 'Transform',
  _ToolId.crop: 'Crop',
  _ToolId.cutout: 'Cutout',
  _ToolId.text: 'Text',
  _ToolId.canvas: 'Canvas',
};

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
  /// Cutout tool: add | remove | polygon.
  String? _maskMode;
  double _brushSize = 28;
  final List<Offset> _polygonPoints = [];
  Offset? _brushCursor;
  _ToolId? _activeTool = _ToolId.text;
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

  /// Crop-aware soft circle into mask; stage + render share the same mask asset.
  Future<void> _paintBrush(MediaObject media, Offset canvasPt, String mode) async {
    final src = _images[media.assetId];
    if (src == null || _doc == null) return;
    final nw = src.width;
    final nh = src.height;
    final maskId = media.maskAssetId ?? newObjectId('mask');
    final existing = _images[maskId];
    final crop = media.crop;
    final iw = crop?.width ?? nw.toDouble();
    final ih = crop?.height ?? nh.toDouble();
    final sx = crop?.x ?? 0.0;
    final sy = crop?.y ?? 0.0;

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
    final lx =
        (canvasPt.dx - media.transform.x) / math.max(media.transform.scaleX, 0.01) +
            iw / 2 +
            sx;
    final ly =
        (canvasPt.dy - media.transform.y) / math.max(media.transform.scaleY, 0.01) +
            ih / 2 +
            sy;
    final r = _brushSize / math.max(media.transform.scaleX, 0.01);
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

  Future<bool> _applyPolygonMask(MediaObject media, List<Offset> points) async {
    if (points.length < 3 || _doc == null) return false;
    final src = _images[media.assetId];
    if (src == null) return false;
    final nw = src.width;
    final nh = src.height;
    final maskId = media.maskAssetId ?? newObjectId('mask');
    final crop = media.crop;
    final iw = crop?.width ?? nw.toDouble();
    final ih = crop?.height ?? nh.toDouble();
    final sx = crop?.x ?? 0.0;
    final sy = crop?.y ?? 0.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final existing = _images[maskId];
    if (existing != null) {
      canvas.drawImage(existing, Offset.zero, Paint());
    } else {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, nw.toDouble(), nh.toDouble()),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }

    final polyRec = ui.PictureRecorder();
    final polyCanvas = Canvas(polyRec);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final lx =
          (points[i].dx - media.transform.x) / math.max(media.transform.scaleX, 0.01) +
              iw / 2 +
              sx;
      final ly =
          (points[i].dy - media.transform.y) / math.max(media.transform.scaleY, 0.01) +
              ih / 2 +
              sy;
      if (i == 0) {
        path.moveTo(lx, ly);
      } else {
        path.lineTo(lx, ly);
      }
    }
    path.close();
    polyCanvas.drawPath(path, Paint()..color = const Color(0xFFFFFFFF));
    final polyPic = polyRec.endRecording();
    final polyImg = await polyPic.toImage(nw, nh);
    canvas.drawImage(polyImg, Offset.zero, Paint()..blendMode = BlendMode.dstIn);

    final picture = recorder.endRecording();
    final painted = await picture.toImage(nw, nh);
    setState(() => _images[maskId] = painted);
    _live(applyMask(_doc!, media.id, maskId));
    return true;
  }

  void _setMaskMode(String? mode) {
    setState(() {
      _polygonPoints.clear();
      _brushCursor = (mode == 'add' || mode == 'remove')
          ? const Offset(canvasSize / 2, canvasSize / 2)
          : null;
      _maskMode = mode;
    });
  }

  Future<void> _handleApplyMask() async {
    final live = _liveDoc.value ?? _doc;
    if (live == null) return;
    final sel = _selectedObject(live);
    if (sel is MediaObject &&
        sel.kind == MediaKind.image &&
        _maskMode == 'polygon') {
      if (_polygonPoints.length < 3) return;
      final ok = await _applyPolygonMask(sel, List.of(_polygonPoints));
      if (!ok) return;
    }
    setState(() {
      _polygonPoints.clear();
      _maskMode = null;
      _brushCursor = null;
    });
    _commitPreview();
  }

  void _cancelPolygon() {
    setState(() {
      _polygonPoints.clear();
      _maskMode = null;
      _brushCursor = null;
    });
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

  Map<_ToolId, bool> _toolsAvailable(CompositionDocument doc) {
    final sel = _selectedObject(doc);
    final selMedia = sel is MediaObject ? sel : null;
    return {
      _ToolId.transform: sel != null,
      _ToolId.crop: selMedia != null,
      _ToolId.cutout: selMedia?.kind == MediaKind.image,
      _ToolId.text: true,
      _ToolId.canvas: true,
    };
  }

  _ToolId? _resolvedActiveTool(CompositionDocument doc) {
    final avail = _toolsAvailable(doc);
    if (_activeTool != null && avail[_activeTool] == true) return _activeTool;
    final sel = _selectedObject(doc);
    if (sel is TextObject) return _ToolId.text;
    if (sel != null && avail[_ToolId.transform] == true) {
      return _ToolId.transform;
    }
    return _ToolId.text;
  }

  void _selectTool(_ToolId id) {
    setState(() => _activeTool = _activeTool == id ? null : id);
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

    final avail = _toolsAvailable(doc);
    // Collapsed (null) stays collapsed; only remap when active becomes invalid.
    final active = _activeTool == null
        ? null
        : (_activeTool != null && avail[_activeTool] == true
            ? _activeTool
            : _resolvedActiveTool(doc));

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_maskMode == 'polygon') _cancelPolygon();
        },
      },
      child: Focus(
        autofocus: true,
        child: BlobGlass(
          colors: chrome,
          borderRadius: _radius,
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle(
            style: TextStyle(color: chrome.foreground),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Wide multi-column only when height is bounded (Expanded host).
                // Portrait tablet in a ListView is wide but unbounded → stay narrow.
                final wide = constraints.maxWidth >= 720 &&
                    constraints.hasBoundedHeight;
                final double stageSide;
                if (wide) {
                  final centerW = constraints.maxWidth - 260 - 140 - 24;
                  stageSide = math.min(
                    560,
                    math.min(centerW.clamp(120, 560), constraints.maxHeight - 80),
                  );
                } else {
                  stageSide = math.min(
                    constraints.maxWidth.isFinite
                        ? constraints.maxWidth
                        : 320,
                    560,
                  );
                }
                final stage = _buildStage(doc, bgColor, side: stageSide);
                final timeline = _buildTimeline(doc, chrome);
                final panel = _buildToolPanel(doc, chrome, active);
                final nav = _ToolNav(
                  tools: [
                    for (final id in _ToolId.values)
                      if (avail[id] == true)
                        (id: id, label: _toolTitles[id]!),
                  ],
                  active: active,
                  onSelect: _selectTool,
                  vertical: wide,
                  chrome: chrome,
                  pill: _pill,
                  primary: widget.primary,
                  onPrimary: widget.onPrimary,
                );
                final previews = _PreviewRow(
                  doc: _previewDoc ?? doc,
                  images: Map.of(_images),
                  axis: wide ? Axis.vertical : Axis.horizontal,
                );
                final header = _buildHeader(chrome);

                if (!wide) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      header,
                      const SizedBox(height: 8),
                      previews,
                      const SizedBox(height: 8),
                      stage,
                      if (timeline != null) ...[
                        const SizedBox(height: 8),
                        timeline,
                      ],
                      if (panel != null) ...[
                        const SizedBox(height: 8),
                        panel,
                      ],
                      const SizedBox(height: 8),
                      nav,
                    ],
                  );
                }

                final tools = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    nav,
                    if (panel != null) ...[
                      const SizedBox(width: 8),
                      Expanded(child: panel),
                    ],
                  ],
                );

                return SizedBox(
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      const SizedBox(height: 8),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 260,
                              child: SingleChildScrollView(child: tools),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: stageSide,
                                    height: stageSide,
                                    child: stage,
                                  ),
                                  if (timeline != null) ...[
                                    const SizedBox(height: 8),
                                    timeline,
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 140,
                              child: SingleChildScrollView(child: previews),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BlobChromeColors chrome) {
    return Row(
      children: [
        if (widget.onCancel != null)
          _chip('Cancel', widget.onCancel, chrome, ghost: true),
        _chip('Undo', _past.isNotEmpty ? _undo : null, chrome),
        _chip('Redo', _future.isNotEmpty ? _redo : null, chrome),
        const Spacer(),
        FilledButton(
          style: _filledStyle(),
          onPressed: _exporting ? null : _doExport,
          child: Text(_exporting ? 'Export…' : 'Export'),
        ),
      ],
    );
  }

  Widget _buildStage(CompositionDocument doc, Color bgColor, {required double side}) {
    final viewScale = side / canvasSize;
    final masking = _maskMode != null;
    final brushing = _maskMode == 'add' || _maskMode == 'remove';

    return SizedBox(
      width: side,
      height: side,
      child: ClipRRect(
        borderRadius:
            widget.blocky ? BorderRadius.zero : BorderRadius.circular(8),
        child: ColoredBox(
          color: bgColor,
          child: MouseRegion(
            cursor: masking ? SystemMouseCursors.precise : SystemMouseCursors.basic,
            onHover: brushing
                ? (e) {
                    setState(() {
                      _brushCursor = Offset(
                        e.localPosition.dx / viewScale,
                        e.localPosition.dy / viewScale,
                      );
                    });
                  }
                : null,
            onExit: (_) {
              if (_brushCursor != null) setState(() => _brushCursor = null);
            },
            child: GestureDetector(
              onScaleStart: (d) {
                final live = _liveDoc.value ?? doc;
                final canvasPt = Offset(
                  d.localFocalPoint.dx / viewScale,
                  d.localFocalPoint.dy / viewScale,
                );
                if (_maskMode == 'polygon') {
                  final sel = _selectedObject(live);
                  if (sel is MediaObject && sel.kind == MediaKind.image) {
                    setState(() => _polygonPoints.add(canvasPt));
                  }
                  return;
                }
                if (_maskMode == 'add' || _maskMode == 'remove') {
                  final sel = _selectedObject(live);
                  if (sel is MediaObject && sel.kind == MediaKind.image) {
                    setState(() => _brushCursor = canvasPt);
                    unawaited(_paintBrush(sel, canvasPt, _maskMode!));
                  }
                  return;
                }
                _gestureStart = live;
                _lastFocal = d.localFocalPoint;
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
                setState(() {});
              },
              onScaleUpdate: (d) {
                final canvasPt = Offset(
                  d.localFocalPoint.dx / viewScale,
                  d.localFocalPoint.dy / viewScale,
                );
                if (_maskMode == 'polygon') return;
                if (_maskMode == 'add' || _maskMode == 'remove') {
                  final live = _liveDoc.value ?? doc;
                  final sel = _selectedObject(live);
                  if (sel is MediaObject && sel.kind == MediaKind.image) {
                    setState(() => _brushCursor = canvasPt);
                    unawaited(_paintBrush(sel, canvasPt, _maskMode!));
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
                if (_maskMode != null) {
                  if (_maskMode == 'add' || _maskMode == 'remove') {
                    _commitPreview();
                  }
                  return;
                }
                if (_gestureStart != null && _doc != null) {
                  _past.add(_gestureStart!);
                  _future.clear();
                  _gestureStart = null;
                }
                setState(() => _previewDoc = _doc);
              },
              child: ListenableBuilder(
                listenable:
                    Listenable.merge([_liveDoc, _frameTick, _playheadTick]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _CompositionPainter(
                      doc: _liveDoc.value ?? doc,
                      images: Map.of(_images),
                      playheadMs: _playheadMs,
                      brushCursor: brushing ? _brushCursor : null,
                      brushSize: _brushSize,
                      polygonPoints:
                          _maskMode == 'polygon' ? List.of(_polygonPoints) : const [],
                      accent: widget.primary,
                    ),
                    size: Size(side, side),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildTimeline(CompositionDocument doc, BlobChromeColors chrome) {
    if (doc.durationMs <= 0) return null;
    final medias = doc.objects.whereType<MediaObject>();
    final primaryMedia = medias.isEmpty ? null : medias.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
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
      ],
    );
  }

  Widget? _buildToolPanel(
    CompositionDocument doc,
    BlobChromeColors chrome,
    _ToolId? active,
  ) {
    if (active == null) return null;
    final sel = _selectedObject(doc);
    final selMedia = sel is MediaObject ? sel : null;
    final isVideo =
        doc.objects.any((o) => o is MediaObject && o.kind == MediaKind.video);

    Widget? body;
    switch (active) {
      case _ToolId.transform:
        if (sel == null) break;
        body = _TransformInspector(
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
        );
      case _ToolId.crop:
        if (selMedia == null) break;
        body = BlobGlass(
          colors: chrome,
          borderRadius: _radius,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _cropSliders(doc, selMedia, chrome),
          ),
        );
      case _ToolId.cutout:
        if (selMedia == null || selMedia.kind != MediaKind.image) break;
        body = _buildCutoutInspector(doc, selMedia, chrome);
      case _ToolId.text:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              children: [
                _chip('Add text', _addText, chrome),
                if (!isVideo) _chip('Overlay', _pickOverlay, chrome),
              ],
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
          ],
        );
      case _ToolId.canvas:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isVideo)
              Wrap(
                spacing: 6,
                children: [
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
              ),
            if (isVideo)
              BlobGlass(
                colors: chrome,
                borderRadius: _radius,
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Remove original sound',
                        style: TextStyle(
                          color: chrome.foreground,
                          fontSize: 13,
                        ),
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
        );
    }

    if (body == null) return null;
    return _ToolPanel(
      title: _toolTitles[active]!,
      chrome: chrome,
      radius: _radius,
      onClose: () => setState(() => _activeTool = null),
      child: body,
    );
  }

  Widget _buildCutoutInspector(
    CompositionDocument doc,
    MediaObject sel,
    BlobChromeColors chrome,
  ) {
    final outline = sel.outline;
    final brushing = _maskMode == 'add' || _maskMode == 'remove';
    return BlobGlass(
      colors: chrome,
      borderRadius: _radius,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Checkbox(
                value: outline != null,
                onChanged: (v) {
                  _push(setOutline(
                    doc,
                    sel.id,
                    v == true
                        ? const OutlineStyle(color: '#ffffff', width: 8)
                        : null,
                  ));
                },
              ),
              Expanded(
                child: Text(
                  'White sticker border',
                  style: TextStyle(color: chrome.foreground, fontSize: 13),
                ),
              ),
            ],
          ),
          if (outline != null) ...[
            Text(
              'Border width ${outline.width.round()}',
              style: TextStyle(fontSize: 12, color: chrome.muted),
            ),
            Slider(
              min: 2,
              max: 32,
              value: outline.width.clamp(2, 32),
              onChanged: (v) {
                _live(setOutline(
                  doc,
                  sel.id,
                  OutlineStyle(color: outline.color, width: v),
                ));
              },
              onChangeEnd: (_) {
                if (_doc != null) {
                  _past.add(_previewDoc ?? _doc!);
                  _future.clear();
                }
                _commitPreview();
              },
            ),
          ],
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                'Brush add',
                () => _setMaskMode(_maskMode == 'add' ? null : 'add'),
                chrome,
                primary: _maskMode == 'add',
              ),
              _chip(
                'Brush remove',
                () => _setMaskMode(_maskMode == 'remove' ? null : 'remove'),
                chrome,
                primary: _maskMode == 'remove',
              ),
              _chip(
                'Polygon',
                () => _setMaskMode(_maskMode == 'polygon' ? null : 'polygon'),
                chrome,
                primary: _maskMode == 'polygon',
              ),
            ],
          ),
          if (brushing) ...[
            const SizedBox(height: 4),
            Text(
              'Brush size ${_brushSize.round()}',
              style: TextStyle(fontSize: 12, color: chrome.muted),
            ),
            Row(
              children: [
                // Size preview: diameter tracks slider (8–64) in a fixed box.
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CustomPaint(
                    painter: _BrushSizePreviewPainter(
                      diameter: _brushSize.clamp(8, 64),
                      color: widget.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: Slider(
                    min: 8,
                    max: 64,
                    value: _brushSize.clamp(8, 64),
                    onChanged: (v) => setState(() {
                      _brushSize = v;
                      // Keep a stage ring visible while dragging (touch has no hover).
                      _brushCursor ??=
                          const Offset(canvasSize / 2, canvasSize / 2);
                    }),
                  ),
                ),
              ],
            ),
          ],
          if (_maskMode == 'polygon')
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text(
                'Tap ≥3 points (auto-closes). Then Apply mask.',
                style: TextStyle(fontSize: 11, color: chrome.muted),
              ),
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              _chip(
                'Apply mask',
                () => unawaited(_handleApplyMask()),
                chrome,
                primary: true,
              ),
              _chip(
                'Clear mask',
                () {
                  setState(() {
                    _maskMode = null;
                    _polygonPoints.clear();
                    _brushCursor = null;
                  });
                  _push(applyMask(doc, sel.id, null));
                },
                chrome,
              ),
            ],
          ),
        ],
      ),
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
    setState(() {
      _selectedId = id;
      _activeTool = _ToolId.text;
    });
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
    bool primary = false,
  }) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: primary ? widget.onPrimary : chrome.foreground,
        backgroundColor: primary
            ? widget.primary
            : ghost
                ? null
                : chrome.btn,
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

class _ToolNav extends StatelessWidget {
  const _ToolNav({
    required this.tools,
    required this.active,
    required this.onSelect,
    required this.vertical,
    required this.chrome,
    required this.pill,
    required this.primary,
    required this.onPrimary,
  });

  final List<({_ToolId id, String label})> tools;
  final _ToolId? active;
  final void Function(_ToolId id) onSelect;
  final bool vertical;
  final BlobChromeColors chrome;
  final BorderRadius pill;
  final Color primary;
  final Color onPrimary;

  @override
  Widget build(BuildContext context) {
    if (tools.isEmpty) return const SizedBox.shrink();
    final kids = [
      for (final t in tools)
        SizedBox(
          height: 44,
          width: vertical ? double.infinity : null,
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              maximumSize: const Size(double.infinity, 44),
              foregroundColor:
                  active == t.id ? onPrimary : chrome.foreground,
              backgroundColor: active == t.id ? primary : chrome.btn,
              shape: RoundedRectangleBorder(
                borderRadius: pill,
                side: BorderSide(color: chrome.btnBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: () => onSelect(t.id),
            child: Text(t.label, overflow: TextOverflow.ellipsis),
          ),
        ),
    ];
    if (vertical) {
      return SizedBox(
        width: 88,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < kids.length; i++) ...[
              if (i > 0) const SizedBox(height: 4),
              kids[i],
            ],
          ],
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < kids.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            kids[i],
          ],
        ],
      ),
    );
  }
}

class _ToolPanel extends StatelessWidget {
  const _ToolPanel({
    required this.title,
    required this.chrome,
    required this.radius,
    required this.onClose,
    required this.child,
  });

  final String title;
  final BlobChromeColors chrome;
  final BorderRadius radius;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlobGlass(
      colors: chrome,
      borderRadius: radius,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: chrome.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 36),
                  foregroundColor: chrome.foreground,
                ),
                onPressed: onClose,
                child: const Text('Close'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _BrushSizePreviewPainter extends CustomPainter {
  _BrushSizePreviewPainter({required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (diameter / 2).clamp(1.0, math.min(size.width, size.height) / 2);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _BrushSizePreviewPainter old) =>
      old.diameter != diameter || old.color != color;
}

class _CompositionPainter extends CustomPainter {
  _CompositionPainter({
    required this.doc,
    required this.images,
    this.playheadMs = 0,
    this.brushCursor,
    this.brushSize = 28,
    this.polygonPoints = const [],
    this.accent = const Color(0xFFF10EA0),
  });

  final CompositionDocument doc;
  final Map<String, ui.Image> images;
  final double playheadMs;
  final Offset? brushCursor;
  final double brushSize;
  final List<Offset> polygonPoints;
  final Color accent;

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

    final stroke = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    if (polygonPoints.isNotEmpty) {
      final path = Path();
      for (var i = 0; i < polygonPoints.length; i++) {
        final p = polygonPoints[i];
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      if (polygonPoints.length >= 3) path.close();
      canvas.drawPath(path, stroke);
      for (final p in polygonPoints) {
        canvas.drawCircle(p, 5, Paint()..color = accent);
      }
    }

    if (brushCursor != null) {
      canvas.drawCircle(
        brushCursor!,
        brushSize,
        stroke..strokeWidth = 2,
      );
      // Dashed feel: second lighter ring
      canvas.drawCircle(
        brushCursor!,
        brushSize,
        Paint()
          ..color = accent.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CompositionPainter old) =>
      old.doc != doc ||
      old.images != images ||
      old.playheadMs != playheadMs ||
      old.brushCursor != brushCursor ||
      old.brushSize != brushSize ||
      old.polygonPoints != polygonPoints;
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
