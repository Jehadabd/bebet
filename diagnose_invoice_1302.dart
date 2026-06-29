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

  print('📂 Database path: $dbPath');
  
  if (!File(dbPath).existsSync()) {
    print('❌ Database not found!');
    return;
  }

  final db = await openDatabase(dbPath, readOnly: true);

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔍 Inspecting Customer "عبود الخليل"');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final customers = await db.query(
    'customers',
    where: 'name LIKE ?',
    whereArgs: ['%عبود الخليل%'],
  );

  if (customers.isEmpty) {
    print('❌ Customer not found!');
    await db.close();
    return;
  }

  final customer = customers.first;
  final customerId = customer['id'] as int;
  
  print('📋 Customer Info:');
  for (final key in customer.keys) {
    print('  $key: ${customer[key]}');
  }

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔍 Inspecting Invoice #1302');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final invoices = await db.query(
    'invoices',
    where: 'id = ?',
    whereArgs: [1302],
  );

  if (invoices.isEmpty) {
    print('❌ Invoice 1302 not found!');
  } else {
    for (final inv in invoices) {
      print('📄 Invoice Info (ID: ${inv['id']}):');
      for (final key in inv.keys) {
        print('  $key: ${inv[key]}');
      }
    }
  }

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔍 Transactions for Invoice #1302 or Customer');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  final transactions = await db.query(
    'transactions',
    where: 'customer_id = ? OR invoice_id = ? OR description LIKE ?',
    whereArgs: [customerId, 1302, '%1302%'],
    orderBy: 'id ASC',
  );

  print('💰 Transactions (${transactions.length}):');
  for (final tx in transactions) {
    print('  [ID: ${tx['id']}] Date: ${tx['transaction_date']}');
    print('    Amount: ${tx['amount_changed']} | Before: ${tx['balance_before_transaction']} | After: ${tx['new_balance_after_transaction']}');
    print('    Type: ${tx['transaction_type']}');
    print('    Desc: ${tx['description']}');
    print('    Invoice ID: ${tx['invoice_id']}');
    print('    Created At: ${tx['created_at']}');
    print('  ------------------------');
  }

  // Check debt_transactions table just in case
  final debtTransactions = await db.query(
    'debt_transactions',
    where: 'customer_id = ? OR invoice_id = ? OR description LIKE ?',
    whereArgs: [customerId, 1302, '%1302%'],
    orderBy: 'id ASC',
  );

  print('\n💳 Debt Transactions (${debtTransactions.length}):');
  for (final tx in debtTransactions) {
    print('  [ID: ${tx['id']}] Date: ${tx['transaction_date']}');
    print('    Amount: ${tx['amount']}');
    print('    Type: ${tx['transaction_type']}');
    print('    Desc: ${tx['description']}');
    print('    Invoice ID: ${tx['invoice_id']}');
    print('  ------------------------');
  }

  await db.close();
}
