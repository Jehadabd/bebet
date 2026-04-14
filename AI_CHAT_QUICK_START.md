لف الدوال والعمليات المنطقية الخاص بزر الموردين (Backend & DAOs)

يحتوي هذا الملف على جميع الدوال الخاصة بالمنطق البرمجي للموردين مع شرح مفصل والكود المصدري الكامل لكل دالة.

========================================================================
أولاً: الخدمة الرئيسية لعمليات الموردين `lib/services/suppliers_service.dart`
========================================================================
هذه الخدمة هي حلقة الوصل بين واجهة المستخدم وقاعدة البيانات الخاصة بجميع عمليات الموردين.

1. دالة تهيئة الجداول `ensureTables`
الشرح: تقوم هذه الدالة بالتأكد من وجود كافة جداول الموردين (الموردين، الفواتير، الدفعات، المناديب، بنود الفاتورة) بشكل سليم داخل قاعدة البيانات SQLite وتضيفها وتحدث هيكلتها إن لزم الأمر.

```dart
  Future<void> ensureTables() async {
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
        created_at TEXT NOT NULL,
        last_modified_at TEXT NOT NULL,
        notes TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
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
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
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
    } catch (_) {}
    // Migration for suppliers.total_purchases
    try {
      final colsSup = await db.rawQuery('PRAGMA table_info(suppliers);');
      final hasTotalPurchases = colsSup.any((c) => (c['name'] == 'total_purchases'));
      if (!hasTotalPurchases) {
        await db.execute('ALTER TABLE suppliers ADD COLUMN total_purchases REAL NOT NULL DEFAULT 0.0;');
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
      CREATE TABLE IF NOT EXISTS supplier_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        delegate_id INTEGER,
        receipt_number TEXT,
        receipt_date TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE,
        FOREIGN KEY (delegate_id) REFERENCES supplier_delegates(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_delegates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        position TEXT,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');

    // Add notes column if it doesn't exist (for existing databases)
    try {
      await db.execute("ALTER TABLE supplier_delegates ADD COLUMN notes TEXT;");
    } catch (e) {}

    // Migration for supplier_payments delegate_id
    try {
      final cols = await db.rawQuery('PRAGMA table_info(supplier_payments);');
      if (!cols.any((c) => c['name'] == 'delegate_id')) {
        await db.execute('ALTER TABLE supplier_payments ADD COLUMN delegate_id INTEGER REFERENCES supplier_delegates(id) ON DELETE SET NULL;');
      }
    } catch (_) {}

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
  }
```

2. قسم سجل الموردين `getAllSuppliers` و `insertSupplier`
الشرح: جلب كل الموردين للواجهة أو حفظ مورد جديد وإعطائه طابع وقت الإنشاء.

```dart
  Future<List<Supplier>> getAllSuppliers() async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query('suppliers', orderBy: 'company_name COLLATE NOCASE');
    return rows.map((e) => Supplier.fromMap(e)).toList();
  }

  Future<int> insertSupplier(Supplier supplier) async {
    await ensureTables();
    final db = await _db;
    final map = supplier.toMap();
    map['last_modified_at'] = DateTime.now().toIso8601String();
    return await db.insert('suppliers', map);
  }
```

3. دالة فواتير المورد `insertSupplierInvoice`
الشرح: تسجل فاتورة المشتريات الجديدة، وتحّدث بشكل ذكي إجمالي مشتريات ورصيد المورد (دينه)، وتسجل العملية في ملفات التدقيق المالي.

```dart
  Future<int> insertSupplierInvoice(SupplierInvoice invoice) async {
    await ensureTables();
    final db = await _db;
    
    int invoiceId = await db.transaction((txn) async {
      final id = await txn.insert('supplier_invoices', invoice.toMap());
      final double remaining = MoneyCalculator.subtract(invoice.totalAmount, invoice.paidAmount);
      
      // Update supplier balance and total purchases
      final supplierRows = await txn.query('suppliers', where: 'id = ?', whereArgs: [invoice.supplierId]);
      if (supplierRows.isNotEmpty) {
         final s = Supplier.fromMap(supplierRows.first);
         final newTotalPurchases = s.totalPurchases + invoice.totalAmount;
         // If remaining > 0, debt increases (currentBalance increases)
         final double balanceChange = remaining > 0 ? remaining : 0.0;
         final newBalance = s.currentBalance + balanceChange;
         
         await txn.update('suppliers', {
           'total_purchases': newTotalPurchases,
           'current_balance': newBalance,
           'last_modified_at': DateTime.now().toIso8601String(),
         }, where: 'id = ?', whereArgs: [invoice.supplierId]);
      }
      return id;
    });
    
    // Audit log
    try {
      final auditService = FinancialAuditService();
      await auditService.logOperation(
        operationType: 'supplier_invoice_create',
        entityType: 'supplier',
        entityId: invoice.supplierId,
        newValues: {
          'invoice_id': invoiceId,
          'total_amount': invoice.totalAmount,
          'amount_paid': invoice.paidAmount,
          'status': invoice.status,
        },
        notes: 'فاتورة مورد جديدة بقيمة \${invoice.totalAmount}',
      );
    } catch (e) {
      print('خطأ في تسجيل التدقيق: \$e');
    }
    
    return invoiceId;
  }
```

4. دالة المدفوعات والإيصالات `insertSupplierReceipt`
الشرح: تسجل دفعة مالية للمورد في قاعدة البيانات وتطرح الدفعة من دين (رصيد) المورد. وتسجل العملية في سجل المحاسبة المالي كتدقيق.

```dart
  Future<int> insertSupplierReceipt(SupplierReceipt receipt) async {
    await ensureTables();
    final db = await _db;
    
    int receiptId = await db.transaction((txn) async {
      final id = await txn.insert('supplier_payments', receipt.toMap());
      
      // Update supplier balance (payment reduces debt)
      final supplierRows = await txn.query('suppliers', where: 'id = ?', whereArgs: [receipt.supplierId]);
      if (supplierRows.isNotEmpty) {
        final s = Supplier.fromMap(supplierRows.first);
        final newBalance = s.currentBalance - receipt.amount;
        
        await txn.update('suppliers', {
          'current_balance': newBalance,
          'last_modified_at': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [receipt.supplierId]);
      }
      return id;
    });
    
    // Audit log
    try {
      final auditService = FinancialAuditService();
      await auditService.logOperation(
        operationType: 'supplier_payment_create',
        entityType: 'supplier',
        entityId: receipt.supplierId,
        newValues: {
          'receipt_id': receiptId,
          'amount': receipt.amount,
        },
        notes: 'سند دفع مورد بقيمة \${receipt.amount}',
      );
    } catch (e) {
      print('خطأ في تسجيل التدقيق: \$e');
    }
    
    return receiptId;
  }
```

5. دالة تحديث مخزون وتكلفة المنتجات `updateProductStatsFromInvoice`
الشرح: تأخذ الفاتورة المضافة وتحدث كمية المخزون لكل منتج بداخلها، وتحسب السعر الجديد لتكلفة المنتج بناءً على التسعيرة الجديدة من المورد.

