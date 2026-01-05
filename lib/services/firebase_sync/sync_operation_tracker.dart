// lib/services/firebase_sync/sync_operation_tracker.dart
// نظام تتبع التحديثات والإقرار المحسّن
// يحل مشكلة تعارض التحديثات بين الأجهزة

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sqflite/sqflite.dart';
import '../database_service.dart';
import 'firebase_sync_config.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// نوع العملية
/// ═══════════════════════════════════════════════════════════════════════════
enum SyncOperationType {
  create,   // إنشاء جديد
  update,   // تحديث
  delete,   // حذف
}

/// ═══════════════════════════════════════════════════════════════════════════
/// نموذج العملية المتتبعة
/// ═══════════════════════════════════════════════════════════════════════════
class TrackedOperation {
  final String syncUuid;
  final String entityType; // 'customer' أو 'transaction'
  final SyncOperationType operationType;
  final int version;
  final int? previousVersion;
  final Map<String, dynamic>? previousData; // البيانات قبل التحديث
  final Map<String, dynamic> currentData;   // البيانات الحالية
  final String originDeviceId;
  final DateTime timestamp;
  final Map<String, DateTime> readBy; // الأجهزة التي قرأت العملية
  final bool canDelete; // هل يمكن حذفها من Firebase

  TrackedOperation({
    required this.syncUuid,
    required this.entityType,
    required this.operationType,
    required this.version,
    this.previousVersion,
    this.previousData,
    required this.currentData,
    required this.originDeviceId,
    required this.timestamp,
    Map<String, DateTime>? readBy,
    this.canDelete = false,
  }) : readBy = readBy ?? {};

  Map<String, dynamic> toFirebaseMap() => {
    'syncUuid': syncUuid,
    'entityType': entityType,
    'operationType': operationType.name,
    'version': version,
    'previousVersion': previousVersion,
    'previousData': previousData,
    'currentData': currentData,
    'originDeviceId': originDeviceId,
    'timestamp': timestamp.toIso8601String(),
    'readBy': readBy.map((k, v) => MapEntry(k, v.toIso8601String())),
    'canDelete': canDelete,
    'uploadedAt': FieldValue.serverTimestamp(),
  };

