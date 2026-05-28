import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';

import '../../flutter_webrtc_zxing.dart' as zxing;
import '../../flutter_webrtc_zxing.dart';
import '../utils/dbg.dart';
import 'scan_mode_dropdown.dart';

/// Widget to scan a barcode using a WebRTC camera stream
class ReaderWidget extends StatefulWidget {
  const ReaderWidget({
    super.key,
    this.onScan,
    this.onScanFailure,
    this.onMultiScan,
    this.onMultiScanFailure,
    this.onRendererCreated,
    this.onMultiScanModeChanged,
    this.isMultiScan = false,
    this.multiScanModeAlignment = Alignment.bottomRight,
    this.multiScanModePadding = const EdgeInsets.all(10),
    this.codeFormat = Format.any,
    this.tryHarder = false,
    this.tryInverted = false,
    this.tryRotate = true,
    this.tryDownscale = false,
    this.maxNumberOfSymbols = 10,
    this.showScannerOverlay = true,
    this.scannerOverlay,
    this.actionButtonsAlignment = Alignment.bottomLeft,
    this.actionButtonsPadding = const EdgeInsets.all(10),
    this.showToggleCamera = true,
    this.showGallery = true,
    this.galleryIcon = const Icon(Icons.photo_library),
    this.toggleCameraIcon = const Icon(Icons.switch_camera),
    this.actionButtonsBackgroundColor = Colors.black,
    this.actionButtonsBackgroundBorderRadius,
    this.scanDelay = const Duration(milliseconds: 1000),
    this.scanDelaySuccess = const Duration(milliseconds: 1000),
    this.cropPercent = 0.5,
    this.horizontalCropOffset = 0.0,
    this.verticalCropOffset = 0.0,
    this.useFrontCamera = false,
    this.targetFps = 10,
    this.loading = const DecoratedBox(
      decoration: BoxDecoration(color: Colors.black),
    ),
    this.onActionSecondButton,
    this.actionSecondButtonIcon,
    this.actionSecondButtonIconBackgroundColor,
  });

  /// Called when a barcode is detected
  final Function(Code)? onScan;

  /// Called when no barcode is detected
  final Function(Code)? onScanFailure;

  /// Called when barcodes are detected in multi-scan mode
  final Function(Codes)? onMultiScan;

  /// Called when no barcodes are detected in multi-scan mode
  final Function(Codes)? onMultiScanFailure;

  /// Called when the WebRTC renderer is created (or on error)
  final Function(RTCVideoRenderer? renderer, Exception? error)?
      onRendererCreated;

  /// Called when the multi scan mode is toggled
  final Function(bool)? onMultiScanModeChanged;

  /// Allow multiple simultaneous scans
  final bool isMultiScan;

  /// Alignment for multi scan mode button
  final AlignmentGeometry multiScanModeAlignment;

  /// Padding for multi scan mode button
  final EdgeInsetsGeometry multiScanModePadding;

  /// Barcode format filter
  final int codeFormat;

  /// Spend more time trying to detect a barcode
  final bool tryHarder;

  /// Try to detect inverted barcodes
  final bool tryInverted;

  /// Try to detect rotated barcodes
  final bool tryRotate;

  /// Try detecting in downscaled images
  final bool tryDownscale;

  /// Maximum barcodes to detect in multi-scan mode
  final int maxNumberOfSymbols;

  /// Show the scanner crop overlay
  final bool showScannerOverlay;

  /// Custom scanner overlay shape
  final ShapeBorder? scannerOverlay;

  /// Alignment for action buttons
  final AlignmentGeometry actionButtonsAlignment;

  /// Padding for action buttons
  final EdgeInsetsGeometry actionButtonsPadding;

  /// Show the camera toggle button
  final bool showToggleCamera;

  /// Show the gallery picker button
  final bool showGallery;

  /// Custom gallery icon
  final Widget galleryIcon;

  /// Custom camera toggle icon
  final Widget toggleCameraIcon;

  /// Background color for action buttons
  final Color actionButtonsBackgroundColor;

  /// Background border radius for action buttons
  final BorderRadius? actionButtonsBackgroundBorderRadius;

  /// Delay between scan attempts when nothing is detected
  final Duration scanDelay;

  /// Delay after a successful scan
  final Duration scanDelaySuccess;

