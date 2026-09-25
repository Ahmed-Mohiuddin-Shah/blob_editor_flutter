import 'document.dart';
import 'fonts.dart';

int _seq = 0;

String newObjectId([String prefix = 'obj']) {
  _seq += 1;
  return '${prefix}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_$_seq';
}

CompositionDocument createEmptyDocument([Background background = 'transparent']) {
  return CompositionDocument(
    canvas: CanvasSpec(background: background),
    objects: const [],
  );
}

CompositionDocument createFromSource(
  String assetId,
  double naturalWidth,
  double naturalHeight, {
  Background background = 'transparent',
  MediaKind kind = MediaKind.image,
  double? durationMs,
  double? fps,
}) {
  final bg = kind == MediaKind.video && background == 'transparent'
      ? '#000000'
      : background;
  final scale = (canvasSize / naturalWidth < canvasSize / naturalHeight)
      ? canvasSize / naturalWidth
      : canvasSize / naturalHeight;
  final dur = kind == MediaKind.image
      ? 0.0
      : (durationMs ?? 0).clamp(0, maxDurationMs).toDouble();
  final keep = kind == MediaKind.image || dur <= 0
      ? null
      : TimeRange(startMs: 0, endMs: dur);
  final media = MediaObject(
    id: newObjectId('media'),
    assetId: assetId,
    kind: kind,
    transform: Transform2D(
      x: canvasSize / 2,
      y: canvasSize / 2,
      scaleX: scale,
      scaleY: scale,
      rotation: 0,
    ),
    crop: CropRect(x: 0, y: 0, width: naturalWidth, height: naturalHeight),
    keep: keep,
  );
  return CompositionDocument(
    canvas: CanvasSpec(background: bg),
    objects: [media],
    durationMs: dur,
    fps: fps ?? (kind == MediaKind.video ? defaultFpsVideo : defaultFpsGif),
    audio: kind == MediaKind.video ? const AudioTrack(muteSource: true) : null,
  );
}

CompositionDocument _mapObject(
  CompositionDocument doc,
  String id,
  CompositionObject Function(CompositionObject) fn,
) {
  var found = false;
  final objects = doc.objects.map((o) {
    if (o.id != id) return o;
    found = true;
    return fn(o);
  }).toList();
  if (!found) throw StateError('object not found: $id');
  return doc.copyWith(objects: objects);
}

CompositionDocument updateTransform(
  CompositionDocument doc,
  String id, {
  double? x,
  double? y,
  double? scaleX,
  double? scaleY,
  double? rotation,
}) {
  return _mapObject(doc, id, (o) {
    final t = o.transform.copyWith(
      x: x,
      y: y,
      scaleX: scaleX,
      scaleY: scaleY,
      rotation: rotation,
    );
    if (o is MediaObject) return o.copyWith(transform: t);
    if (o is TextObject) return o.copyWith(transform: t);
    throw StateError('unknown object');
  });
}

CompositionDocument updateCrop(
  CompositionDocument doc,
  String id,
  CropRect? crop,
) {
  return _mapObject(doc, id, (o) {
    if (o is! MediaObject) throw StateError('crop only on media');
    return o.copyWith(crop: crop);
  });
}

CompositionDocument setBackground(
  CompositionDocument doc,
  Background background,
) {
  final hasVideo =
      doc.objects.any((o) => o is MediaObject && o.kind == MediaKind.video);
  if (hasVideo && background == 'transparent') {
    throw StateError('video canvas cannot be transparent');
  }
  return doc.copyWith(canvas: doc.canvas.copyWith(background: background));
}

CompositionDocument applyMask(
  CompositionDocument doc,
  String id,
  String? maskAssetId,
) {
  return _mapObject(doc, id, (o) {
    if (o is! MediaObject) throw StateError('mask only on media');
    if (o.kind != MediaKind.image) throw StateError('mask only on image');
    return o.copyWith(maskAssetId: maskAssetId, clearMask: maskAssetId == null);
  });
}

CompositionDocument setOutline(
  CompositionDocument doc,
  String id,
  OutlineStyle? outline,
) {
  return _mapObject(doc, id, (o) {
    if (o is! MediaObject) throw StateError('outline only on media');
    if (o.kind != MediaKind.image) throw StateError('outline only on image');
    return o.copyWith(outline: outline, clearOutline: outline == null);
  });
}

