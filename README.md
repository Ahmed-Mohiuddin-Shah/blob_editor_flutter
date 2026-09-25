# blob_editor

Flutter / Dart package for **BLOB Composition** — same JSON document contract (**v2**) as the npm [`blob-editor`](https://www.npmjs.com/package/blob-editor) package — plus sibling **`PrintLayout`** for printable sticker sheets. Drop-in `BlobEditor` widget with built-in media pick.

**UI only for animated output:** `onExport` returns document + still PNGs (+ optional mask). Host POSTs to server; Node worker runs `blob-editor/encode` → gif/mp4.

| Platform | Support |
|----------|---------|
| Android | API 21+ (primary) |
| iOS | Scaffold present; not maintained this release |

## Install

```yaml
dependencies:
  blob_editor: ^0.1.0
```

```bash
flutter pub add blob_editor
```

Requires Flutter **3.47.x** / Dart **3.13.x**.

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
  onExport: (ExportPayload p) {
    // p.document — Composition JSON v2
    // p.chat / thumbnail / full — still PNG Uint8List
    // p.mask — baked cutout alpha when brush/polygon/outline used
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
| `onExport` | `ExportPayload` with `document` + stills + optional `mask` |
| `onCancel?` | Dismiss without export |

Kind-gated UI (image ⊃ gif ⊃ video): crop/scale/rotate/text/undo; BG + multi for image/gif; **brush + polygon mask + outline** for image; trim for gif/video; mute for video.

### Cutout (images)

- **Brush add / remove** — paint keep/cut alpha on the stage (precise cursor; pan disabled while active). Brush size slider 8–64 (default 28).
- **Polygon** — tap ≥3 points (auto-closes), then **Apply mask** to intersect the keep region with any existing mask.
- **Apply mask** — commits the live brush/polygon session and exits the tool. Esc cancels in-progress polygon points.
- **Clear mask** — drops `mask_asset_id`.
- **White sticker border** — optional outline with width slider (2–32).

Stage composites the same mask as export previews (`dstIn`). No in-package ML / auto remove-BG.

### Layout

Chrome: **header** (Cancel / Undo / Redo / Export) + **tool categories** with a **collapsible submenu**.

Categories (kind / selection gated): Transform · Crop · Cutout · Text · Canvas.

- **Narrow** (&lt;720px **or** unbounded height): previews → stage → timeline (if animated) → submenu panel → bottom category nav.
- **Wide** (≥720px **and** bounded height from host, e.g. `Expanded`): tool nav + panel left \| stage + timeline center \| previews right.

Timeline sits under the stage when `duration_ms > 0`, not inside the submenu. Put `BlobEditor` in an `Expanded` (or other bounded-height host) to enable the wide layout — a `ListView` host stays narrow even on wide tablets.

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
- `renderMaskPng` / `renderExports` — stills + optional mask PNG

## Document sketch

`version: 2`, snake_case JSON (`scale_x`, `asset_id`, `start_ms`, …). Canvas 1024²; objects carry media `kind` / single `keep` trim / `mask_asset_id` / `outline`.

## Print layout

```dart
PrintLayout(
  assets: [PrintAssetMeta(id: 's1', label: 'Cat')],
  resolveAsset: (id) async => /* decode sticker full PNG */,
  onExport: (PrintExportPayload p) {
    // p.document.toJson() — PrintDocument v1 (mm page)
    // p.previewPng — sheet preview; PDF via Node encodePrint
  },
)
```

Core helpers: `pageA4`, `layoutGrid`, `validatePrintDocument`, `renderPrintPng`.

## License

MIT
