import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as path;

void main() async {
  // تهيئة sqflite للعمل على Windows
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

  final db = await openDatabase(dbPath);

  // فحص الفاتورة رقم 140
  print('\n═══════════════════════════════════════════════════════════════════');
  print('فحص الفاتورة رقم 140:');
  print('═══════════════════════════════════════════════════════════════════');

  final invoice140 = await db.query(
    'invoices',
    where: 'id = ?',
    whereArgs: [140],
  );

  if (invoice140.isNotEmpty) {
    final inv = invoice140.first;
    print('العميل: ${inv['customer_name']}');
    print('المجموع (total_amount): ${inv['total_amount']}');
    print('الخصم (discount): ${inv['discount']}');
    print('أجور التحميل (loading_fee): ${inv['loading_fee']}');
    print('المبلغ المدفوع: ${inv['amount_paid_on_invoice']}');
    print('نوع الدفع: ${inv['payment_type']}');
    print('التاريخ: ${inv['invoice_date']}');
  }

  // فحص بنود الفاتورة
  print('\n═══════════════════════════════════════════════════════════════════');
  print('بنود الفاتورة رقم 140:');
  print('═══════════════════════════════════════════════════════════════════');

  final items140 = await db.query(
    'invoice_items',
    where: 'invoice_id = ?',
    whereArgs: [140],
  );

  double totalItems = 0;
  for (var item in items140) {
    final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0;
    totalItems += itemTotal;
    print('${item['product_name']}: ${item['item_total']}');
  }

  print('\n═══════════════════════════════════════════════════════════════════');
  print('الحساب:');
  print('═══════════════════════════════════════════════════════════════════');
  print('مجموع البنود: $totalItems');
  
  if (invoice140.isNotEmpty) {
    final inv = invoice140.first;
    final totalAmount = (inv['total_amount'] as num?)?.toDouble() ?? 0;
    final discount = (inv['discount'] as num?)?.toDouble() ?? 0;
    final loadingFee = (inv['loading_fee'] as num?)?.toDouble() ?? 0;
    
    print('الخصم: $discount');
    print('أجور التحميل: $loadingFee');
    print('المجموع الصحيح (بنود - خصم + تحميل): ${totalItems - discount + loadingFee}');
    print('المجموع المعروض: $totalAmount');
    print('الفرق: ${totalAmount - (totalItems - discount + loadingFee)}');
  }

  await db.close();
}
