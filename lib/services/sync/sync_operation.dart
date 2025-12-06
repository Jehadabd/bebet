// lib/services/sync/sync_operation.dart
// نموذج العملية في نظام المزامنة

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'sync_models.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// Causality Vector - لتتبع السببية بين العمليات
/// ═══════════════════════════════════════════════════════════════════════════
class CausalityVector {
  final Map<String, int> _vector;

  CausalityVector([Map<String, int>? initial]) 
    : _vector = Map.from(initial ?? {});

  Map<String, int> get vector => Map.unmodifiable(_vector);

  /// زيادة العداد للجهاز الحالي
  void increment(String deviceId) {
    _vector[deviceId] = (_vector[deviceId] ?? 0) + 1;
  }

  /// الحصول على قيمة جهاز معين
  int get(String deviceId) => _vector[deviceId] ?? 0;

  /// دمج مع vector آخر (أخذ الأعلى لكل جهاز)
  void merge(CausalityVector other) {
    for (final entry in other._vector.entries) {
      final current = _vector[entry.key] ?? 0;
      if (entry.value > current) {
        _vector[entry.key] = entry.value;
      }
    }
  }

  /// هل هذا الـ vector يسبق الآخر؟
  bool happensBefore(CausalityVector other) {
    bool atLeastOneLess = false;
    final allKeys = {..._vector.keys, ...other._vector.keys};
    
    for (final deviceId in allKeys) {
      final thisValue = _vector[deviceId] ?? 0;
      final otherValue = other._vector[deviceId] ?? 0;
      if (thisValue > otherValue) return false;
      if (thisValue < otherValue) atLeastOneLess = true;
    }
    return atLeastOneLess;
  }

  /// هل هناك تعارض (لا أحد يسبق الآخر)؟
  bool conflictsWith(CausalityVector other) {
    return !happensBefore(other) && !other.happensBefore(this) && this != other;
  }

  /// نسخ
  CausalityVector copy() => CausalityVector(Map.from(_vector));

  Map<String, dynamic> toJson() => Map.from(_vector);

  factory CausalityVector.fromJson(Map<String, dynamic>? json) {
    if (json == null) return CausalityVector();
    return CausalityVector(json.map((k, v) => MapEntry(k, v as int)));
  }

