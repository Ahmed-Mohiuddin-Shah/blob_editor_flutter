import 'package:blob_editor/blob_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateDocument', () {
    test('accepts empty doc', () {
      final doc = createEmptyDocument();
      expect(validateDocument(doc.toJson()).version, 1);
    });

    test('rejects wrong canvas', () {
      expect(
        () => validateDocument({
          'version': 1,
          'canvas': {'width': 100, 'height': 100, 'background': 'transparent'},
          'objects': [],
        }),
        throwsA(isA<DocumentValidationException>()),
      );
    });

    test('rejects bad background', () {
      expect(
        () => validateDocument({
          'version': 1,
          'canvas': {'width': 1024, 'height': 1024, 'background': 'red'},
          'objects': [],
        }),
        throwsA(isA<DocumentValidationException>()),
      );
    });
  });

  group('ops', () {
    test('createFromSource centers and scales', () {
      final doc = createFromSource('a1', 1920, 1080);
      expect(doc.objects, hasLength(1));
      final m = doc.objects.first as MediaObject;
      expect(m.transform.x, canvasSize / 2);
      expect(m.transform.scaleX, closeTo(1024 / 1920, 1e-9));
    });

    test('updateTransform / setBackground / addText / applyMask', () {
      var doc = createFromSource('a1', 100, 100);
      final id = doc.objects.first.id;
      doc = updateTransform(doc, id, rotation: 45);
      doc = setBackground(doc, '#ff00aa');
      doc = applyMask(doc, id, 'mask1');
      doc = addText(doc, text: 'HI');
      expect(doc.canvas.background, '#ff00aa');
      expect(doc.objects, hasLength(2));
      final media = doc.objects.first as MediaObject;
      expect(media.transform.rotation, 45);
      expect(media.maskAssetId, 'mask1');
    });
  });

  group('remixDeepCopy', () {
    test('deep-copies and keeps asset ids', () {
      final src = createFromSource('shared', 50, 50);
      final copy = remixDeepCopy(src);
      expect(copy.toJson(), src.toJson());
      expect(identical(copy, src), isFalse);
      expect((copy.objects.first as MediaObject).assetId, 'shared');
    });
  });

  test('exportSizes locked', () {
    expect(exportSizes, {'chat': 128, 'thumbnail': 256, 'full': 1024});
  });
}