```dart
  Future<List<String>> updateProductStatsFromInvoice(int invoiceId) async {
    print('\\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🔄 Starting updateProductStatsFromInvoice for invoice: \$invoiceId');
    
    final items = await getInvoiceItems(invoiceId);
    final db = await _db;
    final List<String> updatedProducts = [];
    
    final Map<int, List<SupplierInvoiceItem>> itemsByProduct = {};
    for (var item in items) {
      if (item.productId != null) {
        itemsByProduct.putIfAbsent(item.productId!, () => []).add(item);
      }
    }
    
    for (var entry in itemsByProduct.entries) {
      final productId = entry.key;
      final productItems = entry.value;
      
      try {
        final productMaps = await db.query('products', where: 'id = ?', whereArgs: [productId], limit: 1);
        if (productMaps.isEmpty) continue;
        
        final productMap = productMaps.first;
        final unitHierarchyJson = productMap['unit_hierarchy'] as String?;
        final oldCost = (productMap['cost_price'] as num?)?.toDouble() ?? 0.0;
        final productName = productMap['name'] as String;

        // 1. Calculate Stock Increase (handling units)
        double totalStockIncrease = 0.0;
        
        for (var item in productItems) {
           double multiplier = 1.0;
           // If unit is not 'قطعة' (Base Unit), look for multiplier in hierarchy
           if (item.unit != 'قطعة' && item.unit != null && unitHierarchyJson != null) {
              try {
                final List<dynamic> hierarchy = json.decode(unitHierarchyJson);
                int currentCumulative = 1;
                for (var level in hierarchy) {
                   final uName = level['unit_name'];
                   final uQty = level['quantity'] as int? ?? 1;
                   currentCumulative *= uQty;
                   if (uName == item.unit) {
                      multiplier = currentCumulative.toDouble();
                      break;
                   }
                }
              } catch (e) {
                print('Error parsing hierarchy for stock: \$e');
              }
           }
           totalStockIncrease += (item.quantity * multiplier);
        }
        
        // 2. Update Stock
        if (totalStockIncrease > 0) {
           await db.rawUpdate(
             'UPDATE products SET stock_quantity = stock_quantity + ? WHERE id = ?',
             [totalStockIncrease, productId],
           );
           print('  📈 \$productName: Stock increased by \$totalStockIncrease items');
        }

        // 3. Update Cost 
        SupplierInvoiceItem? bestItem;
        for (var item in productItems) {
          if (item.unit == 'قطعة') {
            bestItem = item;
            break;
          }
        }
        bestItem ??= productItems.first;
        
        double newCostPerPiece = bestItem.unitPrice; 
        if (bestItem.unit != 'قطعة' && bestItem.unit != null && unitHierarchyJson != null) {
            try {
                final List<dynamic> hierarchy = json.decode(unitHierarchyJson);
                int currentCumulative = 1;
                double conversion = 1.0;
                 for (var level in hierarchy) {
                   final uName = level['unit_name'];
                   final uQty = level['quantity'] as int? ?? 1;
                   currentCumulative *= uQty;
                   if (uName == bestItem!.unit) {
                      conversion = currentCumulative.toDouble();
                      break;
                   }
                }
                if (conversion > 0) {
                  newCostPerPiece = bestItem.unitPrice / conversion;
                }
            } catch(e) {
               print('Error converting cost: \$e');
            }
        }
        
        // Only update if cost changed significantly
        if ((oldCost - newCostPerPiece).abs() > 0.01) {
          String? newUnitCosts;
          final unit = productMap['unit'] as String?;
          
          if (unit == 'piece' && unitHierarchyJson != null && unitHierarchyJson.isNotEmpty) {
            try {
              final List<dynamic> hierarchy = json.decode(unitHierarchyJson);
              final Map<String, double> unitCosts = {};
              double currentCost = newCostPerPiece;
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
            } catch (e) {
              print('Error calculating unit costs: \$e');
            }
          } else if (unit == 'meter') {
             final lengthPerUnit = (productMap['length_per_unit'] as num?)?.toDouble() ?? 0.0;
             if (lengthPerUnit > 0) {
               newUnitCosts = json.encode({
                 'متر': newCostPerPiece,
                 'لفة': newCostPerPiece * lengthPerUnit,
               });
             }
          }
          
          if (newUnitCosts != null) {
            await db.rawUpdate(
              'UPDATE products SET cost_price = ?, unit_costs = ?, last_modified_at = ? WHERE id = ?',
              [newCostPerPiece, newUnitCosts, DateTime.now().toIso8601String(), productId],
            );
          } else {
            await db.rawUpdate(
              'UPDATE products SET cost_price = ?, last_modified_at = ? WHERE id = ?',
              [newCostPerPiece, DateTime.now().toIso8601String(), productId],
            );
          }
          updatedProducts.add('\$productName: \${oldCost.toStringAsFixed(2)} -> \${newCostPerPiece.toStringAsFixed(2)}');
        }
      } catch (e) {
        print('Error updating product \$productId: \$e');
      }
    }
    return updatedProducts;
  }
```

6. دوال المناديب `Delegates` و المرفقات `Attachments` واسترجاع الفواتير 
الشرح: هذه الدوال تقوم بجلب والإضافة على كائنات المندوبين، بنود الفواتير المضافة، وجلب سجل الفواتير والمرفقات للمورد.

```dart
  Future<List<SupplierDelegate>> getDelegates(int supplierId) async {
    await ensureTables();
    return await _delegateDao.getBySupplierId(supplierId);
  }

  Future<int> addDelegate(SupplierDelegate delegate) async {
    await ensureTables();
    return await _delegateDao.insert(delegate);
  }

  Future<int> updateDelegate(SupplierDelegate delegate) async {
    await ensureTables();
    return await _delegateDao.update(delegate);
  }

  Future<void> deleteDelegate(int id) async {
    await ensureTables();
    await _delegateDao.delete(id);
  }

  Future<List<SupplierInvoice>> getSupplierInvoices(int supplierId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query(
      'supplier_invoices',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );
    return rows.map((e) => SupplierInvoice.fromMap(e)).toList();
  }

  Future<List<SupplierReceipt>> getSupplierReceipts(int supplierId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query(
      'supplier_payments',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'date DESC',
    );
    return rows.map((e) => SupplierReceipt.fromMap(e)).toList();
  }

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
```

========================================================================
ثانياً: ملف الاستعلامات لبيانات الموردين `lib/services/database/dao/supplier_dao.dart`
========================================================================
الشرح: دوال جاهزة تستخدم أوامر SQL مباشرة لبطاقات الموردين في قاعدة البيانات.

```dart
class SupplierDao {
  final Future<Database> Function() getDatabase;

  SupplierDao({required this.getDatabase});

  /// إدراج مورد
  Future<int> insertSupplier(Map<String, dynamic> supplierMap) async {
    final db = await getDatabase();
    try {
      supplierMap['created_at'] = DateTime.now().toIso8601String();
      supplierMap['updated_at'] = DateTime.now().toIso8601String();
      return await db.insert('suppliers', supplierMap);
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// جلب جميع الموردين
  Future<List<Map<String, dynamic>>> getAllSuppliers() async {
    final db = await getDatabase();
    try {
      return await db.query('suppliers', orderBy: 'name ASC');
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// تحديث مورد
  Future<int> updateSupplier(int id, Map<String, dynamic> supplierMap) async {
    final db = await getDatabase();
    try {
      supplierMap['updated_at'] = DateTime.now().toIso8601String();
      return await db.update(
        'suppliers',
        supplierMap,
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// حذف مورد
  Future<int> deleteSupplier(int id) async {
    final db = await getDatabase();
    try {
      return await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }

  /// البحث عن الموردين
  Future<List<Map<String, dynamic>>> searchSuppliers(String query) async {
    final db = await getDatabase();
    try {
      return await db.query(
        'suppliers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: ['%\$query%', '%\$query%'],
        limit: 50,
      );
    } catch (e) {
      throw Exception(DatabaseHelpers.handleDatabaseError(e));
    }
  }
}
```

========================================================================
ثالثاً: ملف استعلامات مناديب الموردين `lib/services/database/dao/supplier_delegate_dao.dart`
========================================================================
الشرح: دوال جاهزة للتأثير المباشر على جدول مناديب المورد في قاعدة البيانات.

