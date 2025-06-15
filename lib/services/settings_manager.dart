import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alnaser/models/printer_device.dart'; // Import the new PrinterDevice model

class SettingsManager {
  static const _keyDefaultPrinter = 'default_printer';

  Future<void> saveDefaultPrinter(PrinterDevice printer) async {
    final prefs = await SharedPreferences.getInstance();
    final printerJson = jsonEncode(printer.toJson());
    await prefs.setString(_keyDefaultPrinter, printerJson);
  }

  Future<PrinterDevice?> getDefaultPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final printerJson = prefs.getString(_keyDefaultPrinter);
    if (printerJson != null) {
      return PrinterDevice.fromJson(jsonDecode(printerJson));
    }
    return null;
  }
} 