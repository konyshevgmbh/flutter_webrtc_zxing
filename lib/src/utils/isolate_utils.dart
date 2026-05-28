import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as imglib;

import '../logic/zxing.dart';
import '../models/models.dart';
import 'image_converter.dart';

/// Bundles data to pass between isolates
class IsolateData {
  IsolateData(
    this.encodedBytes,
    this.params, {
    this.cropPercent = 0.5,
    this.horizontalCropOffset = 0.0,
    this.verticalCropOffset = 0.0,
  });

  final Uint8List encodedBytes;
  final DecodeParams params;
  final double cropPercent;
  final double horizontalCropOffset;
  final double verticalCropOffset;
  SendPort? responsePort;
}

/// Manages separate Isolate instance for barcode detection
class IsolateUtils {
  static const String kDebugName = 'ZxingIsolate';

  // ignore: unused_field
  Isolate? _isolate;
  final ReceivePort _receivePort = ReceivePort();
  SendPort? _sendPort;

  SendPort? get sendPort => _sendPort;

  bool _initializing = false;

  Future<void> startReadingBarcode() async {
    if (_initializing || _isolate != null) {
      return;
    }
    _initializing = true;
    try {
      _isolate = await Isolate.spawn<SendPort>(
        readBarcodeEntryPoint,
        _receivePort.sendPort,
        debugName: kDebugName,
      );
      _sendPort = await _receivePort.first;
    } catch (_) {
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  void stopReadingBarcode() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
  }

  static Future<void> readBarcodeEntryPoint(SendPort sendPort) async {
    final ReceivePort port = ReceivePort();
    sendPort.send(port.sendPort);

    await for (final IsolateData? isolateData in port) {
      if (isolateData == null) {
        continue;
      }
      try {
        imglib.Image? image = imglib.decodeImage(isolateData.encodedBytes);
        if (image == null) {
          isolateData.responsePort?.send(
            isolateData.params.isMultiScan ? Codes() : Code(),
          );
          continue;
        }
        image = resizeToMaxSize(image, isolateData.params.maxSize);

        final DecodeParams params = isolateData.params;
        params.width = image.width;
        params.height = image.height;
        params.imageFormat = ImageFormat.rgb;

        final double cropPercent = isolateData.cropPercent;
        if (cropPercent > 0) {
          final int cropSize =
              (min(image.width, image.height) * cropPercent).round();
          params.cropLeft =
              ((image.width - cropSize) ~/ 2 +
                      (isolateData.horizontalCropOffset *
                              (image.width - cropSize) /
                              2))
                  .round()
                  .clamp(0, image.width - cropSize);
          params.cropTop =
              ((image.height - cropSize) ~/ 2 +
                      (isolateData.verticalCropOffset *
                              (image.height - cropSize) /
                              2))
                  .round()
                  .clamp(0, image.height - cropSize);
          params.cropWidth = cropSize;
          params.cropHeight = cropSize;
        }

        final Uint8List bytes = rgbBytes(image);
        dynamic result;
        if (params.isMultiScan) {
          result = zxingReadBarcodes(bytes, params);
        } else {
          result = zxingReadBarcode(bytes, params);
        }
        isolateData.responsePort?.send(result);
      } catch (e) {
        isolateData.responsePort?.send(e);
      }
    }
  }
}