```dart
class SupplierDelegateDao {
  final Future<Database> Function() getDatabase;

  SupplierDelegateDao({required this.getDatabase});

  /// إضافة مندوب جديد
  Future<int> insert(SupplierDelegate delegate) async {
    final _db = await getDatabase();
    return await _db.insert(
      'supplier_delegates',
      delegate.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// الحصول على قائمة المندوبين لمورد معين
  Future<List<SupplierDelegate>> getBySupplierId(int supplierId) async {
    final _db = await getDatabase();
    final List<Map<String, dynamic>> maps = await _db.query(
      'supplier_delegates',
      where: 'supplier_id = ? AND is_active = 1',
      whereArgs: [supplierId],
    );

    return List.generate(maps.length, (i) => SupplierDelegate.fromMap(maps[i]));
  }

  /// تحديث بيانات مندوب
  Future<int> update(SupplierDelegate delegate) async {
    final _db = await getDatabase();
    return await _db.update(
      'supplier_delegates',
      delegate.toMap(),
      where: 'id = ?',
      whereArgs: [delegate.id],
    );
  }

  /// حذف (أو تعطيل) مندوب
  Future<int> delete(int id) async {
    final _db = await getDatabase();
    // نفضل التعطيل بدلاً من الحذف للحفاظ على التكامل المرجعي
    return await _db.update(
      'supplier_delegates',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
```
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/supplier.dart';
import '../services/purchase_service.dart';
import 'supplier_details_screen.dart';

/// شاشة قائمة الموردين (Odoo-Style Kanban View)
class SuppliersListScreen extends StatefulWidget {
  const SuppliersListScreen({super.key});

  @override
  State<SuppliersListScreen> createState() => _SuppliersListScreenState();
}

