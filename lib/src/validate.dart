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
  if (version != documentVersion) {
    throw DocumentValidationException(
      'unsupported version (expected $documentVersion)',
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
  return doc;
}
