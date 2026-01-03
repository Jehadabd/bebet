// lib/services/firebase_sync/firebase_sync_config.dart
// إعدادات مجموعة المزامنة عبر Firebase

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// معرفات المجموعات المتاحة
class SyncGroupIds {
  static const String groupA = 'group_A';
  static const String groupB = 'group_B';
  
  static List<String> get all => [groupA, groupB];
  
  static String getDisplayName(String groupId) {
    switch (groupId) {
      case groupA:
        return 'المجموعة أ';
      case groupB:
        return 'المجموعة ب';
      default:
        return groupId;
    }
  }
}

/// إعدادات المزامنة عبر Firebase
class FirebaseSyncConfig {
  static const String _groupIdKey = 'firebase_sync_group_id';
  static const String _enabledKey = 'firebase_sync_enabled';
  static const String _deviceIdKey = 'firebase_sync_device_id';
  static const String _lastSyncKey = 'firebase_sync_last_sync';
  static const String _groupSecretKey = 'firebase_sync_group_secret';
  
  static final _secureStorage = FlutterSecureStorage();
  
  /// الحصول على معرف المجموعة الحالي
  static Future<String?> getSyncGroupId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_groupIdKey);
  }
  
  /// تعيين معرف المجموعة
  static Future<void> setSyncGroupId(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupIdKey, groupId);
  }
  
  /// هل المزامنة مفعلة؟
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }
  
  /// تفعيل/تعطيل المزامنة
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }
  
  /// الحصول على معرف الجهاز الفريد
  static Future<String> getDeviceId() async {
    String? deviceId = await _secureStorage.read(key: _deviceIdKey);
    if (deviceId == null) {
      deviceId = _generateDeviceId();
      await _secureStorage.write(key: _deviceIdKey, value: deviceId);
    }
    return deviceId;
  }
  
  /// توليد معرف جهاز فريد
  static String _generateDeviceId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
  
  /// الحصول على آخر وقت مزامنة
  static Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getString(_lastSyncKey);
    if (timestamp == null) return null;
    return DateTime.tryParse(timestamp);
  }
  
  /// تحديث آخر وقت مزامنة
  static Future<void> setLastSyncTime(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, time.toIso8601String());
  }
  
  /// مسح جميع إعدادات المزامنة
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_groupIdKey);
    await prefs.remove(_enabledKey);
    await prefs.remove(_lastSyncKey);
  }
  
  /// هل تم إعداد المزامنة؟
  static Future<bool> isConfigured() async {
    final groupId = await getSyncGroupId();
    return groupId != null && groupId.isNotEmpty;
  }
  
  /// الحصول على المفتاح السري للمجموعة
  static Future<String?> getGroupSecret() async {
    return await _secureStorage.read(key: _groupSecretKey);
  }
  
  /// تعيين المفتاح السري للمجموعة
  static Future<void> setGroupSecret(String secret) async {
    await _secureStorage.write(key: _groupSecretKey, value: secret);
  }
  
  /// توليد مفتاح سري جديد للمجموعة (64 حرف)
  static String generateGroupSecret() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
  
  /// الحصول على المفتاح السري أو إنشاء واحد جديد
  static Future<String> getOrCreateGroupSecret() async {
    var secret = await getGroupSecret();
    if (secret == null || secret.length < 32) {
      secret = generateGroupSecret();
      await setGroupSecret(secret);
      print('🔐 تم إنشاء مفتاح سري جديد للمجموعة');
    }
    return secret;
  }
}

/// تحدي رياضي للحماية
class MathChallenge {
  final double num1;
  final double num2;
  final String operator;
  final double answer;
  
  MathChallenge._({
    required this.num1,
    required this.num2,
    required this.operator,
    required this.answer,
  });
  
  /// توليد تحدي رياضي صعب
  static MathChallenge generate() {
    final random = Random();
    
    // أرقام عشوائية بكسور عشرية
    final num1 = (random.nextInt(900) + 100) + (random.nextInt(99) / 100);
    final num2 = (random.nextInt(90) + 10) + (random.nextInt(99) / 100);
    
    // اختيار عملية عشوائية (ضرب أو قسمة)
    final isMultiply = random.nextBool();
    final operator = isMultiply ? '×' : '÷';
    
    double answer;
    if (isMultiply) {
      answer = num1 * num2;
    } else {
      answer = num1 / num2;
    }
    
    return MathChallenge._(
      num1: double.parse(num1.toStringAsFixed(2)),
      num2: double.parse(num2.toStringAsFixed(2)),
      operator: operator,
      answer: double.parse(answer.toStringAsFixed(3)),
    );
  }
  
  /// التحقق من الإجابة (مع هامش خطأ صغير)
  bool verify(String userAnswer) {
    final parsed = double.tryParse(userAnswer);
    if (parsed == null) return false;
    
    // هامش خطأ 0.01
    return (parsed - answer).abs() < 0.01;
  }
  
  /// نص السؤال
  String get questionText => '${num1.toStringAsFixed(2)} $operator ${num2.toStringAsFixed(2)} = ؟';
}
