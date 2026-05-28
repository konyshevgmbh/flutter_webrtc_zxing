import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'flutter_webrtc_zxing.dart';
import 'src/logic/zxing.dart';

export 'generated_bindings.dart';
export 'src/logic/zxing.dart';
export 'src/models/models.dart';
export 'src/utils/extentions.dart';
export 'src/utils/image_converter.dart';

Zxing getZxing() => ZxingMobile();

class ZxingMobile implements Zxing {
  ZxingMobile();

  @override
  String version() => zxingVersion();

  @override
  void setLogEnabled(bool enabled) => setZxingLogEnabled(enabled);

  @override
  String barcodeFormatName(int format) => zxingBarcodeFormatName(format);

  @override
  Future<Encode> encodeBarcode({
    required String contents,
    required EncodeParams params,
  }) async => zxingEncodeBarcode(contents: contents, params: params);

  @override
  Future<void> startCameraProcessing() => zxingStartCameraProcessing();

  @override
  void stopCameraProcessing() => zxingStopCameraProcessing();

  @override
  Future<Code> processWebRtcFrame(
    Uint8List encodedBytes,
    DecodeParams params, {
    double cropPercent = 0.5,
    double horizontalCropOffset = 0.0,
    double verticalCropOffset = 0.0,
  }) async =>
      await zxingProcessWebRtcFrame(
        encodedBytes,
        params,
        cropPercent: cropPercent,
        horizontalCropOffset: horizontalCropOffset,
        verticalCropOffset: verticalCropOffset,
      ) as Code;

  @override
  Future<Codes> processWebRtcFrameMulti(
    Uint8List encodedBytes,
    DecodeParams params, {
    double cropPercent = 0.5,
    double horizontalCropOffset = 0.0,
    double verticalCropOffset = 0.0,
  }) async =>
      await zxingProcessWebRtcFrame(
        encodedBytes,
        params,
        cropPercent: cropPercent,
        horizontalCropOffset: horizontalCropOffset,
        verticalCropOffset: verticalCropOffset,
      ) as Codes;

  @override
  Future<Code> readBarcodeImagePathString(String path, DecodeParams params) =>
      zxingReadBarcodeImagePathString(path, params);

  @override
  Future<Code> readBarcodeImagePath(XFile path, DecodeParams params) =>
      zxingReadBarcodeImagePath(path, params);

  @override
  Future<Code> readBarcodeImageUrl(String url, DecodeParams params) =>
      zxingReadBarcodeImageUrl(url, params);

  @override
  Code readBarcode(Uint8List bytes, DecodeParams params) =>
      zxingReadBarcode(bytes, params);

  @override
  Future<Codes> readBarcodesImagePathString(String path, DecodeParams params) =>
      zxingReadBarcodesImagePathString(path, params);

  @override
  Future<Codes> readBarcodesImagePath(XFile path, DecodeParams params) =>
      zxingReadBarcodesImagePath(path, params);

  @override
  Future<Codes> readBarcodesImageUrl(String url, DecodeParams params) =>
      zxingReadBarcodesImageUrl(url, params);

  @override
  Codes readBarcodes(Uint8List bytes, DecodeParams params) =>
      zxingReadBarcodes(bytes, params);
}