CompositionDocument setTrim(
  CompositionDocument doc,
  String id,
  double startMs,
  double endMs,
) {
  if (!(endMs > startMs)) throw StateError('trim endMs must be > startMs');
  return _mapObject(doc, id, (o) {
    if (o is! MediaObject) throw StateError('trim only on media');
    if (o.kind == MediaKind.image) throw StateError('trim not allowed on image');
    return o.copyWith(keep: TimeRange(startMs: startMs, endMs: endMs));
  });
}

CompositionDocument clearTrim(CompositionDocument doc, String id) {
  return _mapObject(doc, id, (o) {
    if (o is! MediaObject) throw StateError('trim only on media');
    return o.copyWith(clearKeep: true);
  });
}

CompositionDocument setKeep(
  CompositionDocument doc,
  String id,
  TimeRange? keep,
) {
  return _mapObject(doc, id, (o) {
    if (o is! MediaObject) throw StateError('keep only on media');
    return o.copyWith(keep: keep, clearKeep: keep == null);
  });
}

CompositionDocument syncDurationFromPrimary(CompositionDocument doc) {
  final medias = doc.objects.whereType<MediaObject>();
  final primary = medias.isEmpty ? null : medias.first;
  if (primary == null) return doc.copyWith(durationMs: 0);
  if (primary.kind == MediaKind.image && primary.keep == null) {
    return doc.copyWith(durationMs: 0);
  }
  final ms = primary.keep != null ? keepDurationMs(primary.keep) : doc.durationMs;
  return doc.copyWith(durationMs: ms.clamp(0, maxDurationMs.toDouble()));
}

CompositionDocument setAudio(CompositionDocument doc, AudioTrack? audio) {
  final hasVideo =
      doc.objects.any((o) => o is MediaObject && o.kind == MediaKind.video);
  if (audio != null && !hasVideo) {
    throw StateError('audio only on video compositions');
  }
  return doc.copyWith(audio: audio, clearAudio: audio == null);
}

CompositionDocument setMuteSource(CompositionDocument doc, bool mute) {
  return setAudio(doc, AudioTrack(muteSource: mute));
}

CompositionDocument addMedia(
  CompositionDocument doc, {
  required String assetId,
  required MediaKind kind,
  required double naturalWidth,
  required double naturalHeight,
  TimeRange? keep,
  String? id,
}) {
  if (kind == MediaKind.video) {
    throw StateError('cannot add video as overlay');
  }
  final hasVideo =
      doc.objects.any((o) => o is MediaObject && o.kind == MediaKind.video);
  if (hasVideo) {
    throw StateError('cannot add media overlays to a video composition');
  }
  final scale =
      (canvasSize / naturalWidth < canvasSize / naturalHeight
          ? canvasSize / naturalWidth
          : canvasSize / naturalHeight) *
      0.5;
  final media = MediaObject(
    id: id ?? newObjectId('media'),
    assetId: assetId,
    kind: kind,
    transform: Transform2D(
      x: canvasSize / 2,
      y: canvasSize / 2,
      scaleX: scale,
      scaleY: scale,
      rotation: 0,
    ),
    crop: CropRect(x: 0, y: 0, width: naturalWidth, height: naturalHeight),
    keep: keep,
  );
  return doc.copyWith(objects: [...doc.objects, media]);
}

CompositionDocument addText(
  CompositionDocument doc, {
  String? text,
  String? font,
  double? fontSize,
  Transform2D? transform,
  ObjectTextStyle? style,
  String? id,
}) {
  final obj = TextObject(
    id: id ?? newObjectId('text'),
    text: text ?? 'TOP TEXT',
    font: font ?? memeFont,
    fontSize: fontSize ?? 96,
    transform: transform ??
        const Transform2D(
          x: canvasSize / 2,
          y: 140,
          scaleX: 1,
          scaleY: 1,
          rotation: 0,
        ),
    style: style ??
        const ObjectTextStyle(
          fill: '#ffffff',
          stroke: '#000000',
          strokeWidth: 10,
        ),
  );
  return doc.copyWith(objects: [...doc.objects, obj]);
}

CompositionDocument updateText(
  CompositionDocument doc,
  String id, {
  String? text,
  String? font,
  double? fontSize,
  ObjectTextStyle? style,
}) {
  return _mapObject(doc, id, (o) {
    if (o is! TextObject) throw StateError('updateText only on text');
    return o.copyWith(
      text: text,
      font: font,
      fontSize: fontSize,
      style: style,
    );
  });
}

CompositionDocument removeObject(CompositionDocument doc, String id) {
  return doc.copyWith(
    objects: doc.objects.where((o) => o.id != id).toList(),
  );
}
