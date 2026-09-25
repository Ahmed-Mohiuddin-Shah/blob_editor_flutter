# blob_editor

Flutter / Dart package for **BLOB Composition** — same JSON document contract (**v2**) as the npm `blob-editor` package. Drop-in `BlobEditor` widget with built-in media pick.

**UI only for animated output:** `onExport` returns document + still PNGs. Host POSTs to server; Node worker runs `blob-editor/encode` → gif/mp4. See [`docs/diff.md`](../docs/diff.md).

## Requirements

| Tool | Pin / note |
|------|------------|
| Flutter | **3.47.x** (stable; package developed on 3.47.5) |
| Dart | **3.13.x** (`sdk: ^3.13.4`) |
| Android | API 21+; gallery permissions below |
| iOS | Folder may exist; **not maintained** this pass |

## Drop-in usage

```dart
import 'package:blob_editor/blob_editor.dart';

BlobEditor(
  primary: Color(0xFFF10EA0),
  secondary: Color(0xFFE95214),
  onPrimary: Colors.white,
  onSecondary: Colors.white,
  blocky: false,
  themeMode: BlobThemeMode.system,
  onCancel: () {},
  onRemoveBackground: (assetId) async {
    // host/worker segmentation → mask PNG bytes (or null to cancel)
    return null;
  },
  onExport: (ExportPayload p) {
    // p.document — Composition JSON v2
    // p.chat / thumbnail / full — still PNG Uint8List
    // upload document + assets; server encodes gif/video
  },
)
```

### Props (parity with TS)

| Prop | Meaning |
|------|---------|
| `sourceAsset?` | `ImageProvider`. If omitted, opens media picker. |
| `document?` | Initial composition JSON `Map` (edit / remix); v1 migrates. |
| `primary` / `onPrimary` / `secondary` / `onSecondary` | Theme colors |
| `blocky` | `true` = sharp; `false` = Blobby soft radii |
| `themeMode` | `BlobThemeMode.light` \| `.dark` \| `.system` |
| `onRemoveBackground?` | Host cutout: `(assetId) → Future<Uint8List?>` |
| `onExport` | `ExportPayload` with `document` + stills |
| `onCancel?` | Dismiss without export |

Kind-gated UI (image ⊃ gif ⊃ video): crop/scale/rotate/text/undo; BG + multi for image/gif; remove-BG/brush/outline for image; trim for gif/video; mute for video.

## Android permissions

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />
<uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
<uses-permission
    android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
```

## Core (no UI)

```dart
import 'package:blob_editor/blob_editor.dart';

final doc = createFromSource('asset_1', 1920, 1080, kind: MediaKind.video, durationMs: 5000);
validateDocument(doc.toJson());
```

- `exportSizes`: `{ chat: 128, thumbnail: 256, full: 1024 }`
- `paintComposition(..., tMs:)` / `renderFrameImage` for timed preview

## Document sketch

`version: 2`, snake_case JSON (`scale_x`, `asset_id`, `start_ms`, …). Full field map in `docs/diff.md`.
