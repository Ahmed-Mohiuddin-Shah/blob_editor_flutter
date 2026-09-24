# blob_editor

Flutter / Dart package for **BLOB Composition** — same JSON document contract as the npm `blob-editor` package. Drop-in `BlobEditor` widget with built-in gallery pick.

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
  // omit sourceAsset → ImagePicker gallery
  primary: Color(0xFFF10EA0),
  secondary: Color(0xFFE95214),
  onPrimary: Colors.white,
  onSecondary: Colors.white,
  blocky: false, // true = sharp corners; false = Blobby soft radii
  themeMode: BlobThemeMode.system, // light | dark | system
  onCancel: () {},
  onExport: (ExportPayload p) {
    // p.document — versioned Composition JSON
    // p.chat (128), p.thumbnail (256), p.full (1024) — PNG Uint8List
    // host uploads / persists; editor does not talk to BLOB/GLASS
  },
)
```

### Props (parity with TS)

| Prop | Meaning |
|------|---------|
| `sourceAsset?` | `ImageProvider`. If omitted (and no usable `document` media), opens gallery. |
| `document?` | Initial composition JSON `Map` (edit / remix). |
| `primary` / `onPrimary` / `secondary` / `onSecondary` | Theme colors |
| `blocky` | `true` = sharp square chrome; `false` = Blobby soft radii |
| `themeMode` | `BlobThemeMode.light` \| `.dark` \| `.system` (default). Frosted glass chrome. |
| `onExport` | `ExportPayload` with `document` + `chat` / `thumbnail` / `full` |
| `onCancel?` | Dismiss without export |

## Android permissions

Host / example apps that use the built-in picker need:

```xml
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<uses-permission
    android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32" />
```

`image_picker` prompts at runtime on modern Android. See `example/android/app/src/main/AndroidManifest.xml`.

## Core (no UI)

```dart
import 'package:blob_editor/blob_editor.dart';

final doc = createFromSource('asset_1', 1920, 1080);
validateDocument(doc.toJson());
final copy = remixDeepCopy(doc);
// renderExports(doc, (id) => myUiImage);
```

- `exportSizes`: `{ chat: 128, thumbnail: 256, full: 1024 }`
- Preview ≡ export: one 1024 draw, then scale
- Smart cutout hook: `applyMask(doc, id, maskAssetId)`

## Text / meme font

Default face is **Anton** via `google_fonts` (portable Impact stand-in). Add text → inspector for content, size, fill, outline. Drag/pinch still moves the selected layer.

## Example (Android)

```bash
cd blob_editor_flutter
flutter pub get
cd example && flutter run
```

## Tests

```bash
flutter test
flutter analyze
```

## Document sketch

Same as `docs/blob-requirements.md` §7.1 / npm `blob-editor` — `version`, `canvas` 1024², `objects[]` media/text. JSON field names use snake_case (`scale_x`, `asset_id`, …).
