import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'document.dart';

typedef PrintAssetResolver = ui.Image? Function(String assetId);

void _drawCutMarks(Canvas canvas, PrintDocument doc, double dpi) {
  if (!doc.page.cutMarks) return;
  final m = doc.page.marginMm;
  final mark = mmToPx(3, dpi);
  final paint = Paint()
    ..color = const Color(0xFF000000)
    ..strokeWidth = mmToPx(0.2, dpi).clamp(1, 4)
    ..style = PaintingStyle.stroke;
  final left = mmToPx(m.left, dpi);
  final top = mmToPx(m.top, dpi);
  final right = mmToPx(doc.page.widthMm - m.right, dpi);
  final bottom = mmToPx(doc.page.heightMm - m.bottom, dpi);
  for (final p in [
    Offset(left, top),
    Offset(right, top),
    Offset(left, bottom),
    Offset(right, bottom),
  ]) {
    canvas.drawLine(Offset(p.dx - mark, p.dy), Offset(p.dx + mark, p.dy), paint);
    canvas.drawLine(Offset(p.dx, p.dy - mark), Offset(p.dx, p.dy + mark), paint);
  }
}

void paintPrintPage(
  Canvas canvas,
  PrintDocument doc,
  PrintAssetResolver resolver, {
  double dpi = defaultPrintDpi,
}) {
  final size = pagePixelSize(doc.page, dpi);
  if (doc.page.background != 'transparent') {
    final hex = doc.page.background.replaceFirst('#', '');
    if (hex.length == 6) {
      final color = Color(int.parse('FF$hex', radix: 16));
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = color,
      );
    }
  }
  for (final item in doc.items) {
    final img = resolver(item.assetId);
    if (img == null) continue;
    final aspect = img.height / (img.width < 1 ? 1 : img.width);
    final wPx = mmToPx(item.widthMm, dpi);
    final hPx = wPx * aspect;
    final cx = mmToPx(item.xMm, dpi) + wPx / 2;
    final cy = mmToPx(item.yMm, dpi) + hPx / 2;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(item.rotationDeg * 3.141592653589793 / 180);
    paintImage(
      canvas: canvas,
      rect: Rect.fromCenter(center: Offset.zero, width: wPx, height: hPx),
      image: img,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.high,
    );
    canvas.restore();
  }
  _drawCutMarks(canvas, doc, dpi);
}

Future<ui.Image> renderPrintPageImage(
  PrintDocument doc,
  PrintAssetResolver resolver, {
  double dpi = defaultPrintDpi,
}) async {
  final size = pagePixelSize(doc.page, dpi);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  paintPrintPage(canvas, doc, resolver, dpi: dpi);
  final picture = recorder.endRecording();
  return picture.toImage(size.width.round(), size.height.round());
}

Future<List<int>> renderPrintPng(
  PrintDocument doc,
  PrintAssetResolver resolver, {
  double dpi = defaultPrintDpi,
}) async {
  final image = await renderPrintPageImage(doc, resolver, dpi: dpi);
  final bd = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bd!.buffer.asUint8List();
}
