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

  // Get all invoices for this customer
  final invoices = await db.query(
    'invoices',
    where: 'customer_id = ? AND status != ?',
    whereArgs: [customerId, 'محذوفة'],
  );

  double totalDebtFromInvoices = 0;
  print('=== Invoices ===');
  for (final inv in invoices) {
    final type = inv['payment_type'] as String;
    final total = (inv['total_amount'] as num).toDouble();
    final paid = (inv['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
    final remaining = total - paid;
    if (type == 'دين' && remaining > 0) {
      totalDebtFromInvoices += remaining;
      print('Invoice ${inv['id']} (دين): Total=$total, Paid=$paid, Remaining=$remaining');
    } else {
      print('Invoice ${inv['id']} ($type): Total=$total, Paid=$paid');
    }
  }

  // Get all payments (receipts)
  final receipts = await db.query(
    'transactions',
    where: 'customer_id = ? AND transaction_type = ?',
    whereArgs: [customerId, 'تسديد دين'],
  );

  double totalPayments = 0;
  print('\n=== Payments ===');
  for (final rec in receipts) {
    final amount = (rec['amount'] as num).toDouble();
    totalPayments += amount;
    print('Payment ${rec['id']}: Amount=$amount');
  }

  // Check initial debt
  final customerData = await db.query('customers', where: 'id = ?', whereArgs: [customerId]);
  double currentDbDebt = (customerData.first['current_total_debt'] as num).toDouble();

  // Try to find if there was an initial debt transaction
  final initialDebtTx = await db.query(
    'transactions',
    where: 'customer_id = ? AND transaction_type = ?',
    whereArgs: [customerId, 'initial_debt'],
  );
  
  double initialDebt = 0;
  if (initialDebtTx.isNotEmpty) {
    initialDebt = (initialDebtTx.first['amount_changed'] as num).toDouble();
    print('\nInitial debt found: $initialDebt');
  }

  double expectedDebt = initialDebt + totalDebtFromInvoices - totalPayments;
  
  print('\n=== Summary ===');
  print('Initial Debt: $initialDebt');
  print('Debt from Invoices: $totalDebtFromInvoices');
  print('Total Payments: $totalPayments');
  print('Expected Balance: $expectedDebt');
  print('Current DB Balance: $currentDbDebt');

  await db.close();
}
