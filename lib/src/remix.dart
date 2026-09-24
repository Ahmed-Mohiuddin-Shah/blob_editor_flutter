import 'document.dart';

/// Deep-copy document for remix. Same asset_id refs; host owns persistence.
CompositionDocument remixDeepCopy(CompositionDocument source) {
  return CompositionDocument.fromJson(
    Map<String, dynamic>.from(source.toJson()),
  );
}
