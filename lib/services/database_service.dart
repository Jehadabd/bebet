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
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;
  static const int _databaseVersion = 2;

  factory DatabaseService() => _instance;

  DatabaseService._internal();

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
    print('Database operation failed: $e'); // للسجل التقني
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
          final baseCost = costs['قطعة'];
          if (baseCost != null) {
            final multiplier = (item['quantity'] as int).toDouble();
            return baseCost * multiplier;
          }
        }
      }
      
      return 0.0;
    } catch (e) {
      print('Error calculating cost from hierarchy: $e');
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
    _database = await _initDatabase();
    // --- تحقق من وجود العمود قبل محاولة إضافته ---
    final columns = await _database!.rawQuery("PRAGMA table_info(products);");
    final hasUnitHierarchy =
        columns.any((col) => col['name'] == 'unit_hierarchy');
    final hasUnitCosts =
        columns.any((col) => col['name'] == 'unit_costs');
    
    if (!hasUnitHierarchy) {
      try {
        await _database!
            .execute('ALTER TABLE products ADD COLUMN unit_hierarchy TEXT;');
        print('DEBUG: تم إضافة عمود unit_hierarchy بنجاح!');
      } catch (e) {
        print('DEBUG: خطأ أثناء إضافة العمود unit_hierarchy: $e');
      }
    } else {
      print('DEBUG: عمود unit_hierarchy موجود بالفعل، لا حاجة للإضافة.');
    }

    if (!hasUnitCosts) {
      try {
        await _database!
            .execute('ALTER TABLE products ADD COLUMN unit_costs TEXT;');
        print('DEBUG: تم إضافة عمود unit_costs بنجاح!');
      } catch (e) {
        print('DEBUG: خطأ أثناء إضافة العمود unit_costs: $e');
      }
    } else {
      print('DEBUG: عمود unit_costs موجود بالفعل، لا حاجة للإضافة.');
    }

    // تحقق من أعمدة جدول invoice_items وإضافتها إذا لزم
    try {
      final invoiceItemsInfo =
          await _database!.rawQuery('PRAGMA table_info(invoice_items);');
      bool hasActualCostPrice =
          invoiceItemsInfo.any((c) => c['name'] == 'actual_cost_price');
      bool hasSaleType = invoiceItemsInfo.any((c) => c['name'] == 'sale_type');
      bool hasUnitsInLargeUnit =
          invoiceItemsInfo.any((c) => c['name'] == 'units_in_large_unit');
      bool hasUniqueId = invoiceItemsInfo.any((c) => c['name'] == 'unique_id');

      if (!hasActualCostPrice) {
        try {
          await _database!
              .execute('ALTER TABLE invoice_items ADD COLUMN actual_cost_price REAL');
          print('DEBUG DB: actual_cost_price column added successfully to invoice_items table.');
        } catch (e) {
          print("DEBUG DB Error: Failed to add column 'actual_cost_price' to invoice_items table or it already exists: $e");
        }
      }
      if (!hasSaleType) {
        try {
          await _database!
              .execute('ALTER TABLE invoice_items ADD COLUMN sale_type TEXT');
          print('DEBUG DB: sale_type column added successfully to invoice_items table.');
        } catch (e) {
          print("DEBUG DB Error: Failed to add column 'sale_type' to invoice_items table or it already exists: $e");
        }
      }
      if (!hasUnitsInLargeUnit) {
        try {
          await _database!.execute(
              'ALTER TABLE invoice_items ADD COLUMN units_in_large_unit REAL');
          print(
              'DEBUG DB: units_in_large_unit column added successfully to invoice_items table.');
        } catch (e) {
          print(
              "DEBUG DB Error: Failed to add column 'units_in_large_unit' to invoice_items table or it already exists: $e");
        }
      }
      if (!hasUniqueId) {
        try {
          await _database!
              .execute('ALTER TABLE invoice_items ADD COLUMN unique_id TEXT');
          print('DEBUG DB: unique_id column added successfully to invoice_items table.');
        } catch (e) {
          print(
              "DEBUG DB Error: Failed to add column 'unique_id' to invoice_items table or it already exists: $e");
        }
      }
    } catch (e) {
      print('DEBUG DB: Failed to inspect/add invoice_items columns: $e');
    }
    // --- نهاية التحقق ---

    // التحقق من حالة FTS5 وإعادة بناء الفهرس إذا لزم الأمر
    await checkFTSStatus();
    
    // تهيئة العمود المطبع وFTS5 للمنتجات الموجودة
    try {
      await initializeFTSForExistingProducts();
    } catch (e) {
      print('Error initializing FTS: $e');
    }
    
    // إذا كان عدد السجلات في FTS أقل من المنتجات، أعد بناء الفهرس
    try {
      final productCountRes = await _database!.rawQuery('SELECT COUNT(1) as c FROM products;');
      final ftsCountRes = await _database!.rawQuery('SELECT COUNT(1) as c FROM products_fts;');
      
      final int productCount = (productCountRes.first['c'] as int?) ?? 0;
      final int ftsCount = (ftsCountRes.first['c'] as int?) ?? 0;
      
      if (productCount > 0 && ftsCount < productCount) {
        print('Rebuilding FTS index due to missing records');
        await rebuildFTSIndex();
      }

      // اختبار البحث الذكي
      if (productCount > 0) {
        print('Testing smart search functionality...');
        await testSmartSearch();
      }
    } catch (e) {
      print('Error checking FTS counts: $e');
    }

    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dir = await getApplicationSupportDirectory();
    final newPath = join(dir.path, 'debt_book.db');
    final oldPath = join(await getDatabasesPath(), 'debt_book.db');

    print('DEBUG DB: New database path: $newPath');
    print('DEBUG DB: Old database path: $oldPath');

    final oldFile = File(oldPath);
    final newFile = File(newPath);
    if (await oldFile.exists() && !(await newFile.exists())) {
      await oldFile.copy(newPath);
      await oldFile.delete();
    }
    return await openDatabase(
      newPath,
      version: _databaseVersion, // رفع رقم النسخة لتفعيل الترقية وإضافة عمود unique_id
      onCreate: _createDatabase,
      onUpgrade: _onUpgrade,
    );
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
        new_balance_after_transaction REAL NOT NULL,
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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
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
    print(
        'DEBUG DB: Running onUpgrade from version $oldVersion to $newVersion');
    //  ترتيب الترقيات مهم
    if (oldVersion < 2) {
      //  ... (أكواد الترقية السابقة إذا كانت موجودة)
    }
    //  ...
    if (oldVersion < 8) {
      await db
          .execute('ALTER TABLE transactions ADD COLUMN invoice_id INTEGER;');
      //  قد تحتاج لإضافة FOREIGN KEY constraint هنا إذا لم يكن موجودًا من onCreate
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
    if (oldVersion < 2) {
      // إضافة عمود actual_cost_price إلى جدول invoice_items
      try {
        await db.execute('ALTER TABLE invoice_items ADD COLUMN actual_cost_price REAL');
        print('تم إضافة عمود actual_cost_price بنجاح');
      } catch (e) {
        print('العمود موجود بالفعل أو حدث خطأ: $e');
      }
    }
  }

  // --- دوال العملاء ---
  Future<int> insertCustomer(Customer customer) async {
    final db = await database;
    return await db.insert('customers', customer.toMap());
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
      //  قبل حذف العميل، قد ترغب في التعامل مع الفواتير والمعاملات المرتبطة به
      //  مثلاً، هل يتم حذفها أم تبقى؟ حاليًا ON DELETE CASCADE ستحذف المعاملات.
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
  // ... (بقية دوال الفنيين CRUD)

  // --- دوال المعاملات (Transactions) ---
  Future<int> insertTransaction(DebtTransaction transaction) async {
    final db = await database;
    try {
      return await db.insert(
          'transactions', transaction.toMap()); // افترض أن toMap جاهزة
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
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
      return await db.insert('invoices', invoice.toMap());
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
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
          oldInvoice.totalAmount - oldInvoice.amountPaidOnInvoice;
    }

    double newDebtContribution = 0.0;
    if (invoice.paymentType == 'دين') {
      newDebtContribution = invoice.totalAmount - invoice.amountPaidOnInvoice;
    }

    // Calculate the change in debt
    final debtChange = newDebtContribution - oldDebtContribution;

    // Update customer's debt if a customer is linked and there's a debt change
    if (invoice.customerId != null && debtChange != 0) {
      final customer = await getCustomerById(
          invoice.customerId!); // Use the customerId from the invoice
      if (customer != null) {
        final updatedCustomer = customer.copyWith(
          currentTotalDebt: customer.currentTotalDebt + debtChange,
          lastModifiedAt: DateTime.now(),
        );
        await updateCustomer(updatedCustomer);

        // Record the debt change transaction
        await insertTransaction(
          DebtTransaction(
            id: null,
            customerId: customer.id!,
            invoiceId: invoice.id!,
            amountChanged:
                debtChange, // Positive for increase, negative for decrease
            transactionDate: DateTime.now(),
            newBalanceAfterTransaction: customer.currentTotalDebt +
                debtChange, // This will be the balance AFTER this transaction
            transactionNote: _generateInvoiceUpdateTransactionNote(
                oldInvoice, invoice, debtChange), // Generate a descriptive note
            transactionType: 'Invoice_Debt_Adjustment',
            createdAt: DateTime.now(),
          ),
        );
      }
    }

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
      return await db.update(
        'invoices',
        invoice.toMap(),
        where: 'id = ?',
        whereArgs: [invoice.id!],
      );
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

    // Update customer's debt if a customer is linked and there was initial debt from this invoice
    if (invoice.customerId != null && debtToReverse > 0) {
      final customer = await getCustomerById(
          invoice.customerId!); // Use the customerId from the invoice
      if (customer != null) {
        final updatedCustomer = customer.copyWith(
          currentTotalDebt: customer.currentTotalDebt - debtToReverse,
          lastModifiedAt: DateTime.now(),
        );
        await updateCustomer(updatedCustomer);

        // Record the debt reversal transaction
        await insertTransaction(
          DebtTransaction(
            id: null,
            customerId: customer.id!,
            invoiceId: id,
            amountChanged: -debtToReverse, // Negative to reverse the debt
            transactionDate: DateTime.now(),
            newBalanceAfterTransaction: customer.currentTotalDebt -
                debtToReverse, // Balance AFTER reversal
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

  Future<List<InvoiceItem>> getInvoiceItems(int invoiceId) async {
    final db = await database;
    return await getInvoiceItemsUsingTransaction(
        db, invoiceId); //  يمكن إعادة استخدام دالة المعاملة
  }

  // --- تقرير المبيعات الشهري ---
  Future<Map<String, MonthlySalesSummary>> getMonthlySalesSummary() async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> invoiceMaps =
          await db.query('invoices', orderBy: 'invoice_date DESC');
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

      final Map<String, MonthlySalesSummary> monthlySummaries = {};

      for (var entry in invoicesByMonth.entries) {
        final monthYear = entry.key;
        final invoicesInMonth = entry.value;

        double totalSales = 0.0;
        double netProfit = 0.0;
        double cashSales = 0.0;
        double creditSalesValue = 0.0;
        double totalReturns = 0.0; // إجمالي الراجع
        double totalDebtPayments = 0.0; // إجمالي تسديد الديون

        for (var invoice in invoicesInMonth) {
          if (invoice.status == 'محفوظة') {
            totalSales += invoice.totalAmount;
            totalReturns += invoice.returnAmount ?? 0; // حساب إجمالي الراجع

            if (invoice.paymentType == 'نقد') {
              cashSales += invoice.totalAmount;
            } else if (invoice.paymentType == 'دين') {
              creditSalesValue += invoice.totalAmount;
            }

            // احسب تكلفة البنود في الفاتورة مع التعامل مع الوحدات
            final items = await getInvoiceItems(invoice.id!);
            double totalCost = 0.0;
            for (final item in items) {
              final double quantityIndividual = item.quantityIndividual ?? 0.0;
              final double quantityLargeUnit = item.quantityLargeUnit ?? 0.0;
              final double unitsInLargeUnit = item.unitsInLargeUnit ?? 1.0;
              final double qty = quantityLargeUnit > 0
                  ? (quantityLargeUnit * unitsInLargeUnit)
                  : quantityIndividual;
              if (item.actualCostPrice != null) {
                totalCost += item.actualCostPrice! * qty;
              } else if (item.costPrice != null) {
                // costPrice هنا تكلفة إجمالية محفوظة للبند
                totalCost += item.costPrice!;
              }
            }

            // صافي المبيعات بعد الراجع مطروحاً منه التكلفة الفعلية
            final netSaleAmount =
                invoice.totalAmount - (invoice.returnAmount ?? 0);
            final profit = netSaleAmount - totalCost;
            netProfit += profit;
          }
        }

        // جمع معاملات تسديد الديون لهذا الشهر
        final year = int.parse(monthYear.split('-')[0]);
        final month = int.parse(monthYear.split('-')[1]);
        final String start =
            '$year-${month.toString().padLeft(2, '0')}-01T00:00:00.000';
        final String end = month == 12
            ? '${year + 1}-01-01T00:00:00.000'
            : '$year-${(month + 1).toString().padLeft(2, '0')}-01T00:00:00.000';
        final List<Map<String, dynamic>> debtTxMaps = await db.query(
          'transactions',
          where:
              "transaction_type = 'Debt_Paid' AND (invoice_id IS NULL OR invoice_id = 0) AND transaction_date >= ? AND transaction_date < ?",
          whereArgs: [start, end],
        );
        for (final tx in debtTxMaps) {
          totalDebtPayments += (tx['amount_changed'] as double).abs();
        }

        monthlySummaries[monthYear] = MonthlySalesSummary(
          monthYear: monthYear,
          totalSales: totalSales,
          netProfit: netProfit,
          cashSales: cashSales,
          creditSales: creditSalesValue,
          totalReturns: totalReturns, // إضافة إجمالي الراجع
          totalDebtPayments: totalDebtPayments, // إضافة إجمالي تسديد الديون
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
      
      // إنشاء استعلام FTS5 - البحث عن أي من الكلمات
      final ftsQuery = terms.map((term) => '$term*').join(' OR ');
      
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

  Future<int> updateProduct(Product product) async {
    final db = await database;
    try {
      // تطبيع اسم المنتج وحفظه في العمود المطبع
      final productMap = product.toMap();
      productMap['name_norm'] = normalizeArabic(product.name);
      
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
      // التحقق من وجود عمود name_norm
      final columns = await db.rawQuery("PRAGMA table_info(products);");
      final hasNameNorm = columns.any((col) => col['name'] == 'name_norm');
      
      if (!hasNameNorm) {
        print('Adding name_norm column to products table...');
        await db.execute('ALTER TABLE products ADD COLUMN name_norm TEXT;');
      }

      // تحديث name_norm لجميع المنتجات الموجودة
      final products = await db.query('products');
      if (products.isNotEmpty) {
        print('Updating name_norm for ${products.length} existing products...');
        
        for (final product in products) {
          final normalizedName = normalizeArabic(product['name'] as String);
          await db.update(
            'products',
            {'name_norm': normalizedName},
            where: 'id = ?',
            whereArgs: [product['id']],
          );
        }
        print('All products updated with normalized names');
      }

      // التحقق من وجود جدول FTS5
      final ftsTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='products_fts'"
      );
      
      if (ftsTable.isEmpty) {
        print('FTS5 table does not exist, creating it...');
        await db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS products_fts USING fts5(
            name_norm,
            content='products',
            content_rowid='id',
            tokenize = 'unicode61 remove_diacritics 2'
          )
        ''');
      }

      // إدراج جميع المنتجات في FTS5
      if (products.isNotEmpty) {
        await db.execute('DELETE FROM products_fts'); // مسح المحتوى القديم
        
        for (final product in products) {
          final normalizedName = product['name_norm'] ?? normalizeArabic(product['name'] as String);
          await db.execute(
            'INSERT INTO products_fts(rowid, name_norm) VALUES (?, ?)',
            [product['id'], normalizedName]
          );
        }
        
        print('FTS5 initialized with ${products.length} existing products');
      }
    } catch (e) {
      print('Error initializing FTS for existing products: $e');
    }
  }

  /// دالة اختبار للبحث الذكي
  Future<void> testSmartSearch() async {
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
          p.unit
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
        JOIN products p ON ii.product_name = p.name
        WHERE p.id = ? AND i.status = 'محفوظة'
      ''', [productId]);
 
      double totalQuantity = 0.0;
      double totalProfit = 0.0;
      double totalSales = 0.0;
      double averageSellingPrice = 0.0;
      double totalCost = 0.0;
 
      for (final item in itemMaps) {
        final double quantityIndividual =
            (item['quantity_individual'] ?? 0.0) as double;
        final double quantityLargeUnit =
            (item['quantity_large_unit'] ?? 0.0) as double;
        final double unitsInLargeUnit =
            (item['units_in_large_unit'] ?? 1.0) as double;
        
        // تحديد نوع البيع والكمية
        String saleUnit = 'قطعة'; // افتراضي
        double currentItemTotalQuantity = 0.0;
        
        if (quantityLargeUnit > 0) {
          // البيع بوحدة كبيرة (كرتون، باكيت، إلخ)
          currentItemTotalQuantity = quantityLargeUnit * unitsInLargeUnit;
          saleUnit = item['sale_type'] ?? 'قطعة';
        } else {
          // البيع بالقطعة
          currentItemTotalQuantity = quantityIndividual;
          saleUnit = item['unit'] ?? 'قطعة';
        }
        
        final sellingPrice = (item['applied_price'] ?? 0.0) as double;
        
        // حساب التكلفة بناءً على النظام الهرمي
        double costPrice = 0.0;
        
        // محاولة استخدام التكلفة المحسوبة مسبقاً
        if (item['actual_cost_price'] != null) {
          costPrice = (item['actual_cost_price'] as double);
        } else if (item['cost_price'] != null) {
          costPrice = (item['cost_price'] as double);
        } else {
          // حساب التكلفة من النظام الهرمي
          costPrice = _calculateCostFromHierarchy(
            item['unit_hierarchy'],
            item['unit_costs'],
            saleUnit,
            currentItemTotalQuantity,
          );
        }
        
        totalQuantity += currentItemTotalQuantity;
        
        // حساب التكلفة الإجمالية بناءً على الوحدات المباعة
        if (quantityLargeUnit > 0) {
          totalCost += costPrice * quantityLargeUnit;
        } else {
          totalCost += costPrice * quantityIndividual;
        }
        
        // حساب الربح والمبيعات بناءً على الوحدة المباعة نفسها
        if (quantityLargeUnit > 0) {
          // البيع بوحدة كبيرة (كرتون، باكيت، إلخ)
          totalProfit += (sellingPrice - costPrice) * quantityLargeUnit;
          totalSales += sellingPrice * quantityLargeUnit;
          averageSellingPrice += sellingPrice * quantityLargeUnit;
        } else {
          // البيع بالقطعة
          totalProfit += (sellingPrice - costPrice) * quantityIndividual;
          totalSales += sellingPrice * quantityIndividual;
          averageSellingPrice += sellingPrice * quantityIndividual;
        }
      }
 
      // حساب متوسط سعر البيع
      if (totalQuantity > 0) {
        averageSellingPrice = averageSellingPrice / totalQuantity;
      }
 
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
                  THEN ii.quantity_large_unit
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

        double totalQuantity = 0.0;
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
          // استخدام actual_cost_price إذا كان متوفراً، وإلا استخدم cost_price أو product_cost_price
          final costPrice = (item['actual_cost_price'] ?? 
                            item['cost_price'] ?? 
                            item['product_cost_price'] ?? 0.0) as double;
          
          // إضافة الكمية الإجمالية (بالوحدات الأساسية) للمعرض
          totalQuantity += currentItemTotalQuantity;
          
          // حساب المبيعات والتكلفة بناءً على الوحدات المباعة
          if (quantityLargeUnit > 0) {
            totalSelling += sellingPrice * quantityLargeUnit;
            totalCost += costPrice * quantityLargeUnit;
          } else {
            totalSelling += sellingPrice * quantityIndividual;
            totalCost += costPrice * quantityIndividual;
          }
        }

        final double avgSellingPrice =
            totalQuantity > 0 ? (totalSelling / totalQuantity) : 0.0;
        final double avgUnitCost =
            totalQuantity > 0 ? (totalCost / totalQuantity) : 0.0;
        final double profit = totalSelling - totalCost;

        invoices.add(InvoiceWithProductData(
          invoice: invoice,
          quantitySold: totalQuantity,
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

  // دوال تقارير الأشخاص
  Future<Map<String, dynamic>> getCustomerProfitData(int customerId) async {
    final db = await database;
    try {
      // جلب بيانات الفواتير (المحفوظة فقط)
      final List<Map<String, dynamic>> invoiceMaps = await db.rawQuery('''
        SELECT 
          SUM(total_amount) as total_sales,
          COUNT(*) as total_invoices
        FROM invoices
        WHERE customer_id = ? AND status = 'محفوظة'
      ''', [customerId]);
 
      // جلب بيانات المعاملات المالية
      final List<Map<String, dynamic>> transactionMaps = await db.rawQuery('''
        SELECT 
          COUNT(*) as total_transactions
        FROM transactions
        WHERE customer_id = ?
      ''', [customerId]);
 
      // حساب الأرباح من الفواتير (المحفوظة فقط) وبمعادلة كمية مصححة
      final List<Map<String, dynamic>> profitMaps = await db.rawQuery('''
        SELECT 
          SUM((ii.applied_price - COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0)) * 
              (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE COALESCE(ii.quantity_individual, 0.0) END)) as total_profit,
          SUM(ii.applied_price * (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE COALESCE(ii.quantity_individual, 0.0) END)) as total_selling_price,
          SUM(CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE COALESCE(ii.quantity_individual, 0.0) END) as total_quantity
        FROM invoices i
        JOIN invoice_items ii ON i.id = ii.invoice_id
        JOIN products p ON ii.product_name = p.name
        WHERE i.customer_id = ? AND i.status = 'محفوظة'
      ''', [customerId]);
 
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
 
      return {
        'totalSales': totalSales,
        'totalProfit': totalProfit,
        'totalInvoices': totalInvoices,
        'totalTransactions': totalTransactions,
        'averageSellingPrice': averageSellingPrice,
        'totalQuantity': totalQuantity,
      };
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<Map<int, PersonYearData>> getCustomerYearlyData(int customerId) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          strftime('%Y', i.invoice_date) as year,
          SUM(i.total_amount) as total_sales,
          SUM((ii.applied_price - COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0)) * 
              (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END)) as total_profit,
          COUNT(DISTINCT i.id) as total_invoices,
          COUNT(DISTINCT t.id) as total_transactions,
          SUM(ii.applied_price * (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END)) as total_selling_price,
          SUM(CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END) as total_quantity
        FROM invoices i
        LEFT JOIN invoice_items ii ON i.id = ii.invoice_id
        LEFT JOIN products p ON ii.product_name = p.name
        LEFT JOIN transactions t ON i.customer_id = t.customer_id 
          AND strftime('%Y', i.invoice_date) = strftime('%Y', t.transaction_date)
        WHERE i.customer_id = ? AND i.status = 'محفوظة'
        GROUP BY strftime('%Y', i.invoice_date)
        ORDER BY year DESC
      ''', [customerId]);
 
      final Map<int, PersonYearData> yearlyData = {};
      for (final map in maps) {
        final year = int.parse(map['year'] as String);
        final totalSellingPrice = (map['total_selling_price'] ?? 0.0) as double;
        final totalQuantity = (map['total_quantity'] ?? 0.0) as double;
        
        // حساب متوسط سعر البيع
        double averageSellingPrice = 0.0;
        if (totalQuantity > 0) {
          averageSellingPrice = totalSellingPrice / totalQuantity;
        }
        
        yearlyData[year] = PersonYearData(
          totalProfit: (map['total_profit'] ?? 0.0) as double,
          totalSales: (map['total_sales'] ?? 0.0) as double,
          totalInvoices: (map['total_invoices'] ?? 0) as int,
          totalTransactions: (map['total_transactions'] ?? 0) as int,
          averageSellingPrice: averageSellingPrice,
          totalQuantity: totalQuantity,
        );
      }
 
      return yearlyData;
    } catch (e) {
      throw Exception(_handleDatabaseError(e));
    }
  }

  Future<Map<int, PersonMonthData>> getCustomerMonthlyData(
      int customerId, int year) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          strftime('%m', i.invoice_date) as month,
          SUM(i.total_amount) as total_sales,
          SUM((ii.applied_price - COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0)) * 
              (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END)) as total_profit,
          COUNT(DISTINCT i.id) as total_invoices,
          COUNT(DISTINCT t.id) as total_transactions,
          SUM(ii.applied_price * (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END)) as total_selling_price,
          SUM(CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE COALESCE(ii.quantity_individual, 0.0) END) as total_quantity
        FROM invoices i
        LEFT JOIN invoice_items ii ON i.id = ii.invoice_id
        LEFT JOIN products p ON ii.product_name = p.name
        LEFT JOIN transactions t ON i.customer_id = t.customer_id 
          AND strftime('%Y', i.invoice_date) = strftime('%Y', t.transaction_date)
          AND strftime('%m', i.invoice_date) = strftime('%m', t.transaction_date)
        WHERE i.customer_id = ? AND strftime('%Y', i.invoice_date) = ? AND i.status = 'محفوظة'
        GROUP BY strftime('%m', i.invoice_date)
        ORDER BY month ASC
      ''', [customerId, year.toString()]);
 
      final Map<int, PersonMonthData> monthlyData = {};
      for (final map in maps) {
        final month = int.parse(map['month'] as String);
        final totalSellingPrice = (map['total_selling_price'] ?? 0.0) as double;
        final totalQuantity = (map['total_quantity'] ?? 0.0) as double;
        
        // حساب متوسط سعر البيع
        double averageSellingPrice = 0.0;
        if (totalQuantity > 0) {
          averageSellingPrice = totalSellingPrice / totalQuantity;
        }
        
        monthlyData[month] = PersonMonthData(
          totalProfit: (map['total_profit'] ?? 0.0) as double,
          totalSales: (map['total_sales'] ?? 0.0) as double,
          totalInvoices: (map['total_invoices'] ?? 0) as int,
          totalTransactions: (map['total_transactions'] ?? 0) as int,
          averageSellingPrice: averageSellingPrice,
          totalQuantity: totalQuantity,
        );
      }
 
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

  /// دالة لحساب ربح المنتج سنويًا
  Future<Map<int, double>> getProductYearlyProfit(int productId) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          strftime('%Y', i.invoice_date) as year,
          SUM((ii.applied_price - COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0)) * 
              (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END)) as total_profit,
          SUM(ii.applied_price * (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END)) as total_selling_price,
          SUM(CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit * COALESCE(ii.units_in_large_unit, 1.0)
                    ELSE ii.quantity_individual END) as total_quantity
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
        final profit = (map['total_profit'] ?? 0.0) as double;
        yearlyProfit[year] = profit;
      }
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
      final List<Map<String, dynamic>> maps = await db.rawQuery('''
        SELECT 
          strftime('%m', i.invoice_date) as month,
          SUM((ii.applied_price - COALESCE(ii.actual_cost_price, ii.cost_price, p.cost_price, 0)) * 
              (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END)) as total_profit,
          SUM(ii.applied_price * (CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit
                    ELSE ii.quantity_individual END)) as total_selling_price,
          SUM(CASE WHEN ii.quantity_large_unit IS NOT NULL AND ii.quantity_large_unit > 0 
                    THEN ii.quantity_large_unit * COALESCE(ii.units_in_large_unit, 1.0)
                    ELSE ii.quantity_individual END) as total_quantity
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
        final profit = (map['total_profit'] ?? 0.0) as double;
        monthlyProfit[month] = profit;
      }
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
        double totalQuantity = 0.0;
        double totalSelling = 0.0;
        double totalCost = 0.0;
        for (final item in items) {
          final double sellingPrice =
              (item['applied_price'] ?? 0.0) as double;
          final double costPrice = (item['actual_cost_price'] ??
              item['cost_price'] ??
              item['product_cost_price'] ??
              0.0) as double;
          final double quantityIndividual =
              (item['quantity_individual'] ?? 0.0) as double;
          final double quantityLargeUnit =
              (item['quantity_large_unit'] ?? 0.0) as double;
          final double unitsInLargeUnit =
              (item['units_in_large_unit'] ?? 1.0) as double;
          
          // حساب الكمية الإجمالية (بالوحدات الأساسية) للمعرض
          final double currentItemTotalQuantity = quantityLargeUnit > 0
              ? (quantityLargeUnit * unitsInLargeUnit)
              : quantityIndividual;
          
          // حساب المبيعات والتكلفة بناءً على الوحدات المباعة
          if (quantityLargeUnit > 0) {
            totalSelling += sellingPrice * quantityLargeUnit;
            totalCost += costPrice * quantityLargeUnit;
            totalProfit += (sellingPrice - costPrice) * quantityLargeUnit;
          } else {
            totalSelling += sellingPrice * quantityIndividual;
            totalCost += costPrice * quantityIndividual;
            totalProfit += (sellingPrice - costPrice) * quantityIndividual;
          }
          
          totalQuantity += currentItemTotalQuantity;
        }
        final invoice = Invoice.fromMap(items.first);
        final double avgSellingPrice =
            totalQuantity > 0 ? totalSelling / totalQuantity : 0.0;
        final double avgUnitCost =
            totalQuantity > 0 ? totalCost / totalQuantity : 0.0;
        result.add(InvoiceWithProductData(
          invoice: invoice,
          quantitySold: totalQuantity,
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
        
        final profit = (sellingPrice - itemCostPrice) * currentItemTotalQuantity;
        final sales = sellingPrice * currentItemTotalQuantity;
        final cost = itemCostPrice * currentItemTotalQuantity;
        
        totalQuantity += currentItemTotalQuantity;
        totalProfit += profit;
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
} // نهاية كلاس DatabaseService

// أنواع البيانات لنظام التقارير
class InvoiceWithProductData {
  final Invoice invoice;
  final double quantitySold;
  final double profit;
  final double sellingPrice;
  final double unitCostAtSale;

  InvoiceWithProductData({
    required this.invoice,
    required this.quantitySold,
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

class PersonMonthData {
  final double totalProfit;
  final double totalSales;
  final int totalInvoices;
  final int totalTransactions;
  final double averageSellingPrice;
  final double totalQuantity;

  PersonMonthData({
    required this.totalProfit,
    required this.totalSales,
    required this.totalInvoices,
    required this.totalTransactions,
    required this.averageSellingPrice,
    required this.totalQuantity,
  });
}

//  MonthlySalesSummary class
class MonthlySalesSummary {
  final String monthYear;
  final double totalSales;
  final double netProfit;
  final double cashSales;
  final double creditSales;
  final double totalReturns; // إجمالي الراجع
  final double totalDebtPayments; // إجمالي تسديد الديون

  MonthlySalesSummary({
    required this.monthYear,
    required this.totalSales,
    required this.netProfit,
    required this.cashSales,
    required this.creditSales,
    required this.totalReturns, // إضافة إجمالي الراجع
    required this.totalDebtPayments, // إضافة إجمالي تسديد الديون
  });

  @override
  String toString() {
    return 'MonthlySummary($monthYear: Sales=$totalSales, Profit=$netProfit, Cash=$cashSales, Credit=$creditSales, Returns=$totalReturns, DebtPayments=$totalDebtPayments)';
  }
}
