// سكريبت لتحليل بيانات عميل الهايس / شركة السنابل الذهبية
// للبحث عن سبب الفرق بين مجموع الفواتير والرصيد الظاهر

import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final dbPath = '${Platform.environment['APPDATA']}/com.example/debt_book/debt_book.db';
  print('📂 مسار قاعدة البيانات: $dbPath');
  
  final db = await openDatabase(dbPath, readOnly: true);
  
  // البحث عن العميل
  print('\n' + '=' * 80);
  print('🔍 البحث عن العميل: الهايس / شركة السنابل الذهبية');
  print('=' * 80);
  
  // التحقق من أعمدة جدول العملاء
  final custCols = await db.rawQuery("PRAGMA table_info(customers)");
  print('أعمدة جدول العملاء:');
  for (final col in custCols) {
    print('  - ${col['name']}');
  }
  print('');
  
  // البحث عن جميع العملاء
  final customers = await db.rawQuery('''
    SELECT c.*, 
           (SELECT SUM(amount_changed) FROM transactions WHERE customer_id = c.id) as calc_debt
    FROM customers c
    WHERE c.name LIKE '%سنابل%' OR c.name LIKE '%هايس%'
  ''');
  
  print('العملاء الموجودين:');
  for (final c in customers) {
    print('  - ${c['name']} (ID: ${c['id']}) | المحسوب: ${c['calc_debt']}');
  }
  print('');
  
  if (customers.isEmpty) {
    print('❌ لم يتم العثور على العميل');
    await db.close();
    return;
  }
  
  for (final customer in customers) {
    final customerId = customer['id'] as int;
    final customerName = customer['name'];
    final customerDebt = customer['calc_debt'];
    
    print('\n📋 العميل: $customerName (ID: $customerId)');
    print('💰 الدين المسجل في جدول العملاء: $customerDebt');
    
    // جلب جميع الفواتير
    print('\n' + '-' * 60);
    print('📄 الفواتير:');
    print('-' * 60);
    
    // أولاً نتحقق من أعمدة جدول الفواتير
    final tableInfo = await db.rawQuery("PRAGMA table_info(invoices)");
    print('  أعمدة جدول الفواتير:');
    for (final col in tableInfo) {
      print('    - ${col['name']}');
    }
    print('');
    
    final invoices = await db.rawQuery('''
      SELECT * FROM invoices 
      WHERE customer_id = ? AND status = 'محفوظة'
      ORDER BY invoice_date ASC, id ASC
    ''', [customerId]);
    
    double totalInvoiceAmount = 0;
    double totalPaidOnInvoices = 0;
    double totalRemainingOnInvoices = 0;
    int debtInvoicesCount = 0;
    int cashInvoicesCount = 0;
    
    for (final inv in invoices) {
      final invId = inv['id'];
      final date = inv['invoice_date'];
      final total = (inv['total_amount'] as num?)?.toDouble() ?? 0;
      final paymentType = inv['payment_type'];
      
      // حساب المدفوع من المعاملات
      final paidResult = await db.rawQuery('''
        SELECT COALESCE(SUM(ABS(amount_changed)), 0) as paid
        FROM transactions 
        WHERE invoice_id = ? AND amount_changed < 0
      ''', [invId]);
      final paid = (paidResult.first['paid'] as num?)?.toDouble() ?? 0;
      final remaining = total - paid;
      
      if (paymentType == 'دين') {
        debtInvoicesCount++;
        totalInvoiceAmount += total;
        totalPaidOnInvoices += paid;
        totalRemainingOnInvoices += remaining;
      } else {
        cashInvoicesCount++;
      }
      
      print('  فاتورة #$invId | $date | $paymentType | المبلغ: $total | المدفوع: $paid | المتبقي: $remaining');
    }
    
    print('\n📊 ملخص الفواتير:');
    print('  - عدد فواتير الدين: $debtInvoicesCount');
    print('  - عدد فواتير النقد: $cashInvoicesCount');
    print('  - إجمالي مبالغ فواتير الدين: $totalInvoiceAmount');
    print('  - إجمالي المدفوع على الفواتير: $totalPaidOnInvoices');
    print('  - إجمالي المتبقي على الفواتير: $totalRemainingOnInvoices');
    
    // جلب جميع المعاملات
    print('\n' + '-' * 60);
    print('💳 المعاملات (سجل الديون):');
    print('-' * 60);
    
    final transactions = await db.rawQuery('''
      SELECT t.*, i.id as inv_id
      FROM transactions t
      LEFT JOIN invoices i ON t.invoice_id = i.id
      WHERE t.customer_id = ?
      ORDER BY t.transaction_date ASC, t.id ASC
    ''', [customerId]);
    
    double totalDebtAdded = 0;
    double totalPayments = 0;
    
    for (final tx in transactions) {
      final txId = tx['id'];
      final date = tx['transaction_date'];
      final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0;
      final type = tx['transaction_type'];
      final invoiceId = tx['invoice_id'];
      final balanceBefore = tx['balance_before'];
      final balanceAfter = tx['balance_after'];
      final note = tx['transaction_note'] ?? '';
      
      if (amount > 0) {
        totalDebtAdded += amount;
      } else {
        totalPayments += amount.abs();
      }
      
      String invoiceInfo = invoiceId != null ? '(فاتورة #$invoiceId)' : '(يدوي)';
      print('  معاملة #$txId | $date | $type | المبلغ: $amount | قبل: $balanceBefore | بعد: $balanceAfter $invoiceInfo');
      if (note.toString().isNotEmpty) print('    ملاحظة: $note');
    }
    
    print('\n📊 ملخص المعاملات:');
    print('  - إجمالي الديون المضافة: $totalDebtAdded');
    print('  - إجمالي المدفوعات: $totalPayments');
    print('  - الصافي (الدين الحالي): ${totalDebtAdded - totalPayments}');
    
    // جلب سجل تعديلات الفواتير
    print('\n' + '-' * 60);
    print('📝 سجل تعديلات الفواتير (Snapshots):');
    print('-' * 60);
    
    for (final inv in invoices) {
      final invId = inv['id'] as int;
      
      final snapshots = await db.rawQuery('''
        SELECT * FROM invoice_snapshots 
        WHERE invoice_id = ?
        ORDER BY created_at ASC
      ''', [invId]);
      
      if (snapshots.isNotEmpty) {
        print('\n  📄 فاتورة #$invId:');
        for (final snap in snapshots) {
          final snapType = snap['snapshot_type'];
          final snapDate = snap['created_at'];
          final snapTotal = snap['total_amount'];
          final snapPaid = snap['amount_paid'];
          final snapPaymentType = snap['payment_type'];
          print('    - $snapType | $snapDate | المبلغ: $snapTotal | المدفوع: $snapPaid | النوع: $snapPaymentType');
        }
      }
    }
    
    // التحقق من التطابق
    print('\n' + '=' * 80);
    print('🔍 التحليل والمقارنة:');
    print('=' * 80);
    print('  الدين المسجل في جدول العملاء: $customerDebt');
    print('  الدين المحسوب من المعاملات: ${totalDebtAdded - totalPayments}');
    print('  المتبقي على الفواتير: $totalRemainingOnInvoices');
    
    final debtFromTx = totalDebtAdded - totalPayments;
    final customerDebtNum = (customerDebt as num?)?.toDouble() ?? 0;
    if (customerDebtNum != debtFromTx) {
      print('\n⚠️ هناك فرق بين الدين المسجل والمحسوب!');
      print('  الفرق: ${customerDebtNum - debtFromTx}');
    }
    
    if (debtFromTx != totalRemainingOnInvoices) {
      print('\n⚠️ هناك فرق بين الدين من المعاملات والمتبقي على الفواتير!');
      print('  الفرق: ${debtFromTx - totalRemainingOnInvoices}');
    }
  }
  
  await db.close();
  print('\n✅ انتهى التحليل');
}