  factory TrackedOperation.fromFirebaseMap(Map<String, dynamic> map) {
    final readByMap = <String, DateTime>{};
    if (map['readBy'] != null) {
      (map['readBy'] as Map<String, dynamic>).forEach((key, value) {
        if (value is String) {
          readByMap[key] = DateTime.parse(value);
        } else if (value is Timestamp) {
          readByMap[key] = value.toDate();
        }
      });
    }

    return TrackedOperation(
      syncUuid: map['syncUuid'] as String,
      entityType: map['entityType'] as String,
      operationType: SyncOperationType.values.firstWhere(
        (t) => t.name == map['operationType'],
        orElse: () => SyncOperationType.create,
      ),
      version: map['version'] as int? ?? 1,
      previousVersion: map['previousVersion'] as int?,
      previousData: map['previousData'] as Map<String, dynamic>?,
      currentData: map['currentData'] as Map<String, dynamic>? ?? {},
      originDeviceId: map['originDeviceId'] as String? ?? '',
      timestamp: map['timestamp'] is Timestamp
          ? (map['timestamp'] as Timestamp).toDate()
          : DateTime.parse(map['timestamp'] as String? ?? DateTime.now().toIso8601String()),
      readBy: readByMap,
      canDelete: map['canDelete'] as bool? ?? false,
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// خدمة تتبع العمليات
/// ═══════════════════════════════════════════════════════════════════════════
class SyncOperationTracker {
  static final SyncOperationTracker _instance = SyncOperationTracker._internal();
  factory SyncOperationTracker() => _instance;
  SyncOperationTracker._internal();

  final DatabaseService _db = DatabaseService();
  FirebaseFirestore? _firestore;
  String? _groupId;
  String? _deviceId;
  String? _groupSecret;
  bool _isInitialized = false;

  // مؤقت التنظيف التلقائي
  Timer? _cleanupTimer;
  static const Duration _cleanupInterval = Duration(minutes: 15);
  static const Duration _minConnectionTime = Duration(minutes: 15);

  // Stream للإشعار بالعمليات الجديدة
  final _operationController = StreamController<TrackedOperation>.broadcast();
  Stream<TrackedOperation> get onOperationReceived => _operationController.stream;

  // الاستماع للعمليات
  StreamSubscription? _operationsListener;

  /// ═══════════════════════════════════════════════════════════════════════
  /// التهيئة
  /// ═══════════════════════════════════════════════════════════════════════

  Future<void> initialize({
    required FirebaseFirestore firestore,
    required String groupId,
    required String deviceId,
    String? groupSecret,
  }) async {
    if (_isInitialized) return;

    _firestore = firestore;
    _groupId = groupId;
    _deviceId = deviceId;
    _groupSecret = groupSecret;

    // إنشاء الجداول المحلية
    await _createLocalTables();

    // بدء الاستماع للعمليات
    _startListening();

    // بدء مؤقت التنظيف
    _startCleanupTimer();

    _isInitialized = true;
    print('✅ تم تهيئة SyncOperationTracker');
  }

  void dispose() {
    _operationsListener?.cancel();
    _cleanupTimer?.cancel();
    _operationController.close();
    _isInitialized = false;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// إنشاء الجداول المحلية
  /// ═══════════════════════════════════════════════════════════════════════

  Future<void> _createLocalTables() async {
    final db = await _db.database;

    // جدول تتبع إصدارات العمليات
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_operation_versions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_uuid TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        current_version INTEGER DEFAULT 1,
        last_updated_at TEXT NOT NULL,
        UNIQUE(sync_uuid)
      )
    ''');

    // جدول سجل العمليات (للتدقيق)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_operation_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_uuid TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        version INTEGER NOT NULL,
        previous_data TEXT,
        current_data TEXT NOT NULL,
        origin_device_id TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        applied_at TEXT NOT NULL
      )
    ''');

    // جدول حالة الاتصال للأجهزة
    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_connection_status (
        device_id TEXT PRIMARY KEY,
        connected_since TEXT,
        last_seen TEXT NOT NULL,
        is_online INTEGER DEFAULT 0
      )
    ''');

    // فهارس للبحث السريع
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_op_versions_uuid 
      ON sync_operation_versions(sync_uuid)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_op_log_uuid 
      ON sync_operation_log(sync_uuid)
    ''');
  }


  /// ═══════════════════════════════════════════════════════════════════════
  /// تسجيل عملية جديدة (عند الإنشاء أو التحديث المحلي)
  /// ═══════════════════════════════════════════════════════════════════════

  /// تسجيل عملية إنشاء جديدة
  Future<TrackedOperation?> trackCreate({
    required String syncUuid,
    required String entityType,
    required Map<String, dynamic> data,
  }) async {
    return await _trackOperation(
      syncUuid: syncUuid,
      entityType: entityType,
      operationType: SyncOperationType.create,
      currentData: data,
      previousData: null,
    );
  }

  /// تسجيل عملية تحديث
  Future<TrackedOperation?> trackUpdate({
    required String syncUuid,
    required String entityType,
    required Map<String, dynamic> previousData,
    required Map<String, dynamic> currentData,
  }) async {
    return await _trackOperation(
      syncUuid: syncUuid,
      entityType: entityType,
      operationType: SyncOperationType.update,
      currentData: currentData,
      previousData: previousData,
    );
  }

  /// تسجيل عملية حذف
  Future<TrackedOperation?> trackDelete({
    required String syncUuid,
    required String entityType,
    required Map<String, dynamic> deletedData,
  }) async {
    return await _trackOperation(
      syncUuid: syncUuid,
      entityType: entityType,
      operationType: SyncOperationType.delete,
      currentData: {'isDeleted': true},
      previousData: deletedData,
    );
  }

  /// تسجيل العملية داخلياً
  Future<TrackedOperation?> _trackOperation({
    required String syncUuid,
    required String entityType,
    required SyncOperationType operationType,
    required Map<String, dynamic> currentData,
    Map<String, dynamic>? previousData,
  }) async {
    if (!_isInitialized || _firestore == null || _groupId == null) return null;

    final db = await _db.database;
    final now = DateTime.now();

    // الحصول على الإصدار الحالي
    final versionResult = await db.query(
      'sync_operation_versions',
      where: 'sync_uuid = ?',
      whereArgs: [syncUuid],
    );

    int currentVersion = 1;
    int? previousVersion;

    if (versionResult.isNotEmpty) {
      previousVersion = versionResult.first['current_version'] as int;
      currentVersion = previousVersion + 1;
    }

    // تحديث الإصدار المحلي
    await db.insert(
      'sync_operation_versions',
      {
        'sync_uuid': syncUuid,
        'entity_type': entityType,
        'current_version': currentVersion,
        'last_updated_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // إنشاء العملية المتتبعة
    final operation = TrackedOperation(
      syncUuid: syncUuid,
      entityType: entityType,
      operationType: operationType,
      version: currentVersion,
      previousVersion: previousVersion,
      previousData: previousData,
      currentData: currentData,
      originDeviceId: _deviceId!,
      timestamp: now,
    );

    // رفع العملية إلى Firebase
    try {
      await _uploadOperation(operation);
      
      // تسجيل في السجل المحلي
      await _logOperation(operation);
      
      print('📤 تم رفع عملية ${operationType.name} للـ $entityType (v$currentVersion)');
      return operation;
    } catch (e) {
      print('❌ فشل رفع العملية: $e');
      return null;
    }
  }

  /// رفع العملية إلى Firebase
  Future<void> _uploadOperation(TrackedOperation operation) async {
    if (_firestore == null || _groupId == null) return;

    final docId = '${operation.syncUuid}_v${operation.version}';
    
    final data = operation.toFirebaseMap();
    if (_groupSecret != null) {
      data['groupSecret'] = _groupSecret;
    }

    await _firestore!
        .collection('sync_groups')
        .doc(_groupId)
        .collection('sync_operations')
        .doc(docId)
        .set(data);
  }

  /// تسجيل العملية في السجل المحلي
  Future<void> _logOperation(TrackedOperation operation) async {
    final db = await _db.database;
    
    await db.insert('sync_operation_log', {
      'sync_uuid': operation.syncUuid,
      'entity_type': operation.entityType,
      'operation_type': operation.operationType.name,
      'version': operation.version,
      'previous_data': operation.previousData != null 
          ? jsonEncode(operation.previousData) 
          : null,
      'current_data': jsonEncode(operation.currentData),
      'origin_device_id': operation.originDeviceId,
      'timestamp': operation.timestamp.toIso8601String(),
      'applied_at': DateTime.now().toIso8601String(),
    });
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// الاستماع للعمليات من الأجهزة الأخرى
  /// ═══════════════════════════════════════════════════════════════════════

  void _startListening() {
    if (_firestore == null || _groupId == null || _deviceId == null) return;

    _operationsListener = _firestore!
        .collection('sync_groups')
        .doc(_groupId)
        .collection('sync_operations')
        .orderBy('timestamp', descending: true)
        .limit(100) // آخر 100 عملية
        .snapshots()
        .listen(_onOperationsChanged);
  }

  Future<void> _onOperationsChanged(QuerySnapshot snapshot) async {
    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;

      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final originDeviceId = data['originDeviceId'] as String?;
      
      // تجاهل العمليات من نفس الجهاز
      if (originDeviceId == _deviceId) continue;

      try {
        final operation = TrackedOperation.fromFirebaseMap(data);
        
        // معالجة العملية
        await _processReceivedOperation(operation, change.doc.id);
        
        // إرسال إشعار
        _operationController.add(operation);
        
      } catch (e) {
        print('❌ خطأ في معالجة العملية: $e');
      }
    }
  }

  /// معالجة عملية مستلمة
  Future<void> _processReceivedOperation(TrackedOperation operation, String docId) async {
    final db = await _db.database;

    // التحقق من الإصدار المحلي
    final localVersion = await db.query(
      'sync_operation_versions',
      where: 'sync_uuid = ?',
      whereArgs: [operation.syncUuid],
    );

    int currentLocalVersion = 0;
    if (localVersion.isNotEmpty) {
      currentLocalVersion = localVersion.first['current_version'] as int;
    }

    // إذا كان الإصدار البعيد أحدث
    if (operation.version > currentLocalVersion) {
      // تحديث الإصدار المحلي
      await db.insert(
        'sync_operation_versions',
        {
          'sync_uuid': operation.syncUuid,
          'entity_type': operation.entityType,
          'current_version': operation.version,
          'last_updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // تسجيل في السجل
      await _logOperation(operation);

      print('📥 عملية ${operation.operationType.name} v${operation.version} من ${operation.originDeviceId}');
    }

    // تعليم العملية كمقروءة
    await _markAsRead(docId);
  }

  /// تعليم العملية كمقروءة من هذا الجهاز
  Future<void> _markAsRead(String docId) async {
    if (_firestore == null || _groupId == null || _deviceId == null) return;

    try {
      await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('sync_operations')
          .doc(docId)
          .update({
        'readBy.$_deviceId': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // قد تفشل إذا لم يكن لدينا صلاحية
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// التنظيف التلقائي
  /// ═══════════════════════════════════════════════════════════════════════

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _performCleanup();
    });
  }

  /// تنظيف العمليات المقروءة من جميع الأجهزة
  Future<void> _performCleanup() async {
    if (_firestore == null || _groupId == null) return;

    try {
      // جلب الأجهزة المتصلة
      final devicesSnapshot = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('devices')
          .get();

      final onlineDevices = <String>[];
      final now = DateTime.now();

      for (final doc in devicesSnapshot.docs) {
        final data = doc.data();
        final lastSeen = data['lastSeen'];
        DateTime? lastSeenDate;

        if (lastSeen is Timestamp) {
          lastSeenDate = lastSeen.toDate();
        } else if (lastSeen is String) {
          lastSeenDate = DateTime.tryParse(lastSeen);
        }

        // الجهاز متصل إذا كان آخر ظهور له خلال دقيقة
        if (lastSeenDate != null && now.difference(lastSeenDate).inMinutes < 1) {
          onlineDevices.add(doc.id);
        }
      }

      // إذا كان هناك أقل من جهازين متصلين، لا نحذف
      if (onlineDevices.length < 2) return;

      // جلب العمليات القابلة للحذف
      final operationsSnapshot = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('sync_operations')
          .get();

      int deletedCount = 0;

      for (final doc in operationsSnapshot.docs) {
        final data = doc.data();
        final readBy = data['readBy'] as Map<String, dynamic>? ?? {};
        final timestamp = data['timestamp'];
        
        DateTime? operationTime;
        if (timestamp is Timestamp) {
          operationTime = timestamp.toDate();
        } else if (timestamp is String) {
          operationTime = DateTime.tryParse(timestamp);
        }

        // التحقق من أن جميع الأجهزة المتصلة قرأت العملية
        bool allDevicesRead = true;
        for (final deviceId in onlineDevices) {
          if (!readBy.containsKey(deviceId)) {
            allDevicesRead = false;
            break;
          }
        }

        // التحقق من مرور 15 دقيقة على العملية
        bool isOldEnough = operationTime != null && 
            now.difference(operationTime) >= _minConnectionTime;

        // حذف العملية إذا قرأها الجميع ومر عليها 15 دقيقة
        if (allDevicesRead && isOldEnough) {
          await doc.reference.delete();
          deletedCount++;
        }
      }

      if (deletedCount > 0) {
        print('🧹 تم حذف $deletedCount عملية مقروءة من Firebase');
      }

    } catch (e) {
      print('❌ خطأ في التنظيف: $e');
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// أدوات مساعدة
  /// ═══════════════════════════════════════════════════════════════════════

  /// الحصول على إصدار العملية الحالي
  Future<int> getCurrentVersion(String syncUuid) async {
    final db = await _db.database;
    
    final result = await db.query(
      'sync_operation_versions',
      where: 'sync_uuid = ?',
      whereArgs: [syncUuid],
    );

    if (result.isEmpty) return 0;
    return result.first['current_version'] as int;
  }

  /// الحصول على سجل العمليات لكيان معين
  Future<List<Map<String, dynamic>>> getOperationLog(String syncUuid) async {
    final db = await _db.database;
    
    return await db.query(
      'sync_operation_log',
      where: 'sync_uuid = ?',
      whereArgs: [syncUuid],
      orderBy: 'version DESC',
    );
  }

  /// الحصول على إحصائيات
  Future<Map<String, dynamic>> getStats() async {
    if (_firestore == null || _groupId == null) {
      return {'error': 'غير مُعد'};
    }

    try {
      final operationsCount = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('sync_operations')
          .count()
          .get();

      final db = await _db.database;
      final localVersions = await db.rawQuery(
        'SELECT COUNT(*) as count FROM sync_operation_versions'
      );
      final localLogs = await db.rawQuery(
        'SELECT COUNT(*) as count FROM sync_operation_log'
      );

      return {
        'pendingOperations': operationsCount.count ?? 0,
        'trackedEntities': localVersions.first['count'] ?? 0,
        'logEntries': localLogs.first['count'] ?? 0,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// تنظيف السجلات القديمة (أكثر من 30 يوم)
  Future<int> cleanupOldLogs() async {
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(const Duration(days: 30)).toIso8601String();

    final deleted = await db.delete(
      'sync_operation_log',
      where: 'applied_at < ?',
      whereArgs: [cutoff],
    );

    if (deleted > 0) {
      print('🧹 تم حذف $deleted سجل قديم');
    }

    return deleted;
  }
}
