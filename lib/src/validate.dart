import 'document.dart';

class DocumentValidationException implements Exception {
  DocumentValidationException(this.message);
  final String message;
  @override
  String toString() => 'DocumentValidationException: $message';
}

final _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

bool _isBackground(String v) => v == 'transparent' || _hex.hasMatch(v);

CompositionDocument validateDocument(Map<String, dynamic> raw) {
  final version = raw['version'];
  if (version != documentVersion && version != 1) {
    throw DocumentValidationException(
      'unsupported version (expected $documentVersion or 1)',
    );
  }
  final canvas = raw['canvas'] as Map<String, dynamic>?;
  if (canvas == null ||
      canvas['width'] != canvasSize ||
      canvas['height'] != canvasSize) {
    throw DocumentValidationException(
      'canvas must be ${canvasSize}x$canvasSize',
    );
  }
  final bg = canvas['background'] as String?;
  if (bg == null || !_isBackground(bg)) {
    throw DocumentValidationException(
      'canvas.background must be "transparent" or #RRGGBB',
    );
  }
  final objectsRaw = raw['objects'];
  if (objectsRaw is! List) {
    throw DocumentValidationException('objects must be an array');
  }
  final doc = CompositionDocument.fromJson(raw);
  final ids = doc.objects.map((o) => o.id).toSet();
  if (ids.length != doc.objects.length) {
    throw DocumentValidationException('object ids must be unique');
  }
  if (doc.durationMs < 0 || doc.durationMs > maxDurationMs) {
    throw DocumentValidationException('duration_ms invalid');
  }

  final medias = doc.objects.whereType<MediaObject>().toList();
  final videos = medias.where((m) => m.kind == MediaKind.video).toList();
  if (videos.length > 1) {
    throw DocumentValidationException('at most one video media object allowed');
  }
  if (videos.length == 1 && medias.length > 1) {
    throw DocumentValidationException(
      'video compositions cannot include other media overlays',
    );
  }
  if (videos.length == 1 && doc.canvas.background == 'transparent') {
    throw DocumentValidationException(
      'video canvas.background cannot be transparent',
    );
  }
  if (doc.audio != null && videos.isEmpty) {
    throw DocumentValidationException('audio only allowed on video compositions');
  }

  for (final m in medias) {
    if (m.kind != MediaKind.image) {
      if (m.maskAssetId != null) {
        throw DocumentValidationException(
          'mask_asset_id only allowed on image (${m.id})',
        );
      }
      if (m.outline != null) {
        throw DocumentValidationException(
          'outline only allowed on image (${m.id})',
        );
      }
    }
    if (m.keep != null && m.keep!.endMs <= m.keep!.startMs) {
      throw DocumentValidationException('keep invalid (${m.id})');
    }
  }

  return doc;
}
