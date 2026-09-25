import 'package:blob_editor/blob_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validate empty A4', () {
    final doc = createEmptyPrintDocument();
    expect(validatePrintDocument(doc.toJson()).page.widthMm, 210);
  });

  test('layoutGrid packs square cells', () {
    final doc = layoutGrid(
      ['a', 'b', 'c', 'd'],
      pageA4(),
      const LayoutGridOptions(rows: 2, columns: 2),
    );
    expect(doc.items, hasLength(4));
    final w = doc.items.first.widthMm;
    expect(doc.items.every((it) => it.widthMm == w), isTrue);
  });

  test('rejects bad background', () {
    expect(
      () => validatePrintDocument({
        'version': 1,
        'page': {
          'width_mm': 210,
          'height_mm': 297,
          'margin_mm': {'top': 10, 'right': 10, 'bottom': 10, 'left': 10},
          'background': 'white',
          'cut_marks': true,
        },
        'items': [],
      }),
      throwsA(isA<PrintValidationError>()),
    );
  });
}
