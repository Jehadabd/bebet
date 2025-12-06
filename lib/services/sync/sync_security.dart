// lib/services/sync/sync_security.dart
// خدمات الأمان والتشفير لنظام المزامنة

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// خدمة الأمان للمزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncSecurity {
  static const _storage = FlutterSecureStorage();
  static const String _secretKeyStorageKey = 'sync_shared_secret_v2';
  static const String _deviceIdStorageKey = 'sync_device_id_v2';
  
  /// توليد مفتاح سري جديد
  static String generateSecretKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }
  
  /// حفظ المفتاح السري
  static Future<void> saveSecretKey(String key) async {
    await _storage.write(key: _secretKeyStorageKey, value: key);
  }
  
  /// قراءة المفتاح السري
  static Future<String?> getSecretKey() async {
    return await _storage.read(key: _secretKeyStorageKey);
  }
  
  /// الحصول على المفتاح السري أو إنشاء واحد جديد
  static Future<String> getOrCreateSecretKey() async {
    var key = await getSecretKey();
    if (key == null || key.isEmpty) {
      key = generateSecretKey();
      await saveSecretKey(key);
    }
    return key;
  }
  
  /// حفظ معرف الجهاز
  static Future<void> saveDeviceId(String deviceId) async {
    await _storage.write(key: _deviceIdStorageKey, value: deviceId);
  }
  
  /// قراءة معرف الجهاز
  static Future<String?> getDeviceId() async {
    return await _storage.read(key: _deviceIdStorageKey);
  }
  
  /// الحصول على معرف الجهاز أو إنشاء واحد جديد (ثابت ودائم)
  /// 
  /// هذه الدالة تضمن أن معرف الجهاز:
  /// 1. يُولّد مرة واحدة فقط عند أول استخدام
  /// 2. يُحفظ في التخزين الآمن
  /// 3. يبقى ثابتاً حتى لو تغيرت الشبكة (WiFi/4G)
  /// 4. يُحوّل أي ID قديم (بصيغة MAC/IP) إلى UUID ثابت
  static Future<String> getOrCreateDeviceId() async {
    var deviceId = await getDeviceId();
    
    // التحقق من وجود ID وأنه بصيغة UUID صحيحة
    if (deviceId == null || deviceId.isEmpty || !_isValidUuid(deviceId)) {
      // إذا كان هناك ID قديم بصيغة MAC/IP، نُسجّله للتتبع
      if (deviceId != null && deviceId.isNotEmpty) {
        print('🔄 تحويل معرف الجهاز القديم: $deviceId');
      }
      
      // توليد UUID جديد ثابت
      deviceId = generateUuid();
      await saveDeviceId(deviceId);
      print('🆕 تم توليد معرف جهاز جديد (UUID): $deviceId');
    }
    return deviceId;
  }
  
  /// التحقق من أن المعرف بصيغة UUID صحيحة
  /// UUID format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  static bool _isValidUuid(String id) {
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return uuidRegex.hasMatch(id);
  }
  
  /// توليد توقيع HMAC-SHA256 للبيانات
  static String signData(String data, String secretKey) {
    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(data);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }
  
  /// التحقق من صحة التوقيع
  static bool verifySignature(String data, String signature, String secretKey) {
    final expectedSignature = signData(data, secretKey);
    // مقارنة آمنة ضد timing attacks
    return _secureCompare(signature, expectedSignature);
  }
  
  /// مقارنة آمنة للسلاسل (ضد timing attacks)
  static bool _secureCompare(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
  
  /// حساب checksum SHA-256 للبيانات
  static String calculateChecksum(dynamic data) {
    String jsonString;
    if (data is String) {
      jsonString = data;
    } else {
      jsonString = jsonEncode(data);
    }
    final bytes = utf8.encode(jsonString);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// حساب checksum لقائمة من العناصر (مرتبة)
  static String calculateListChecksum(List<Map<String, dynamic>> items, String sortKey) {
    // ترتيب العناصر للحصول على نتيجة ثابتة
    final sorted = List<Map<String, dynamic>>.from(items)
      ..sort((a, b) => (a[sortKey]?.toString() ?? '').compareTo(b[sortKey]?.toString() ?? ''));
    return calculateChecksum(sorted);
  }
  
  /// توليد UUID فريد
  static String generateUuid() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    
    // Set version to 4
    values[6] = (values[6] & 0x0f) | 0x40;
    // Set variant to RFC 4122
    values[8] = (values[8] & 0x3f) | 0x80;
    
    final hex = values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
  
  /// توليد معرف عملية فريد
  static String generateOperationId(String deviceId) {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final random = Random.secure().nextInt(999999).toString().padLeft(6, '0');
    final deviceShort = deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId;
    return 'op_${timestamp}_${deviceShort}_$random';
  }
  
  /// توليد معرف قفل فريد
  static String generateLockId(String deviceId) {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final random = Random.secure().nextInt(9999).toString().padLeft(4, '0');
    return 'lock_${timestamp}_${deviceId.substring(0, 8)}_$random';
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// Merkle Tree لحساب hash شامل للبيانات
/// ═══════════════════════════════════════════════════════════════════════════
class MerkleTree {
  /// حساب Merkle Root لقائمة من الـ hashes
  static String calculateRoot(List<String> hashes) {
    if (hashes.isEmpty) {
      return sha256.convert(utf8.encode('')).toString();
    }
    if (hashes.length == 1) {
      return hashes[0];
    }
    
    List<String> currentLevel = List.from(hashes);
    
    while (currentLevel.length > 1) {
      List<String> nextLevel = [];
      
      for (int i = 0; i < currentLevel.length; i += 2) {
        if (i + 1 < currentLevel.length) {
          // دمج زوج من الـ hashes
          final combined = currentLevel[i] + currentLevel[i + 1];
          nextLevel.add(sha256.convert(utf8.encode(combined)).toString());
        } else {
          // إذا كان العدد فردي، نرفع الأخير كما هو
          nextLevel.add(currentLevel[i]);
        }
      }
      
      currentLevel = nextLevel;
    }
    
    return currentLevel[0];
  }
  
  /// حساب Merkle Root من قائمة عمليات
  static String calculateFromOperations(List<Map<String, dynamic>> operations) {
    if (operations.isEmpty) return calculateRoot([]);
    
    final hashes = operations.map((op) {
      final checksum = op['metadata']?['checksum'] as String?;
      if (checksum != null && checksum.isNotEmpty) {
        return checksum;
      }
      return SyncSecurity.calculateChecksum(op);
    }).toList();
    
    return calculateRoot(hashes);
  }
  
  /// التحقق من سلامة البيانات باستخدام Merkle Root
  static bool verify(List<String> hashes, String expectedRoot) {
    final calculatedRoot = calculateRoot(hashes);
    return calculatedRoot == expectedRoot;
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// مدقق سلامة البيانات
/// ═══════════════════════════════════════════════════════════════════════════
class DataIntegrityChecker {
  /// التحقق من سلامة عملية واحدة
  static bool verifyOperation(Map<String, dynamic> operation, String secretKey) {
    try {
      final metadata = operation['metadata'] as Map<String, dynamic>?;
      if (metadata == null) return false;
      
      final checksum = metadata['checksum'] as String?;
      final signature = metadata['signature'] as String?;
      
      if (checksum == null || signature == null) return false;
      
      // التحقق من checksum
      final payload = operation['payload'];
      final expectedChecksum = SyncSecurity.calculateChecksum(payload);
      if (checksum != expectedChecksum) {
        print('❌ Checksum mismatch for operation ${operation['operation_id']}');
        return false;
      }
      
      // التحقق من التوقيع
      final operationId = operation['operation_id'] as String;
      final deviceId = operation['device_id'] as String;
      final localSequence = operation['local_sequence'] as int;
      final dataToSign = '$operationId|$deviceId|$localSequence|$checksum';
      
      if (!SyncSecurity.verifySignature(dataToSign, signature, secretKey)) {
        print('❌ Signature invalid for operation $operationId');
        return false;
      }
      
      return true;
    } catch (e) {
      print('❌ Error verifying operation: $e');
      return false;
    }
  }
  
  /// التحقق من تسلسل العمليات (لا توجد فجوات)
  static bool verifySequence(List<Map<String, dynamic>> operations, String deviceId) {
    if (operations.isEmpty) return true;
    
    // فلترة عمليات الجهاز المحدد
    final deviceOps = operations
      .where((op) => op['device_id'] == deviceId)
      .toList()
      ..sort((a, b) => (a['local_sequence'] as int).compareTo(b['local_sequence'] as int));
    
    if (deviceOps.isEmpty) return true;
    
    // التحقق من عدم وجود فجوات
    for (int i = 1; i < deviceOps.length; i++) {
      final prev = deviceOps[i - 1]['local_sequence'] as int;
      final curr = deviceOps[i]['local_sequence'] as int;
      if (curr != prev + 1) {
        print('❌ Sequence gap detected: $prev -> $curr for device $deviceId');
        return false;
      }
    }
    
    return true;
  }
  
  /// التحقق من سلامة الفهرس
  static bool verifyManifest(Map<String, dynamic> manifest, String secretKey) {
    try {
      final checksum = manifest['checksum'] as String?;
      if (checksum == null) return false;
      
      // إنشاء نسخة بدون checksum لحساب الـ checksum المتوقع
      final manifestCopy = Map<String, dynamic>.from(manifest);
      manifestCopy.remove('checksum');
      
      final expectedChecksum = SyncSecurity.calculateChecksum(manifestCopy);
      return checksum == expectedChecksum;
    } catch (e) {
      print('❌ Error verifying manifest: $e');
      return false;
    }
  }
}
