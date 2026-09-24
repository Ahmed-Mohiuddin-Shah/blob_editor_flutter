import 'dart:typed_data';

/// BLOB Composition document — mirrors TS `blob-editor` core.

const int documentVersion = 1;
const int canvasSize = 1024;

typedef Background = String; // "transparent" | "#RRGGBB"

class Transform2D {
  const Transform2D({
    required this.x,
    required this.y,
    required this.scaleX,
    required this.scaleY,
    required this.rotation,
  });

  final double x;
  final double y;
  final double scaleX;
  final double scaleY;

  /// Degrees, clockwise.
  final double rotation;

  Transform2D copyWith({
    double? x,
    double? y,
    double? scaleX,
    double? scaleY,
    double? rotation,
  }) =>
      Transform2D(
        x: x ?? this.x,
        y: y ?? this.y,
        scaleX: scaleX ?? this.scaleX,
        scaleY: scaleY ?? this.scaleY,
        rotation: rotation ?? this.rotation,
      );

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'scale_x': scaleX,
        'scale_y': scaleY,
        'rotation': rotation,
      };

  factory Transform2D.fromJson(Map<String, dynamic> j) => Transform2D(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        scaleX: (j['scale_x'] as num).toDouble(),
        scaleY: (j['scale_y'] as num).toDouble(),
        rotation: (j['rotation'] as num).toDouble(),
      );
}

class CropRect {
  const CropRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  factory CropRect.fromJson(Map<String, dynamic> j) => CropRect(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
      );
}

class Timing {
  const Timing({required this.start, required this.end});
  final double start;
  final double end;

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory Timing.fromJson(Map<String, dynamic> j) => Timing(
        start: (j['start'] as num).toDouble(),
        end: (j['end'] as num).toDouble(),
      );
}

sealed class CompositionObject {
  String get id;
  Transform2D get transform;
  Map<String, dynamic> toJson();
}

class MediaObject implements CompositionObject {
  MediaObject({
    required this.id,
    required this.assetId,
    required this.transform,
    this.crop,
    this.maskAssetId,
    this.timing,
  });

  @override
  final String id;
  final String assetId;
  @override
  final Transform2D transform;
  final CropRect? crop;
  final String? maskAssetId;
  final Timing? timing;

  MediaObject copyWith({
    Transform2D? transform,
    CropRect? crop,
    String? maskAssetId,
    bool clearMask = false,
  }) =>
      MediaObject(
        id: id,
        assetId: assetId,
        transform: transform ?? this.transform,
        crop: crop ?? this.crop,
        maskAssetId: clearMask ? null : (maskAssetId ?? this.maskAssetId),
        timing: timing,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'media',
        'asset_id': assetId,
        'transform': transform.toJson(),
        'crop': crop?.toJson(),
        'mask_asset_id': maskAssetId,
        'timing': timing?.toJson(),
      };

  factory MediaObject.fromJson(Map<String, dynamic> j) => MediaObject(
        id: j['id'] as String,
        assetId: j['asset_id'] as String,
        transform: Transform2D.fromJson(j['transform'] as Map<String, dynamic>),
        crop: j['crop'] == null
            ? null
            : CropRect.fromJson(j['crop'] as Map<String, dynamic>),
        maskAssetId: j['mask_asset_id'] as String?,
        timing: j['timing'] == null
            ? null
            : Timing.fromJson(j['timing'] as Map<String, dynamic>),
      );
}

class ObjectTextStyle {
  const ObjectTextStyle({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
  });

  final String fill;
  final String stroke;
  final double strokeWidth;

  ObjectTextStyle copyWith({String? fill, String? stroke, double? strokeWidth}) =>
      ObjectTextStyle(
        fill: fill ?? this.fill,
        stroke: stroke ?? this.stroke,
        strokeWidth: strokeWidth ?? this.strokeWidth,
      );

  Map<String, dynamic> toJson() => {
        'fill': fill,
        'stroke': stroke,
        'stroke_width': strokeWidth,
      };

