// lib/services/sync/sync_audit_service.dart
// خدمة تدقيق وأمان المزامنة
// 
// الميزات:
// 1. ✅ نسخ احتياطي تلقائي قبل المزامنة
// 2. ✅ سجل تدقيق المزامنة
// 3. ✅ التحقق بعد المزامنة (بدون إصلاح تلقائي)
// 4. ✅ تأكيد للمعاملات الكبيرة (>10 مليون)
// 5. ✅ رفض المعاملات القديمة (>شهر)

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database_service.dart';
import 'sync_operation.dart';
import 'sync_models.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// إعدادات أمان المزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncSecurityConfig {
  /// الحد الأقصى للمبلغ الذي يتطلب تأكيد (10 مليون)
  final double largeTransactionThreshold;
  
  /// عمر المعاملة الأقصى بالأيام (30 يوم = شهر)
  final int maxTransactionAgeDays;
  
  /// عدد النسخ الاحتياطية المحفوظة
  final int maxBackupsToKeep;
  
  /// تفعيل النسخ الاحتياطي قبل المزامنة
  final bool enablePreSyncBackup;
  
  /// تفعيل التحقق بعد المزامنة
  final bool enablePostSyncVerification;
  
  /// تفعيل تأكيد المعاملات الكبيرة
  final bool enableLargeTransactionConfirmation;
  
  /// تفعيل رفض المعاملات القديمة
  final bool enableOldTransactionRejection;

  const SyncSecurityConfig({
    this.largeTransactionThreshold = 10000000, // 10 مليون
    this.maxTransactionAgeDays = 30, // شهر
    this.maxBackupsToKeep = 3,
    this.enablePreSyncBackup = true,
    this.enablePostSyncVerification = true,
    this.enableLargeTransactionConfirmation = true,
    this.enableOldTransactionRejection = true,
  });
}

/// ═══════════════════════════════════════════════════════════════════════════
/// معاملة تحتاج تأكيد
/// ═══════════════════════════════════════════════════════════════════════════
class PendingLargeTransaction {
  final SyncOperation operation;
  final String customerName;
  final double amount;
  final String transactionType; // إضافة دين / تسديد
  final String date;
  
  PendingLargeTransaction({
    required this.operation,
    required this.customerName,
    required this.amount,
    required this.transactionType,
    required this.date,
  });
}

/// ═══════════════════════════════════════════════════════════════════════════
/// نتيجة التحقق بعد المزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class PostSyncVerificationResult {
  final bool isHealthy;
  final int customersChecked;
  final int customersWithIssues;
  final List<CustomerBalanceIssue> issues;
  final DateTime verifiedAt;
  
  PostSyncVerificationResult({
    required this.isHealthy,
    required this.customersChecked,
    required this.customersWithIssues,
    required this.issues,
    required this.verifiedAt,
  });
}

/// ═══════════════════════════════════════════════════════════════════════════
/// مشكلة في رصيد عميل
/// ═══════════════════════════════════════════════════════════════════════════
class CustomerBalanceIssue {
  final int customerId;
  final String customerName;
  final double recordedBalance;
  final double calculatedBalance;
  final double difference;
  
  CustomerBalanceIssue({
    required this.customerId,
    required this.customerName,
    required this.recordedBalance,
    required this.calculatedBalance,
    required this.difference,
  });
}

