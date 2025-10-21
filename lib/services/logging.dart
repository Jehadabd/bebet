import 'package:flutter/foundation.dart';

class AppLog {
  // Toggle verbose logs globally. Keep false in production.
  static bool verbose = true;

  static void d(String message) {
    if (!verbose) return;
    debugPrint(message);
  }
}