class _SuppliersListScreenState extends State<SuppliersListScreen> {
  final _searchController = TextEditingController();
  List<Supplier> _suppliers = [];
  List<Supplier> _filteredSuppliers = [];
  bool _isLoading = true;
  String _filterType = 'all'; // all, with_debt, no_debt

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    final suppliers = await context.read<PurchaseService>().getSuppliers();
    setState(() {
      _suppliers = suppliers;
      _applyFilter();
      _isLoading = false;
    });
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    _filteredSuppliers = _suppliers.where((s) {
      // Apply search
      final matchesSearch = s.name.toLowerCase().contains(query) ||
          (s.phone?.contains(query) ?? false);
      
      // Apply filter
      switch (_filterType) {
        case 'with_debt':
          return matchesSearch && s.hasDebt;
        case 'no_debt':
          return matchesSearch && !s.hasDebt;
        default:
          return matchesSearch;
      }
    }).toList();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('الموردون', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF455A64),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Filter menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              _filterType = value;
              _applyFilter();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'all', child: Text('الكل')),
              const PopupMenuItem(value: 'with_debt', child: Text('عليهم دين')),
              const PopupMenuItem(value: 'no_debt', child: Text('بدون دين')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Stats
          _buildStatsHeader(),
          
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'بحث باسم المورد أو رقم الهاتف...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (_) => _applyFilter(),
            ),
          ),
          
          // Suppliers Grid (Kanban Style)
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSuppliers.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadSuppliers,
                        child: GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _filteredSuppliers.length,
                          itemBuilder: (context, index) {
                            return _buildSupplierCard(_filteredSuppliers[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSupplierDialog(),
        backgroundColor: const Color(0xFF455A64),
        icon: const Icon(Icons.add),
        label: const Text('مورد جديد'),
      ),
    );
  }

  Widget _buildStatsHeader() {
    final totalSuppliers = _suppliers.length;
    final withDebt = _suppliers.where((s) => s.hasDebt).length;
    final totalDebtIqd = _suppliers.fold(0.0, (sum, s) => sum + s.totalDebtIqd);
    final totalDebtUsd = _suppliers.fold(0.0, (sum, s) => sum + s.totalDebtUsd);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF455A64),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          _buildStatItem('عدد الموردين', '$totalSuppliers', Icons.people),
          _buildStatItem('عليهم دين', '$withDebt', Icons.warning_amber, color: Colors.orange),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (totalDebtIqd > 0)
                  Text(
                    '${_formatNumber(totalDebtIqd)} IQD',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                if (totalDebtUsd > 0)
                  Text(
                    '${_formatNumber(totalDebtUsd)} USD',
                    style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                  ),
                const Text('إجمالي الديون', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color ?? Colors.white, size: 28),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSupplierCard(Supplier supplier) {
    final hasDebt = supplier.hasDebt;
    final debtColor = hasDebt ? Colors.red : Colors.green;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SupplierDetailsScreen(supplier: supplier)),
        ).then((_) => _loadSuppliers());
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with avatar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF455A64).withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF455A64),
                    child: Text(
                      supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      supplier.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            
            // Body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Phone
                    if (supplier.phone != null && supplier.phone!.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(supplier.phone!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    const Spacer(),
                    
                    // Debt info
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: debtColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(hasDebt ? Icons.arrow_upward : Icons.check_circle, 
                               size: 14, color: debtColor),
                          const SizedBox(width: 4),
                          Text(
                            hasDebt 
                                ? '${_formatNumber(supplier.totalDebt)} ${supplier.currency}'
                                : 'لا يوجد دين',
                            style: TextStyle(
                              color: debtColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // Stats row
                    Row(
                      children: [
                        _buildMiniStat(Icons.receipt, '${supplier.totalInvoices}'),
                        const SizedBox(width: 12),
                        _buildMiniStat(Icons.payments, '${supplier.totalPayments}'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 12, color: Colors.grey),
        const SizedBox(width: 2),
        Text(value, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.store_mall_directory, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا يوجد موردين',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط على الزر أدناه لإضافة مورد جديد',
            style: TextStyle(fontSize: 14, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  void _showAddSupplierDialog({Supplier? supplier}) {
    final isEdit = supplier != null;
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final phoneController = TextEditingController(text: supplier?.phone ?? '');
    final addressController = TextEditingController(text: supplier?.address ?? '');
    String currency = supplier?.currency ?? 'IQD';
    String paymentTerms = supplier?.paymentTerms ?? 'cash';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(isEdit ? Icons.edit : Icons.person_add, color: const Color(0xFF455A64)),
              const SizedBox(width: 8),
              Text(isEdit ? 'تعديل مورد' : 'إضافة مورد جديد'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المورد *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'العنوان',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: currency,
                  decoration: const InputDecoration(
                    labelText: 'العملة المفضلة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'IQD', child: Text('IQD - دينار عراقي')),
                    DropdownMenuItem(value: 'USD', child: Text('USD - دولار أمريكي')),
                  ],
                  onChanged: isEdit ? null : (val) => setDialogState(() => currency = val!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paymentTerms,
                  decoration: const InputDecoration(
                    labelText: 'شروط الدفع',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payment),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                    DropdownMenuItem(value: 'credit', child: Text('آجل')),
                  ],
                  onChanged: (val) => setDialogState(() => paymentTerms = val!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF455A64)),
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الرجاء إدخال اسم المورد')),
                  );
                  return;
                }

                final now = DateTime.now();
                final newSupplier = Supplier(
                  id: supplier?.id,
                  name: nameController.text.trim(),
                  phone: phoneController.text.trim(),
                  address: addressController.text.trim(),
                  currency: currency,
                  paymentTerms: paymentTerms,
                  totalDebtIqd: supplier?.totalDebtIqd ?? 0.0,
                  totalDebtUsd: supplier?.totalDebtUsd ?? 0.0,
                  totalInvoices: supplier?.totalInvoices ?? 0,
                  totalPayments: supplier?.totalPayments ?? 0,
                  createdAt: supplier?.createdAt ?? now,
                  updatedAt: now,
                );

                final purchaseService = context.read<PurchaseService>();
                if (isEdit) {
                  await purchaseService.updateSupplier(newSupplier);
                } else {
                  await purchaseService.addSupplier(newSupplier);
                }

                Navigator.pop(context);
                _loadSuppliers();
              },
              child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatNumber(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(0)}K';
    }
    return number.toStringAsFixed(0);
  }
}
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' as intl;
import '../models/supplier.dart';
import '../models/purchase_invoice.dart';
import '../models/supplier_payment.dart';
import '../models/supplier_delegate.dart';
import '../services/purchase_service.dart';
import '../services/suppliers_service.dart';
import 'create_purchase_invoice_screen.dart';
import 'register_payment_dialog.dart';
import 'invoice_details_split_screen.dart';
import 'delegate_details_screen.dart';

class SupplierDetailsScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierDetailsScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailsScreen> createState() => _SupplierDetailsScreenState();
}

class _SupplierDetailsScreenState extends State<SupplierDetailsScreen> {
  late Supplier _supplier;
  List<PurchaseInvoice> _invoices = [];
  List<SupplierPayment> _payments = [];
  List<SupplierDelegate> _delegates = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final purchaseService = context.read<PurchaseService>();
    final suppliersService = context.read<SuppliersService>();
    
    final invoices = await purchaseService.getInvoicesForSupplier(_supplier.id!);
    final payments = await purchaseService.getPaymentsForSupplier(_supplier.id!);
    final delegates = await suppliersService.getDelegates(_supplier.id!);
    
    final suppliers = await purchaseService.getSuppliers(query: _supplier.name);
    final updatedSupplier = suppliers.firstWhere(
      (s) => s.id == _supplier.id,
      orElse: () => _supplier,
    );
    
    if (mounted) {
      setState(() {
        _invoices = invoices;
        _payments = payments;
        _delegates = delegates;
        _supplier = updatedSupplier;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate 50
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(),
          if (_isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsGrid(),
                    const SizedBox(height: 32),
                    
                    _buildSectionHeader('المندوبين', Icons.people_outline, 
                      action: TextButton.icon(
                        onPressed: _showAddDelegateDialog,
                        icon: const Icon(Icons.add_circle_outline, size: 16),
                        label: const Text('إضافة مندوب'),
                      )
                    ),
                    const SizedBox(height: 16),
                    _buildDelegatesList(),
                    const SizedBox(height: 32),

                    _buildSectionHeader('آخر الفواتير', Icons.receipt_long_outlined),
                    const SizedBox(height: 16),
                    _buildRecentInvoicesList(),
                    const SizedBox(height: 32),
                     
                    _buildSectionHeader('سجل المدفوعات', Icons.payment_outlined),
                    const SizedBox(height: 16),
                    _buildRecentPaymentsList(),
                    const SizedBox(height: 40), // Bottom padding
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: _buildFAB(),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 200.0,
      floating: false,
      pinned: true,
      backgroundColor: const Color(0xFF0F172A), // Slate 900
      iconTheme: const IconThemeData(color: Colors.white),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: const Color(0xFF0F172A)),
            Positioned(
              right: -50, top: -50,
              child: Icon(Icons.business, size: 200, color: Colors.white.withOpacity(0.05)),
            ),
            Padding(
               padding: const EdgeInsets.all(24.0),
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.end,
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   const SizedBox(height: 40),
                   Row(
                     children: [
                       Container(
                         padding: const EdgeInsets.all(3),
                         decoration: BoxDecoration(
                           color: Colors.white,
                           borderRadius: BorderRadius.circular(50),
                         ),
                         child: CircleAvatar(
                           radius: 32,
                           backgroundColor: const Color(0xFF3B82F6),
                           child: Text(
                             _supplier.name.isNotEmpty ? _supplier.name[0].toUpperCase() : '?',
                             style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                           ),
                         ),
                       ),
                       const SizedBox(width: 16),
                       Expanded(
                         child: Column(
                           crossAxisAlignment: CrossAxisAlignment.start,
                           children: [
                             Text(
                               _supplier.name,
                               style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                             ),
                             const SizedBox(height: 4),
                             Row(
                               children: [
                                 if (_supplier.phone != null) ...[
                                   Icon(Icons.phone, size: 14, color: Colors.grey[400]),
                                   const SizedBox(width: 4),
                                   Text(_supplier.phone!, style: TextStyle(color: Colors.grey[400])),
                                   const SizedBox(width: 16),
                                 ],
                                 Container(
                                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                   decoration: BoxDecoration(
                                     color: Colors.white.withOpacity(0.1),
                                     borderRadius: BorderRadius.circular(4),
                                   ),
                                   child: Text(
                                     _supplier.paymentTerms == 'credit' ? 'آجل' : 'نقدي',
                                     style: const TextStyle(color: Colors.white, fontSize: 12),
                                   ),
                                 ),
                               ],
                             ),
                           ],
                         ),
                       ),
                     ],
                   ),
                 ],
               ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(icon: const Icon(Icons.edit, color: Colors.white), onPressed: _editSupplier),
        IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _loadData),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return Row(
      children: [
        Expanded(
          child: _buildStatBox(
            'الرصيد الكلي',
            '${_formatNumber(_supplier.totalDebt)} ${_supplier.currency}',
            Icons.account_balance_wallet,
            _supplier.hasDebt ? Colors.red : Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatBox(
            'الفواتير',
            '${_supplier.totalInvoices}',
            Icons.receipt_long,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatBox(
            'المدفوعات',
            '${_supplier.totalPayments}',
            Icons.payments,
            Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildStatBox(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Segoe UI')),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {Widget? action}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const Spacer(),
        if (action != null) action,
      ],
    );
  }

  Widget _buildDelegatesList() {
    if (_delegates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(Icons.people_outline, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 8),
            Text('لا يوجد مندوبين مرتبطين', style: TextStyle(color: Colors.grey[500])),
          ],
        ),
      );
    }

    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _delegates.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final delegate = _delegates[index];
          return GestureDetector(
            onTap: () {
               Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DelegateDetailsScreen(delegate: delegate),
                ),
              );
            },
            child: Container(
              width: 130,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.blue[50],
                    child: Text(delegate.name[0].toUpperCase(), style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(delegate.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  if (delegate.phone != null)
                    Text(delegate.phone!, maxLines: 1, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecentInvoicesList() {
    if (_invoices.isEmpty) {
      return const Center(child: Text('لا توجد فواتير بعد'));
    }
    
    // Show only top 5 recent invoices
    final recentInvoices = _invoices.take(5).toList();

    return Column(
      children: recentInvoices.map((invoice) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[100]!),
          ),
          child: ListTile(
            leading: div(
              child: Icon(Icons.receipt_long, color: Colors.blue[700]),
              color: Colors.blue[50]!,
            ),
            title: Text('فاتورة #${invoice.invoiceNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(intl.DateFormat('yyyy-MM-dd').format(invoice.date)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${_formatNumber(invoice.totalAmount)} ${invoice.currency}', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(invoice.statusArabic, style: TextStyle(fontSize: 11, color: _getStatusColor(invoice.status))),
              ],
            ),
            onTap: () {
               Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => InvoiceDetailsSplitScreen(invoiceId: invoice.id!),
                ),
              );
            },
          ),
        );
      }).toList(),
    );
  }
  Widget div({required Widget child, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: child,
    );
  }

  Widget _buildRecentPaymentsList() {
    if (_payments.isEmpty) return const Center(child: Text('لا توجد مدفوعات'));
    final recent = _payments.take(5).toList();

    return Column(
      children: recent.map((payment) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
           child: ListTile(
            leading: div(child: const Icon(Icons.check, color: Colors.green), color: Colors.green[50]!),
            title: Text('تسديد دفعة', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(intl.DateFormat('yyyy-MM-dd').format(payment.date)),
            trailing: Text('${_formatNumber(payment.amount)} ${payment.currency}', 
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.note_add),
                title: const Text('إنشاء فاتورة شراء'),
                onTap: () {
                  Navigator.pop(context);
                  _createInvoice();
                },
              ),
              ListTile(
                leading: const Icon(Icons.payment),
                title: const Text('تسجيل دفعة واصلة'),
                onTap: () {
                  Navigator.pop(context);
                  _registerPayment();
                },
              ),
            ],
          ),
        );
      },
      icon: const Icon(Icons.add),
      label: const Text('إجراء جديد'),
      backgroundColor: const Color(0xFF0F172A),
    );
  }

  void _showAddDelegateDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة مندوب جديد'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'اسم المندوب', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'رقم الهاتف (اختياري)', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              
              final service = context.read<SuppliersService>();
              await service.addDelegate(SupplierDelegate(
                supplierId: _supplier.id!,
                name: nameController.text.trim(),
                phone: phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
              ));
              
              Navigator.pop(context);
              _loadData(); // Refresh
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _createInvoice() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePurchaseInvoiceScreen(preselectedSupplier: _supplier),
      ),
    ).then((_) => _loadData());
  }

  void _registerPayment() {
    showDialog(
      context: context,
      builder: (_) => RegisterPaymentDialog(supplier: _supplier),
    ).then((_) => _loadData());
  }

  void _editSupplier() {
    // Reuse existing logic from Dashboard/List screen if refactored, or implement duplicate here for now
  }

  MaterialColor _getStatusColor(String status) {
    switch (status) {
      case 'draft': return Colors.grey;
      case 'confirmed': return Colors.blue;
      case 'paid': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return Colors.blue;
    }
  }

  String _formatNumber(double number) {
    if (number == 0) return '0';
    return intl.NumberFormat("#,##0", "en_US").format(number);
  }
}
import 'package:flutter/material.dart';
import '../models/supplier.dart';

