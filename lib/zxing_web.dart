import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:image/image.dart' as imglib;
import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

import 'flutter_webrtc_zxing.dart';
import 'src/utils/dbg.dart';

// ── JS bridge declaration ────────────────────────────────────────────────────

// Calls window.flutterZxingReadBarcodes — injected at runtime by _ensureBridge()
@JS('flutterZxingReadBarcodes')
external JSPromise<JSString> _jsReadBarcodes(
  JSUint8Array bytes,
  JSString optionsJson,
);

// Calls window.flutterZxingWriteBarcode — injected at runtime by _ensureBridge()
@JS('flutterZxingWriteBarcode')
external JSPromise<JSString> _jsWriteBarcode(
  JSString content,
  JSString optionsJson,
);

// ── Bridge initialisation ────────────────────────────────────────────────────

// Flutter web serves plugin assets at this base path.
const String _assetBase = '/assets/packages/flutter_webrtc_zxing/lib/web/zxing';

// Inline ES-module that imports from the bundled assets and exposes
// window.flutterZxingReadBarcodes.  Injected once as <script type="module">.
const String _bridgeModule = '''
import { setZXingModuleOverrides, readBarcodesFromImageFile, writeBarcode }
  from "$_assetBase/index.js";

setZXingModuleOverrides({
  locateFile: (path, prefix) =>
    path.endsWith(".wasm") ? "$_assetBase/" + path : prefix + path,
});

window.flutterZxingReadBarcodes = async function(bytes, optionsJson) {
  const options = JSON.parse(optionsJson);
  const blob = new Blob([bytes], { type: "image/jpeg" });
  let results;
  try {
    results = await readBarcodesFromImageFile(blob, options);
  } catch (e) {
    console.error("[zxing-wasm]", e);
    return "[]";
  }
  return JSON.stringify(results.map(r => ({
    text:      r.text      ?? "",
    isValid:   r.isValid   ?? false,
    error:     r.error     ?? "",
    format:    r.format    ?? "None",
    isInverted:r.isInverted?? false,
    isMirrored:r.isMirrored?? false,
    position: r.position ? {
      topLeftX:     Math.round(r.position.topLeft.x),
      topLeftY:     Math.round(r.position.topLeft.y),
      topRightX:    Math.round(r.position.topRight.x),
      topRightY:    Math.round(r.position.topRight.y),
      bottomLeftX:  Math.round(r.position.bottomLeft.x),
      bottomLeftY:  Math.round(r.position.bottomLeft.y),
      bottomRightX: Math.round(r.position.bottomRight.x),
      bottomRightY: Math.round(r.position.bottomRight.y),
    } : null,
  })));
};

window.flutterZxingWriteBarcode = async function(content, optionsJson) {
  const options = JSON.parse(optionsJson);
  let result;
  try {
    result = await writeBarcode(content, options);
  } catch(e) {
    return JSON.stringify({ error: String(e), data: null });
  }
  if (result.error || !result.image) {
    return JSON.stringify({ error: result.error || "no image", data: null });
  }
  const ab = await result.image.arrayBuffer();
  const bytes = new Uint8Array(ab);
  // Convert to base64 in chunks to avoid call-stack limit
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return JSON.stringify({ error: '', data: btoa(binary) });
};

window.dispatchEvent(new CustomEvent("flutterZxingReady"));
''';

bool _bridgeReady = false;
Completer<void>? _bridgeLoading;

Future<void> _ensureBridge() async {
  if (_bridgeReady) {
    return;
  }
  if (_bridgeLoading != null) {
    dbg('[bridge] already loading — waiting…');
    return _bridgeLoading!.future;
  }

  dbg('[bridge] injecting <script type="module">');
  final Stopwatch sw = Stopwatch()..start();
  final Completer<void> completer = Completer<void>();
  _bridgeLoading = completer;

  final JSFunction handler = (web.Event _) {
    dbg('[bridge] flutterZxingReady received in ${sw.elapsedMilliseconds} ms');
    _bridgeReady = true;
    if (!completer.isCompleted) {
      completer.complete();
    }
  }.toJS;
  web.window.addEventListener('flutterZxingReady', handler);

  final web.HTMLScriptElement script =
      web.document.createElement('script') as web.HTMLScriptElement;
  script.type = 'module';
  script.text = _bridgeModule;
  web.document.head!.append(script);

  return completer.future;
}

