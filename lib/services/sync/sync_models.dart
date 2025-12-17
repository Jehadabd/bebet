// lib/services/sync/sync_models.dart
// نماذج البيانات لنظام المزامنة فائق الأمان

import 'dart:convert';
import 'package:crypto/crypto.dart';

/// أنواع العمليات المدعومة في المزامنة
enum SyncOperationType {
  // عمليات العملاء
  customerCreate,
  customerUpdate,
  customerDelete,
  
  // عمليات المعاملات
  transactionCreate,
  transactionUpdate,
  transactionDelete,
  
  // عمليات خاصة
  balanceRecalculate,
  bulkImport,
  dataCorrection,
}

/// حالة العملية
enum OperationStatus {
  pending,    // في انتظار الرفع
  uploaded,   // تم الرفع
  applied,    // تم التطبيق على جهاز آخر
  confirmed,  // تم التأكيد من جميع الأجهزة
  failed,     // فشلت
}

/// أنواع أخطاء المزامنة
enum SyncErrorType {
  networkError,
  lockAcquisitionFailed,
  lockExpired,
  signatureInvalid,
  checksumMismatch,
  sequenceGap,
  conflictDetected,
  rollbackRequired,
  quotaExceeded,
  authenticationFailed,
  unknownError,
}

/// حالة القفل
enum LockStatus {
  free,       // القفل متاح
  acquired,   // تم الحصول على القفل
  busy,       // القفل مشغول بجهاز آخر
  expired,    // القفل منتهي الصلاحية
}

/// ═══════════════════════════════════════════════════════════════════════════
/// نموذج القفل الموزع (Distributed Lock)
/// ═══════════════════════════════════════════════════════════════════════════
class SyncLock {
  final String lockId;
  final String deviceId;
  final String deviceName;
  final DateTime acquiredAt;
  final DateTime expiresAt;
  final String operationType;
  final DateTime heartbeat;
  final String signature;

  SyncLock({
    required this.lockId,
    required this.deviceId,
    required this.deviceName,
    required this.acquiredAt,
    required this.expiresAt,
    required this.operationType,
    required this.heartbeat,
    required this.signature,
  });

  /// هل انتهت صلاحية القفل؟
  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  /// الوقت المتبقي بالثواني
  int get remainingSeconds => 
    isExpired ? 0 : expiresAt.difference(DateTime.now().toUtc()).inSeconds;

  Map<String, dynamic> toJson() => {
    'lock_id': lockId,
    'device_id': deviceId,
    'device_name': deviceName,
    'acquired_at': acquiredAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'operation_type': operationType,
    'heartbeat': heartbeat.toIso8601String(),
    'signature': signature,
  };

  factory SyncLock.fromJson(Map<String, dynamic> json) => SyncLock(
    lockId: json['lock_id'] as String,
    deviceId: json['device_id'] as String,
    deviceName: json['device_name'] as String? ?? 'Unknown',
    acquiredAt: DateTime.parse(json['acquired_at'] as String),
    expiresAt: DateTime.parse(json['expires_at'] as String),
    operationType: json['operation_type'] as String,
    heartbeat: DateTime.parse(json['heartbeat'] as String),
    signature: json['signature'] as String,
  );
}

/// ═══════════════════════════════════════════════════════════════════════════
/// نموذج حالة الجهاز في الفهرس
/// ═══════════════════════════════════════════════════════════════════════════
class DeviceState {
  final String deviceId;
  final String deviceName;
  final DateTime firstSeen;
  final DateTime lastSync;
  final int localSequence;
  final int syncedUpToGlobal;
  final int pendingOperations;
  final String status;
  final String appVersion;

  DeviceState({
    required this.deviceId,
    required this.deviceName,
    required this.firstSeen,
    required this.lastSync,
    required this.localSequence,
    required this.syncedUpToGlobal,
    required this.pendingOperations,
    this.status = 'ACTIVE',
    this.appVersion = '1.0.0',
  });

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'name': deviceName,
    'first_seen': firstSeen.toIso8601String(),
    'last_sync': lastSync.toIso8601String(),
    'local_sequence': localSequence,
    'synced_up_to_global': syncedUpToGlobal,
    'pending_operations': pendingOperations,
    'status': status,
    'app_version': appVersion,
  };

  factory DeviceState.fromJson(String deviceId, Map<String, dynamic> json) => DeviceState(
    deviceId: deviceId,
    deviceName: json['name'] as String? ?? 'Unknown',
    appVersion: json['app_version'] as String? ?? '1.0.0',
    firstSeen: DateTime.parse(json['first_seen'] as String),
    lastSync: DateTime.parse(json['last_sync'] as String),
    localSequence: json['local_sequence'] as int? ?? 0,
    syncedUpToGlobal: json['synced_up_to_global'] as int? ?? 0,
    pendingOperations: json['pending_operations'] as int? ?? 0,
    status: json['status'] as String? ?? 'ACTIVE',
  );

  DeviceState copyWith({
    String? deviceName,
    DateTime? lastSync,
    int? localSequence,
    int? syncedUpToGlobal,
    int? pendingOperations,
    String? status,
  }) => DeviceState(
    deviceId: deviceId,
    deviceName: deviceName ?? this.deviceName,
    firstSeen: firstSeen,
    lastSync: lastSync ?? this.lastSync,
    localSequence: localSequence ?? this.localSequence,
    syncedUpToGlobal: syncedUpToGlobal ?? this.syncedUpToGlobal,
    pendingOperations: pendingOperations ?? this.pendingOperations,
    status: status ?? this.status,
    appVersion: appVersion ?? this.appVersion,
  );
}

