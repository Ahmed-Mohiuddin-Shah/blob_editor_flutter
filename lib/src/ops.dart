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
  double naturalHeight, [
  Background background = 'transparent',
]) {
  final scale = (canvasSize / naturalWidth < canvasSize / naturalHeight)
      ? canvasSize / naturalWidth
      : canvasSize / naturalHeight;
  final media = MediaObject(
    id: newObjectId('media'),
    assetId: assetId,
    transform: Transform2D(
      x: canvasSize / 2,
      y: canvasSize / 2,
      scaleX: scale,
      scaleY: scale,
      rotation: 0,
    ),
    crop: CropRect(x: 0, y: 0, width: naturalWidth, height: naturalHeight),
  );
  return CompositionDocument(
    canvas: CanvasSpec(background: background),
    objects: [media],
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
    return MediaObject(
      id: o.id,
      assetId: o.assetId,
      transform: o.transform,
      crop: crop,
      maskAssetId: o.maskAssetId,
      timing: o.timing,
    );
  });
}

CompositionDocument setBackground(
  CompositionDocument doc,
  Background background,
) {
  return doc.copyWith(canvas: doc.canvas.copyWith(background: background));
}

CompositionDocument applyMask(
  CompositionDocument doc,
  String id,
  String? maskAssetId,
) {
  return _mapObject(doc, id, (o) {
    if (o is! MediaObject) throw StateError('mask only on media');
    return o.copyWith(maskAssetId: maskAssetId, clearMask: maskAssetId == null);
  });
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