// ── Format mapping ───────────────────────────────────────────────────────────

// zxing-wasm 1.x used "QR-Code" style names (matching zxing-cpp C++ API).
// zxing-wasm 2.x changed to camelCase / no-hyphen names. Both variants listed.
const Map<String, int> _nameToFormat = <String, int>{
  'Aztec': Format.aztec,
  'Codabar': Format.codabar,
  'Code39': Format.code39,      'Code-39': Format.code39,
  'Code93': Format.code93,      'Code-93': Format.code93,
  'Code128': Format.code128,    'Code-128': Format.code128,
  'DataBar': Format.dataBar,
  'DataBarExpanded': Format.dataBarExpanded,
  'DataMatrix': Format.dataMatrix,
  'EAN8': Format.ean8,          'EAN-8': Format.ean8,
  'EAN13': Format.ean13,        'EAN-13': Format.ean13,
  'ITF': Format.itf,
  'MaxiCode': Format.maxiCode,
  'PDF417': Format.pdf417,
  'QRCode': Format.qrCode,      'QR-Code': Format.qrCode,   'QR_CODE': Format.qrCode,
  'UPCA': Format.upca,          'UPC-A': Format.upca,
  'UPCE': Format.upce,          'UPC-E': Format.upce,
  'MicroQRCode': Format.microQRCode,
  'RMQRCode': Format.rmqrCode,  'rMQR-Code': Format.rmqrCode,
};

// Canonical names used by zxing-wasm 2.x for both reader format filter and writer format.
const Map<int, String> _formatToName = <int, String>{
  Format.aztec: 'Aztec',
  Format.codabar: 'Codabar',
  Format.code39: 'Code39',
  Format.code93: 'Code93',
  Format.code128: 'Code128',
  Format.dataBar: 'DataBar',
  Format.dataBarExpanded: 'DataBarExpanded',
  Format.dataMatrix: 'DataMatrix',
  Format.ean8: 'EAN-8',
  Format.ean13: 'EAN-13',
  Format.itf: 'ITF',
  Format.maxiCode: 'MaxiCode',
  Format.pdf417: 'PDF417',
  Format.qrCode: 'QRCode',
  Format.upca: 'UPC-A',
  Format.upce: 'UPC-E',
  Format.microQRCode: 'MicroQRCode',
  Format.rmqrCode: 'rMQRCode',
};

List<String> _maskToNames(int mask) {
  if (mask == Format.any || mask == 0) {
    return <String>[];
  }
  return _formatToName.entries
      .where((MapEntry<int, String> e) => mask & e.key != 0)
      .map((MapEntry<int, String> e) => e.value)
      .toList();
}

// ── Core WASM call ───────────────────────────────────────────────────────────

Future<List<Code>> _callWasm(Uint8List bytes, DecodeParams params) async {
  await _ensureBridge();

  final Map<String, dynamic> options = <String, dynamic>{
    'formats': _maskToNames(params.format),
    'tryHarder': params.tryHarder,
    'tryRotate': params.tryRotate,
    'tryInvert': params.tryInverted,
    'tryDownscale': params.tryDownscale,
    'maxNumberOfSymbols': params.maxNumberOfSymbols,
  };

  dbg('[wasm] call  ${bytes.length} bytes  formats=${options["formats"]}');
  final Stopwatch sw = Stopwatch()..start();
  final JSString jsResult = await _jsReadBarcodes(
    bytes.toJS,
    jsonEncode(options).toJS,
  ).toDart;
  final int duration = sw.elapsedMilliseconds;
  dbg('[wasm] done  $duration ms');

  final List<dynamic> raw = jsonDecode(jsResult.toDart) as List<dynamic>;
  dbg('[wasm] results=${raw.length}  valid=${raw.where((dynamic r) => (r as Map<String, dynamic>)["isValid"] == true).length}');
  return raw.map((dynamic item) {
    final Map<String, dynamic> m = item as Map<String, dynamic>;
    final String formatName = (m['format'] as String?) ?? '';
    dbg('[wasm] format raw="$formatName"  mapped=${_nameToFormat[formatName]}');
    final String? errorText = m['error'] as String?;

    Position? position;
    final dynamic pos = m['position'];
    if (pos != null) {
      final Map<String, dynamic> p = pos as Map<String, dynamic>;
      position = Position(
        0, 0,
        (p['topLeftX'] as num).toInt(),
        (p['topLeftY'] as num).toInt(),
        (p['topRightX'] as num).toInt(),
        (p['topRightY'] as num).toInt(),
        (p['bottomLeftX'] as num).toInt(),
        (p['bottomLeftY'] as num).toInt(),
        (p['bottomRightX'] as num).toInt(),
        (p['bottomRightY'] as num).toInt(),
      );
    }

    return Code(
      text: m['text'] as String?,
      isValid: (m['isValid'] as bool?) ?? false,
      error: errorText != null && errorText.isNotEmpty ? errorText : null,
      format: _nameToFormat[formatName] ?? Format.none,
      position: position,
      isInverted: (m['isInverted'] as bool?) ?? false,
      isMirrored: (m['isMirrored'] as bool?) ?? false,
      duration: duration,
    );
  }).toList();
}

