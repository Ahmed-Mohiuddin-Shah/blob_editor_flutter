import 'dart:ui' as ui;

import 'package:blob_editor/blob_editor.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _solidImage(int w, int h, int rgba) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = ui.Color(rgba),
  );
  final picture = recorder.endRecording();
  return picture.toImage(w, h);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renderMaskPng null without mask or outline', () async {
    final img = await _solidImage(64, 64, 0xFFFF0000);
    final doc = createFromSource('a1', 64, 64);
    final mask = await renderMaskPng(doc, (id) => id == 'a1' ? img : null);
    expect(mask, isNull);
  });

  test('renderMaskPng returns bytes when outline present', () async {
    var doc = createFromSource('a1', 64, 64);
    final id = doc.objects.first.id;
    doc = setOutline(doc, id, const OutlineStyle(color: '#ffffff', width: 8));
    final img = await _solidImage(64, 64, 0xFFFF0000);
    final mask = await renderMaskPng(doc, (id) => id == 'a1' ? img : null);
    expect(mask, isNotNull);
    expect(mask!.length, greaterThan(32));
  });

  test('renderExports fills mask when cutout outline set', () async {
    var doc = createFromSource('a1', 64, 64);
    final id = doc.objects.first.id;
    doc = setOutline(doc, id, const OutlineStyle(color: '#ffffff', width: 4));
    final img = await _solidImage(64, 64, 0xFF00FF00);
    final payload = await renderExports(doc, (id) => id == 'a1' ? img : null);
    expect(payload.mask, isNotNull);
    expect(payload.chat.length, greaterThan(0));
  });
}