  factory ObjectTextStyle.fromJson(Map<String, dynamic> j) => ObjectTextStyle(
        fill: j['fill'] as String,
        stroke: j['stroke'] as String,
        strokeWidth: (j['stroke_width'] as num).toDouble(),
      );
}

class TextObject implements CompositionObject {
  TextObject({
    required this.id,
    required this.text,
    required this.font,
    required this.fontSize,
    required this.transform,
    required this.style,
  });

  @override
  final String id;
  final String text;
  final String font;
  final double fontSize;
  @override
  final Transform2D transform;
  final ObjectTextStyle style;

  TextObject copyWith({
    String? text,
    String? font,
    double? fontSize,
    Transform2D? transform,
    ObjectTextStyle? style,
  }) =>
      TextObject(
        id: id,
        text: text ?? this.text,
        font: font ?? this.font,
        fontSize: fontSize ?? this.fontSize,
        transform: transform ?? this.transform,
        style: style ?? this.style,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'text',
        'text': text,
        'font': font,
        'font_size': fontSize,
        'transform': transform.toJson(),
        'style': style.toJson(),
      };

  factory TextObject.fromJson(Map<String, dynamic> j) => TextObject(
        id: j['id'] as String,
        text: j['text'] as String,
        font: j['font'] as String,
        fontSize: (j['font_size'] as num).toDouble(),
        transform: Transform2D.fromJson(j['transform'] as Map<String, dynamic>),
        style: ObjectTextStyle.fromJson(j['style'] as Map<String, dynamic>),
      );
}

class CanvasSpec {
  const CanvasSpec({
    this.width = canvasSize,
    this.height = canvasSize,
    this.background = 'transparent',
  });

  final int width;
  final int height;
  final Background background;

  CanvasSpec copyWith({Background? background}) => CanvasSpec(
        width: width,
        height: height,
        background: background ?? this.background,
      );

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'background': background,
      };

  factory CanvasSpec.fromJson(Map<String, dynamic> j) => CanvasSpec(
        width: j['width'] as int,
        height: j['height'] as int,
        background: j['background'] as String,
      );
}

class CompositionDocument {
  CompositionDocument({
    this.version = documentVersion,
    required this.canvas,
    required this.objects,
  });

  final int version;
  final CanvasSpec canvas;
  final List<CompositionObject> objects;

  CompositionDocument copyWith({
    CanvasSpec? canvas,
    List<CompositionObject>? objects,
  }) =>
      CompositionDocument(
        version: version,
        canvas: canvas ?? this.canvas,
        objects: objects ?? this.objects,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'canvas': canvas.toJson(),
        'objects': objects.map((o) => o.toJson()).toList(),
      };

  factory CompositionDocument.fromJson(Map<String, dynamic> j) {
    final objs = (j['objects'] as List<dynamic>).map((raw) {
      final m = raw as Map<String, dynamic>;
      final type = m['type'] as String;
      if (type == 'media') return MediaObject.fromJson(m);
      if (type == 'text') return TextObject.fromJson(m);
      throw FormatException('unknown object type: $type');
    }).toList();
    return CompositionDocument(
      version: j['version'] as int,
      canvas: CanvasSpec.fromJson(j['canvas'] as Map<String, dynamic>),
      objects: objs,
    );
  }
}

/// Export payload — parity with TS `ExportPayload`.
class ExportPayload {
  ExportPayload({
    required this.document,
    required this.chat,
    required this.thumbnail,
    required this.full,
    this.mask,
    this.background = 'transparent',
    this.mimeType = 'image/png',
  });

  final CompositionDocument document;
  final Uint8List chat;
  final Uint8List thumbnail;
  final Uint8List full;
  final Uint8List? mask;
  final Background background;
  final String mimeType;

  Map<String, Uint8List> get exports => {
        'chat': chat,
        'thumbnail': thumbnail,
        'full': full,
      };
}