  /// Crop percentage of the shorter screen dimension (0 = full frame)
  final double cropPercent;

  /// Horizontal crop offset (-1 left … +1 right)
  final double horizontalCropOffset;

  /// Vertical crop offset (-1 top … +1 bottom)
  final double verticalCropOffset;

  /// Use front-facing camera
  final bool useFrontCamera;

  /// Target frames per second for barcode scanning
  final int targetFps;

  /// Widget shown while the camera is initialising
  final Widget loading;

  /// Callback for an optional second action button
  final Function()? onActionSecondButton;

  /// Icon for the optional second action button
  final Widget? actionSecondButtonIcon;

  /// Background color for the optional second action button
  final Color? actionSecondButtonIconBackgroundColor;

  @override
  State<ReaderWidget> createState() => _ReaderWidgetState();
}

class _ReaderWidgetState extends State<ReaderWidget>
    with WidgetsBindingObserver {
  RTCVideoRenderer? _renderer;
  MediaStream? _localStream;
  Timer? _frameTimer;

  bool _isProcessing = false;
  bool _isRunning = false;
  bool _isStarting = false;
  bool _pendingStart = false; // resumed fired while _isStarting was true
  bool _fatalError = false;   // permanent error (e.g. permission denied) — stop retrying
  bool _isMultiScan = false;
  bool _useFrontCamera = false;

  Codes results = Codes();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isMultiScan = widget.isMultiScan;
    _useFrontCamera = widget.useFrontCamera;
    _init();
  }

  Future<void> _init() async {
    try {
      dbg('[init] startCameraProcessing…');
      await zx.startCameraProcessing();
      dbg('[init] startCameraProcessing done');
      if (!mounted) {
        return;
      }
      await _startCamera();
    } catch (e) {
      debugPrint('ReaderWidget init error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_isRunning && !_fatalError) {
          if (_isStarting) {
            _pendingStart = true;
          } else {
            _startCamera();
          }
        }
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _stopCamera();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    zx.stopCameraProcessing();
    super.dispose();
  }

  Future<void> _startCamera() async {
    if (_isRunning || _isStarting || _fatalError) {
      dbg('[cam] _startCamera skipped (running=$_isRunning starting=$_isStarting)');
      return;
    }
    _isStarting = true;
    dbg('[cam] _startCamera begin  front=$_useFrontCamera');
    try {
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) {
        dbg('[cam] WebRTC.initialize…');
        await WebRTC.initialize();
        dbg('[cam] WebRTC.initialize done');
      }
      if (!mounted) {
        return;
      }

      dbg('[cam] RTCVideoRenderer.initialize…');
      final RTCVideoRenderer renderer = RTCVideoRenderer();
      await renderer.initialize();
      dbg('[cam] RTCVideoRenderer ready');
      if (!mounted) {
        await renderer.dispose();
        return;
      }
      _renderer = renderer;

      final Map<String, dynamic> constraints = <String, dynamic>{
        'audio': false,
        'video': <String, dynamic>{
          'facingMode': _useFrontCamera ? 'user' : 'environment',
          'width': <String, dynamic>{'ideal': 1280},
          'height': <String, dynamic>{'ideal': 720},
          'frameRate': <String, dynamic>{'ideal': 30},
        },
      };

      dbg('[cam] getUserMedia…');
      final MediaStream stream =
          await navigator.mediaDevices.getUserMedia(constraints);
      if (!mounted || _renderer == null) {
        dbg('[cam] disposed during getUserMedia — aborting');
        for (final MediaStreamTrack t in stream.getTracks()) {
          await t.stop();
        }
        await stream.dispose();
        await _renderer?.dispose();
        _renderer = null;
        return;
      }
      _localStream = stream;
      renderer.srcObject = _localStream;

      final int trackCount = stream.getVideoTracks().length;
      dbg('[cam] stream ready  videoTracks=$trackCount  fps=${widget.targetFps}');

      setState(() => _isRunning = true);
      widget.onRendererCreated?.call(renderer, null);

      final Duration interval = Duration(
        milliseconds: (1000 / widget.targetFps).round().clamp(33, 5000),
      );
      dbg('[cam] timer started  interval=${interval.inMilliseconds} ms');
      _frameTimer = Timer.periodic(interval, (_) => _captureAndProcess());
    } catch (e) {
      final Exception ex = e is Exception ? e : Exception(e.toString());
      if (e.toString().contains('NotAllowedError') ||
          e.toString().contains('PermissionDenied')) {
        _fatalError = true;
        dbg('[cam] fatal error — stopping retries: $e');
      }
      widget.onRendererCreated?.call(null, ex);
      debugPrint('_startCamera error: $e');
    } finally {
      _isStarting = false;
      if (_pendingStart && mounted && !_isRunning && !_fatalError) {
        _pendingStart = false;
        _startCamera();
      }
    }
  }

  Future<void> _stopCamera() async {
    _frameTimer?.cancel();
    _frameTimer = null;
    _isRunning = false;
    _isProcessing = false;

    if (_localStream != null) {
      for (final MediaStreamTrack track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }

    await _renderer?.dispose();
    _renderer = null;
  }

  void _captureAndProcess() {
    if (!_isRunning || _isProcessing || _localStream == null) {
      return;
    }
    final List<MediaStreamTrack> tracks = _localStream!.getVideoTracks();
    if (tracks.isEmpty) {
      return;
    }

    _isProcessing = true;
    final Stopwatch frameSw = Stopwatch()..start();
    tracks.first.captureFrame().then((ByteBuffer byteBuffer) async {
      if (!_isRunning || !mounted) {
        return;
      }
      final Uint8List bytes = Uint8List.view(byteBuffer);
      dbg('[frame] captureFrame ${bytes.length} bytes in ${frameSw.elapsedMilliseconds} ms');

      final DecodeParams params = DecodeParams(
        format: widget.codeFormat,
        tryHarder: widget.tryHarder,
        tryRotate: widget.tryRotate,
        tryInverted: widget.tryInverted,
        tryDownscale: widget.tryDownscale,
        maxNumberOfSymbols: widget.maxNumberOfSymbols,
        isMultiScan: _isMultiScan,
      );

      final double cropPercent = _isMultiScan ? 0 : widget.cropPercent;

      if (_isMultiScan) {
        final Codes result = await zx.processWebRtcFrameMulti(
          bytes,
          params,
          cropPercent: cropPercent,
          horizontalCropOffset: widget.horizontalCropOffset,
          verticalCropOffset: widget.verticalCropOffset,
        );
        if (result.codes.isNotEmpty) {
          results = result;
          widget.onMultiScan?.call(result);
          if (mounted) {
            setState(() {});
          }
          await Future<void>.delayed(widget.scanDelaySuccess);
        } else {
          results = Codes();
          widget.onMultiScanFailure?.call(result);
        }
      } else {
        final Code result = await zx.processWebRtcFrame(
          bytes,
          params,
          cropPercent: cropPercent,
          horizontalCropOffset: widget.horizontalCropOffset,
          verticalCropOffset: widget.verticalCropOffset,
        );
        if (result.isValid) {
          dbg('[scan] ✓ "${result.text}"  format=${result.format}  ${result.duration} ms');
          results = Codes(codes: <Code>[result]);
          widget.onScan?.call(result);
          if (mounted) {
            setState(() {});
          }
          await Future<void>.delayed(widget.scanDelaySuccess);
        } else {
          dbg('[scan] no barcode found');
          results = Codes();
          widget.onScanFailure?.call(result);
        }
      }
    }).catchError((Object e) {
      debugPrint('_captureAndProcess error: $e');
    }).whenComplete(() async {
      await Future<void>.delayed(widget.scanDelay);
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isCameraReady = _isRunning && _renderer != null;
    final Size size = MediaQuery.of(context).size;
    final double cameraMaxSize = max(size.width, size.height);
    final double cropSize = min(size.width, size.height) * widget.cropPercent;

    return Stack(
      children: <Widget>[
        if (!isCameraReady)
          widget.loading
        else
          SizedBox(
            width: cameraMaxSize,
            height: cameraMaxSize,
            child: ClipRRect(
              child: OverflowBox(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: cameraMaxSize,
                    height: cameraMaxSize,
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        RTCVideoView(
                          _renderer!,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                        if (widget.showScannerOverlay &&
                            results.codes.isNotEmpty &&
                            widget.cropPercent == 0)
                          MultiResultOverlay(
                            results: results.codes,
                            onCodeTap: widget.onScan,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (widget.showScannerOverlay &&
            widget.cropPercent != 0 &&
            !_isMultiScan)
          Container(
            decoration: ShapeDecoration(
              shape:
                  widget.scannerOverlay ??
                  ScannerOverlayBorder(
                    cutOutSize: cropSize,
                    horizontalOffset: widget.horizontalCropOffset,
                    verticalOffset: widget.verticalCropOffset,
                    borderColor: Theme.of(context).primaryColor,
                    overlayColor: Colors.black45,
                    borderRadius: 4,
                    borderLength: 20,
                    borderWidth: 8,
                  ),
            ),
          ),
        SafeArea(
          child: Align(
            alignment: widget.actionButtonsAlignment,
            child: Padding(
              padding: widget.actionButtonsPadding,
              child: ClipRRect(
                borderRadius:
                    widget.actionButtonsBackgroundBorderRadius ??
                    BorderRadius.circular(10.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius:
                          widget.actionButtonsBackgroundBorderRadius ??
                          BorderRadius.circular(10.0),
                      child: ColoredBox(
                        color: widget.actionButtonsBackgroundColor,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (widget.showGallery)
                              IconButton(
                                onPressed: _onGalleryButtonTapped,
                                color: Colors.white,
                                icon: widget.galleryIcon,
                              ),
                            if (widget.showToggleCamera)
                              IconButton(
                                onPressed: _onToggleCameraButtonTapped,
                                color: Colors.white,
                                icon: widget.toggleCameraIcon,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.onActionSecondButton != null &&
                        widget.actionSecondButtonIcon != null) ...<Widget>[
                      Container(
                        margin: EdgeInsets.only(
                          bottom:
                              (widget.onMultiScanModeChanged != null &&
                                  widget.multiScanModeAlignment ==
                                      Alignment.bottomRight)
                              ? 55.0
                              : 0,
                        ),
                        child: IconButton.filled(
                          padding: widget.actionButtonsPadding,
                          onPressed: widget.onActionSecondButton,
                          icon: widget.actionSecondButtonIcon!,
                          style: IconButton.styleFrom(
                            backgroundColor:
                                widget.actionSecondButtonIconBackgroundColor ??
                                widget.actionButtonsBackgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  widget.actionButtonsBackgroundBorderRadius ??
                                  BorderRadius.zero,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.onMultiScanModeChanged != null)
          SafeArea(
            child: ScanModeDropdown(
              isMultiScan: _isMultiScan,
              alignment: widget.multiScanModeAlignment,
              padding: widget.multiScanModePadding,
              onChanged: (bool value) {
                if (mounted) {
                  setState(() => _isMultiScan = value);
                }
                widget.onMultiScanModeChanged?.call(value);
              },
            ),
          ),
      ],
    );
  }

  Future<void> _onGalleryButtonTapped() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    if (file == null) {
      return;
    }

    final DecodeParams params = DecodeParams(
      imageFormat: zxing.ImageFormat.rgb,
      format: widget.codeFormat,
      tryHarder: widget.tryHarder,
      tryInverted: widget.tryInverted,
      isMultiScan: _isMultiScan,
    );

    if (_isMultiScan) {
      final Codes result = await zx.readBarcodesImagePath(file, params);
      if (result.codes.isNotEmpty) {
        results = result;
        widget.onMultiScan?.call(result);
        if (mounted) {
          setState(() {});
        }
      } else {
        results = Codes();
        widget.onMultiScanFailure?.call(result);
      }
    } else {
      final Code result = await zx.readBarcodeImagePath(file, params);
      if (result.isValid) {
        widget.onScan?.call(result);
      } else {
        widget.onScanFailure?.call(result);
      }
    }
  }

  Future<void> _onToggleCameraButtonTapped() async {
    if (_localStream == null) {
      return;
    }
    final List<MediaStreamTrack> tracks = _localStream!.getVideoTracks();
    if (tracks.isEmpty) {
      return;
    }
    _useFrontCamera = !_useFrontCamera;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (e) {
      debugPrint('switchCamera failed ($e), restarting with new facing mode');
      await _stopCamera();
      await _startCamera();
    }
  }
}
