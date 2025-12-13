import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(
    '${Platform.environment['APPDATA']}/com.example/debt_book/debt_book.db',
    readOnly: true,
  );

  print('فحص المعاملة 911:');
  final tx911 = await db.rawQuery('SELECT * FROM transactions WHERE id = 911');
  print(tx911);

  print('\nفحص جميع المعاملات للعميل 249:');
  final allTx = await db.rawQuery(
    'SELECT id, customer_id, amount_changed, transaction_type, invoice_id FROM transactions WHERE customer_id = 249 ORDER BY id'
  );
  for (final tx in allTx) {
    print(tx);
  }

  print('\nعدد المعاملات: ${allTx.length}');

  await db.close();
}