/// ═══════════════════════════════════════════════════════════════════════════
/// سجل عملية مزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncAuditLog {
  final int? id;
  final DateTime syncStartTime;
  final DateTime? syncEndTime;
  final String syncType; // full_transfer, normal, quick
  final int operationsUploaded;
  final int operationsDownloaded;
  final int operationsApplied;
  final int operationsFailed;
  final bool success;
  final String? errorMessage;
  final String? affectedCustomers; // JSON list of customer names
  final String? warnings; // JSON list of warnings
  final String deviceId;
  final String? backupPath;
  
  SyncAuditLog({
    this.id,
    required this.syncStartTime,
    this.syncEndTime,
    required this.syncType,
    this.operationsUploaded = 0,
    this.operationsDownloaded = 0,
    this.operationsApplied = 0,
    this.operationsFailed = 0,
    this.success = false,
    this.errorMessage,
    this.affectedCustomers,
    this.warnings,
    required this.deviceId,
    this.backupPath,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'sync_start_time': syncStartTime.toIso8601String(),
    'sync_end_time': syncEndTime?.toIso8601String(),
    'sync_type': syncType,
    'operations_uploaded': operationsUploaded,
    'operations_downloaded': operationsDownloaded,
    'operations_applied': operationsApplied,
    'operations_failed': operationsFailed,
    'success': success ? 1 : 0,
    'error_message': errorMessage,
    'affected_customers': affectedCustomers,
    'warnings': warnings,
    'device_id': deviceId,
    'backup_path': backupPath,
  };
  
  factory SyncAuditLog.fromJson(Map<String, dynamic> json) => SyncAuditLog(
    id: json['id'] as int?,
    syncStartTime: DateTime.parse(json['sync_start_time'] as String),
    syncEndTime: json['sync_end_time'] != null 
        ? DateTime.parse(json['sync_end_time'] as String) 
        : null,
    syncType: json['sync_type'] as String,
    operationsUploaded: json['operations_uploaded'] as int? ?? 0,
    operationsDownloaded: json['operations_downloaded'] as int? ?? 0,
    operationsApplied: json['operations_applied'] as int? ?? 0,
    operationsFailed: json['operations_failed'] as int? ?? 0,
    success: (json['success'] as int? ?? 0) == 1,
    errorMessage: json['error_message'] as String?,
    affectedCustomers: json['affected_customers'] as String?,
    warnings: json['warnings'] as String?,
    deviceId: json['device_id'] as String,
    backupPath: json['backup_path'] as String?,
  );
}