class AddSupplierScreen extends StatefulWidget {
  const AddSupplierScreen({Key? key}) : super(key: key);

  @override
  State<AddSupplierScreen> createState() => _AddSupplierScreenState();
}

class _AddSupplierScreenState extends State<AddSupplierScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _openingBalanceController = TextEditingController(text: '0');

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة مورد')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'اسم الشركة',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'الاسم مطلوب'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'الهاتف (اختياري)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _openingBalanceController,
                decoration: const InputDecoration(
                  labelText: 'رصيد افتتاحي (اختياري)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ'),
                  onPressed: _onSave,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;
    final opening = double.tryParse(_openingBalanceController.text.trim()) ?? 0;
    final supplier = Supplier(
      companyName: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim().isEmpty
          ? null
          : _phoneController.text.trim(),
      openingBalance: opening,
      currentBalance: opening,
    );
    Navigator.of(context).pop(supplier);
  }
}


import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/supplier.dart';
import '../models/product.dart';
import '../services/gemini_service.dart';
import '../services/suppliers_service.dart';
import '../services/ensemble_ai_service.dart';
import '../models/supplier_invoice_item.dart';
import '../models/attachment.dart';
import '../services/database_service.dart';

class NewSupplierInvoiceScreen extends StatefulWidget {
  final Supplier supplier;
  const NewSupplierInvoiceScreen({Key? key, required this.supplier}) : super(key: key);

  @override
  State<NewSupplierInvoiceScreen> createState() => _NewSupplierInvoiceScreenState();
}

