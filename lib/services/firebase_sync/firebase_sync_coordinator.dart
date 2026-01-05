// lib/services/firebase_sync/firebase_sync_coordinator.dart
// منسق المزامنة بين Firebase و Google Drive
// يضمن عدم تكرار العمليات وتنسيق الرفع بين النظامين

import 'dart:async';
import 'package:sqflite/sqflite.dart';
import '../database_service.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// حالة مزامنة العملية
/// ═══════════════════════════════════════════════════════════════════════════
enum SyncSource {
  local,          // تم إنشاؤها محلياً
  firebase,       // تم استلامها من Firebase
  googleDrive,    // تم استلامها من Google Drive
}

/// ═══════════════════════════════════════════════════════════════════════════
/// منسق المزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class FirebaseSyncCoordinator {
  static final FirebaseSyncCoordinator _instance = FirebaseSyncCoordinator._internal();
  factory FirebaseSyncCoordinator() => _instance;
  FirebaseSyncCoordinator._internal();
  
  final DatabaseService _db = DatabaseService();
  bool _isInitialized = false;
  
  /// تهيئة جدول التنسيق
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    final db = await _db.database;
    
    // جدول تتبع حالة المزامنة لكل عملية
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_coordination (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        sync_uuid TEXT NOT NULL,
        firebase_synced INTEGER DEFAULT 0,
        firebase_synced_at TEXT,
        drive_synced INTEGER DEFAULT 0,
        drive_synced_at TEXT,
        source TEXT DEFAULT 'local',
        checksum TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(entity_type, sync_uuid)
      )
    ''');
    
    // فهرس للبحث السريع
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_coord_uuid 
      ON sync_coordination(entity_type, sync_uuid)
    ''');
    
    _isInitialized = true;
    print('✅ تم تهيئة منسق المزامنة');
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// تسجيل العمليات
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تسجيل عملية جديدة (عند الإنشاء المحلي)
  Future<void> registerOperation({
    required String entityType,
    required String syncUuid,
    required SyncSource source,
    String? checksum,
    Transaction? txn, // 🟢 إضافة دعم Transaction
  }) async {
    await initialize();
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    
    try {
      if (txn != null) {
        await txn.insert(
          'sync_coordination',
          {
            'entity_type': entityType,
            'sync_uuid': syncUuid,
            'source': source.name,
            'checksum': checksum,
            'firebase_synced': source == SyncSource.firebase ? 1 : 0,
            'firebase_synced_at': source == SyncSource.firebase ? now : null,
            'drive_synced': source == SyncSource.googleDrive ? 1 : 0,
            'drive_synced_at': source == SyncSource.googleDrive ? now : null,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } else {
        await db.insert(
          'sync_coordination',
          {
            'entity_type': entityType,
            'sync_uuid': syncUuid,
            'source': source.name,
            'checksum': checksum,
            'firebase_synced': source == SyncSource.firebase ? 1 : 0,
            'firebase_synced_at': source == SyncSource.firebase ? now : null,
            'drive_synced': source == SyncSource.googleDrive ? 1 : 0,
            'drive_synced_at': source == SyncSource.googleDrive ? now : null,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    } catch (e) {
      // تجاهل إذا كانت موجودة مسبقاً
    }
  }
  
  /// تعليم العملية كمرفوعة على Firebase
  Future<void> markFirebaseSynced(String entityType, String syncUuid, {Transaction? txn}) async {
    await initialize();
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    
    final values = {
      'firebase_synced': 1,
      'firebase_synced_at': now,
      'updated_at': now,
    };
    
    const where = 'entity_type = ? AND sync_uuid = ?';
    final whereArgs = [entityType, syncUuid];

    if (txn != null) {
      await txn.update('sync_coordination', values, where: where, whereArgs: whereArgs);
    } else {
      await db.update('sync_coordination', values, where: where, whereArgs: whereArgs);
    }
  }
  
  /// تعليم العملية كمرفوعة على Google Drive
  Future<void> markDriveSynced(String entityType, String syncUuid, {Transaction? txn}) async {
    await initialize();
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    
    final values = {
      'drive_synced': 1,
      'drive_synced_at': now,
      'updated_at': now,
    };

    const where = 'entity_type = ? AND sync_uuid = ?';
    final whereArgs = [entityType, syncUuid];

    if (txn != null) {
      await txn.update('sync_coordination', values, where: where, whereArgs: whereArgs);
    } else {
      await db.update('sync_coordination', values, where: where, whereArgs: whereArgs);
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// التحقق من حالة المزامنة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// هل تم رفع العملية على Firebase؟
  Future<bool> isFirebaseSynced(String entityType, String syncUuid) async {
    await initialize();
    final db = await _db.database;
    
    final result = await db.query(
      'sync_coordination',
      columns: ['firebase_synced'],
      where: 'entity_type = ? AND sync_uuid = ?',
      whereArgs: [entityType, syncUuid],
    );
    
    if (result.isEmpty) return false;
    return result.first['firebase_synced'] == 1;
  }
  
  /// الحصول على وقت آخر مزامنة لكيان معين
  Future<String?> getLastSyncTime(String entityType, String syncUuid) async {
    await initialize();
    final db = await _db.database;
    
    final result = await db.query(
      'sync_coordination',
      columns: ['firebase_synced_at'],
      where: 'entity_type = ? AND sync_uuid = ?',
      whereArgs: [entityType, syncUuid],
    );
    
    if (result.isNotEmpty && result.first['firebase_synced_at'] != null) {
      return result.first['firebase_synced_at'] as String;
    }
    return null;
  }
  
  /// هل تم رفع العملية على Google Drive؟
  Future<bool> isDriveSynced(String entityType, String syncUuid) async {
    await initialize();
    final db = await _db.database;
    
    final result = await db.query(
      'sync_coordination',
      columns: ['drive_synced'],
      where: 'entity_type = ? AND sync_uuid = ?',
      whereArgs: [entityType, syncUuid],
    );
    
    if (result.isEmpty) return false;
    return result.first['drive_synced'] == 1;
  }
  
  /// الحصول على مصدر العملية
  Future<SyncSource?> getOperationSource(String entityType, String syncUuid) async {
    await initialize();
    final db = await _db.database;
    
    final result = await db.query(
      'sync_coordination',
      columns: ['source'],
      where: 'entity_type = ? AND sync_uuid = ?',
      whereArgs: [entityType, syncUuid],
    );
    
    if (result.isEmpty) return null;
    
    final source = result.first['source'] as String?;
    if (source == null) return SyncSource.local;
    
    return SyncSource.values.firstWhere(
      (s) => s.name == source,
      orElse: () => SyncSource.local,
    );
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// الحصول على العمليات المعلقة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// العمليات التي لم يتم رفعها على Firebase بعد
  Future<List<Map<String, dynamic>>> getPendingForFirebase() async {
    await initialize();
    final db = await _db.database;
    
    // العملاء المعلقين
    final customers = await db.rawQuery('''
      SELECT c.*, 'customer' as entity_type
      FROM customers c
      LEFT JOIN sync_coordination sc ON sc.entity_type = 'customer' AND sc.sync_uuid = c.sync_uuid
      WHERE c.sync_uuid IS NOT NULL 
        AND (sc.firebase_synced IS NULL OR sc.firebase_synced = 0)
        AND (c.is_deleted IS NULL OR c.is_deleted = 0)
    ''');
    
    // المعاملات المعلقة
    final transactions = await db.rawQuery('''
      SELECT t.*, 'transaction' as entity_type, c.sync_uuid as customer_sync_uuid
      FROM transactions t
      JOIN customers c ON t.customer_id = c.id
      LEFT JOIN sync_coordination sc ON sc.entity_type = 'transaction' AND sc.sync_uuid = t.sync_uuid
      WHERE t.sync_uuid IS NOT NULL 
        AND (sc.firebase_synced IS NULL OR sc.firebase_synced = 0)
        AND (t.is_deleted IS NULL OR t.is_deleted = 0)
    ''');
    
    return [...customers, ...transactions];
  }
  
  /// العمليات التي لم يتم رفعها على Google Drive بعد
  /// (لإخبار نظام Drive أن يتخطاها إذا رفعها Firebase)
  Future<List<String>> getFirebaseSyncedUuids(String entityType) async {
    await initialize();
    final db = await _db.database;
    
    final result = await db.query(
      'sync_coordination',
      columns: ['sync_uuid'],
      where: 'entity_type = ? AND firebase_synced = 1',
      whereArgs: [entityType],
    );
    
    return result.map((r) => r['sync_uuid'] as String).toList();
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// التحقق من التكرار
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// التحقق من وجود معاملة مكررة
  Future<bool> isDuplicateTransaction({
    required int customerId,
    required String transactionDate,
    required double amount,
    required String transactionType,
  }) async {
    final db = await _db.database;
    
    final result = await db.query(
      'transactions',
      where: '''customer_id = ? AND 
                transaction_date = ? AND 
                ABS(amount_changed - ?) < 0.01 AND
                transaction_type = ? AND
                (is_deleted IS NULL OR is_deleted = 0)''',
      whereArgs: [customerId, transactionDate, amount, transactionType],
    );
    
    return result.isNotEmpty;
  }
  
  /// التحقق من وجود عميل مكرر
  Future<bool> isDuplicateCustomer({
    required String name,
    String? phone,
  }) async {
    final db = await _db.database;
    
    String where = 'name = ? AND (is_deleted IS NULL OR is_deleted = 0)';
    List<dynamic> whereArgs = [name];
    
    if (phone != null && phone.isNotEmpty) {
      where += ' AND phone = ?';
      whereArgs.add(phone);
    }
    
    final result = await db.query(
      'customers',
      where: where,
      whereArgs: whereArgs,
    );
    
    return result.isNotEmpty;
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// إحصائيات
  /// ═══════════════════════════════════════════════════════════════════════
  
  Future<Map<String, dynamic>> getStats() async {
    await initialize();
    final db = await _db.database;
    
    final total = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_coordination'
    );
    
    final firebaseSynced = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_coordination WHERE firebase_synced = 1'
    );
    
    final driveSynced = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_coordination WHERE drive_synced = 1'
    );
    
    final bothSynced = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_coordination WHERE firebase_synced = 1 AND drive_synced = 1'
    );
    
    return {
      'total': total.first['count'],
      'firebase_synced': firebaseSynced.first['count'],
      'drive_synced': driveSynced.first['count'],
      'both_synced': bothSynced.first['count'],
    };
  }
  
  /// تنظيف السجلات القديمة
  Future<int> cleanup({int keepDays = 90}) async {
    await initialize();
    final db = await _db.database;
    
    final cutoff = DateTime.now()
        .subtract(Duration(days: keepDays))
        .toIso8601String();
    
    final deleted = await db.delete(
      'sync_coordination',
      where: 'firebase_synced = 1 AND drive_synced = 1 AND updated_at < ?',
      whereArgs: [cutoff],
    );
    
    print('🧹 تم حذف $deleted سجل تنسيق قديم');
    return deleted;
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// Singleton للوصول السهل
/// ═══════════════════════════════════════════════════════════════════════════
class SyncCoordinatorInstance {
  static FirebaseSyncCoordinator? _instance;
  
  static Future<FirebaseSyncCoordinator> get() async {
    _instance ??= FirebaseSyncCoordinator();
    await _instance!.initialize();
    return _instance!;
  }
}