/// ═══════════════════════════════════════════════════════════════════════════
/// خدمة تدقيق وأمان المزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncAuditService {
  final DatabaseService _db;
  final SyncSecurityConfig config;
  
  // Callback للتأكيد على المعاملات الكبيرة
  Future<bool> Function(List<PendingLargeTransaction>)? onLargeTransactionsDetected;
  
  // Callback لإظهار تحذيرات التحقق
  void Function(PostSyncVerificationResult)? onVerificationComplete;
  
  SyncAuditService({
    DatabaseService? db,
    this.config = const SyncSecurityConfig(),
  }) : _db = db ?? DatabaseService();

  /// ═══════════════════════════════════════════════════════════════════════
  /// 1. النسخ الاحتياطي قبل المزامنة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// إنشاء نسخة احتياطية من قاعدة البيانات
  Future<String?> createPreSyncBackup() async {
    if (!config.enablePreSyncBackup) return null;
    
    try {
      print('💾 جاري إنشاء نسخة احتياطية قبل المزامنة...');
      
      // الحصول على مسار قاعدة البيانات بطريقة تعمل على جميع المنصات
      String dbFullPath;
      
      if (Platform.isWindows) {
        // على Windows، نستخدم مسار التطبيق
        final appDir = await getApplicationDocumentsDirectory();
        dbFullPath = '${appDir.path}/debt_book.db';
        
        // إذا لم يكن موجوداً، نجرب المسار الافتراضي
        if (!await File(dbFullPath).exists()) {
          final dbPath = await getDatabasesPath();
          dbFullPath = '$dbPath/debt_book.db';
        }
      } else {
        // على Android/iOS
        final dbPath = await getDatabasesPath();
        dbFullPath = '$dbPath/debt_book.db';
      }
      
      final sourceFile = File(dbFullPath);
      
      if (!await sourceFile.exists()) {
        print('⚠️ ملف قاعدة البيانات غير موجود في: $dbFullPath');
        // محاولة البحث عن الملف
        final possiblePaths = await _findDatabaseFile();
        if (possiblePaths != null) {
          dbFullPath = possiblePaths;
          print('✅ تم العثور على قاعدة البيانات في: $dbFullPath');
        } else {
          return null;
        }
      }
      
      // إنشاء مجلد النسخ الاحتياطية
      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${appDir.path}/sync_backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      
      // اسم ملف النسخة الاحتياطية
      final timestamp = DateTime.now().toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupPath = '${backupDir.path}/backup_$timestamp.db';
      
      // نسخ الملف
      await File(dbFullPath).copy(backupPath);
      
      print('✅ تم إنشاء نسخة احتياطية: $backupPath');
      
      // تنظيف النسخ القديمة
      await _cleanupOldBackups(backupDir);
      
      return backupPath;
    } catch (e) {
      print('❌ فشل إنشاء النسخة الاحتياطية: $e');
      return null;
    }
  }
  
  /// البحث عن ملف قاعدة البيانات
  Future<String?> _findDatabaseFile() async {
    final possibleLocations = <String>[];
    
    try {
      // مسارات محتملة على Windows
      if (Platform.isWindows) {
        final appDir = await getApplicationDocumentsDirectory();
        possibleLocations.add('${appDir.path}/debt_book.db');
        possibleLocations.add('${appDir.path}/databases/debt_book.db');
        
        final appSupport = await getApplicationSupportDirectory();
        possibleLocations.add('${appSupport.path}/debt_book.db');
        possibleLocations.add('${appSupport.path}/databases/debt_book.db');
      }
      
      // المسار الافتراضي
      final dbPath = await getDatabasesPath();
      possibleLocations.add('$dbPath/debt_book.db');
      
      for (final path in possibleLocations) {
        if (await File(path).exists()) {
          return path;
        }
      }
    } catch (e) {
      print('⚠️ خطأ في البحث عن قاعدة البيانات: $e');
    }
    
    return null;
  }
  
  /// تنظيف النسخ الاحتياطية القديمة
  Future<void> _cleanupOldBackups(Directory backupDir) async {
    try {
      final files = await backupDir.list().toList();
      final backupFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList();
      
      // ترتيب حسب تاريخ التعديل (الأحدث أولاً)
      backupFiles.sort((a, b) => 
        b.statSync().modified.compareTo(a.statSync().modified));
      
      // حذف النسخ الزائدة
      if (backupFiles.length > config.maxBackupsToKeep) {
        for (final file in backupFiles.skip(config.maxBackupsToKeep)) {
          await file.delete();
          print('🗑️ تم حذف نسخة احتياطية قديمة: ${file.path}');
        }
      }
    } catch (e) {
      print('⚠️ خطأ في تنظيف النسخ الاحتياطية: $e');
    }
  }
  
  /// استعادة من نسخة احتياطية
  /// ⚠️ ملاحظة: يجب إعادة تشغيل التطبيق بعد الاستعادة
  Future<bool> restoreFromBackup(String backupPath) async {
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        print('❌ ملف النسخة الاحتياطية غير موجود');
        return false;
      }
      
      final dbPath = await getDatabasesPath();
      final targetPath = '$dbPath/debt_book.db';
      
      // ⚠️ ملاحظة: لا يمكن إغلاق قاعدة البيانات من هنا
      // يجب على المستخدم إعادة تشغيل التطبيق بعد الاستعادة
      
      // استعادة النسخة
      await backupFile.copy(targetPath);
      
      print('✅ تم استعادة قاعدة البيانات من النسخة الاحتياطية');
      print('⚠️ يرجى إعادة تشغيل التطبيق لتفعيل التغييرات');
      return true;
    } catch (e) {
      print('❌ فشل استعادة النسخة الاحتياطية: $e');
      return false;
    }
  }
  
  /// الحصول على قائمة النسخ الاحتياطية المتاحة
  Future<List<Map<String, dynamic>>> getAvailableBackups() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${appDir.path}/sync_backups');
      
      if (!await backupDir.exists()) return [];
      
      final files = await backupDir.list().toList();
      final backups = <Map<String, dynamic>>[];
      
      for (final file in files.whereType<File>()) {
        if (file.path.endsWith('.db')) {
          final stat = await file.stat();
          backups.add({
            'path': file.path,
            'name': file.path.split('/').last,
            'size': stat.size,
            'created': stat.modified,
          });
        }
      }
      
      // ترتيب حسب التاريخ (الأحدث أولاً)
      backups.sort((a, b) => 
        (b['created'] as DateTime).compareTo(a['created'] as DateTime));
      
      return backups;
    } catch (e) {
      print('⚠️ خطأ في جلب النسخ الاحتياطية: $e');
      return [];
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 2. فحص المعاملات قبل التطبيق
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// فحص المعاملات الواردة وتصنيفها
  Future<({
    List<SyncOperation> approved,
    List<SyncOperation> rejected,
    List<PendingLargeTransaction> needsConfirmation,
    List<String> rejectionReasons,
  })> validateIncomingOperations(List<SyncOperation> operations) async {
    final approved = <SyncOperation>[];
    final rejected = <SyncOperation>[];
    final needsConfirmation = <PendingLargeTransaction>[];
    final rejectionReasons = <String>[];
    
    for (final op in operations) {
      // فقط فحص عمليات المعاملات
      if (op.entityType != 'transaction') {
        approved.add(op);
        continue;
      }
      
      // 1. فحص عمر المعاملة
      if (config.enableOldTransactionRejection) {
        final transactionDate = _extractTransactionDate(op);
        if (transactionDate != null) {
          final age = DateTime.now().difference(transactionDate).inDays;
          if (age > config.maxTransactionAgeDays) {
            rejected.add(op);
            final customerName = op.payloadAfter['customer_name'] ?? 'غير معروف';
            rejectionReasons.add(
              'رفض معاملة قديمة (${age} يوم) للعميل "$customerName" بتاريخ ${transactionDate.toString().split(' ').first}'
            );
            continue;
          }
        }
      }
      
      // 2. فحص المعاملات الكبيرة
      if (config.enableLargeTransactionConfirmation) {
        final amount = _extractAmount(op);
        if (amount.abs() >= config.largeTransactionThreshold) {
          final customerName = op.payloadAfter['customer_name'] ?? 
                              op.payloadAfter['name'] ?? 'غير معروف';
          final transactionType = amount > 0 ? 'إضافة دين' : 'تسديد';
          final date = _extractTransactionDate(op)?.toString().split(' ').first ?? 'غير معروف';
          
          needsConfirmation.add(PendingLargeTransaction(
            operation: op,
            customerName: customerName.toString(),
            amount: amount,
            transactionType: transactionType,
            date: date,
          ));
          continue;
        }
      }
      
      // المعاملة مقبولة
      approved.add(op);
    }
    
    return (
      approved: approved,
      rejected: rejected,
      needsConfirmation: needsConfirmation,
      rejectionReasons: rejectionReasons,
    );
  }
  
  /// استخراج تاريخ المعاملة
  DateTime? _extractTransactionDate(SyncOperation op) {
    final dateStr = op.payloadAfter['transaction_date'] ?? 
                   op.payloadAfter['date'] ??
                   op.payloadAfter['created_at'];
    if (dateStr == null) return null;
    
    try {
      return DateTime.parse(dateStr.toString());
    } catch (_) {
      return null;
    }
  }
  
  /// استخراج المبلغ
  double _extractAmount(SyncOperation op) {
    final amount = op.payloadAfter['amount_changed'] ?? 
                  op.payloadAfter['amount'] ?? 
                  op.payloadAfter['total_amount'] ?? 0;
    return (amount as num).toDouble();
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 3. التحقق بعد المزامنة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// التحقق من صحة الأرصدة بعد المزامنة
  Future<PostSyncVerificationResult> verifyAfterSync(List<int> affectedCustomerIds) async {
    if (!config.enablePostSyncVerification) {
      return PostSyncVerificationResult(
        isHealthy: true,
        customersChecked: 0,
        customersWithIssues: 0,
        issues: [],
        verifiedAt: DateTime.now(),
      );
    }
    
    print('🔍 جاري التحقق من صحة الأرصدة بعد المزامنة...');
    
    final issues = <CustomerBalanceIssue>[];
    final db = await _db.database;
    
    for (final customerId in affectedCustomerIds) {
      try {
        // جلب بيانات العميل
        final customerData = await db.query(
          'customers',
          where: 'id = ?',
          whereArgs: [customerId],
        );
        
        if (customerData.isEmpty) continue;
        
        final customer = customerData.first;
        final recordedBalance = (customer['current_total_debt'] as num?)?.toDouble() ?? 0;
        final customerName = customer['name'] as String? ?? 'غير معروف';
        
        // حساب الرصيد من المعاملات
        final sumResult = await db.rawQuery('''
          SELECT COALESCE(SUM(amount_changed), 0) as total
          FROM transactions
          WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
        ''', [customerId]);
        
        final calculatedBalance = (sumResult.first['total'] as num?)?.toDouble() ?? 0;
        
        // مقارنة الأرصدة
        final difference = (recordedBalance - calculatedBalance).abs();
        if (difference > 0.01) { // تجاهل الفروقات الصغيرة جداً
          issues.add(CustomerBalanceIssue(
            customerId: customerId,
            customerName: customerName,
            recordedBalance: recordedBalance,
            calculatedBalance: calculatedBalance,
            difference: difference,
          ));
          
          print('⚠️ فرق في رصيد العميل "$customerName": مسجل=$recordedBalance، محسوب=$calculatedBalance');
        }
      } catch (e) {
        print('⚠️ خطأ في التحقق من العميل $customerId: $e');
      }
    }
    
    final result = PostSyncVerificationResult(
      isHealthy: issues.isEmpty,
      customersChecked: affectedCustomerIds.length,
      customersWithIssues: issues.length,
      issues: issues,
      verifiedAt: DateTime.now(),
    );
    
    if (issues.isEmpty) {
      print('✅ جميع الأرصدة صحيحة');
    } else {
      print('⚠️ وُجدت ${issues.length} مشكلة في الأرصدة');
    }
    
    // إرسال النتيجة للـ callback
    onVerificationComplete?.call(result);
    
    return result;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 4. سجل تدقيق المزامنة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// إنشاء جدول سجل التدقيق (يُستدعى عند تهيئة قاعدة البيانات)
  static Future<void> createAuditTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_start_time TEXT NOT NULL,
        sync_end_time TEXT,
        sync_type TEXT NOT NULL,
        operations_uploaded INTEGER DEFAULT 0,
        operations_downloaded INTEGER DEFAULT 0,
        operations_applied INTEGER DEFAULT 0,
        operations_failed INTEGER DEFAULT 0,
        success INTEGER DEFAULT 0,
        error_message TEXT,
        affected_customers TEXT,
        warnings TEXT,
        device_id TEXT NOT NULL,
        backup_path TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }
  
  /// التأكد من وجود جدول سجل التدقيق
  Future<void> _ensureAuditTable() async {
    final db = await _db.database;
    try {
      // محاولة إنشاء الجدول إذا لم يكن موجوداً
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sync_start_time TEXT NOT NULL,
          sync_end_time TEXT,
          sync_type TEXT NOT NULL,
          operations_uploaded INTEGER DEFAULT 0,
          operations_downloaded INTEGER DEFAULT 0,
          operations_applied INTEGER DEFAULT 0,
          operations_failed INTEGER DEFAULT 0,
          success INTEGER DEFAULT 0,
          error_message TEXT,
          affected_customers TEXT,
          warnings TEXT,
          device_id TEXT NOT NULL,
          backup_path TEXT,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    } catch (e) {
      // الجدول موجود بالفعل - تجاهل الخطأ
      print('📝 جدول sync_audit_log موجود بالفعل');
    }
  }
  
  /// بدء تسجيل عملية مزامنة
  Future<int> startSyncLog({
    required String syncType,
    required String deviceId,
    String? backupPath,
  }) async {
    // التأكد من وجود الجدول أولاً
    await _ensureAuditTable();
    
    final db = await _db.database;
    
    final id = await db.insert('sync_audit_log', {
      'sync_start_time': DateTime.now().toUtc().toIso8601String(),
      'sync_type': syncType,
      'device_id': deviceId,
      'backup_path': backupPath,
    });
    
    print('📝 بدء تسجيل المزامنة: ID=$id, النوع=$syncType');
    return id;
  }
  
  /// تحديث سجل المزامنة عند الانتهاء
  Future<void> completeSyncLog({
    required int logId,
    required bool success,
    int operationsUploaded = 0,
    int operationsDownloaded = 0,
    int operationsApplied = 0,
    int operationsFailed = 0,
    String? errorMessage,
    List<String>? affectedCustomers,
    List<String>? warnings,
  }) async {
    final db = await _db.database;
    
    await db.update(
      'sync_audit_log',
      {
        'sync_end_time': DateTime.now().toUtc().toIso8601String(),
        'success': success ? 1 : 0,
        'operations_uploaded': operationsUploaded,
        'operations_downloaded': operationsDownloaded,
        'operations_applied': operationsApplied,
        'operations_failed': operationsFailed,
        'error_message': errorMessage,
        'affected_customers': affectedCustomers != null 
            ? jsonEncode(affectedCustomers) 
            : null,
        'warnings': warnings != null ? jsonEncode(warnings) : null,
      },
      where: 'id = ?',
      whereArgs: [logId],
    );
    
    print('📝 اكتمل تسجيل المزامنة: ID=$logId, نجاح=$success');
  }
  
  /// جلب سجل المزامنات
  Future<List<SyncAuditLog>> getSyncLogs({int limit = 50}) async {
    final db = await _db.database;
    
    final results = await db.query(
      'sync_audit_log',
      orderBy: 'sync_start_time DESC',
      limit: limit,
    );
    
    return results.map((r) => SyncAuditLog.fromJson(r)).toList();
  }
  
  /// جلب آخر عملية مزامنة ناجحة
  Future<SyncAuditLog?> getLastSuccessfulSync() async {
    final db = await _db.database;
    
    final results = await db.query(
      'sync_audit_log',
      where: 'success = 1',
      orderBy: 'sync_start_time DESC',
      limit: 1,
    );
    
    if (results.isEmpty) return null;
    return SyncAuditLog.fromJson(results.first);
  }
  
  /// حذف سجلات المزامنة القديمة (أكثر من 30 يوم)
  Future<int> cleanupOldLogs({int daysToKeep = 30}) async {
    final db = await _db.database;
    
    final cutoffDate = DateTime.now()
        .subtract(Duration(days: daysToKeep))
        .toUtc()
        .toIso8601String();
    
    final deleted = await db.delete(
      'sync_audit_log',
      where: 'sync_start_time < ?',
      whereArgs: [cutoffDate],
    );
    
    if (deleted > 0) {
      print('🗑️ تم حذف $deleted سجل مزامنة قديم');
    }
    
    return deleted;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 5. تفاصيل عمليات المزامنة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// التأكد من وجود جدول تفاصيل العمليات
  Future<void> _ensureSyncOperationDetailsTable() async {
    final db = await _db.database;
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_operation_details (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sync_log_id INTEGER,
          operation_type TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id INTEGER,
          entity_uuid TEXT,
          customer_id INTEGER,
          customer_name TEXT,
          amount REAL,
          transaction_type TEXT,
          operation_time TEXT NOT NULL,
          success INTEGER DEFAULT 1,
          error_message TEXT,
          direction TEXT DEFAULT 'download',
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (sync_log_id) REFERENCES sync_audit_log(id)
        )
      ''');
      
      // إنشاء فهرس للبحث السريع
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sync_op_details_time 
        ON sync_operation_details(operation_time)
      ''');
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_sync_op_details_customer 
        ON sync_operation_details(customer_id)
      ''');
    } catch (e) {
      // الجدول موجود بالفعل
    }
  }
  
  /// تسجيل تفاصيل عملية مزامنة
  Future<void> logSyncOperationDetail({
    int? syncLogId,
    required String operationType,
    required String entityType,
    int? entityId,
    String? entityUuid,
    int? customerId,
    String? customerName,
    double? amount,
    String? transactionType,
    required DateTime operationTime,
    bool success = true,
    String? errorMessage,
    String direction = 'download',
  }) async {
    await _ensureSyncOperationDetailsTable();
    final db = await _db.database;
    
    await db.insert('sync_operation_details', {
      'sync_log_id': syncLogId,
      'operation_type': operationType,
      'entity_type': entityType,
      'entity_id': entityId,
      'entity_uuid': entityUuid,
      'customer_id': customerId,
      'customer_name': customerName,
      'amount': amount,
      'transaction_type': transactionType,
      'operation_time': operationTime.toIso8601String(),
      'success': success ? 1 : 0,
      'error_message': errorMessage,
      'direction': direction,
    });
  }
  
  /// جلب السنوات المتاحة في سجل العمليات
  Future<List<int>> getAvailableYears() async {
    await _ensureSyncOperationDetailsTable();
    final db = await _db.database;
    
    final results = await db.rawQuery('''
      SELECT DISTINCT strftime('%Y', operation_time) as year
      FROM sync_operation_details
      ORDER BY year DESC
    ''');
    
    return results
        .map((r) => int.tryParse(r['year']?.toString() ?? '') ?? 0)
        .where((y) => y > 0)
        .toList();
  }
  
  /// جلب الأشهر المتاحة في سنة معينة
  Future<List<int>> getAvailableMonths(int year) async {
    await _ensureSyncOperationDetailsTable();
    final db = await _db.database;
    
    final results = await db.rawQuery('''
      SELECT DISTINCT strftime('%m', operation_time) as month
      FROM sync_operation_details
      WHERE strftime('%Y', operation_time) = ?
      ORDER BY month DESC
    ''', [year.toString()]);
    
    return results
        .map((r) => int.tryParse(r['month']?.toString() ?? '') ?? 0)
        .where((m) => m > 0)
        .toList();
  }
  
  /// جلب تفاصيل العمليات لشهر معين
  Future<List<SyncOperationDetail>> getOperationDetails({
    required int year,
    required int month,
    String? entityType,
    int? customerId,
  }) async {
    await _ensureSyncOperationDetailsTable();
    final db = await _db.database;
    
    String whereClause = "strftime('%Y', operation_time) = ? AND strftime('%m', operation_time) = ?";
    List<dynamic> whereArgs = [year.toString(), month.toString().padLeft(2, '0')];
    
    if (entityType != null) {
      whereClause += ' AND entity_type = ?';
      whereArgs.add(entityType);
    }
    
    if (customerId != null) {
      whereClause += ' AND customer_id = ?';
      whereArgs.add(customerId);
    }
    
    final results = await db.query(
      'sync_operation_details',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'operation_time DESC',
    );
    
    return results.map((r) => SyncOperationDetail.fromJson(r)).toList();
  }
  
  /// جلب إحصائيات شهر معين
  Future<Map<String, dynamic>> getMonthStats(int year, int month) async {
    await _ensureSyncOperationDetailsTable();
    final db = await _db.database;
    
    final monthStr = month.toString().padLeft(2, '0');
    
    final results = await db.rawQuery('''
      SELECT 
        COUNT(*) as total,
        SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successful,
        SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) as failed,
        SUM(CASE WHEN direction = 'download' THEN 1 ELSE 0 END) as downloaded,
        SUM(CASE WHEN direction = 'upload' THEN 1 ELSE 0 END) as uploaded,
        SUM(CASE WHEN entity_type = 'transaction' THEN 1 ELSE 0 END) as transactions,
        SUM(CASE WHEN entity_type = 'customer' THEN 1 ELSE 0 END) as customers
      FROM sync_operation_details
      WHERE strftime('%Y', operation_time) = ? AND strftime('%m', operation_time) = ?
    ''', [year.toString(), monthStr]);
    
    if (results.isEmpty) {
      return {
        'total': 0,
        'successful': 0,
        'failed': 0,
        'downloaded': 0,
        'uploaded': 0,
        'transactions': 0,
        'customers': 0,
      };
    }
    
    return {
      'total': results.first['total'] ?? 0,
      'successful': results.first['successful'] ?? 0,
      'failed': results.first['failed'] ?? 0,
      'downloaded': results.first['downloaded'] ?? 0,
      'uploaded': results.first['uploaded'] ?? 0,
      'transactions': results.first['transactions'] ?? 0,
      'customers': results.first['customers'] ?? 0,
    };
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// نموذج تفاصيل عملية مزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncOperationDetail {
  final int? id;
  final int? syncLogId;
  final String operationType;
  final String entityType;
  final int? entityId;
  final String? entityUuid;
  final int? customerId;
  final String? customerName;
  final double? amount;
  final String? transactionType;
  final DateTime operationTime;
  final bool success;
  final String? errorMessage;
  final String direction;
  
  SyncOperationDetail({
    this.id,
    this.syncLogId,
    required this.operationType,
    required this.entityType,
    this.entityId,
    this.entityUuid,
    this.customerId,
    this.customerName,
    this.amount,
    this.transactionType,
    required this.operationTime,
    this.success = true,
    this.errorMessage,
    this.direction = 'download',
  });
  
  factory SyncOperationDetail.fromJson(Map<String, dynamic> json) {
    return SyncOperationDetail(
      id: json['id'] as int?,
      syncLogId: json['sync_log_id'] as int?,
      operationType: json['operation_type'] as String,
      entityType: json['entity_type'] as String,
      entityId: json['entity_id'] as int?,
      entityUuid: json['entity_uuid'] as String?,
      customerId: json['customer_id'] as int?,
      customerName: json['customer_name'] as String?,
      amount: (json['amount'] as num?)?.toDouble(),
      transactionType: json['transaction_type'] as String?,
      operationTime: DateTime.parse(json['operation_time'] as String),
      success: (json['success'] as int?) == 1,
      errorMessage: json['error_message'] as String?,
      direction: json['direction'] as String? ?? 'download',
    );
  }
  
  /// وصف نوع العملية
  String get operationTypeLabel {
    switch (operationType) {
      case 'create':
        return 'إنشاء';
      case 'update':
        return 'تحديث';
      case 'delete':
        return 'حذف';
      default:
        return operationType;
    }
  }
  
  /// وصف نوع الكيان
  String get entityTypeLabel {
    switch (entityType) {
      case 'transaction':
        return 'معاملة';
      case 'customer':
        return 'عميل';
      case 'invoice':
        return 'فاتورة';
      default:
        return entityType;
    }
  }
  
  /// وصف نوع المعاملة
  String get transactionTypeLabel {
    if (amount == null) return '';
    if (amount! > 0) return 'إضافة دين';
    if (amount! < 0) return 'تسديد';
    return '';
  }
  
  /// وصف الاتجاه
  String get directionLabel {
    return direction == 'download' ? 'تنزيل' : 'رفع';
  }
}
