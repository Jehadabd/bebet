import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/supplier.dart';
import '../models/delegate.dart';
import 'database_service.dart';
import 'financial_audit_service.dart';
import '../utils/money_calculator.dart'; // Added import
import 'cache_service.dart'; // 🚀 استيراد خدمة Cache

class SuppliersService {
  SuppliersService();
  
  // 🚀 متغير ثابت للتأكد من تشغيل ensureTables مرة واحدة فقط
  static bool _tablesEnsured = false;
  static final List<Supplier> _suppliersCache = [];
  static DateTime? _lastCacheUpdate;
  static const Duration _cacheValidDuration = Duration(minutes: 5);
  
  /// 🚀 التحقق من صلاحية Cache الموردين
  bool get _isCacheValid {
    if (_lastCacheUpdate == null) return false;
    return DateTime.now().difference(_lastCacheUpdate!) < _cacheValidDuration;
  }

  Future<Database> get _db async => await DatabaseService().database;

  Future<void> ensureTables() async {
    // 🚀 تحسين: تشغيل مرة واحدة فقط في الجلسة
    if (_tablesEnsured) return;
    
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_name TEXT NOT NULL,
        tax_number TEXT,
        phone_number TEXT,
        email_address TEXT,
        address TEXT,
        opening_balance REAL NOT NULL DEFAULT 0.0,
        current_balance REAL NOT NULL DEFAULT 0.0,
        total_purchases REAL NOT NULL DEFAULT 0.0,
        default_currency TEXT NOT NULL DEFAULT 'IQD',
        created_at TEXT NOT NULL,
        last_modified_at TEXT NOT NULL,
        notes TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS delegates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        phone_number TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        delegate_id INTEGER,
        invoice_number TEXT,
        invoice_date TEXT NOT NULL,
        total_amount REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0.0,
        amount_paid REAL NOT NULL DEFAULT 0.0,
        currency TEXT NOT NULL DEFAULT 'IQD',
        status TEXT NOT NULL DEFAULT 'آجل',
        payment_type TEXT NOT NULL DEFAULT 'دين',
        created_at TEXT NOT NULL,
        last_modified_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE,
        FOREIGN KEY (delegate_id) REFERENCES delegates(id) ON DELETE SET NULL
      )
    ''');

    // Ensure migration for older databases: add missing columns
    try {
      final cols = await db.rawQuery('PRAGMA table_info(supplier_invoices);');
      final hasPaymentType = cols.any((c) => (c['name'] == 'payment_type'));
      if (!hasPaymentType) {
        await db.execute(
            "ALTER TABLE supplier_invoices ADD COLUMN payment_type TEXT NOT NULL DEFAULT 'دين';");
      }
      final hasAmountPaid = cols.any((c) => (c['name'] == 'amount_paid'));
      if (!hasAmountPaid) {
        await db.execute(
            'ALTER TABLE supplier_invoices ADD COLUMN amount_paid REAL NOT NULL DEFAULT 0.0;');
      }
      final hasDelegateId = cols.any((c) => (c['name'] == 'delegate_id'));
      if (!hasDelegateId) {
        await db.execute(
            'ALTER TABLE supplier_invoices ADD COLUMN delegate_id INTEGER;');
      }
      final hasExchangeRate = cols.any((c) => (c['name'] == 'exchange_rate'));
      if (!hasExchangeRate) {
        await db.execute(
            'ALTER TABLE supplier_invoices ADD COLUMN exchange_rate REAL NOT NULL DEFAULT 1.0;');
      }
    } catch (_) {}
    // Migration for suppliers.total_purchases
    try {
      final colsSup = await db.rawQuery('PRAGMA table_info(suppliers);');
      final hasTotalPurchases = colsSup.any((c) => (c['name'] == 'total_purchases'));
      if (!hasTotalPurchases) {
        await db.execute('ALTER TABLE suppliers ADD COLUMN total_purchases REAL NOT NULL DEFAULT 0.0;');
      }
      final hasDefaultCurrency = colsSup.any((c) => (c['name'] == 'default_currency'));
      if (!hasDefaultCurrency) {
        await db.execute("ALTER TABLE suppliers ADD COLUMN default_currency TEXT NOT NULL DEFAULT 'IQD';");
      }
    } catch (_) {}
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        receipt_number TEXT,
        receipt_date TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_type TEXT NOT NULL,
        owner_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        file_type TEXT NOT NULL,
        extracted_text TEXT,
        extraction_confidence REAL,
        uploaded_at TEXT NOT NULL
      )
    ''');
    
    // جدول بنود فواتير الموردين
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        total_price REAL NOT NULL,
        unit TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (invoice_id) REFERENCES supplier_invoices(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
      )
    ''');
    
    // 🚀 تم التأكد من الجداول
    _tablesEnsured = true;
  }

  // --- دوال المندوبين ---
  
  Future<List<Delegate>> getDelegatesBySupplier(int supplierId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query(
      'delegates', 
      where: 'supplier_id = ?', 
      whereArgs: [supplierId], 
      orderBy: 'name COLLATE NOCASE'
    );
    return rows.map((e) => Delegate.fromMap(e)).toList();
  }

  Future<int> insertDelegate(Delegate delegate) async {
    await ensureTables();
    final db = await _db;
    return await db.insert('delegates', delegate.toMap());
  }

  Future<void> deleteDelegate(int id) async {
    await ensureTables();
    final db = await _db;
    await db.delete('delegates', where: 'id = ?', whereArgs: [id]);
  }

  // --- دوال الموردين الأساسية ---

  /// 🚀 جلب الموردين مع Cache ذكي
  /// إذا كانت الـ Cache صالحة، يعيد البيانات فوراً
  /// وإلا يجلب من قاعدة البيانات ويحدث الـ Cache
  Future<List<Supplier>> getAllSuppliers() async {
    // 🚀 تحقق من Cache أولاً
    if (_isCacheValid && _suppliersCache.isNotEmpty) {
      return List.from(_suppliersCache); // نسخة جديدة
    }
    
    await ensureTables();
    final db = await _db;
    final rows = await db.query('suppliers', orderBy: 'company_name COLLATE NOCASE');
    final suppliers = rows.map((e) => Supplier.fromMap(e)).toList();
    
    // 🚀 تحديث Cache
    _suppliersCache.clear();
    _suppliersCache.addAll(suppliers);
    _lastCacheUpdate = DateTime.now();
    
    return suppliers;
  }
  
  /// 🚀 إجبار تحديث Cache الموردين (استدعاؤها بعد أي كتابة)
  void _invalidateSuppliersCache() {
    _lastCacheUpdate = null;
    _suppliersCache.clear();
  }

  Future<int> insertSupplier(Supplier supplier) async {
    await ensureTables();
    final db = await _db;
    supplier.lastModifiedAt = DateTime.now();
    final id = await db.insert('suppliers', supplier.toMap());
    
    // 🚀 تحديث Cache بعد الكتابة
    _invalidateSuppliersCache();
    
    return id;
  }

  Future<int> insertSupplierInvoice(SupplierInvoice invoice) async {
    await ensureTables();
    final db = await _db;
    
    int invoiceId = await db.transaction((txn) async {
      final id = await txn.insert('supplier_invoices', invoice.toMap());
      
      // إذا كانت الفاتورة مسودة، لا تؤثر على الرصيد أو المشتريات
      if (invoice.status != 'مسودة') {
        // احسب تأثير الفاتورة على الرصيد
        final double remaining = MoneyCalculator.subtract(invoice.totalAmount, invoice.amountPaid);
        final double delta = invoice.paymentType == 'نقد' ? 0.0 : (remaining > 0 ? remaining : 0.0);
        
        // حدّث الرصيد والمشتريات الإجمالية (المشتريات تزيد دائماً بقيمة الفاتورة)
        await txn.rawUpdate(
          'UPDATE suppliers SET current_balance = current_balance + ?, total_purchases = total_purchases + ?, last_modified_at = ? WHERE id = ?',
          [delta, invoice.totalAmount, DateTime.now().toIso8601String(), invoice.supplierId],
        );
      }
      return id;
    });
    
    // تسجيل العملية في سجل التدقيق (خارج الترانزاكشن لتجنب القفل)
    try {
      // نحتاج لجلب الرصيد الجديد للتسجيل الدقيق، أو نحسبه تقريبياً
      // للتبسيط سنقوم بالتسجيل كما كان
      final auditService = FinancialAuditService();
      await auditService.logOperation(
        operationType: 'supplier_invoice_create',
        entityType: 'supplier',
        entityId: invoice.supplierId,
        newValues: {
          'invoice_id': invoiceId,
          'total_amount': invoice.totalAmount,
          'amount_paid': invoice.amountPaid,
          'payment_type': invoice.paymentType,
        },
        notes: 'فاتورة مورد جديدة بقيمة ${invoice.totalAmount}',
      );
    } catch (e) {
      print('خطأ في تسجيل التدقيق: $e');
    }
    
    // 🚀 تحديث Cache بعد الكتابة
    _invalidateSuppliersCache();
    
    return invoiceId;
  }

  Future<int> insertSupplierReceipt(SupplierReceipt receipt) async {
    await ensureTables();
    final db = await _db;
    
    int receiptId = await db.transaction((txn) async {
      final id = await txn.insert('supplier_receipts', receipt.toMap());
      // حدّث الرصيد
      await txn.rawUpdate(
        'UPDATE suppliers SET current_balance = current_balance - ? , last_modified_at = ? WHERE id = ?',
        [receipt.amount, DateTime.now().toIso8601String(), receipt.supplierId],
      );
      return id;
    });
    
    // تسجيل العملية في سجل التدقيق
    try {
      final auditService = FinancialAuditService();
      await auditService.logOperation(
        operationType: 'supplier_receipt_create',
        entityType: 'supplier',
        entityId: receipt.supplierId,
        newValues: {
          'receipt_id': receiptId,
          'amount': receipt.amount,
          'payment_method': receipt.paymentMethod,
        },
        notes: 'سند قبض مورد بقيمة ${receipt.amount}',
      );
    } catch (e) {
      print('خطأ في تسجيل التدقيق: $e');
    }
    
    // 🚀 تحديث Cache بعد الكتابة
    _invalidateSuppliersCache();
    
    return receiptId;
  }

  Future<int> insertAttachment(Attachment attachment) async {
    await ensureTables();
    final db = await _db;
    return await db.insert('attachments', attachment.toMap());
  }

  Future<String> saveAttachmentFile({required List<int> bytes, required String extension}) async {
    final dir = await getApplicationSupportDirectory();
    final attachmentsDir = Directory(p.join(dir.path, 'attachments'));
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }
    final fileName = 'att_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final filePath = p.join(attachmentsDir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return filePath;
  }

  Future<List<SupplierInvoice>> getInvoicesBySupplier(int supplierId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query('supplier_invoices',
        where: 'supplier_id = ?', whereArgs: [supplierId], orderBy: 'invoice_date DESC');
    return rows.map((e) => SupplierInvoice.fromMap(e)).toList();
  }

  Future<List<SupplierReceipt>> getReceiptsBySupplier(int supplierId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query('supplier_receipts',
        where: 'supplier_id = ?', whereArgs: [supplierId], orderBy: 'receipt_date DESC');
    return rows.map((e) => SupplierReceipt.fromMap(e)).toList();
  }

  Future<List<Attachment>> getAttachmentsForSupplier(int supplierId) async {
    await ensureTables();
    final db = await _db;
    // مرفقات مرتبطة بالمورد مباشرة أو بعملياته
    final invoiceIds = await db.query('supplier_invoices',
        columns: ['id'], where: 'supplier_id = ?', whereArgs: [supplierId]);
    final receiptIds = await db.query('supplier_receipts',
        columns: ['id'], where: 'supplier_id = ?', whereArgs: [supplierId]);
    final invIds = invoiceIds.map((e) => e['id'] as int).toList();
    final recIds = receiptIds.map((e) => e['id'] as int).toList();

    final List<Map<String, Object?>> rows = [];
    if (invIds.isNotEmpty) {
      final inPlaceholders = List.filled(invIds.length, '?').join(',');
      final r = await db.rawQuery(
          'SELECT * FROM attachments WHERE owner_type = "SupplierInvoice" AND owner_id IN ($inPlaceholders)',
          invIds);
      rows.addAll(r);
    }
    if (recIds.isNotEmpty) {
      final inPlaceholders = List.filled(recIds.length, '?').join(',');
      final r = await db.rawQuery(
          'SELECT * FROM attachments WHERE owner_type = "SupplierReceipt" AND owner_id IN ($inPlaceholders)',
          recIds);
      rows.addAll(r);
    }
    return rows.map((e) => Attachment.fromMap(e)).toList();
  }

  Future<List<Attachment>> getAttachmentsForOwner({
    required String ownerType,
    required int ownerId,
  }) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query('attachments',
        where: 'owner_type = ? AND owner_id = ?',
        whereArgs: [ownerType, ownerId],
        orderBy: 'uploaded_at DESC');
    return rows.map((e) => Attachment.fromMap(e)).toList();
  }

  // --- دوال بنود فواتير الموردين ---
  
  Future<int> insertInvoiceItem(SupplierInvoiceItem item) async {
    await ensureTables();
    final db = await _db;
    return await db.insert('supplier_invoice_items', item.toMap());
  }

  Future<List<SupplierInvoiceItem>> getInvoiceItems(int invoiceId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query(
      'supplier_invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'created_at ASC',
    );
    return rows.map((e) => SupplierInvoiceItem.fromMap(e)).toList();
  }

  Future<void> deleteInvoiceItems(int invoiceId) async {
    await ensureTables();
    final db = await _db;
    await db.delete(
      'supplier_invoice_items',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
    );
  }

  /// تحديث أسعار المنتجات من بنود الفاتورة
  Future<List<String>> updateProductCostsFromInvoice(int invoiceId) async {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔄 بدء updateProductCostsFromInvoice للفاتورة: $invoiceId');
    
    final db = await _db;
    final List<String> updatedProducts = [];

    // جلب بيانات الفاتورة لمعرفة العملة وسعر الصرف
    final invoiceMaps = await db.query('supplier_invoices', where: 'id = ?', whereArgs: [invoiceId], limit: 1);
    if (invoiceMaps.isEmpty) return [];
    final invoiceMap = invoiceMaps.first;
    final String currency = invoiceMap['currency'] as String? ?? 'IQD';
    final double exchangeRate = (invoiceMap['exchange_rate'] as num?)?.toDouble() ?? 1.0;
    
    print('💵 عملة الفاتورة: $currency, سعر الصرف: $exchangeRate');
    
    // جلب بنود الفاتورة
    final itemMaps = await db.query('supplier_invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
    final items = itemMaps.map((map) => SupplierInvoiceItem.fromMap(map)).toList();
    
    // تجميع البنود حسب المنتج لتجنب التحديث المتكرر
    final Map<int, List<SupplierInvoiceItem>> itemsByProduct = {};
    for (var item in items) {
      if (item.productId != null) {
        itemsByProduct.putIfAbsent(item.productId!, () => []).add(item);
      }
    }
    
    print('📊 عدد المنتجات الفريدة: ${itemsByProduct.length}');
    
    for (var entry in itemsByProduct.entries) {
      final productId = entry.key;
      final productItems = entry.value;
      
      print('\n--- معالجة منتج ID: $productId ---');
      print('  عدد البنود لهذا المنتج: ${productItems.length}');
      
      // اختيار البند الأفضل للتحديث:
      // 1. أولوية للبند بوحدة "قطعة"
      // 2. إذا لم يوجد، نستخدم أول بند
      SupplierInvoiceItem? bestItem;
      for (var item in productItems) {
        print('  - بند: ${item.productName}, وحدة: ${item.unit}, سعر: ${item.unitPrice}');
        if (item.unit == 'قطعة') {
          bestItem = item;
          print('    ✓ تم اختيار هذا البند (وحدة قطعة)');
          break;
        }
      }
      bestItem ??= productItems.first;
      
      if (bestItem.unit != 'قطعة') {
        print('  ⚠️ تحذير: لا يوجد بند بوحدة "قطعة"، سيتم استخدام: ${bestItem.unit}');
      }
      
      final item = bestItem;
      print('  📌 البند المختار: ${item.productName}');
      print('  productId: ${item.productId}');
      print('  unitPrice: ${item.unitPrice}');
      print('  quantity: ${item.quantity}');
      print('  unit: ${item.unit}');
      
      try {
        // جلب المنتج الحالي
        final productMaps = await db.query(
          'products',
          where: 'id = ?',
          whereArgs: [item.productId],
          limit: 1,
        );
        
        if (productMaps.isEmpty) {
          print('  ❌ لم يتم العثور على المنتج في قاعدة البيانات!');
          continue;
        }
        
        final productMap = productMaps.first;
        final oldCost = (productMap['cost_price'] as num?)?.toDouble() ?? 0.0;
        
        // تحويل التكلفة للدينار دائماً إذا كانت الفاتورة بالدولار
        double newCost = item.unitPrice;
        if (currency == 'USD') {
          newCost = item.unitPrice * exchangeRate;
          print('  💱 تحويل التكلفة من دولار إلى دينار: ${item.unitPrice} × $exchangeRate = $newCost');
        }
        
        print('  💰 التكلفة القديمة (دينار): $oldCost');
        print('  💰 التكلفة الجديدة (دينار): $newCost');
        print('  📊 الفرق: ${(newCost - oldCost).toStringAsFixed(2)}');
        
        // تحديث التكلفة فقط إذا اختلفت
        if ((oldCost - newCost).abs() > 0.01) {
          print('  🔄 التكلفة تغيرت! سيتم التحديث...');
          
          // حساب unit_costs الجديدة
          String? newUnitCosts;
          final unit = productMap['unit'] as String?;
          final unitHierarchy = productMap['unit_hierarchy'] as String?;
          
          print('  📐 وحدة المنتج: $unit');
          print('  📐 الهرمية: $unitHierarchy');
          
          if (unit == 'piece' && unitHierarchy != null && unitHierarchy.isNotEmpty) {
            try {
              final List<dynamic> hierarchy = json.decode(unitHierarchy);
              final Map<String, double> unitCosts = {};
              double currentCost = newCost;
              unitCosts['قطعة'] = currentCost;
              
              for (var level in hierarchy) {
                final unitName = level['unit_name'] as String?;
                final qty = level['quantity'] as int?;
                if (unitName != null && qty != null && qty > 0) {
                  currentCost = currentCost * qty;
                  unitCosts[unitName] = currentCost;
                }
              }
              
              newUnitCosts = json.encode(unitCosts);
              print('  ✅ حساب unit_costs: $newUnitCosts');
            } catch (e) {
              print('  ⚠️ خطأ في حساب unit_costs: $e');
            }
          } else if (unit == 'meter') {
            final lengthPerUnit = (productMap['length_per_unit'] as num?)?.toDouble() ?? 0.0;
            if (lengthPerUnit > 0) {
              newUnitCosts = json.encode({
                'متر': newCost,
                'لفة': newCost * lengthPerUnit,
              });
              print('  ✅ حساب unit_costs للمتر: $newUnitCosts');
            }
          }
          
          // تحديث cost_price و unit_costs
          if (newUnitCosts != null) {
            print('  💾 تحديث cost_price و unit_costs...');
            await db.rawUpdate(
              'UPDATE products SET cost_price = ?, unit_costs = ?, last_modified_at = ? WHERE id = ?',
              [newCost, newUnitCosts, DateTime.now().toIso8601String(), item.productId],
            );
          } else {
            print('  💾 تحديث cost_price فقط...');
            await db.rawUpdate(
              'UPDATE products SET cost_price = ?, last_modified_at = ? WHERE id = ?',
              [newCost, DateTime.now().toIso8601String(), item.productId],
            );
          }
          
          updatedProducts.add('${item.productName}: ${oldCost.toStringAsFixed(2)} ← ${newCost.toStringAsFixed(2)}');
          print('  ✅ تم التحديث بنجاح!');
        } else {
          print('  ⏭️ تخطي: السعر لم يتغير');
        }
      } catch (e) {
        print('  ❌ خطأ: $e');
      }
    }
    
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 النتيجة النهائية: ${updatedProducts.length} منتج محدث');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    return updatedProducts;
  }

  /// الحصول على إجمالي عدد الفواتير
  Future<int> getTotalInvoiceCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM supplier_invoices');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// الحصول على إجمالي عدد سندات القبض
  Future<int> getTotalReceiptCount() async {
    final db = await _db;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM supplier_receipts');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}


