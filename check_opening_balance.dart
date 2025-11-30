import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = p.join(
    Platform.environment['APPDATA'] ?? '',
    'com.example',
    'debt_book',
    'debt_book.db',
  );

  final db = await openDatabase(dbPath, readOnly: true);

  print('🔍 فحص معاملات العميل: محمد العسكر /محلات (ID: 394)\n');

  // جلب جميع المعاملات
  final transactions = await db.query(
    'transactions',
    where: 'customer_id = ?',
    whereArgs: [394],
    orderBy: 'transaction_date ASC, created_at ASC',
  );

  print('📊 عدد المعاملات: ${transactions.length}\n');

  double runningBalance = 0.0;
  for (var i = 0; i < transactions.length; i++) {
    final tx = transactions[i];
    final id = tx['id'];
    final date = tx['transaction_date'];
    final amountChanged = (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
    final balanceBefore = (tx['balance_before_transaction'] as num?)?.toDouble() ?? 0.0;
    final balanceAfter = (tx['new_balance_after_transaction'] as num?)?.toDouble() ?? 0.0;
    final type = tx['transaction_type'];
    final note = tx['transaction_note'] ?? '';
    final invoiceId = tx['invoice_id'];

    print('${i + 1}. [$id] $date');
    print('   نوع: $type');
    print('   المبلغ: ${amountChanged.toStringAsFixed(2)}');
    print('   قبل: ${balanceBefore.toStringAsFixed(2)} → بعد: ${balanceAfter.toStringAsFixed(2)}');
    print('   ملاحظة: $note');
    if (invoiceId != null) {
      print('   فاتورة: $invoiceId');
    }
    print('');

    runningBalance = balanceAfter;
  }

  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('💰 الرصيد النهائي من المعاملات: ${runningBalance.toStringAsFixed(2)}');

  // جلب الرصيد من جدول العملاء
  final customer = await db.query(
    'customers',
    where: 'id = ?',
    whereArgs: [394],
    limit: 1,
  );

  if (customer.isNotEmpty) {
    final currentDebt = (customer.first['current_total_debt'] as num?)?.toDouble() ?? 0.0;
    print('💾 الرصيد في جدول العملاء: ${currentDebt.toStringAsFixed(2)}');

    final diff = (currentDebt - runningBalance).abs();
    if (diff > 0.01) {
      print('');
      print('⚠️ هناك فرق: ${diff.toStringAsFixed(2)}');
      print('🔍 السبب المحتمل: معاملات غير مسجلة أو دين أولي');
    } else {
      print('✅ الرصيد متطابق!');
    }
  }

  await db.close();
}
