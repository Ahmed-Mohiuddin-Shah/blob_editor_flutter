import 'dart:typed_data';

/// BLOB Composition document — mirrors TS `blob-editor` core (v2, simplified).

const int documentVersion = 2;
const int canvasSize = 1024;
const int maxDurationMs = 10000;
const double defaultFpsGif = 15;
const double defaultFpsVideo = 24;

typedef Background = String; // "transparent" | "#RRGGBB"

enum MediaKind { image, gif, video }

extension MediaKindJson on MediaKind {
  String get json => name;
  static MediaKind parse(String? v) {
    switch (v) {
      case 'gif':
        return MediaKind.gif;
      case 'video':
        return MediaKind.video;
      default:
        return MediaKind.image;
    }
  }
}

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

  CropRect copyWith({double? x, double? y, double? width, double? height}) =>
      CropRect(
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
      );

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

class TimeRange {
  const TimeRange({required this.startMs, required this.endMs});
  final double startMs;
  final double endMs;

  double get durationMs => (endMs - startMs).clamp(0, double.infinity);

  Map<String, dynamic> toJson() => {'start_ms': startMs, 'end_ms': endMs};

  factory TimeRange.fromJson(Map<String, dynamic> j) => TimeRange(
        startMs: (j['start_ms'] as num).toDouble(),
        endMs: (j['end_ms'] as num).toDouble(),
      );
}

class OutlineStyle {
  const OutlineStyle({required this.color, required this.width});
  final String color;
  final double width;

  Map<String, dynamic> toJson() => {'color': color, 'width': width};

  factory OutlineStyle.fromJson(Map<String, dynamic> j) => OutlineStyle(
        color: j['color'] as String,
        width: (j['width'] as num).toDouble(),
      );
}

class AudioTrack {
  const AudioTrack({required this.muteSource});
  final bool muteSource;

  AudioTrack copyWith({bool? muteSource}) =>
      AudioTrack(muteSource: muteSource ?? this.muteSource);

  Map<String, dynamic> toJson() => {'mute_source': muteSource};

  factory AudioTrack.fromJson(Map<String, dynamic> j) => AudioTrack(
        muteSource: j['mute_source'] as bool? ?? true,
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
    required this.kind,
    required this.transform,
    this.crop,
    this.maskAssetId,
    this.keep,
    this.outline,
  });

  @override
  final String id;
  final String assetId;
  final MediaKind kind;
  @override
  final Transform2D transform;
  final CropRect? crop;
  final String? maskAssetId;
  /// Single-range trim. null = full source.
  final TimeRange? keep;
  final OutlineStyle? outline;

  MediaObject copyWith({
    Transform2D? transform,
    CropRect? crop,
    String? maskAssetId,
    bool clearMask = false,
    TimeRange? keep,
    bool clearKeep = false,
    OutlineStyle? outline,
    bool clearOutline = false,
    MediaKind? kind,
  }) =>
      MediaObject(
        id: id,
        assetId: assetId,
        kind: kind ?? this.kind,
        transform: transform ?? this.transform,
        crop: crop ?? this.crop,
        maskAssetId: clearMask ? null : (maskAssetId ?? this.maskAssetId),
        keep: clearKeep ? null : (keep ?? this.keep),
        outline: clearOutline ? null : (outline ?? this.outline),
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'media',
        'asset_id': assetId,
        'kind': kind.json,
        'transform': transform.toJson(),
        'crop': crop?.toJson(),
        'mask_asset_id': maskAssetId,
        'keep': keep?.toJson(),
        'outline': outline?.toJson(),
      };

  factory MediaObject.fromJson(Map<String, dynamic> j) {
    TimeRange? keep = _coerceKeep(j['keep']);
    if (keep == null && j['timing'] is Map) {
      final t = j['timing'] as Map<String, dynamic>;
      var start = (t['start'] as num).toDouble();
      var end = (t['end'] as num).toDouble();
      if (end <= 120 && start < 120) {
        start *= 1000;
        end *= 1000;
      }
      if (end > start) keep = TimeRange(startMs: start, endMs: end);
    }
    return MediaObject(
      id: j['id'] as String,
      assetId: j['asset_id'] as String,
      kind: MediaKindJson.parse(j['kind'] as String?),
      transform: Transform2D.fromJson(j['transform'] as Map<String, dynamic>),
      crop: j['crop'] == null
          ? null
          : CropRect.fromJson(j['crop'] as Map<String, dynamic>),
      maskAssetId: j['mask_asset_id'] as String?,
      keep: keep,
      outline: j['outline'] == null
          ? null
          : OutlineStyle.fromJson(j['outline'] as Map<String, dynamic>),
    );
  }
}

