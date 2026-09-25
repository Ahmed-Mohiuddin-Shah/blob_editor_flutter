import 'document.dart';

int _seq = 0;

String newPrintItemId([String prefix = 'item']) {
  _seq += 1;
  return '${prefix}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_$_seq';
}

PrintDocument setPrintPage(PrintDocument doc, PrintPage page) =>
    doc.copyWith(page: page);

PrintDocument addPrintItem(
  PrintDocument doc, {
  required String assetId,
  double? xMm,
  double? yMm,
  double? widthMm,
  double? rotationDeg,
  String? id,
}) {
  final m = doc.page.marginMm;
  final item = PrintItem(
    id: id ?? newPrintItemId(),
    assetId: assetId,
    xMm: xMm ?? m.left,
    yMm: yMm ?? m.top,
    widthMm: widthMm ?? 40,
    rotationDeg: rotationDeg ?? 0,
  );
  return doc.copyWith(items: [...doc.items, item]);
}

PrintDocument removePrintItem(PrintDocument doc, String id) {
  final items = doc.items.where((it) => it.id != id).toList();
  if (items.length == doc.items.length) {
    throw StateError('print item not found: $id');
  }
  return doc.copyWith(items: items);
}

PrintDocument updatePrintItem(
  PrintDocument doc,
  String id, {
  String? assetId,
  double? xMm,
  double? yMm,
  double? widthMm,
  double? rotationDeg,
}) {
  final idx = doc.items.indexWhere((it) => it.id == id);
  if (idx < 0) throw StateError('print item not found: $id');
  final next = doc.items[idx].copyWith(
    assetId: assetId,
    xMm: xMm,
    yMm: yMm,
    widthMm: widthMm,
    rotationDeg: rotationDeg,
  );
  if (next.widthMm <= 0) throw ArgumentError('width_mm must be > 0');
  final items = [...doc.items];
  items[idx] = next;
  return doc.copyWith(items: items);
}

PrintDocument movePrintItem(
  PrintDocument doc,
  String id,
  double xMm,
  double yMm,
) =>
    updatePrintItem(doc, id, xMm: xMm, yMm: yMm);

PrintDocument resizePrintItem(PrintDocument doc, String id, double widthMm) =>
    updatePrintItem(doc, id, widthMm: widthMm);

PrintDocument rotatePrintItem(
  PrintDocument doc,
  String id,
  double rotationDeg,
) =>
    updatePrintItem(doc, id, rotationDeg: rotationDeg);

/// Pack asset ids into a grid inside page margins. Extra ids dropped.
PrintDocument layoutGrid(
  List<String> assetIds,
  PrintPage page,
  LayoutGridOptions opts,
) {
  final rows = opts.rows < 1 ? 1 : opts.rows;
  final cols = opts.columns < 1 ? 1 : opts.columns;
  final gap = opts.gapMm;
  final m = page.marginMm;
  final innerW = page.widthMm - m.left - m.right;
  final innerH = page.heightMm - m.top - m.bottom;
  if (innerW <= 0 || innerH <= 0) {
    throw StateError('page margins leave no printable area');
  }
  final cellW = (innerW - gap * (cols - 1)) / cols;
  final cellH = (innerH - gap * (rows - 1)) / rows;
  if (cellW <= 0 || cellH <= 0) {
    throw StateError('grid cells have non-positive size');
  }
  final sticker = cellW < cellH ? cellW : cellH;
  final capacity = rows * cols;
  final ids = assetIds.take(capacity).toList();
  final items = <PrintItem>[];
  for (var i = 0; i < ids.length; i++) {
    final r = i ~/ cols;
    final c = i % cols;
    items.add(PrintItem(
      id: newPrintItemId('grid'),
      assetId: ids[i],
      xMm: m.left + c * (cellW + gap) + (cellW - sticker) / 2,
      yMm: m.top + r * (cellH + gap) + (cellH - sticker) / 2,
      widthMm: sticker,
    ));
  }
  return createEmptyPrintDocument(page).copyWith(items: items);
}

PrintItem? findPrintItem(PrintDocument doc, String id) {
  for (final it in doc.items) {
    if (it.id == id) return it;
  }
  return null;
}