class _NewSupplierInvoiceScreenState extends State<NewSupplierInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _paidCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');
  String _paymentType = 'دين'; // نقد أو دين
  bool _saving = false;
  Uint8List? _pickedBytes;
  String? _pickedMime;
  String? _pickedName;
  final NumberFormat _nf = NumberFormat('#,##0.##', 'en');
  bool _formatting = false;

  final SuppliersService _service = SuppliersService();
  final DatabaseService _db = DatabaseService();
  
  // قائمة بنود الفاتورة
  List<SupplierInvoiceItem> _items = [];
  List<Product> _allProducts = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _dateCtrl.text = DateTime.now().toIso8601String().split('T')[0];
  }

  Future<void> _loadProducts() async {
    final products = await _db.getAllProducts();
    setState(() {
      _allProducts = products;
    });
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _numberCtrl.dispose();
    _totalCtrl.dispose();
    _paidCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  void _recalculateTotal() {
    final itemsTotal = _items.fold(0.0, (sum, item) => sum + item.totalPrice);
    setState(() {
      _totalCtrl.text = _nf.format(itemsTotal);
    });
  }

  void _addItem() {
    showDialog(
      context: context,
      builder: (context) => _AddItemDialog(
        allProducts: _allProducts,
        onAdd: (item) {
          setState(() {
            _items.add(item);
            _recalculateTotal();
          });
        },
      ),
    );
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _recalculateTotal();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فاتورة مورد جديدة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'ملء تلقائي من صورة',
            onPressed: _onAutofillFromImage,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text('المورد: ${widget.supplier.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _paymentType,
                decoration: const InputDecoration(labelText: 'طريقة الدفع'),
                items: const [
                  DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                  DropdownMenuItem(value: 'دين', child: Text('دين')),
                ],
                onChanged: (v) { if (v != null) setState(() { _paymentType = v; }); },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dateCtrl,
                decoration: const InputDecoration(labelText: 'تاريخ الفاتورة (ISO yyyy-MM-dd)'),
                validator: (v) => (v == null || v.isEmpty) ? 'أدخل التاريخ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _numberCtrl,
                decoration: const InputDecoration(labelText: 'رقم الفاتورة (اختياري)'),
              ),
              const SizedBox(height: 16),
              // قسم المنتجات
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('المنتجات:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ElevatedButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة منتج'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_items.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('لم يتم إضافة منتجات بعد'),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return Card(
                      child: ListTile(
                        title: Text(item.productName),
                        subtitle: Text(
                          '${item.quantity} ${item.unit ?? ''} × ${item.unitPrice.toStringAsFixed(2)} = ${item.totalPrice.toStringAsFixed(2)}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeItem(index),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _totalCtrl,
                decoration: const InputDecoration(labelText: 'الإجمالي'),
                keyboardType: TextInputType.number,
                readOnly: _items.isNotEmpty, // للقراءة فقط إذا كانت هناك بنود
                onChanged: (v) => _onFormatNumber(_totalCtrl),
                validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '')) == null) ? 'أدخل رقم صحيح' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _discountCtrl,
                decoration: const InputDecoration(labelText: 'الخصم (اختياري)'),
                keyboardType: TextInputType.number,
                onChanged: (v) =>

 _onFormatNumber(_discountCtrl),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _paidCtrl,
                decoration: const InputDecoration(labelText: 'المدفوع عند الفاتورة (اختياري)'),
                keyboardType: TextInputType.number,
                onChanged: (v) => _onFormatNumber(_paidCtrl),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(_pickedName == null ? 'إرفاق ملف (اختياري)' : _pickedName!),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _onPickAttachment,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('اختيار'),
                    ),
                    if (_pickedBytes != null)
                      IconButton(
                        tooltip: 'إزالة',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() { _pickedBytes = null; _pickedMime = null; _pickedName = null; }),
                      )
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                  label: const Text('حفظ'),
                  onPressed: _saving ? null : _onSave,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAutofillFromImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');

    setState(() {
      _pickedBytes = file.bytes!;
      _pickedMime = mime;
      _pickedName = file.name;
    });

    setState(() {
      _saving = true; // Show loading indicator
    });

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري تحليل الفاتورة بواسطة الذكاء الاصطناعي الخاص...')));
      }

      // Use the new Local AI Service (Ensemble → Table Extractor → Fallback)
      final aiService = EnsembleAIService();
      
      // Write bytes to temp file for the service
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${file.name}');
      await tempFile.writeAsBytes(file.bytes!);
      
      final data = await aiService.extractInvoiceData(tempFile);
      
      if (mounted) {
        setState(() {
          _saving = false; // Stop loading
        });
      }
      
      if (data.containsKey('error')) {
         throw Exception(data['error']);
      }

      final date = (data['date'] ?? '').toString();
      final invoiceNum = (data['invoice_number'] ?? '').toString();
      final total = (data['total'] ?? 0.0).toString();
      final detectionMethod = (data['detection_method'] ?? 'unknown').toString();
      
      // ═══ Auto-populate header fields ═══
      if (mounted) {
        setState(() {
          if (date.isNotEmpty) {
               _dateCtrl.text = date;
          }
          if (invoiceNum.isNotEmpty) _numberCtrl.text = invoiceNum;
          if (total != "0.0" && total != "0") { 
              _totalCtrl.text = _nf.format(double.tryParse(total) ?? 0); 
          }
          _onFormatNumber(_totalCtrl);
        });
      }
      
      // ═══ Auto-populate ITEMS from AI extraction ═══
      final List<dynamic> extractedItems = data['items'] ?? [];
      if (extractedItems.isNotEmpty && mounted) {
        final List<SupplierInvoiceItem> newItems = [];
        
        for (var aiItem in extractedItems) {
          final String name = (aiItem['name'] ?? '').toString().trim();
          final double qty = _toDouble(aiItem['qty']);
          final double price = _toDouble(aiItem['price']);
          final double lineTotal = _toDouble(aiItem['line_total']);
          final String unit = (aiItem['unit'] ?? '').toString();
          
          // Skip items without useful data
          if (name.isEmpty && price == 0 && lineTotal == 0) continue;
          
          // Try to match with database products
          int? matchedProductId;
          String finalName = name;
          if (name.isNotEmpty && _allProducts.isNotEmpty) {
            for (var product in _allProducts) {
              if (product.name.contains(name) || name.contains(product.name)) {
                matchedProductId = product.id;
                finalName = product.name; // Use the official product name
                break;
              }
            }
          }
          
          newItems.add(SupplierInvoiceItem(
            invoiceId: 0, // Will be set on save
            productId: matchedProductId,
            productName: finalName.isEmpty ? 'منتج غير معرّف' : finalName,
            quantity: qty > 0 ? qty : 1.0,
            unitPrice: price,
            totalPrice: lineTotal > 0 ? lineTotal : (qty > 0 ? qty * price : price),
            unit: unit.isNotEmpty ? unit : null,
            createdAt: DateTime.now(),
          ));
        }
        
        if (newItems.isNotEmpty) {
          setState(() {
            _items.addAll(newItems);
            _recalculateTotal();
          });
        }
      }
      
      if (mounted) {
        final itemCount = extractedItems.length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('✅ تم استخراج $itemCount منتج بنجاح! (طريقة: $detectionMethod)'),
          duration: const Duration(seconds: 4),
        ));
      }

    } catch (e) {
      if (mounted) {
        setState(() { _saving = false; });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('فشل التحليل: $e')));
    }
  }



  Future<void> _onPickAttachment() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : 'image/jpeg');
    setState(() {
      _pickedBytes = file.bytes!;
      _pickedMime = mime;
      _pickedName = file.name;
    });
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    // منع الضغط المتكرر
    if (_saving) return;
    
    setState(() => _saving = true);
    
    try {
      print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🚀 بدء عملية الحفظ...');
      
      final total = double.tryParse(_totalCtrl.text.replaceAll(',', '').trim()) ?? 0;
      final discount = double.tryParse(_discountCtrl.text.replaceAll(',', '').trim()) ?? 0;
      final paid = double.tryParse(_paidCtrl.text.replaceAll(',', '').trim()) ?? 0;
      
      final inv = SupplierInvoice(
        supplierId: widget.supplier.id!,
        invoiceNumber: _numberCtrl.text.trim().isEmpty ? '' : _numberCtrl.text.trim(),
        date: DateTime.tryParse(_dateCtrl.text.trim()) ?? DateTime.now(),
        totalAmount: total,
        paidAmount: paid,
      );
      
      // الخطوة 1: حفظ الفاتورة
      print('📝 [1/5] حفظ الفاتورة...');
      final invoiceId = await _service.insertSupplierInvoice(inv);
      print('✅ تم حفظ الفاتورة برقم: $invoiceId');
      
      // الخطوة 2: حفظ البنود
      print('📝 [2/5] حفظ ${_items.length} بنود...');
      int savedItems = 0;
      List<String> failedItems = [];
      
      for (var item in _items) {
        try {
          item.invoiceId = invoiceId;
          // Ensure productId is valid (not -1) or null
          if (item.productId != null && item.productId! <= 0) {
             print('⚠️ Item ${item.productName} has invalid productId: ${item.productId}. Setting to null.');
             // We can't set productId because it's final (in some versions) or we fixed it in toMap.
             // But let's log it.
          }
          await _service.insertInvoiceItem(item);
          savedItems++;
          print('  ✓ حفظ بند $savedItems/${_items.length}: ${item.productName} (ID: ${item.productId})');
        } catch (e) {
          print('❌ فشل حفظ البند ${item.productName}: $e');
          failedItems.add('${item.productName}: $e');
        }
      }
      
      // التحقق من أن جميع البنود حُفظت بنجاح
      if (savedItems != _items.length) {
        final errorMsg = 'فشل حفظ ${_items.length - savedItems} من ${_items.length} بند!\nالبنود الفاشلة: ${failedItems.join(", ")}';
        print('❌ $errorMsg');
        throw Exception(errorMsg);
      }
      
      print('✅ تم حفظ جميع البنود بنجاح ($savedItems/${_items.length})');
      
      // التحقق النهائي: قراءة البنود من قاعدة البيانات للتأكد
      print('🔍 [2.5/5] التحقق من البنود في قاعدة البيانات...');
      final savedItemsInDb = await _service.getInvoiceItems(invoiceId);
      if (savedItemsInDb.length != _items.length) {
        final errorMsg = 'خطأ في التحقق: تم حفظ ${savedItemsInDb.length} بند في قاعدة البيانات بدلاً من ${_items.length}!';
        print('❌ $errorMsg');
        throw Exception(errorMsg);
      }
      print('✅ تم التحقق: جميع البنود موجودة في قاعدة البيانات (${savedItemsInDb.length}/${_items.length})');
      
      // الخطوة 3: تحديث أسعار المنتجات
      print('🔄 [3/5] تحديث أسعار المنتجات...');
      final updatedProducts = await _service.updateProductStatsFromInvoice(invoiceId);
      print('✅ تم تحديث ${updatedProducts.length} منتج');
      
      // الخطوة 4: حفظ المرفق
      if (_pickedBytes != null && _pickedMime != null) {
        print('📎 [4/5] حفظ المرفق...');
        final ext = _pickedMime == 'application/pdf' ? 'pdf' : (_pickedMime == 'image/png' ? 'png' : 'jpg');
        final path = await _service.saveAttachmentFile(bytes: _pickedBytes!, extension: ext);
        await _service.insertAttachment(Attachment(
          ownerType: 'SupplierInvoice',
          ownerId: invoiceId,
          filePath: path,
          fileType: ext == 'pdf' ? 'pdf' : 'image',
          extractedText: null,
          extractionConfidence: null,
          uploadedAt: DateTime.now(),
        ));
        print('✅ تم حفظ المرفق');
      } else {
        print('⏭️ [4/5] لا يوجد مرفق');
      }
      
      // الخطوة 5: عرض رسالة التحديث (إذا لزم الأمر)
      if (updatedProducts.isNotEmpty && mounted) {
        print('📢 [5/5] عرض رسالة التحديث...');
        await showDialog<bool>(
          context: context,
          barrierDismissible: false, // منع الإغلاق بالنقر خارج الحوار
          builder: (context) => WillPopScope(
            onWillPop: () async => false, // منع الإغلاق بزر الرجوع
            child: AlertDialog(
              title: const Text('✅ تم الحفظ بنجاح'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تم تحديث أسعار المنتجات التالية:'),
                    const SizedBox(height: 8),
                    ...updatedProducts.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• $p', style: const TextStyle(fontSize: 14)),
                    )),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('موافق'),
                ),
              ],
            ),
          ),
        );
      } else {
        print('⏭️ [5/5] لا توجد منتجات محدثة');
      }
      
      print('✅ اكتملت جميع العمليات بنجاح');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // العودة إلى الشاشة السابقة
      if (!mounted) return;
      Navigator.of(context).pop(true);
      
    } catch (e, stackTrace) {
      print('❌ خطأ في الحفظ: $e');
      print('Stack trace: $stackTrace');
      
      if (!mounted) return;
      
      // عرض رسالة خطأ واضحة
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('❌ فشل الحفظ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('حدث خطأ أثناء حفظ الفاتورة:'),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
      
      // إعادة تفعيل الزر في حالة الخطأ فقط
      if (mounted) setState(() => _saving = false);
    }
    // ملاحظة: لا يوجد finally هنا - الزر يبقى معطلاً حتى تكتمل العملية أو يحدث خطأ
  }

  void _onFormatNumber(TextEditingController ctrl) {
    if (_formatting) return;
    _formatting = true;
    final raw = ctrl.text.replaceAll(',', '').trim();
    if (raw.isEmpty) { _formatting = false; return; }
    final val = double.tryParse(raw);
    if (val != null) {
      ctrl.text = _nf.format(val);
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
    _formatting = false;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '')) ?? 0.0;
  }
}

