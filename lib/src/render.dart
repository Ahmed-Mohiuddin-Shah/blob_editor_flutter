import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

import 'document.dart';
import 'fonts.dart';
import 'sizes.dart';

typedef AssetResolver = ui.Image? Function(String assetId);

Color? _parseColor(String v) {
  if (v == 'transparent') return null;
  if (v.length == 7 && v.startsWith('#')) {
    final n = int.parse(v.substring(1), radix: 16);
    return Color(0xFF000000 | n);
  }
  return null;
}

void _drawBackground(Canvas canvas, Background background) {
  final c = _parseColor(background);
  if (c == null) return;
  canvas.drawRect(
    Rect.fromLTWH(0, 0, canvasSize.toDouble(), canvasSize.toDouble()),
    Paint()..color = c,
  );
}

void _drawMedia(Canvas canvas, MediaObject obj, AssetResolver resolver) {
  final image = resolver(obj.assetId);
  if (image == null) return;

  final crop = obj.crop;
  final sw = crop?.width ?? image.width.toDouble();
  final sh = crop?.height ?? image.height.toDouble();
  final sx = crop?.x ?? 0;
  final sy = crop?.y ?? 0;
  final src = Rect.fromLTWH(sx, sy, sw, sh);
  final dst = Rect.fromCenter(center: Offset.zero, width: sw, height: sh);

  canvas.save();
  canvas.translate(obj.transform.x, obj.transform.y);
  canvas.rotate(obj.transform.rotation * math.pi / 180);
  canvas.scale(obj.transform.scaleX, obj.transform.scaleY);

  final maskId = obj.maskAssetId;
  final mask = maskId != null ? resolver(maskId) : null;
  if (mask != null) {
    canvas.saveLayer(dst, Paint());
    canvas.drawImageRect(image, src, dst, Paint());
    canvas.drawImageRect(
      mask,
      Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
      dst,
      Paint()..blendMode = BlendMode.dstIn,
    );
    canvas.restore();
  } else {
    canvas.drawImageRect(image, src, dst, Paint());
  }
  canvas.restore();
}

TextStyle _memeTextStyle({
  required String font,
  required double fontSize,
  Color? color,
  Paint? foreground,
}) {
  final useMeme = font == memeFont || font == 'Impact';
  if (useMeme) {
    return GoogleFonts.anton(
      fontSize: fontSize,
      color: color,
      foreground: foreground,
    );
  }
  return TextStyle(
    fontFamily: font,
    fontSize: fontSize,
    color: color,
    foreground: foreground,
  );
}

void _drawText(Canvas canvas, TextObject obj) {
  canvas.save();
  canvas.translate(obj.transform.x, obj.transform.y);
  canvas.rotate(obj.transform.rotation * math.pi / 180);
  canvas.scale(obj.transform.scaleX, obj.transform.scaleY);

  final fill = _parseColor(obj.style.fill) ?? const Color(0xFFFFFFFF);
  final stroke = _parseColor(obj.style.stroke) ?? const Color(0xFF000000);

  if (obj.style.strokeWidth > 0) {
    final strokeTp = TextPainter(
      text: TextSpan(
        text: obj.text,
        style: _memeTextStyle(
          font: obj.font,
          fontSize: obj.fontSize,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = obj.style.strokeWidth
            ..color = stroke
            ..strokeJoin = StrokeJoin.round,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    strokeTp.layout();
    strokeTp.paint(canvas, Offset(-strokeTp.width / 2, -strokeTp.height / 2));
  }

  final fillTp = TextPainter(
    text: TextSpan(
      text: obj.text,
      style: _memeTextStyle(
        font: obj.font,
        fontSize: obj.fontSize,
        color: fill,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  );
  fillTp.layout();
  fillTp.paint(canvas, Offset(-fillTp.width / 2, -fillTp.height / 2));
  canvas.restore();
}

void paintComposition(
  Canvas canvas,
  CompositionDocument doc,
  AssetResolver resolver,
) {
  _drawBackground(canvas, doc.canvas.background);
  for (final obj in doc.objects) {
    switch (obj) {
      case MediaObject():
        _drawMedia(canvas, obj, resolver);
      case TextObject():
        _drawText(canvas, obj);
    }
  }
}

Future<ui.Image> renderFullImage(
  CompositionDocument doc,
  AssetResolver resolver,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintComposition(canvas, doc, resolver);
  final picture = recorder.endRecording();
  return picture.toImage(canvasSize, canvasSize);
}

Future<Uint8List> _imageToPng(ui.Image image) async {
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bd == null) throw StateError('png encode failed');
  return bd.buffer.asUint8List();
}

Future<Uint8List> _scalePng(ui.Image source, int size) async {
  if (size == canvasSize) return _imageToPng(source);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  final scaled = await picture.toImage(size, size);
  return _imageToPng(scaled);
}

/// Preview ≡ export: one full render, then scale.
Future<ExportPayload> renderExports(
  CompositionDocument doc,
  AssetResolver resolver,
) async {
  final fullImg = await renderFullImage(doc, resolver);
  final chat = await _scalePng(fullImg, exportSizes['chat']!);
  final thumbnail = await _scalePng(fullImg, exportSizes['thumbnail']!);
  final full = await _scalePng(fullImg, exportSizes['full']!);
  return ExportPayload(
    document: doc,
    chat: chat,
    thumbnail: thumbnail,
    full: full,
    background: doc.canvas.background,
  );
}