// ── Image preparation (crop / resize) ────────────────────────────────────────

Future<Uint8List> _prepareBytes(
  Uint8List encodedBytes,
  DecodeParams params,
  double cropPercent,
  double horizontalCropOffset,
  double verticalCropOffset,
) async {
  if (cropPercent <= 0) {
    return encodedBytes;
  }

  imglib.Image? image = imglib.decodeImage(encodedBytes);
  if (image == null) {
    return encodedBytes;
  }
  image = resizeToMaxSize(image, params.maxSize);

  final int cropSize =
      (min(image.width, image.height) * cropPercent).round();
  if (cropSize > 0) {
    final int cropLeft =
        ((image.width - cropSize) ~/ 2 +
                (horizontalCropOffset * (image.width - cropSize) / 2))
            .round()
            .clamp(0, image.width - cropSize);
    final int cropTop =
        ((image.height - cropSize) ~/ 2 +
                (verticalCropOffset * (image.height - cropSize) / 2))
            .round()
            .clamp(0, image.height - cropSize);
    image = imglib.copyCrop(
      image,
      x: cropLeft,
      y: cropTop,
      width: cropSize,
      height: cropSize,
    );
  }

  return Uint8List.fromList(imglib.encodeJpg(image));
}

// ── ZxingWeb implementation ──────────────────────────────────────────────────

// ignore: avoid_classes_with_only_static_members
class FlutterWebrtcZxingPlugin {
  static void registerWith(Registrar registrar) {}
}

Zxing getZxing() => ZxingWeb();

class ZxingWeb implements Zxing {
  @override
  String version() => 'zxing-wasm (web)';

  @override
  void setLogEnabled(bool enabled) {}

  @override
  String barcodeFormatName(int format) =>
      _formatToName[format] ?? 'Unknown';

  @override
  Future<Encode> encodeBarcode({
    required String contents,
    required EncodeParams params,
  }) async {
    await _ensureBridge();

    final String formatName = _formatToName[params.format] ?? 'QRCode';
    // zxing-wasm WriterOptions: sizeHint (pixels), ecLevel ("L"/"M"/"Q"/"H"), withQuietZones
    const Map<int, String> eccMap = <int, String>{2: 'L', 4: 'M', 6: 'Q', 8: 'H'};
    final Map<String, dynamic> options = <String, dynamic>{
      'format': formatName,
      'sizeHint': params.width,
      'ecLevel': eccMap[params.eccLevel.value] ?? '',
      'withQuietZones': params.margin > 0,
    };

    dbg('[encode] $formatName ${params.width}x${params.height}');
    final Stopwatch sw = Stopwatch()..start();

    final JSString jsResult = await _jsWriteBarcode(
      contents.toJS,
      jsonEncode(options).toJS,
    ).toDart;
    dbg('[encode] done ${sw.elapsedMilliseconds} ms');

    final Map<String, dynamic> map =
        jsonDecode(jsResult.toDart) as Map<String, dynamic>;
    final String? error = map['error'] as String?;
    if (error != null && error.isNotEmpty) {
      dbg('[encode] ✗ error="$error"');
      return Encode(false, params.format, contents, null, 0, error);
    }

    // Return the PNG from zxing-wasm as-is.
    // WriterWidget detects PNG by magic bytes and uses Image.memory() directly,
    // avoiding the raw-grayscale path that would introduce gray antialiasing pixels.
    final Uint8List pngBytes = base64Decode(map['data'] as String);
    dbg('[encode] ✓ PNG ${pngBytes.length} bytes');
    return Encode(true, params.format, contents, pngBytes, pngBytes.length, null);
  }

