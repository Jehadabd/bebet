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

  final db = await openDatabase(dbPath);
  final customerId = 1283;

  await db.transaction((txn) async {
    // 1. Delete all transactions for this customer
    final count = await txn.delete(
      'transactions',
      where: 'customer_id = ?',
      whereArgs: [customerId],
    );
    print('Deleted $count transactions for customer $customerId');

    // 2. Set customer debt to 0
    await txn.update(
      'customers',
      {'current_total_debt': 0.0, 'last_modified_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [customerId],
    );
    print('Reset debt for customer $customerId to 0');
  });

  print('\n✅ Fix applied successfully.');
  await db.close();
}
