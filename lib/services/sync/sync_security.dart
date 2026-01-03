// lib/services/sync/sync_security.dart
// خدمات الأمان والتشفير لنظام المزامنة

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// خدمة الأمان للمزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncSecurity {
  static const _storage = FlutterSecureStorage();
  static const String _secretKeyStorageKey = 'sync_shared_secret_v3';
  static const String _deviceIdStorageKey = 'sync_device_id_v2';
  
  // اسم ملف المفتاح المشترك على Google Drive
  static const String _sharedSecretFileName = '.shared_secret.json';
  static const String _syncFolderName = 'DebtBook_Sync_v3';
  
  // 🔐 مفتاح احتياطي (يُستخدم فقط إذا لم يتم إنشاء مفتاح للمجموعة)
  // ⚠️ هذا المفتاح للتوافق مع الإصدارات القديمة فقط
  static const String _legacyFallbackKey = 'DebtBook_Legacy_Key_v3';
  
  /// توليد مفتاح سري جديد (256-bit)
  static String generateSecretKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }
  
  /// حفظ المفتاح السري محلياً
  static Future<void> saveSecretKey(String key) async {
    await _storage.write(key: _secretKeyStorageKey, value: key);
    print('🔐 تم حفظ المفتاح المشترك محلياً');
  }
  
  /// قراءة المفتاح السري المحلي
  static Future<String?> getSecretKey() async {
    return await _storage.read(key: _secretKeyStorageKey);
  }
  
  /// الحصول على المفتاح السري أو إنشاء واحد جديد
  /// 🔐 الآن يُولّد مفتاح فريد لكل تثبيت بدلاً من مفتاح ثابت
  static Future<String> getOrCreateSecretKey() async {
    // 1. محاولة قراءة المفتاح المحفوظ
    var key = await getSecretKey();
    
    if (key != null && key.isNotEmpty && key != _legacyFallbackKey) {
      return key;
    }
    
    // 2. إنشاء مفتاح جديد
    key = generateSecretKey();
    await saveSecretKey(key);
    print('🆕 تم إنشاء مفتاح سري جديد');
    
    return key;
  }
  
  /// الحصول على مفتاح لمجموعة معينة
  /// يُستخدم مع Firebase Sync حيث كل مجموعة لها مفتاح خاص
  static Future<String> getGroupSecretKey(String groupId) async {
    final groupKeyStorageKey = 'sync_group_secret_$groupId';
    
    var key = await _storage.read(key: groupKeyStorageKey);
    
    if (key != null && key.isNotEmpty) {
      return key;
    }
    
    // إنشاء مفتاح جديد للمجموعة
    key = generateSecretKey();
    await _storage.write(key: groupKeyStorageKey, value: key);
    print('🆕 تم إنشاء مفتاح للمجموعة: $groupId');
    
    return key;
  }
  
  /// حفظ مفتاح مجموعة (عند استيراده من جهاز آخر)
  static Future<void> saveGroupSecretKey(String groupId, String key) async {
    final groupKeyStorageKey = 'sync_group_secret_$groupId';
    await _storage.write(key: groupKeyStorageKey, value: key);
    print('🔐 تم حفظ مفتاح المجموعة: $groupId');
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔄 مزامنة المفتاح المشترك مع Google Drive
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// مزامنة المفتاح المشترك - يُستدعى عند كل مزامنة
  /// 1. يتحقق من وجود المفتاح على Drive
  /// 2. إذا وُجد: يُنزّله ويحفظه محلياً
  /// 3. إذا لم يوجد: يرفع المفتاح المحلي إلى Drive
  static Future<String> syncSharedSecret(drive.DriveApi driveApi, String syncFolderId) async {
    print('🔄 جاري مزامنة المفتاح المشترك...');
    
    try {
      // 1. البحث عن ملف المفتاح على Drive
      final remoteKey = await _downloadSharedSecret(driveApi, syncFolderId);
      
      if (remoteKey != null && remoteKey.isNotEmpty) {
        // المفتاح موجود على Drive - نحفظه محلياً
        await saveSecretKey(remoteKey);
        print('✅ تم تنزيل المفتاح المشترك من Google Drive');
        return remoteKey;
      }
      
      // 2. المفتاح غير موجود - نرفع المفتاح المحلي
      var localKey = await getSecretKey();
      if (localKey == null || localKey.isEmpty) {
        localKey = generateSecretKey();
        await saveSecretKey(localKey);
      }
      
      // رفع المفتاح إلى Drive
      await _uploadSharedSecret(driveApi, syncFolderId, localKey);
      print('✅ تم رفع المفتاح المشترك إلى Google Drive');
      
      return localKey;
      
    } catch (e) {
      print('⚠️ خطأ في مزامنة المفتاح: $e');
      // في حالة الخطأ، نستخدم المفتاح المحلي
      return await getOrCreateSecretKey();
    }
  }
  
  /// تنزيل المفتاح المشترك من Google Drive
  static Future<String?> _downloadSharedSecret(drive.DriveApi driveApi, String syncFolderId) async {
    try {
      final files = await driveApi.files.list(
        q: "name = '$_sharedSecretFileName' and '$syncFolderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id,name)',
      );
      
      if (files.files?.isEmpty ?? true) {
        print('📭 لا يوجد مفتاح مشترك على Drive');
        return null;
      }
      
      final fileId = files.files!.first.id!;
      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return json['secret_key'] as String?;
      
    } catch (e) {
      print('⚠️ خطأ في تنزيل المفتاح: $e');
      return null;
    }
  }
  
  /// رفع المفتاح المشترك إلى Google Drive
  static Future<void> _uploadSharedSecret(drive.DriveApi driveApi, String syncFolderId, String secretKey) async {
    try {
      final data = {
        'secret_key': secretKey,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'version': 1,
      };
      
      final content = jsonEncode(data);
      final bytes = utf8.encode(content);
      
      // إنشاء ملف مؤقت
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$_sharedSecretFileName');
      await tempFile.writeAsBytes(bytes);
      
      final media = drive.Media(tempFile.openRead(), bytes.length);
      
      await driveApi.files.create(
        drive.File()
          ..name = _sharedSecretFileName
          ..parents = [syncFolderId],
        uploadMedia: media,
      );
      
      await tempFile.delete();
      print('📤 تم رفع المفتاح المشترك');
      
    } catch (e) {
      print('❌ فشل رفع المفتاح: $e');
      rethrow;
    }
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