// حوار إضافة منتج
class _AddItemDialog extends StatefulWidget {
  final List<Product> allProducts;
  final Function(SupplierInvoiceItem) onAdd;

  const _AddItemDialog({required this.allProducts, required this.onAdd});

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _productNameCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _totalPriceCtrl = TextEditingController(); // السعر الإجمالي للوحدة المختارة
  Product? _selectedProduct;
  List<Product> _filteredProducts = [];
  String? _selectedUnit; // الوحدة المختارة (قطعة، كرتون، إلخ)
  List<String> _availableUnits = ['قطعة']; // الوحدات المتاحة
  Map<String, int> _unitQuantities = {}; // عدد القطع في كل وحدة
  final _calculatedCostCtrl = TextEditingController(); // التكلفة المحسوبة للقطعة

  @override
  void dispose() {
    _productNameCtrl.dispose();
    _quantityCtrl.dispose();
    _totalPriceCtrl.dispose();
    _calculatedCostCtrl.dispose();
    super.dispose();
  }

  void _searchProducts(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredProducts = [];
      });
      return;
    }
    
    setState(() {
      _filteredProducts = widget.allProducts
          .where((p) => p.name.contains(query))
          .take(10)
          .toList();
    });
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _productNameCtrl.text = product.name;
      _filteredProducts = [];
      
      // بناء قائمة الوحدات المتاحة
      _availableUnits = ['قطعة'];
      _unitQuantities = {};
      
      if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
        try {
          final List<dynamic> hierarchy = json.decode(product.unitHierarchy!);
          int cumulativeQty = 1;
          for (var level in hierarchy) {
            final unitName = level['unit_name'] as String?;
            final qty = level['quantity'] as int?;
            if (unitName != null && qty != null && qty > 0) {
              cumulativeQty *= qty;
              _availableUnits.add(unitName);
              _unitQuantities[unitName] = cumulativeQty;
            }
          }
        } catch (e) {
          print('خطأ في قراءة الهرمية: $e');
        }
      }
      
      _selectedUnit = 'قطعة';
      _totalPriceCtrl.text = (product.costPrice ?? 0).toString();
      _recalculateCost();
    });
  }

  void _recalculateCost() {
    if (_totalPriceCtrl.text.isEmpty  || _selectedUnit == null) return;
    
    final totalPrice = double.tryParse(_totalPriceCtrl.text.trim()) ?? 0;
    if (_selectedUnit == 'قطعة') {
      _calculatedCostCtrl.text = totalPrice.toStringAsFixed(2);
    } else {
      final unitQty = _unitQuantities[_selectedUnit] ?? 1;
      final costPerPiece = totalPrice / unitQty;
      _calculatedCostCtrl.text = costPerPiece.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة منتج'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // حقل اسم المنتج مع البحث
              TextFormField(
                controller: _productNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المنتج',
                  hintText: 'ابحث عن منتج...',
                ),
                onChanged: _searchProducts,
                validator: (v) => (v == null || v.isEmpty) ? 'أدخل اسم المنتج' : null,
              ),
              // نتائج البحث
              if (_filteredProducts.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      return ListTile(
                        title: Text(product.name),
                        subtitle: Text('التكلفة: ${product.costPrice?.toStringAsFixed(2) ?? '-'}'),
                        onTap: () => _selectProduct(product),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              // اختيار الوحدة
              if (_selectedProduct != null)
                DropdownButtonFormField<String>(
                  value: _selectedUnit,
                  decoration: const InputDecoration(labelText: 'الوحدة في الفاتورة'),
                  items: _availableUnits.map((unit) {
                    String label = unit;
                    if (unit != 'قطعة' && _unitQuantities.containsKey(unit)) {
                      label = '$unit (${_unitQuantities[unit]} قطعة)';
                    }
                    return DropdownMenuItem(value: unit, child: Text(label));
                  }).toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedUnit = v;
                      _recalculateCost();
                    });
                  },
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityCtrl,
                decoration: InputDecoration(
                  labelText: 'الكمية ($_selectedUnit)',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'أدخل كمية صحيحة' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _totalPriceCtrl,
                decoration: InputDecoration(
                  labelText: 'سعر التكلفة (لـ $_selectedUnit)',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _recalculateCost(),
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'أدخل سعر صحيح' : null,
              ),
              const SizedBox(height: 12),
              // التكلفة المحسوبة للقطعة
              if (_calculatedCostCtrl.text.isNotEmpty && _selectedUnit != 'قطعة')
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تكلفة القطعة: ${_calculatedCostCtrl.text} دينار',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            
            final quantity = double.parse(_quantityCtrl.text.trim());
            final totalPriceForUnit = double.parse(_totalPriceCtrl.text.trim());
            
            // حساب سعر القطعة
            double unitPricePerPiece;
            if (_selectedUnit == 'قطعة') {
              unitPricePerPiece = totalPriceForUnit;
            } else {
              final unitQty = _unitQuantities[_selectedUnit] ?? 1;
              unitPricePerPiece = totalPriceForUnit / unitQty;
            }
            
            final item = SupplierInvoiceItem(
              invoiceId: 0, // سيتم تحديثه لاحقاً
              productId: _selectedProduct?.id,
              productName: _productNameCtrl.text.trim(),
              quantity: quantity,
              unitPrice: unitPricePerPiece, // سعر القطعة الواحدة
              totalPrice: quantity * totalPriceForUnit, // الإجمالي في الفاتورة
              unit: _selectedUnit,
              notes: _selectedUnit != 'قطعة' 
                ? 'من $_selectedUnit (${_unitQuantities[_selectedUnit]} قطعة) بسعر $totalPriceForUnit'
                : null,
              createdAt: DateTime.now(),
            );
            
            widget.onAdd(item);
            Navigator.pop(context);
          },
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';

import '../models/supplier.dart';
import '../services/suppliers_service.dart';

class NewSupplierReceiptScreen extends StatefulWidget {
  final Supplier supplier;
  const NewSupplierReceiptScreen({Key? key, required this.supplier}) : super(key: key);

  @override
  State<NewSupplierReceiptScreen> createState() => _NewSupplierReceiptScreenState();
}

class _NewSupplierReceiptScreenState extends State<NewSupplierReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _methodCtrl = TextEditingController(text: 'نقد');
  bool _saving = false;
  Uint8List? _pickedBytes;
  String? _pickedMime;
  String? _pickedName;
  final NumberFormat _nf = NumberFormat('#,##0.##', 'en');
  bool _formatting = false;

  final SuppliersService _service = SuppliersService();

  @override
  void dispose() {
    _dateCtrl.dispose();
    _numberCtrl.dispose();
    _amountCtrl.dispose();
    _methodCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سند قبض جديد')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text('المورد: ${widget.supplier.companyName}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dateCtrl,
                decoration: const InputDecoration(labelText: 'تاريخ السند (ISO yyyy-MM-dd)'),
                validator: (v) => (v == null || v.isEmpty) ? 'أدخل التاريخ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _numberCtrl,
                decoration: const InputDecoration(labelText: 'رقم السند (اختياري)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'المبلغ'),
                keyboardType: TextInputType.number,
                onChanged: (_) => _onFormatNumber(_amountCtrl),
                validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '')) == null) ? 'أدخل رقم صحيح' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _methodCtrl,
                decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(_pickedName == null ? 'إرفاق ملف (اختياري)' : _pickedName!),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _onPickAttachment,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('اختيار'),
                    ),
                    if (_pickedBytes != null)
                      IconButton(
                        tooltip: 'إزالة',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() { _pickedBytes = null; _pickedMime = null; _pickedName = null; }),
                      )
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                  label: const Text('حفظ'),
                  onPressed: _saving ? null : _onSave,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    
    // منع الضغط المتكرر
    if (_saving) return;
    
    setState(() => _saving = true);
    
    try {
      print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🚀 بدء عملية حفظ سند القبض...');
      
      final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
      
      final rec = SupplierReceipt(
        supplierId: widget.supplier.id!,
        receiptNumber: _numberCtrl.text.trim().isEmpty ? null : _numberCtrl.text.trim(),
        receiptDate: DateTime.tryParse(_dateCtrl.text.trim()) ?? DateTime.now(),
        amount: amount,
        paymentMethod: _methodCtrl.text.trim().isEmpty ? 'نقد' : _methodCtrl.text.trim(),
      );
      
      // الخطوة 1: حفظ سند القبض
      print('📝 [1/2] حفظ سند القبض...');
      final id = await _service.insertSupplierReceipt(rec);
      print('✅ تم حفظ سند القبض برقم: $id');
      
      // الخطوة 2: حفظ المرفق (إذا وجد)
      if (_pickedBytes != null && _pickedMime != null) {
        print('📎 [2/2] حفظ المرفق...');
        final ext = _pickedMime == 'application/pdf' ? 'pdf' : (_pickedMime == 'image/png' ? 'png' : 'jpg');
        final path = await _service.saveAttachmentFile(bytes: _pickedBytes!, extension: ext);
        await _service.insertAttachment(Attachment(
          ownerType: 'SupplierReceipt',
          ownerId: id,
          filePath: path,
          fileType: ext == 'pdf' ? 'pdf' : 'image',
          extractedText: null,
          extractionConfidence: null,
        ));
        print('✅ تم حفظ المرفق');
      } else {
        print('⏭️ [2/2] لا يوجد مرفق');
      }
      
      print('✅ اكتملت جميع العمليات بنجاح');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // العودة إلى الشاشة السابقة
      if (!mounted) return;
      Navigator.of(context).pop(true);
      
    } catch (e, stackTrace) {
      print('❌ خطأ في الحفظ: $e');
      print('Stack trace: $stackTrace');
      
      if (!mounted) return;
      
      // عرض رسالة خطأ واضحة
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('❌ فشل الحفظ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('حدث خطأ أثناء حفظ سند القبض:'),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
      
      // إعادة تفعيل الزر في حالة الخطأ فقط
      if (mounted) setState(() => _saving = false);
    }
    // ملاحظة: لا يوجد finally هنا - الزر يبقى معطلاً حتى تكتمل العملية أو يحدث خطأ
  }

  Future<void> _onPickAttachment() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : 'image/jpeg');
    setState(() {
      _pickedBytes = file.bytes!;
      _pickedMime = mime;
      _pickedName = file.name;
    });
  }

  void _onFormatNumber(TextEditingController ctrl) {
    if (_formatting) return;
    _formatting = true;
    final raw = ctrl.text.replaceAll(',', '').trim();
    if (raw.isEmpty) { _formatting = false; return; }
    final val = double.tryParse(raw);
    if (val != null) {
      ctrl.text = _nf.format(val);
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
    _formatting = false;
  }
}


