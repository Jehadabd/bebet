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
  print('🔍 قائمة جميع الموردين:');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // عرض جميع الموردين
  final allSuppliers = await db.query('suppliers');
  for (var s in allSuppliers) {
    print('  [${s['id']}] ${s['company_name']} - رصيد: ${s['current_balance']}');
  }

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('🔍 فحص حساب: محمد العسكر');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // البحث عن المورد - استخدم ID=1 (تجريبي) كمثال
  // يمكنك تغيير الرقم حسب المورد المطلوب
  final suppliers = await db.query(
    'suppliers',
    where: 'id = ?',
    whereArgs: [1], // المورد "تجريبي"
  );

  if (suppliers.isEmpty) {
    print('❌ لم يتم العثور على المورد!');
    await db.close();
    return;
  }

  final supplier = suppliers.first;
  final supplierId = supplier['id'] as int;
  final companyName = supplier['company_name'] as String;
  final openingBalance = (supplier['opening_balance'] as num?)?.toDouble() ?? 0.0;
  final currentBalance = (supplier['current_balance'] as num?)?.toDouble() ?? 0.0;
  final totalPurchases = (supplier['total_purchases'] as num?)?.toDouble() ?? 0.0;

  print('📋 معلومات المورد:');
  print('  الاسم: $companyName');
  print('  ID: $supplierId');
  print('  الدين الأولي (opening_balance): ${openingBalance.toStringAsFixed(2)}');
  print('  الرصيد الحالي (current_balance): ${currentBalance.toStringAsFixed(2)}');
  print('  إجمالي المشتريات: ${totalPurchases.toStringAsFixed(2)}');

  // جلب جميع الفواتير
  final invoices = await db.query(
    'supplier_invoices',
    where: 'supplier_id = ?',
    whereArgs: [supplierId],
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

  // جلب جميع سندات القبض
  final receipts = await db.query(
    'supplier_receipts',
    where: 'supplier_id = ?',
    whereArgs: [supplierId],
    orderBy: 'receipt_date ASC, created_at ASC',
  );

  print('\n💰 سندات القبض (${receipts.length}):');
  double totalPayments = 0.0;
  for (var rec in receipts) {
    final id = rec['id'];
    final receiptNumber = rec['receipt_number'];
    final receiptDate = rec['receipt_date'];
    final amount = (rec['amount'] as num).toDouble();
    
    totalPayments += amount;
    
    print('  [$id] $receiptNumber - $receiptDate');
    print('      مبلغ: $amount');
  }

  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 التحليل:');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('1️⃣ الدين الأولي: ${openingBalance.toStringAsFixed(2)}');
  print('2️⃣ إجمالي الدين من الفواتير: ${totalDebtFromInvoices.toStringAsFixed(2)}');
  print('3️⃣ إجمالي المدفوعات: ${totalPayments.toStringAsFixed(2)}');
  print('');
  print('🧮 الرصيد المحسوب = الدين الأولي + دين الفواتير - المدفوعات');
  final calculatedBalance = openingBalance + totalDebtFromInvoices - totalPayments;
  print('   = $openingBalance + $totalDebtFromInvoices - $totalPayments');
  print('   = ${calculatedBalance.toStringAsFixed(2)}');
  print('');
  print('💾 الرصيد في قاعدة البيانات: ${currentBalance.toStringAsFixed(2)}');
  print('');
  
  final difference = (currentBalance - calculatedBalance).abs();
  if (difference > 0.01) {
    print('❌ هناك فرق: ${difference.toStringAsFixed(2)}');
    print('');
    print('🔍 التشخيص المحتمل:');
    
    // هل الدين الأولي مضاف مرتين؟
    if ((difference - openingBalance).abs() < 0.01) {
      print('  ⚠️ يبدو أن الدين الأولي مضاف مرتين!');
      print('  الحل: الرصيد الصحيح = ${(currentBalance - openingBalance).toStringAsFixed(2)}');
    }
    // هل هناك فواتير نقد محسوبة كدين؟
    else {
      print('  ⚠️ قد تكون هناك فواتير نقد محسوبة كدين بالخطأ');
    }
  } else {
    print('✅ الرصيد صحيح!');
  }

  await db.close();
}
