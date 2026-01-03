// lib/services/sync/sync_encryption.dart
// خدمة التشفير للمزامنة - AES-256-CBC

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// خدمة التشفير للمزامنة
class SyncEncryption {
  static const _storage = FlutterSecureStorage();
  
  static const String _groupKeyPrefix = 'sync_group_key_';
  static const String _groupSaltPrefix = 'sync_group_salt_';
  
  static const int _keyLength = 32;
  static const int _ivLength = 16;
  static const int _saltLength = 32;
  static const int _pbkdf2Iterations = 100000;
  
  /// توليد مفتاح جديد لمجموعة مزامنة
  static Future<String> generateGroupKey() async {
    final random = Random.secure();
    final keyBytes = List<int>.generate(_keyLength, (_) => random.nextInt(256));
    return base64Url.encode(keyBytes);
  }
  
  /// توليد salt جديد
  static String generateSalt() {
    final random = Random.secure();
    final saltBytes = List<int>.generate(_saltLength, (_) => random.nextInt(256));
    return base64Url.encode(saltBytes);
  }
  
  /// حفظ مفتاح المجموعة محلياً
  static Future<void> saveGroupKey(String groupId, String key) async {
    await _storage.write(key: '$_groupKeyPrefix$groupId', value: key);
  }
  
  /// حفظ salt المجموعة
  static Future<void> saveGroupSalt(String groupId, String salt) async {
    await _storage.write(key: '$_groupSaltPrefix$groupId', value: salt);
  }
  
  /// الحصول على مفتاح المجموعة
  static Future<String?> getGroupKey(String groupId) async {
    return await _storage.read(key: '$_groupKeyPrefix$groupId');
  }

  /// الحصول على salt المجموعة
  static Future<String?> getGroupSalt(String groupId) async {
    return await _storage.read(key: '$_groupSaltPrefix$groupId');
  }
  
  /// الحصول على مفتاح المجموعة أو إنشاء واحد جديد
  static Future<({String key, String salt, bool isNew})> getOrCreateGroupKey(String groupId) async {
    var key = await getGroupKey(groupId);
    var salt = await getGroupSalt(groupId);
    
    if (key != null && salt != null) {
      return (key: key, salt: salt, isNew: false);
    }
    
    key = await generateGroupKey();
    salt = generateSalt();
    
    await saveGroupKey(groupId, key);
    await saveGroupSalt(groupId, salt);
    
    return (key: key, salt: salt, isNew: true);
  }
  
  /// حذف مفتاح المجموعة
  static Future<void> deleteGroupKey(String groupId) async {
    await _storage.delete(key: '$_groupKeyPrefix$groupId');
    await _storage.delete(key: '$_groupSaltPrefix$groupId');
  }
  
  /// اشتقاق مفتاح التشفير من المفتاح الأساسي
  static Uint8List _deriveKey(String masterKey, String salt) {
    final keyBytes = utf8.encode(masterKey);
    final saltBytes = utf8.encode(salt);
    
    final hmac = Hmac(sha256, keyBytes);
    var block = Uint8List(_keyLength);
    var u = Uint8List.fromList(saltBytes + [0, 0, 0, 1]);
    
    for (int i = 0; i < _pbkdf2Iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (int j = 0; j < _keyLength; j++) {
        block[j] ^= u[j % u.length];
      }
    }
    
    return block;
  }
  
  /// تشفير البيانات
  static Future<String> encryptData(String plainText, String groupId) async {
    final keyData = await getOrCreateGroupKey(groupId);
    final derivedKey = _deriveKey(keyData.key, keyData.salt);
    
    final random = Random.secure();
    final ivBytes = List<int>.generate(_ivLength, (_) => random.nextInt(256));
    final iv = enc.IV(Uint8List.fromList(ivBytes));
    
    final key = enc.Key(derivedKey);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    
    return '${base64Encode(ivBytes)}:${encrypted.base64}';
  }
  
  /// فك تشفير البيانات
  static Future<String> decryptData(String encryptedData, String groupId) async {
    final keyData = await getOrCreateGroupKey(groupId);
    final derivedKey = _deriveKey(keyData.key, keyData.salt);
    
    final parts = encryptedData.split(':');
    if (parts.length != 2) {
      throw const FormatException('تنسيق البيانات المشفرة غير صحيح');
    }
    
    final ivBytes = base64Decode(parts[0]);
    final encryptedBytes = parts[1];
    
    final key = enc.Key(derivedKey);
    final iv = enc.IV(Uint8List.fromList(ivBytes));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    
    return encrypter.decrypt64(encryptedBytes, iv: iv);
  }
  