import 'package:flutter/material.dart';
import '../models/supplier.dart';
import 'package:intl/intl.dart' as intl;

class SupplierRichCard extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const SupplierRichCard({
    super.key,
    required this.supplier,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final hasDebt = supplier.hasDebt;
    final totalBalance = supplier.totalDebt;
    final totalPaid = supplier.totalPayments.toDouble(); // Assuming we track this
    final totalVolume = totalBalance + totalPaid;
    final progress = totalVolume > 0 ? (totalPaid / totalVolume) : 0.0;
    
    // Determine currency logic safely
    final currencySymbol = supplier.currency == 'USD' ? '\$' : 'د.ع';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          border: Border.all(color: Colors.grey.withOpacity(0.1)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // DELETE BUTTON HOVER EFFECT (Simulated by simple position)
              Positioned(
                top: 12,
                left: 12,
                child: IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.grey[400], size: 20),
                  onPressed: onDelete,
                  tooltip: 'حذف المورد',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[50],
                    hoverColor: Colors.red.withOpacity(0.1),
                    focusColor: Colors.red.withOpacity(0.1),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // HEADER
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF455A64), Color(0xFF607D8B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF455A64).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                supplier.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  supplier.paymentTerms == 'credit' ? 'آجل' : 'نقدي', // Simplified category logic
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    const Spacer(),

                    // STATS ROW
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildMiniStat('الفواتير', '${supplier.totalInvoices}'),
                          // Note: totalPayments might need updates in Supplier model to be accurate
                          _buildMiniStat('المدفوعات', '${supplier.totalPayments}'), 
                        ],
                      ),
                    ),

                    // FINANCIALS
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'الرصيد المتبقي',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        ),
                        Text(
                          '${_formatCurrency(supplier.totalDebt)} $currencySymbol',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: hasDebt ? const Color(0xFFEF4444) : const Color(0xFF10B981), // Red if debt, Green if clean
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // PROGRESS BAR
                    Stack(
                      children: [
                        Container(
                          height: 6,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6), // Blue 500
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // ACTION BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onTap,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF334155),
                          elevation: 0,
                          side: BorderSide(color: Colors.grey[200]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'عرض التفاصيل',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF334155)),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
      ],
    );
  }

  String _formatCurrency(double amount) {
    return intl.NumberFormat("#,##0", "en_US").format(amount);
  }
}
 