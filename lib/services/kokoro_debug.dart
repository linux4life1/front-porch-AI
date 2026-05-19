// Temporary debug flag for the Kokoro worker pool system.
// Set to false to completely disable all Kokoro-related debug prints.
// 
// TODO: Delete this file + all kDebugPrint calls once the pool is stable.

import 'package:flutter/foundation.dart';

const bool kDebugKokoro = true;

void kDebugPrint(String message) {
  if (kDebugKokoro) {
    debugPrint(message);
  }
}
