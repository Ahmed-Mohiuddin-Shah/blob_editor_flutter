import 'document.dart';

class PrintValidationError implements Exception {
  PrintValidationError(this.message);
  final String message;
  @override
  String toString() => 'PrintValidationError: $message';
}

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

bool _isBackground(String v) => v == 'transparent' || _hex.hasMatch(v);

PrintMargins _margins(Map<String, dynamic> m, String path) {
  for (final k in ['top', 'right', 'bottom', 'left']) {
    final n = m[k];
    if (n is! num || n < 0) {
      throw PrintValidationError('$path.$k must be >= 0');
    }
  }
  return PrintMargins.fromJson(m);
}

PrintPage _page(Map<String, dynamic> p) {
  final w = p['width_mm'];
  final h = p['height_mm'];
  if (w is! num || w <= 0) {
    throw PrintValidationError('page.width_mm must be > 0');
  }
  if (h is! num || h <= 0) {
    throw PrintValidationError('page.height_mm must be > 0');
  }
  final bg = p['background'];
  if (bg is! String || !_isBackground(bg)) {
    throw PrintValidationError('page.background must be transparent or #RRGGBB');
  }
  final cut = p['cut_marks'];
  if (cut is! bool) {
    throw PrintValidationError('page.cut_marks must be boolean');
  }
  final margin = p['margin_mm'];
  if (margin is! Map) {
    throw PrintValidationError('page.margin_mm required');
  }
  return PrintPage(
    widthMm: w.toDouble(),
    heightMm: h.toDouble(),
    marginMm: _margins(Map<String, dynamic>.from(margin), 'page.margin_mm'),
    background: bg,
    cutMarks: cut,
  );
}

PrintItem _item(Map<String, dynamic> o, int index) {
  final id = o['id'];
  final assetId = o['asset_id'];
  if (id is! String || id.isEmpty) {
    throw PrintValidationError('items[$index].id required');
  }
  if (assetId is! String || assetId.isEmpty) {
    throw PrintValidationError('items[$index].asset_id required');
  }
  for (final k in ['x_mm', 'y_mm', 'width_mm', 'rotation_deg']) {
    if (o[k] is! num) {
      throw PrintValidationError('items[$index].$k must be a number');
    }
  }
  if ((o['width_mm'] as num) <= 0) {
    throw PrintValidationError('items[$index].width_mm must be > 0');
  }
  return PrintItem.fromJson(o);
}

PrintDocument validatePrintDocument(Object? raw) {
  if (raw is! Map) {
    throw PrintValidationError('document must be an object');
  }
  final d = Map<String, dynamic>.from(raw);
  final version = d['version'];
  if (version != printDocumentVersion && version != 1) {
    throw PrintValidationError('unsupported print document version: $version');
  }
  final itemsRaw = d['items'];
  if (itemsRaw is! List) {
    throw PrintValidationError('items must be an array');
  }
  final items = <PrintItem>[];
  final ids = <String>{};
  for (var i = 0; i < itemsRaw.length; i++) {
    final it = _item(Map<String, dynamic>.from(itemsRaw[i] as Map), i);
    if (!ids.add(it.id)) {
      throw PrintValidationError('duplicate item id: ${it.id}');
    }
    items.add(it);
  }
  final pageRaw = d['page'];
  if (pageRaw is! Map) {
    throw PrintValidationError('page required');
  }
  return PrintDocument(
    version: printDocumentVersion,
    page: _page(Map<String, dynamic>.from(pageRaw)),
    items: items,
  );
}
