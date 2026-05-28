import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'src/models/models.dart';

import 'zxing_cross.dart'
    if (dart.library.io) 'zxing_mobile.dart'
    if (dart.library.html) 'zxing_web.dart';

export 'src/models/models.dart';
export 'src/ui/ui.dart';
export 'src/utils/image_converter.dart';

final Zxing zx = Zxing();

abstract class Zxing {
  /// factory constructor to return the correct implementation.
  factory Zxing() => getZxing();

  String version() => '';
  void setLogEnabled(bool enabled) {}
  String barcodeFormatName(int format) => '';

  /// Creates barcode from the given contents
  Future<Encode> encodeBarcode({
    required String contents,
    required EncodeParams params,
  });

  /// Starts reading barcode from the camera
  Future<void> startCameraProcessing();

  /// Stops reading barcode from the camera
  void stopCameraProcessing();

  /// Reads barcode from a WebRTC video frame (encoded JPEG bytes from captureFrame())
  Future<Code> processWebRtcFrame(
    Uint8List encodedBytes,
    DecodeParams params, {
    double cropPercent,
    double horizontalCropOffset,
    double verticalCropOffset,
  });

  /// Reads barcodes from a WebRTC video frame (encoded JPEG bytes from captureFrame())
  Future<Codes> processWebRtcFrameMulti(
    Uint8List encodedBytes,
    DecodeParams params, {
    double cropPercent,
    double horizontalCropOffset,
    double verticalCropOffset,
  });

  /// Reads barcode from String image path
  Future<Code> readBarcodeImagePathString(String path, DecodeParams params);

  /// Reads barcode from XFile image path
  Future<Code> readBarcodeImagePath(XFile path, DecodeParams params);

  /// Reads barcode from image url
  Future<Code> readBarcodeImageUrl(String url, DecodeParams params);

  /// Reads barcode from Uint8List image bytes
  Code readBarcode(Uint8List bytes, DecodeParams params);

  /// Reads barcodes from String image path
  Future<Codes> readBarcodesImagePathString(String path, DecodeParams params);

  /// Reads barcodes from XFile image path
  Future<Codes> readBarcodesImagePath(XFile path, DecodeParams params);

  /// Reads barcodes from image url
  Future<Codes> readBarcodesImageUrl(String url, DecodeParams params);

  /// Reads barcodes from Uint8List image bytes
  Codes readBarcodes(Uint8List bytes, DecodeParams params);
}