  @override
  bool operator ==(Object other) {
    if (other is! CausalityVector) return false;
    if (_vector.length != other._vector.length) return false;
    for (final key in _vector.keys) {
      if (_vector[key] != other._vector[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode => _vector.hashCode;

  @override
  String toString() => 'CausalityVector($_vector)';
}

/// ═══════════════════════════════════════════════════════════════════════════
/// نموذج العملية (Sync Operation)
/// ═══════════════════════════════════════════════════════════════════════════
class SyncOperation {
  final String operationId;
  final int globalSequence;
  final int localSequence;
  final String deviceId;
  final DateTime timestamp;
  final SyncOperationType operationType;
  final String entityType;
  final String entityUuid;
  final String? customerUuid;
  final Map<String, dynamic>? payloadBefore;
  final Map<String, dynamic> payloadAfter;
  final String checksum;
  final String signature;
  final String? parentOperationId;
  final CausalityVector causalityVector;
  final Map<String, OperationAcknowledgment> acknowledgments;
  final OperationStatus status;

  SyncOperation({
    required this.operationId,
    required this.globalSequence,
    required this.localSequence,
    required this.deviceId,
    required this.timestamp,
    required this.operationType,
    required this.entityType,
    required this.entityUuid,
    this.customerUuid,
    this.payloadBefore,
    required this.payloadAfter,
    required this.checksum,
    required this.signature,
    this.parentOperationId,
    required this.causalityVector,
    Map<String, OperationAcknowledgment>? acknowledgments,
    this.status = OperationStatus.pending,
  }) : acknowledgments = acknowledgments ?? {};

  /// إنشاء عملية جديدة
  factory SyncOperation.create({
    required String deviceId,
    required int localSequence,
    required SyncOperationType operationType,
    required String entityType,
    required String entityUuid,
    String? customerUuid,
    Map<String, dynamic>? payloadBefore,
    required Map<String, dynamic> payloadAfter,
    String? parentOperationId,
    required CausalityVector causalityVector,
    required String secretKey,
  }) {
    final now = DateTime.now().toUtc();
    final operationId = _generateOperationId(deviceId, now, localSequence);
    
    // حساب checksum للـ payload
    final payloadJson = jsonEncode({
      'before': payloadBefore,
      'after': payloadAfter,
    });
    final checksum = sha256.convert(utf8.encode(payloadJson)).toString();
    
    // حساب التوقيع
    final dataToSign = '$operationId|$deviceId|$localSequence|$checksum';
    final signature = _signData(dataToSign, secretKey);
    
    return SyncOperation(
      operationId: operationId,
      globalSequence: 0, // سيتم تعيينه عند الرفع
      localSequence: localSequence,
      deviceId: deviceId,
      timestamp: now,
      operationType: operationType,
      entityType: entityType,
      entityUuid: entityUuid,
      customerUuid: customerUuid,
      payloadBefore: payloadBefore,
      payloadAfter: payloadAfter,
      checksum: checksum,
      signature: signature,
      parentOperationId: parentOperationId,
      causalityVector: causalityVector,
    );
  }

  static String _generateOperationId(String deviceId, DateTime timestamp, int sequence) {
    final ts = timestamp.toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    return 'op_${ts}_${deviceId.substring(0, 8)}_$sequence';
  }

  static String _signData(String data, String secretKey) {
    final key = utf8.encode(secretKey);
    final bytes = utf8.encode(data);
    final hmac = Hmac(sha256, key);
    return hmac.convert(bytes).toString();
  }

  /// التحقق من صحة التوقيع
  bool verifySignature(String secretKey) {
    final dataToSign = '$operationId|$deviceId|$localSequence|$checksum';
    final expectedSignature = _signData(dataToSign, secretKey);
    return signature == expectedSignature;
  }

  /// التحقق من صحة الـ checksum
  bool verifyChecksum() {
    final payloadJson = jsonEncode({
      'before': payloadBefore,
      'after': payloadAfter,
    });
    final expectedChecksum = sha256.convert(utf8.encode(payloadJson)).toString();
    return checksum == expectedChecksum;
  }

  Map<String, dynamic> toJson() => {
    'operation_id': operationId,
    'global_sequence': globalSequence,
    'local_sequence': localSequence,
    'device_id': deviceId,
    'timestamp': timestamp.toIso8601String(),
    'operation_type': operationType.name,
    'entity': {
      'type': entityType,
      'uuid': entityUuid,
      if (customerUuid != null) 'customer_uuid': customerUuid,
    },
    'payload': {
      'before': payloadBefore,
      'after': payloadAfter,
    },
    'metadata': {
      'checksum': checksum,
      'signature': signature,
      'parent_operation': parentOperationId,
      'causality_vector': causalityVector.toJson(),
    },
    'acknowledgments': acknowledgments.map((k, v) => MapEntry(k, v.toJson())),
    'status': status.name,
  };

  factory SyncOperation.fromJson(Map<String, dynamic> json) {
    final entity = json['entity'] as Map<String, dynamic>? ?? {};
    final payload = json['payload'] as Map<String, dynamic>? ?? {};
    final metadata = json['metadata'] as Map<String, dynamic>? ?? {};
    final acksJson = json['acknowledgments'] as Map<String, dynamic>? ?? {};
    
    return SyncOperation(
      operationId: json['operation_id'] as String,
      globalSequence: json['global_sequence'] as int? ?? 0,
      localSequence: json['local_sequence'] as int? ?? 0,
      deviceId: json['device_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      operationType: SyncOperationType.values.firstWhere(
        (e) => e.name == json['operation_type'],
        orElse: () => SyncOperationType.transactionCreate,
      ),
      entityType: entity['type'] as String? ?? 'transaction',
      entityUuid: entity['uuid'] as String? ?? '',
      customerUuid: entity['customer_uuid'] as String?,
      payloadBefore: payload['before'] as Map<String, dynamic>?,
      payloadAfter: payload['after'] as Map<String, dynamic>? ?? {},
      checksum: metadata['checksum'] as String? ?? '',
      signature: metadata['signature'] as String? ?? '',
      parentOperationId: metadata['parent_operation'] as String?,
      causalityVector: CausalityVector.fromJson(
        metadata['causality_vector'] as Map<String, dynamic>?,
      ),
      acknowledgments: acksJson.map(
        (k, v) => MapEntry(k, OperationAcknowledgment.fromJson(v as Map<String, dynamic>)),
      ),
      status: OperationStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => OperationStatus.pending,
      ),
    );
  }

  SyncOperation copyWith({
    int? globalSequence,
    Map<String, OperationAcknowledgment>? acknowledgments,
    OperationStatus? status,
  }) => SyncOperation(
    operationId: operationId,
    globalSequence: globalSequence ?? this.globalSequence,
    localSequence: localSequence,
    deviceId: deviceId,
    timestamp: timestamp,
    operationType: operationType,
    entityType: entityType,
    entityUuid: entityUuid,
    customerUuid: customerUuid,
    payloadBefore: payloadBefore,
    payloadAfter: payloadAfter,
    checksum: checksum,
    signature: signature,
    parentOperationId: parentOperationId,
    causalityVector: causalityVector,
    acknowledgments: acknowledgments ?? this.acknowledgments,
    status: status ?? this.status,
  );
}

/// ═══════════════════════════════════════════════════════════════════════════
/// تأكيد استلام العملية
/// ═══════════════════════════════════════════════════════════════════════════
class OperationAcknowledgment {
  final String deviceId;
  final DateTime receivedAt;
  final DateTime? appliedAt;
  final String status; // RECEIVED, APPLIED, FAILED, CONFLICT

  OperationAcknowledgment({
    required this.deviceId,
    required this.receivedAt,
    this.appliedAt,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'received_at': receivedAt.toIso8601String(),
    if (appliedAt != null) 'applied_at': appliedAt!.toIso8601String(),
    'status': status,
  };

  factory OperationAcknowledgment.fromJson(Map<String, dynamic> json) => OperationAcknowledgment(
    deviceId: json['device_id'] as String? ?? '',
    receivedAt: DateTime.parse(json['received_at'] as String),
    appliedAt: json['applied_at'] != null ? DateTime.parse(json['applied_at'] as String) : null,
    status: json['status'] as String? ?? 'RECEIVED',
  );
}

/// ═══════════════════════════════════════════════════════════════════════════
/// تعارض مكتشف
/// ═══════════════════════════════════════════════════════════════════════════
class SyncConflict {
  final String conflictId;
  final DateTime detectedAt;
  final String entityType;
  final String entityUuid;
  final SyncOperation localOperation;
  final SyncOperation remoteOperation;
  final String conflictType; // UPDATE_UPDATE, UPDATE_DELETE, etc.
  final String? resolution; // LOCAL_WINS, REMOTE_WINS, MERGED, MANUAL
  final Map<String, dynamic>? resolvedData;
  final DateTime? resolvedAt;

  SyncConflict({
    required this.conflictId,
    required this.detectedAt,
    required this.entityType,
    required this.entityUuid,
    required this.localOperation,
    required this.remoteOperation,
    required this.conflictType,
    this.resolution,
    this.resolvedData,
    this.resolvedAt,
  });

  Map<String, dynamic> toJson() => {
    'conflict_id': conflictId,
    'detected_at': detectedAt.toIso8601String(),
    'entity_type': entityType,
    'entity_uuid': entityUuid,
    'local_operation': localOperation.toJson(),
    'remote_operation': remoteOperation.toJson(),
    'conflict_type': conflictType,
    if (resolution != null) 'resolution': resolution,
    if (resolvedData != null) 'resolved_data': resolvedData,
    if (resolvedAt != null) 'resolved_at': resolvedAt!.toIso8601String(),
  };

  factory SyncConflict.fromJson(Map<String, dynamic> json) => SyncConflict(
    conflictId: json['conflict_id'] as String,
    detectedAt: DateTime.parse(json['detected_at'] as String),
    entityType: json['entity_type'] as String,
    entityUuid: json['entity_uuid'] as String,
    localOperation: SyncOperation.fromJson(json['local_operation'] as Map<String, dynamic>),
    remoteOperation: SyncOperation.fromJson(json['remote_operation'] as Map<String, dynamic>),
    conflictType: json['conflict_type'] as String,
    resolution: json['resolution'] as String?,
    resolvedData: json['resolved_data'] as Map<String, dynamic>?,
    resolvedAt: json['resolved_at'] != null ? DateTime.parse(json['resolved_at'] as String) : null,
  );
}
