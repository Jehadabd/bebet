import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(
    '${Platform.environment['APPDATA']}/com.example/debt_book/debt_book.db',
    readOnly: true,
  );

  print('فحص المعاملة 911 بالتفصيل:');
  final tx911 = await db.rawQuery('SELECT * FROM transactions WHERE id = 911');
  if (tx911.isNotEmpty) {
    final tx = tx911.first;
    print('customer_id: ${tx['customer_id']}');
    print('invoice_id: ${tx['invoice_id']}');
    print('amount_changed: ${tx['amount_changed']}');
    print('balance_before: ${tx['balance_before_transaction']}');
    print('balance_after: ${tx['new_balance_after_transaction']}');
    print('transaction_type: ${tx['transaction_type']}');
    print('description: ${tx['description']}');
  }

  print('\nفحص الفاتورة 191:');
  final inv191 = await db.rawQuery('SELECT customer_id, customer_name FROM invoices WHERE id = 191');
  print(inv191);

  await db.close();
}
