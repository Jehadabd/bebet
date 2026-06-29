// services/custom_units_service.dart
// خدمة حفظ الوحدات المخصصة - تحفظ الوحدات التي يدخلها المستخدم
// وتظهرها كخيارات مقترحة في المرات القادمة

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class CustomUnitsService {
  static const String _baseUnitsKey = 'custom_base_units';
  static const String _largeUnitsKey = 'custom_large_units';

  // الوحدات الافتراضية المقترحة للوحدة الأساسية
  static const List<String> _defaultBaseUnits = [
    'قطعة',
    'متر',
    'سنتيمتر',
    'غرام',
    'كيلو',
    'باكيت',
    'كرتون',
    'لفة',
    'علبة',
    'باكية',
    'صندوق',
    'كيس',
    'ربطة',
    'سيت',
    'ماتور',
    'رزمة',
    'طرد',
    'عبوة',
    'باكج',
  ];

  // الوحدات الافتراضية المقترحة للوحدات الكبيرة
  static const List<String> _defaultLargeUnits = [
    'كرتون',
    'صندوق',
    'ربطة',
    'كيس',
    'سيت',
    'باكيت',
    'لفة',
    'علبة',
    'باكية',
    'رزمة',
    'طرد',
    'عبوة',
  ];

  /// الحصول على قائمة الوحدات الأساسية (الافتراضية + المخصصة)
  static Future<List<String>> getBaseUnits() async {
    final prefs = await SharedPreferences.getInstance();
    final customJson = prefs.getString(_baseUnitsKey);
    
    List<String> units = List.from(_defaultBaseUnits);
    
    if (customJson != null && customJson.isNotEmpty) {
      try {
        final customUnits = List<String>.from(jsonDecode(customJson));
        for (final unit in customUnits) {
          if (!units.contains(unit)) {
            units.add(unit);
          }
        }
      } catch (_) {}
    }
    
    return units;
  }

  /// الحصول على قائمة الوحدات الكبيرة (الافتراضية + المخصصة)
  static Future<List<String>> getLargeUnits() async {
    final prefs = await SharedPreferences.getInstance();
    final customJson = prefs.getString(_largeUnitsKey);
    
    List<String> units = List.from(_defaultLargeUnits);
    
    if (customJson != null && customJson.isNotEmpty) {
      try {
        final customUnits = List<String>.from(jsonDecode(customJson));
        for (final unit in customUnits) {
          if (!units.contains(unit)) {
            units.add(unit);
          }
        }
      } catch (_) {}
    }
    
    return units;
  }

  /// إضافة وحدة أساسية مخصصة
  static Future<void> addBaseUnit(String unitName) async {
    if (unitName.trim().isEmpty || _defaultBaseUnits.contains(unitName.trim())) return;
    
    final prefs = await SharedPreferences.getInstance();
    final customJson = prefs.getString(_baseUnitsKey);
    
    List<String> customUnits = [];
    if (customJson != null && customJson.isNotEmpty) {
      try {
        customUnits = List<String>.from(jsonDecode(customJson));
      } catch (_) {}
    }
    
    final trimmed = unitName.trim();
    if (!customUnits.contains(trimmed)) {
      customUnits.add(trimmed);
      await prefs.setString(_baseUnitsKey, jsonEncode(customUnits));
    }
  }

  /// إضافة وحدة كبيرة مخصصة
  static Future<void> addLargeUnit(String unitName) async {
    if (unitName.trim().isEmpty || _defaultLargeUnits.contains(unitName.trim())) return;
    
    final prefs = await SharedPreferences.getInstance();
    final customJson = prefs.getString(_largeUnitsKey);
    
    List<String> customUnits = [];
    if (customJson != null && customJson.isNotEmpty) {
      try {
        customUnits = List<String>.from(jsonDecode(customJson));
      } catch (_) {}
    }
    
    final trimmed = unitName.trim();
    if (!customUnits.contains(trimmed)) {
      customUnits.add(trimmed);
      await prefs.setString(_largeUnitsKey, jsonEncode(customUnits));
    }
  }

  /// الحصول على الوحدات الأساسية بشكل متزامن (من Cache)
  static List<String> getBaseUnitsSync() {
    // نرجع القائمة الافتراضية لأن SharedPreferences يحتاج async
    // يمكن استدعاء getBaseUnits() للحصول على القائمة الكاملة
    return List.from(_defaultBaseUnits);
  }

  /// الحصول على الوحدات الكبيرة بشكل متزامن (من Cache)
  static List<String> getLargeUnitsSync() {
    return List.from(_defaultLargeUnits);
  }
}
