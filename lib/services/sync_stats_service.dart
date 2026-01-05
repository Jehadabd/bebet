// lib/services/sync_stats_service.dart
// خدمة إحصائيات المزامنة - Lazy Loading فقط عند الطلب

import 'package:sqflite/sqflite.dart';
import '../models/sync_stat.dart';
import 'database_service.dart';

class SyncStatsService {
  final DatabaseService _db = DatabaseService();

  /// الحصول على المعاملات الناجحة
  /// ⚡ Lazy loading - يُنفذ فقط عند الطلب
  Future<List<SyncStat>> getSuccessfulTransactions({
    String? customerName,
    SyncStatType? type,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _db.database;
    final stats = <SyncStat>[];

    try {
      // استعلام للمعاملات المستقبلة (received) من sync
      if (type == null || type == SyncStatType.received) {
        final receivedStats = await _getReceivedTransactions(
          db: db,
          customerName: customerName,
          startDate: startDate,
          endDate: endDate,
        );
        stats.addAll(receivedStats);
      }

      // استعلام للمعاملات المرسلة (sent) والمؤكدة
      if (type == null || type == SyncStatType.sent) {
        final sentStats = await _getSentTransactions(
          db: db,
          customerName: customerName,
          startDate: startDate,
          endDate: endDate,
        );
        stats.addAll(sentStats);
      }

      // ترتيب حسب التاريخ (الأحدث أولاً)
      stats.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return stats;
    } catch (e) {
      print('❌ خطأ في جلب المعاملات الناجحة: $e');
      return [];
    }
  }

  /// الحصول على العمليات الفاشلة
  Future<List<SyncStat>> getFailedOperations({
    String? customerName,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _db.database;
    final stats = <SyncStat>[];

    try {
      // استعلام من sync_retry_queue (العمليات الفاشلة)
      String query = '''
        SELECT 
          srq.sync_uuid,
          srq.retry_count,
          srq.created_at,
          srq.data,
          c.name as customer_name,
          c.id as customer_id
        FROM sync_retry_queue srq
        LEFT JOIN transactions t ON t.sync_uuid = srq.sync_uuid
        LEFT JOIN customers c ON c.id = t.customer_id
        WHERE srq.type = 'transaction'
      ''';

      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];

      if (customerName != null && customerName.isNotEmpty) {
        whereConditions.add('c.name LIKE ?');
        whereArgs.add('%$customerName%');
      }

      if (startDate != null) {
        whereConditions.add('srq.created_at >= ?');
        whereArgs.add(startDate.toIso8601String());
      }

      if (endDate != null) {
        whereConditions.add('srq.created_at <= ?');
        whereArgs.add(endDate.toIso8601String());
      }

      if (whereConditions.isNotEmpty) {
        query += ' AND ${whereConditions.join(' AND ')}';
      }

      query += ' ORDER BY srq.created_at DESC LIMIT 500';

      final results = await db.rawQuery(query, whereArgs);

      for (final row in results) {
        try {
          final syncUuid = row['sync_uuid'] as String;
          final customerNameVal = row['customer_name'] as String? ?? 'غير معروف';
          final customerId = row['customer_id'] as int? ?? 0;
          final retryCount = row['retry_count'] as int? ?? 0;
          final createdAt = DateTime.parse(row['created_at'] as String);

          // محاولة استخراج بيانات المعاملة من JSON
          double amount = 0.0;
          double balanceBefore = 0.0;
          double balanceAfter = 0.0;

          // إذا كانت البيانات موجودة في data (JSON)
          // يمكننا استخراجها، لكن لتبسيط الأمر سنستخدم قيم افتراضية

          stats.add(SyncStat(
            transactionId: syncUuid,
            customerName: customerNameVal,
            customerId: customerId,
            timestamp: createdAt,
            amount: amount,
            balanceBefore: balanceBefore,
            balanceAfter: balanceAfter,
            type: SyncStatType.sent, // العمليات الفاشلة عادة من sent
            status: SyncStatStatus.failed,
            retryCount: retryCount,
            errorMessage: 'فشل الرفع بعد $retryCount محاولة',
          ));
        } catch (e) {
          print('تخطي صف: $e');
        }
      }

      return stats;
    } catch (e) {
      print('❌ خطأ في جلب العمليات الفاشلة: $e');
      return [];
    }
  }

  /// الحصول على ملخص الإحصائيات
  Future<SyncStatsSummary> getSummary() async {
    try {
      final successful = await getSuccessfulTransactions();
      final failed = await getFailedOperations();

      final sentCount = successful.where((s) => s.type == SyncStatType.sent).length;
      final receivedCount = successful.where((s) => s.type == SyncStatType.received).length;

      DateTime? oldest;
      DateTime? newest;

      if (successful.isNotEmpty) {
        // الأقدم (أول عنصر بعد الترتيب التنازلي = الأحدث، لذا نأخذ الأخير)
        oldest = successful.last.timestamp;
        newest = successful.first.timestamp;
      }

      return SyncStatsSummary(
        totalSuccess: successful.length,
        totalFailed: failed.length,
        sentCount: sentCount,
        receivedCount: receivedCount,
        oldestStat: oldest,
        newestStat: newest,
      );
    } catch (e) {
      print('❌ خطأ في جلب الملخص: $e');
      return SyncStatsSummary(
        totalSuccess: 0,
        totalFailed: 0,
        sentCount: 0,
        receivedCount: 0,
      );
    }
  }

  /// Helper: جلب المعاملات المستقبلة
  Future<List<SyncStat>> _getReceivedTransactions({
    required Database db,
    String? customerName,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // المعاملات المستقبلة = is_created_by_me = 0
    String query = '''
      SELECT 
        t.sync_uuid,
        t.customer_id,
        c.name as customer_name,
        t.transaction_date,
        t.amount_changed,
        t.balance_before_transaction,
        t.new_balance_after_transaction,
        t.created_at
      FROM transactions t
      INNER JOIN customers c ON c.id = t.customer_id
      WHERE t.is_created_by_me = 0
        AND t.sync_uuid IS NOT NULL
        AND (t.is_deleted IS NULL OR t.is_deleted = 0)
    ''';

    final whereArgs = <dynamic>[];

    if (customerName != null && customerName.isNotEmpty) {
      query += ' AND c.name LIKE ?';
      whereArgs.add('%$customerName%');
    }

    if (startDate != null) {
      query += ' AND t.transaction_date >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      query += ' AND t.transaction_date <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    query += ' ORDER BY t.transaction_date DESC LIMIT 500';

    final results = await db.rawQuery(query, whereArgs);
    final stats = <SyncStat>[];

    for (final row in results) {
      try {
        stats.add(SyncStat(
          transactionId: row['sync_uuid'] as String,
          customerName: row['customer_name'] as String? ?? 'غير معروف',
          customerId: row['customer_id'] as int,
          timestamp: DateTime.parse(row['transaction_date'] as String),
          amount: (row['amount_changed'] as num).toDouble(),
          balanceBefore: (row['balance_before_transaction'] as num? ?? 0).toDouble(),
          balanceAfter: (row['new_balance_after_transaction'] as num? ?? 0).toDouble(),
          type: SyncStatType.received,
          status: SyncStatStatus.success,
        ));
      } catch (e) {
        print('تخطي صف: $e');
      }
    }

    return stats;
  }

  /// Helper: جلب المعاملات المرسلة والمؤكدة
  Future<List<SyncStat>> _getSentTransactions({
    required Database db,
    String? customerName,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // المعاملات المرسلة = is_created_by_me = 1 AND تم تأكيدها في transaction_acks
    String query = '''
      SELECT DISTINCT
        t.sync_uuid,
        t.customer_id,
        c.name as customer_name,
        t.transaction_date,
        t.amount_changed,
        t.balance_before_transaction,
        t.new_balance_after_transaction,
        t.created_at,
        ta.received_at
      FROM transactions t
      INNER JOIN customers c ON c.id = t.customer_id
      INNER JOIN transaction_acks ta ON ta.transaction_sync_uuid = t.sync_uuid
      WHERE (t.is_created_by_me = 1 OR t.is_created_by_me IS NULL)
        AND t.sync_uuid IS NOT NULL
        AND (t.is_deleted IS NULL OR t.is_deleted = 0)
    ''';

    final whereArgs = <dynamic>[];

    if (customerName != null && customerName.isNotEmpty) {
      query += ' AND c.name LIKE ?';
      whereArgs.add('%$customerName%');
    }

    if (startDate != null) {
      query += ' AND t.transaction_date >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      query += ' AND t.transaction_date <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    query += ' ORDER BY ta.received_at DESC LIMIT 500';

    final results = await db.rawQuery(query, whereArgs);
    final stats = <SyncStat>[];

    for (final row in results) {
      try {
        stats.add(SyncStat(
          transactionId: row['sync_uuid'] as String,
          customerName: row['customer_name'] as String? ?? 'غير معروف',
          customerId: row['customer_id'] as int,
          timestamp: DateTime.parse(row['received_at'] as String),
          amount: (row['amount_changed'] as num).toDouble(),
          balanceBefore: (row['balance_before_transaction'] as num? ?? 0).toDouble(),
          balanceAfter: (row['new_balance_after_transaction'] as num? ?? 0).toDouble(),
          type: SyncStatType.sent,
          status: SyncStatStatus.success,
        ));
      } catch (e) {
        print('تخطي صف: $e');
      }
    }

    return stats;
  }
}