  @override
  Future<void> startCameraProcessing() async {
    // Pre-load the WASM bridge so the first scan has no cold-start delay.
    await _ensureBridge();
  }

  @override
  void stopCameraProcessing() {}

  @override
  Future<Code> processWebRtcFrame(
    Uint8List encodedBytes,
    DecodeParams params, {
    double cropPercent = 0.5,
    double horizontalCropOffset = 0.0,
    double verticalCropOffset = 0.0,
  }) async {
    final Uint8List bytes = await _prepareBytes(
      encodedBytes,
      params,
      cropPercent,
      horizontalCropOffset,
      verticalCropOffset,
    );
    final List<Code> results = await _callWasm(bytes, params);
    return results.isNotEmpty ? results.first : Code();
  }

  @override
  Future<Codes> processWebRtcFrameMulti(
    Uint8List encodedBytes,
    DecodeParams params, {
    double cropPercent = 0.5,
    double horizontalCropOffset = 0.0,
    double verticalCropOffset = 0.0,
  }) async {
    final Uint8List bytes = await _prepareBytes(
      encodedBytes,
      params,
      cropPercent,
      horizontalCropOffset,
      verticalCropOffset,
    );
    final List<Code> codes = await _callWasm(bytes, params);
    return Codes(codes: codes.where((Code c) => c.isValid).toList());
  }

  @override
  Future<Code> readBarcodeImagePathString(
    String path,
    DecodeParams params,
  ) => readBarcodeImagePath(XFile(path), params);

  @override
  Future<Code> readBarcodeImagePath(XFile file, DecodeParams params) async {
    final Uint8List bytes = await file.readAsBytes();
    final List<Code> results = await _callWasm(bytes, params);
    return results.firstWhere((Code c) => c.isValid, orElse: Code.new);
  }

  @override
  Future<Code> readBarcodeImageUrl(String url, DecodeParams params) async {
    final Uint8List bytes = (await NetworkAssetBundle(
      Uri.parse(url),
    ).load(url)).buffer.asUint8List();
    final List<Code> results = await _callWasm(bytes, params);
    return results.firstWhere((Code c) => c.isValid, orElse: Code.new);
  }

  @override
  Code readBarcode(Uint8List bytes, DecodeParams params) =>
      throw UnsupportedError(
        'readBarcode is synchronous and cannot run on web. '
        'Use readBarcodeImagePath instead.',
      );

  @override
  Future<Codes> readBarcodesImagePathString(
    String path,
    DecodeParams params,
  ) => readBarcodesImagePath(XFile(path), params);

  @override
  Future<Codes> readBarcodesImagePath(XFile file, DecodeParams params) async {
    final Uint8List bytes = await file.readAsBytes();
    params.isMultiScan = true;
    final List<Code> codes = await _callWasm(bytes, params);
    return Codes(codes: codes.where((Code c) => c.isValid).toList());
  }

  @override
  Future<Codes> readBarcodesImageUrl(String url, DecodeParams params) async {
    final Uint8List bytes = (await NetworkAssetBundle(
      Uri.parse(url),
    ).load(url)).buffer.asUint8List();
    params.isMultiScan = true;
    final List<Code> codes = await _callWasm(bytes, params);
    return Codes(codes: codes.where((Code c) => c.isValid).toList());
  }

  @override
  Codes readBarcodes(Uint8List bytes, DecodeParams params) =>
      throw UnsupportedError(
        'readBarcodes is synchronous and cannot run on web. '
        'Use readBarcodesImagePath instead.',
      );
}
