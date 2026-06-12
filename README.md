# Flutter ZXing

Flutter ZXing is a high-performance Flutter plugin for scanning and generating QR codes and barcodes. Built on the powerful [ZXing C++ library](https://github.com/zxing-cpp/zxing-cpp), it provides fast and reliable barcode processing on **all Flutter platforms** — mobile, desktop, and web.

Camera access uses [flutter_webrtc](https://pub.dev/packages/flutter_webrtc), so the same scanning widget works on Android, iOS, macOS, Windows, Linux, and Web without any platform-specific code in your app.

> **Note:** This is an experimental fork of [khoren93/flutter_zxing](https://github.com/khoren93/flutter_zxing) that replaces the `camera` plugin with WebRTC for unified cross-platform camera support. If you don't need web or desktop camera scanning, the original package is simpler and more lightweight.

> **Alternative worth considering:** The [zxing2](https://pub.dev/packages/zxing2) package (scanning and generation) may be a better choice in many cases — it has noticeably better web performance and on native platforms the difference is often negligible. For an example of using `zxing2` together with `flutter_webrtc` for cross-platform camera scanning, see [flutter_webrtc_zxing2](https://github.com/konyshevgmbh/flutter_webrtc_zxing2).

---

## pub.dev

**[https://pub.dev/packages/flutter_webrtc_zxing](https://pub.dev/packages/flutter_webrtc_zxing)**

---

## Live Demo

**[https://konyshevgmbh.github.io/flutter_webrtc_zxing/](https://konyshevgmbh.github.io/flutter_webrtc_zxing/)**

---

## Table of Contents

- [Features](#features)
- [Supported Formats](#supported-formats)
- [Supported Platforms](#supported-platforms)
- [Getting Started](#getting-started)
- [Usage](#usage)
  - [ReaderWidget (recommended)](#readerwidget-recommended)
  - [Process frames manually](#process-frames-manually)
  - [Read from file or URL](#read-from-file-or-url)
  - [Generate barcodes](#generate-barcodes)
- [Web setup](#web-setup)
- [License](#license)

---

## Features

- Scan QR codes and barcodes from the **live camera stream on all platforms** (mobile, desktop, and web).
- Scan multiple barcodes at once.
- Read barcodes from an image file or URL.
- Generate QR codes and barcodes with customizable content and size.
- Returns the position and corner points of every detected barcode.
- Drop-in `ReaderWidget` with built-in scanner overlay, camera toggle, and gallery picker.

---

## Supported Formats

| Linear product | Linear industrial | Matrix             |
|----------------|-------------------|--------------------|
| UPC-A          | Code 39           | QR Code            |
| UPC-E          | Code 93           | Micro QR Code      |
| EAN-8          | Code 128          | rMQR Code          |
| EAN-13         | Codabar           | Aztec              |
| DataBar        | DataBar Expanded  | DataMatrix         |
|                | ITF               | PDF417             |
|                |                   | MaxiCode (partial) |

---

## Supported Platforms

| Platform | Scanning | Generating | Notes |
|----------|----------|------------|-------|
| Android  | ✅ | ✅ | API 21+. Tested. |
| iOS      | ⚠️ | ⚠️ | iOS 11+. Not personally tested — should work. |
| macOS    | ⚠️ | ⚠️ | Not personally tested — should work. |
| Windows  | ✅ | ✅ | Tested. |
| Linux    | ⚠️ | ⚠️ | Not personally tested — should work. |
| Web      | ✅ | ✅ | Tested. Uses [zxing-wasm](https://github.com/Sec-ant/zxing-wasm) — first scan has a cold-start delay while the WASM module loads (~300 ms). See [Web setup](#web-setup). |

---

## Getting Started

### Add as a dependency

```yaml
dependencies:
  flutter_webrtc_zxing: ^0.2.1
```

> **iOS / macOS note:** the plugin requires the `zxing-cpp` C++ sources in `ios/` and `macos/`. Run the setup script once after cloning:
>
> ```bash
> git clone --recursive https://github.com/konyshevgmbh/flutter_webrtc_zxing.git
> ./flutter_webrtc_zxing/scripts/update_ios_macos_src.sh
> ```
>
> Then add a local path override in your app:
>
> ```yaml
> dependency_overrides:
>   flutter_webrtc_zxing:
>     path: ./flutter_webrtc_zxing
> ```

### Run the example

```bash
git clone --recursive https://github.com/konyshevgmbh/flutter_webrtc_zxing.git
cd flutter_webrtc_zxing/example
flutter pub get
flutter run                  # mobile / desktop
flutter run -d chrome        # web
```

---

## Usage

### ReaderWidget (recommended)

Drop `ReaderWidget` anywhere in your widget tree — it handles camera initialisation, WebRTC setup, and barcode detection automatically.

```dart
import 'package:flutter_webrtc_zxing/flutter_webrtc_zxing.dart';

ReaderWidget(
  onScan: (Code result) {
    debugPrint('Scanned: ${result.text}  format: ${result.format}');
  },
  onScanFailure: (Code result) {
    // called every tick when nothing is found
  },

  // Optional tuning
  codeFormat: Format.any,       // filter to specific format(s)
  tryHarder: false,
  tryInverted: false,
  cropPercent: 0.5,             // centre crop (0 = full frame)
  scanDelay: Duration(milliseconds: 500),
  useFrontCamera: false,
  targetFps: 10,
)
```

**Multi-scan** (several codes at once):

```dart
ReaderWidget(
  isMultiScan: true,
  onMultiScan: (Codes results) {
    for (final code in results.codes) {
      debugPrint('${code.text}');
    }
  },
)
```

### Process frames manually

Use this when you already have a WebRTC stream and want to scan frames yourself:

```dart
await zx.startCameraProcessing();   // starts the processing isolate

// inside your frame callback — encodedBytes is Uint8List from RTCVideoTrack.captureFrame()
final Code result = await zx.processWebRtcFrame(
  encodedBytes,
  DecodeParams(format: Format.qrCode),
  cropPercent: 0.5,
);
if (result.isValid) debugPrint(result.text);

zx.stopCameraProcessing();          // call in dispose
```

### Read from file or URL

```dart
// From XFile (e.g. image_picker result)
final Code result = await zx.readBarcodeImagePath(xFile, DecodeParams());

// From local path string
final Code result = await zx.readBarcodeImagePathString('/path/to/image.jpg', DecodeParams());

// From remote URL
final Code result = await zx.readBarcodeImageUrl('https://example.com/qr.png', DecodeParams());

// From raw bytes (native only — use readBarcodeImagePath on web)
final Code result = zx.readBarcode(bytes, DecodeParams(imageFormat: ImageFormat.rgb));
```

### Generate barcodes

```dart
import 'package:flutter_webrtc_zxing/flutter_webrtc_zxing.dart';
import 'package:image/image.dart' as imglib;

final Encode result = zx.encodeBarcode(
  contents: 'https://example.com',
  params: EncodeParams(
    format: Format.qrCode,
    width: 256,
    height: 256,
    margin: 10,
    eccLevel: EccLevel.medium,
  ),
);

if (result.isValid && result.data != null) {
  final img = imglib.Image.fromBytes(
    width: result.width!,
    height: result.height!,
    bytes: result.data!.buffer,
    numChannels: 1,
  );
  final Uint8List png = imglib.encodePng(img);
  // display or save png
}

// Or use the built-in widget
WriterWidget(
  onSuccess: (Encode result, Uint8List? bytes) { },
  onError: (String error) { },
)
```

---

## Web setup

On web the library loads a pre-built [zxing-wasm](https://github.com/Sec-ant/zxing-wasm) module from your Flutter asset bundle — **no CDN, no external scripts, no `index.html` changes needed**.

The bundled files live in `lib/web/` and are declared as Flutter assets in the library's `pubspec.yaml`. They are served automatically alongside your app.

### Updating the WASM bundle

When you want to upgrade to a newer `zxing-wasm` version:

```bash
VERSION=2.2.4   # replace with target version

curl -L https://cdn.jsdelivr.net/npm/zxing-wasm@${VERSION}/dist/es/share.js         -o lib/web/share.js
curl -L https://cdn.jsdelivr.net/npm/zxing-wasm@${VERSION}/dist/es/full/index.js    -o lib/web/zxing/index.js
curl -L https://cdn.jsdelivr.net/npm/zxing-wasm@${VERSION}/dist/full/zxing_full.wasm -o lib/web/zxing/zxing_full.wasm
```

Then update the version in [`lib/web/zxing/version.txt`](lib/web/zxing/version.txt).

---

## License

MIT. See [LICENSE](LICENSE).

Original work © 2022 Khoren Markosyan. Modifications © 2025 Igor Konyshev.