  /// تشفير Map (JSON)
  static Future<String> encryptJson(Map<String, dynamic> data, String groupId) async {
    final jsonString = jsonEncode(data);
    return await encryptData(jsonString, groupId);
  }
  
  /// فك تشفير إلى Map (JSON)
  static Future<Map<String, dynamic>> decryptJson(String encryptedData, String groupId) async {
    final jsonString = await decryptData(encryptedData, groupId);
    return jsonDecode(jsonString) as Map<String, dynamic>;
  }
  
  /// تشفير bytes
  static Future<Uint8List> encryptBytes(Uint8List plainBytes, String groupId) async {
    final keyData = await getOrCreateGroupKey(groupId);
    final derivedKey = _deriveKey(keyData.key, keyData.salt);
    
    final random = Random.secure();
    final ivBytes = Uint8List.fromList(
      List<int>.generate(_ivLength, (_) => random.nextInt(256))
    );
    
    final key = enc.Key(derivedKey);
    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    
    final encrypted = encrypter.encryptBytes(plainBytes, iv: iv);
    
    final combined = Uint8List(_ivLength + encrypted.bytes.length);
    combined.setRange(0, _ivLength, ivBytes);
    combined.setRange(_ivLength, combined.length, encrypted.bytes);
    
    return combined;
  }
  
  /// فك تشفير bytes
  static Future<Uint8List> decryptBytes(Uint8List encryptedBytes, String groupId) async {
    if (encryptedBytes.length < _ivLength) {
      throw const FormatException('البيانات المشفرة قصيرة جداً');
    }
    
    final keyData = await getOrCreateGroupKey(groupId);
    final derivedKey = _deriveKey(keyData.key, keyData.salt);
    
    final ivBytes = encryptedBytes.sublist(0, _ivLength);
    final dataBytes = encryptedBytes.sublist(_ivLength);
    
    final key = enc.Key(derivedKey);
    final iv = enc.IV(ivBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    
    final decrypted = encrypter.decryptBytes(enc.Encrypted(dataBytes), iv: iv);
    
    return Uint8List.fromList(decrypted);
  }
  
  /// التحقق من وجود مفتاح للمجموعة
  static Future<bool> hasGroupKey(String groupId) async {
    final key = await getGroupKey(groupId);
    return key != null && key.isNotEmpty;
  }
  
  /// تصدير مفتاح المجموعة
  static Future<String?> exportGroupKey(String groupId) async {
    final key = await getGroupKey(groupId);
    final salt = await getGroupSalt(groupId);
    
    if (key == null || salt == null) return null;
    
    final exportData = {
      'group_id': groupId,
      'key': key,
      'salt': salt,
      'version': 1,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
    };
    
    return base64Url.encode(utf8.encode(jsonEncode(exportData)));
  }
  
  /// استيراد مفتاح المجموعة
  static Future<bool> importGroupKey(String exportedKey) async {
    try {
      final jsonString = utf8.decode(base64Url.decode(exportedKey));
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      
      final groupId = data['group_id'] as String;
      final key = data['key'] as String;
      final salt = data['salt'] as String;
      
      await saveGroupKey(groupId, key);
      await saveGroupSalt(groupId, salt);
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// حساب hash للتحقق من سلامة البيانات
  static String calculateIntegrityHash(String encryptedData) {
    return sha256.convert(utf8.encode(encryptedData)).toString().substring(0, 16);
  }
  
  /// التحقق من سلامة البيانات
  static bool verifyIntegrity(String encryptedData, String expectedHash) {
    final actualHash = calculateIntegrityHash(encryptedData);
    return actualHash == expectedHash;
  }
}

/// نتيجة عملية التشفير
class EncryptionResult {
  final String encryptedData;
  final String integrityHash;
  
  const EncryptionResult({
    required this.encryptedData,
    required this.integrityHash,
  });
  
  Map<String, dynamic> toJson() => {
    'data': encryptedData,
    'hash': integrityHash,
  };
  
  factory EncryptionResult.fromJson(Map<String, dynamic> json) => EncryptionResult(
    encryptedData: json['data'] as String,
    integrityHash: json['hash'] as String,
  );
}
