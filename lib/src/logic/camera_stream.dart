part of 'zxing.dart';

IsolateUtils? isolateUtils;

/// Starts the barcode processing isolate
Future<void> zxingStartCameraProcessing() async {
  if (isolateUtils != null) {
    return;
  }
  isolateUtils = IsolateUtils();
  await isolateUtils?.startReadingBarcode();
}

/// Stops the barcode processing isolate
void zxingStopCameraProcessing() {
  isolateUtils?.stopReadingBarcode();
  isolateUtils = null;
}

/// Processes a WebRTC video frame (encoded bytes from captureFrame())
Future<dynamic> zxingProcessWebRtcFrame(
  Uint8List encodedBytes,
  DecodeParams params, {
  double cropPercent = 0.5,
  double horizontalCropOffset = 0.0,
  double verticalCropOffset = 0.0,
}) => _inference(
  IsolateData(
    encodedBytes,
    params,
    cropPercent: cropPercent,
    horizontalCropOffset: horizontalCropOffset,
    verticalCropOffset: verticalCropOffset,
  ),
);

/// Runs barcode detection in a separate isolate
Future<dynamic> _inference(IsolateData isolateData) async {
  final ReceivePort responsePort = ReceivePort();
  isolateUtils?.sendPort?.send(
    isolateData..responsePort = responsePort.sendPort,
  );
  final dynamic results = await responsePort.first;
  return results;
}
