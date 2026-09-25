import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('blob_editor/video_poster');

/// Scrub preview width — export stills stay full-res elsewhere.
const int kScrubMaxWidth = 480;

/// Coarse bucket for play preview only (ms).
const int kPlayBucketMs = 200;

final LinkedHashMap<String, ui.Image> _frameCache = LinkedHashMap();
const int _cacheCap = 64;

String _cacheKey(String path, double timeMs, int maxWidth, bool accurate) {
  if (accurate) {
    // ~1 frame @ 30fps
    return '$path|a|${(timeMs / 33).round()}|$maxWidth';
  }
  return '$path|p|${(timeMs / kPlayBucketMs).floor()}|$maxWidth';
}

void _putCache(String key, ui.Image image) {
  _frameCache.remove(key);
  _frameCache[key] = image;
  while (_frameCache.length > _cacheCap) {
    _frameCache.remove(_frameCache.keys.first);
  }
}

/// Frame at [timeMs] for a local video [path].
/// [accurate]: true = nearest frame (scrub); false = keyframe-ish (play).
Future<ui.Image> videoPosterImage(
  String path, {
  int maxWidth = kScrubMaxWidth,
  double timeMs = 0,
  bool accurate = true,
}) async {
  final key = _cacheKey(path, timeMs, maxWidth, accurate);
  final hit = _frameCache[key];
  if (hit != null) {
    _frameCache.remove(key);
    _frameCache[key] = hit;
    return hit;
  }

  final requestMs = accurate
      ? timeMs
      : (timeMs / kPlayBucketMs).floor() * kPlayBucketMs;

  try {
    final bytes = await _channel.invokeMethod<Uint8List>('posterPng', {
      'path': path,
      'maxWidth': maxWidth,
      'timeMs': requestMs,
      'accurate': accurate,
    });
    if (bytes != null && bytes.isNotEmpty) {
      final img = await _decodeBytes(bytes);
      _putCache(key, img);
      return img;
    }
  } on MissingPluginException {
    // tests / non-Android
  } on PlatformException {
    // fall through
  }
  return _placeholderPoster();
}

Future<void> releaseVideoPoster() async {
  try {
    await _channel.invokeMethod<void>('release');
  } on MissingPluginException {
    // ignore
  } on PlatformException {
    // ignore
  }
  _frameCache.clear();
}

Future<double> videoDurationMs(String path) async {
  try {
    final map = await _channel.invokeMethod<Map>('durationMs', {'path': path});
    final v = map?['durationMs'];
    if (v is num) return v.toDouble().clamp(0, 10000);
  } on MissingPluginException {
    // ignore
  } on PlatformException {
    // ignore
  }
  return 3000;
}

Future<({List<ui.Image> frames, List<int> delaysMs, double totalMs})> decodeGifFrames(
  Uint8List bytes,
) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frames = <ui.Image>[];
  final delays = <int>[];
  for (var i = 0; i < codec.frameCount; i++) {
    final f = await codec.getNextFrame();
    frames.add(f.image);
    final d = f.duration.inMilliseconds;
    delays.add(d <= 0 ? 100 : d);
  }
  if (frames.isEmpty) {
    return (frames: frames, delaysMs: delays, totalMs: 0.0);
  }
  final total =
      delays.fold<int>(0, (a, b) => a + b).toDouble().clamp(0.0, 10000.0);
  return (frames: frames, delaysMs: delays, totalMs: total.toDouble());
}

ui.Image gifFrameAt(List<ui.Image> frames, List<int> delaysMs, double tMs) {
  if (frames.isEmpty) {
    throw StateError('no gif frames');
  }
  if (frames.length == 1) return frames.first;
  final total = delaysMs.fold<int>(0, (a, b) => a + b);
  if (total <= 0) return frames.first;
  var t = tMs % total;
  if (t < 0) t += total;
  var acc = 0;
  for (var i = 0; i < frames.length; i++) {
    acc += delaysMs[i];
    if (t < acc) return frames[i];
  }
  return frames.last;
}

Future<ui.Image> _decodeBytes(Uint8List bytes) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromList(bytes, c.complete);
  return c.future;
}

Future<ui.Image> _placeholderPoster() async {
  const w = 1280.0;
  const h = 720.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()..color = const Color(0xFF1A1A1A),
  );
  final play = Path()
    ..moveTo(w * 0.42, h * 0.35)
    ..lineTo(w * 0.42, h * 0.65)
    ..lineTo(w * 0.62, h * 0.5)
    ..close();
  canvas.drawPath(play, Paint()..color = const Color(0xB3FFFFFF));
  final picture = recorder.endRecording();
  return picture.toImage(w.toInt(), h.toInt());
}
