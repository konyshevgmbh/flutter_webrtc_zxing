import 'package:flutter/foundation.dart';

final DateTime _start = DateTime.now();

void dbg(String msg) {
  if (kDebugMode) {
    final int ms = DateTime.now().difference(_start).inMilliseconds;
    debugPrint('[zxing +${ms}ms] $msg');
  }
}
