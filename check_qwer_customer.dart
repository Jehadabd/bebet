// سكريبت للتحقق من بيانات العميل qwer
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final dbPath = '${Platform.environment['APPDATA']}/com.example/debt_book/debt_book.db';
  print('فتح قاعدة البيانات: $dbPath');
  
  final db = await openDatabase(dbPath, readOnly: true);
  
  // البحث عن العميل
  print('\n=== بيانات العميل ===');
  final customers = await db.query('customers', where: "name LIKE '%qwer%'");
  if (customers.isEmpty) {
    print('لم يتم العثور على العميل');
    await db.close();
    return;
  }
  
  final customer = customers.first;
  final customerId = customer['id'] as int;
  print('ID: $customerId');
  print('الاسم: ${customer['name']}');
  print('الرصيد الحالي: ${customer['current_total_debt']}');
  
  // جلب الفواتير
  print('\n=== الفواتير ===');
  final invoices = await db.query(
    'invoices',
    where: 'customer_id = ?',
    whereArgs: [customerId],
    orderBy: 'invoice_date ASC, id ASC',
  );
  
  for (final inv in invoices) {
    final invoiceId = inv['id'];
    final totalAmount = (inv['total_amount'] as num?)?.toDouble() ?? 0;
    final paidAmount = (inv['paid_amount'] as num?)?.toDouble() ?? 0;
    final remaining = totalAmount - paidAmount;
    
    print('---');
    print('فاتورة #$invoiceId');
    print('  التاريخ: ${inv['invoice_date']}');
    print('  المبلغ الإجمالي: $totalAmount');
    print('  المبلغ المدفوع على الفاتورة: $paidAmount');
    print('  المتبقي على الفاتورة: $remaining');
    print('  نوع الدفع: ${inv['payment_type']}');
    print('  الحالة: ${inv['status']}');
    
    // جلب المعاملات المرتبطة بهذه الفاتورة
    final invoiceTx = await db.query(
      'transactions',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
      orderBy: 'transaction_date ASC, id ASC',
    );
    
    double invoiceNetDebt = 0;
    print('  --- معاملات الفاتورة ---');
    for (final tx in invoiceTx) {
      final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0;
      invoiceNetDebt += amount;
      print('    ${tx['transaction_type']}: $amount (الرصيد بعد: ${tx['new_balance_after_transaction']})');
    }
    print('  صافي دين الفاتورة من المعاملات: $invoiceNetDebt');
  }
  
  // جلب المعاملات اليدوية
  print('\n=== المعاملات اليدوية ===');
  final manualTx = await db.query(
    'transactions',
    where: 'customer_id = ? AND invoice_id IS NULL',
    whereArgs: [customerId],
    orderBy: 'transaction_date ASC, id ASC',
  );
  
  double manualDebt = 0;
  double manualPayment = 0;
  
  for (final tx in manualTx) {
    final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0;
    print('${tx['transaction_type']}: $amount');
    if (amount > 0) {
      manualDebt += amount;
    } else {
      manualPayment += amount.abs();
    }
  }
  
  print('\n=== الملخص ===');
  print('إجمالي الديون اليدوية: $manualDebt');
  print('إجمالي المدفوعات اليدوية: $manualPayment');
  print('صافي اليدوي: ${manualDebt - manualPayment}');
  print('رصيد العميل المخزن: ${customer['current_total_debt']}');
  
  // حساب من كل المعاملات
  final allTx = await db.query(
    'transactions',
    where: 'customer_id = ?',
    whereArgs: [customerId],
  );
  
  double totalFromTx = 0;
  for (final tx in allTx) {
    totalFromTx += (tx['amount_changed'] as num?)?.toDouble() ?? 0;
  }
  print('مجموع كل المعاملات: $totalFromTx');
  
  // جلب سجل تعديلات الفاتورة
  print('\n=== سجل تعديلات الفاتورة #342 ===');
  final history = await db.query(
    'invoice_snapshots',
    where: 'invoice_id = ?',
    whereArgs: [342],
    orderBy: 'created_at ASC',
  );
  
  for (int i = 0; i < history.length; i++) {
    final h = history[i];
    print('---');
    print('نسخة #${h['version_number']}');
    print('  التاريخ: ${h['created_at']}');
    print('  الإجمالي: ${h['total_amount']}');
    print('  نوع الدفع: ${h['payment_type']}');
    print('  نوع التغيير: ${h['change_type']}');
  }
  
  await db.close();
}
