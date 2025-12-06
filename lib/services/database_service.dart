// services/database_service.dart
// services/database_service.dart

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/customer.dart'; // تأكد من أن المسار صحيح وأن النموذج محدث
import '../models/transaction.dart'; // DebtTransaction - تأكد من أن المسار صحيح
import '../models/product.dart'; // تأكد من أن المسار صحيح
import '../models/invoice.dart'; // تأكد من أن المسار صحيح وأن النموذج محدث بحقل amountPaidOnInvoice
import '../models/invoice_item.dart'; // تأكد من أن المسار صحيح
import '../models/installer.dart'; // تأكد من أن المسار صحيح
import '../models/invoice_adjustment.dart';
import '../models/person_data.dart';
import '../models/inventory_data.dart';
import '../models/monthly_overview.dart';
import '../utils/money_calculator.dart'; // Added import
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'dart:convert';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;
  static const int _databaseVersion = 34;
  // تحكم بالطباعات التشخيصية من مصدر واحد
  // معطل في الإصدار النهائي لتجنب الطباعات المزعجة
  static const bool _verboseLogs = false;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  /// التحقق من سلامة قاعدة البيانات وإصلاحها إذا لزم الأمر
  Future<bool> checkAndRepairDatabaseIntegrity() async {
    if (!_verboseLogs) return true; // لا تطبع شيء في الوضع العادي
    try {
      final db = await database;
      
      // نسخ قاعدة البيانات احتياطياً (استخدم مجلد الدعم وتأكد من وجوده)
      try {
        final supportDir = await getApplicationSupportDirectory();
        final backupDir = Directory(join(
          supportDir.path,
          '.dart_tool',
          'sqflite_common_ffi',
          'databases',
        ));
        if (!await backupDir.exists()) {
          await backupDir.create(recursive: true);
        }
        final sourcePath = await getDatabaseFilePath();
        final backupPath = join(backupDir.path, 'debt_book_backup.db');
        final sourceFile = File(sourcePath);
        if (await sourceFile.exists()) {
          await sourceFile.copy(backupPath);
        } else {
          // ملف قاعدة البيانات غير موجود
        }
      } catch (e) {
        // تجاهل خطأ النسخ الاحتياطي
      }

      // التحقق من سلامة قاعدة البيانات
      final integrityCheck = await db.rawQuery('PRAGMA integrity_check;');
      final isIntact = integrityCheck.first.values.first == 'ok';
      
      if (!isIntact) {
        // محاولة إصلاح قاعدة البيانات
        await db.execute('VACUUM;');
        
        // إعادة بناء جداول FTS
        await rebuildFTSIndex();
        
        return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  /// استعادة قاعدة البيانات من النسخة الاحتياطية
  Future<bool> restoreFromBackup() async {
    try {
      final dbPath = await getDatabasesPath();
      final backupPath = join(dbPath, 'debt_book_backup.db');
      final currentDbPath = join(dbPath, 'debt_book.db');
      
      if (!File(backupPath).existsSync()) {
        return false;
      }
      
      // إغلاق الاتصال الحالي بقاعدة البيانات
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      
      // نسخ النسخة الاحتياطية
      File(backupPath).copySync(currentDbPath);
      
      return true;
    } catch (e) {
      return false;
    }
  }

  String _handleDatabaseError(dynamic e) {
    String errorMessage = 'حدث خطأ غير معروف في قاعدة البيانات.';
    if (e is DatabaseException) {
      if (e.toString().contains('UNIQUE constraint failed')) {
        errorMessage =
            'فشل العملية: البيانات المدخلة موجودة بالفعل (مثلاً اسم مكرر).';
      } else if (e.toString().contains('NOT NULL constraint failed')) {
        errorMessage = 'فشل العملية: هناك بيانات مطلوبة لم يتم إدخالها.';
      } else {
        errorMessage = 'حدث خطأ في قاعدة البيانات: ${e.toString()}';
      }
    } else if (e is Exception) {
      errorMessage = 'حدث خطأ غير متوقع: ${e.toString()}';
    }
    return errorMessage;
  }

  /// حساب التكلفة من النظام الهرمي للوحدات
  double _calculateCostFromHierarchy(String? unitHierarchy, String? unitCosts, String saleUnit, double quantity) {
    try {
      if (unitHierarchy == null || unitCosts == null) return 0.0;
      
      // تحليل JSON
      final hierarchy = List<Map<String, dynamic>>.from(
        jsonDecode(unitHierarchy) as List,
      );
      final costs = Map<String, double>.from(
        jsonDecode(unitCosts) as Map,
      );
      
      // البحث عن التكلفة المباشرة
      if (costs.containsKey(saleUnit)) {
        return costs[saleUnit]!;
      }
      
      // البحث في التسلسل الهرمي
      for (var item in hierarchy) {
        if (item['unit_name'] == saleUnit) {
          // حساب التكلفة من الوحدة الأساسية
          final baseCost = costs['قطعة'] ?? costs['متر'];
          if (baseCost != null) {
            final multiplier = (item['quantity'] as num).toDouble();
            return baseCost * multiplier;
          }
        }
      }
      
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  /// دالة تطبيع النص العربي - حذف التشكيل والتوحيد
  String normalizeArabic(String input) {
    if (input.isEmpty) return input;
    
    // حذف التشكيل والتطويل
    final diacritics = RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]');
    String s = input.replaceAll(diacritics, '').replaceAll('\u0640', '');
    
    // توحيد الألف والهمزات والياء والتاء المربوطة
    s = s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ؤ', 'و')
        .replaceAll('ئ', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي');
    
    // إزالة مسافات زائدة
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    
    return s;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    
    try {
      _database = await _initDatabase();
      
      // التحقق من سلامة قاعدة البيانات عند كل تهيئة
      await checkAndRepairDatabaseIntegrity();
    } catch (e) {
      // تجاهل الخطأ
      // محاولة استعادة من النسخة الاحتياطية إذا فشلت التهيئة
      final restored = await restoreFromBackup();
      if (restored) {
        _database = await _initDatabase();
      }
    }
    
    // Ensure critical tables exist for older DBs
    try {
      await _database!.execute('''
        CREATE TABLE IF NOT EXISTS invoice_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_id INTEGER NOT NULL,
          action TEXT NOT NULL,
          details TEXT,
          created_at TEXT NOT NULL,
          created_by TEXT,
          FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
        )
      ''');
    } catch (e) {
      // تجاهل الخطأ
    }
    
    // التأكد من وجود جدول التدقيق المالي
    try {
      await _database!.execute('''
        CREATE TABLE IF NOT EXISTS financial_audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          operation_type TEXT NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id INTEGER NOT NULL,
          old_values TEXT,
          new_values TEXT,
          notes TEXT,
          created_at TEXT NOT NULL
        )
      ''');
    } catch (e) {
      // تجاهل الخطأ
    }
    
    // التأكد من وجود جدول نسخ الفواتير
    try {
      await _database!.execute('''
        CREATE TABLE IF NOT EXISTS invoice_snapshots (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_id INTEGER NOT NULL,
          version_number INTEGER NOT NULL DEFAULT 1,
          snapshot_type TEXT NOT NULL,
          customer_name TEXT,
          customer_phone TEXT,
          customer_address TEXT,
          invoice_date TEXT,
          payment_type TEXT,
          total_amount REAL,
          discount REAL,
          amount_paid REAL,
          loading_fee REAL,
          items_json TEXT,
          created_at TEXT NOT NULL,
          notes TEXT,
          FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
        )
      ''');
    } catch (e) {
      // تجاهل الخطأ
    }
    // --- تحقق من وجود العمود قبل محاولة إضافته ---
    // معاملات: أعمدة المزامنة
    try {
      final txInfo = await _database!.rawQuery('PRAGMA table_info(transactions);');
      final hasIsCreatedByMe = txInfo.any((col) => col['name'] == 'is_created_by_me');
      final hasIsUploaded = txInfo.any((col) => col['name'] == 'is_uploaded');
      final hasTxnUuid = txInfo.any((col) => col['name'] == 'transaction_uuid');
      if (!hasIsCreatedByMe) {
        try {
          await _database!.execute('ALTER TABLE transactions ADD COLUMN is_created_by_me INTEGER DEFAULT 1;');
        } catch (e) {
          // تجاهل الخطأ
        }
      }
      if (!hasIsUploaded) {
        try {
          await _database!.execute('ALTER TABLE transactions ADD COLUMN is_uploaded INTEGER DEFAULT 0;');
        } catch (e) {
          // تجاهل الخطأ
        }
      }
      if (!hasTxnUuid) {
        try {
          await _database!.execute('ALTER TABLE transactions ADD COLUMN transaction_uuid TEXT;');
          await _database!.execute('CREATE UNIQUE INDEX IF NOT EXISTS ux_transactions_uuid ON transactions(transaction_uuid) WHERE transaction_uuid IS NOT NULL;');
        } catch (e) {
          // تجاهل الخطأ
        }
      }
    } catch (e) {
      // تجاهل الخطأ
    }
    final columns = await _database!.rawQuery("PRAGMA table_info(products);");
    final hasUnitHierarchy =
        columns.any((col) => col['name'] == 'unit_hierarchy');
    final hasUnitCosts =
        columns.any((col) => col['name'] == 'unit_costs');
    
    if (!hasUnitHierarchy) {
      try {
        await _database!
            .execute('ALTER TABLE products ADD COLUMN unit_hierarchy TEXT;');
      } catch (e) {
        // تجاهل الخطأ
      }
    }

    if (!hasUnitCosts) {
      try {
        await _database!
            .execute('ALTER TABLE products ADD COLUMN unit_costs TEXT;');
      } catch (e) {
        // تجاهل الخطأ
      }
    }

    // تحقق من أعمدة جدول invoice_items وإضافتها إذا لزم
    try {
      final invoiceItemsInfo =
          await _database!.rawQuery('PRAGMA table_info(invoice_items);');
      bool hasProductId = invoiceItemsInfo.any((c) => c['name'] == 'product_id');
      bool hasActualCostPrice =
          invoiceItemsInfo.any((c) => c['name'] == 'actual_cost_price');
      bool hasSaleType = invoiceItemsInfo.any((c) => c['name'] == 'sale_type');
      bool hasUnitsInLargeUnit =
          invoiceItemsInfo.any((c) => c['name'] == 'units_in_large_unit');
      bool hasUniqueId = invoiceItemsInfo.any((c) => c['name'] == 'unique_id');
      if (!hasProductId) {
        try {
          await _database!
              .execute('ALTER TABLE invoice_items ADD COLUMN product_id INTEGER');
        } catch (e) {
          // تجاهل الخطأ
        }
      }

      if (!hasActualCostPrice) {
        try {
          await _database!
              .execute('ALTER TABLE invoice_items ADD COLUMN actual_cost_price REAL');
        } catch (e) {
          // تجاهل الخطأ
        }
      }
      if (!hasSaleType) {
        try {
          await _database!
              .execute('ALTER TABLE invoice_items ADD COLUMN sale_type TEXT');
        } catch (e) {
          // تجاهل الخطأ
        }
      }
      if (!hasUnitsInLargeUnit) {
        try {
          await _database!.execute(
              'ALTER TABLE invoice_items ADD COLUMN units_in_large_unit REAL');
        } catch (e) {
          // تجاهل الخطأ
        }
      }
      if (!hasUniqueId) {
        try {
          await _database!
              .execute('ALTER TABLE invoice_items ADD COLUMN unique_id TEXT');
        } catch (e) {
          // تجاهل الخطأ
        }
      }
    } catch (e) {
      // تجاهل الخطأ
    }
    // تحقق من أعمدة جدول invoice_adjustments وإضافتها إذا لزم (لتوافق القواعد الجديدة)
    try {
      final adjInfo = await _database!.rawQuery('PRAGMA table_info(invoice_adjustments);');
      Future<void> _ensureAdjCol(String name, String ddl) async {
        if (!adjInfo.any((c) => c['name'] == name)) {
          try {
            await _database!.execute('ALTER TABLE invoice_adjustments ADD COLUMN ' + ddl + ';');
          } catch (e) {
            // تجاهل الخطأ
          }
        }
      }
      await _ensureAdjCol('product_id', 'product_id INTEGER');
      await _ensureAdjCol('product_name', 'product_name TEXT');
      await _ensureAdjCol('quantity', 'quantity REAL');
      await _ensureAdjCol('price', 'price REAL');
      await _ensureAdjCol('unit', 'unit TEXT');
      await _ensureAdjCol('sale_type', 'sale_type TEXT');
      await _ensureAdjCol('units_in_large_unit', 'units_in_large_unit REAL');
    } catch (e) {
      // تجاهل الخطأ
    }

    // --- تحقق من وجود عمود total_points في جدول installers ---
    try {
      final installersInfo = await _database!.rawQuery('PRAGMA table_info(installers);');
      final hasTotalPoints = installersInfo.any((col) => col['name'] == 'total_points');
      if (!hasTotalPoints) {
        try {
          await _database!.execute('ALTER TABLE installers ADD COLUMN total_points REAL DEFAULT 0.0;');
        } catch (e) {
          // تجاهل الخطأ
        }
      }
    } catch (e) {
      // تجاهل الخطأ
    }
    
    // --- تحقق من وجود عمود points_rate في جدول invoices ---
    try {
      final invoicesInfo = await _database!.rawQuery('PRAGMA table_info(invoices);');
      final hasPointsRate = invoicesInfo.any((col) => col['name'] == 'points_rate');
      if (!hasPointsRate) {
        try {
          await _database!.execute('ALTER TABLE invoices ADD COLUMN points_rate REAL DEFAULT 1.0;');
        } catch (e) {
          // تجاهل الخطأ
        }
      }
    } catch (e) {
      // تجاهل الخطأ
    }

    // --- إنشاء جدول نقاط المؤسسين installer_points ---
    await _database!.execute('''
      CREATE TABLE IF NOT EXISTS installer_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        installer_id INTEGER NOT NULL,
        invoice_id INTEGER,
        points REAL NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (installer_id) REFERENCES installers (id) ON DELETE CASCADE,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE SET NULL
      )
    ''');
    
    // --- إنشاء جدول أرشيف سندات القبض للعملاء ---
    await _database!.execute('''
      CREATE TABLE IF NOT EXISTS customer_receipt_vouchers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_number INTEGER NOT NULL,
        customer_id INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        before_payment REAL NOT NULL,
        paid_amount REAL NOT NULL,
        after_payment REAL NOT NULL,
        transaction_id INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE,
        FOREIGN KEY (transaction_id) REFERENCES transactions (id) ON DELETE SET NULL
      )
    ''');
    
    // --- نهاية التحقق ---

    // التحقق من حالة FTS5 وإعادة بناء الفهرس إذا لزم الأمر
    await checkFTSStatus();
    
    // تهيئة العمود المطبع وFTS5 للمنتجات الموجودة
    try {
      await initializeFTSForExistingProducts();
    } catch (e) {
      // تجاهل الخطأ
    }
    
    // إذا كان عدد السجلات في FTS أقل من المنتجات، أعد بناء الفهرس
    try {
      final productCountRes = await _database!.rawQuery('SELECT COUNT(1) as c FROM products;');
      final ftsCountRes = await _database!.rawQuery('SELECT COUNT(1) as c FROM products_fts;');
      
      final int productCount = (productCountRes.first['c'] as int?) ?? 0;
      final int ftsCount = (ftsCountRes.first['c'] as int?) ?? 0;
      
      if (productCount > 0 && ftsCount < productCount) {
        await rebuildFTSIndex();
      }

      // اختبار البحث الذكي (معطل في الإصدار النهائي)
      if (_verboseLogs && productCount > 0) {
        await testSmartSearch();
      }
    } catch (e) {
      // تجاهل الخطأ
    }

    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dir = await getApplicationSupportDirectory();
    final newPath = join(dir.path, 'debt_book.db');
    final oldPath = join(await getDatabasesPath(), 'debt_book.db');

    // print('DEBUG DB: New database path: $newPath');
    // print('DEBUG DB: Old database path: $oldPath');

    final oldFile = File(oldPath);
    final newFile = File(newPath);
    if (await oldFile.exists() && !(await newFile.exists())) {
      await oldFile.copy(newPath);
      await oldFile.delete();
    }
    
    // إنشاء مجلد الملفات الصوتية
    await ensureAudioNotesDirectory();
    
    final db = await openDatabase(
      newPath,
      version: _databaseVersion, // رفع رقم النسخة لتفعيل الترقية وإضافة عمود unique_id
      onCreate: _createDatabase,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        // تفعيل FOREIGN KEYS لضمان عمل CASCADE
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    
    // إصلاح قاعدة البيانات بعد الفتح مباشرة
    await repairDatabase(db);
    
    // ملاحظة: تم إلغاء تنظيف المعاملات اليتيمة - نتركها كما هي
    // await _cleanupOrphanedTransactions(db);
    
    return db;
  }

  /// تنظيف المعاملات اليتيمة (التي لا يوجد لها عميل)
  Future<void> _cleanupOrphanedTransactions(Database db) async {
    try {
      // حذف المعاملات التي customer_id الخاص بها غير موجود في جدول customers
      final result = await db.rawDelete('''
        DELETE FROM transactions 
        WHERE customer_id NOT IN (SELECT id FROM customers)
      ''');
      
      // لا نطبع شيء - تنظيف صامت
    } catch (e) {
      // تجاهل الخطأ - لا نوقف التطبيق
    }
  }

  // دالة لمحاولة فحص وإصلاح قاعدة البيانات
  Future<void> repairDatabase(Database db) async {
    try {
      // إنشاء مجلد النسخ الاحتياطي إذا لم يكن موجوداً
      final supportDir = await getApplicationSupportDirectory();
      final backupDir = Directory(join(
        supportDir.path,
        '.dart_tool',
        'sqflite_common_ffi',
        'databases'
      ));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // إنشاء نسخة احتياطية قبل الإصلاح
      final dbFile = File(await getDatabaseFilePath());
      if (await dbFile.exists()) {
        final backupPath = join(backupDir.path, 'debt_book_backup.db');
        await dbFile.copy(backupPath);
      }

      // فحص سلامة قاعدة البيانات
      final List<Map<String, dynamic>> check = await db.rawQuery('PRAGMA integrity_check;');
      
      if (check.isNotEmpty && check.first['integrity_check'] != 'ok') {
        // إعادة بناء الفهارس قد يصلح بعض المشاكل
        await db.rawQuery('REINDEX;');
      }
    } catch (e) {
      // تجاهل الخطأ
    }
  }

  // إرجاع مسار ملف قاعدة البيانات الحالي
  Future<String> getDatabaseFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, 'debt_book.db');
  }

  // إرجاع كائن الملف لقاعدة البيانات
  Future<File> getDatabaseFile() async {
    final path = await getDatabaseFilePath();
    return File(path);
  }

  // إنشاء مجلد الملفات الصوتية في نفس مجلد قاعدة البيانات
  Future<void> ensureAudioNotesDirectory() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final audioDir = Directory('${supportDir.path}/audio_notes');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
        
        // نسخ الملفات الصوتية من مجلد المستندات القديم إذا وجدت
        await _migrateAudioFilesFromDocuments();
      }
    } catch (e) {
      // تجاهل الخطأ
    }
  }

  /// يبني المسار المطلق لملف صوتي اعتمادًا على مسار قاعدة البيانات (Support dir)
  Future<String> getAudioNotePath(String fileName) async {
    final supportDir = await getApplicationSupportDirectory();
    return '${supportDir.path}/audio_notes/$fileName';
  }

  /// يحوّل القيمة المخزنة (قد تكون مسارًا كاملاً أو اسم ملف) إلى مسار مطلق ضمن مجلد التطبيق
  Future<String> resolveStoredAudioPath(String storedValue) async {
    // دعم كلا الفاصلين / و \
    final lastSlash = storedValue.lastIndexOf('/');
    final lastBackslash = storedValue.lastIndexOf('\\');
    final cutIndex = lastSlash > lastBackslash ? lastSlash : lastBackslash;
    final fileName = cutIndex >= 0 ? storedValue.substring(cutIndex + 1) : storedValue;
    return getAudioNotePath(fileName);
  }

  /// ترحيل قيَم المسارات الصوتية القديمة (مسار كامل) إلى مجرد أسماء ملفات
  Future<void> migrateAudioPathsToFilenames() async {
    final db = await database;
    // ترحيل transactions
    try {
      final rows = await db.query('transactions',
          columns: ['id', 'audio_note_path'],
          where: 'audio_note_path IS NOT NULL AND TRIM(audio_note_path) <> ""');
      for (final row in rows) {
        final id = row['id'] as int;
        final oldPath = row['audio_note_path'] as String?;
        if (oldPath != null && oldPath.isNotEmpty) {
          final lastSlash = oldPath.lastIndexOf('/');
          final lastBackslash = oldPath.lastIndexOf('\\');
          final cutIndex = lastSlash > lastBackslash ? lastSlash : lastBackslash;
          final fileName = cutIndex >= 0 ? oldPath.substring(cutIndex + 1) : oldPath;
          if (fileName != oldPath) {
            await db.update('transactions', {'audio_note_path': fileName}, where: 'id = ?', whereArgs: [id]);
          }
        }
      }
    } catch (e) {
      // تجاهل الخطأ
    }

    // ترحيل customers
    try {
      final rows = await db.query('customers',
          columns: ['id', 'audio_note_path'],
          where: 'audio_note_path IS NOT NULL AND TRIM(audio_note_path) <> ""');
      for (final row in rows) {
        final id = row['id'] as int;
        final oldPath = row['audio_note_path'] as String?;
        if (oldPath != null && oldPath.isNotEmpty) {
          final lastSlash = oldPath.lastIndexOf('/');
          final lastBackslash = oldPath.lastIndexOf('\\');
          final cutIndex = lastSlash > lastBackslash ? lastSlash : lastBackslash;
          final fileName = cutIndex >= 0 ? oldPath.substring(cutIndex + 1) : oldPath;
          if (fileName != oldPath) {
            await db.update('customers', {'audio_note_path': fileName}, where: 'id = ?', whereArgs: [id]);
          }
        }
      }
    } catch (e) {
      // تجاهل الخطأ
    }
  }

  // نسخ الملفات الصوتية من مجلد المستندات إلى مجلد قاعدة البيانات
  Future<void> _migrateAudioFilesFromDocuments() async {
    try {
      final documentsDir = await getApplicationDocumentsDirectory();
      final oldAudioDir = Directory('${documentsDir.path}/audio_notes');
      
      if (await oldAudioDir.exists()) {
        final supportDir = await getApplicationSupportDirectory();
        final newAudioDir = Directory('${supportDir.path}/audio_notes');
        
        await for (final entity in oldAudioDir.list()) {
          if (entity is File) {
            final fileName = entity.path.split(Platform.pathSeparator).last;
            final targetFile = File('${newAudioDir.path}/$fileName');
            
            if (!await targetFile.exists()) {
              await entity.copy(targetFile.path);
            }
          }
        }
      }
    } catch (e) {
      // تجاهل الخطأ
    }
  }

  // إرجاع جميع مسارات الملفات الصوتية المحفوظة في قاعدة البيانات (المعاملات والعملاء)
  Future<List<String>> getAllAudioNotePaths() async {
    final db = await database;
    final List<String> paths = [];
    try {
      final trs = await db.rawQuery(
          "SELECT audio_note_path FROM transactions WHERE audio_note_path IS NOT NULL AND TRIM(audio_note_path) <> ''");
      for (final row in trs) {
        final p = row['audio_note_path'] as String?;
        if (p != null && p.trim().isNotEmpty) {
          paths.add(p);
        }
      }
    } catch (e) {
      // تجاهل الخطأ
    }
    try {
      final cus = await db.rawQuery(
          "SELECT audio_note_path FROM customers WHERE audio_note_path IS NOT NULL AND TRIM(audio_note_path) <> ''");
      for (final row in cus) {
        final p = row['audio_note_path'] as String?;
        if (p != null && p.trim().isNotEmpty) {
          paths.add(p);
        }
      }
    } catch (e) {
      // تجاهل الخطأ
    }
    return paths.toSet().toList();
  }

  Future<void> _createDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        current_total_debt REAL NOT NULL DEFAULT 0.0,
        general_note TEXT,
        address TEXT,
        created_at TEXT NOT NULL,
        last_modified_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        transaction_date TEXT NOT NULL,
        amount_changed REAL NOT NULL,
        new_balance_after_transaction REAL DEFAULT 0.0,
        transaction_note TEXT,
        transaction_type TEXT,
        description TEXT,
        created_at TEXT NOT NULL,
        invoice_id INTEGER, --  يمكن أن يكون NULL إذا كانت معاملة يدوية
        FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        name_norm TEXT, -- عمود مطبع للبحث الذكي
        unit TEXT NOT NULL,
        unit_price REAL NOT NULL,
        cost_price REAL,
        pieces_per_unit INTEGER,
        length_per_unit REAL,
        price1 REAL NOT NULL,
        price2 REAL,
        price3 REAL,
        price4 REAL,
        price5 REAL,
        unit_hierarchy TEXT,
        created_at TEXT NOT NULL,
        last_modified_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE installers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL,
        total_billed_amount REAL DEFAULT 0.0 -- تم تعديل القيمة الافتراضية
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        customer_address TEXT,
        installer_name TEXT,
        invoice_date TEXT NOT NULL,
        payment_type TEXT NOT NULL,
        total_amount REAL NOT NULL,
        discount REAL NOT NULL,
        amount_paid_on_invoice REAL NOT NULL,
        created_at TEXT NOT NULL,
        last_modified_at TEXT NOT NULL,
        customer_id INTEGER,
        status TEXT NOT NULL DEFAULT 'مسودة',
        return_amount REAL NOT NULL DEFAULT 0,
        is_locked INTEGER NOT NULL DEFAULT 0,
        loading_fee REAL DEFAULT 0
      )
    ''');

    // Ensure final_total column exists then backfill to total_amount for existing rows
    try {
      final info = await db.rawQuery('PRAGMA table_info(invoices);');
      final hasFinalTotal = info.any((c) => c['name'] == 'final_total');
      if (!hasFinalTotal) {
        await db.execute('ALTER TABLE invoices ADD COLUMN final_total REAL;');
        await db.rawUpdate('UPDATE invoices SET final_total = total_amount WHERE final_total IS NULL;');
      }
    } catch (e) {
      print("DEBUG DB Error: adding/backfilling 'final_total' failed: $e");
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        unit TEXT NOT NULL,
        unit_price REAL NOT NULL,
        cost_price REAL,
        actual_cost_price REAL,
        quantity_individual REAL,
        quantity_large_unit REAL,
        applied_price REAL NOT NULL,
        item_total REAL NOT NULL,
        sale_type TEXT,
        units_in_large_unit REAL,
        unique_id TEXT NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');

    // Create adjustments table with optional item-level details
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_adjustments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        type TEXT NOT NULL CHECK(type IN ('debit','credit')),
        amount_delta REAL NOT NULL,
        product_id INTEGER,
        product_name TEXT,
        quantity REAL,
        price REAL,
        unit TEXT,
        sale_type TEXT,
        units_in_large_unit REAL,
        settlement_payment_type TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');

    // Invoice audit log (optional, lightweight)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        details TEXT,
        created_at TEXT NOT NULL,
        created_by TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');

    // Financial audit log - سجل التدقيق المالي الشامل
    await db.execute('''
      CREATE TABLE IF NOT EXISTS financial_audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id INTEGER NOT NULL,
        old_values TEXT,
        new_values TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Invoice snapshots - نسخ الفواتير لتتبع التعديلات
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        version_number INTEGER NOT NULL DEFAULT 1,
        snapshot_type TEXT NOT NULL,
        customer_name TEXT,
        customer_phone TEXT,
        customer_address TEXT,
        invoice_date TEXT,
        payment_type TEXT,
        total_amount REAL,
        discount REAL,
        amount_paid REAL,
        loading_fee REAL,
        items_json TEXT,
        created_at TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
      )
    ''');

    // -->> بداية الإضافة: إنشاء جدول FTS5 والمحفزات

    // 1. إنشاء جدول FTS5 لفهرسة أسماء المنتجات المطبع
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS products_fts USING fts5(
        name_norm,
        content='products',
        content_rowid='id',
        tokenize = 'unicode61 remove_diacritics 2'
      );
    ''');

    // 2. إنشاء محفزات (Triggers) للحفاظ على تزامن جدول FTS5 مع جدول products
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS products_ai AFTER INSERT ON products BEGIN
        INSERT INTO products_fts(rowid, name_norm) VALUES (new.id, new.name_norm);
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS products_ad AFTER DELETE ON products BEGIN
        INSERT INTO products_fts(products_fts, rowid, name_norm) VALUES ('delete', old.id, old.name_norm);
      END;
    ''');
    await db.execute('''
      CREATE TRIGGER IF NOT EXISTS products_au AFTER UPDATE ON products BEGIN
        INSERT INTO products_fts(products_fts, rowid, name_norm) VALUES ('delete', old.id, old.name_norm);
        INSERT INTO products_fts(rowid, name_norm) VALUES (new.id, new.name_norm);
      END;
    ''');

    // 3. (مهم جداً) تعبئة جدول الفهرسة بالبيانات الموجودة حاليًا عند إنشاء قاعدة البيانات لأول مرة
    await db.execute('''
      INSERT INTO products_fts(rowid, name_norm) SELECT id, name_norm FROM products;
    ''');

    // -->> نهاية الإضافة
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (_verboseLogs) {
      print(
          'DEBUG DB: Running onUpgrade from version $oldVersion to $newVersion');
    }
    //  ترتيب الترقيات مهم
    if (oldVersion < 2) {
      //  ... (أكواد الترقية السابقة إذا كانت موجودة)
    }
    if (oldVersion < 3) {
      // إضافة جدول invoice_adjustments مع الأعمدة المطلوبة
      await db.execute('''
        CREATE TABLE IF NOT EXISTS invoice_adjustments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_id INTEGER NOT NULL,
          type TEXT NOT NULL CHECK(type IN ('debit','credit')),
          amount_delta REAL NOT NULL,
          product_id INTEGER,
          product_name TEXT,
          quantity REAL,
          price REAL,
          unit TEXT,
          sale_type TEXT,
          units_in_large_unit REAL,
          settlement_payment_type TEXT,
          note TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
        )
      ''');
      
      // إضافة عمود final_total للفواتير
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN final_total REAL;');
        // تحديث الفواتير الموجودة
        await db.execute('UPDATE invoices SET final_total = total_amount WHERE final_total IS NULL;');
      } catch (e) {
        print('DEBUG DB: final_total column already exists or error: $e');
      }
    }
    if (oldVersion < 4) {
      // إضافة جدول invoice_logs إذا لم يكن موجوداً
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS invoice_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoice_id INTEGER NOT NULL,
            action TEXT NOT NULL,
            details TEXT,
            created_at TEXT NOT NULL,
            FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
          )
        ''');
      } catch (e) {
        print('DEBUG DB: invoice_logs table already exists or error: $e');
      }
    }
    //  ...
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN invoice_id INTEGER;');
      } catch (e) {
        print('DEBUG DB: invoice_id column already exists or error: $e');
      }
    }
    if (oldVersion < 9) {
      try {
        await db.execute(
            'ALTER TABLE invoices ADD COLUMN amount_paid_on_invoice REAL DEFAULT 0.0;');
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'amount_paid_on_invoice' or it already exists: $e");
      }
    }
    if (oldVersion < 10) {
      try {
        await db
            .execute('ALTER TABLE invoices ADD COLUMN customer_id INTEGER;');
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'customer_id' to invoices table or it already exists: $e");
      }
    }
    if (oldVersion < 11) {
      try {
        await db.execute(
            "ALTER TABLE invoices ADD COLUMN status TEXT NOT NULL DEFAULT 'محفوظة';");
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'status' to invoices table or it already exists: $e");
      }
    }
    if (oldVersion < 12) {
      try {
        await db.execute(
            "ALTER TABLE invoices ADD COLUMN discount REAL NOT NULL DEFAULT 0.0;");
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'discount' to invoices table or it already exists: $e");
      }
    }
    if (oldVersion < 13) {
      try {
        await db
            .execute("ALTER TABLE invoice_items ADD COLUMN sale_type TEXT;");
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'sale_type' to invoice_items table or it already exists: $e");
      }
    }
    if (oldVersion < 14) {
      try {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN transaction_type TEXT;');
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'transaction_type' to transactions table or it already exists: $e");
      }
    }
    if (oldVersion < 15) {
      try {
        await db
            .execute('ALTER TABLE transactions ADD COLUMN description TEXT;');
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'description' to transactions table or it already exists: $e");
      }
    }
    if (oldVersion < 16) {
      print('DEBUG DB: Attempting to add serial_number column.');
      try {
        await db.execute(
            'ALTER TABLE invoices ADD COLUMN serial_number INTEGER UNIQUE;');
        print('DEBUG DB: serial_number column added successfully.');
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'serial_number' to invoices table or it already exists: $e");
      }
    }
    if (oldVersion < 17) {
      print('DEBUG DB: Attempting to drop serial_number column.');
      try {
        // Check if the column exists before attempting to drop it
        final tableInfo = await db.rawQuery('PRAGMA table_info(invoices);');
        final columnExists =
            tableInfo.any((column) => column['name'] == 'serial_number');
        if (columnExists) {
          await db.execute('ALTER TABLE invoices DROP COLUMN serial_number;');
          print('DEBUG DB: serial_number column dropped successfully.');
        } else {
          print(
              'DEBUG DB: serial_number column does not exist, skipping drop.');
        }
      } catch (e) {
        print('DEBUG DB Error: Failed to drop serial_number column: $e');
      }
    }
    if (oldVersion < 18) {
      try {
        await db.execute(
            'ALTER TABLE invoices ADD COLUMN return_amount REAL DEFAULT 0.0;');
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'return_amount' to invoices table or it already exists: $e");
      }
      try {
        await db.execute(
            'ALTER TABLE invoices ADD COLUMN is_locked INTEGER DEFAULT 0;');
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'is_locked' to invoices table or it already exists: $e");
      }
    }
    if (oldVersion < 19) {
      try {
        await db.execute(
            'ALTER TABLE invoice_items ADD COLUMN units_in_large_unit REAL;');
        print(
            'DEBUG DB: units_in_large_unit column added successfully to invoice_items table.');
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'units_in_large_unit' to invoice_items table or it already exists: $e");
      }
    }
    if (oldVersion < 23) {
      try {
        await db.execute(
            'ALTER TABLE transactions ADD COLUMN audio_note_path TEXT;');
        print(
            'DEBUG DB: audio_note_path column added successfully to transactions table.');
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'audio_note_path' to transactions table or it already exists: $e");
      }
    }
    if (oldVersion < 24) {
      try {
        await db
            .execute('ALTER TABLE customers ADD COLUMN audio_note_path TEXT;');
        print(
            'DEBUG DB: audio_note_path column added successfully to customers table.');
      } catch (e) {
        print(
            "DEBUG DB Error: Failed to add column 'audio_note_path' to customers table or it already exists: $e");
      }
    }
    if (oldVersion < 25) {
      try {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN unique_id TEXT');
        print('DEBUG DB: unique_id column added successfully to invoice_items table.');
      } catch (e) {
        print("DEBUG DB Error: Failed to add column 'unique_id' to invoice_items table or it already exists: $e");
      }
    }
    // Add final_total to invoices if missing and backfill
    try {
      final info = await db.rawQuery('PRAGMA table_info(invoices);');
      final hasFinalTotal = info.any((c) => c['name'] == 'final_total');
      if (!hasFinalTotal) {
        await db.execute('ALTER TABLE invoices ADD COLUMN final_total REAL;');
        await db.rawUpdate('UPDATE invoices SET final_total = total_amount WHERE final_total IS NULL;');
        print('DEBUG DB: final_total column added and backfilled.');
      }
    } catch (e) {
      print("DEBUG DB Error: adding/backfilling 'final_total': $e");
    }

    // إضافة عمود is_read_by_others للجدول transactions
    if (oldVersion < 26) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN is_read_by_others INTEGER DEFAULT 0;');
        print('DEBUG DB: is_read_by_others column added successfully to transactions table.');
      } catch (e) {
        print("DEBUG DB Error: Failed to add column 'is_read_by_others' to transactions table or it already exists: $e");
      }
    }

    // Ensure invoice_adjustments table exists and has item fields
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS invoice_adjustments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_id INTEGER NOT NULL,
          type TEXT NOT NULL CHECK(type IN ('debit','credit')),
          amount_delta REAL NOT NULL,
          product_id INTEGER,
          product_name TEXT,
          quantity REAL,
          price REAL,
          note TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
        )
      ''');
      // Try to add missing columns if table existed without them
      final adjInfo = await db.rawQuery('PRAGMA table_info(invoice_adjustments);');
      Future<void> _ensureCol(String name, String ddl) async {
        if (!adjInfo.any((c) => c['name'] == name)) {
          try { await db.execute('ALTER TABLE invoice_adjustments ADD COLUMN ' + ddl + ';'); } catch (_) {}
        }
      }
      await _ensureCol('product_id', 'product_id INTEGER');
      await _ensureCol('product_name', 'product_name TEXT');
      await _ensureCol('quantity', 'quantity REAL');
      await _ensureCol('price', 'price REAL');
      await _ensureCol('unit', 'unit TEXT');
      await _ensureCol('sale_type', 'sale_type TEXT');
      await _ensureCol('units_in_large_unit', 'units_in_large_unit REAL');
      await _ensureCol('settlement_payment_type', 'settlement_payment_type TEXT');
    } catch (e) {
      print('DEBUG DB: ensuring invoice_adjustments schema failed: $e');
    }

    // Ensure invoice_logs exists
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS invoice_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_id INTEGER NOT NULL,
          action TEXT NOT NULL,
          details TEXT,
          created_at TEXT NOT NULL,
          created_by TEXT,
          FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
        )
      ''');
    } catch (e) {
      print('DEBUG DB: ensuring invoice_logs failed: $e');
    }
    if (oldVersion < 27) {
      // إضافة عمود actual_cost_price إلى جدول invoice_items
      try {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN actual_cost_price REAL');
        print('تم إضافة عمود actual_cost_price بنجاح');
      } catch (e) {
        print('العمود موجود بالفعل أو حدث خطأ: $e');
      }
    }
    // تأكيد وجود عمود product_id في جدول invoice_items بعد الترقية
    try {
      final info = await db.rawQuery('PRAGMA table_info(invoice_items);');
      final hasProductId = info.any((c) => c['name'] == 'product_id');
      if (!hasProductId) {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN product_id INTEGER');
        print('DEBUG DB: product_id column added to invoice_items during upgrade.');
      }
    } catch (e) {
      print("DEBUG DB: Failed ensuring 'product_id' on invoice_items during upgrade: $e");
    }
    
    // إضافة عمود balance_before_transaction إلى جدول transactions
    if (oldVersion < 30) {
      try {
        await db.execute('ALTER TABLE transactions ADD COLUMN balance_before_transaction REAL');
        print('تم إضافة عمود balance_before_transaction بنجاح');
        
        // تحديث قيم الرصيد قبل المعاملة لجميع المعاملات الموجودة
        final List<Map<String, dynamic>> customers = await db.query('customers');
        for (final customer in customers) {
          final int customerId = customer['id'];
          // جلب جميع معاملات العميل مرتبة حسب التاريخ
          final List<Map<String, dynamic>> transactions = await db.query(
            'transactions',
            where: 'customer_id = ?',
            whereArgs: [customerId],
            orderBy: 'transaction_date ASC, id ASC'
          );
          
          double runningBalance = 0.0;
          for (int i = 0; i < transactions.length; i++) {
            final int transactionId = transactions[i]['id'];
            // تحديث الرصيد قبل المعاملة
            await db.update(
              'transactions',
              {'balance_before_transaction': runningBalance},
              where: 'id = ?',
              whereArgs: [transactionId]
            );
            // تحديث الرصيد الجاري للمعاملة التالية
            runningBalance = MoneyCalculator.add(runningBalance, (transactions[i]['amount_changed'] as num).toDouble());
          }
        }
        print('تم تحديث قيم الرصيد قبل المعاملة لجميع المعاملات بنجاح');
      } catch (e) {
        print('خطأ في إضافة أو تحديث عمود balance_before_transaction: $e');
      }
    }
        if (oldVersion < 31) {
      try {
        await db.execute('ALTER TABLE invoices ADD COLUMN loading_fee REAL DEFAULT 0;');
      } catch (e) {
        print("DEBUG DB Error: Failed to add column 'loading_fee' to invoices table or it already exists: $e");
      }
    }
    
    // إضافة جدول التدقيق المالي في الترقية 32
    if (oldVersion < 32) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS financial_audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            operation_type TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id INTEGER NOT NULL,
            old_values TEXT,
            new_values TEXT,
            notes TEXT,
            created_at TEXT NOT NULL
          )
        ''');
        print('DEBUG DB: جدول التدقيق المالي تم إنشاؤه بنجاح');
      } catch (e) {
        print("DEBUG DB Error: Failed to create financial_audit_log table: $e");
      }
    }
    
    // إضافة جدول نسخ الفواتير (لتتبع التعديلات) في الترقية 33
    if (oldVersion < 33) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS invoice_snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            invoice_id INTEGER NOT NULL,
            version_number INTEGER NOT NULL DEFAULT 1,
            snapshot_type TEXT NOT NULL,
            customer_name TEXT,
            customer_phone TEXT,
            customer_address TEXT,
            invoice_date TEXT,
            payment_type TEXT,
            total_amount REAL,
            discount REAL,
            amount_paid REAL,
            loading_fee REAL,
            items_json TEXT,
            created_at TEXT NOT NULL,
            notes TEXT,
            FOREIGN KEY (invoice_id) REFERENCES invoices (id) ON DELETE CASCADE
          )
        ''');
        print('DEBUG DB: جدول نسخ الفواتير تم إنشاؤه بنجاح');
      } catch (e) {
        print("DEBUG DB Error: Failed to create invoice_snapshots table: $e");
      }
    }
  }

  // --- دوال العملاء ---
  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    
    // إدراج العميل أولاً
    final customerId = await db.insert('customers', customer.toMap());
    
    // إذا كان هناك دين مبدئي، أضف معاملة تلقائية
    if (customer.currentTotalDebt > 0) {
      final now = DateTime.now();
      await db.insert('transactions', {
        'customer_id': customerId,
        'transaction_date': now.toIso8601String(),
        'amount_changed': customer.currentTotalDebt,
        'new_balance_after_transaction': customer.currentTotalDebt,
        'transaction_note': 'الدين المبدئي عند إضافة العميل',
        'transaction_type': 'opening_balance',
        'description': 'رصيد افتتاحي',
        'created_at': now.toIso8601String(),
        'invoice_id': null,
      });
      
      print('✅ تم إضافة معاملة الدين المبدئي: ${customer.currentTotalDebt} دينار للعميل: ${customer.name}');
    }
    
    return customerId;
  }

  Future<List<Customer>> getAllCustomers({String orderBy = 'name ASC'}) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps =
          await db.query('customers', orderBy: orderBy);
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      print('Error getting all customers: $e');
      throw Exception(_handleDatabaseError(e));
    }
  }

  // إرجاع العملاء الذين لديهم دين حالي أو لديهم أي معاملة في جدول المعاملات
  Future<List<Customer>> getCustomersForDebtRegister({String orderBy = 'name ASC'}) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.*
        FROM customers c
        WHERE c.current_total_debt > 0
           OR EXISTS (SELECT 1 FROM transactions t WHERE t.customer_id = c.id LIMIT 1)
        ORDER BY ${orderBy.replaceAll("'", "")}
      ''');
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      print('Error getting customers for debt register: $e');
      throw Exception(_handleDatabaseError(e));
    }
  }

  // ترتيب العملاء حسب آخر إضافة دين (من الأحدث للأقدم)
  Future<List<int>> getCustomerIdsSortedByLastDebtAdded() async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.id, MAX(t.transaction_date) as last_debt_date
        FROM customers c
        LEFT JOIN transactions t ON t.customer_id = c.id 
          AND t.transaction_type IN ('manual_debt', 'DEBT_ADDITION', 'debt_addition')
        WHERE c.current_total_debt > 0
           OR EXISTS (SELECT 1 FROM transactions t2 WHERE t2.customer_id = c.id LIMIT 1)
        GROUP BY c.id
        ORDER BY last_debt_date DESC NULLS LAST, c.name ASC
      ''');
      return maps.map((m) => m['id'] as int).toList();
    } catch (e) {
      print('Error getting customers sorted by last debt added: $e');
      return [];
    }
  }

  // ترتيب العملاء حسب آخر تسديد (من الأحدث للأقدم)
  Future<List<int>> getCustomerIdsSortedByLastPayment() async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.id, MAX(t.transaction_date) as last_payment_date
        FROM customers c
        LEFT JOIN transactions t ON t.customer_id = c.id 
          AND t.transaction_type IN ('debt_payment', 'DEBT_PAYMENT')
        WHERE c.current_total_debt > 0
           OR EXISTS (SELECT 1 FROM transactions t2 WHERE t2.customer_id = c.id LIMIT 1)
        GROUP BY c.id
        ORDER BY last_payment_date DESC NULLS LAST, c.name ASC
      ''');
      return maps.map((m) => m['id'] as int).toList();
    } catch (e) {
      print('Error getting customers sorted by last payment: $e');
      return [];
    }
  }

  // ترتيب العملاء حسب آخر معاملة (أي نوع - من الأحدث للأقدم)
  Future<List<int>> getCustomerIdsSortedByLastTransaction() async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT c.id, MAX(t.transaction_date) as last_transaction_date
        FROM customers c
        LEFT JOIN transactions t ON t.customer_id = c.id
        WHERE c.current_total_debt > 0
           OR EXISTS (SELECT 1 FROM transactions t2 WHERE t2.customer_id = c.id LIMIT 1)
        GROUP BY c.id
        ORDER BY last_transaction_date DESC NULLS LAST, c.name ASC
      ''');
      return maps.map((m) => m['id'] as int).toList();
    } catch (e) {
      print('Error getting customers sorted by last transaction: $e');
      return [];
    }
  }

  Future<Customer?> getCustomerById(int id) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'customers',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return Customer.fromMap(maps.first);
      }
    } catch (e) {
      print('Error getting customer by ID $id: $e');
      throw Exception(_handleDatabaseError(e));
    }
    return null;
  }

  Future<int> updateCustomer(Customer customer) async {
    final db = await database;
    return await db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    try {
      // حذف ملفات الصوت المرتبطة بالعميل والمعاملات أولاً
      try {
        // صوت العميل نفسه
        final customerRows = await db.query('customers', columns: ['audio_note_path'], where: 'id = ?', whereArgs: [id], limit: 1);
        if (customerRows.isNotEmpty) {
          final audio = customerRows.first['audio_note_path'] as String?;
          if (audio != null && audio.trim().isNotEmpty) {
            final path = await resolveStoredAudioPath(audio);
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
          }
        }

        // أصوات المعاملات الخاصة بالعميل
        final txRows = await db.query(
          'transactions',
          columns: ['audio_note_path'],
          where: 'customer_id = ? AND audio_note_path IS NOT NULL AND TRIM(audio_note_path) <> ""',
          whereArgs: [id],
        );
        for (final row in txRows) {
          final audio = row['audio_note_path'] as String?;
          if (audio != null && audio.trim().isNotEmpty) {
            final path = await resolveStoredAudioPath(audio);
            final file = File(path);
            if (await file.exists()) {
              try {
                await file.delete();
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        // لا تمنع حذف العميل إذا فشل حذف الملفات
      }

      // حذف المعاملات المرتبطة بالعميل يدوياً (لضمان الحذف حتى لو CASCADE لم يعمل)
      await db.delete(
        'transactions',
        where: 'customer_id = ?',
        whereArgs: [id],
      );
      
      // حذف سندات القبض المرتبطة بالعميل
      await db.delete(
        'customer_receipt_vouchers',
        where: 'customer_id = ?',
        whereArgs: [id],
      );
      
      // حذف العميل
      return await db.delete(
        'customers',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<List<Customer>> searchCustomers(String query) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'customers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: ['%$query%', '%$query%'],
        orderBy: 'name ASC',
      );
      return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  // --- دوال المنتجات ---
  Future<int> insertProduct(Product product) async {
    final db = await database;
    try {
      // تطبيع اسم المنتج وحفظه في العمود المطبع
      final productMap = product.toMap();
      productMap['name_norm'] = normalizeArabic(product.name);
      // بناء unit_costs تلقائياً عند وجود تكلفة أساس أو طول/هرمية
      try {
        if (product.costPrice != null && product.costPrice! > 0) {
          final Map<String, dynamic> newUnitCosts = {};
          if (product.unit == 'piece') {
            double currentCost = product.costPrice!;
            newUnitCosts['قطعة'] = currentCost;
            if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
              try {
                final List<dynamic> hierarchy = jsonDecode(product.unitHierarchy!.replaceAll("'", '"')) as List<dynamic>;
                for (final level in hierarchy) {
                  final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                  final double qty = (level['quantity'] is num)
                      ? (level['quantity'] as num).toDouble()
                      : double.tryParse(level['quantity'].toString()) ?? 1.0;
                  currentCost = currentCost * qty;
                  if (unitName.isNotEmpty) {
                    newUnitCosts[unitName] = currentCost;
                  }
                }
              } catch (_) {}
            }
          } else if (product.unit == 'meter') {
            newUnitCosts['متر'] = product.costPrice!;
            if (product.lengthPerUnit != null && product.lengthPerUnit! > 0) {
              newUnitCosts['لفة'] = product.costPrice! * product.lengthPerUnit!;
            }
          } else {
            newUnitCosts[product.unit] = product.costPrice!;
          }
          productMap['unit_costs'] = jsonEncode(newUnitCosts);
        }
      } catch (e) {
        print('WARN: Failed to build unit_costs on insert: $e');
      }
      
      return await db.insert('products', productMap);
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<List<Product>> getAllProducts({String orderBy = 'name ASC'}) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps =
          await db.query('products', orderBy: orderBy);
      return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    try {
      return await db.delete(
        'products',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  // --- دوال الفنيين ---
  Future<int> insertInstaller(Installer installer) async {
    final db = await database;
    try {
      return await db.insert(
          'installers', installer.toMap()); // افترض أن toMap جاهزة
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<List<Installer>> getAllInstallers(
      {String orderBy = 'name ASC'}) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps =
          await db.query('installers', orderBy: orderBy);
      return List.generate(maps.length, (i) => Installer.fromMap(maps[i]));
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  // --- Installer Points System ---

  /// Add points to an installer manually
  Future<void> addInstallerPoints(int installerId, double points, String reason, {int? invoiceId}) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Insert into installer_points
      await txn.insert('installer_points', {
        'installer_id': installerId,
        'invoice_id': invoiceId,
        'points': points,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2. Update installer total_points
      final List<Map<String, dynamic>> installerMaps = await txn.query(
        'installers',
        columns: ['total_points'],
        where: 'id = ?',
        whereArgs: [installerId],
      );
      
      if (installerMaps.isNotEmpty) {
        double currentPoints = (installerMaps.first['total_points'] as num?)?.toDouble() ?? 0.0;
        double newTotal = MoneyCalculator.add(currentPoints, points);
        
        await txn.update(
          'installers',
          {'total_points': newTotal},
          where: 'id = ?',
          whereArgs: [installerId],
        );
      }
    });
  }

  /// Deduct points from an installer manually
  Future<void> deductInstallerPoints(int installerId, double points, String reason) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Insert into installer_points with negative value
      await txn.insert('installer_points', {
        'installer_id': installerId,
        'invoice_id': null,
        'points': -points, // Negative value for deduction
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2. Update installer total_points
      final List<Map<String, dynamic>> installerMaps = await txn.query(
        'installers',
        columns: ['total_points'],
        where: 'id = ?',
        whereArgs: [installerId],
      );
      
      if (installerMaps.isNotEmpty) {
        double currentPoints = (installerMaps.first['total_points'] as num?)?.toDouble() ?? 0.0;
        double newTotal = MoneyCalculator.subtract(currentPoints, points); // Subtract the points
        
        await txn.update(
          'installers',
          {'total_points': newTotal},
          where: 'id = ?',
          whereArgs: [installerId],
        );
      }
    });
  }

  /// Get points history for an installer
  Future<List<Map<String, dynamic>>> getInstallerPointsHistory(int installerId) async {
    final db = await database;
    return await db.query(
      'installer_points',
      where: 'installer_id = ?',
      whereArgs: [installerId],
      orderBy: 'created_at DESC',
    );
  }

  /// Update points from an invoice (handle create/update)
  /// [customPoints] - إذا تم تحديده، يتم استخدامه بدلاً من الحساب التلقائي
  /// [pointsPerHundredThousand] - عدد النقاط لكل 100,000 (الافتراضي 1.0)
  Future<void> updateInstallerPointsFromInvoice(
    int invoiceId, 
    String installerName, 
    double invoiceTotal, {
    double? customPoints,
    double pointsPerHundredThousand = 1.0,
  }) async {
    if (installerName.trim().isEmpty) return;

    final db = await database;
    
    // 1. Find the installer by name
    final List<Map<String, dynamic>> installers = await db.query(
      'installers',
      where: 'name = ?',
      whereArgs: [installerName],
    );
    
    if (installers.isEmpty) return; 
    
    final int installerId = installers.first['id'] as int;
    
    // 2. Calculate points: استخدام النقاط المخصصة أو الحساب التلقائي
    final double newPoints = customPoints ?? (invoiceTotal / 100000.0) * pointsPerHundredThousand;
    
    await db.transaction((txn) async {
      // 3. Check if points already exist for this invoice
      final List<Map<String, dynamic>> existingPoints = await txn.query(
        'installer_points',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
      );
      
      if (existingPoints.isNotEmpty) {
        // Update existing entry
        final double oldPoints = (existingPoints.first['points'] as num).toDouble();
        final double diff = MoneyCalculator.subtract(newPoints, oldPoints);
        
        if (diff.abs() > 0.001) {
          await txn.update(
            'installer_points',
            {
              'points': newPoints,
              'reason': 'فاتورة رقم $invoiceId (تعديل)',
            },
            where: 'invoice_id = ?',
            whereArgs: [invoiceId],
          );
          
          // Update total points
           final List<Map<String, dynamic>> inst = await txn.query(
            'installers',
            columns: ['total_points'],
            where: 'id = ?',
            whereArgs: [installerId],
          );
          double currentTotal = (inst.first['total_points'] as num?)?.toDouble() ?? 0.0;
          await txn.update(
            'installers',
            {'total_points': currentTotal + diff},
            where: 'id = ?',
            whereArgs: [installerId],
          );
        }
      } else {
        // Insert new entry
        await txn.insert('installer_points', {
          'installer_id': installerId,
          'invoice_id': invoiceId,
          'points': newPoints,
          'reason': 'فاتورة رقم $invoiceId',
          'created_at': DateTime.now().toIso8601String(),
        });
        
        // Update total points
         final List<Map<String, dynamic>> inst = await txn.query(
          'installers',
          columns: ['total_points'],
          where: 'id = ?',
          whereArgs: [installerId],
        );
        double currentTotal = (inst.first['total_points'] as num?)?.toDouble() ?? 0.0;
        await txn.update(
          'installers',
          {'total_points': currentTotal + newPoints},
          where: 'id = ?',
          whereArgs: [installerId],
        );
      }
    });
  }

  /// Recalculate and update total billed amount for a specific installer
  Future<void> updateInstallerBilledAmount(int installerId) async {
    final db = await database;
    
    // 1. Get installer name
    final List<Map<String, dynamic>> installerMaps = await db.query(
      'installers',
      columns: ['name'],
      where: 'id = ?',
      whereArgs: [installerId],
    );
    
    if (installerMaps.isEmpty) return;
    final String installerName = installerMaps.first['name'] as String;

    // 2. Sum all invoices for this installer
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT SUM(total_amount) as total 
      FROM invoices 
      WHERE installer_name = ? AND status = 'محفوظة'
    ''', [installerName]);
    
    double total = 0.0;
    if (result.isNotEmpty && result.first['total'] != null) {
      total = (result.first['total'] as num).toDouble();
    }

    // 3. Update installer record
    await db.update(
      'installers',
      {'total_billed_amount': total},
      where: 'id = ?',
      whereArgs: [installerId],
    );
  }
  // ... (بقية دوال الفنيين CRUD)

  // --- دوال المعاملات (Transactions) ---

  /// التحقق من صحة رصيد العميل ومطابقته لآخر معاملة
  Future<void> verifyCustomerBalance(int customerId) async {
    final db = await database;
    
    final customer = await getCustomerById(customerId);
    if (customer == null) throw Exception('Customer not found');

    // جلب آخر معاملة فقط
    final List<Map<String, dynamic>> lastTxRows = await db.query(
      'transactions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'transaction_date DESC, id DESC',
      limit: 1,
    );

    if (lastTxRows.isEmpty) {
      if (customer.currentTotalDebt.abs() > 0.01) {
         throw Exception('خطأ في البيانات: العميل لديه رصيد ${customer.currentTotalDebt} ولكن لا توجد معاملات مسجلة.');
      }
      return;
    }

    final lastTx = DebtTransaction.fromMap(lastTxRows.first);
    
    // التحقق من تطابق رصيد العميل مع رصيد آخر معاملة
    final diff = (customer.currentTotalDebt - lastTx.newBalanceAfterTransaction!).abs();
    if (diff > 0.01) {
      throw Exception('خطأ خطير في التكامل المالي: رصيد العميل (${customer.currentTotalDebt}) لا يطابق رصيد آخر معاملة (${lastTx.newBalanceAfterTransaction}).');
    }
  }

  Future<int> insertTransaction(DebtTransaction transaction) async {
    final db = await database;
    // استخدام معاملة قاعدة بيانات (Transaction) لضمان الذرية (Atomicity)
    return await db.transaction((txn) async {
      try {
        // 1. جلب العميل (مصدر الحقيقة للرصيد الحالي)
        final List<Map<String, dynamic>> customerMaps = await txn.query(
          'customers',
          where: 'id = ?',
          whereArgs: [transaction.customerId],
          limit: 1,
        );
        if (customerMaps.isEmpty) {
          throw Exception('لم يتم العثور على العميل');
        }
        final customer = Customer.fromMap(customerMaps.first);
        
        // 2. جلب آخر معاملة للتحقق من التسلسل
        final List<Map<String, dynamic>> lastTxRows = await txn.query(
          'transactions',
          where: 'customer_id = ?',
          whereArgs: [transaction.customerId],
          orderBy: 'transaction_date DESC, id DESC',
          limit: 1,
        );
        
        double verifiedBalanceBefore = customer.currentTotalDebt;

        // التحقق من سلامة البيانات قبل الإضافة
        if (lastTxRows.isNotEmpty) {
          final lastTx = DebtTransaction.fromMap(lastTxRows.first);
          if ((verifiedBalanceBefore - lastTx.newBalanceAfterTransaction!).abs() > 0.01) {
             // في حال وجود عدم تطابق، نعتمد على الرصيد المسجل في العميل لكن نسجل تحذيراً
             print('تحذير: عدم تطابق رصيد العميل مع آخر معاملة قبل الإضافة الجديدة.');
             // يمكن تفعيل السطر التالي لرفض العملية تماماً إذا أردنا صرامة تامة
             // throw Exception('تنبيه أمني: رصيد العميل الحالي لا يتطابق مع آخر معاملة مسجلة.');
          }
        }
        
        // 3. حساب الرصيد الجديد
        double newBalanceAfterTransaction = MoneyCalculator.add(verifiedBalanceBefore, transaction.amountChanged);
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🔒 تحسين الأمان: التحقق المزدوج (Double-entry verification)
        // ═══════════════════════════════════════════════════════════════════════════
        final verification = MoneyCalculator.verifyTransaction(
          balanceBefore: verifiedBalanceBefore,
          amountChanged: transaction.amountChanged,
          expectedBalanceAfter: newBalanceAfterTransaction,
        );
        
        if (!verification.isValid) {
          print('⚠️ تحذير أمني: ${verification.errorMessage}');
          // في حالة عدم التطابق، نستخدم القيمة المحسوبة
          newBalanceAfterTransaction = verification.calculatedBalance;
        }
        
        // 4. تجهيز المعاملة بالأرصدة الصحيحة
        final updatedTransaction = transaction.copyWith(
          balanceBeforeTransaction: verifiedBalanceBefore,
          newBalanceAfterTransaction: newBalanceAfterTransaction,
        );
        
        // 5. إدراج المعاملة
        final id = await txn.insert('transactions', updatedTransaction.toMap());

        // 6. تحديث رصيد العميل
        await txn.update(
          'customers',
          {
            'current_total_debt': newBalanceAfterTransaction,
            'last_modified_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [transaction.customerId],
        );
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🔒 تحسين الأمان: التحقق بعد الحفظ (Post-save verification)
        // ═══════════════════════════════════════════════════════════════════════════
        final List<Map<String, dynamic>> verifyCustomer = await txn.query(
          'customers',
          columns: ['current_total_debt'],
          where: 'id = ?',
          whereArgs: [transaction.customerId],
          limit: 1,
        );
        
        if (verifyCustomer.isNotEmpty) {
          final savedBalance = (verifyCustomer.first['current_total_debt'] as num).toDouble();
          if (!MoneyCalculator.areEqual(savedBalance, newBalanceAfterTransaction)) {
            print('⚠️ تحذير أمني: الرصيد المحفوظ ($savedBalance) ≠ الرصيد المتوقع ($newBalanceAfterTransaction)');
          }
        }

        return id;
      } catch (e) {
        throw Exception(_handleDatabaseError(e));
      }
    });
  }

  Future<DebtTransaction?> getTransactionById(int id) async {
    final db = await database;
    try {
      final maps = await db.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
      if (maps.isNotEmpty) {
        return DebtTransaction.fromMap(maps.first);
      }
      return null;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// تحديث معاملة يدوية وإعادة حساب إجمالي دين العميل من جميع المعاملات
  /// يعيد العميل بعد التحديث لعكس الرصيد الجديد في الواجهة
  Future<Customer> updateManualTransaction(DebtTransaction updated) async {
    final db = await database;
    if (updated.id == null) {
      throw Exception('لا يمكن تعديل معاملة بدون معرّف');
    }

    try {
      // قراءة المعاملة القديمة للتعرّف على الفرق
      final oldTx = await getTransactionById(updated.id!);
      if (oldTx == null) {
        throw Exception('لم يتم العثور على المعاملة المراد تعديلها');
      }
      if (oldTx.invoiceId != null) {
        // للحفاظ على سلامة الفواتير، لا نسمح بتعديل معاملات مرتبطة بفاتورة من هنا
        throw Exception('لا يمكن تعديل معاملة مرتبطة بفاتورة من هنا');
      }

      // جلب العميل
      final customer = await getCustomerById(oldTx.customerId);
      if (customer == null) {
        throw Exception('العميل غير موجود');
      }

      // الحصول على المعاملات السابقة لهذه المعاملة لتحديد الرصيد قبلها
      final transactions = await getCustomerTransactions(
        oldTx.customerId, 
        orderBy: 'transaction_date ASC, id ASC'
      );
      
      // البحث عن المعاملة الحالية في القائمة
      int currentIndex = transactions.indexWhere((t) => t.id == oldTx.id);
      if (currentIndex == -1) {
        throw Exception('لم يتم العثور على المعاملة في قائمة معاملات العميل');
      }
      
      // حساب الرصيد قبل المعاملة
      double balanceBeforeTransaction = 0.0;
      if (currentIndex > 0) {
        balanceBeforeTransaction = transactions[currentIndex - 1].newBalanceAfterTransaction ?? 0.0;
      }
      
      // حدد نوع المعاملة بناءً على الإشارة
      final String newType = updated.amountChanged >= 0
          ? 'manual_debt'
          : 'manual_payment';
          
      // حساب الرصيد الجديد بعد المعاملة بناءً على الرصيد قبلها
      final double newBalanceAfter = MoneyCalculator.add(balanceBeforeTransaction, updated.amountChanged);
      
      // تحديث المعاملة بالبيانات الجديدة
      int updatedRows = await db.update(
        'transactions',
        {
          'amount_changed': updated.amountChanged,
          'transaction_note': updated.transactionNote,
          'transaction_date': updated.transactionDate.toIso8601String(),
          'transaction_type': newType,
          'new_balance_after_transaction': newBalanceAfter,
          'balance_before_transaction': balanceBeforeTransaction,
        },
        where: 'id = ?',
        whereArgs: [updated.id],
      );
      
      if (updatedRows == 0) {
        throw Exception('فشل في تحديث المعاملة، لم يتم تحديث أي صفوف');
      }
      
      // تحديث أرصدة المعاملات اللاحقة
      if (currentIndex < transactions.length - 1) {
        double runningBalance = newBalanceAfter;
        for (int i = currentIndex + 1; i < transactions.length; i++) {
          // تحديث الرصيد قبل المعاملة والرصيد بعد المعاملة في عملية واحدة
          double newBalance = MoneyCalculator.add(runningBalance, transactions[i].amountChanged);
          int updatedSubRows = await db.update(
            'transactions',
            {
              'balance_before_transaction': runningBalance,
              'new_balance_after_transaction': newBalance,
            },
            where: 'id = ?',
            whereArgs: [transactions[i].id],
          );
          
          if (updatedSubRows == 0) {
            print('تحذير: فشل في تحديث المعاملة التالية بمعرف ${transactions[i].id}');
          }
          
          // تحديث الرصيد الجاري للمعاملة التالية
          runningBalance = newBalance;
        }
      }
      
      // إعادة حساب الرصيد الإجمالي من جميع المعاملات وتحديث رصيد العميل
      await recalculateAndApplyCustomerDebt(oldTx.customerId);

      // جلب العميل المحدث
      final updatedCustomer = await getCustomerById(oldTx.customerId);
      if (updatedCustomer == null) {
        throw Exception('فشل في تحديث بيانات العميل');
      }

      return updatedCustomer;
    } catch (e) {
      print('خطأ في تحديث المعاملة: ${e.toString()}');
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// توافق واجهة: تحديث معاملة (حاليًا للمعاملات اليدوية فقط)
  Future<Customer> updateTransaction(DebtTransaction updated) async {
    return updateManualTransaction(updated);
  }

  /// تحويل نوع المعاملة من إضافة دين إلى تسديد دين أو العكس
  Future<Customer> convertTransactionType(int transactionId) async {
    final db = await database;
    
    try {
      // قراءة المعاملة الحالية
      final transaction = await getTransactionById(transactionId);
      if (transaction == null) {
        throw Exception('لم يتم العثور على المعاملة المراد تحويلها');
      }
      
      if (transaction.invoiceId != null) {
        // لا نسمح بتحويل معاملات مرتبطة بفاتورة
        throw Exception('لا يمكن تحويل نوع معاملة مرتبطة بفاتورة');
      }
      
      // الحصول على المعاملات مرتبة حسب التاريخ
      final transactions = await getCustomerTransactions(
        transaction.customerId, 
        orderBy: 'transaction_date ASC, id ASC'
      );
      
      // البحث عن المعاملة الحالية في القائمة
      int currentIndex = transactions.indexWhere((t) => t.id == transactionId);
      if (currentIndex == -1) {
        throw Exception('لم يتم العثور على المعاملة في قائمة معاملات العميل');
      }
      
      // حساب الرصيد قبل المعاملة
      double balanceBeforeTransaction = 0.0;
      if (currentIndex > 0) {
        balanceBeforeTransaction = transactions[currentIndex - 1].newBalanceAfterTransaction ?? 0.0;
      }
      
      // تحويل المبلغ من موجب إلى سالب أو العكس
      final double newAmount = -transaction.amountChanged;
      
      // تحديد نوع المعاملة الجديد بناءً على الإشارة
      final String newType = newAmount >= 0 ? 'manual_debt' : 'manual_payment';
      
      // حساب الرصيد الجديد بعد المعاملة بناءً على الرصيد قبلها
      final double newBalanceAfter = MoneyCalculator.add(balanceBeforeTransaction, newAmount);
      
      // تحديث المعاملة بالمبلغ والنوع الجديد
      await db.update(
        'transactions',
        {
          'amount_changed': newAmount,
          'transaction_type': newType,
          'new_balance_after_transaction': newBalanceAfter,
          'balance_before_transaction': balanceBeforeTransaction,
        },
        where: 'id = ?',
        whereArgs: [transactionId],
      );
      
      // تحديث أرصدة المعاملات اللاحقة
      if (currentIndex < transactions.length - 1) {
        double runningBalance = newBalanceAfter;
        for (int i = currentIndex + 1; i < transactions.length; i++) {
          // تحديث الرصيد قبل المعاملة للمعاملة الحالية
          await db.update(
            'transactions',
            {
              'balance_before_transaction': runningBalance,
              'new_balance_after_transaction': MoneyCalculator.add(runningBalance, transactions[i].amountChanged),
            },
            where: 'id = ?',
            whereArgs: [transactions[i].id],
          );
          
          // تحديث الرصيد الجاري للمعاملة التالية
          runningBalance = MoneyCalculator.add(runningBalance, transactions[i].amountChanged);
        }
      }
      
      // إعادة حساب الرصيد الإجمالي من جميع المعاملات وتحديث رصيد العميل
      await recalculateAndApplyCustomerDebt(transaction.customerId);
      
      // جلب العميل المحدث
      final updatedCustomer = await getCustomerById(transaction.customerId);
      if (updatedCustomer == null) {
        throw Exception('فشل في تحديث بيانات العميل');
      }
      
      return updatedCustomer;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// إعادة احتساب مجموع دين العميل من جميع المعاملات وتطبيقه على سجل العميل
  Future<double> recalculateAndApplyCustomerDebt(int customerId) async {
    final db = await database;
    // احسب مجموع amount_changed للعميل
    final res = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) AS total FROM transactions WHERE customer_id = ?;',
        [customerId]);
    final double total = ((res.first['total'] as num?) ?? 0).toDouble();

    final customer = await getCustomerById(customerId);
    if (customer != null) {
      final updated = customer.copyWith(
        currentTotalDebt: total,
        lastModifiedAt: DateTime.now(),
      );
      await updateCustomer(updated);
    }
    return total;
  }

  /// إعادة حساب الرصيد بعد كل معاملة بناءً على الترتيب الزمني
  Future<void> recalculateCustomerTransactionBalances(int customerId) async {
    final db = await database;
    
    // جلب جميع معاملات العميل مرتبة حسب التاريخ
    final transactions = await getCustomerTransactions(customerId, orderBy: 'transaction_date ASC, id ASC');
    
    double runningBalance = 0.0;
    
    // تحديث الرصيد بعد كل معاملة
    for (final transaction in transactions) {
      final double balanceBefore = runningBalance;
      runningBalance = MoneyCalculator.add(runningBalance, transaction.amountChanged);
      
      await db.update(
        'transactions',
        {
          'balance_before_transaction': balanceBefore,
          'new_balance_after_transaction': runningBalance
        },
        where: 'id = ?',
        whereArgs: [transaction.id],
      );
    }
  }

  /// إعادة حساب جميع أرصدة المعاملات لجميع العملاء (دالة مساعدة لإصلاح البيانات)
  Future<void> recalculateAllTransactionBalances() async {
    final db = await database;
    
    // جلب جميع العملاء
    final customers = await getAllCustomers();
    
    for (final customer in customers) {
      if (customer.id != null) {
        await recalculateCustomerTransactionBalances(customer.id!);
        await recalculateAndApplyCustomerDebt(customer.id!);
      }
    }
  }

  /// دالة مساعدة لإصلاح جميع البيانات بعد تحديث قاعدة البيانات
  Future<void> fixAllTransactionBalances() async {
    print('بدء إصلاح جميع أرصدة المعاملات...');
    await recalculateAllTransactionBalances();
    print('تم إصلاح جميع أرصدة المعاملات بنجاح!');
  }

  Future<List<DebtTransaction>> getCustomerTransactions(int customerId,
      {String orderBy = 'transaction_date DESC, id DESC'}) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'transactions',
        where: 'customer_id = ?',
        whereArgs: [customerId],
        orderBy: orderBy,
      );
      return List.generate(
          maps.length, (i) => DebtTransaction.fromMap(maps[i]));
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }
  // ... (بقية دوال المعاملات)

  // --- دوال الفواتير والمنطق المحاسبي ---

  Future<Customer?> _findCustomer(
      DatabaseExecutor txn, String customerName, String? customerPhone) async {
    //  محاولة البحث بالاسم والهاتف (إذا كان الهاتف موجودًا)
    String whereClause = 'name = ?';
    List<dynamic> whereArgs = [customerName.trim()];

    if (customerPhone != null && customerPhone.trim().isNotEmpty) {
      whereClause += ' AND phone = ?';
      whereArgs.add(customerPhone.trim());
    } else {
      //  إذا كان الهاتف فارغًا في الفاتورة، ابحث عن عميل بنفس الاسم وهاتفه فارغ أو NULL
      whereClause += ' AND (phone IS NULL OR phone = "")';
    }

    try {
      final List<Map<String, dynamic>> customerMaps = await txn.query(
        'customers',
        where: whereClause,
        whereArgs: whereArgs,
        limit: 1,
      );
      if (customerMaps.isNotEmpty) {
        return Customer.fromMap(customerMaps.first);
      }
    } catch (e) {
      print('Error finding customer "$customerName": $e');
      // لا ترمي استثناء هنا، فقط أرجع null ليتم التعامل معه لاحقًا
    }
    return null;
  }

  Future<void> _updateInstallerTotal(
      DatabaseExecutor txn, String? installerName, double amountChange) async {
    if (installerName != null &&
        installerName.trim().isNotEmpty &&
        amountChange != 0) {
      try {
        await txn.rawUpdate('''
          UPDATE installers
          SET total_billed_amount = COALESCE(total_billed_amount, 0.0) + ?
          WHERE name = ?
        ''', [amountChange, installerName.trim()]);
      } catch (e) {
        print("Error updating installer total for $installerName: $e");
        //  قد ترغب في رمي استثناء هنا إذا كان تحديث الفني حرجًا
      }
    }
  }

  String _generateInvoiceUpdateTransactionNote(
      Invoice oldInvoice, Invoice newInvoice, double netDebtChangeForCustomer) {
    List<String> changes = [];
    if (oldInvoice.totalAmount.toStringAsFixed(2) !=
        newInvoice.totalAmount.toStringAsFixed(2)) {
      changes.add(
          'إجمالي الفاتورة تغير من ${oldInvoice.totalAmount.toStringAsFixed(2)} إلى ${newInvoice.totalAmount.toStringAsFixed(2)}.');
    }
    if (oldInvoice.paymentType != newInvoice.paymentType) {
      changes.add(
          'نوع الدفع تغير من "${oldInvoice.paymentType}" إلى "${newInvoice.paymentType}".');
    }

    String mainMessage;
    if (netDebtChangeForCustomer > 0) {
      mainMessage =
          'نتج عن ذلك زيادة صافية في دين العميل بمقدار ${netDebtChangeForCustomer.toStringAsFixed(2)}.';
    } else if (netDebtChangeForCustomer < 0) {
      mainMessage =
          'نتج عن ذلك نقصان صافي في دين العميل بمقدار ${(-netDebtChangeForCustomer).toStringAsFixed(2)}.';
    } else {
      mainMessage = 'لم يتغير صافي الدين على العميل بسبب هذا التعديل.';
    }

    if (changes.isEmpty && netDebtChangeForCustomer == 0) {
      return 'تحديث بيانات الفاتورة #${newInvoice.id} (بدون تغيير مالي مؤثر على رصيد دين العميل).';
    }
    return 'تعديل فاتورة #${newInvoice.id}: ${changes.join(' ')} $mainMessage'
        .trim();
  }

  Future<int> insertInvoice(Invoice invoice) async {
    final db = await database;
    try {
      // No serial number generation needed
      final id = await db.insert('invoices', invoice.toMap());
      // Initialize final_total to equal total_amount at creation
      try {
        await db.rawUpdate('UPDATE invoices SET final_total = total_amount WHERE id = ? AND (final_total IS NULL OR final_total = 0)', [id]);
      } catch (_) {}
      return id;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// حفظ الفاتورة بشكل كامل وآمن (Transaction)
  /// هذه الدالة تضمن حفظ كل البيانات أو عدم حفظ أي شيء في حال حدوث خطأ
  Future<Invoice> saveCompleteInvoice({
    required Invoice invoice,
    required List<InvoiceItem> items,
    required Customer? customerData, // بيانات العميل (للبحث أو الإنشاء)
    required bool isUpdate,
    Invoice? oldInvoice, // الفاتورة القديمة في حالة التعديل
    String? createdBy, // للمراقبة
  }) async {
    final db = await database;
    
    return await db.transaction((txn) async {
      try {
        // 1. معالجة العميل (Customer Handling)
        int? customerId = invoice.customerId;
        Customer? customer;
        
        // إذا تم تمرير بيانات عميل، نتأكد من وجوده أو ننشئه
        if (customerData != null) {
          // محاولة البحث عن العميل
          customer = await _findCustomer(txn, customerData.name, customerData.phone);
          
          if (customer == null) {
            // إنشاء عميل جديد
            final newCustomer = customerData.copyWith(
              createdAt: DateTime.now(),
              lastModifiedAt: DateTime.now(),
              currentTotalDebt: 0.0, // الدين سيتم تحديثه لاحقاً
            );
            final newId = await txn.insert('customers', newCustomer.toMap());
            customer = newCustomer.copyWith(id: newId);
            customerId = newId;
          } else {
            customerId = customer.id;
          }
        }

        // تحديث معرف العميل في الفاتورة
        var invoiceToSave = invoice.copyWith(customerId: customerId);

        // 2. معالجة الفني (Installer Handling)
        if (invoiceToSave.installerName != null && invoiceToSave.installerName!.isNotEmpty) {
          // التحقق من وجود الفني
          final List<Map<String, dynamic>> installers = await txn.query(
            'installers',
            where: 'name = ?',
            whereArgs: [invoiceToSave.installerName],
          );
          
          if (installers.isEmpty) {
            await txn.insert('installers', {
              'name': invoiceToSave.installerName,
              'total_billed_amount': 0.0,
            });
          }
          
          // تحديث مجاميع الفني
          // خصم المبلغ القديم (إذا كان تعديل)
          if (isUpdate && oldInvoice != null && oldInvoice.installerName != null) {
             await _updateInstallerTotal(txn, oldInvoice.installerName, -oldInvoice.totalAmount);
          }
          // إضافة المبلغ الجديد
          await _updateInstallerTotal(txn, invoiceToSave.installerName, invoiceToSave.totalAmount);
        } else if (isUpdate && oldInvoice != null && oldInvoice.installerName != null) {
          // إذا تم حذف الفني من الفاتورة، نخصم المبلغ من الفني القديم
          await _updateInstallerTotal(txn, oldInvoice.installerName, -oldInvoice.totalAmount);
        }

        // 3. حفظ الفاتورة (Invoice Saving)
        int invoiceId;
        if (isUpdate) {
          invoiceId = invoiceToSave.id!;
          await txn.update(
            'invoices', 
            invoiceToSave.toMap(), 
            where: 'id = ?', 
            whereArgs: [invoiceId]
          );
          
          // حذف العناصر القديمة
          await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
        } else {
          invoiceId = await txn.insert('invoices', invoiceToSave.toMap());
          invoiceToSave = invoiceToSave.copyWith(id: invoiceId);
        }

        // 4. حفظ العناصر (Items Saving)
        for (var item in items) {
          var itemMap = item.toMap();
          itemMap['invoice_id'] = invoiceId;
          itemMap.remove('id'); // لتوليد معرف جديد
          await txn.insert('invoice_items', itemMap);
        }
        
        // تحديث final_total
        await txn.rawUpdate('UPDATE invoices SET final_total = total_amount WHERE id = ?', [invoiceId]);

        // 5. معالجة الديون والمعاملات (Debt & Transactions)
        // يتم تطبيق الديون فقط إذا كانت الفاتورة "محفوظة" وليست "معلقة" أو "مسودة"
        bool shouldApplyDebt = invoiceToSave.status == 'محفوظة';
        
        if (customer != null && shouldApplyDebt) {
          double oldDebtContribution = 0.0;
          double newDebtContribution = 0.0;
          
          // حساب المساهمة القديمة في الدين
          // فقط إذا كانت الفاتورة القديمة أيضاً "محفوظة" (ليست معلقة سابقاً)
          // إذا كانت معلقة سابقاً، فهي لم تساهم في الدين، لذا oldDebtContribution = 0
          bool oldWasApplied = false;
          if (isUpdate && oldInvoice != null) {
             // نفترض أن الفواتير القديمة المحفوظة فقط هي التي أثرت في الدين
             // (يمكن التحقق من status القديم إذا كان متوفراً، أو نفترض ذلك بناءً على وجود معاملة)
             // للسلامة، نتحقق من status القديم
             if (oldInvoice.status == 'محفوظة' && oldInvoice.paymentType == 'دين') {
               oldDebtContribution = MoneyCalculator.subtract(oldInvoice.totalAmount, oldInvoice.amountPaidOnInvoice);
               oldWasApplied = true;
             }
          }
          
          // حساب المساهمة الجديدة في الدين
          if (invoiceToSave.paymentType == 'دين') {
            newDebtContribution = MoneyCalculator.subtract(invoiceToSave.totalAmount, invoiceToSave.amountPaidOnInvoice);
          }
          
          final double debtChange = MoneyCalculator.subtract(newDebtContribution, oldDebtContribution);
          
          if (debtChange.abs() > 0.001) { // استخدام هامش صغير لمشاكل الـ double
            // تحديث رصيد العميل
            final currentCustomerData = await txn.query('customers', where: 'id = ?', whereArgs: [customer.id]);
            if (currentCustomerData.isNotEmpty) {
               double currentDebt = (currentCustomerData.first['current_total_debt'] as num).toDouble();
               double newTotalDebt = MoneyCalculator.add(currentDebt, debtChange);

               
               await txn.update(
                 'customers', 
                 {
                   'current_total_debt': newTotalDebt,
                   'last_modified_at': DateTime.now().toIso8601String(),
                 },
                 where: 'id = ?',
                 whereArgs: [customer.id]
               );
               
               // معالجة سجل المعاملات (Transactions)
               if (isUpdate && oldWasApplied) {
                 // محاولة العثور على المعاملة المرتبطة بهذه الفاتورة
                 final existingTx = await txn.query(
                   'transactions',
                   where: 'invoice_id = ? AND transaction_type = ?',
                   whereArgs: [invoiceId, 'invoice_debt'],
                 );
                 
                 if (existingTx.isNotEmpty) {
                   if (newDebtContribution > 0) {
                     // تحديث المعاملة الموجودة
                     await txn.update(
                       'transactions',
                       {
                         'amount_changed': newDebtContribution,
                         'new_balance_after_transaction': newTotalDebt, 
                       },
                       where: 'id = ?',
                       whereArgs: [existingTx.first['id']]
                     );
                   } else {
                     // إذا لم يعد هناك دين (تحولت لنقد)، نحذف المعاملة
                     await txn.delete('transactions', where: 'id = ?', whereArgs: [existingTx.first['id']]);
                   }
                 } else if (newDebtContribution > 0) {
                   // إنشاء معاملة جديدة (ربما كانت نقد وأصبحت دين)
                   await txn.insert('transactions', {
                      'customer_id': customer.id,
                      'transaction_date': invoiceToSave.invoiceDate.toIso8601String(),
                      'amount_changed': newDebtContribution,
                      'new_balance_after_transaction': newTotalDebt,
                      'transaction_note': 'دين فاتورة رقم $invoiceId',
                      'transaction_type': 'invoice_debt',
                      'description': 'فاتورة مبيعات (تعديل)',
                      'created_at': DateTime.now().toIso8601String(),
                      'invoice_id': invoiceId,
                   });
                 }
               } else {
                 // فاتورة جديدة أو كانت معلقة وأصبحت محفوظة
                 if (newDebtContribution > 0) {
                   await txn.insert('transactions', {
                      'customer_id': customer.id,
                      'transaction_date': invoiceToSave.invoiceDate.toIso8601String(),
                      'amount_changed': newDebtContribution,
                      'new_balance_after_transaction': newTotalDebt,
                      'transaction_note': 'دين فاتورة رقم $invoiceId',
                      'transaction_type': 'invoice_debt',
                      'description': 'فاتورة مبيعات',
                      'created_at': DateTime.now().toIso8601String(),
                      'invoice_id': invoiceId,
                   });
                 }
               }
            }
          }
        }

        // 6. سجل التدقيق (Audit Log)
        if (isUpdate && oldInvoice != null) {
          await txn.insert('invoice_logs', {
            'invoice_id': invoiceId,
            'action': 'updated_transactional',
            'details': 'تم التحديث بنجاح عبر المعاملات الآمنة',
            'created_at': DateTime.now().toIso8601String(),
            'created_by': createdBy,
          });
        } else {
          await txn.insert('invoice_logs', {
            'invoice_id': invoiceId,
            'action': 'created_transactional',
            'details': 'تم الإنشاء بنجاح عبر المعاملات الآمنة',
            'created_at': DateTime.now().toIso8601String(),
            'created_by': createdBy,
          });
        }

        // إرجاع الفاتورة المحفوظة
        final savedInvoiceMaps = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
        return Invoice.fromMap(savedInvoiceMaps.first);
        
      } catch (e) {
        print('Transaction Error: $e');
        throw e; // سيقوم الترانزاكشن بإلغاء كل التغييرات تلقائياً
      }
    });
  }


  // --- Adjustments (Settlements) ---
  Future<int> insertInvoiceAdjustment(InvoiceAdjustment adjustment) async {
    final db = await database;
    try {
      final id = await db.insert('invoice_adjustments', adjustment.toMap());
      // Apply financial effects
      await applyInvoiceAdjustment(adjustment.invoiceId);
      // تأثير التسوية على سجل الديون حسب نوع التسوية وطريقة الدفع المختارة
      try {
        final invoice = await getInvoiceById(adjustment.invoiceId);
        if (invoice != null && invoice.customerId != null) {
          final String paymentKind = (adjustment.settlementPaymentType ?? 'دين');
          // تحديد تأثير الدين: إذا كانت 'دين' نطبق، إذا 'نقد' لا نؤثر على الدين
          if (paymentKind == 'دين') {
            // delta للدين: تسوية إضافة (debit) ترفع الدين، تسوية حذف (credit) تخفض الدين
            final double debtDelta = adjustment.amountDelta;
            if (debtDelta != 0) {
              await db.transaction((txn) async {
                final customer = await getCustomerByIdUsingTransaction(txn, invoice.customerId!);
                if (customer != null) {
                  final double currentDebt = customer.currentTotalDebt;
                  double intendedNewDebt = MoneyCalculator.add(currentDebt, debtDelta);
                  double appliedDelta = debtDelta;
                  double refundCash = 0.0;
                  // لا نسمح بأن يصبح الدين سالباً؛ الفائض يُعاد نقداً
                  if (intendedNewDebt < 0) {
                    refundCash = -intendedNewDebt; // مقدار النقد الواجب إرجاعه
                    appliedDelta = -currentDebt;   // خفض الدين حتى الصفر فقط
                    intendedNewDebt = 0.0;
                  }
                  await txn.update('customers', {
                    'current_total_debt': intendedNewDebt,
                    'last_modified_at': DateTime.now().toIso8601String(),
                  }, where: 'id = ?', whereArgs: [customer.id]);
                  await txn.insert('transactions', {
                    'customer_id': customer.id,
                    'transaction_date': DateTime.now().toIso8601String(),
                    'amount_changed': appliedDelta,
                    'new_balance_after_transaction': intendedNewDebt,
                    'transaction_note': ((adjustment.type == 'debit' ? 'تسوية إضافة' : 'تسوية حذف') + ' مرتبطة بالفاتورة رقم ${invoice.id}' + (refundCash > 0 ? ' | استرجاع نقدي للعميل: ' + refundCash.toStringAsFixed(0) : '')),
                    'transaction_type': 'SETTLEMENT',
                    'description': 'Invoice settlement adjustment',
                    'created_at': DateTime.now().toIso8601String(),
                    'invoice_id': invoice.id,
                  });
                }
              });
            }
          }
        }
      } catch (e) {
        print('WARN: failed to apply settlement debt effect: $e');
      }
      return id;
    } catch (e) {
      // معالجة غياب عمود settlement_payment_type القديمة ثم إعادة المحاولة
      final es = e.toString();
      if (es.contains('no column named settlement_payment_type') || es.contains('has no column named settlement_payment_type')) {
        try {
          await db.execute('ALTER TABLE invoice_adjustments ADD COLUMN settlement_payment_type TEXT;');
          final id = await db.insert('invoice_adjustments', adjustment.toMap());
          // Apply financial effects
          await applyInvoiceAdjustment(adjustment.invoiceId);
          try {
            final invoice = await getInvoiceById(adjustment.invoiceId);
            if (invoice != null && invoice.customerId != null) {
              final String paymentKind = (adjustment.settlementPaymentType ?? 'دين');
              if (paymentKind == 'دين') {
                final double debtDelta = adjustment.amountDelta;
                if (debtDelta != 0) {
                  await db.transaction((txn) async {
                    final customer = await getCustomerByIdUsingTransaction(txn, invoice.customerId!);
                    if (customer != null) {
                      final double currentDebt = customer.currentTotalDebt;
                      double intendedNewDebt = MoneyCalculator.add(currentDebt, debtDelta);
                      double appliedDelta = debtDelta;
                      double refundCash = 0.0;
                      if (intendedNewDebt < 0) {
                        refundCash = -intendedNewDebt;
                        appliedDelta = -currentDebt;
                        intendedNewDebt = 0.0;
                      }
                      await txn.update('customers', {
                        'current_total_debt': intendedNewDebt,
                        'last_modified_at': DateTime.now().toIso8601String(),
                      }, where: 'id = ?', whereArgs: [customer.id]);
                      await txn.insert('transactions', {
                        'customer_id': customer.id,
                        'transaction_date': DateTime.now().toIso8601String(),
                        'amount_changed': appliedDelta,
                        'new_balance_after_transaction': intendedNewDebt,
                        'transaction_note': ((adjustment.type == 'debit' ? 'تسوية إضافة' : 'تسوية حذف') + ' مرتبطة بالفاتورة رقم ${invoice.id}' + (refundCash > 0 ? ' | استرجاع نقدي للعميل: ' + refundCash.toStringAsFixed(0) : '')),
                        'transaction_type': 'SETTLEMENT',
                        'description': 'Invoice settlement adjustment',
                        'created_at': DateTime.now().toIso8601String(),
                        'invoice_id': invoice.id,
                      });
                    }
                  });
                }
              }
            }
          } catch (e2) {
            print('WARN: failed to apply settlement debt effect after adding column: $e2');
          }
          return id;
        } catch (_) {}
      }
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<List<InvoiceAdjustment>> getInvoiceAdjustments(int invoiceId) async {
    final db = await database;
    final maps = await db.query('invoice_adjustments', where: 'invoice_id = ?', whereArgs: [invoiceId], orderBy: 'created_at ASC, id ASC');
    return maps.map((m) => InvoiceAdjustment.fromMap(m)).toList();
  }

  Future<void> applyInvoiceAdjustment(int invoiceId) async {
    final db = await database;
    await db.transaction((txn) async {
      // Recalculate sum of adjustments
      final sumRows = await txn.rawQuery('SELECT COALESCE(SUM(amount_delta),0) AS s FROM invoice_adjustments WHERE invoice_id = ?', [invoiceId]);
      final double sumAdj = ((sumRows.first['s'] as num?) ?? 0).toDouble();

      // Get invoice
      final invoice = await getInvoiceByIdUsingTransaction(txn, invoiceId);
      if (invoice == null) return;

      // Update final_total = total_amount + sum(adjustments)
      final double newFinal = MoneyCalculator.add(invoice.totalAmount, sumAdj);
      await txn.update('invoices', {'final_total': newFinal, 'last_modified_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [invoiceId]);
      // NOTE: لا نقوم بتعديل دين العميل أو إنشاء حركة هنا.
      // يتم ذلك حصراً داخل insertInvoiceAdjustment وفق طريقة دفع التسوية.

      // Update installer billed amount by delta as well
      if (invoice.installerName != null && invoice.installerName!.isNotEmpty) {
        final lastAdjRows = await txn.rawQuery('SELECT amount_delta FROM invoice_adjustments WHERE invoice_id = ? ORDER BY created_at DESC, id DESC LIMIT 1', [invoiceId]);
        final double lastDelta = lastAdjRows.isNotEmpty ? ((lastAdjRows.first['amount_delta'] as num).toDouble()) : 0.0;
        if (lastDelta != 0) {
          await _updateInstallerTotal(txn, invoice.installerName, lastDelta);
        }
      }

      // Audit log
      try {
        await txn.insert('invoice_logs', {
          'invoice_id': invoiceId,
          'action': 'adjusted',
          'details': '{"delta": $sumAdj}',
          'created_at': DateTime.now().toIso8601String(),
          'created_by': null,
        });
      } catch (_) {}
    });
  }

  Future<int> updateInvoice(Invoice invoice) async {
    final db = await database;

    // Get the old invoice to calculate debt changes
    final oldInvoice = await getInvoiceById(invoice.id!);
    if (oldInvoice == null) return 0;

    // Calculate total paid amount for the invoice
    final List<Map<String, dynamic>> paymentMaps = await db.query(
      'transactions',
      where: 'invoice_id = ?',
      whereArgs: [invoice.id!],
    );
    final totalPaid = paymentMaps.fold<double>(
        0, (sum, map) => sum + (map['amount_changed'] as num).toDouble());

    // Calculate old and new debt contributions
    // The debt contribution from an invoice is its total amount minus the total amount paid directly on it.
    // Note: The previous logic here seemed to calculate debt contribution based on total paid transactions,
    // but amount_paid_on_invoice field is specifically for direct payments on this invoice.
    // Let's use the new amountPaidOnInvoice field for debt calculation logic related to the customer.
    // We also need to consider if the paymentType changes from 'نقد' to 'دين' or vice versa.

    double oldDebtContribution = 0.0;
    if (oldInvoice.paymentType == 'دين') {
      oldDebtContribution =
          MoneyCalculator.subtract(oldInvoice.totalAmount, oldInvoice.amountPaidOnInvoice);
    }

    double newDebtContribution = 0.0;
    if (invoice.paymentType == 'دين') {
      newDebtContribution = MoneyCalculator.subtract(invoice.totalAmount, invoice.amountPaidOnInvoice);
    }

    // Calculate the change in debt
    final debtChange = MoneyCalculator.subtract(newDebtContribution, oldDebtContribution);

    // Note: Debt transaction handling is now done in create_invoice_screen.dart
    // to avoid duplicate transactions. This method only updates the invoice.

    // Update installer's total billed amount if installer name changed or total amount changed
    if (oldInvoice.installerName != invoice.installerName ||
        oldInvoice.totalAmount != invoice.totalAmount) {
      // Reverse the old installer's billed amount (if any)
      if (oldInvoice.installerName != null &&
          oldInvoice.installerName!.isNotEmpty) {
        await _updateInstallerTotal(
            db, oldInvoice.installerName!, -oldInvoice.totalAmount);
      }
      // Add the new installer's billed amount (if any)
      if (invoice.installerName != null && invoice.installerName!.isNotEmpty) {
        await _updateInstallerTotal(
            db, invoice.installerName!, invoice.totalAmount);
      }
    }

    try {
      final count = await db.update(
        'invoices',
        invoice.toMap(),
        where: 'id = ?',
        whereArgs: [invoice.id!],
      );
      try {
        await db.insert('invoice_logs', {
          'invoice_id': invoice.id,
          'action': 'updated',
          'details': null,
          'created_at': DateTime.now().toIso8601String(),
          'created_by': null,
        });
      } catch (_) {}
      return count;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<int> deleteInvoice(int id) async {
    final db = await database;

    // Get the invoice to calculate debt reversal and update installer total
    final invoice = await getInvoiceById(id);
    if (invoice == null) return 0;

    // Calculate remaining debt to reverse for the customer
    // This should be the debt amount associated with this specific invoice, not affected by other payments.
    double debtToReverse = 0.0;
    if (invoice.paymentType == 'دين') {
      // Find the transaction linked to this invoice that represents the initial debt
      final initialDebtTransaction = await getInvoiceDebtTransaction(id);
      if (initialDebtTransaction != null) {
        debtToReverse = initialDebtTransaction
            .amountChanged; // This is the positive debt amount recorded initially
      }
      // If there were partial payments recorded as separate transactions for this invoice,
      // those should have already updated the customer's total debt.
      // So, when deleting the invoice, we reverse the *initial* debt amount recorded.
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح: تحديث رصيد العميل عبر insertTransaction فقط (لتجنب التحديث المزدوج)
    // ═══════════════════════════════════════════════════════════════════════════
    // Update customer's debt if a customer is linked and there was initial debt from this invoice
    if (invoice.customerId != null && debtToReverse > 0) {
      final customer = await getCustomerById(
          invoice.customerId!); // Use the customerId from the invoice
      if (customer != null) {
        // 🔧 إصلاح: لا نقوم بتحديث العميل مباشرة لأن insertTransaction ستفعل ذلك
        // هذا يمنع التحديث المزدوج للرصيد
        
        // Record the debt reversal transaction (هذه الدالة تحدث رصيد العميل تلقائياً)
        await insertTransaction(
          DebtTransaction(
            id: null,
            customerId: customer.id!,
            invoiceId: id,
            amountChanged: -debtToReverse, // Negative to reverse the debt
            transactionDate: DateTime.now(),
            newBalanceAfterTransaction: 0, // سيتم حسابها تلقائياً في insertTransaction
            transactionNote: 'حذف الفاتورة رقم $id (عكس دين الفاتورة)',
            transactionType: 'Invoice_Debt_Reversal',
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    // Update installer's total billed amount (reverse the amount from this invoice)
    if (invoice.installerName != null && invoice.installerName!.isNotEmpty) {
      await _updateInstallerTotal(
          db, invoice.installerName!, -invoice.totalAmount);
    }

    try {
      // Log before deletion
      try {
        await db.insert('invoice_logs', {
          'invoice_id': id,
          'action': 'deleted',
          'details': null,
          'created_at': DateTime.now().toIso8601String(),
          'created_by': null,
        });
      } catch (_) {}

      // Delete all transactions associated with this invoice
      await db.delete(
        'transactions',
        where: 'invoice_id = ?',
        whereArgs: [id],
      );

      // Delete all invoice items associated with this invoice
      await db.delete(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [id],
      );

      // Delete the invoice
      return await db.delete(
        'invoices',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  // Lock/unlock helpers with audit logs
  Future<void> lockInvoice(int invoiceId, {String? createdBy}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('invoices', {
        'is_locked': 1,
        'status': 'محفوظة',
        'last_modified_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [invoiceId]);
      await txn.insert('invoice_logs', {
        'invoice_id': invoiceId,
        'action': 'locked',
        'details': null,
        'created_at': DateTime.now().toIso8601String(),
        'created_by': createdBy,
      });
    });
  }

  Future<void> unlockInvoice(int invoiceId, {String? createdBy}) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('invoices', {
        'is_locked': 0,
        'last_modified_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [invoiceId]);
      await txn.insert('invoice_logs', {
        'invoice_id': invoiceId,
        'action': 'unlocked',
        'details': null,
        'created_at': DateTime.now().toIso8601String(),
        'created_by': createdBy,
      });
    });
  }

  // New methods for Invoice Items
  Future<int> insertInvoiceItem(InvoiceItem item) async {
    final db = await database;
    try {
      final result = await db.insert('invoice_items', {
        'invoice_id': item.invoiceId,
        'product_name': item.productName,
        'unit': item.unit,
        'unit_price': item.unitPrice,
        'cost_price': item.costPrice,
        'actual_cost_price': item.actualCostPrice, // التكلفة الفعلية للمنتج في وقت البيع
        'quantity_individual': item.quantityIndividual,
        'quantity_large_unit': item.quantityLargeUnit,
        'applied_price': item.appliedPrice,
        'item_total': item.itemTotal,
        'sale_type': item.saleType,
        'units_in_large_unit': item.unitsInLargeUnit,
        'unique_id': item.uniqueId,
      });
      return result;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<int> updateInvoiceItem(InvoiceItem item) async {
    final db = await database;
    try {
      final result = await db.update(
        'invoice_items',
        {
          'product_name': item.productName,
          'unit': item.unit,
          'unit_price': item.unitPrice,
          'cost_price': item.costPrice,
          'actual_cost_price': item.actualCostPrice, // التكلفة الفعلية للمنتج في وقت البيع
          'quantity_individual': item.quantityIndividual,
          'quantity_large_unit': item.quantityLargeUnit,
          'applied_price': item.appliedPrice,
          'item_total': item.itemTotal,
          'sale_type': item.saleType,
          'units_in_large_unit': item.unitsInLargeUnit,
        },
        where: 'id = ?',
        whereArgs: [item.id],
      );
      return result;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<int> deleteInvoiceItem(int id) async {
    final db = await database;
    try {
      return await db.delete(
        'invoice_items',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// ضبط المساهمة الحالية لهذه الفاتورة في دين العميل بشكل مباشر (تعديل حي)
  /// newContribution هي قيمة الدين التي يجب أن تمثلها هذه الفاتورة حالياً.
  /// الدالة تحسب الفرق مع المساهمة الحالية (من جميع معاملات هذه الفاتورة ما عدا المدفوعات اليدوية)
  /// ثم تطبق هذا الفرق على رصيد العميل وتكتب معاملة واحدة بالفارق.
  Future<void> setInvoiceDebtContribution({
    required int invoiceId,
    required int customerId,
    required double newContribution,
    String? note,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // اجمع مساهمة الفاتورة الحالية من كل المعاملات المرتبطة بهذه الفاتورة باستثناء المدفوعات اليدوية
      // نستثني manual_payment لأنها تمثل تسديد خارجي لا يجب أن يُحتسب ضمن مساهمة الفاتورة نفسها
      final List<Map<String, Object?>> rows = await txn.query(
        'transactions',
        columns: ['amount_changed', 'transaction_type'],
        where: 'invoice_id = ? AND (transaction_type IS NULL OR transaction_type <> ?)',
        whereArgs: [invoiceId, 'manual_payment'],
      );
      double currentContribution = 0.0;
      for (final r in rows) {
        final num? v = r['amount_changed'] as num?;
        currentContribution += (v ?? 0).toDouble();
      }

      final double delta = MoneyCalculator.subtract(newContribution, currentContribution);
      const double eps = 1e-6;
      if (delta.abs() < eps) {
        return; // لا حاجة لتغيير
      }

      // حدّث رصيد العميل
      final customer = await getCustomerByIdUsingTransaction(txn, customerId);
      if (customer == null) return;
      final double newBalance = MoneyCalculator.add(customer.currentTotalDebt, delta);
      await txn.update(
        'customers',
        {
          'current_total_debt': newBalance,
          'last_modified_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [customerId],
      );

      // اكتب معاملة تمثل الفارق فقط
      await txn.insert('transactions', {
        'customer_id': customerId,
        'transaction_date': DateTime.now().toIso8601String(),
        'amount_changed': delta,
        'new_balance_after_transaction': newBalance,
        'transaction_note': note ?? 'تعديل حي لمساهمة الفاتورة',
        'transaction_type': 'invoice_live_update',
        'description': 'Live delta applied to match invoice contribution',
        'invoice_id': invoiceId,
        'created_at': DateTime.now().toIso8601String(),
        'audio_note_path': null,
      });
    });
  }

  // Method to get the initial debt transaction for an invoice
  Future<DebtTransaction?> getInvoiceDebtTransaction(int invoiceId) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'transactions',
        where: 'invoice_id = ? AND amount_changed > 0',
        whereArgs: [invoiceId],
        orderBy:
            'created_at ASC', // Get the earliest positive transaction linked to this invoice
        limit: 1,
      );
      if (maps.isNotEmpty) {
        return DebtTransaction.fromMap(maps.first);
      }
    } catch (e) {
      print(
          'Error getting invoice debt transaction for invoice $invoiceId: $e');
      // Do not throw here, return null if not found or error occurs
    }
    return null;
  }

  // دوال مساعدة للقراءة داخل معاملة (إذا كنت تستدعيها من داخل دوال أخرى تستخدم معاملة)
  Future<Invoice?> getInvoiceByIdUsingTransaction(
      DatabaseExecutor txn, int id) async {
    final List<Map<String, dynamic>> maps = await txn.query(
      'invoices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Invoice.fromMap(maps.first);
    }
    return null;
  }

  Future<Customer?> getCustomerByIdUsingTransaction(
      DatabaseExecutor txn, int id) async {
    final List<Map<String, dynamic>> maps = await txn.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Customer.fromMap(maps.first);
    }
    return null;
  }

  Future<List<InvoiceItem>> getInvoiceItemsUsingTransaction(
      DatabaseExecutor txn, int invoiceId) async {
    final List<Map<String, dynamic>> maps = await txn.query(
      'invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
    );
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔍 DEBUG: طباعة الأصناف المجلوبة من قاعدة البيانات
    // ═══════════════════════════════════════════════════════════════════════════
    print('═══════════════════════════════════════════════════════════════════');
    print('🔍 DEBUG DB READ: جلب أصناف الفاتورة رقم $invoiceId');
    print('🔍 DEBUG DB READ: عدد الأصناف في قاعدة البيانات: ${maps.length}');
    for (int i = 0; i < maps.length; i++) {
      final map = maps[i];
      print('🔍 DEBUG DB READ: صنف [$i]: ${map['product_name']}');
      print('   - id: ${map['id']}');
      print('   - quantity_individual: ${map['quantity_individual']}');
      print('   - quantity_large_unit: ${map['quantity_large_unit']}');
      print('   - applied_price: ${map['applied_price']}');
      print('   - item_total: ${map['item_total']}');
      print('   - sale_type: ${map['sale_type']}');
      print('   - unique_id: ${map['unique_id']}');
    }
    print('═══════════════════════════════════════════════════════════════════');
    
    return List.generate(maps.length, (i) => InvoiceItem.fromMap(maps[i]));
  }

  // --- دوال جلب الفواتير وبنودها (خارج المعاملات) ---
  Future<List<Invoice>> getAllInvoices(
      {String orderBy = 'invoice_date DESC, id DESC'}) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps =
          await db.query('invoices', orderBy: orderBy);
      return List.generate(maps.length, (i) => Invoice.fromMap(maps[i]));
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<Invoice?> getInvoiceById(int id) async {
    final db = await database;
    return await getInvoiceByIdUsingTransaction(
        db, id); //  يمكن إعادة استخدام دالة المعاملة
  }

  /// جلب آخر N أسعار لنفس العميل ولنفس المنتج من الفواتير "المحفوظة"
  /// تُستخدم لميزة تنبيه سجل الأسعار.
  /// تُعيد قائمة من الخرائط تحتوي: applied_price, invoice_date, sale_type
  Future<List<Map<String, dynamic>>> getLastNPricesForCustomerProduct({
    required String customerName,
    String? customerPhone,
    required String productName,
    int limit = 3,
    String? saleType,
  }) async {
    final db = await database;
    try {
      // نستخدم LEFT JOIN على customers للسماح بالفواتير التي لا تملك customer_id
      // المطابقة تتم بأحد مسارين:
      // 1) customer_id موجود: طابق على اسم ورقم هاتف العميل (إن وُجد الهاتف)
      // 2) customer_id غير موجود: طابق على اسم العميل النصي داخل الفاتورة
      final bool noPhone = customerPhone == null || customerPhone.trim().isEmpty;
      final String phoneParam = (customerPhone ?? '').trim();
      final String ignoreFlag = noPhone ? '1' : '0';
      final List<dynamic> args = [
        customerName.trim(),                // c.name = ?
        phoneParam,                         // ? = ''
        ignoreFlag,                         // ? = '1'
        phoneParam,                         // c.phone = ?
        customerName.trim(),                // i.customer_name = ? (عند عدم وجود customer_id)
        productName.trim(),                 // ii.product_name = ?
      ];
      String saleTypeFilter = '';
      if (saleType != null && saleType.trim().isNotEmpty) {
        saleTypeFilter = ' AND ii.sale_type = ? ';
        args.add(saleType.trim());
      }
      args.add(limit);

      final sql = '''
        SELECT 
          ii.applied_price AS applied_price,
          i.invoice_date AS invoice_date,
          ii.sale_type AS sale_type,
          i.id AS invoice_id
        FROM invoices i
        JOIN invoice_items ii ON ii.invoice_id = i.id
        LEFT JOIN customers c ON c.id = i.customer_id
        WHERE i.status = 'محفوظة'
          AND (
            (i.customer_id IS NOT NULL AND c.name = ? AND ( ? = '' OR ? = '1' OR c.phone = ?))
            OR (i.customer_id IS NULL AND i.customer_name = ?)
          )
          AND ii.product_name = ?
          $saleTypeFilter
        ORDER BY i.invoice_date DESC
        LIMIT ?
      ''';

      final rows = await db.rawQuery(sql, args);
      return rows;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<List<InvoiceItem>> getInvoiceItems(int invoiceId) async {
    final db = await database;
    return await getInvoiceItemsUsingTransaction(
        db, invoiceId); //  يمكن إعادة استخدام دالة المعاملة
  }

  // --- تقرير المبيعات الشهري ---
  Future<Map<String, MonthlyOverview>> getMonthlySalesSummary({DateTime? fromDate}) async {
    final db = await database;
    try {
      // إذا تم تمرير fromDate نُطبّق الفلترة، وإلا نجلب جميع الفواتير لحساب الجرد الشهري بشكل صحيح
      List<Map<String, dynamic>> invoiceMaps;
      if (fromDate != null) {
        invoiceMaps = await db.query(
        'invoices',
        where: 'invoice_date >= ?',
          whereArgs: [fromDate.toIso8601String()],
        orderBy: 'invoice_date DESC',
      );
      } else {
        invoiceMaps = await db.query(
          'invoices',
          orderBy: 'invoice_date DESC',
        );
      }
      //  تحويل جميع الخرائط إلى كائنات Invoice أولاً للتعامل مع التواريخ بشكل صحيح
      final List<Invoice> allInvoices =
          invoiceMaps.map((map) => Invoice.fromMap(map)).toList();

      final Map<String, List<Invoice>> invoicesByMonth = {};
      for (var invoice in allInvoices) {
        if (invoice.invoiceDate == null) {
          print(
              "فاتورة (ID: ${invoice.id}) بتاريخ فارغ، سيتم تجاهلها في الملخص الشهري.");
          continue;
        }
        //  invoiceDate يجب أن يكون DateTime هنا
        final monthYear =
            '${invoice.invoiceDate!.year}-${invoice.invoiceDate!.month.toString().padLeft(2, '0')}';

        invoicesByMonth.putIfAbsent(monthYear, () => []).add(invoice);
      }

      final Map<String, MonthlyOverview> monthlySummaries = {};

      for (var entry in invoicesByMonth.entries) {
        final monthYear = entry.key;
        final invoicesInMonth = entry.value;

        double totalSales = 0.0;
        double netProfit = 0.0;
        double totalCostSum = 0.0; // إجمالي التكلفة للشهر
        double cashSales = 0.0;
        double creditSalesValue = 0.0;
        double totalReturns = 0.0; // إجمالي الراجع
        double totalDebtPayments = 0.0; // إجمالي تسديد الديون
        double totalManualDebt = 0.0; // إضافة دين يدوية
        double settlementAdditions = 0.0; // تسوية الإضافة (مبلغ + ملاحظة)
        double settlementReturns = 0.0; // تسوية الإرجاع (مبلغ + ملاحظة)
        int invoiceCount = 0; // عدد الفواتير
        int manualDebtCount = 0; // عدد معاملات إضافة الدين
        int manualPaymentCount = 0; // عدد معاملات تسديد الدين

        for (var invoice in invoicesInMonth) {
          if (invoice.status == 'محفوظة') {
            totalSales += invoice.totalAmount;
            totalReturns += invoice.returnAmount ?? 0; // حساب إجمالي الراجع

            if (invoice.paymentType == 'نقد') {
              cashSales += invoice.totalAmount;
            } else if (invoice.paymentType == 'دين') {
              creditSalesValue += invoice.totalAmount;
            }

            // احسب تكلفة البنود في الفاتورة بمنطق مطابق لتقارير البضاعة عبر JOIN لضمان توافر بيانات المنتج
            // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط (مصاريف كهرباء/تشغيل)
            double totalCost = 0.0;
            final List<Map<String, dynamic>> itemRows = await db.rawQuery('''
              SELECT 
                ii.quantity_individual AS qi,
                ii.quantity_large_unit AS ql,
                ii.units_in_large_unit AS uilu,
                ii.cost_price AS item_cost_total,
                ii.actual_cost_price AS actual_cost_per_unit,
                ii.applied_price AS selling_price,
                ii.sale_type AS sale_type,
                p.unit AS product_unit,
                p.cost_price AS product_cost_price,
                p.length_per_unit AS length_per_unit,
                p.unit_costs AS unit_costs
              FROM invoice_items ii
              JOIN products p ON p.name = ii.product_name
              WHERE ii.invoice_id = ?
            ''', [invoice.id!]);

            for (final row in itemRows) {
              final double qi = (row['qi'] as num?)?.toDouble() ?? 0.0;
              final double ql = (row['ql'] as num?)?.toDouble() ?? 0.0;
              final double uilu = (row['uilu'] as num?)?.toDouble() ?? 0.0;
              final String saleType = (row['sale_type'] as String?) ?? '';
              final String productUnit = (row['product_unit'] as String?) ?? '';
              final double productCost = (row['product_cost_price'] as num?)?.toDouble() ?? 0.0;
              final double? lengthPerUnit = (row['length_per_unit'] as num?)?.toDouble();
              final double? actualCostPerUnit = (row['actual_cost_per_unit'] as num?)?.toDouble();
              final double sellingPrice = (row['selling_price'] as num?)?.toDouble() ?? 0.0;
              final String? unitCostsJson = row['unit_costs'] as String?;
              Map<String, dynamic> unitCosts = const {};
              if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
                try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
              }

              final bool soldAsLargeUnit = ql > 0;
              final double soldUnitsCount = soldAsLargeUnit ? ql : qi;

              // حساب التكلفة لكل وحدة مباعة
              double costPerSoldUnit;
              if (actualCostPerUnit != null && actualCostPerUnit > 0) {
                costPerSoldUnit = actualCostPerUnit;
              } else if (soldAsLargeUnit) {
                // أولاً: إن كانت تكلفة الوحدة الكبيرة مخزنة استخدمها مباشرة
                final dynamic stored = unitCosts[saleType];
                if (stored is num && stored > 0) {
                  costPerSoldUnit = stored.toDouble();
                } else {
                  final bool isMeterRoll = productUnit == 'meter' && lengthPerUnit != null && (saleType == 'لفة');
                  costPerSoldUnit = isMeterRoll
                      ? productCost * (lengthPerUnit ?? 1.0)
                      : productCost * uilu;
                }
              } else {
                costPerSoldUnit = productCost;
              }

              // 🔧 إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
              if (costPerSoldUnit <= 0 && sellingPrice > 0) {
                costPerSoldUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
              }

              totalCost += costPerSoldUnit * soldUnitsCount;
            }

            // صافي المبيعات بعد الراجع مطروحاً منه التكلفة الفعلية
            final netSaleAmount = MoneyCalculator.subtract(invoice.totalAmount, (invoice.returnAmount ?? 0));
            final profit = MoneyCalculator.subtract(netSaleAmount, totalCost);
            netProfit += profit;
            totalCostSum += totalCost; // تجميع التكلفة للشهر
            invoiceCount++; // عد الفواتير
          }
        }

        // نطاق هذا الشهر
        final year = int.parse(monthYear.split('-')[0]);
        final month = int.parse(monthYear.split('-')[1]);
        final String start =
            '$year-${month.toString().padLeft(2, '0')}-01T00:00:00.000';
        final String end = month == 12
            ? '${year + 1}-01-01T00:00:00.000'
            : '$year-${(month + 1).toString().padLeft(2, '0')}-01T00:00:00.000';

        // أضف الدين المبدئي والمعاملات اليدوية (إضافة دين) إلى البيع بالدين لهذا الشهر
        final List<Map<String, dynamic>> manualDebtTx = await db.query(
          'transactions',
          columns: ['amount_changed'],
          where:
              "(transaction_type = 'manual_debt' OR transaction_type = 'opening_balance') AND transaction_date >= ? AND transaction_date < ?",
          whereArgs: [start, end],
        );
        for (final tx in manualDebtTx) {
          final amount = (tx['amount_changed'] as num).toDouble();
          creditSalesValue += amount;
          totalManualDebt += amount; // تجميع إضافة الدين اليدوية
        }
        manualDebtCount = manualDebtTx.length; // عدد معاملات إضافة الدين
        
        // حساب ربح المعاملات اليدوية (15% من إضافة الدين اليدوية فقط - بدون الدين المبدئي)
        // الشرط: manual_debt فقط + غير مرتبطة بفاتورة (invoice_id IS NULL)
        double manualDebtProfitValue = 0.0;
        final List<Map<String, dynamic>> manualDebtOnlyTx = await db.query(
          'transactions',
          columns: ['amount_changed'],
          where:
              "transaction_type = 'manual_debt' AND invoice_id IS NULL AND transaction_date >= ? AND transaction_date < ?",
          whereArgs: [start, end],
        );
        for (final tx in manualDebtOnlyTx) {
          final amount = (tx['amount_changed'] as num).toDouble();
          manualDebtProfitValue += amount * 0.15; // 15% ربح
        }

        // جمع معاملات تسديد الديون لهذا الشهر (manual_payment)
        final List<Map<String, dynamic>> debtTxMaps = await db.query(
          'transactions',
          columns: ['amount_changed'],
          where:
              "transaction_type = 'manual_payment' AND transaction_date >= ? AND transaction_date < ?",
          whereArgs: [start, end],
        );
        for (final tx in debtTxMaps) {
          totalDebtPayments += (tx['amount_changed'] as num).toDouble().abs();
        }
        manualPaymentCount = debtTxMaps.length; // عدد معاملات تسديد الدين

        // جمع تسويات الشهر من جدول التسويات المرتبطة بالفواتير (مبلغ + ملاحظة فقط)
        try {
          final List<Map<String, Object?>> debitRows = await db.rawQuery(
            '''
              SELECT COALESCE(SUM(amount_delta), 0) AS s
              FROM invoice_adjustments
              WHERE type = 'debit'
                AND created_at >= ? AND created_at < ?
                AND (product_id IS NULL)
                AND (product_name IS NULL OR product_name = '')
                AND (quantity IS NULL)
                AND (price IS NULL)
            ''',
            [start, end],
          );
          final List<Map<String, Object?>> creditRows = await db.rawQuery(
            '''
              SELECT COALESCE(SUM(ABS(amount_delta)), 0) AS s
              FROM invoice_adjustments
              WHERE type = 'credit'
                AND created_at >= ? AND created_at < ?
                AND (product_id IS NULL)
                AND (product_name IS NULL OR product_name = '')
                AND (quantity IS NULL)
                AND (price IS NULL)
            ''' ,
            [start, end],
          );
          settlementAdditions = ((debitRows.first['s'] as num?) ?? 0).toDouble();
          settlementReturns = ((creditRows.first['s'] as num?) ?? 0).toDouble();
        } catch (_) {}

        // دمج تسويات البنود (ذات product_id) في إجمالي المبيعات وصافي الأرباح لهذا الشهر وفق الهرمية
        try {
          final List<Map<String, Object?>> adjRows = await db.rawQuery(
            '''
              SELECT ia.type, ia.quantity, ia.price, ia.sale_type, ia.units_in_large_unit,
                     p.unit AS product_unit, p.cost_price AS product_cost, p.length_per_unit AS length_per_unit
              FROM invoice_adjustments ia
              JOIN products p ON p.id = ia.product_id
              WHERE ia.product_id IS NOT NULL
                AND ia.created_at >= ? AND ia.created_at < ?
            ''',
            [start, end],
          );

          double addSalesFromAdj = 0.0;
          double addProfitFromAdj = 0.0;
          for (final r in adjRows) {
            final String type = (r['type'] as String?) ?? 'debit';
            final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
            final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
            final String saleType = (r['sale_type'] as String?) ?? ((r['product_unit'] as String?) == 'meter' ? 'متر' : 'قطعة');
            final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;
            final String productUnit = (r['product_unit'] as String?) ?? 'piece';
            final double baseCost = ((r['product_cost'] as num?)?.toDouble()) ?? 0.0;
            final double? lengthPerUnit = (r['length_per_unit'] as num?)?.toDouble();
            if (qtySaleUnits == 0) continue;

            final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;

            double baseQty;
            if (productUnit == 'meter' && saleType == 'لفة') {
              final double factor = (unitsInLargeUnit > 0) ? unitsInLargeUnit : (lengthPerUnit ?? 1.0);
              baseQty = qtySaleUnits * factor;
            } else if (saleType == 'قطعة' || saleType == 'متر') {
              baseQty = qtySaleUnits;
            } else {
              baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
            }
            final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;
            final double costContribution = baseCost * (signedBaseQty);

            addSalesFromAdj += salesContribution;
            addProfitFromAdj += (salesContribution - costContribution);
          }

          totalSales += addSalesFromAdj;
          netProfit += addProfitFromAdj;
        } catch (_) {}

        monthlySummaries[monthYear] = MonthlyOverview(
          monthYear: monthYear,
          totalSales: totalSales,
          netProfit: netProfit,
          totalCost: totalCostSum, // إجمالي التكلفة
          cashSales: cashSales,
          creditSales: creditSalesValue,
          totalReturns: totalReturns, // إضافة إجمالي الراجع
          totalDebtPayments: totalDebtPayments, // إضافة إجمالي تسديد الديون
          totalManualDebt: totalManualDebt, // إضافة دين يدوية
          manualDebtProfit: manualDebtProfitValue, // ربح المعاملات اليدوية (15%)
          settlementAdditions: settlementAdditions,
          settlementReturns: settlementReturns,
          invoiceCount: invoiceCount, // عدد الفواتير
          manualDebtCount: manualDebtCount, // عدد معاملات إضافة الدين
          manualPaymentCount: manualPaymentCount, // عدد معاملات تسديد الدين
        );
      }
      //  فرز الملخصات حسب الشهر تنازليًا
      var sortedEntries = monthlySummaries.entries.toList()
        ..sort((a, b) => b.key.compareTo(a.key));

      return Map.fromEntries(sortedEntries);
    } catch (e) {
      print("Error in getMonthlySalesSummary: $e");
      throw Exception(_handleDatabaseError(e));
    }
  }

  // Implement missing methods
  Future<List<Customer>> getCustomersModifiedToday() async {
    final db = await database;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'last_modified_at >= ? AND current_total_debt > 0',
      whereArgs: [startOfDay.toIso8601String()],
    );

    return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
  }

  /// دالة البحث العادية (للحفاظ على التوافق مع باقي التطبيق)
  Future<List<Product>> searchProducts(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'products',
        where: 'name LIKE ?',
        whereArgs: ['%$query%'],
        orderBy: 'name ASC',
        limit: 50,
      );
      return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
    } catch (e) {
      print('Error in regular search: $e');
      return [];
    }
  }

  /// دالة البحث الذكية المتعددة الطبقات - مخصصة لشاشة إنشاء الفاتورة
  Future<List<Product>> searchProductsSmart(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final db = await database;
    final normalizedQuery = normalizeArabic(query);
    
    try {
      // الطبقة 1: FTS5 للبحث السريع والدقيق
      final ftsResults = await _searchWithFTS(db, normalizedQuery);
      
      // الطبقة 2: LIKE subsequence للبحث عن الكلمات في ترتيب مختلف
      final likeResults = await _searchWithLike(db, normalizedQuery);
      
      // دمج النتائج وإزالة المكررات
      final allResults = <Product>[];
      final seenIds = <int>{};
      
      // إضافة نتائج FTS5 أولاً (أعلى أولوية)
      for (final product in ftsResults) {
        if (seenIds.add(product.id!)) {
          allResults.add(product);
        }
      }
      
      // إضافة نتائج LIKE (أقل أولوية)
      for (final product in likeResults) {
        if (seenIds.add(product.id!)) {
          allResults.add(product);
        }
      }
      
      // ترتيب النتائج حسب الأولوية
      return allResults.take(50).toList();
      
    } catch (e) {
      print('Error in smart search: $e');
      // Fallback إلى البحث العادي
      return await _fallbackSearch(db, query);
    }
  }

  /// البحث باستخدام FTS5
  Future<List<Product>> _searchWithFTS(Database db, String normalizedQuery) async {
    try {
      // تقسيم الاستعلام إلى كلمات
      final terms = normalizedQuery.split(' ').where((t) => t.isNotEmpty).toList();
      if (terms.isEmpty) return [];
      
      // تنظيف الكلمات من الأحرف الخاصة التي تسبب مشاكل في FTS5
      final cleanedTerms = terms.map((term) {
        // إزالة علامات الاقتباس والأحرف الخاصة
        return term.replaceAll(RegExp(r'''['"*()[\]{}]'''), '');
      }).where((t) => t.isNotEmpty).toList();
      
      if (cleanedTerms.isEmpty) return [];
      
      // إنشاء استعلام FTS5 - البحث عن أي من الكلمات
      final ftsQuery = cleanedTerms.map((term) => '$term*').join(' OR ');
      
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT p.*, bm25(products_fts) AS rank_score
        FROM products_fts
        JOIN products p ON p.id = products_fts.rowid
        WHERE products_fts MATCH ?
        ORDER BY rank_score ASC
        LIMIT 30
      ''', [ftsQuery]);
      
      return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
    } catch (e) {
      print('FTS search error: $e');
      return [];
    }
  }

  /// البحث باستخدام LIKE subsequence
  Future<List<Product>> _searchWithLike(Database db, String normalizedQuery) async {
    try {
      final terms = normalizedQuery.split(' ').where((t) => t.isNotEmpty).toList();
      if (terms.isEmpty) return [];
      
      // نمط subsequence: "كوب ... فنار" مع كلمات بينهما
      final subsequencePattern = '%${terms.join('%')}%';
      
      // البحث عن الكلمات في أي ترتيب
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT p.*, 
          CASE 
            WHEN p.name_norm LIKE ? THEN 100
            WHEN p.name_norm LIKE ? THEN 80
            ELSE 60
          END AS relevance_score
        FROM products p
        WHERE p.name_norm LIKE ? OR p.name_norm LIKE ?
        ORDER BY relevance_score DESC, p.name_norm ASC
        LIMIT 30
      ''', [
        normalizedQuery,           // تطابق كامل
        '$normalizedQuery%',       // يبدأ بالكلمة
        subsequencePattern,        // subsequence
        '%$normalizedQuery%',      // يحتوي على الكلمة
      ]);
      
      return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
    } catch (e) {
      print('LIKE search error: $e');
      return [];
    }
  }

  /// البحث العادي كـ fallback
  Future<List<Product>> _fallbackSearch(Database db, String query) async {
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'products',
        where: 'name LIKE ?',
        whereArgs: ['%$query%'],
        orderBy: 'name ASC',
        limit: 20,
      );
      return List.generate(maps.length, (i) => Product.fromMap(maps[i]));
    } catch (e) {
      print('Fallback search error: $e');
      return [];
    }
  }

  Future<Product?> getProductById(int productId) async {
    final db = await database;
    try {
      final maps = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
      if (maps.isEmpty) return null;
      return Product.fromMap(maps.first);
    } catch (e) {
      print('Error getting product by ID $productId: $e');
      return null;
    }
  }

  Future<List<Product>> searchProductsByIdPrefix(String prefix, {int limit = 8}) async {
    final db = await database;
    try {
      final maps = await db.rawQuery(
        'SELECT * FROM products WHERE CAST(id AS TEXT) LIKE ? ORDER BY id LIMIT ?;',
        ['${prefix.replaceAll('%', '')}%', limit],
      );
      return maps.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      print('Error searching products by ID prefix $prefix: $e');
      return [];
    }
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    try {
      // تطبيع اسم المنتج وحفظه في العمود المطبع
      final productMap = product.toMap();
      productMap['name_norm'] = normalizeArabic(product.name);
      // إعادة احتساب تكاليف الوحدات تلقائياً عند تغيير تكلفة الوحدة الأساسية
      try {
        if (product.costPrice != null && product.costPrice! > 0) {
          final Map<String, dynamic> newUnitCosts = {};
          // المنتجات المباعة بالقطعة: ابنِ التكاليف عبر التسلسل الهرمي
          if (product.unit == 'piece') {
            double currentCost = product.costPrice!; // تكلفة القطعة
            newUnitCosts['قطعة'] = currentCost;
            if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
              try {
                final List<dynamic> hierarchy = jsonDecode(product.unitHierarchy!.replaceAll("'", '"')) as List<dynamic>;
                for (final level in hierarchy) {
                  final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                  final double qty = (level['quantity'] is num)
                      ? (level['quantity'] as num).toDouble()
                      : double.tryParse(level['quantity'].toString()) ?? 1.0;
                  currentCost = currentCost * qty; // تراكمي
                  if (unitName.isNotEmpty) {
                    newUnitCosts[unitName] = currentCost;
                  }
                }
              } catch (_) {}
            }
          } else if (product.unit == 'meter') {
            // المنتجات المباعة بالمتر: متر و/أو لفة
            newUnitCosts['متر'] = product.costPrice!;
            if (product.lengthPerUnit != null && product.lengthPerUnit! > 0) {
              newUnitCosts['لفة'] = product.costPrice! * product.lengthPerUnit!;
            }
          } else {
            // أي وحدات أخرى: احتفظ بتكلفة الوحدة كما هي كبداية
            newUnitCosts[product.unit] = product.costPrice!;
          }
          productMap['unit_costs'] = jsonEncode(newUnitCosts);
        }
      } catch (e) {
        // لا تعطل التحديث إذا فشل بناء التكاليف لأي سبب
        print('WARN: Failed to recalculate unit_costs: $e');
      }
      
      return await db.update(
        'products',
        productMap,
        where: 'id = ?',
        whereArgs: [product.id!],
      );
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// إصلاح تكاليف الوحدات للمنتجات ذات النظام الهرمي/المتر استناداً إلى تكلفة الأساس الحالية
  Future<int> repairHierarchicalUnitCosts() async {
    final db = await database;
    int updated = 0;
    try {
      final List<Map<String, dynamic>> rows = await db.rawQuery('''
        SELECT id, name, unit, cost_price, unit_hierarchy, length_per_unit
        FROM products
        WHERE (unit_hierarchy IS NOT NULL AND TRIM(unit_hierarchy) <> '')
           OR (unit = 'meter' AND length_per_unit IS NOT NULL AND length_per_unit > 0)
      ''');

      for (final r in rows) {
        final int id = r['id'] as int;
        final String unit = (r['unit'] as String?) ?? 'piece';
        final double baseCost = ((r['cost_price'] as num?)?.toDouble() ?? 0.0);
        final String? unitHierarchy = r['unit_hierarchy'] as String?;
        final double? lengthPerUnit = (r['length_per_unit'] as num?)?.toDouble();

        if (baseCost <= 0) continue;

        final Map<String, dynamic> newUnitCosts = {};
        if (unit == 'piece') {
          double currentCost = baseCost;
          newUnitCosts['قطعة'] = currentCost;
          if (unitHierarchy != null && unitHierarchy.trim().isNotEmpty) {
            try {
              final List<dynamic> hierarchy = jsonDecode(unitHierarchy.replaceAll("'", '"')) as List<dynamic>;
              for (final level in hierarchy) {
                final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
                final double qty = (level['quantity'] is num)
                    ? (level['quantity'] as num).toDouble()
                    : double.tryParse(level['quantity'].toString()) ?? 1.0;
                currentCost = currentCost * qty;
                if (unitName.isNotEmpty) {
                  newUnitCosts[unitName] = currentCost;
                }
              }
            } catch (_) {}
          }
        } else if (unit == 'meter') {
          newUnitCosts['متر'] = baseCost;
          if (lengthPerUnit != null && lengthPerUnit > 0) {
            newUnitCosts['لفة'] = baseCost * lengthPerUnit;
          }
        } else {
          newUnitCosts[unit] = baseCost;
        }

        try {
          await db.update('products', {'unit_costs': jsonEncode(newUnitCosts), 'last_modified_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
          updated++;
        } catch (e) {
          print('Repair unit_costs failed for product #$id: $e');
        }
      }
    } catch (e) {
      print('repairHierarchicalUnitCosts error: $e');
    }
    return updated;
  }

  /// دالة لإعادة بناء فهرس FTS5
  Future<void> rebuildFTSIndex() async {
    final db = await database;
    try {
      await db.execute("INSERT INTO products_fts(products_fts) VALUES('rebuild');");
      print('FTS5 index rebuilt successfully');
    } catch (e) {
      print('Error rebuilding FTS index: $e');
    }
  }

  /// دالة للتحقق من حالة FTS5
  Future<void> checkFTSStatus() async {
    final db = await database;
    try {
      // التحقق من وجود جدول FTS5
      final ftsTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='products_fts'"
      );
      
      if (ftsTable.isEmpty) {
        print('FTS5 table does not exist');
        return;
      }
      
      // التحقق من عدد السجلات
      final productCount = await db.rawQuery('SELECT COUNT(*) FROM products');
      final ftsCount = await db.rawQuery('SELECT COUNT(*) FROM products_fts');
      
      print('Products: ${productCount.first.values.first}');
      print('FTS entries: ${ftsCount.first.values.first}');
      
      // اختبار بحث بسيط
      final testResult = await db.rawQuery(
        'SELECT * FROM products_fts WHERE products_fts MATCH ? LIMIT 5',
        ['بلك*']
      );
      
      print('Test search results: ${testResult.length}');
      
    } catch (e) {
      print('Error checking FTS status: $e');
    }
  }

  /// دالة لتهيئة العمود المطبع وFTS5 للمنتجات الموجودة
  Future<void> initializeFTSForExistingProducts() async {
    final db = await database;
    try {
      await db.transaction((txn) async {
        // التحقق من وجود عمود name_norm
        final columns = await txn.rawQuery("PRAGMA table_info(products);");
        final hasNameNorm = columns.any((col) => col['name'] == 'name_norm');
        
        if (!hasNameNorm) {
          print('إضافة عمود name_norm إلى جدول المنتجات...');
          await txn.execute('ALTER TABLE products ADD COLUMN name_norm TEXT;');
        }

        // تحديث name_norm لجميع المنتجات الموجودة
        final products = await txn.query('products');
        if (products.isNotEmpty) {
          print('تحديث name_norm لـ ${products.length} منتج موجود...');
          
          for (final product in products) {
            final normalizedName = normalizeArabic(product['name'] as String);
            await txn.update(
              'products',
              {'name_norm': normalizedName},
              where: 'id = ?',
              whereArgs: [product['id']],
            );
          }
          print('تم تحديث جميع المنتجات بأسماء مطبعة');
        }

        // إعادة إنشاء جدول FTS5 من الصفر
        try {
          await txn.execute('DROP TABLE IF EXISTS products_fts;');
        } catch (e) {
          print('خطأ أثناء حذف جدول FTS القديم: $e');
        }

        print('إنشاء جدول FTS5 جديد...');
        await txn.execute('''
          CREATE VIRTUAL TABLE products_fts USING fts5(
            name_norm,
            content='products',
            content_rowid='id',
            tokenize = 'unicode61 remove_diacritics 2'
          )
        ''');

        // إعادة إدراج جميع المنتجات في FTS5
        if (products.isNotEmpty) {
          print('إدراج ${products.length} منتج في فهرس FTS...');
          
          for (final product in products) {
            final normalizedName = product['name_norm'] ?? normalizeArabic(product['name'] as String);
            await txn.execute(
              'INSERT INTO products_fts(rowid, name_norm) VALUES (?, ?)',
              [product['id'], normalizedName]
            );
          }
          
          print('تم تهيئة FTS5 بـ ${products.length} منتج');
        }
      });

      // التحقق من نجاح التهيئة باستعلام صالح (معطل افتراضياً)
      if (_verboseLogs) {
        try {
          final sanity = await db.rawQuery(
            'SELECT count(1) as c FROM products_fts WHERE products_fts MATCH ? LIMIT 1',
            ['بلك*']
          );
          final c = (sanity.isNotEmpty ? sanity.first.values.first : 0) ?? 0;
          print('اختبار البحث FTS (sanity): $c نتيجة');
        } catch (e) {
          print('FTS sanity check failed: $e');
        }
      }

    } catch (e) {
      print('خطأ أثناء تهيئة FTS للمنتجات الموجودة: $e');
      // محاولة إعادة بناء الفهرس في حالة الفشل
      try {
        await rebuildFTSIndex();
      } catch (rebuildError) {
        print('فشل إعادة بناء فهرس FTS: $rebuildError');
      }
    }
  }

  /// دالة اختبار للبحث الذكي
  Future<void> testSmartSearch() async {
    if (!_verboseLogs) return; // تعطيل الاختبارات والطباعات في الإصدار النهائي
    print('=== اختبار البحث الذكي ===');
    
    try {
      // اختبار 1: البحث عن "كوب فنار"
      print('\n1. البحث عن "كوب فنار":');
      final results1 = await searchProductsSmart("كوب فنار");
      print('نتائج البحث: ${results1.length}');
      for (var product in results1) {
        print('- ${product.name} (مطبع: ${product.name})');
      }

      // اختبار 2: البحث عن "كوب"
      print('\n2. البحث عن "كوب":');
      final results2 = await searchProductsSmart("كوب");
      print('نتائج البحث: ${results2.length}');
      for (var product in results2.take(5)) {
        print('- ${product.name}');
      }

      // اختبار 3: البحث عن "فنار"
      print('\n3. البحث عن "فنار":');
      final results3 = await searchProductsSmart("فنار");
      print('نتائج البحث: ${results3.length}');
      for (var product in results3.take(5)) {
        print('- ${product.name}');
      }

      // اختبار 4: البحث عن "كوب واحد"
      print('\n4. البحث عن "كوب واحد":');
      final results4 = await searchProductsSmart("كوب واحد");
      print('نتائج البحث: ${results4.length}');
      for (var product in results4) {
        print('- ${product.name}');
      }

    } catch (e) {
      print('خطأ في اختبار البحث الذكي: $e');
    }
    
    print('=== نهاية الاختبار ===');
  }

  Future<Installer?> getInstallerByName(String name) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'installers',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Installer.fromMap(maps.first);
  }

  Future<List<Installer>> searchInstallers(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'installers',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
    );
    return List.generate(maps.length, (i) => Installer.fromMap(maps[i]));
  }

  Future<List<Invoice>> getInvoicesByInstaller(String installerName) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'invoices',
      where: 'installer_name = ?',
      whereArgs: [installerName],
      orderBy: 'invoice_date DESC', // ترتيب من الأحدث إلى الأقدم
    );
    return List.generate(maps.length, (i) => Invoice.fromMap(maps[i]));
  }

  Future<List<Customer>> getCustomersForMonth(int year, int month) async {
    final db = await database;
    final String monthStr = month.toString().padLeft(2, '0');
    final String start = '$year-$monthStr-01T00:00:00.000';
    final String end = month == 12
        ? '${year + 1}-01-01T00:00:00.000'
        : '$year-${(month + 1).toString().padLeft(2, '0')}-01T00:00:00.000';
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where:
          '((last_modified_at >= ? AND last_modified_at < ?) OR (created_at >= ? AND created_at < ?)) AND current_total_debt > 0',
      whereArgs: [start, end, start, end],
    );
    return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
  }

  Future<File> generateMonthlyDebtsPdf(
      List<Customer> customers, int year, int month) async {
    final font = pw.Font.ttf(
        (await rootBundle.load('assets/fonts/Amiri-Regular.ttf'))
            .buffer
            .asByteData());
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        textDirection: pw.TextDirection.rtl,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text('سجل ديون شهر $year-$month',
                style: pw.TextStyle(font: font, fontSize: 24)),
            pw.SizedBox(height: 16),
            pw.Table.fromTextArray(
              headers: ['المبلغ', 'العنوان', 'الاسم'],
              data: customers
                  .map((c) => [
                        c.currentTotalDebt.toStringAsFixed(2),
                        c.address ?? '',
                        c.name
                      ])
                  .toList(),
              headerStyle: pw.TextStyle(
                  font: font, fontWeight: pw.FontWeight.bold, fontSize: 14),
              cellStyle: pw.TextStyle(font: font, fontSize: 12),
              cellAlignment: pw.Alignment.centerRight,
              columnWidths: {
                2: pw.FlexColumnWidth(
                    2.5), // الاسم يأخذ المساحة الأكبر (آخر عمود)
                1: pw.FlexColumnWidth(1.5), // العنوان وسط
                0: pw.FlexColumnWidth(1), // المبلغ يسار (أول عمود)
              },
            ),
          ],
        ),
      ),
    );
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/سجل_ديون_${year}_$month.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  Future<List<Customer>> getLateCustomers(int months) async {
    final db = await database;
    final now = DateTime.now();
    final threshold = DateTime(now.year, now.month - months, now.day);
    final List<Map<String, dynamic>> maps = await db.query(
      'customers',
      where: 'current_total_debt > 0 AND last_modified_at < ?',
      whereArgs: [threshold.toIso8601String()],
    );
    return List.generate(maps.length, (i) => Customer.fromMap(maps[i]));
  }

  // --- دوال معاملات الدين ---
  Future<int> insertDebtTransaction(DebtTransaction transaction) async {
    final db = await database;
    return await db.insert('transactions', transaction.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<DebtTransaction>> getTransactionsToUpload() async {
    final db = await database;
    final maps = await db.query(
      'transactions',
      where: '(is_created_by_me = 1) AND (is_uploaded = 0 OR is_uploaded IS NULL)',
      orderBy: 'transaction_date ASC, id ASC',
    );
    return maps.map((m) => DebtTransaction.fromMap(m)).toList();
  }

  /// جلب المعاملات حسب الفترة والنوع مع اسم العميل
  /// [transactionTypes] قائمة أنواع المعاملات مثل ['manual_debt', 'opening_balance'] أو ['manual_payment']
  /// [startDate] و [endDate] نطاق التاريخ
  Future<List<Map<String, dynamic>>> getTransactionsWithCustomerName({
    required List<String> transactionTypes,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await database;
    try {
      final startStr = startDate.toIso8601String();
      final endStr = endDate.toIso8601String();
      
      // بناء شرط الأنواع
      final typePlaceholders = transactionTypes.map((_) => '?').join(', ');
      
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          t.id,
          t.customer_id,
          t.transaction_date,
          t.amount_changed,
          t.balance_before_transaction,
          t.new_balance_after_transaction,
          t.transaction_note,
          t.transaction_type,
          t.description,
          c.name as customer_name,
          c.phone as customer_phone
        FROM transactions t
        LEFT JOIN customers c ON t.customer_id = c.id
        WHERE t.transaction_type IN ($typePlaceholders)
          AND t.transaction_date >= ?
          AND t.transaction_date < ?
        ORDER BY t.transaction_date DESC
      ''', [...transactionTypes, startStr, endStr]);
      
      return maps;
    } catch (e) {
      print('Error in getTransactionsWithCustomerName: $e');
      return [];
    }
  }

  Future<void> markTransactionsUploaded(List<String> transactionUuids) async {
    if (transactionUuids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(transactionUuids.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE transactions SET is_uploaded = 1 WHERE transaction_uuid IN ($placeholders)',
      transactionUuids,
    );
  }

  /// إدراج معاملة خارجية (من المزامنة) وتطبيقها على رصيد العميل
  /// ✅ تم تحسين: التحقق من UUID قبل الإدراج لمنع التكرار
  Future<void> insertExternalTransactionAndApply({
    required int customerId,
    required double amount,
    required String type,
    String? note,
    String? description,
    String? transactionUuid,
    DateTime? occurredAt,
  }) async {
    final db = await database;
    
    // ✅ التحقق من وجود المعاملة مسبقاً بناءً على UUID
    if (transactionUuid != null && transactionUuid.isNotEmpty) {
      final existing = await db.query(
        'transactions',
        where: 'transaction_uuid = ?',
        whereArgs: [transactionUuid],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        print('SYNC: تجاهل معاملة مكررة UUID=$transactionUuid');
        return; // المعاملة موجودة مسبقاً، لا نضيفها مرة أخرى
      }
    }
    
    await db.transaction((txn) async {
      final customer = await getCustomerByIdUsingTransaction(txn, customerId);
      if (customer == null) throw Exception('العميل غير موجود');
      
      // حساب الرصيد قبل وبعد المعاملة
      final double balanceBefore = customer.currentTotalDebt;
      final double newBalance = MoneyCalculator.add(balanceBefore, amount);
      
      // تحديث رصيد العميل
      await txn.update('customers', {
        'current_total_debt': newBalance,
        'last_modified_at': DateTime.now().toIso8601String(),
      }, where: 'id = ?', whereArgs: [customer.id]);
      
      // إدراج المعاملة مع الأرصدة الصحيحة
      await txn.insert('transactions', {
        'customer_id': customer.id,
        'transaction_date': (occurredAt ?? DateTime.now()).toIso8601String(),
        'amount_changed': amount,
        'balance_before_transaction': balanceBefore,
        'new_balance_after_transaction': newBalance,
        'transaction_note': note,
        'transaction_type': type,
        'description': description,
        'created_at': DateTime.now().toIso8601String(),
        'audio_note_path': null,
        'is_created_by_me': 0,
        'is_uploaded': 0,
        'transaction_uuid': transactionUuid,
      });
      
      print('✅ SYNC: تم إدراج معاملة خارجية للعميل $customerId، المبلغ: $amount، الرصيد الجديد: $newBalance');
    });
  }

  Future<void> setTransactionUuidById(int transactionId, String uuid) async {
    final db = await database;
    await db.update('transactions', {
      'transaction_uuid': uuid,
    }, where: 'id = ?', whereArgs: [transactionId]);
  }

  Future<List<DebtTransaction>> getDebtTransactionsForCustomer(
      int customerId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'transaction_date DESC',
    );
    return List.generate(maps.length, (i) => DebtTransaction.fromMap(maps[i]));
  }

  Future<DebtTransaction?> getDebtTransactionById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return DebtTransaction.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateDebtTransaction(DebtTransaction transaction) async {
    final db = await database;
    return await db.update(
      'transactions',
      transaction.toMap(),
      where: 'id = ?',
      whereArgs: [transaction.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> deleteDebtTransaction(int id) async {
    final db = await database;
    return await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // دالة لجلب آخر id للفواتير
  Future<int> getLastInvoiceId() async {
    final db = await database;
    final result = await db.rawQuery('SELECT MAX(id) as maxId FROM invoices');
    if (result.isNotEmpty && result.first['maxId'] != null) {
      return result.first['maxId'] as int;
    }
    return 0;
  }

  Future<int> updateInstaller(Installer installer) async {
    final db = await database;
    return await db.update(
      'installers',
      installer.toMap(),
      where: 'id = ?',
      whereArgs: [installer.id],
    );
  }

  /// دالة لإعادة حساب وتحديث إجمالي المبلغ المفوتر لكل المؤسسين من الفواتير
  Future<void> recalculateAllInstallersBilledAmount() async {
    final db = await database;
    // جلب جميع المؤسسين
    final installersMaps = await db.query('installers');
    for (final installerMap in installersMaps) {
      final installer = Installer.fromMap(installerMap);
      // جلب جميع الفواتير المرتبطة بهذا المؤسس
      final invoicesMaps = await db.query(
        'invoices',
        where: 'installer_name = ?',
        whereArgs: [installer.name],
      );
      double total = 0.0;
      for (final invoiceMap in invoicesMaps) {
        final invoice = Invoice.fromMap(invoiceMap);
        // إذا كانت الفاتورة مقفلة (راجع محفوظ)، اطرح قيمة الراجع
        if (invoice.isLocked) {
          total += (invoice.totalAmount - invoice.returnAmount);
        } else {
          total += invoice.totalAmount;
        }
      }
      final updatedInstaller = installer.copyWith(totalBilledAmount: total);
      await updateInstaller(updatedInstaller);
    }
  }

  // البحث عن عميل بالاسم بعد التطبيع (إزالة المسافات)
  Future<Customer?> findCustomerByNormalizedName(String name,
      {String? phone}) async {
    final db = await database;
    final normalizedName = name.replaceAll(' ', '');
    List<Map<String, dynamic>> maps;
    if (phone != null && phone.trim().isNotEmpty) {
      maps = await db.rawQuery(
        "SELECT * FROM customers WHERE REPLACE(name, ' ', '') = ? AND phone = ? LIMIT 1",
        [normalizedName, phone.trim()],
      );
    } else {
      maps = await db.rawQuery(
        "SELECT * FROM customers WHERE REPLACE(name, ' ', '') = ? LIMIT 1",
        [normalizedName],
      );
    }
    if (maps.isNotEmpty) {
      return Customer.fromMap(maps.first);
    }
    return null;
  }

  // --- دوال نظام التقارير ---

    // دوال تقارير البضاعة
  Future<Map<String, dynamic>> getProductSalesData(int productId) async {
    final db = await database;
    try {
      // جلب جميع الفواتير المحفوظة التي تحتوي على هذا المنتج مع بيانات المنتج الكاملة
      final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
        SELECT 
          ii.quantity_individual,
          ii.quantity_large_unit,
          ii.units_in_large_unit,
          ii.applied_price,
          ii.cost_price,
          ii.actual_cost_price,
          ii.item_total,
          ii.sale_type,
          p.cost_price as product_cost_price,
          p.unit_hierarchy,
          p.unit_costs,
          p.unit,
          p.length_per_unit
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
        JOIN products p ON ii.product_name = p.name
        WHERE p.id = ? AND i.status = 'محفوظة'
      ''', [productId]);
 
      double totalQuantity = 0.0; // بوحدة الأساس (قطعة/متر)
      double totalProfit = 0.0;
      double totalSales = 0.0;
      double averageSellingPrice = 0.0; // سيتم قسمة مجموع المبيعات على مجموع الكمية الأساسية
      double totalCost = 0.0;
 
      for (final item in itemMaps) {
        final double quantityIndividual =
            (item['quantity_individual'] ?? 0.0) as double;
        final double quantityLargeUnit =
            (item['quantity_large_unit'] ?? 0.0) as double;
        final double unitsInLargeUnit =
            (item['units_in_large_unit'] ?? 1.0) as double;

        // 1) احسب إجمالي الكمية بوحدة الأساس (قطعة/متر)
        double currentItemTotalQuantity = 0.0;
        if (quantityLargeUnit > 0) {
          currentItemTotalQuantity = quantityLargeUnit * unitsInLargeUnit;
        } else {
          currentItemTotalQuantity = quantityIndividual;
        }

        totalQuantity += currentItemTotalQuantity;

        // 2) استخدم إجمالي المبيعات المحفوظ للبند
        final double itemSales = (item['item_total'] ?? 0.0) as double;

        // 3) احسب التكلفة بإتباع نفس منطق السنة/الشهر
        final double? actualCostPrice = item['actual_cost_price'] as double?; // قد تكون تكلفة للوحدة المباعة
        final double baseCostPrice = (item['cost_price'] ?? item['product_cost_price'] ?? 0.0) as double; // تكلفة للوحدة الأساسية غالبًا
        final double appliedPrice = (item['applied_price'] ?? 0.0) as double; // سعر البيع للوحدة

        double itemCostTotal = 0.0;
        if (quantityLargeUnit > 0) {
          // بيع بوحدة كبيرة
          double costPerLargeUnit = actualCostPrice != null && actualCostPrice > 0
              ? actualCostPrice
              : baseCostPrice * unitsInLargeUnit;
          // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
          if (costPerLargeUnit <= 0 && appliedPrice > 0) {
            costPerLargeUnit = MoneyCalculator.getEffectiveCost(0, appliedPrice);
          }
          itemCostTotal = costPerLargeUnit * quantityLargeUnit;
        } else {
          // بيع بالوحدة الأساسية
          double costPerUnit = actualCostPrice != null && actualCostPrice > 0
              ? actualCostPrice
              : baseCostPrice;
          // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
          if (costPerUnit <= 0 && appliedPrice > 0) {
            costPerUnit = MoneyCalculator.getEffectiveCost(0, appliedPrice);
          }
          itemCostTotal = costPerUnit * quantityIndividual;
        }

        totalSales += itemSales;
        totalCost += itemCostTotal;
        totalProfit = MoneyCalculator.add(totalProfit, MoneyCalculator.subtract(itemSales, itemCostTotal));

        // 4) للمعدل لكل وحدة أساس: مجموع المبيعات ÷ مجموع الكمية الأساسية
        averageSellingPrice += itemSales; // سيقسم لاحقاً على totalQuantity
      }
 
      // حساب متوسط سعر البيع
      if (totalQuantity > 0) {
        averageSellingPrice = averageSellingPrice / totalQuantity;
      }
 
      // دمج تسويات البنود (debit/credit) لهذا المنتج عبر جدول invoice_adjustments مع احترام الهرمية
      try {
        final prodRows = await db.rawQuery('SELECT unit, cost_price, length_per_unit FROM products WHERE id = ?', [productId]);
        String productUnit = 'piece';
        double baseCost = 0.0;
        double? lengthPerUnit;
        if (prodRows.isNotEmpty) {
          productUnit = (prodRows.first['unit'] as String?) ?? 'piece';
          baseCost = ((prodRows.first['cost_price'] as num?)?.toDouble() ?? 0.0);
          lengthPerUnit = (prodRows.first['length_per_unit'] as num?)?.toDouble();
        }

        final rows = await db.rawQuery('''
          SELECT type, quantity, price, sale_type, units_in_large_unit
          FROM invoice_adjustments
          WHERE product_id = ?
        ''', [productId]);

        for (final r in rows) {
          final String type = (r['type'] as String?) ?? 'debit';
          final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
          final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
          final String saleType = (r['sale_type'] as String?) ?? (productUnit == 'meter' ? 'متر' : 'قطعة');
          final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;

          if (qtySaleUnits == 0) continue;

          // المبيعات لهذا السطر (إشارة حسب النوع)
          final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;

          // تحويل الكمية إلى وحدة الأساس
          double baseQty;
          if (productUnit == 'meter' && saleType == 'لفة') {
            final double factor = (unitsInLargeUnit > 0)
                ? unitsInLargeUnit
                : (lengthPerUnit ?? 1.0);
            baseQty = qtySaleUnits * factor;
          } else if (saleType == 'قطعة' || saleType == 'متر') {
            baseQty = qtySaleUnits;
          } else {
            baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
          }
          final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;

          // التكلفة = تكلفة وحدة الأساس × الكمية بوحدة الأساس
          final double costContribution = baseCost * (signedBaseQty);

          totalSales += salesContribution;
          totalQuantity += signedBaseQty;
          totalCost += costContribution.abs();
          totalProfit = MoneyCalculator.add(totalProfit, MoneyCalculator.subtract(salesContribution, costContribution));
        }

        if (totalQuantity > 0) {
          averageSellingPrice = totalSales / totalQuantity;
        }
      } catch (_) {}

      return {
        'totalQuantity': totalQuantity,
        'totalProfit': totalProfit,
        'totalSales': totalSales,
        'averageSellingPrice': averageSellingPrice,
        'totalCost': totalCost,
        'profitMargin': totalSales > 0 ? (totalProfit / totalSales) * 100 : 0.0,
      };
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<Map<int, double>> getProductYearlySales(int productId) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          strftime('%Y', i.invoice_date) as year,
          SUM(CASE 
                WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                  THEN ii.quantity_large_unit
                ELSE COALESCE(ii.quantity_individual, 0.0)
              END) as total_quantity
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
        JOIN products p ON ii.product_name = p.name
        WHERE p.id = ? AND i.status = 'محفوظة'
        GROUP BY strftime('%Y', i.invoice_date)
        ORDER BY year DESC
      ''', [productId]);

      final Map<int, double> yearlySales = {};
      for (final map in maps) {
        final year = int.parse(map['year'] as String);
        final quantity = (map['total_quantity'] ?? 0.0) as double;
        yearlySales[year] = quantity;
      }

      // دمج تسويات البنود سنوياً
      try {
        final rows = await db.rawQuery('''
          SELECT strftime('%Y', created_at) as year,
                 COALESCE(SUM(CASE WHEN type='debit' THEN quantity ELSE -quantity END),0) AS qty
          FROM invoice_adjustments
          WHERE product_id = ?
          GROUP BY strftime('%Y', created_at)
        ''', [productId]);
        for (final r in rows) {
          final int year = int.parse((r['year'] as String));
          final double qty = ((r['qty'] as num?) ?? 0).toDouble();
          yearlySales[year] = (yearlySales[year] ?? 0) + qty;
        }
      } catch (_) {}

      return yearlySales;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<Map<int, double>> getProductMonthlySales(
      int productId, int year) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          strftime('%m', i.invoice_date) as month,
          SUM(CASE 
                WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                  THEN ii.quantity_large_unit * COALESCE(ii.units_in_large_unit, 1.0)
                ELSE COALESCE(ii.quantity_individual, 0.0)
              END) as total_quantity
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
        JOIN products p ON ii.product_name = p.name
        WHERE p.id = ? AND strftime('%Y', i.invoice_date) = ? AND i.status = 'محفوظة'
        GROUP BY strftime('%m', i.invoice_date)
        ORDER BY month ASC
      ''', [productId, year.toString()]);

      final Map<int, double> monthlySales = {};
      for (final map in maps) {
        final month = int.parse(map['month'] as String);
        final quantity = (map['total_quantity'] ?? 0.0) as double;
        monthlySales[month] = quantity;
      }

      // دمج تسويات البنود شهرياً
      try {
        final rows = await db.rawQuery('''
          SELECT strftime('%m', created_at) as month,
                 COALESCE(SUM(CASE WHEN type='debit' THEN quantity ELSE -quantity END),0) AS qty
          FROM invoice_adjustments
          WHERE product_id = ? AND strftime('%Y', created_at) = ?
          GROUP BY strftime('%m', created_at)
        ''', [productId, year.toString()]);
        for (final r in rows) {
          final int month = int.parse((r['month'] as String));
          final double qty = ((r['qty'] as num?) ?? 0).toDouble();
          monthlySales[month] = (monthlySales[month] ?? 0) + qty;
        }
      } catch (_) {}

      return monthlySales;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<List<InvoiceWithProductData>> getProductInvoicesForMonth(
      int productId, int year, int month) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT DISTINCT i.*
        FROM invoices i
        JOIN invoice_items ii ON i.id = ii.invoice_id
        JOIN products p ON ii.product_name = p.name
        WHERE p.id = ? 
          AND strftime('%Y', i.invoice_date) = ?
          AND strftime('%m', i.invoice_date) = ?
        ORDER BY i.invoice_date DESC
      ''', [productId, year.toString(), month.toString().padLeft(2, '0')]);

      final List<InvoiceWithProductData> invoices = [];
      for (final map in maps) {
        final invoice = Invoice.fromMap(map);
        // سنحتاج لتجميع البنود لكل فاتورة لحساب متوسطات صحيحة
        // اجلب كل البنود الخاصة بهذه الفاتورة وهذا المنتج
        final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
          SELECT 
            ii.quantity_individual,
            ii.quantity_large_unit,
            ii.units_in_large_unit,
            ii.applied_price,
            ii.cost_price,
            ii.actual_cost_price,
            p.cost_price as product_cost_price
          FROM invoice_items ii
          JOIN products p ON ii.product_name = p.name
          WHERE ii.invoice_id = ? AND p.id = ?
        ''', [invoice.id, productId]);

        double totalQuantity = 0.0; // بوحدة الأساس
        double saleUnitsCount = 0.0; // بعدد وحدات البيع (قطعة أو باكيت/لفة)
        double totalSelling = 0.0;
        double totalCost = 0.0;

        for (final item in itemMaps) {
          final double quantityIndividual =
              (item['quantity_individual'] ?? 0.0) as double;
          final double quantityLargeUnit =
              (item['quantity_large_unit'] ?? 0.0) as double;
          final double unitsInLargeUnit =
              (item['units_in_large_unit'] ?? 1.0) as double;
          final double currentItemTotalQuantity = quantityLargeUnit > 0
              ? (quantityLargeUnit * unitsInLargeUnit)
              : quantityIndividual;
          final double sellingPrice = (item['applied_price'] ?? 0.0) as double;
          final double? actualCostPrice = item['actual_cost_price'] as double?; // قد تكون تكلفة للوحدة المباعة
          final double baseCostPrice = (item['cost_price'] ?? 
                                        item['product_cost_price'] ?? 0.0) as double; // تكلفة للوحدة الأساسية في الغالب
          
          // إضافة الكمية الإجمالية (بالوحدات الأساسية) للمعرض
          totalQuantity += currentItemTotalQuantity;
          saleUnitsCount += quantityLargeUnit > 0
              ? quantityLargeUnit
              : quantityIndividual;
          
          // حساب المبيعات والتكلفة مع مراعاة الوحدات الكبيرة (لفة/كرتون ...)
          if (quantityLargeUnit > 0) {
            // البيع بوحدة كبيرة: actual_cost_price إن وُجد فهو تكلفة للوحدة الكبيرة بالفعل
            double costPerLargeUnit = actualCostPrice != null && actualCostPrice > 0
                ? actualCostPrice
                : baseCostPrice * unitsInLargeUnit;
            // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
            if (costPerLargeUnit <= 0 && sellingPrice > 0) {
              costPerLargeUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
            }
            totalSelling += sellingPrice * quantityLargeUnit;
            totalCost += costPerLargeUnit * quantityLargeUnit;
          } else {
            // البيع بالوحدة الأساسية
            double costPerUnit = actualCostPrice != null && actualCostPrice > 0
                ? actualCostPrice
                : baseCostPrice;
            // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
            if (costPerUnit <= 0 && sellingPrice > 0) {
              costPerUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
            }
            totalSelling += sellingPrice * quantityIndividual;
            totalCost += costPerUnit * quantityIndividual;
          }
        }

        final double avgSellingPrice =
            totalQuantity > 0 ? (totalSelling / totalQuantity) : 0.0;
        final double avgUnitCost =
            totalQuantity > 0 ? (totalCost / totalQuantity) : 0.0;
        final double profit = MoneyCalculator.subtract(totalSelling, totalCost);

        invoices.add(InvoiceWithProductData(
          invoice: invoice,
          quantitySold: totalQuantity,
          saleUnitsCount: saleUnitsCount,
          profit: profit,
          sellingPrice: avgSellingPrice,
          unitCostAtSale: avgUnitCost,
        ));
      }

      return invoices;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  // دالة لتحديث الفواتير القديمة وربطها بالعملاء
  Future<void> updateOldInvoicesWithCustomerIds() async {
    final db = await database;
    try {
      if (_verboseLogs) print('🔄 بدء تحديث الفواتير القديمة...');
      
      // جلب جميع الفواتير التي لا تحتوي على customer_id
      final List<Map<String, dynamic>> invoicesWithoutCustomerId = await db.rawQuery('''
        SELECT id, customer_name, customer_phone, customer_address
        FROM invoices 
        WHERE customer_id IS NULL AND status = 'محفوظة'
        ORDER BY created_at ASC
      ''');
      
      print('📊 عدد الفواتير القديمة: ${invoicesWithoutCustomerId.length}');
      
      int updatedCount = 0;
      
      for (final invoice in invoicesWithoutCustomerId) {
        final int invoiceId = invoice['id'] as int;
        final String customerName = invoice['customer_name'] as String;
        final String? customerPhone = invoice['customer_phone'] as String?;
        final String? customerAddress = invoice['customer_address'] as String?;
        
        print('🔍 البحث عن عميل للفاتورة $invoiceId: $customerName');
        
        // البحث عن العميل بالاسم والهاتف
        Customer? customer;
        
        if (customerPhone != null && customerPhone.trim().isNotEmpty) {
          // البحث بالاسم والهاتف
          customer = await findCustomerByNormalizedName(
            customerName.trim(),
            phone: customerPhone.trim(),
          );
        }
        
        if (customer == null) {
          // البحث بالاسم فقط
          customer = await findCustomerByNormalizedName(customerName.trim());
        }
        
        if (customer != null && customer.id != null) {
          // تحديث الفاتورة بربطها بالعميل
          await db.update(
            'invoices',
            {'customer_id': customer.id},
            where: 'id = ?',
            whereArgs: [invoiceId],
          );
          
          print('✅ تم ربط الفاتورة $invoiceId بالعميل ${customer.name} (ID: ${customer.id})');
          updatedCount++;
        } else {
          print('❌ لم يتم العثور على عميل للفاتورة $invoiceId: $customerName');
        }
      }
      
      print('🎉 تم تحديث $updatedCount فاتورة من أصل ${invoicesWithoutCustomerId.length}');
      
    } catch (e) {
      print('❌ خطأ في تحديث الفواتير القديمة: $e');
      throw Exception('فشل في تحديث الفواتير القديمة: $e');
    }
  }

  // دوال تقارير الأشخاص
  Future<Map<String, dynamic>> getCustomerProfitData(int customerId) async {
    final db = await database;
    try {
      // جلب بيانات الفواتير (المحفوظة فقط) - تشمل الفواتير القديمة والجديدة
      final List<Map<String, dynamic>> invoiceMaps = await db.rawQuery('''
        SELECT 
          SUM(total_amount) as total_sales,
          COUNT(*) as total_invoices
        FROM invoices
        WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
          SELECT name FROM customers WHERE id = ?
        ))) AND status = 'محفوظة'
      ''', [customerId, customerId]);
 
      // جلب بيانات المعاملات المالية
      final List<Map<String, dynamic>> transactionMaps = await db.rawQuery('''
        SELECT 
          COUNT(*) as total_transactions
        FROM transactions
        WHERE customer_id = ?
      ''', [customerId]);
 
      // حساب الأرباح من الفواتير (المحفوظة فقط) وبمعادلة كمية مصححة
      // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط من سعر البيع
      final List<Map<String, dynamic>> profitMaps = await db.rawQuery('''
        SELECT 
          SUM(
            CASE 
              WHEN COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0) > 0 
              THEN (ii.applied_price - COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0))
              ELSE ii.applied_price * 0.10
            END * 
            (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                  THEN ii.quantity_large_unit
                  ELSE COALESCE(ii.quantity_individual, 0.0) END)
          ) as total_profit,
          SUM(ii.applied_price * (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE COALESCE(ii.quantity_individual, 0.0) END)) as total_selling_price,
          SUM(CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE COALESCE(ii.quantity_individual, 0.0) END) as total_quantity
        FROM invoices i
        JOIN invoice_items ii ON i.id = ii.invoice_id
        JOIN products p ON ii.product_name = p.name
        WHERE (i.customer_id = ? OR (i.customer_id IS NULL AND i.customer_name = (
          SELECT name FROM customers WHERE id = ?
        ))) AND i.status = 'محفوظة'
      ''', [customerId, customerId]);
 
      final totalSales = (invoiceMaps.first['total_sales'] ?? 0.0) as double;
      final totalInvoices = (invoiceMaps.first['total_invoices'] ?? 0) as int;
      final totalTransactions =
          (transactionMaps.first['total_transactions'] ?? 0) as int;
      final totalProfit = (profitMaps.first['total_profit'] ?? 0.0) as double;
      final totalSellingPrice = (profitMaps.first['total_selling_price'] ?? 0.0) as double;
      final totalQuantity = (profitMaps.first['total_quantity'] ?? 0.0) as double;
      
      // حساب متوسط سعر البيع
      double averageSellingPrice = 0.0;
      if (totalQuantity > 0) {
        averageSellingPrice = totalSellingPrice / totalQuantity;
      }

      // استخدم متغيرات قابلة للتعديل عند دمج التسويات
      double adjTotalSales = totalSales;
      double adjTotalProfit = totalProfit;
      double adjTotalQuantity = totalQuantity;
      double adjAverageSellingPrice = averageSellingPrice;
 
      // دمج تسويات البنود الخاصة بهذا العميل في إجمالياته (اعتماداً على الفواتير المرتبطة به)
      // 🔧 إصلاح: تضمين الفواتير القديمة التي ليس لها customer_id (بالاسم)
      try {
        final List<Map<String, dynamic>> invIds = await db.rawQuery('''
          SELECT id FROM invoices 
          WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
            SELECT name FROM customers WHERE id = ?
          ))) AND status = 'محفوظة'
        ''', [customerId, customerId]);
        if (invIds.isNotEmpty) {
          final ids = invIds.map((e) => (e['id'] as int)).toList();
          final placeholders = List.filled(ids.length, '?').join(',');
          final List<Map<String, Object?>> rows = await db.rawQuery('''
            SELECT ia.type, ia.quantity, ia.price, ia.sale_type, ia.units_in_large_unit,
                   p.unit AS product_unit, p.cost_price AS product_cost, p.length_per_unit AS length_per_unit
            FROM invoice_adjustments ia
            JOIN invoices i ON i.id = ia.invoice_id
            LEFT JOIN products p ON p.id = ia.product_id
            WHERE ia.product_id IS NOT NULL AND ia.invoice_id IN ($placeholders)
          ''', ids);
          double addSales = 0.0;
          double addProfit = 0.0;
          double addBaseQty = 0.0;
          for (final r in rows) {
            final String type = (r['type'] as String?) ?? 'debit';
            final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
            final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
            final String saleType = (r['sale_type'] as String?) ?? ((r['product_unit'] as String?) == 'meter' ? 'متر' : 'قطعة');
            final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;
            final String productUnit = (r['product_unit'] as String?) ?? 'piece';
            final double baseCost = ((r['product_cost'] as num?)?.toDouble()) ?? 0.0;
            final double? lengthPerUnit = (r['length_per_unit'] as num?)?.toDouble();
            if (qtySaleUnits == 0) continue;
            final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;
            double baseQty;
            if (productUnit == 'meter' && saleType == 'لفة') {
              final double factor = (unitsInLargeUnit > 0) ? unitsInLargeUnit : (lengthPerUnit ?? 1.0);
              baseQty = qtySaleUnits * factor;
            } else if (saleType == 'قطعة' || saleType == 'متر') {
              baseQty = qtySaleUnits;
            } else {
              baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
            }
            final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;
            final double costContribution = baseCost * (signedBaseQty);
            addSales += salesContribution;
            addProfit += (salesContribution - costContribution);
            addBaseQty += signedBaseQty;
          }
          adjTotalSales += addSales;
          adjTotalProfit += addProfit;
          adjTotalQuantity += addBaseQty;
          if (adjTotalQuantity > 0) {
            adjAverageSellingPrice = adjTotalSales / adjTotalQuantity;
          }
        }
      } catch (_) {}

      return {
        'totalSales': adjTotalSales,
        'totalProfit': adjTotalProfit,
        'totalInvoices': totalInvoices,
        'totalTransactions': totalTransactions,
        'averageSellingPrice': adjAverageSellingPrice,
        'totalQuantity': adjTotalQuantity,
      };
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<Map<int, PersonYearData>> getCustomerYearlyData(int customerId) async {
    final db = await database;
    try {
      // ═══════════════════════════════════════════════════════════════════════════
      // 🔧 إصلاح: فصل استعلام الفواتير عن المعاملات لتجنب تكرار الصفوف
      // 🔧 إصلاح 2: تضمين الفواتير القديمة التي ليس لها customer_id (بالاسم)
      // 🔧 إصلاح 3: فصل استعلام المبيعات عن الأرباح لتجنب تكرار total_amount
      // ═══════════════════════════════════════════════════════════════════════════
      
      // 1. جلب بيانات المبيعات وعدد الفواتير (بدون JOIN مع الأصناف لتجنب التكرار)
      final List<Map<String, dynamic>> salesMaps = await db.rawQuery('''
        SELECT 
          strftime('%Y', invoice_date) as year,
          SUM(total_amount) as total_sales,
          COUNT(*) as total_invoices
        FROM invoices
        WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
          SELECT name FROM customers WHERE id = ?
        ))) AND status = 'محفوظة'
        GROUP BY strftime('%Y', invoice_date)
        ORDER BY year DESC
      ''', [customerId, customerId]);
      
      // 2. جلب بيانات الأرباح من الأصناف (نفس طريقة getCustomerProfitData)
      // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط من سعر البيع
      final List<Map<String, dynamic>> profitMaps = await db.rawQuery('''
        SELECT 
          strftime('%Y', i.invoice_date) as year,
          SUM(
            CASE 
              WHEN COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0) > 0 
              THEN (ii.applied_price - COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0))
              ELSE ii.applied_price * 0.10
            END * 
            (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                  THEN ii.quantity_large_unit
                  ELSE COALESCE(ii.quantity_individual, 0.0) END)
          ) as total_profit,
          SUM(ii.applied_price * (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE COALESCE(ii.quantity_individual, 0.0) END)) as total_selling_price,
          SUM(CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE COALESCE(ii.quantity_individual, 0.0) END) as total_quantity
        FROM invoices i
        JOIN invoice_items ii ON i.id = ii.invoice_id
        JOIN products p ON ii.product_name = p.name
        WHERE (i.customer_id = ? OR (i.customer_id IS NULL AND i.customer_name = (
          SELECT name FROM customers WHERE id = ?
        ))) AND i.status = 'محفوظة'
        GROUP BY strftime('%Y', i.invoice_date)
      ''', [customerId, customerId]);
      
      // تحويل بيانات الأرباح إلى map للوصول السريع
      final Map<int, Map<String, dynamic>> profitByYear = {};
      for (final p in profitMaps) {
        final year = int.parse(p['year'] as String);
        profitByYear[year] = p;
      }
      
      // 2. جلب عدد المعاملات لكل سنة بشكل منفصل
      final List<Map<String, dynamic>> txMaps = await db.rawQuery('''
        SELECT 
          strftime('%Y', transaction_date) as year,
          COUNT(*) as total_transactions
        FROM transactions
        WHERE customer_id = ?
        GROUP BY strftime('%Y', transaction_date)
      ''', [customerId]);
 
      final Map<int, PersonYearData> yearlyData = {};
      // 4. تحويل المعاملات إلى map للوصول السريع
      final Map<int, int> txByYear = {};
      for (final tx in txMaps) {
        final year = int.parse(tx['year'] as String);
        txByYear[year] = (tx['total_transactions'] ?? 0) as int;
      }
      
      // 5. دمج بيانات المبيعات والأرباح
      for (final map in salesMaps) {
        final year = int.parse(map['year'] as String);
        final profitData = profitByYear[year];
        
        final totalSellingPrice = (profitData?['total_selling_price'] ?? 0.0) as double;
        final totalQuantity = (profitData?['total_quantity'] ?? 0.0) as double;
        final totalProfit = (profitData?['total_profit'] ?? 0.0) as double;
        
        // حساب متوسط سعر البيع
        double averageSellingPrice = 0.0;
        if (totalQuantity > 0) {
          averageSellingPrice = totalSellingPrice / totalQuantity;
        }
        
        yearlyData[year] = PersonYearData(
          totalProfit: totalProfit,
          totalSales: (map['total_sales'] ?? 0.0) as double,
          totalInvoices: (map['total_invoices'] ?? 0) as int,
          totalTransactions: txByYear[year] ?? 0,
          averageSellingPrice: averageSellingPrice,
          totalQuantity: totalQuantity,
        );
      }
 
      // دمج تسويات البنود سنوياً لهذا العميل (تشمل الفواتير القديمة والجديدة)
      try {
        final invIds = await db.rawQuery('''
          SELECT id, strftime('%Y', invoice_date) as y 
          FROM invoices 
          WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
            SELECT name FROM customers WHERE id = ?
          ))) AND status = 'محفوظة'
        ''', [customerId, customerId]);
        if (invIds.isNotEmpty) {
          final ids = invIds.map((e) => (e['id'] as int)).toList();
          final placeholders = List.filled(ids.length, '?').join(',');
          final rows = await db.rawQuery('''
            SELECT strftime('%Y', ia.created_at) as year, ia.type, ia.quantity, ia.price, ia.sale_type, ia.units_in_large_unit,
                   p.unit AS product_unit, p.cost_price AS product_cost, p.length_per_unit AS length_per_unit
            FROM invoice_adjustments ia
            JOIN invoices i ON i.id = ia.invoice_id
            LEFT JOIN products p ON p.id = ia.product_id
            WHERE ia.product_id IS NOT NULL AND ia.invoice_id IN ($placeholders)
          ''', ids);
          for (final r in rows) {
            final int year = int.parse((r['year'] as String));
            final String type = (r['type'] as String?) ?? 'debit';
            final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
            final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
            final String saleType = (r['sale_type'] as String?) ?? ((r['product_unit'] as String?) == 'meter' ? 'متر' : 'قطعة');
            final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;
            final String productUnit = (r['product_unit'] as String?) ?? 'piece';
            final double baseCost = ((r['product_cost'] as num?)?.toDouble()) ?? 0.0;
            final double? lengthPerUnit = (r['length_per_unit'] as num?)?.toDouble();
            if (qtySaleUnits == 0) continue;
            final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;
            double baseQty;
            if (productUnit == 'meter' && saleType == 'لفة') {
              final double factor = (unitsInLargeUnit > 0) ? unitsInLargeUnit : (lengthPerUnit ?? 1.0);
              baseQty = qtySaleUnits * factor;
            } else if (saleType == 'قطعة' || saleType == 'متر') {
              baseQty = qtySaleUnits;
            } else {
              baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
            }
            final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;
            final double costContribution = baseCost * (signedBaseQty);
            final existing = yearlyData[year];
            if (existing != null) {
              final updated = PersonYearData(
                totalProfit: existing.totalProfit + (salesContribution - costContribution),
                totalSales: existing.totalSales + salesContribution,
                totalInvoices: existing.totalInvoices,
                totalTransactions: existing.totalTransactions,
                averageSellingPrice: 0.0, // سيعاد حسابه أدناه
                totalQuantity: existing.totalQuantity + signedBaseQty,
              );
              yearlyData[year] = updated;
            } else {
              yearlyData[year] = PersonYearData(
                totalProfit: (salesContribution - costContribution),
                totalSales: salesContribution,
                totalInvoices: 0,
                totalTransactions: 0,
                averageSellingPrice: 0.0,
                totalQuantity: signedBaseQty,
              );
            }
          }
          // إعادة حساب متوسط سعر البيع للسنة
          for (final entry in yearlyData.entries) {
            final q = entry.value.totalQuantity;
            final s = entry.value.totalSales;
            yearlyData[entry.key] = PersonYearData(
              totalProfit: entry.value.totalProfit,
              totalSales: s,
              totalInvoices: entry.value.totalInvoices,
              totalTransactions: entry.value.totalTransactions,
              averageSellingPrice: q > 0 ? (s / q) : 0.0,
              totalQuantity: q,
            );
          }
        }
      } catch (_) {}

      return yearlyData;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<Map<int, PersonMonthData>> getCustomerMonthlyData(
      int customerId, int year) async {
    final db = await database;
    try {
      // الخطوة 1: إحضار مجاميع المبيعات وعدد الفواتير والمعاملات شهرياً (بدون أرباح)
      // 🔧 إصلاح: تضمين الفواتير القديمة التي ليس لها customer_id (بالاسم)
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          m.month AS month,
          m.total_sales AS total_sales,
          m.total_invoices AS total_invoices,
          COALESCE(t.total_transactions, 0) AS total_transactions
        FROM (
          SELECT 
            strftime('%m', invoice_date) AS month,
            SUM(total_amount) AS total_sales,
            COUNT(DISTINCT id) AS total_invoices
          FROM invoices
          WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
            SELECT name FROM customers WHERE id = ?
          ))) AND strftime('%Y', invoice_date) = ? AND status = 'محفوظة'
          GROUP BY strftime('%m', invoice_date)
        ) m
        LEFT JOIN (
          SELECT strftime('%m', transaction_date) AS month, COUNT(DISTINCT id) AS total_transactions
          FROM transactions
          WHERE customer_id = ? AND strftime('%Y', transaction_date) = ?
          GROUP BY strftime('%m', transaction_date)
        ) t ON t.month = m.month
        ORDER BY m.month ASC
      ''', [customerId, customerId, year.toString(), customerId, year.toString()]);
 
      final Map<int, PersonMonthData> monthlyData = {};
      for (final map in maps) {
        final month = int.parse(map['month'] as String);
        monthlyData[month] = PersonMonthData(
          totalProfit: 0.0, // سنحسبها بدقة في الخطوة 2
          totalSales: (map['total_sales'] ?? 0.0) as double,
          totalInvoices: (map['total_invoices'] ?? 0) as int,
          totalTransactions: (map['total_transactions'] ?? 0) as int,
          invoices: const [],
        );
      }
 
      // الخطوة 2: حساب الربح بنفس طريقة getCustomerProfitData و getCustomerYearlyData
      // 🔧 إصلاح: تضمين الفواتير القديمة التي ليس لها customer_id (بالاسم)
      // 🔧 إصلاح 2: توحيد طريقة حساب الربح مع الدوال الأخرى
      // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط من سعر البيع
      final List<Map<String, dynamic>> profitRows = await db.rawQuery('''
        SELECT 
          strftime('%m', i.invoice_date) AS month,
          SUM(
            CASE 
              WHEN COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0) > 0 
              THEN (ii.applied_price - COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0))
              ELSE ii.applied_price * 0.10
            END * 
            (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                  THEN ii.quantity_large_unit
                  ELSE COALESCE(ii.quantity_individual, 0.0) END)
          ) as total_profit
        FROM invoices i
        JOIN invoice_items ii ON i.id = ii.invoice_id
        JOIN products p ON ii.product_name = p.name
        WHERE (i.customer_id = ? OR (i.customer_id IS NULL AND i.customer_name = (
          SELECT name FROM customers WHERE id = ?
        ))) AND strftime('%Y', i.invoice_date) = ? AND i.status = 'محفوظة'
        GROUP BY strftime('%m', i.invoice_date)
      ''', [customerId, customerId, year.toString()]);

      for (final r in profitRows) {
        final int month = int.parse((r['month'] as String));
        final double totalProfit = ((r['total_profit'] as num?) ?? 0).toDouble();
        
        final existing = monthlyData[month];
        if (existing != null) {
          monthlyData[month] = PersonMonthData(
            totalProfit: totalProfit,
            totalSales: existing.totalSales,
            totalInvoices: existing.totalInvoices,
            totalTransactions: existing.totalTransactions,
            invoices: existing.invoices,
          );
        } else {
          monthlyData[month] = PersonMonthData(
            totalProfit: totalProfit,
            totalSales: 0.0,
            totalInvoices: 0,
            totalTransactions: 0,
            invoices: const [],
          );
        }
      }

      // الخطوة 3: دمج تسويات البنود شهرياً لهذا العميل (debit/credit) كمساهمات إضافية في المبيعات والربح
      // 🔧 إصلاح: تضمين الفواتير القديمة التي ليس لها customer_id (بالاسم)
      try {
        final invIds = await db.rawQuery('''
          SELECT id 
          FROM invoices 
          WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = (
            SELECT name FROM customers WHERE id = ?
          ))) AND status = 'محفوظة' AND strftime('%Y', invoice_date) = ?
        ''', [customerId, customerId, year.toString()]);
        if (invIds.isNotEmpty) {
          final ids = invIds.map((e) => (e['id'] as int)).toList();
          final placeholders = List.filled(ids.length, '?').join(',');
          final rows = await db.rawQuery('''
            SELECT strftime('%m', ia.created_at) as month, ia.type, ia.quantity, ia.price, ia.sale_type, ia.units_in_large_unit,
                   p.unit AS product_unit, p.cost_price AS product_cost, p.length_per_unit AS length_per_unit
            FROM invoice_adjustments ia
            JOIN invoices i ON i.id = ia.invoice_id
            LEFT JOIN products p ON p.id = ia.product_id
            WHERE ia.product_id IS NOT NULL AND ia.invoice_id IN ($placeholders)
          ''', ids);
          for (final r in rows) {
            final int month = int.parse((r['month'] as String));
            final String type = (r['type'] as String?) ?? 'debit';
            final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
            final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
            final String saleType = (r['sale_type'] as String?) ?? ((r['product_unit'] as String?) == 'meter' ? 'متر' : 'قطعة');
            final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;
            final String productUnit = (r['product_unit'] as String?) ?? 'piece';
            final double baseCost = ((r['product_cost'] as num?)?.toDouble()) ?? 0.0;
            final double? lengthPerUnit = (r['length_per_unit'] as num?)?.toDouble();
            if (qtySaleUnits == 0) continue;
            final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;
            double baseQty;
            if (productUnit == 'meter' && saleType == 'لفة') {
              final double factor = (unitsInLargeUnit > 0) ? unitsInLargeUnit : (lengthPerUnit ?? 1.0);
              baseQty = qtySaleUnits * factor;
            } else if (saleType == 'قطعة' || saleType == 'متر') {
              baseQty = qtySaleUnits;
            } else {
              baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
            }
            final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;
            final double costContribution = baseCost * (signedBaseQty);
            final existing = monthlyData[month];
            if (existing != null) {
              monthlyData[month] = PersonMonthData(
                totalProfit: existing.totalProfit + (salesContribution - costContribution),
                totalSales: existing.totalSales + salesContribution,
                totalInvoices: existing.totalInvoices,
                totalTransactions: existing.totalTransactions,
                invoices: existing.invoices,
              );
            } else {
              monthlyData[month] = PersonMonthData(
                totalProfit: (salesContribution - costContribution),
                totalSales: salesContribution,
                totalInvoices: 0,
                totalTransactions: 0,
                invoices: const [],
              );
            }
          }
          // لا حاجة لإعادة حساب متوسط السعر أو الكمية هنا لأن PersonMonthData لا يتضمنهما
        }
      } catch (_) {}

      return monthlyData;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<List<Invoice>> getCustomerInvoicesForMonth(
      int customerId, int year, int month) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT *
        FROM invoices
        WHERE customer_id = ? 
          AND strftime('%Y', invoice_date) = ?
          AND strftime('%m', invoice_date) = ?
        ORDER BY invoice_date DESC
      ''', [customerId, year.toString(), month.toString().padLeft(2, '0')]);

      return List.generate(maps.length, (i) => Invoice.fromMap(maps[i]));
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<List<DebtTransaction>> getCustomerTransactionsForMonth(
      int customerId, int year, int month) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT *
        FROM transactions
        WHERE customer_id = ? 
          AND strftime('%Y', transaction_date) = ?
          AND strftime('%m', transaction_date) = ?
        ORDER BY transaction_date DESC
      ''', [customerId, year.toString(), month.toString().padLeft(2, '0')]);

      return List.generate(
          maps.length, (i) => DebtTransaction.fromMap(maps[i]));
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// طباعة تفصيل فاتورة محددة بالمعرف: عناصر، تحويل الكمية الأساسية، التكلفة، الربح، وإجمالي الفاتورة
  Future<void> debugPrintInvoiceById(int invoiceId) async {
    if (!_verboseLogs) return; // معطل في الإصدار النهائي
    final db = await database;
    try {
      final invRows = await db.rawQuery('''
        SELECT id, invoice_date, customer_name, total_amount, status
        FROM invoices WHERE id = ? LIMIT 1
      ''', [invoiceId]);
      if (invRows.isEmpty) {
        print('[InvoiceDebug] Invoice #$invoiceId not found');
        return;
      }
      final inv = invRows.first;
      print('[InvoiceDebug] --- Invoice #${inv['id']} date=${inv['invoice_date']} customer=${inv['customer_name']} status=${inv['status']} total=${inv['total_amount']} ---');

      final itemRows = await db.rawQuery('''
        SELECT ii.product_name, ii.applied_price,
               ii.actual_cost_price AS acp,
               ii.cost_price AS item_cost,
               ii.sale_type, ii.quantity_individual, ii.quantity_large_unit, ii.units_in_large_unit,
               p.unit AS product_unit, p.length_per_unit, p.cost_price AS product_cost, p.unit_costs AS unit_costs
        FROM invoice_items ii
        LEFT JOIN products p ON ii.product_name = p.name
        WHERE ii.invoice_id = ?
        ORDER BY ii.id ASC
      ''', [invoiceId]);

      double totalSales = 0.0;
      double totalProfit = 0.0;
      for (final r in itemRows) {
        final String prod = (r['product_name'] as String?) ?? '';
        final double applied = ((r['applied_price'] as num?) ?? 0).toDouble();
        final double? acp = (r['acp'] as num?)?.toDouble();
        final double itemCost = ((r['item_cost'] as num?) ?? 0).toDouble();
        final String saleType = (r['sale_type'] as String?) ?? '';
        final double qi = ((r['quantity_individual'] as num?) ?? 0).toDouble();
        final double ql = ((r['quantity_large_unit'] as num?) ?? 0).toDouble();
        final double uilu = ((r['units_in_large_unit'] as num?) ?? 0).toDouble();
        final String productUnit = (r['product_unit'] as String?) ?? '';
        final double? lengthPerUnit = (r['length_per_unit'] as num?)?.toDouble();
        final double productCost = ((r['product_cost'] as num?) ?? 0).toDouble();
        final String? unitCostsJson = r['unit_costs'] as String?;
        Map<String, dynamic> unitCosts = const {};
        if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
          try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
        }

        final bool soldAsLargeUnit = ql > 0;
        final double saleUnitsCount = soldAsLargeUnit ? ql : qi;

        double costPerSaleUnit;
        if (acp != null && acp > 0) {
          costPerSaleUnit = acp;
        } else if (soldAsLargeUnit) {
          // أولاً جرّب قراءة تكلفة الوحدة الكبيرة مباشرة من unit_costs إن كانت مخزنة
          final dynamic stored = unitCosts[saleType];
          if (stored is num) {
            costPerSaleUnit = stored.toDouble();
          } else if (productUnit == 'meter' && saleType == 'لفة') {
            costPerSaleUnit = productCost * (lengthPerUnit ?? 1.0);
          } else {
            costPerSaleUnit = productCost * (uilu > 0 ? uilu : 1.0);
          }
        } else {
          costPerSaleUnit = itemCost > 0 ? itemCost : productCost;
        }

        final double lineAmount = applied * saleUnitsCount;
        final double lineCostTotal = costPerSaleUnit * saleUnitsCount;
        final double lineProfit = MoneyCalculator.subtract(lineAmount, lineCostTotal);
        totalSales += lineAmount;
        totalProfit = MoneyCalculator.add(totalProfit, lineProfit);
        print('[InvoiceDebug][Item] prod="$prod" type=$saleType qty=$saleUnitsCount price=$applied amount=$lineAmount costPerUnit=$costPerSaleUnit costTotal=$lineCostTotal profit=$lineProfit');
      }

      // التسويات الخاصة بهذه الفاتورة
      final adjRows = await db.rawQuery('''
        SELECT ia.type, ia.quantity, ia.price, ia.sale_type, ia.units_in_large_unit,
               p.unit AS product_unit, p.cost_price AS product_cost, p.length_per_unit AS length_per_unit
        FROM invoice_adjustments ia
        LEFT JOIN products p ON p.id = ia.product_id
        WHERE ia.product_id IS NOT NULL AND ia.invoice_id = ?
      ''', [invoiceId]);
      for (final r in adjRows) {
        final String type = (r['type'] as String?) ?? 'debit';
        final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
        final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
        final String saleType = (r['sale_type'] as String?) ?? ((r['product_unit'] as String?) == 'meter' ? 'متر' : 'قطعة');
        final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;
        final String productUnit = (r['product_unit'] as String?) ?? 'piece';
        final double baseCost = ((r['product_cost'] as num?)?.toDouble()) ?? 0.0;
        final double? lengthPerUnit = (r['length_per_unit'] as num?)?.toDouble();
        if (qtySaleUnits == 0) continue;
        final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;
        double baseQty;
        if (productUnit == 'meter' && saleType == 'لفة') {
          final double factor = (unitsInLargeUnit > 0) ? unitsInLargeUnit : (lengthPerUnit ?? 1.0);
          baseQty = qtySaleUnits * factor;
        } else if (saleType == 'قطعة' || saleType == 'متر') {
          baseQty = qtySaleUnits;
        } else {
          baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
        }
        final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;
        final double costContribution = baseCost * signedBaseQty;
        totalSales += salesContribution;
        totalProfit = MoneyCalculator.add(totalProfit, MoneyCalculator.subtract(salesContribution, costContribution));
        print('[InvoiceDebug][Adj] type=$type saleType=$saleType baseQty=$signedBaseQty price=$pricePerSaleUnit baseCost=$baseCost sales=$salesContribution profit=${salesContribution - costContribution}');
      }

      print('[InvoiceDebug] === Totals for invoice #$invoiceId: sales=$totalSales profit=$totalProfit ===');
    } catch (e) {
      print('debugPrintInvoiceById failed: $e');
    }
  }

  Future<void> debugPrintProductsForInvoice(int invoiceId) async {
    if (!_verboseLogs) return; // معطل في الإصدار النهائي
    final db = await database;
    try {
      final List<Map<String, dynamic>> rows = await db.rawQuery('''
        SELECT DISTINCT ii.product_name AS product_name
        FROM invoice_items ii
        WHERE ii.invoice_id = ?
      ''', [invoiceId]);

      if (rows.isEmpty) {
        print('[ProductDebug] No products found for invoice #$invoiceId');
        return;
      }

      for (final r in rows) {
        final String productName = r['product_name'] as String;
        final List<Map<String, dynamic>> pr = await db.rawQuery('''
          SELECT p.name, p.unit, p.unit_price, p.cost_price, p.pieces_per_unit,
                 p.length_per_unit, p.unit_hierarchy, p.unit_costs
          FROM products p
          WHERE p.name = ?
          LIMIT 1
        ''', [productName]);
        if (pr.isEmpty) {
          print('[ProductDebug] product not found in products: "$productName"');
          continue;
        }

        final Map<String, dynamic> p = pr.first;
        final String unit = (p['unit'] ?? '') as String;
        final double baseCost = ((p['cost_price'] as num?)?.toDouble() ?? 0.0);
        final int? piecesPerUnit = (p['pieces_per_unit'] as num?)?.toInt();
        final double? lengthPerUnit = (p['length_per_unit'] as num?)?.toDouble();
        final String? unitHierarchyJson = p['unit_hierarchy'] as String?;
        final String? unitCostsJson = p['unit_costs'] as String?;

        List<dynamic> hierarchy = const [];
        Map<String, dynamic> unitCosts = const {};
        try {
          if (unitHierarchyJson != null && unitHierarchyJson.trim().isNotEmpty) {
            hierarchy = jsonDecode(unitHierarchyJson) as List<dynamic>;
          }
        } catch (_) {}
        try {
          if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
            unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>;
          }
        } catch (_) {}

        print('[ProductDebug] name="$productName" unit=$unit baseCost=$baseCost piecesPerUnit=${piecesPerUnit ?? 0} lengthPerUnit=${lengthPerUnit ?? 0}');

        if (unitCosts.isNotEmpty) {
          final entries = unitCosts.entries
              .map((e) => '${e.key}=${(e.value is num) ? (e.value as num).toDouble() : e.value}')
              .join(', ');
          print('[ProductDebug][UnitCosts] $entries');
        } else {
          print('[ProductDebug][UnitCosts] <empty>');
        }

        if (hierarchy.isNotEmpty) {
          for (final h in hierarchy) {
            if (h is Map<String, dynamic>) {
              final String unitName = (h['unit_name'] ?? '') as String;
              final dynamic qtyRaw = h['quantity'];
              double qty = 0;
              if (qtyRaw is num) qty = qtyRaw.toDouble();
              print('[ProductDebug][Hierarchy] $unitName qty=$qty');
              // طباعة تكلفة الوحدة الكبيرة المحسوبة/المخزنة بوضوح
              double derivedCost;
              final dynamic stored = unitCosts[unitName];
              if (stored is num) {
                derivedCost = stored.toDouble();
                print('[ProductDebug][Cost][$unitName] storedUnitCost=$derivedCost');
              } else {
                // للمتر و"لفة" استخدم طول اللفة
                if (unit == 'meter' && unitName == 'لفة') {
                  final double len = (lengthPerUnit ?? 1.0);
                  derivedCost = baseCost * len;
                } else {
                  derivedCost = baseCost * (qty > 0 ? qty : 1.0);
                }
                print('[ProductDebug][Cost][$unitName] computedUnitCost=$derivedCost (from baseCost x qty)');
              }
            }
          }
        } else {
          print('[ProductDebug][Hierarchy] <empty>');
        }

        // What unit multipliers were used for this product in this invoice
        final List<Map<String, dynamic>> used = await db.rawQuery('''
          SELECT ii.sale_type, ii.units_in_large_unit AS uilu
          FROM invoice_items ii
          WHERE ii.invoice_id = ? AND ii.product_name = ?
        ''', [invoiceId, productName]);
        for (final u in used) {
          final String saleType = (u['sale_type'] ?? '') as String;
          final double uilu = ((u['uilu'] as num?) ?? 0).toDouble();
          print('[ProductDebug][UsedInInv] sale_type=$saleType units_in_large_unit=$uilu');
          // طباعة تكلفة الوحدة المستخدمة فعلياً بوضوح
          double saleUnitCost;
          final dynamic stored = unitCosts[saleType];
          if (stored is num) {
            saleUnitCost = stored.toDouble();
            print('[ProductDebug][UsedInInvCost] sale_type=$saleType unitCostSource=stored unitCost=$saleUnitCost');
          } else if (unit == 'meter' && saleType == 'لفة') {
            saleUnitCost = baseCost * ((lengthPerUnit ?? 1.0));
            print('[ProductDebug][UsedInInvCost] sale_type=$saleType unitCostSource=lengthBased unitCost=$saleUnitCost');
          } else if (saleType == 'قطعة' || saleType == 'متر' || uilu == 0) {
            saleUnitCost = baseCost;
            print('[ProductDebug][UsedInInvCost] sale_type=$saleType unitCostSource=base unitCost=$saleUnitCost');
          } else {
            saleUnitCost = baseCost * uilu;
            print('[ProductDebug][UsedInInvCost] sale_type=$saleType unitCostSource=multiplied unitCost=$saleUnitCost');
          }
        }
      }
    } catch (e) {
      print('[ProductDebug] Error: $e');
    }
  }

  /// دالة لحساب ربح المنتج سنويًا
  Future<Map<int, double>> getProductYearlyProfit(int productId) async {
    final db = await database;
    try {
      // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط من سعر البيع
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          strftime('%Y', i.invoice_date) as year,
          SUM(
            CASE 
              WHEN COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0) > 0 
              THEN (ii.applied_price - COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0))
              ELSE ii.applied_price * 0.10
            END * 
            (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                  THEN ii.quantity_large_unit
                  ELSE ii.quantity_individual END)
          ) as total_profit,
          SUM(ii.applied_price * (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END)) as total_selling_price,
          SUM(CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit * COALESCE(ii.units_in_large_unit, 1.0)
                    ELSE ii.quantity_individual END) as total_quantity,
          p.unit,
          p.length_per_unit,
          p.unit_hierarchy,
          p.unit_costs
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
        JOIN products p ON ii.product_name = p.name
        WHERE p.id = ? AND i.status = 'محفوظة'
        GROUP BY strftime('%Y', i.invoice_date)
        ORDER BY year DESC
      ''', [productId]);

      final Map<int, double> yearlyProfit = {};
      for (final map in maps) {
        final year = int.parse(map['year'] as String);
        double profit = (map['total_profit'] ?? 0.0) as double;
        
        // تصحيح الربح للمنتجات المباعة بالمتر
        final productUnit = map['unit'] as String;
        if (productUnit == 'meter') {
          // إعادة حساب الربح باستخدام النظام الهرمي
          final unitHierarchy = map['unit_hierarchy'] as String?;
          final unitCosts = map['unit_costs'] as String?;
          
          if (unitHierarchy != null && unitCosts != null) {
            // جلب تفاصيل البنود لهذا العام
            final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
              SELECT 
                ii.quantity_individual,
                ii.quantity_large_unit,
                ii.units_in_large_unit,
                ii.applied_price,
                ii.sale_type,
                p.cost_price as product_cost_price
              FROM invoice_items ii
              JOIN invoices i ON ii.invoice_id = i.id
              JOIN products p ON ii.product_name = p.name
              WHERE p.id = ? AND strftime('%Y', i.invoice_date) = ? AND i.status = 'محفوظة'
            ''', [productId, year.toString()]);
            
            double correctedProfit = 0.0;
            for (final item in itemMaps) {
              final double quantityIndividual = (item['quantity_individual'] ?? 0.0) as double;
              final double quantityLargeUnit = (item['quantity_large_unit'] ?? 0.0) as double;
              final double unitsInLargeUnit = (item['units_in_large_unit'] ?? 1.0) as double;
              final double sellingPrice = (item['applied_price'] ?? 0.0) as double;
              final String saleType = (item['sale_type'] ?? 'متر') as String;
              
              double costPrice = 0.0;
              if (saleType == 'متر') {
                costPrice = (item['product_cost_price'] ?? 0.0) as double;
              } else if (saleType == 'لفة') {
                // حساب تكلفة اللفة من النظام الهرمي
                costPrice = _calculateCostFromHierarchy(unitHierarchy, unitCosts, 'لفة', 1.0);
                if (costPrice == 0.0) {
                  // إذا لم يتم العثور على التكلفة، احسبها يدوياً
                  final productCostPrice = (item['product_cost_price'] ?? 0.0) as double;
                  final lengthPerUnit = (map['length_per_unit'] ?? 1.0) as double;
                  costPrice = productCostPrice * lengthPerUnit;
                }
              }
              
              // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
              if (costPrice <= 0 && sellingPrice > 0) {
                costPrice = MoneyCalculator.getEffectiveCost(0, sellingPrice);
              }
              
              if (quantityLargeUnit > 0) {
                correctedProfit += (sellingPrice - costPrice) * quantityLargeUnit;
              } else {
                correctedProfit += (sellingPrice - costPrice) * quantityIndividual;
              }
            }
            
            profit = correctedProfit;
          }
        }
        
        yearlyProfit[year] = profit;
      }
      // دمج أرباح تسويات البنود سنوياً مع احترام الهرمية
      try {
        final prodRows = await db.rawQuery('SELECT unit, cost_price, length_per_unit FROM products WHERE id = ?', [productId]);
        String productUnit = (prodRows.isNotEmpty ? (prodRows.first['unit'] as String?) : null) ?? 'piece';
        final double baseCost = prodRows.isNotEmpty ? ((prodRows.first['cost_price'] as num?)?.toDouble() ?? 0.0) : 0.0;
        final double? lengthPerUnit = prodRows.isNotEmpty ? (prodRows.first['length_per_unit'] as num?)?.toDouble() : null;

        final rows = await db.rawQuery('''
          SELECT strftime('%Y', created_at) as year, type, quantity, price, sale_type, units_in_large_unit
          FROM invoice_adjustments
          WHERE product_id = ?
        ''', [productId]);

        for (final r in rows) {
          final int year = int.parse((r['year'] as String));
          final String type = (r['type'] as String?) ?? 'debit';
          final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
          final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
          final String saleType = (r['sale_type'] as String?) ?? (productUnit == 'meter' ? 'متر' : 'قطعة');
          final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;
          if (qtySaleUnits == 0) continue;

          final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;

          double baseQty;
          if (productUnit == 'meter' && saleType == 'لفة') {
            final double factor = (unitsInLargeUnit > 0) ? unitsInLargeUnit : (lengthPerUnit ?? 1.0);
            baseQty = qtySaleUnits * factor;
          } else if (saleType == 'قطعة' || saleType == 'متر') {
            baseQty = qtySaleUnits;
          } else {
            baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
          }
          final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;
          final double costContribution = baseCost * (signedBaseQty);

          yearlyProfit[year] = (yearlyProfit[year] ?? 0) + (salesContribution - costContribution);
        }
      } catch (_) {}

      return yearlyProfit;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// دالة لحساب ربح المنتج شهريًا لسنة معينة
  Future<Map<int, double>> getProductMonthlyProfit(
      int productId, int year) async {
    final db = await database;
    try {
      // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط من سعر البيع
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          strftime('%m', i.invoice_date) as month,
          SUM(
            CASE 
              WHEN COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0) > 0 
              THEN (ii.applied_price - COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0))
              ELSE ii.applied_price * 0.10
            END * 
            (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                  THEN ii.quantity_large_unit
                  ELSE ii.quantity_individual END)
          ) as total_profit,
          SUM(ii.applied_price * (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END)) as total_selling_price,
          SUM(CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit * COALESCE(ii.units_in_large_unit, 1.0)
                    ELSE ii.quantity_individual END) as total_quantity,
          p.unit,
          p.length_per_unit,
          p.unit_hierarchy,
          p.unit_costs
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
        JOIN products p ON ii.product_name = p.name
        WHERE p.id = ? AND strftime('%Y', i.invoice_date) = ? AND i.status = 'محفوظة'
        GROUP BY strftime('%m', i.invoice_date)
        ORDER BY month ASC
      ''', [productId, year.toString()]);

      final Map<int, double> monthlyProfit = {};
      for (final map in maps) {
        final month = int.parse(map['month'] as String);
        double profit = (map['total_profit'] ?? 0.0) as double;
        
        // تصحيح الربح للمنتجات المباعة بالمتر
        final productUnit = map['unit'] as String;
        if (productUnit == 'meter') {
          // إعادة حساب الربح باستخدام النظام الهرمي
          final unitHierarchy = map['unit_hierarchy'] as String?;
          final unitCosts = map['unit_costs'] as String?;
          
          if (unitHierarchy != null && unitCosts != null) {
            // جلب تفاصيل البنود لهذا الشهر
            final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
              SELECT 
                ii.quantity_individual,
                ii.quantity_large_unit,
                ii.units_in_large_unit,
                ii.applied_price,
                ii.sale_type,
                p.cost_price as product_cost_price
              FROM invoice_items ii
              JOIN invoices i ON ii.invoice_id = i.id
              JOIN products p ON ii.product_name = p.name
              WHERE p.id = ? AND strftime('%Y', i.invoice_date) = ? AND strftime('%m', i.invoice_date) = ? AND i.status = 'محفوظة'
            ''', [productId, year.toString(), month.toString().padLeft(2, '0')]);
            
            double correctedProfit = 0.0;
            for (final item in itemMaps) {
              final double quantityIndividual = (item['quantity_individual'] ?? 0.0) as double;
              final double quantityLargeUnit = (item['quantity_large_unit'] ?? 0.0) as double;
              final double unitsInLargeUnit = (item['units_in_large_unit'] ?? 1.0) as double;
              final double sellingPrice = (item['applied_price'] ?? 0.0) as double;
              final String saleType = (item['sale_type'] ?? 'متر') as String;
              
              double costPrice = 0.0;
              if (saleType == 'متر') {
                costPrice = (item['product_cost_price'] ?? 0.0) as double;
              } else if (saleType == 'لفة') {
                // حساب تكلفة اللفة من النظام الهرمي
                costPrice = _calculateCostFromHierarchy(unitHierarchy, unitCosts, 'لفة', 1.0);
                if (costPrice == 0.0) {
                  // إذا لم يتم العثور على التكلفة، احسبها يدوياً
                  final productCostPrice = (item['product_cost_price'] ?? 0.0) as double;
                  final lengthPerUnit = (map['length_per_unit'] ?? 1.0) as double;
                  costPrice = productCostPrice * lengthPerUnit;
                }
              }
              
              // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
              if (costPrice <= 0 && sellingPrice > 0) {
                costPrice = MoneyCalculator.getEffectiveCost(0, sellingPrice);
              }
              
              if (quantityLargeUnit > 0) {
                correctedProfit += (sellingPrice - costPrice) * quantityLargeUnit;
              } else {
                correctedProfit += (sellingPrice - costPrice) * quantityIndividual;
              }
            }
            
            profit = correctedProfit;
          }
        }
        
        monthlyProfit[month] = profit;
      }
      // دمج أرباح تسويات البنود شهرياً مع احترام الهرمية
      try {
        final prodRows = await db.rawQuery('SELECT unit, cost_price, length_per_unit FROM products WHERE id = ?', [productId]);
        String productUnit = (prodRows.isNotEmpty ? (prodRows.first['unit'] as String?) : null) ?? 'piece';
        final double baseCost = prodRows.isNotEmpty ? ((prodRows.first['cost_price'] as num?)?.toDouble() ?? 0.0) : 0.0;
        final double? lengthPerUnit = prodRows.isNotEmpty ? (prodRows.first['length_per_unit'] as num?)?.toDouble() : null;

        final rows = await db.rawQuery('''
          SELECT strftime('%m', created_at) as month, type, quantity, price, sale_type, units_in_large_unit
          FROM invoice_adjustments
          WHERE product_id = ? AND strftime('%Y', created_at) = ?
        ''', [productId, year.toString()]);

        for (final r in rows) {
          final int month = int.parse((r['month'] as String));
          final String type = (r['type'] as String?) ?? 'debit';
          final double qtySaleUnits = ((r['quantity'] as num?) ?? 0).toDouble();
          final double pricePerSaleUnit = ((r['price'] as num?) ?? 0).toDouble();
          final String saleType = (r['sale_type'] as String?) ?? (productUnit == 'meter' ? 'متر' : 'قطعة');
          final double unitsInLargeUnit = ((r['units_in_large_unit'] as num?)?.toDouble()) ?? 1.0;
          if (qtySaleUnits == 0) continue;

          final double salesContribution = (type == 'debit' ? 1 : -1) * qtySaleUnits * pricePerSaleUnit;

          double baseQty;
          if (productUnit == 'meter' && saleType == 'لفة') {
            final double factor = (unitsInLargeUnit > 0) ? unitsInLargeUnit : (lengthPerUnit ?? 1.0);
            baseQty = qtySaleUnits * factor;
          } else if (saleType == 'قطعة' || saleType == 'متر') {
            baseQty = qtySaleUnits;
          } else {
            baseQty = qtySaleUnits * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
          }
          final double signedBaseQty = (type == 'debit' ? 1 : -1) * baseQty;
          final double costContribution = baseCost * (signedBaseQty);

          monthlyProfit[month] = (monthlyProfit[month] ?? 0) + (salesContribution - costContribution);
        }
      } catch (_) {}

      return monthlyProfit;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// جلب جميع فواتير العميل في شهر معيّن مع ربح كل فاتورة
  Future<List<InvoiceWithProductData>> getCustomerInvoicesWithProfitForMonth(
      int customerId, int year, int month) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT i.*, ii.product_name, ii.applied_price, ii.cost_price, ii.actual_cost_price, ii.quantity_individual, ii.quantity_large_unit, ii.units_in_large_unit, p.cost_price as product_cost_price
        FROM invoices i
        JOIN invoice_items ii ON i.id = ii.invoice_id
        JOIN products p ON ii.product_name = p.name
        WHERE i.customer_id = ?
          AND strftime('%Y', i.invoice_date) = ?
          AND strftime('%m', i.invoice_date) = ?
          AND i.status = 'محفوظة'
        ORDER BY i.invoice_date DESC
      ''', [customerId, year.toString(), month.toString().padLeft(2, '0')]);

      // تجميع البنود حسب الفاتورة
      final Map<int, List<Map<String, dynamic>>> invoiceItemsMap = {};
      for (final map in maps) {
        final invoiceId = map['id'] as int;
        invoiceItemsMap.putIfAbsent(invoiceId, () => []).add(map);
      }

      final List<InvoiceWithProductData> result = [];
      for (final entry in invoiceItemsMap.entries) {
        final invoiceId = entry.key;
        final items = entry.value;
        double totalProfit = 0.0;
        double totalQuantity = 0.0; // بوحدة الأساس
        double saleUnitsCount = 0.0; // بعدد وحدات البيع
        double totalSelling = 0.0;
        double totalCost = 0.0;
        for (final item in items) {
          final double sellingPrice = ((item['applied_price'] as num?) ?? 0).toDouble();
          final double? actualCostPrice = (item['actual_cost_price'] as num?)?.toDouble();
          final double itemCostPrice = ((item['cost_price'] as num?) ?? 0).toDouble();
          final double productCostPrice = ((item['product_cost_price'] as num?) ?? 0).toDouble();
          final double quantityIndividual = ((item['quantity_individual'] as num?) ?? 0).toDouble();
          final double quantityLargeUnit = ((item['quantity_large_unit'] as num?) ?? 0).toDouble();
          final double unitsInLargeUnit = ((item['units_in_large_unit'] as num?) ?? 1).toDouble();

          // الكمية الإجمالية (بالوحدة الأساسية)
          final double currentItemTotalQuantity = quantityLargeUnit > 0
              ? (quantityLargeUnit * unitsInLargeUnit)
              : quantityIndividual;

          // تكلفة وحدة البيع: أولوية للتكلفة الفعلية، ثم المخزنة لوحدة البيع، ثم مضاعفة الأساس
          double costPerSaleUnit;
          if (actualCostPrice != null && actualCostPrice > 0) {
            costPerSaleUnit = actualCostPrice;
          } else if (quantityLargeUnit > 0) {
            // نحاول قراءة unit_costs للوحدة الكبيرة
            double? stored;
            try {
              final pr = await db.rawQuery('SELECT unit, length_per_unit, unit_costs FROM products WHERE name = ? LIMIT 1', [item['product_name']]);
              if (pr.isNotEmpty) {
                final String? unitCostsJson = pr.first['unit_costs'] as String?;
                final String productUnit = (pr.first['unit'] as String?) ?? 'piece';
                final double? lengthPerUnit = (pr.first['length_per_unit'] as num?)?.toDouble();
                Map<String, dynamic> unitCosts = const {};
                if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
                  try { unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; } catch (_) {}
                }
                // sale_type غير موجود في هذا الاستعلام؛ نفترض Large unit إذا quantity_large_unit > 0
                // سنستنتج التكلفة: إن وُجدت قيمة للوحدة الكبيرة ضمن unit_costs (مثل "باكيت"/"كرتون") فلن تصلنا هنا مباشرة
                // لذا نعتمد مسار fallback العام: للمتر/لفة استخدم الطول، وإلا استخدم ضرب الأساس
                stored = null; // لا نملك sale_type هنا، لذا لا نستطيع الانتقاء بالاسم؛ سنستخدم fallback
                if (stored != null && stored > 0) {
                  costPerSaleUnit = stored;
                } else if (productUnit == 'meter') {
                  final double base = productCostPrice > 0 ? productCostPrice : (itemCostPrice > 0 ? itemCostPrice : 0.0);
                  costPerSaleUnit = base * ((lengthPerUnit ?? 1.0));
                } else {
                  final double base = productCostPrice > 0 ? productCostPrice : (itemCostPrice > 0 ? itemCostPrice : 0.0);
                  costPerSaleUnit = base * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
                }
              } else {
                final double base = productCostPrice > 0 ? productCostPrice : (itemCostPrice > 0 ? itemCostPrice : 0.0);
                costPerSaleUnit = base * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
              }
            } catch (_) {
              final double base = productCostPrice > 0 ? productCostPrice : (itemCostPrice > 0 ? itemCostPrice : 0.0);
              costPerSaleUnit = base * (unitsInLargeUnit > 0 ? unitsInLargeUnit : 1.0);
            }
          } else {
            // بيع بالوحدة الأساسية
            costPerSaleUnit = itemCostPrice > 0 ? itemCostPrice : productCostPrice;
          }

          // 🔧 إصلاح: إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
          if (costPerSaleUnit <= 0 && sellingPrice > 0) {
            costPerSaleUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
          }

          if (quantityLargeUnit > 0) {
            totalSelling += sellingPrice * quantityLargeUnit;
            totalCost += costPerSaleUnit * quantityLargeUnit;
            totalProfit = MoneyCalculator.add(totalProfit, MoneyCalculator.multiply(MoneyCalculator.subtract(sellingPrice, costPerSaleUnit), quantityLargeUnit));
          } else {
            totalSelling += sellingPrice * quantityIndividual;
            totalCost += costPerSaleUnit * quantityIndividual;
            totalProfit = MoneyCalculator.add(totalProfit, MoneyCalculator.multiply(MoneyCalculator.subtract(sellingPrice, costPerSaleUnit), quantityIndividual));
          }

          totalQuantity += currentItemTotalQuantity;
          saleUnitsCount += quantityLargeUnit > 0 ? quantityLargeUnit : quantityIndividual;
        }
        final invoice = Invoice.fromMap(items.first);
        final double avgSellingPrice =
            totalQuantity > 0 ? totalSelling / totalQuantity : 0.0;
        final double avgUnitCost =
            totalQuantity > 0 ? totalCost / totalQuantity : 0.0;
        result.add(InvoiceWithProductData(
          invoice: invoice,
          quantitySold: totalQuantity,
          saleUnitsCount: saleUnitsCount,
          profit: totalProfit,
          sellingPrice: avgSellingPrice,
          unitCostAtSale: avgUnitCost,
        ));
      }
      return result;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// دالة اختبار لحساب الأرباح - للتأكد من صحة الحسابات
  Future<Map<String, dynamic>> testProfitCalculation(int productId) async {
    final db = await database;
    try {
      // جلب بيانات المنتج
      final productMaps = await db.rawQuery('''
        SELECT * FROM products WHERE id = ?
      ''', [productId]);
      
      if (productMaps.isEmpty) {
        throw Exception('المنتج غير موجود');
      }
      
      final product = productMaps.first;
      final costPrice = (product['cost_price'] ?? 0.0) as double;
      
      // جلب جميع الفواتير التي تحتوي على هذا المنتج
      final List<Map<String, dynamic>> itemMaps = await db.rawQuery('''
        SELECT 
          ii.quantity_individual,
          ii.quantity_large_unit,
          ii.units_in_large_unit,
          ii.applied_price,
          ii.cost_price,
          ii.item_total,
          i.id as invoice_id,
          i.invoice_date
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
        WHERE ii.product_name = ?
        ORDER BY i.invoice_date DESC
      ''', [product['name']]);

      final List<Map<String, dynamic>> detailedResults = [];
      double totalQuantity = 0.0;
      double totalProfit = 0.0;
      double totalSales = 0.0;
      double totalCost = 0.0;

      for (final item in itemMaps) {
        double quantityIndividual =
            (item['quantity_individual'] ?? 0.0) as double;
        double quantityLargeUnit =
            (item['quantity_large_unit'] ?? 0.0) as double;
        double unitsInLargeUnit =
            (item['units_in_large_unit'] ?? 1.0) as double;
        double currentItemTotalQuantity =
            quantityIndividual + (quantityLargeUnit * unitsInLargeUnit);
        final sellingPrice = (item['applied_price'] ?? 0.0) as double;
        // استخدام actual_cost_price إذا كان متوفراً، وإلا استخدم cost_price أو product_cost_price
        final itemCostPrice = (item['actual_cost_price'] ?? 
                              item['cost_price'] ?? 
                              costPrice) as double;
        
        final profit = MoneyCalculator.multiply(MoneyCalculator.subtract(sellingPrice, itemCostPrice), currentItemTotalQuantity);
        final sales = sellingPrice * currentItemTotalQuantity;
        final cost = itemCostPrice * currentItemTotalQuantity;
        
        totalQuantity += currentItemTotalQuantity;
        totalProfit = MoneyCalculator.add(totalProfit, profit);
        totalSales += sales;
        totalCost += cost;
        
        detailedResults.add({
          'invoice_id': item['invoice_id'],
          'date': item['invoice_date'],
          'quantity': currentItemTotalQuantity,
          'cost_price': itemCostPrice,
          'selling_price': sellingPrice,
          'profit': profit,
          'sales': sales,
          'cost': cost,
        });
      }

      return {
        'product_name': product['name'],
        'product_cost_price': costPrice,
        'total_quantity': totalQuantity,
        'total_profit': totalProfit,
        'total_sales': totalSales,
        'total_cost': totalCost,
        'detailed_results': detailedResults,
        'calculation_formula': 'الربح = (سعر البيع - سعر التكلفة) × الكمية',
        'verification': totalProfit == (totalSales - totalCost) ? 'صحيح' : 'خطأ',
      };
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  /// إعادة حساب مجاميع جميع الفواتير من البنود
  Future<Map<String, dynamic>> recalculateAllInvoiceTotals() async {
    try {
      final db = await database;
      int fixed = 0;
      int totalInvoices = 0;
      final List<String> details = [];
      
      // جلب جميع الفواتير
      final invoices = await db.query('invoices');
      totalInvoices = invoices.length;
      
      for (var invoice in invoices) {
        final invoiceId = invoice['id'] as int;
        final displayedTotal = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
        final discount = (invoice['discount'] as num?)?.toDouble() ?? 0.0;
        final loadingFee = (invoice['loading_fee'] as num?)?.toDouble() ?? 0.0;
        
        // جلب عناصر الفاتورة
        final items = await db.query(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );
        
        // حساب المجموع الفعلي من item_total
        double calculatedTotal = 0.0;
        for (var item in items) {
          final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
          calculatedTotal += itemTotal;
        }
        
        // المجموع الصحيح = مجموع البنود - الخصم + أجور التحميل
        final correctTotal = MoneyCalculator.add(MoneyCalculator.subtract(calculatedTotal, discount), loadingFee);
        
        // مقارنة المجموع (مع هامش خطأ صغير للأرقام العشرية)
        if ((displayedTotal - correctTotal).abs() > 0.01) {
          // تحديث الفاتورة
          await db.update(
            'invoices',
            {'total_amount': correctTotal},
            where: 'id = ?',
            whereArgs: [invoiceId],
          );
          
          fixed++;
          details.add(
            'فاتورة #$invoiceId: ${displayedTotal.toStringAsFixed(0)} ← ${correctTotal.toStringAsFixed(0)} دينار'
          );
        }
      }
      
      return {
        'success': true,
        'fixed': fixed,
        'total_invoices': totalInvoices,
        'details': details,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🛡️ دوال الحماية والتدقيق المالي الإضافية
  // ═══════════════════════════════════════════════════════════════════════════

  /// التحقق الشامل من سلامة البيانات المالية لعميل معين
  /// يُرجع تقريراً مفصلاً عن حالة البيانات
  Future<FinancialIntegrityReport> verifyCustomerFinancialIntegrity(int customerId) async {
    final db = await database;
    final List<String> issues = [];
    final List<String> warnings = [];
    bool isHealthy = true;

    try {
      // 1. جلب بيانات العميل
      final customer = await getCustomerById(customerId);
      if (customer == null) {
        return FinancialIntegrityReport(
          customerId: customerId,
          customerName: 'غير موجود',
          isHealthy: false,
          issues: ['العميل غير موجود'],
          warnings: [],
          calculatedBalance: 0,
          recordedBalance: 0,
          transactionCount: 0,
        );
      }
      
      final String customerName = customer.name;

      // 2. حساب مجموع المعاملات
      final sumResult = await db.rawQuery(
        'SELECT COALESCE(SUM(amount_changed), 0) AS total FROM transactions WHERE customer_id = ?',
        [customerId]
      );
      final double calculatedBalance = ((sumResult.first['total'] as num?) ?? 0).toDouble();
      final double recordedBalance = customer.currentTotalDebt;

      // 3. جلب عدد المعاملات
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM transactions WHERE customer_id = ?',
        [customerId]
      );
      final int transactionCount = (countResult.first['cnt'] as int?) ?? 0;

      // 4. التحقق من تطابق الرصيد
      final double balanceDiff = (calculatedBalance - recordedBalance).abs();
      if (balanceDiff > 0.01) {
        isHealthy = false;
        issues.add('عدم تطابق الرصيد: المسجل=${recordedBalance.toStringAsFixed(2)}, المحسوب=${calculatedBalance.toStringAsFixed(2)}, الفرق=${balanceDiff.toStringAsFixed(2)}');
      }

      // 5. التحقق من تسلسل الأرصدة في المعاملات
      final transactions = await getCustomerTransactions(customerId, orderBy: 'transaction_date ASC, id ASC');
      double runningBalance = 0.0;
      for (int i = 0; i < transactions.length; i++) {
        final tx = transactions[i];
        final expectedBalanceAfter = MoneyCalculator.add(runningBalance, tx.amountChanged);
        
        // التحقق من الرصيد قبل المعاملة
        if (tx.balanceBeforeTransaction != null) {
          final beforeDiff = (tx.balanceBeforeTransaction! - runningBalance).abs();
          if (beforeDiff > 0.01) {
            warnings.add('معاملة #${tx.id}: الرصيد قبل غير متطابق (المتوقع: ${runningBalance.toStringAsFixed(2)}, المسجل: ${tx.balanceBeforeTransaction!.toStringAsFixed(2)})');
          }
        }
        
        // التحقق من الرصيد بعد المعاملة
        if (tx.newBalanceAfterTransaction != null) {
          final afterDiff = (tx.newBalanceAfterTransaction! - expectedBalanceAfter).abs();
          if (afterDiff > 0.01) {
            warnings.add('معاملة #${tx.id}: الرصيد بعد غير متطابق (المتوقع: ${expectedBalanceAfter.toStringAsFixed(2)}, المسجل: ${tx.newBalanceAfterTransaction!.toStringAsFixed(2)})');
          }
        }
        
        runningBalance = expectedBalanceAfter;
      }

      // 6. التحقق من وجود معاملات بمبالغ صفرية (قد تكون خطأ)
      final zeroTransactions = transactions.where((t) => t.amountChanged == 0).toList();
      if (zeroTransactions.isNotEmpty) {
        warnings.add('يوجد ${zeroTransactions.length} معاملة بمبلغ صفر');
      }

      // 7. التحقق من وجود معاملات مستقبلية
      final now = DateTime.now();
      final futureTransactions = transactions.where((t) => t.transactionDate.isAfter(now.add(const Duration(days: 1)))).toList();
      if (futureTransactions.isNotEmpty) {
        warnings.add('يوجد ${futureTransactions.length} معاملة بتاريخ مستقبلي');
      }

      return FinancialIntegrityReport(
        customerId: customerId,
        customerName: customerName,
        isHealthy: isHealthy && warnings.isEmpty,
        issues: issues,
        warnings: warnings,
        calculatedBalance: calculatedBalance,
        recordedBalance: recordedBalance,
        transactionCount: transactionCount,
      );
    } catch (e) {
      return FinancialIntegrityReport(
        customerId: customerId,
        customerName: 'خطأ',
        isHealthy: false,
        issues: ['خطأ في التحقق: $e'],
        warnings: [],
        calculatedBalance: 0,
        recordedBalance: 0,
        transactionCount: 0,
      );
    }
  }

  /// التحقق الشامل من سلامة البيانات المالية لجميع العملاء
  Future<List<FinancialIntegrityReport>> verifyAllCustomersFinancialIntegrity() async {
    final customers = await getAllCustomers();
    final List<FinancialIntegrityReport> reports = [];
    
    for (final customer in customers) {
      if (customer.id != null) {
        final report = await verifyCustomerFinancialIntegrity(customer.id!);
        reports.add(report);
      }
    }
    
    return reports;
  }

  /// إصلاح تلقائي لجميع مشاكل الأرصدة
  /// يُرجع عدد العملاء الذين تم إصلاحهم
  Future<int> autoFixAllBalanceIssues() async {
    final db = await database;
    int fixedCount = 0;
    
    try {
      final customers = await getAllCustomers();
      
      for (final customer in customers) {
        if (customer.id == null) continue;
        
        // حساب المجموع الصحيح
        final sumResult = await db.rawQuery(
          'SELECT COALESCE(SUM(amount_changed), 0) AS total FROM transactions WHERE customer_id = ?',
          [customer.id]
        );
        final double correctBalance = ((sumResult.first['total'] as num?) ?? 0).toDouble();
        
        // التحقق من وجود فرق
        final diff = (customer.currentTotalDebt - correctBalance).abs();
        if (diff > 0.01) {
          // تحديث رصيد العميل
          await db.update(
            'customers',
            {
              'current_total_debt': correctBalance,
              'last_modified_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [customer.id],
          );
          
          // إعادة حساب تسلسل الأرصدة
          await recalculateCustomerTransactionBalances(customer.id!);
          
          fixedCount++;
          print('✅ تم إصلاح رصيد العميل ${customer.name}: ${customer.currentTotalDebt} → $correctBalance');
        }
      }
      
      return fixedCount;
    } catch (e) {
      print('❌ خطأ في الإصلاح التلقائي: $e');
      return fixedCount;
    }
  }

  /// التحقق من صحة معاملة قبل إدراجها (طبقة حماية إضافية)
  Future<TransactionValidationResult> validateTransactionBeforeInsert({
    required int customerId,
    required double amountChanged,
    required String transactionType,
  }) async {
    final List<String> errors = [];
    final List<String> warnings = [];
    
    try {
      // 1. التحقق من وجود العميل
      final customer = await getCustomerById(customerId);
      if (customer == null) {
        errors.add('العميل غير موجود');
        return TransactionValidationResult(isValid: false, errors: errors, warnings: warnings);
      }
      
      // 2. التحقق من المبلغ
      if (amountChanged == 0) {
        warnings.add('المبلغ صفر - هل هذا مقصود؟');
      }
      
      if (amountChanged.abs() > 1000000000) {
        errors.add('المبلغ كبير جداً (أكثر من مليار)');
      }
      
      // 3. التحقق من نوع المعاملة
      final validTypes = ['manual_debt', 'manual_payment', 'invoice_debt', 'opening_balance', 'return_payment', 'SETTLEMENT', 'invoice_live_update', 'Invoice_Debt_Reversal'];
      if (!validTypes.contains(transactionType)) {
        warnings.add('نوع المعاملة غير معروف: $transactionType');
      }
      
      // 4. التحقق من أن التسديد لا يتجاوز الدين (للمدفوعات فقط)
      if (amountChanged < 0 && transactionType == 'manual_payment') {
        final newBalance = customer.currentTotalDebt + amountChanged;
        if (newBalance < -0.01) {
          warnings.add('التسديد سيجعل الرصيد سالباً (${newBalance.toStringAsFixed(2)})');
        }
      }
      
      // 5. التحقق من سلامة بيانات العميل الحالية
      final integrityReport = await verifyCustomerFinancialIntegrity(customerId);
      if (!integrityReport.isHealthy) {
        warnings.add('تحذير: بيانات العميل تحتاج إصلاح قبل إضافة معاملات جديدة');
      }
      
      return TransactionValidationResult(
        isValid: errors.isEmpty,
        errors: errors,
        warnings: warnings,
        currentBalance: customer.currentTotalDebt,
        expectedNewBalance: customer.currentTotalDebt + amountChanged,
      );
    } catch (e) {
      errors.add('خطأ في التحقق: $e');
      return TransactionValidationResult(isValid: false, errors: errors, warnings: warnings);
    }
  }

  /// إدراج معاملة مع تحقق مُحسّن (بديل آمن لـ insertTransaction)
  Future<int> insertTransactionSafe(DebtTransaction transaction) async {
    // 1. التحقق أولاً
    final validation = await validateTransactionBeforeInsert(
      customerId: transaction.customerId,
      amountChanged: transaction.amountChanged,
      transactionType: transaction.transactionType,
    );
    
    if (!validation.isValid) {
      throw Exception('فشل التحقق: ${validation.errors.join(', ')}');
    }
    
    // 2. طباعة التحذيرات إن وجدت
    for (final warning in validation.warnings) {
      print('⚠️ تحذير: $warning');
    }
    
    // 3. إدراج المعاملة
    return await insertTransaction(transaction);
  }

  /// التحقق من صحة فاتورة قبل حفظها
  Future<InvoiceValidationResult> validateInvoiceBeforeSave({
    required double totalAmount,
    required double discount,
    required double amountPaid,
    required String paymentType,
    required List<Map<String, dynamic>> items,
  }) async {
    final List<String> errors = [];
    final List<String> warnings = [];
    
    // 1. التحقق من المبالغ
    if (totalAmount <= 0) {
      errors.add('إجمالي الفاتورة يجب أن يكون أكبر من صفر');
    }
    
    if (discount < 0) {
      errors.add('الخصم لا يمكن أن يكون سالباً');
    }
    
    if (discount >= totalAmount) {
      errors.add('الخصم لا يمكن أن يكون أكبر من أو يساوي الإجمالي');
    }
    
    if (amountPaid < 0) {
      errors.add('المبلغ المدفوع لا يمكن أن يكون سالباً');
    }
    
    // 2. التحقق من البنود
    if (items.isEmpty) {
      errors.add('الفاتورة يجب أن تحتوي على بند واحد على الأقل');
    }
    
    // 3. التحقق من تطابق المجموع
    double calculatedTotal = 0;
    for (final item in items) {
      final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0;
      calculatedTotal += itemTotal;
    }
    
    // ملاحظة: totalAmount قد يشمل رسوم التحميل، لذا نتحقق من الفرق المعقول
    final totalDiff = (calculatedTotal - totalAmount).abs();
    if (totalDiff > 1000000) { // فرق كبير جداً
      warnings.add('فرق كبير بين مجموع البنود والإجمالي');
    }
    
    // 4. التحقق من نوع الدفع
    if (paymentType == 'نقد' && amountPaid < (totalAmount - discount)) {
      warnings.add('المبلغ المدفوع أقل من الإجمالي في فاتورة نقدية');
    }
    
    return InvoiceValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      calculatedTotal: calculatedTotal,
    );
  }

  /// إنشاء نسخة احتياطية من بيانات عميل معين (JSON)
  Future<Map<String, dynamic>> backupCustomerData(int customerId) async {
    final db = await database;
    
    final customer = await getCustomerById(customerId);
    if (customer == null) {
      throw Exception('العميل غير موجود');
    }
    
    final transactions = await getCustomerTransactions(customerId, orderBy: 'transaction_date ASC, id ASC');
    
    // جلب الفواتير المرتبطة
    final invoices = await db.query(
      'invoices',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'invoice_date ASC',
    );
    
    return {
      'backup_date': DateTime.now().toIso8601String(),
      'customer': customer.toMap(),
      'transactions': transactions.map((t) => t.toMap()).toList(),
      'invoices': invoices,
      'calculated_balance': transactions.fold(0.0, (sum, t) => sum + t.amountChanged),
    };
  }

  /// التحقق الدوري التلقائي (يمكن استدعاؤها عند بدء التطبيق)
  Future<PeriodicCheckResult> performPeriodicIntegrityCheck() async {
    final startTime = DateTime.now();
    int customersChecked = 0;
    int issuesFound = 0;
    int issuesFixed = 0;
    final List<String> details = [];
    
    try {
      final customers = await getAllCustomers();
      customersChecked = customers.length;
      
      for (final customer in customers) {
        if (customer.id == null) continue;
        
        final report = await verifyCustomerFinancialIntegrity(customer.id!);
        
        if (!report.isHealthy) {
          issuesFound++;
          details.add('${customer.name}: ${report.issues.join(', ')}');
          
          // إصلاح تلقائي
          await recalculateAndApplyCustomerDebt(customer.id!);
          await recalculateCustomerTransactionBalances(customer.id!);
          issuesFixed++;
        }
      }
      
      final duration = DateTime.now().difference(startTime);
      
      return PeriodicCheckResult(
        checkDate: startTime,
        duration: duration,
        customersChecked: customersChecked,
        issuesFound: issuesFound,
        issuesFixed: issuesFixed,
        details: details,
        success: true,
      );
    } catch (e) {
      return PeriodicCheckResult(
        checkDate: startTime,
        duration: DateTime.now().difference(startTime),
        customersChecked: customersChecked,
        issuesFound: issuesFound,
        issuesFixed: issuesFixed,
        details: ['خطأ: $e'],
        success: false,
      );
    }
  }

  /// حساب ملخص مالي سريع للتطبيق
  Future<FinancialSummary> getFinancialSummary() async {
    final db = await database;
    
    // إجمالي ديون العملاء
    final debtResult = await db.rawQuery(
      'SELECT COALESCE(SUM(current_total_debt), 0) AS total FROM customers WHERE current_total_debt > 0'
    );
    final totalCustomerDebt = ((debtResult.first['total'] as num?) ?? 0).toDouble();
    
    // إجمالي الأرصدة الدائنة (عملاء لهم رصيد سالب)
    final creditResult = await db.rawQuery(
      'SELECT COALESCE(SUM(ABS(current_total_debt)), 0) AS total FROM customers WHERE current_total_debt < 0'
    );
    final totalCustomerCredit = ((creditResult.first['total'] as num?) ?? 0).toDouble();
    
    // عدد العملاء
    final customerCountResult = await db.rawQuery('SELECT COUNT(*) AS cnt FROM customers');
    final totalCustomers = (customerCountResult.first['cnt'] as int?) ?? 0;
    
    // عدد العملاء المدينين
    final debtorCountResult = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM customers WHERE current_total_debt > 0'
    );
    final debtorCount = (debtorCountResult.first['cnt'] as int?) ?? 0;
    
    // إجمالي الفواتير
    final invoiceResult = await db.rawQuery(
      "SELECT COUNT(*) AS cnt, COALESCE(SUM(total_amount), 0) AS total FROM invoices WHERE status = 'محفوظة'"
    );
    final totalInvoices = (invoiceResult.first['cnt'] as int?) ?? 0;
    final totalInvoiceAmount = ((invoiceResult.first['total'] as num?) ?? 0).toDouble();
    
    return FinancialSummary(
      totalCustomerDebt: totalCustomerDebt,
      totalCustomerCredit: totalCustomerCredit,
      totalCustomers: totalCustomers,
      debtorCount: debtorCount,
      totalInvoices: totalInvoices,
      totalInvoiceAmount: totalInvoiceAmount,
      generatedAt: DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // دوال سجل التدقيق المالي (Financial Audit Log)
  // ═══════════════════════════════════════════════════════════════════════════

  /// إدراج سجل تدقيق
  Future<int> insertAuditLog({
    required String operationType,
    required String entityType,
    required int entityId,
    String? oldValues,
    String? newValues,
    String? notes,
  }) async {
    final db = await database;
    try {
      return await db.insert('financial_audit_log', {
        'operation_type': operationType,
        'entity_type': entityType,
        'entity_id': entityId,
        'old_values': oldValues,
        'new_values': newValues,
        'notes': notes,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('خطأ في إدراج سجل التدقيق: $e');
      return 0;
    }
  }

  /// جلب سجل التدقيق لكيان معين
  Future<List<Map<String, dynamic>>> getAuditLogForEntity(
    String entityType,
    int entityId,
  ) async {
    final db = await database;
    try {
      return await db.query(
        'financial_audit_log',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType, entityId],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      print('خطأ في جلب سجل التدقيق: $e');
      return [];
    }
  }

  /// جلب سجل التدقيق لفترة زمنية
  Future<List<Map<String, dynamic>>> getAuditLogForPeriod(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;
    try {
      return await db.query(
        'financial_audit_log',
        where: 'created_at >= ? AND created_at <= ?',
        whereArgs: [
          startDate.toIso8601String(),
          endDate.toIso8601String(),
        ],
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      print('خطأ في جلب سجل التدقيق للفترة: $e');
      return [];
    }
  }

  /// جلب آخر العمليات المالية
  Future<List<Map<String, dynamic>>> getRecentAuditLogs({int limit = 50}) async {
    final db = await database;
    try {
      return await db.query(
        'financial_audit_log',
        orderBy: 'created_at DESC',
        limit: limit,
      );
    } catch (e) {
      print('خطأ في جلب آخر العمليات: $e');
      return [];
    }
  }

  /// حذف سجلات التدقيق القديمة (أقدم من 6 أشهر)
  Future<int> cleanOldAuditLogs() async {
    final db = await database;
    try {
      final sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));
      return await db.delete(
        'financial_audit_log',
        where: 'created_at < ?',
        whereArgs: [sixMonthsAgo.toIso8601String()],
      );
    } catch (e) {
      print('خطأ في حذف سجلات التدقيق القديمة: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📸 دوال نسخ الفواتير (Invoice Snapshots)
  // ═══════════════════════════════════════════════════════════════════════════

  /// حفظ نسخة من الفاتورة قبل التعديل
  Future<int> saveInvoiceSnapshot({
    required int invoiceId,
    required String snapshotType, // 'original', 'before_edit', 'after_edit'
    String? notes,
  }) async {
    final db = await database;
    try {
      // جلب بيانات الفاتورة الحالية
      final invoiceMaps = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
      if (invoiceMaps.isEmpty) {
        throw Exception('الفاتورة غير موجودة');
      }
      final invoice = invoiceMaps.first;
      
      // جلب أصناف الفاتورة
      final items = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      final itemsJson = jsonEncode(items);
      
      // حساب رقم النسخة
      final existingSnapshots = await db.query(
        'invoice_snapshots',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'version_number DESC',
        limit: 1,
      );
      final versionNumber = existingSnapshots.isEmpty 
          ? 1 
          : ((existingSnapshots.first['version_number'] as int?) ?? 0) + 1;
      
      // حفظ النسخة
      return await db.insert('invoice_snapshots', {
        'invoice_id': invoiceId,
        'version_number': versionNumber,
        'snapshot_type': snapshotType,
        'customer_name': invoice['customer_name'],
        'customer_phone': invoice['customer_phone'],
        'customer_address': invoice['customer_address'],
        'invoice_date': invoice['invoice_date'],
        'payment_type': invoice['payment_type'],
        'total_amount': invoice['total_amount'],
        'discount': invoice['discount'],
        'amount_paid': invoice['amount_paid_on_invoice'],
        'loading_fee': invoice['loading_fee'],
        'items_json': itemsJson,
        'created_at': DateTime.now().toIso8601String(),
        'notes': notes,
      });
    } catch (e) {
      print('خطأ في حفظ نسخة الفاتورة: $e');
      return -1;
    }
  }

  /// جلب جميع نسخ فاتورة معينة
  Future<List<Map<String, dynamic>>> getInvoiceSnapshots(int invoiceId) async {
    final db = await database;
    try {
      return await db.query(
        'invoice_snapshots',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'version_number ASC',
      );
    } catch (e) {
      print('خطأ في جلب نسخ الفاتورة: $e');
      return [];
    }
  }

  /// التحقق من وجود تعديلات على الفاتورة
  Future<bool> hasInvoiceBeenModified(int invoiceId) async {
    final db = await database;
    try {
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM invoice_snapshots WHERE invoice_id = ?',
        [invoiceId],
      ));
      return (count ?? 0) > 0;
    } catch (e) {
      return false;
    }
  }

  /// جلب عدد التعديلات على الفاتورة
  Future<int> getInvoiceModificationCount(int invoiceId) async {
    final db = await database;
    try {
      final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM invoice_snapshots WHERE invoice_id = ?',
        [invoiceId],
      ));
      return count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔐 نظام Checksums للتحقق من سلامة البيانات
  // ═══════════════════════════════════════════════════════════════════════════

  /// حساب checksum لفاتورة معينة
  String calculateInvoiceChecksum(Map<String, dynamic> invoice, List<Map<String, dynamic>> items) {
    // بناء سلسلة من البيانات الحرجة
    final buffer = StringBuffer();
    buffer.write(invoice['id'] ?? 0);
    buffer.write('|');
    buffer.write(invoice['total_amount'] ?? 0);
    buffer.write('|');
    buffer.write(invoice['discount'] ?? 0);
    buffer.write('|');
    buffer.write(invoice['amount_paid_on_invoice'] ?? 0);
    buffer.write('|');
    buffer.write(invoice['customer_id'] ?? 0);
    buffer.write('|');
    
    // إضافة مجموع الأصناف
    double itemsTotal = 0;
    for (final item in items) {
      itemsTotal += (item['item_total'] as num?)?.toDouble() ?? 0;
    }
    buffer.write(itemsTotal.toStringAsFixed(2));
    
    // حساب hash بسيط
    final data = buffer.toString();
    int hash = 0;
    for (int i = 0; i < data.length; i++) {
      hash = ((hash << 5) - hash) + data.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF; // تحويل إلى 32-bit
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// التحقق من صحة checksum لفاتورة
  Future<bool> verifyInvoiceChecksum(int invoiceId) async {
    final db = await database;
    try {
      final invoiceMaps = await db.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
      if (invoiceMaps.isEmpty) return false;
      
      final items = await db.query('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
      
      // حساب checksum الحالي
      final currentChecksum = calculateInvoiceChecksum(invoiceMaps.first, items);
      
      // التحقق من تطابق المجاميع
      final invoice = invoiceMaps.first;
      final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0;
      
      double itemsTotal = 0;
      for (final item in items) {
        itemsTotal += (item['item_total'] as num?)?.toDouble() ?? 0;
      }
      
      // السماح بفرق بسيط بسبب أجور التحميل
      final loadingFee = (invoice['loading_fee'] as num?)?.toDouble() ?? 0;
      final discount = (invoice['discount'] as num?)?.toDouble() ?? 0;
      final expectedTotal = itemsTotal + loadingFee - discount;
      
      // التحقق من التطابق (مع هامش صغير للأخطاء العشرية)
      return (totalAmount - expectedTotal).abs() < 0.01;
    } catch (e) {
      print('خطأ في التحقق من checksum: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📊 نظام المطابقة اليومية التلقائية (Daily Reconciliation)
  // ═══════════════════════════════════════════════════════════════════════════

  /// تنفيذ المطابقة اليومية الشاملة
  Future<DailyReconciliationResult> performDailyReconciliation() async {
    final startTime = DateTime.now();
    final List<String> issues = [];
    final List<String> fixes = [];
    int customersChecked = 0;
    int invoicesChecked = 0;
    int issuesFound = 0;
    int issuesFixed = 0;
    
    try {
      final db = await database;
      
      // 1. التحقق من أرصدة العملاء
      print('🔍 بدء المطابقة اليومية...');
      final customers = await getAllCustomers();
      customersChecked = customers.length;
      
      for (final customer in customers) {
        if (customer.id == null) continue;
        
        // حساب الرصيد من المعاملات
        final transactions = await getCustomerTransactions(customer.id!, orderBy: 'id ASC');
        double calculatedBalance = 0;
        for (final tx in transactions) {
          calculatedBalance += tx.amountChanged;
        }
        
        // مقارنة مع الرصيد المسجل
        if ((calculatedBalance - customer.currentTotalDebt).abs() > 0.01) {
          issuesFound++;
          issues.add('العميل ${customer.name}: الرصيد المسجل (${customer.currentTotalDebt.toStringAsFixed(2)}) لا يتطابق مع المحسوب (${calculatedBalance.toStringAsFixed(2)})');
          
          // إصلاح تلقائي
          await recalculateAndApplyCustomerDebt(customer.id!);
          issuesFixed++;
          fixes.add('تم إصلاح رصيد العميل ${customer.name}');
        }
      }
      
      // 2. التحقق من الفواتير
      final invoices = await db.query('invoices', where: "status = 'محفوظة'");
      invoicesChecked = invoices.length;
      
      for (final invoice in invoices) {
        final invoiceId = invoice['id'] as int;
        final isValid = await verifyInvoiceChecksum(invoiceId);
        
        if (!isValid) {
          issuesFound++;
          issues.add('الفاتورة رقم $invoiceId: مجموع الأصناف لا يتطابق مع الإجمالي');
          // لا نصلح الفواتير تلقائياً، فقط نسجل المشكلة
        }
      }
      
      // 3. التحقق من تسلسل المعاملات
      for (final customer in customers) {
        if (customer.id == null) continue;
        
        final transactions = await getCustomerTransactions(customer.id!, orderBy: 'transaction_date ASC, id ASC');
        double runningBalance = 0;
        
        for (int i = 0; i < transactions.length; i++) {
          final tx = transactions[i];
          final expectedBalanceAfter = MoneyCalculator.add(runningBalance, tx.amountChanged);
          
          if (tx.newBalanceAfterTransaction != null && 
              (tx.newBalanceAfterTransaction! - expectedBalanceAfter).abs() > 0.01) {
            issuesFound++;
            issues.add('معاملة ${tx.id} للعميل ${customer.name}: الرصيد بعد المعاملة غير صحيح');
            
            // إصلاح تلقائي
            await recalculateCustomerTransactionBalances(customer.id!);
            issuesFixed++;
            fixes.add('تم إصلاح تسلسل معاملات العميل ${customer.name}');
            break; // الإصلاح يشمل كل المعاملات
          }
          
          runningBalance = expectedBalanceAfter;
        }
      }
      
      final duration = DateTime.now().difference(startTime);
      print('✅ انتهت المطابقة اليومية في ${duration.inSeconds} ثانية');
      print('   - العملاء: $customersChecked');
      print('   - الفواتير: $invoicesChecked');
      print('   - المشاكل: $issuesFound');
      print('   - الإصلاحات: $issuesFixed');
      
      // تسجيل في سجل التدقيق
      await insertAuditLog(
        operationType: 'daily_reconciliation',
        entityType: 'system',
        entityId: 0,
        notes: 'المطابقة اليومية: $customersChecked عميل، $invoicesChecked فاتورة، $issuesFound مشكلة، $issuesFixed إصلاح',
      );
      
      return DailyReconciliationResult(
        date: startTime,
        duration: duration,
        customersChecked: customersChecked,
        invoicesChecked: invoicesChecked,
        issuesFound: issuesFound,
        issuesFixed: issuesFixed,
        issues: issues,
        fixes: fixes,
        success: true,
      );
    } catch (e) {
      print('❌ خطأ في المطابقة اليومية: $e');
      return DailyReconciliationResult(
        date: startTime,
        duration: DateTime.now().difference(startTime),
        customersChecked: customersChecked,
        invoicesChecked: invoicesChecked,
        issuesFound: issuesFound,
        issuesFixed: issuesFixed,
        issues: [...issues, 'خطأ: $e'],
        fixes: fixes,
        success: false,
      );
    }
  }

  /// التحقق السريع من سلامة البيانات (للاستخدام عند بدء التطبيق)
  Future<QuickIntegrityCheckResult> performQuickIntegrityCheck() async {
    final startTime = DateTime.now();
    bool isHealthy = true;
    final List<String> warnings = [];
    
    try {
      final db = await database;
      
      // 1. التحقق من سلامة قاعدة البيانات
      final integrityCheck = await db.rawQuery('PRAGMA integrity_check;');
      final dbIntegrity = integrityCheck.first.values.first == 'ok';
      if (!dbIntegrity) {
        isHealthy = false;
        warnings.add('قاعدة البيانات تحتاج إصلاح');
      }
      
      // 2. التحقق من وجود عملاء بأرصدة غير منطقية
      final negativeDebtCustomers = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM customers WHERE current_total_debt < -1000000'
      );
      final negativeCount = (negativeDebtCustomers.first['cnt'] as int?) ?? 0;
      if (negativeCount > 0) {
        warnings.add('يوجد $negativeCount عميل برصيد سالب كبير');
      }
      
      // 3. التحقق من وجود فواتير بدون أصناف
      final emptyInvoices = await db.rawQuery('''
        SELECT COUNT(*) as cnt FROM invoices i 
        WHERE status = 'محفوظة' 
        AND NOT EXISTS (SELECT 1 FROM invoice_items ii WHERE ii.invoice_id = i.id)
      ''');
      final emptyCount = (emptyInvoices.first['cnt'] as int?) ?? 0;
      if (emptyCount > 0) {
        warnings.add('يوجد $emptyCount فاتورة محفوظة بدون أصناف');
      }
      
      // 4. التحقق من وجود معاملات يتيمة (بدون عميل)
      final orphanTransactions = await db.rawQuery('''
        SELECT COUNT(*) as cnt FROM transactions t 
        WHERE NOT EXISTS (SELECT 1 FROM customers c WHERE c.id = t.customer_id)
      ''');
      final orphanCount = (orphanTransactions.first['cnt'] as int?) ?? 0;
      if (orphanCount > 0) {
        warnings.add('يوجد $orphanCount معاملة بدون عميل');
      }
      
      // ═══════════════════════════════════════════════════════════════════════════
      // 🔒 تحسين الأمان: التحقق من تسلسل المعاملات (Chain Verification)
      // ═══════════════════════════════════════════════════════════════════════════
      // 5. التحقق من أن رصيد كل عميل يتطابق مع آخر معاملة له
      final balanceMismatch = await db.rawQuery('''
        SELECT c.id, c.name, c.current_total_debt as recorded_balance,
               (SELECT new_balance_after_transaction 
                FROM transactions 
                WHERE customer_id = c.id 
                ORDER BY transaction_date DESC, id DESC 
                LIMIT 1) as last_tx_balance
        FROM customers c
        WHERE c.current_total_debt != 0
        AND EXISTS (SELECT 1 FROM transactions WHERE customer_id = c.id)
        AND ABS(c.current_total_debt - 
               COALESCE((SELECT new_balance_after_transaction 
                         FROM transactions 
                         WHERE customer_id = c.id 
                         ORDER BY transaction_date DESC, id DESC 
                         LIMIT 1), 0)) > 0.01
        LIMIT 10
      ''');
      
      if (balanceMismatch.isNotEmpty) {
        isHealthy = false;
        for (final row in balanceMismatch) {
          final name = row['name'] as String? ?? 'غير معروف';
          final recorded = (row['recorded_balance'] as num?)?.toDouble() ?? 0;
          final lastTx = (row['last_tx_balance'] as num?)?.toDouble() ?? 0;
          warnings.add('عدم تطابق رصيد العميل "$name": مسجل=$recorded، آخر معاملة=$lastTx');
        }
      }
      
      // 6. التحقق من وجود معاملات بأرصدة غير منطقية
      final brokenChain = await db.rawQuery('''
        SELECT COUNT(*) as cnt FROM transactions 
        WHERE balance_before_transaction IS NULL 
           OR new_balance_after_transaction IS NULL
      ''');
      final brokenCount = (brokenChain.first['cnt'] as int?) ?? 0;
      if (brokenCount > 0) {
        warnings.add('يوجد $brokenCount معاملة بدون أرصدة مسجلة');
      }
      
      final duration = DateTime.now().difference(startTime);
      
      return QuickIntegrityCheckResult(
        checkDate: startTime,
        duration: duration,
        isHealthy: isHealthy && warnings.isEmpty,
        warnings: warnings,
        databaseIntegrity: dbIntegrity,
      );
    } catch (e) {
      return QuickIntegrityCheckResult(
        checkDate: startTime,
        duration: DateTime.now().difference(startTime),
        isHealthy: false,
        warnings: ['خطأ في الفحص: $e'],
        databaseIntegrity: false,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 📄 دوال أرشيف سندات القبض للعملاء
  // ═══════════════════════════════════════════════════════════════════════════

  /// الحصول على رقم سند القبض التالي للعميل
  Future<int> getNextCustomerReceiptNumber() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(receipt_number) as max_num FROM customer_receipt_vouchers'
    );
    final maxNum = result.first['max_num'] as int?;
    return (maxNum ?? 0) + 1;
  }

  /// حفظ سند قبض جديد للعميل
  Future<int> insertCustomerReceiptVoucher(CustomerReceiptVoucher receipt) async {
    final db = await database;
    final map = receipt.toMap();
    map.remove('id'); // إزالة id لأنه auto-increment
    return await db.insert('customer_receipt_vouchers', map);
  }

  /// الحصول على جميع سندات القبض لعميل معين
  Future<List<CustomerReceiptVoucher>> getCustomerReceiptVouchers(int customerId) async {
    final db = await database;
    final results = await db.query(
      'customer_receipt_vouchers',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
    return results.map((map) => CustomerReceiptVoucher.fromMap(map)).toList();
  }

  /// الحصول على سند قبض بواسطة ID
  Future<CustomerReceiptVoucher?> getCustomerReceiptVoucherById(int id) async {
    final db = await database;
    final results = await db.query(
      'customer_receipt_vouchers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return CustomerReceiptVoucher.fromMap(results.first);
  }

  /// حذف سند قبض
  Future<int> deleteCustomerReceiptVoucher(int id) async {
    final db = await database;
    return await db.delete(
      'customer_receipt_vouchers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// الحصول على عدد سندات القبض لعميل معين
  Future<int> getCustomerReceiptVouchersCount(int customerId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM customer_receipt_vouchers WHERE customer_id = ?',
      [customerId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

} // نهاية كلاس DatabaseService

// ═══════════════════════════════════════════════════════════════════════════
// 🛡️ نماذج البيانات للحماية والتدقيق المالي
// ═══════════════════════════════════════════════════════════════════════════

/// تقرير سلامة البيانات المالية
class FinancialIntegrityReport {
  final int customerId;
  final String customerName; // اسم العميل
  final bool isHealthy;
  final List<String> issues;
  final List<String> warnings;
  final double calculatedBalance;
  final double recordedBalance;
  final int transactionCount;

  FinancialIntegrityReport({
    required this.customerId,
    required this.customerName,
    required this.isHealthy,
    required this.issues,
    required this.warnings,
    required this.calculatedBalance,
    required this.recordedBalance,
    required this.transactionCount,
  });

  @override
  String toString() {
    return 'FinancialIntegrityReport(customerId: $customerId, customerName: $customerName, isHealthy: $isHealthy, issues: ${issues.length}, warnings: ${warnings.length})';
  }
}

/// نتيجة التحقق من المعاملة
class TransactionValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final double? currentBalance;
  final double? expectedNewBalance;

  TransactionValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    this.currentBalance,
    this.expectedNewBalance,
  });
}

/// نتيجة التحقق من الفاتورة
class InvoiceValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final double calculatedTotal;

  InvoiceValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    required this.calculatedTotal,
  });
}

/// نتيجة الفحص الدوري
class PeriodicCheckResult {
  final DateTime checkDate;
  final Duration duration;
  final int customersChecked;
  final int issuesFound;
  final int issuesFixed;
  final List<String> details;
  final bool success;

  PeriodicCheckResult({
    required this.checkDate,
    required this.duration,
    required this.customersChecked,
    required this.issuesFound,
    required this.issuesFixed,
    required this.details,
    required this.success,
  });

  @override
  String toString() {
    return 'PeriodicCheckResult(checked: $customersChecked, issues: $issuesFound, fixed: $issuesFixed, success: $success)';
  }
}

/// ملخص مالي
class FinancialSummary {
  final double totalCustomerDebt;
  final double totalCustomerCredit;
  final int totalCustomers;
  final int debtorCount;
  final int totalInvoices;
  final double totalInvoiceAmount;
  final DateTime generatedAt;

  FinancialSummary({
    required this.totalCustomerDebt,
    required this.totalCustomerCredit,
    required this.totalCustomers,
    required this.debtorCount,
    required this.totalInvoices,
    required this.totalInvoiceAmount,
    required this.generatedAt,
  });
}

// أنواع البيانات لنظام التقارير
class InvoiceWithProductData {
  final Invoice invoice;
  final double quantitySold;
  final double saleUnitsCount;
  final double profit;
  final double sellingPrice;
  final double unitCostAtSale;

  InvoiceWithProductData({
    required this.invoice,
    required this.quantitySold,
    required this.saleUnitsCount,
    required this.profit,
    required this.sellingPrice,
    required this.unitCostAtSale,
  });
}

class PersonYearData {
  final double totalProfit;
  final double totalSales;
  final int totalInvoices;
  final int totalTransactions;
  final double averageSellingPrice;
  final double totalQuantity;

  PersonYearData({
    required this.totalProfit,
    required this.totalSales,
    required this.totalInvoices,
    required this.totalTransactions,
    required this.averageSellingPrice,
    required this.totalQuantity,
  });
}

// إزالة تعريفات مكررة للـ PersonMonthData و MonthlySalesSummary لاستخدام نماذج المجلد models

/// نتيجة المطابقة اليومية
class DailyReconciliationResult {
  final DateTime date;
  final Duration duration;
  final int customersChecked;
  final int invoicesChecked;
  final int issuesFound;
  final int issuesFixed;
  final List<String> issues;
  final List<String> fixes;
  final bool success;

  DailyReconciliationResult({
    required this.date,
    required this.duration,
    required this.customersChecked,
    required this.invoicesChecked,
    required this.issuesFound,
    required this.issuesFixed,
    required this.issues,
    required this.fixes,
    required this.success,
  });

  @override
  String toString() {
    return 'DailyReconciliationResult(date: $date, customers: $customersChecked, invoices: $invoicesChecked, issues: $issuesFound, fixed: $issuesFixed, success: $success)';
  }
  
  /// هل البيانات سليمة 100%؟
  bool get isFullyHealthy => issuesFound == 0;
  
  /// نسبة الأمان
  double get healthPercentage {
    final total = customersChecked + invoicesChecked;
    if (total == 0) return 100.0;
    return ((total - issuesFound) / total) * 100;
  }
}

/// نتيجة الفحص السريع
class QuickIntegrityCheckResult {
  final DateTime checkDate;
  final Duration duration;
  final bool isHealthy;
  final List<String> warnings;
  final bool databaseIntegrity;

  QuickIntegrityCheckResult({
    required this.checkDate,
    required this.duration,
    required this.isHealthy,
    required this.warnings,
    required this.databaseIntegrity,
  });

  @override
  String toString() {
    return 'QuickIntegrityCheckResult(healthy: $isHealthy, warnings: ${warnings.length}, dbIntegrity: $databaseIntegrity)';
  }
}


// ═══════════════════════════════════════════════════════════════════════════
// 📄 دوال أرشيف سندات القبض للعملاء
// ═══════════════════════════════════════════════════════════════════════════

/// نموذج سند القبض للعميل
class CustomerReceiptVoucher {
  final int? id;
  final int receiptNumber;
  final int customerId;
  final String customerName;
  final double beforePayment;
  final double paidAmount;
  final double afterPayment;
  final int? transactionId;
  final String? notes;
  final DateTime createdAt;

  CustomerReceiptVoucher({
    this.id,
    required this.receiptNumber,
    required this.customerId,
    required this.customerName,
    required this.beforePayment,
    required this.paidAmount,
    required this.afterPayment,
    this.transactionId,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'receipt_number': receiptNumber,
      'customer_id': customerId,
      'customer_name': customerName,
      'before_payment': beforePayment,
      'paid_amount': paidAmount,
      'after_payment': afterPayment,
      'transaction_id': transactionId,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory CustomerReceiptVoucher.fromMap(Map<String, dynamic> map) {
    return CustomerReceiptVoucher(
      id: map['id'] as int?,
      receiptNumber: map['receipt_number'] as int,
      customerId: map['customer_id'] as int,
      customerName: map['customer_name'] as String,
      beforePayment: (map['before_payment'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num).toDouble(),
      afterPayment: (map['after_payment'] as num).toDouble(),
      transactionId: map['transaction_id'] as int?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
