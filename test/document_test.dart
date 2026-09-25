import 'package:blob_editor/blob_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateDocument', () {
    test('accepts empty doc', () {
      final doc = createEmptyDocument();
      expect(validateDocument(doc.toJson()).version, 2);
    });

    test('migrates v1', () {
      final doc = validateDocument({
        'version': 1,
        'canvas': {'width': 1024, 'height': 1024, 'background': 'transparent'},
        'objects': [],
      });
      expect(doc.version, 2);
      expect(doc.durationMs, 0);
    });

    test('rejects wrong canvas', () {
      expect(
        () => validateDocument({
          'version': 2,
          'canvas': {'width': 100, 'height': 100, 'background': 'transparent'},
          'objects': [],
          'duration_ms': 0,
          'fps': 15,
          'audio': null,
        }),
        throwsA(isA<DocumentValidationException>()),
      );
    });

    test('rejects bad background', () {
      expect(
        () => validateDocument({
          'version': 2,
          'canvas': {'width': 1024, 'height': 1024, 'background': 'red'},
          'objects': [],
          'duration_ms': 0,
          'fps': 15,
          'audio': null,
        }),
        throwsA(isA<DocumentValidationException>()),
      );
    });

    test('rejects transparent bg on video', () {
      final doc = createFromSource(
        'v1',
        100,
        100,
        kind: MediaKind.video,
        durationMs: 2000,
        background: '#000000',
      );
      final raw = doc.toJson();
      (raw['canvas'] as Map)['background'] = 'transparent';
      expect(
        () => validateDocument(raw),
        throwsA(isA<DocumentValidationException>()),
      );
    });

    test('rejects video with image overlay', () {
      final doc = createFromSource(
        'v1',
        100,
        100,
        kind: MediaKind.video,
        durationMs: 2000,
        background: '#000000',
      );
      final raw = doc.toJson();
      (raw['objects'] as List).add({
        'id': 'm2',
        'type': 'media',
        'asset_id': 'a2',
        'kind': 'image',
        'transform': {
          'x': 0,
          'y': 0,
          'scale_x': 1,
          'scale_y': 1,
          'rotation': 0,
        },
        'crop': null,
        'mask_asset_id': null,
        'keep': null,
        'outline': null,
      });
      expect(
        () => validateDocument(raw),
        throwsA(isA<DocumentValidationException>()),
      );
    });

    test('rejects mask on gif', () {
      final doc = createFromSource(
        'g1',
        100,
        100,
        kind: MediaKind.gif,
        durationMs: 2000,
      );
      final raw = doc.toJson();
      (raw['objects'] as List).first['mask_asset_id'] = 'mask1';
      expect(
        () => validateDocument(raw),
        throwsA(isA<DocumentValidationException>()),
      );
    });
  });

  group('ops', () {
    test('createFromSource centers and scales', () {
      final doc = createFromSource('a1', 1920, 1080);
      expect(doc.objects, hasLength(1));
      final m = doc.objects.first as MediaObject;
      expect(m.kind, MediaKind.image);
      expect(m.transform.x, canvasSize / 2);
      expect(m.transform.scaleX, closeTo(1024 / 1920, 1e-9));
    });

    test('createFromSource video sets duration and mute', () {
      final doc = createFromSource(
        'v1',
        100,
        100,
        kind: MediaKind.video,
        durationMs: 5000,
      );
      expect(doc.durationMs, 5000);
      expect(doc.canvas.background, '#000000');
      expect(doc.audio?.muteSource, isTrue);
      final m = doc.objects.first as MediaObject;
      expect(m.kind, MediaKind.video);
      expect(m.keep, isNotNull);
      expect(m.keep!.startMs, 0);
      expect(m.keep!.endMs, 5000);
    });

    test('updateTransform / setBackground / addText / applyMask / outline', () {
      var doc = createFromSource('a1', 100, 100);
      final id = doc.objects.first.id;
      doc = updateTransform(doc, id, rotation: 45);
      doc = setBackground(doc, '#ff00aa');
      doc = applyMask(doc, id, 'mask1');
      doc = setOutline(doc, id, const OutlineStyle(color: '#ffffff', width: 8));
      doc = addText(doc, text: 'HI');
      expect(doc.canvas.background, '#ff00aa');
      expect(doc.objects, hasLength(2));
      final media = doc.objects.first as MediaObject;
      expect(media.transform.rotation, 45);
      expect(media.maskAssetId, 'mask1');
      expect(media.outline?.width, 8);
    });

    test('setTrim syncs duration', () {
      var doc = createFromSource(
        'g1',
        100,
        100,
        kind: MediaKind.gif,
        durationMs: 4000,
      );
      final id = doc.objects.first.id;
      doc = setTrim(doc, id, 500, 2500);
      doc = syncDurationFromPrimary(doc);
      expect(doc.durationMs, 2000);
    });

    test('rejects video overlay and mask on gif', () {
      final img = createFromSource('a1', 100, 100);
      expect(
        () => addMedia(
          img,
          assetId: 'v',
          kind: MediaKind.video,
          naturalWidth: 50,
          naturalHeight: 50,
        ),
        throwsStateError,
      );
      final gif = createFromSource(
        'g1',
        100,
        100,
        kind: MediaKind.gif,
        durationMs: 1000,
      );
      expect(
        () => applyMask(gif, gif.objects.first.id, 'm'),
        throwsStateError,
      );
    });

    test('collapses multi-range keep on fromJson', () {
      final doc = CompositionDocument.fromJson({
        'version': 2,
        'canvas': {'width': 1024, 'height': 1024, 'background': 'transparent'},
        'objects': [
          {
            'id': 'm1',
            'type': 'media',
            'asset_id': 'a',
            'kind': 'gif',
            'transform': {
              'x': 0,
              'y': 0,
              'scale_x': 1,
              'scale_y': 1,
              'rotation': 0,
            },
            'keep': [
              {'start_ms': 0, 'end_ms': 500},
              {'start_ms': 1000, 'end_ms': 1500},
            ],
          },
        ],
        'duration_ms': 1000,
        'fps': 15,
      });
      final m = doc.objects.first as MediaObject;
      expect(m.keep?.startMs, 0);
      expect(m.keep?.endMs, 500);
    });
  });

  group('timing', () {
    test('mapCompToSource single range', () {
      const keep = TimeRange(startMs: 1000, endMs: 3000);
      expect(keepDurationMs(keep), 2000);
      expect(mapCompToSource(keep, 0), 1000);
      expect(mapCompToSource(keep, 500), 1500);
      expect(mapCompToSource(keep, 2000), isNull);
    });
  });

  group('remixDeepCopy', () {
    test('deep-copies and keeps asset ids', () {
      final src = createFromSource('shared', 50, 50);
      final copy = remixDeepCopy(src);
      expect(copy.toJson(), src.toJson());
      expect(identical(copy, src), isFalse);
      expect((copy.objects.first as MediaObject).assetId, 'shared');
    });
  });

  test('exportSizes locked', () {
    expect(exportSizes, {'chat': 128, 'thumbnail': 256, 'full': 1024});
  });
}
