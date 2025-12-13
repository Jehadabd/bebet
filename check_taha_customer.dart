// سكريبت لفحص مشكلة العميل "طه العدنان الحمد المؤسس" والفاتورة 191
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = '${Platform.environment['APPDATA']}/com.example/debt_book/debt_book.db';
  print('📂 فتح قاعدة البيانات: $dbPath');
  
  final db = await openDatabase(dbPath, readOnly: true);

  print('\n' + '=' * 80);
  print('🔍 البحث عن العميل "طه العدنان الحمد المؤسس"');
  print('=' * 80);

  // البحث عن العميل
  final customers = await db.rawQuery('''
    SELECT * FROM customers 
    WHERE name LIKE '%طه%العدنان%' OR name LIKE '%طه العدنان%'
  ''');

  if (customers.isEmpty) {
    print('❌ لم يتم العثور على العميل');
    await db.close();
    return;
  }

  final customer = customers.first;
  final customerId = customer['id'] as int;
  final customerName = customer['name'] as String;
  final currentDebt = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;

  print('✅ تم العثور على العميل:');
  print('   - ID: $customerId');
  print('   - الاسم: $customerName');
  print('   - الرصيد المسجل: $currentDebt');

  print('\n' + '=' * 80);
  print('📋 فحص الفاتورة رقم 191');
  print('=' * 80);

  // فحص الفاتورة 191
  final invoice191 = await db.rawQuery('SELECT * FROM invoices WHERE id = 191');
  
  if (invoice191.isEmpty) {
    print('❌ الفاتورة 191 غير موجودة');
  } else {
    final inv = invoice191.first;
    print('✅ الفاتورة 191:');
    print('   - customer_id: ${inv['customer_id']}');
    print('   - customer_name: ${inv['customer_name']}');
    print('   - total_amount: ${inv['total_amount']}');
    print('   - amount_paid_on_invoice: ${inv['amount_paid_on_invoice']}');
    print('   - payment_type: ${inv['payment_type']}');
    print('   - status: ${inv['status']}');
    print('   - invoice_date: ${inv['invoice_date']}');
    print('   - created_at: ${inv['created_at']}');
    
    // فحص المعاملات المرتبطة بالفاتورة 191
    final txFor191 = await db.rawQuery('''
      SELECT * FROM transactions WHERE invoice_id = 191
    ''');
    
    print('\n   📊 المعاملات المرتبطة بالفاتورة 191: ${txFor191.length}');
    for (final tx in txFor191) {
      print('      - ID: ${tx['id']}, amount: ${tx['amount_changed']}, type: ${tx['transaction_type']}');
    }
    
    if (txFor191.isEmpty) {
      print('   ⚠️ لا توجد معاملات مرتبطة بهذه الفاتورة!');
    }
  }

  print('\n' + '=' * 80);
  print('📋 جميع فواتير العميل');
  print('=' * 80);

  final allInvoices = await db.rawQuery('''
    SELECT * FROM invoices 
    WHERE customer_id = ? OR customer_name LIKE '%طه%العدنان%'
    ORDER BY invoice_date ASC
  ''', [customerId]);

  print('عدد الفواتير: ${allInvoices.length}');
  for (final inv in allInvoices) {
    final invId = inv['id'];
    final total = inv['total_amount'];
    final paid = inv['amount_paid_on_invoice'];
    final type = inv['payment_type'];
    final status = inv['status'];
    final date = inv['invoice_date'];
    final custId = inv['customer_id'];
    
    // فحص المعاملات لهذه الفاتورة
    final txCount = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM transactions WHERE invoice_id = ?', 
      [invId]
    );
    final txNum = txCount.first['cnt'] as int;
    
    final hasIssue = type == 'دين' && txNum == 0 ? '⚠️' : '✅';
    print('$hasIssue فاتورة #$invId: $total دينار, مدفوع: $paid, نوع: $type, حالة: $status, تاريخ: $date, customer_id: $custId, معاملات: $txNum');
  }

  print('\n' + '=' * 80);
  print('📊 جميع معاملات العميل');
  print('=' * 80);

  final allTx = await db.rawQuery('''
    SELECT * FROM transactions 
    WHERE customer_id = ?
    ORDER BY transaction_date ASC, id ASC
  ''', [customerId]);

  print('عدد المعاملات: ${allTx.length}');
  double runningBalance = 0.0;
  for (final tx in allTx) {
    final txId = tx['id'];
    final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
    final balanceBefore = (tx['balance_before_transaction'] as num?)?.toDouble();
    final balanceAfter = (tx['new_balance_after_transaction'] as num?)?.toDouble() ?? 0.0;
    final type = tx['transaction_type'];
    final invoiceId = tx['invoice_id'];
    final date = tx['transaction_date'];
    final note = tx['transaction_note'] ?? tx['description'];
    
    runningBalance += amount;
    
    final invoiceInfo = invoiceId != null ? ' [فاتورة #$invoiceId]' : '';
    print('TX#$txId: $amount, قبل: $balanceBefore, بعد: $balanceAfter, نوع: $type$invoiceInfo, تاريخ: $date');
    print('        ملاحظة: $note');
  }

  print('\n' + '=' * 80);
  print('📈 ملخص التحليل');
  print('=' * 80);

  // حساب الرصيد من المعاملات
  final sumResult = await db.rawQuery('''
    SELECT COALESCE(SUM(amount_changed), 0) as total 
    FROM transactions 
    WHERE customer_id = ?
  ''', [customerId]);
  final calculatedBalance = (sumResult.first['total'] as num?)?.toDouble() ?? 0.0;

  // حساب ديون الفواتير التي ليس لها معاملات
  final missingTxInvoices = await db.rawQuery('''
    SELECT i.id, i.total_amount, i.amount_paid_on_invoice, i.payment_type
    FROM invoices i
    WHERE (i.customer_id = ? OR i.customer_name LIKE '%طه%العدنان%')
      AND i.payment_type = 'دين'
      AND i.status = 'محفوظة'
      AND NOT EXISTS (SELECT 1 FROM transactions t WHERE t.invoice_id = i.id)
  ''', [customerId]);

  double missingDebt = 0.0;
  print('\n⚠️ فواتير دين بدون معاملات:');
  for (final inv in missingTxInvoices) {
    final invId = inv['id'];
    final total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
    final paid = (inv['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
    final remaining = total - paid;
    missingDebt += remaining;
    print('   - فاتورة #$invId: إجمالي $total, مدفوع $paid, متبقي $remaining');
  }

  print('\n📊 النتائج:');
  print('   - الرصيد المسجل للعميل: $currentDebt');
  print('   - الرصيد المحسوب من المعاملات: $calculatedBalance');
  print('   - ديون فواتير بدون معاملات: $missingDebt');
  print('   - الرصيد الصحيح المتوقع: ${calculatedBalance + missingDebt}');
  
  final diff = currentDebt - (calculatedBalance + missingDebt);
  if (diff.abs() > 0.01) {
    print('   ❌ فرق: $diff');
  } else {
    print('   ✅ الرصيد متطابق');
  }

  await db.close();
  print('\n✅ انتهى الفحص');
}
