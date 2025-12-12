// تحليل تفصيلي لعميل السنابل الذهبية مع سجل التعديلات
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final dbPath = '${Platform.environment['APPDATA']}/com.example/debt_book/debt_book.db';
  final db = await openDatabase(dbPath, readOnly: true);
  
  final customerId = 448; // الهايس / شركه السنابل الذهبية
  
  print('=' * 100);
  print('تحليل تفصيلي لعميل: الهايس / شركه السنابل الذهبية (ID: $customerId)');
  print('=' * 100);
  
  // جلب الفواتير مع كل التفاصيل
  final invoices = await db.rawQuery('''
    SELECT * FROM invoices 
    WHERE customer_id = ? AND status = 'محفوظة'
    ORDER BY invoice_date ASC
  ''', [customerId]);
  
  print('\n📄 تحليل كل فاتورة مع معاملاتها وسجل التعديلات:');
  print('-' * 100);
  
  double totalInvoiceAmounts = 0;
  double totalNetDebt = 0;
  
  for (final inv in invoices) {
    final invId = inv['id'] as int;
    final total = (inv['total_amount'] as num?)?.toDouble() ?? 0;
    final finalTotal = (inv['final_total'] as num?)?.toDouble() ?? total;
    final discount = (inv['discount'] as num?)?.toDouble() ?? 0;
    final loadingFee = (inv['loading_fee'] as num?)?.toDouble() ?? 0;
    final amountPaidOnInvoice = (inv['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0;
    final paymentType = inv['payment_type'];
    final date = inv['invoice_date'];
    final createdAt = inv['created_at'];
    final lastModified = inv['last_modified_at'];
    
    totalInvoiceAmounts += total;
    
    // جلب المعاملات المرتبطة بهذه الفاتورة
    final txs = await db.rawQuery('''
      SELECT * FROM transactions 
      WHERE invoice_id = ?
      ORDER BY transaction_date ASC
    ''', [invId]);
    
    double netDebt = 0;
    for (final tx in txs) {
      netDebt += (tx['amount_changed'] as num?)?.toDouble() ?? 0;
    }
    totalNetDebt += netDebt;
    
    print('\n' + '=' * 100);
    print('📄 فاتورة #$invId');
    print('=' * 100);
    print('   📅 تاريخ الفاتورة: $date');
    print('   📅 تاريخ الإنشاء: $createdAt');
    print('   📅 آخر تعديل: $lastModified');
    print('   💳 نوع الدفع: $paymentType');
    print('   💰 مبلغ الفاتورة (total_amount): $total');
    print('   💰 المبلغ النهائي (final_total): $finalTotal');
    print('   🏷️ الخصم: $discount');
    print('   🚚 أجور التحميل: $loadingFee');
    print('   💵 المدفوع على الفاتورة: $amountPaidOnInvoice');
    print('   📊 صافي الدين من المعاملات: $netDebt');
    if (total != netDebt) {
      print('   ⚠️ الفرق بين مبلغ الفاتورة وصافي المعاملات: ${total - netDebt}');
    }
    
    // سجل التعديلات (Snapshots)
    print('\n   📝 سجل التعديلات (Snapshots):');
    final snapshots = await db.rawQuery('''
      SELECT * FROM invoice_snapshots 
      WHERE invoice_id = ?
      ORDER BY created_at ASC
    ''', [invId]);
    
    if (snapshots.isEmpty) {
      print('      لا يوجد سجل تعديلات');
    } else {
      for (int i = 0; i < snapshots.length; i++) {
        final snap = snapshots[i];
        final snapType = snap['snapshot_type'];
        final snapDate = snap['created_at'];
        final snapTotal = snap['total_amount'];
        final snapPaid = snap['amount_paid'];
        final snapPaymentType = snap['payment_type'];
        final snapDiscount = snap['discount'];
        final snapLoadingFee = snap['loading_fee'];
        
        print('      ${i + 1}. $snapType | $snapDate');
        print('         المبلغ: $snapTotal | المدفوع: $snapPaid | النوع: $snapPaymentType');
        print('         الخصم: $snapDiscount | أجور التحميل: $snapLoadingFee');
        
        // مقارنة مع السابق
        if (i > 0 && snapType == 'after_edit') {
          final prevSnap = snapshots[i - 1];
          final prevTotal = (prevSnap['total_amount'] as num?)?.toDouble() ?? 0;
          final currTotal = (snapTotal as num?)?.toDouble() ?? 0;
          if (prevTotal != currTotal) {
            print('         📈 تغيير المبلغ: $prevTotal → $currTotal (فرق: ${currTotal - prevTotal})');
          }
        }
      }
    }
    
    // المعاملات
    print('\n   💳 المعاملات المرتبطة:');
    if (txs.isEmpty) {
      print('      لا توجد معاملات');
    } else {
      for (final tx in txs) {
        final txId = tx['id'];
        final txDate = tx['transaction_date'];
        final txType = tx['transaction_type'];
        final amount = tx['amount_changed'];
        final note = tx['transaction_note'] ?? '';
        print('      #$txId | $txDate | $txType | $amount');
        if (note.toString().isNotEmpty) print('         ملاحظة: $note');
      }
    }
  }
  
  // المعاملات اليدوية
  print('\n' + '-' * 80);
  print('💳 المعاملات اليدوية (غير مرتبطة بفاتورة):');
  
  final manualTxs = await db.rawQuery('''
    SELECT * FROM transactions 
    WHERE customer_id = ? AND invoice_id IS NULL
    ORDER BY transaction_date ASC
  ''', [customerId]);
  
  double manualDebt = 0;
  double manualPayments = 0;
  
  for (final tx in manualTxs) {
    final txId = tx['id'];
    final txDate = tx['transaction_date'];
    final txType = tx['transaction_type'];
    final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0;
    final note = tx['transaction_note'] ?? '';
    
    if (amount > 0) {
      manualDebt += amount;
    } else {
      manualPayments += amount.abs();
    }
    
    print('  #$txId | $txDate | $txType | $amount | $note');
  }
  
  print('\n' + '=' * 80);
  print('📊 الملخص:');
  print('=' * 80);
  print('إجمالي مبالغ الفواتير: $totalInvoiceAmounts');
  print('صافي الدين من معاملات الفواتير: $totalNetDebt');
  print('الديون اليدوية: $manualDebt');
  print('المدفوعات اليدوية: $manualPayments');
  print('');
  print('الدين الإجمالي المتوقع: ${totalNetDebt + manualDebt - manualPayments}');
  
  // الدين الفعلي من المعاملات
  final debtResult = await db.rawQuery('''
    SELECT SUM(amount_changed) as total FROM transactions WHERE customer_id = ?
  ''', [customerId]);
  final actualDebt = (debtResult.first['total'] as num?)?.toDouble() ?? 0;
  print('الدين الفعلي من المعاملات: $actualDebt');
  
  await db.close();
}
