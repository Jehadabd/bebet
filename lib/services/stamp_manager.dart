import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/app_settings.dart';

class StampManager {
  static pw.MemoryImage? coloredCash;
  static pw.MemoryImage? coloredCredit;
  static pw.MemoryImage? inkCash;
  static pw.MemoryImage? inkCredit;
  static pw.MemoryImage? customCash;
  static pw.MemoryImage? customCredit;

  static Future<pw.MemoryImage?> _tryLoadAsset(String basePath) async {
    try {
      final data = await rootBundle.load('$basePath.jpg');
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (e) {
      try {
        final data = await rootBundle.load('$basePath.png');
        return pw.MemoryImage(data.buffer.asUint8List());
      } catch (e2) {
        print('Error loading asset $basePath (.jpg or .png): $e2');
        return null;
      }
    }
  }

  static Future<void> loadStamps(AppSettings settings) async {
    try {
      if (settings.stampType == 'colored') {
        coloredCash ??= await _tryLoadAsset('assets/stamps/colored_cash');
        coloredCredit ??= await _tryLoadAsset('assets/stamps/colored_credit');
      } else if (settings.stampType == 'ink') {
        inkCash ??= await _tryLoadAsset('assets/stamps/ink_cash');
        inkCredit ??= await _tryLoadAsset('assets/stamps/ink_credit');
      } else if (settings.stampType == 'custom') {
        if (settings.customCashStampPath != null && File(settings.customCashStampPath!).existsSync()) {
          customCash = pw.MemoryImage(File(settings.customCashStampPath!).readAsBytesSync());
        } else {
          customCash = null;
        }
        if (settings.customCreditStampPath != null && File(settings.customCreditStampPath!).existsSync()) {
          customCredit = pw.MemoryImage(File(settings.customCreditStampPath!).readAsBytesSync());
        } else {
          customCredit = null;
        }
      }
    } catch (e) {
      print('Error loading stamp assets: $e');
    }
  }
}
