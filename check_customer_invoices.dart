// سكريبت لفحص فواتير عميل معين
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

void main() async {
  // تهيئة sqflite للعمل على سطح المكتب
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // مسار قاعدة البيانات
  final dbPath = path.join(
    Platform.environment['APPDATA'] ?? '',
    'com.example',
    'debt_book',
    'debt_book.db',
  );

  print('مسار قاعدة البيانات: $dbPath');

  if (!File(dbPath).existsSync()) {
    print('قاعدة البيانات غير موجودة!');
    return;
  }

  final db = await openDatabase(dbPath);

  // البحث عن العميل "ليبان العلوان"
  final customers = await db.rawQuery('''
    SELECT * FROM customers WHERE name LIKE '%ليبان%' OR name LIKE '%العلوان%'
  ''');

  print('\n=== العملاء الذين يحتوي اسمهم على "ليبان" أو "العلوان" ===');
  for (final c in customers) {
    print('ID: ${c['id']}, الاسم: ${c['name']}, الدين الحالي: ${c['current_total_debt']}');
  }

  if (customers.isEmpty) {
    print('لم يتم العثور على عميل بهذا الاسم');
    await db.close();
    return;
  }

  final customerId = customers.first['id'] as int;
  final customerName = customers.first['name'] as String;

  print('\n=== فواتير العميل "$customerName" (ID: $customerId) ===');
  
  // جلب جميع الفواتير لهذا العميل
  final allInvoices = await db.rawQuery('''
    SELECT id, customer_name, invoice_date, total_amount, discount, status, customer_id
    FROM invoices
    WHERE customer_id = ? OR (customer_id IS NULL AND customer_name = ?)
    ORDER BY invoice_date DESC
  ''', [customerId, customerName]);

  print('\nجميع الفواتير (${allInvoices.length} فاتورة):');
  double totalAll = 0;
  for (final inv in allInvoices) {
    final amount = (inv['total_amount'] as num?)?.toDouble() ?? 0;
    totalAll += amount;
    print('  ID: ${inv['id']}, التاريخ: ${inv['invoice_date']}, المبلغ: $amount, الحالة: ${inv['status']}, customer_id: ${inv['customer_id']}');
  }
  print('إجمالي جميع الفواتير: $totalAll');

  // جلب الفواتير من 2025-12-01 فما فوق
  print('\n=== الفواتير من 2025-12-01 فما فوق (المحفوظة فقط) ===');
  final dec2025Invoices = await db.rawQuery('''
    SELECT id, customer_name, invoice_date, total_amount, discount, status, customer_id
    FROM invoices
    WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = ?))
      AND status = 'محفوظة'
      AND DATE(invoice_date) >= '2025-12-01'
    ORDER BY invoice_date DESC
  ''', [customerId, customerName]);

  print('الفواتير من ديسمبر 2025 (${dec2025Invoices.length} فاتورة):');
  double totalDec = 0;
  for (final inv in dec2025Invoices) {
    final amount = (inv['total_amount'] as num?)?.toDouble() ?? 0;
    totalDec += amount;
    print('  ID: ${inv['id']}, التاريخ: ${inv['invoice_date']}, المبلغ: $amount, الخصم: ${inv['discount']}');
    
    // جلب عناصر الفاتورة
    final items = await db.rawQuery('''
      SELECT product_name, quantity_large_unit, quantity_individual, applied_price, item_total
      FROM invoice_items
      WHERE invoice_id = ?
    ''', [inv['id']]);
    
    double itemsTotal = 0;
    for (final item in items) {
      final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0;
      itemsTotal += itemTotal;
      print('    - ${item['product_name']}: كمية كبيرة=${item['quantity_large_unit']}, كمية فردية=${item['quantity_individual']}, السعر=${item['applied_price']}, الإجمالي=$itemTotal');
    }
    print('    مجموع العناصر: $itemsTotal');
  }
  print('\nإجمالي فواتير ديسمبر 2025: $totalDec');

  // تشغيل نفس الاستعلام المستخدم في التقارير
  print('\n=== نتيجة استعلام التقارير ===');
  final reportResult = await db.rawQuery('''
    SELECT 
      SUM(total_amount) as total_sales,
      COUNT(*) as total_invoices
    FROM invoices
    WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = ?))
      AND status = 'محفوظة'
      AND DATE(invoice_date) >= '2025-12-01'
  ''', [customerId, customerName]);

  print('المبيعات: ${reportResult.first['total_sales']}');
  print('عدد الفواتير: ${reportResult.first['total_invoices']}');

  // تشغيل استعلام getCustomerYearlyData
  print('\n=== نتيجة استعلام getCustomerYearlyData ===');
  final yearlyResult = await db.rawQuery('''
    SELECT 
      strftime('%Y', invoice_date) as year,
      strftime('%m', invoice_date) as month,
      SUM(total_amount) as total_sales,
      COUNT(*) as total_invoices
    FROM invoices
    WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = ?))
      AND status = 'محفوظة'
      AND DATE(invoice_date) >= '2025-12-01'
    GROUP BY strftime('%Y', invoice_date), strftime('%m', invoice_date)
    ORDER BY year DESC, month DESC
  ''', [customerId, customerName]);

  for (final row in yearlyResult) {
    print('السنة: ${row['year']}, الشهر: ${row['month']}, المبيعات: ${row['total_sales']}, الفواتير: ${row['total_invoices']}');
  }

  // تشغيل استعلام getCustomerMonthlyData للسنة 2025
  print('\n=== نتيجة استعلام getCustomerMonthlyData للسنة 2025 ===');
  final monthlyResult = await db.rawQuery('''
    SELECT 
      strftime('%m', invoice_date) AS month,
      SUM(total_amount) AS total_sales,
      COUNT(DISTINCT id) AS total_invoices
    FROM invoices
    WHERE (customer_id = ? OR (customer_id IS NULL AND customer_name = ?))
      AND strftime('%Y', invoice_date) = '2025' 
      AND status = 'محفوظة'
      AND DATE(invoice_date) >= '2025-12-01'
    GROUP BY strftime('%m', invoice_date)
  ''', [customerId, customerName]);

  for (final row in monthlyResult) {
    print('الشهر: ${row['month']}, المبيعات: ${row['total_sales']}, الفواتير: ${row['total_invoices']}');
  }

  await db.close();
  print('\nتم الانتهاء!');
}
