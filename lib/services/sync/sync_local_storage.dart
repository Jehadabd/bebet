// lib/services/sync/sync_local_storage.dart
// التخزين المحلي لعمليات المزامنة

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database_service.dart';
import 'sync_models.dart';
import 'sync_operation.dart';
import 'sync_security.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// خدمة التخزين المحلي للمزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncLocalStorage {
  final DatabaseService _db;
  
  SyncLocalStorage([DatabaseService? db]) : _db = db ?? DatabaseService();

  // متغير لتتبع حالة التهيئة
  static bool _tablesInitialized = false;
  static final _initLock = Object();
  
  /// تهيئة جداول المزامنة
  Future<void> ensureSyncTables() async {
    // تجنب التهيئة المتكررة
    if (_tablesInitialized) return;
    
    try {
      final db = await _db.database;
      
      // تم نقل إنشاء الجداول إلى DatabaseService لتفادي مشاكل القفل (Database Locked)
      // نحن نعتمد الآن على أن الجداول موجودة بالفعل بفضل DatabaseService._initDatabase
      
      // تعيين sync_uuid للسجلات الموجودة التي ليس لها uuid
      await _assignMissingSyncUuids(db);
      
      _tablesInitialized = true;
      print('✅ تم تهيئة جداول المزامنة بنجاح');
      
    } catch (e) {
      print('⚠️ خطأ في تهيئة جداول المزامنة: $e');
      // إعادة المحاولة بعد تأخير قصير
      await Future.delayed(const Duration(milliseconds: 500));
      rethrow;
    }
  }

  Future<void> _ensureColumn(Database db, String table, String column, String type) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      final hasColumn = info.any((col) => col['name'] == column);
      if (!hasColumn) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
        print('✅ تم إضافة عمود $column إلى جدول $table');
      }
    } catch (e) {
      print('⚠️ خطأ في إضافة عمود $column: $e');
    }
  }

  Future<void> _assignMissingSyncUuids(Database db) async {
    // تعيين sync_uuid للعملاء
    final customersWithoutUuid = await db.query(
      'customers',
      where: 'sync_uuid IS NULL',
    );
    
    for (final customer in customersWithoutUuid) {
      final uuid = SyncSecurity.generateUuid();
      await db.update(
        'customers',
        {'sync_uuid': uuid},
        where: 'id = ?',
        whereArgs: [customer['id']],
      );
    }
    
    if (customersWithoutUuid.isNotEmpty) {
      print('✅ تم تعيين sync_uuid لـ ${customersWithoutUuid.length} عميل');
    }
    
    // تعيين sync_uuid للمعاملات (استخدام transaction_uuid إذا كان موجوداً)
    final transactionsWithoutUuid = await db.query(
      'transactions',
      where: 'sync_uuid IS NULL',
    );
    
    for (final tx in transactionsWithoutUuid) {
      final existingUuid = tx['transaction_uuid'] as String?;
      final uuid = existingUuid ?? SyncSecurity.generateUuid();
      await db.update(
        'transactions',
        {'sync_uuid': uuid},
        where: 'id = ?',
        whereArgs: [tx['id']],
      );
    }
    
    if (transactionsWithoutUuid.isNotEmpty) {
      print('✅ تم تعيين sync_uuid لـ ${transactionsWithoutUuid.length} معاملة');
    }
  }

  /// حفظ حالة المزامنة
  Future<void> saveSyncState({
    required String deviceId,
    String? deviceName,
    required int localSequence,
    required int syncedUpToGlobal,
  }) async {
    final db = await _db.database;
    
    await db.insert(
      'sync_state',
      {
        'id': 1,
        'device_id': deviceId,
        'device_name': deviceName,
        'local_sequence': localSequence,
        'synced_up_to_global': syncedUpToGlobal,
        'last_sync_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// قراءة حالة المزامنة
  Future<Map<String, dynamic>?> getSyncState() async {
    final db = await _db.database;
    final results = await db.query('sync_state', where: 'id = 1');
    return results.isNotEmpty ? results.first : null;
  }

  /// الحصول على التسلسل المحلي التالي
  Future<int> getNextLocalSequence(String deviceId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT MAX(local_sequence) as max_seq FROM sync_operations WHERE device_id = ?',
      [deviceId],
    );
    return ((result.first['max_seq'] as int?) ?? 0) + 1;
  }

  /// حفظ عملية جديدة
  Future<void> saveOperation(SyncOperation operation) async {
    final db = await _db.database;
    
    await db.insert(
      'sync_operations',
      {
        'operation_id': operation.operationId,
        'device_id': operation.deviceId,
        'local_sequence': operation.localSequence,
        'global_sequence': operation.globalSequence,
        'operation_type': operation.operationType.name,
        'entity_type': operation.entityType,
        'entity_uuid': operation.entityUuid,
        'customer_uuid': operation.customerUuid,
        'payload_before': operation.payloadBefore != null ? jsonEncode(operation.payloadBefore) : null,
        'payload_after': jsonEncode(operation.payloadAfter),
        'checksum': operation.checksum,
        'signature': operation.signature,
        'parent_operation_id': operation.parentOperationId,
        'causality_vector': jsonEncode(operation.causalityVector.toJson()),
        'status': operation.status.name,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'data': jsonEncode(operation.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// الحصول على العمليات المعلقة
  Future<List<SyncOperation>> getPendingOperations() async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_operations',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'local_sequence ASC',
    );
    
    return rows.map((r) {
      final data = jsonDecode(r['data'] as String) as Map<String, dynamic>;
      return SyncOperation.fromJson(data);
    }).toList();
  }

  /// تحديث حالة العملية
  Future<void> updateOperationStatus(
    String operationId,
    OperationStatus status, {
    int? globalSequence,
  }) async {
    final db = await _db.database;
    
    final updates = <String, dynamic>{
      'status': status.name,
    };
    
    if (globalSequence != null) {
      updates['global_sequence'] = globalSequence;
    }
    
    if (status == OperationStatus.uploaded) {
      updates['uploaded_at'] = DateTime.now().toUtc().toIso8601String();
    }
    
    await db.update(
      'sync_operations',
      updates,
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  /// التحقق من أن العملية تم تطبيقها مسبقاً
  Future<bool> isOperationApplied(String operationId) async {
    final db = await _db.database;
    final results = await db.query(
      'sync_applied_operations',
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
    return results.isNotEmpty;
  }

  /// تسجيل عملية تم تطبيقها
  Future<void> markOperationAsApplied(String operationId, String deviceId) async {
    final db = await _db.database;
    
    await db.insert(
      'sync_applied_operations',
      {
        'operation_id': operationId,
        'device_id': deviceId,
        'applied_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// الحصول على Causality Vector الحالي
  Future<CausalityVector> getCurrentCausalityVector() async {
    final db = await _db.database;
    
    // جمع أعلى تسلسل لكل جهاز
    final results = await db.rawQuery('''
      SELECT device_id, MAX(local_sequence) as max_seq
      FROM sync_operations
      GROUP BY device_id
    ''');
    
    final vector = <String, int>{};
    for (final row in results) {
      final deviceId = row['device_id'] as String;
      final maxSeq = row['max_seq'] as int;
      vector[deviceId] = maxSeq;
    }
    
    return CausalityVector(vector);
  }
}
