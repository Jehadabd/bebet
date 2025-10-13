import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alnaser/models/app_settings.dart'; // Import AppSettings model
import 'package:alnaser/models/printer_device.dart'; // Import PrinterDevice model

class SettingsManager {
  static const _keyAppSettings = 'app_settings';
  static const _keyDefaultPrinter = 'default_printer';

  static Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = jsonEncode(settings.toJson());
    await prefs.setString(_keyAppSettings, settingsJson);
  }

  static Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString(_keyAppSettings);
    if (settingsJson != null) {
      return AppSettings.fromJson(jsonDecode(settingsJson));
    }
    return AppSettings(); // Return default settings if none are saved
  }

  static Future<void> saveAppSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = jsonEncode(settings.toJson());
    await prefs.setString(_keyAppSettings, settingsJson);
  }

  static Future<AppSettings> getAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settingsJson = prefs.getString(_keyAppSettings);
    if (settingsJson != null) {
      return AppSettings.fromJson(jsonDecode(settingsJson));
    }
    return AppSettings(); // Return default settings if none are saved
  }

  static Future<void> saveDefaultPrinter(PrinterDevice printer) async {
    final prefs = await SharedPreferences.getInstance();
    final printerJson = jsonEncode(printer.toJson());
    await prefs.setString(_keyDefaultPrinter, printerJson);
  }

  static Future<PrinterDevice?> getDefaultPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final printerJson = prefs.getString(_keyDefaultPrinter);
    if (printerJson != null) {
      return PrinterDevice.fromJson(jsonDecode(printerJson));
    }
    return null;
  }
} 