TimeRange? _coerceKeep(dynamic raw) {
  if (raw == null) return null;
  if (raw is List) {
    if (raw.isEmpty) return null;
    final first = raw.first;
    if (first is! Map) return null;
    final r = TimeRange.fromJson(Map<String, dynamic>.from(first));
    return r.endMs > r.startMs ? r : null;
  }
  if (raw is Map) {
    final r = TimeRange.fromJson(Map<String, dynamic>.from(raw));
    return r.endMs > r.startMs ? r : null;
  }
  return null;
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
    this.durationMs = 0,
    this.fps = defaultFpsGif,
    this.audio,
  });

  final int version;
  final CanvasSpec canvas;
  final List<CompositionObject> objects;
  final double durationMs;
  final double fps;
  final AudioTrack? audio;

  CompositionDocument copyWith({
    CanvasSpec? canvas,
    List<CompositionObject>? objects,
    double? durationMs,
    double? fps,
    AudioTrack? audio,
    bool clearAudio = false,
  }) =>
      CompositionDocument(
        version: version,
        canvas: canvas ?? this.canvas,
        objects: objects ?? this.objects,
        durationMs: durationMs ?? this.durationMs,
        fps: fps ?? this.fps,
        audio: clearAudio ? null : (audio ?? this.audio),
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'canvas': canvas.toJson(),
        'objects': objects.map((o) => o.toJson()).toList(),
        'duration_ms': durationMs,
        'fps': fps,
        'audio': audio?.toJson(),
      };

  factory CompositionDocument.fromJson(Map<String, dynamic> j) {
    final ver = j['version'] as int? ?? 1;
    final objs = (j['objects'] as List<dynamic>).map((raw) {
      final m = raw as Map<String, dynamic>;
      final type = m['type'] as String;
      if (type == 'media') return MediaObject.fromJson(m);
      if (type == 'text') return TextObject.fromJson(m);
      throw FormatException('unknown object type: $type');
    }).toList();

    final medias = objs.whereType<MediaObject>();
    final primary = medias.isEmpty ? null : medias.first;
    AudioTrack? audio;
    if (primary?.kind == MediaKind.video && j['audio'] is Map) {
      audio = AudioTrack.fromJson(j['audio'] as Map<String, dynamic>);
    }

    return CompositionDocument(
      version: ver == 1 ? documentVersion : ver,
      canvas: CanvasSpec.fromJson(j['canvas'] as Map<String, dynamic>),
      objects: objs,
      durationMs: (j['duration_ms'] as num?)?.toDouble() ?? 0,
      fps: (j['fps'] as num?)?.toDouble() ?? defaultFpsGif,
      audio: audio,
    );
  }
}

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

double keepDurationMs(TimeRange? keep) {
  if (keep == null) return 0;
  return keep.durationMs;
}

/// @deprecated alias
double keepTotalMs(TimeRange? keep) => keepDurationMs(keep);

double? mapCompToSource(TimeRange? keep, double tMs) {
  if (keep == null) return tMs;
  final d = keep.durationMs;
  if (tMs < 0 || tMs >= d) return null;
  return keep.startMs + tMs;
}
