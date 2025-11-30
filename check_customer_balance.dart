import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() async {
  // تهيئة sqflite_ffi
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // البحث عن قاعدة البيانات
  final dbPath = p.join(
    Platform.environment['APPDATA'] ?? '',
    'com.example',
    'debt_book',
    'debt_book.db',
  );

  print('📂 مسار قاعدة البيانات: $dbPath');
  
  if (!File(dbPath).existsSync()) {
    print('❌ قاعدة البيانات غير موجودة!');
    return;
  }

  final db = await openDatabase(dbPath, readOnly: true);

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔍 قائمة جميع العملاء:');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // عرض جميع العملاء الذين لديهم رصيد
  final allCustomers = await db.query('customers', orderBy: 'name');
  print('العملاء الذين لديهم رصيد:');
  for (var c in allCustomers) {
    final balance = (c['current_total_debt'] as num?)?.toDouble() ?? 0.0;
    if (balance > 0) {
      print('  [${c['id']}] ${c['name']} - رصيد: ${balance.toStringAsFixed(0)} - هاتف: ${c['phone']}');
    }
  }

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔍 فحص حساب: محمد العسكر');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // البحث عن العميل برقم الهاتف
  final customers = await db.query(
    'customers',
    where: 'phone LIKE ?',
    whereArgs: ['%687222%'],
  );

  if (customers.isEmpty) {
    print('❌ لم يتم العثور على العميل!');
    print('جرب البحث بكلمة أخرى من الاسم');
    await db.close();
    return;
  }

  final customer = customers.first;
  final customerId = customer['id'] as int;
  final customerName = customer['name'] as String;
  final phoneNumber = customer['phone'] as String?;
  final currentBalance = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;
  
  // لا يوجد opening_balance في جدول العملاء
  final openingBalance = 0.0;

  print('📋 معلومات العميل:');
  print('  الاسم: $customerName');
  print('  ID: $customerId');
  print('  الهاتف: $phoneNumber');
  print('  الرصيد الحالي (current_total_debt): ${currentBalance.toStringAsFixed(2)}');

  // جلب جميع الفواتير
  final invoices = await db.query(
    'invoices',
    where: 'customer_id = ?',
    whereArgs: [customerId],
    orderBy: 'invoice_date ASC, created_at ASC',
  );

  print('\n📊 الفواتير (${invoices.length}):');
  double totalDebtFromInvoices = 0.0;
  for (var inv in invoices) {
    final id = inv['id'];
    final invoiceNumber = inv['invoice_number'];
    final invoiceDate = inv['invoice_date'];
    final totalAmount = (inv['total_amount'] as num).toDouble();
    final amountPaid = (inv['amount_paid'] as num?)?.toDouble() ?? 0.0;
    final paymentType = inv['payment_type'] as String? ?? 'دين';
    
    final remaining = totalAmount - amountPaid;
    final debtImpact = paymentType == 'نقد' ? 0.0 : (remaining > 0 ? remaining : 0.0);
    
    totalDebtFromInvoices += debtImpact;
    
    print('  [$id] $invoiceNumber - $invoiceDate');
    print('      نوع: $paymentType, مبلغ: $totalAmount, مدفوع: $amountPaid');
    print('      تأثير على الدين: $debtImpact');
  }

  // جلب جميع سندات القبض (المعاملات من نوع تسديد)
  final receipts = await db.query(
    'debt_transactions',
    where: 'customer_id = ? AND transaction_type = ?',
    whereArgs: [customerId, 'تسديد دين'],
    orderBy: 'transaction_date ASC, created_at ASC',
  );

  print('\n💰 سندات القبض (${receipts.length}):');
  double totalPayments = 0.0;
  for (var rec in receipts) {
    final id = rec['id'];
    final transactionDate = rec['transaction_date'];
    final amount = (rec['amount'] as num).toDouble();
    
    totalPayments += amount;
    
    print('  [$id] $transactionDate');
    print('      مبلغ: $amount');
  }

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 التحليل:');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('1️⃣ إجمالي الدين من الفواتير: ${totalDebtFromInvoices.toStringAsFixed(2)}');
  print('2️⃣ إجمالي المدفوعات: ${totalPayments.toStringAsFixed(2)}');
  print('');
  print('🧮 الرصيد المحسوب = دين الفواتير - المدفوعات');
  final calculatedBalance = totalDebtFromInvoices - totalPayments;
  print('   = $totalDebtFromInvoices - $totalPayments');
  print('   = ${calculatedBalance.toStringAsFixed(2)}');
  print('');
  print('💾 الرصيد في قاعدة البيانات: ${currentBalance.toStringAsFixed(2)}');
  print('📄 الرصيد في كشف الحساب (من الصورة): 7,864,600');
  print('');
  
  final difference = (currentBalance - calculatedBalance).abs();
  if (difference > 0.01) {
    print('❌ هناك فرق بين الرصيد المحسوب والمخزن: ${difference.toStringAsFixed(2)}');
    print('');
    print('🔍 التشخيص المحتمل:');
    print('  ⚠️ قد تكون هناك فواتير نقد محسوبة كدين بالخطأ');
    print('  ⚠️ أو هناك معاملات قديمة لم يتم احتسابها');
  } else {
    print('✅ الرصيد المحسوب يطابق المخزن في قاعدة البيانات');
  }
  
  // مقارنة مع كشف الحساب
  final statementBalance = 7864600.0;
  final diffFromStatement = (currentBalance - statementBalance).abs();
  if (diffFromStatement > 0.01) {
    print('');
    print('⚠️ الفرق بين البرنامج وكشف الحساب: ${diffFromStatement.toStringAsFixed(2)}');
    print('  🔍 يجب فحص جميع المعاملات للعثور على السبب');
  } else {
    print('');
    print('✅ الرصيد في البرنامج يطابق كشف الحساب!');
  }

  await db.close();
}