/// ═══════════════════════════════════════════════════════════════════════════
/// نموذج الفهرس الرئيسي (Manifest)
/// ═══════════════════════════════════════════════════════════════════════════
class SyncManifest {
  final String schemaVersion;
  final String appVersion;
  final int globalSequence;
  final DateTime lastModified;
  final String lastModifiedBy;
  final String checksum;
  final Map<String, DeviceState> devices;
  final Map<String, EntityState> entities;
  final String merkleRoot;

  SyncManifest({
    this.schemaVersion = '2.0.0',
    this.appVersion = '1.0.0',
    required this.globalSequence,
    required this.lastModified,
    required this.lastModifiedBy,
    required this.checksum,
    required this.devices,
    required this.entities,
    required this.merkleRoot,
  });

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'app_version': appVersion,
    'global_sequence': globalSequence,
    'last_modified': lastModified.toIso8601String(),
    'last_modified_by': lastModifiedBy,
    'checksum': checksum,
    'devices': devices.map((k, v) => MapEntry(k, v.toJson())),
    'entities': entities.map((k, v) => MapEntry(k, v.toJson())),
    'integrity': {
      'merkle_root': merkleRoot,
      'verification_timestamp': DateTime.now().toUtc().toIso8601String(),
    },
  };

  factory SyncManifest.fromJson(Map<String, dynamic> json) {
    final devicesJson = json['devices'] as Map<String, dynamic>? ?? {};
    final entitiesJson = json['entities'] as Map<String, dynamic>? ?? {};
    final integrityJson = json['integrity'] as Map<String, dynamic>? ?? {};
    
    return SyncManifest(
      schemaVersion: json['schema_version'] as String? ?? '2.0.0',
      appVersion: json['app_version'] as String? ?? '1.0.0',
      globalSequence: json['global_sequence'] as int? ?? 0,
      lastModified: DateTime.parse(json['last_modified'] as String? ?? DateTime.now().toIso8601String()),
      lastModifiedBy: json['last_modified_by'] as String? ?? '',
      checksum: json['checksum'] as String? ?? '',
      devices: devicesJson.map((k, v) => MapEntry(k, DeviceState.fromJson(k, v as Map<String, dynamic>))),
      entities: entitiesJson.map((k, v) => MapEntry(k, EntityState.fromJson(k, v as Map<String, dynamic>))),
      merkleRoot: integrityJson['merkle_root'] as String? ?? '',
    );
  }

  /// إنشاء manifest فارغ جديد
  factory SyncManifest.empty(String deviceId) => SyncManifest(
    globalSequence: 0,
    lastModified: DateTime.now().toUtc(),
    lastModifiedBy: deviceId,
    checksum: '',
    devices: {},
    entities: {
      'customers': EntityState(name: 'customers', count: 0, lastModified: DateTime.now().toUtc(), checksum: ''),
      'transactions': EntityState(name: 'transactions', count: 0, lastModified: DateTime.now().toUtc(), checksum: ''),
    },
    merkleRoot: '',
  );

  SyncManifest copyWith({
    int? globalSequence,
    DateTime? lastModified,
    String? lastModifiedBy,
    String? checksum,
    Map<String, DeviceState>? devices,
    Map<String, EntityState>? entities,
    String? merkleRoot,
    String? appVersion,
  }) => SyncManifest(
    schemaVersion: schemaVersion,
    appVersion: appVersion ?? this.appVersion,
    globalSequence: globalSequence ?? this.globalSequence,
    lastModified: lastModified ?? this.lastModified,
    lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
    checksum: checksum ?? this.checksum,
    devices: devices ?? this.devices,
    entities: entities ?? this.entities,
    merkleRoot: merkleRoot ?? this.merkleRoot,
  );
}

/// حالة كيان (جدول) في الفهرس
class EntityState {
  final String name;
  final int count;
  final DateTime lastModified;
  final String checksum;

  EntityState({
    required this.name,
    required this.count,
    required this.lastModified,
    required this.checksum,
  });

  Map<String, dynamic> toJson() => {
    'count': count,
    'last_modified': lastModified.toIso8601String(),
    'checksum': checksum,
  };

  factory EntityState.fromJson(String name, Map<String, dynamic> json) => EntityState(
    name: name,
    count: json['count'] as int? ?? 0,
    lastModified: DateTime.parse(json['last_modified'] as String? ?? DateTime.now().toIso8601String()),
    checksum: json['checksum'] as String? ?? '',
  );
}
