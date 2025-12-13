import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final db = await openDatabase(
    '${Platform.environment['APPDATA']}/com.example/debt_book/debt_book.db',
    readOnly: true,
  );

  print('العميل 581:');
  final c581 = await db.rawQuery('SELECT id, name, current_total_debt FROM customers WHERE id = 581');
  print(c581);

  print('\nالعميل 249:');
  final c249 = await db.rawQuery('SELECT id, name, current_total_debt FROM customers WHERE id = 249');
  print(c249);

  await db.close();
}
