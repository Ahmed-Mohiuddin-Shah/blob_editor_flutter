// BLOB Print layout document — mirrors TS `blob-editor/print` (v1).

const int printDocumentVersion = 1;
const double defaultPrintDpi = 150;

class PrintMargins {
  const PrintMargins({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  final double top;
  final double right;
  final double bottom;
  final double left;

  Map<String, dynamic> toJson() => {
        'top': top,
        'right': right,
        'bottom': bottom,
        'left': left,
      };

  factory PrintMargins.fromJson(Map<String, dynamic> j) => PrintMargins(
        top: (j['top'] as num).toDouble(),
        right: (j['right'] as num).toDouble(),
        bottom: (j['bottom'] as num).toDouble(),
        left: (j['left'] as num).toDouble(),
      );
}

class PrintPage {
  const PrintPage({
    required this.widthMm,
    required this.heightMm,
    required this.marginMm,
    this.background = '#FFFFFF',
    this.cutMarks = true,
  });

  final double widthMm;
  final double heightMm;
  final PrintMargins marginMm;
  final String background; // transparent | #RRGGBB
  final bool cutMarks;

  PrintPage copyWith({
    double? widthMm,
    double? heightMm,
    PrintMargins? marginMm,
    String? background,
    bool? cutMarks,
  }) =>
      PrintPage(
        widthMm: widthMm ?? this.widthMm,
        heightMm: heightMm ?? this.heightMm,
        marginMm: marginMm ?? this.marginMm,
        background: background ?? this.background,
        cutMarks: cutMarks ?? this.cutMarks,
      );

  Map<String, dynamic> toJson() => {
        'width_mm': widthMm,
        'height_mm': heightMm,
        'margin_mm': marginMm.toJson(),
        'background': background,
        'cut_marks': cutMarks,
      };

  factory PrintPage.fromJson(Map<String, dynamic> j) => PrintPage(
        widthMm: (j['width_mm'] as num).toDouble(),
        heightMm: (j['height_mm'] as num).toDouble(),
        marginMm: PrintMargins.fromJson(j['margin_mm'] as Map<String, dynamic>),
        background: j['background'] as String? ?? '#FFFFFF',
        cutMarks: j['cut_marks'] as bool? ?? true,
      );
}

class PrintItem {
  const PrintItem({
    required this.id,
    required this.assetId,
    required this.xMm,
    required this.yMm,
    required this.widthMm,
    this.rotationDeg = 0,
  });

  final String id;
  final String assetId;
  final double xMm;
  final double yMm;
  final double widthMm;
  final double rotationDeg;

  PrintItem copyWith({
    String? assetId,
    double? xMm,
    double? yMm,
    double? widthMm,
    double? rotationDeg,
  }) =>
      PrintItem(
        id: id,
        assetId: assetId ?? this.assetId,
        xMm: xMm ?? this.xMm,
        yMm: yMm ?? this.yMm,
        widthMm: widthMm ?? this.widthMm,
        rotationDeg: rotationDeg ?? this.rotationDeg,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'asset_id': assetId,
        'x_mm': xMm,
        'y_mm': yMm,
        'width_mm': widthMm,
        'rotation_deg': rotationDeg,
      };

  factory PrintItem.fromJson(Map<String, dynamic> j) => PrintItem(
        id: j['id'] as String,
        assetId: j['asset_id'] as String,
        xMm: (j['x_mm'] as num).toDouble(),
        yMm: (j['y_mm'] as num).toDouble(),
        widthMm: (j['width_mm'] as num).toDouble(),
        rotationDeg: (j['rotation_deg'] as num?)?.toDouble() ?? 0,
      );
}

class PrintDocument {
  const PrintDocument({
    this.version = printDocumentVersion,
    required this.page,
    this.items = const [],
  });

  final int version;
  final PrintPage page;
  final List<PrintItem> items;

  PrintDocument copyWith({PrintPage? page, List<PrintItem>? items}) =>
      PrintDocument(
        version: version,
        page: page ?? this.page,
        items: items ?? this.items,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'page': page.toJson(),
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory PrintDocument.fromJson(Map<String, dynamic> j) => PrintDocument(
        version: j['version'] as int? ?? printDocumentVersion,
        page: PrintPage.fromJson(j['page'] as Map<String, dynamic>),
        items: (j['items'] as List<dynamic>? ?? [])
            .map((e) => PrintItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class PrintAssetMeta {
  const PrintAssetMeta({required this.id, this.label, this.thumbUrl});
  final String id;
  final String? label;
  final String? thumbUrl;
}

class PrintExportPayload {
  const PrintExportPayload({
    required this.document,
    required this.previewPng,
  });
  final PrintDocument document;
  final List<int> previewPng;
}

class LayoutGridOptions {
  const LayoutGridOptions({
    required this.rows,
    required this.columns,
    this.gapMm = 2,
  });
  final int rows;
  final int columns;
  final double gapMm;
}

const PrintMargins _defaultMargins =
    PrintMargins(top: 10, right: 10, bottom: 10, left: 10);

PrintPage pageCustom(
  double widthMm,
  double heightMm, {
  PrintMargins? marginMm,
  String background = '#FFFFFF',
  bool cutMarks = true,
}) =>
    PrintPage(
      widthMm: widthMm,
      heightMm: heightMm,
      marginMm: marginMm ?? _defaultMargins,
      background: background,
      cutMarks: cutMarks,
    );

PrintPage pageA4({
  PrintMargins? marginMm,
  String background = '#FFFFFF',
  bool cutMarks = true,
}) =>
    pageCustom(210, 297,
        marginMm: marginMm, background: background, cutMarks: cutMarks);

PrintPage pageA5({
  PrintMargins? marginMm,
  String background = '#FFFFFF',
  bool cutMarks = true,
}) =>
    pageCustom(148, 210,
        marginMm: marginMm, background: background, cutMarks: cutMarks);

PrintDocument createEmptyPrintDocument([PrintPage? page]) =>
    PrintDocument(page: page ?? pageA4());

double mmToPx(double mm, double dpi) => (mm / 25.4) * dpi;

({double width, double height}) pagePixelSize(PrintPage page, double dpi) => (
      width: mmToPx(page.widthMm, dpi).roundToDouble().clamp(1, double.infinity),
      height: mmToPx(page.heightMm, dpi).roundToDouble().clamp(1, double.infinity),
    );
