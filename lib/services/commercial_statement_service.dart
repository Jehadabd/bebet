// services/commercial_statement_service.dart
// خدمة كشف الحساب التجاري - تجميع المعاملات المرتبطة بالفواتير
import 'database_service.dart';
import '../models/transaction.dart';

class CommercialStatementService {
  final DatabaseService _db = DatabaseService();

  /// جلب السنوات المتاحة للعميل (من أقدم فاتورة أو معاملة)
  Future<List<int>> getAvailableYears(int customerId) async {
    final db = await _db.database;
    
    // جلب السنوات من المعاملات
    final txYears = await db.rawQuery('''
      SELECT DISTINCT strftime('%Y', transaction_date) as year
      FROM transactions
      WHERE customer_id = ?
    ''', [customerId]);
    
    // جلب السنوات من الفواتير (بما فيها النقدية)
    final invYears = await db.rawQuery('''
      SELECT DISTINCT strftime('%Y', invoice_date) as year
      FROM invoices
      WHERE customer_id = ? AND status = 'محفوظة'
    ''', [customerId]);
    
    final allYears = <int>{};
    for (final r in txYears) {
      final y = int.tryParse(r['year']?.toString() ?? '');
      if (y != null && y > 0) allYears.add(y);
    }
    for (final r in invYears) {
      final y = int.tryParse(r['year']?.toString() ?? '');
      if (y != null && y > 0) allYears.add(y);
    }
    
    final sorted = allYears.toList()..sort();
    return sorted;
  }

  /// جلب كشف الحساب التجاري الكامل
  Future<Map<String, dynamic>> getCommercialStatement({
    required int customerId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await _db.database;
    
    // 1. جلب جميع الفواتير (دين ونقد) للعميل في الفترة
    String invoiceWhere = 'customer_id = ? AND status = ?';
    List<dynamic> invoiceArgs = [customerId, 'محفوظة'];
    
    if (startDate != null) {
      invoiceWhere += ' AND DATE(invoice_date) >= DATE(?)';
      invoiceArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      invoiceWhere += ' AND DATE(invoice_date) <= DATE(?)';
      invoiceArgs.add(endDate.toIso8601String());
    }
    
    final invoices = await db.query(
      'invoices',
      where: invoiceWhere,
      whereArgs: invoiceArgs,
      orderBy: 'invoice_date ASC, id ASC',
    );
    
    // 2. جلب المعاملات اليدوية (غير مرتبطة بفاتورة)
    String txWhere = 'customer_id = ? AND invoice_id IS NULL';
    List<dynamic> txArgs = [customerId];
    
    if (startDate != null) {
      txWhere += ' AND DATE(transaction_date) >= DATE(?)';
      txArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      txWhere += ' AND DATE(transaction_date) <= DATE(?)';
      txArgs.add(endDate.toIso8601String());
    }
    
    final manualTx = await db.query(
      'transactions',
      where: txWhere,
      whereArgs: txArgs,
      orderBy: 'transaction_date ASC, id ASC',
    );
    
    // 2.5 جلب المعاملات المرتبطة بفواتير لكن الفواتير ليس لها customer_id مطابق
    // هذا يحل مشكلة الفواتير القديمة التي لم يتم ربطها بالعميل بشكل صحيح
    String orphanTxWhere = 'customer_id = ? AND invoice_id IS NOT NULL';
    List<dynamic> orphanTxArgs = [customerId];
    
    if (startDate != null) {
      orphanTxWhere += ' AND DATE(transaction_date) >= DATE(?)';
      orphanTxArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      orphanTxWhere += ' AND DATE(transaction_date) <= DATE(?)';
      orphanTxArgs.add(endDate.toIso8601String());
    }
    
    final invoiceRelatedTx = await db.query(
      'transactions',
      where: orphanTxWhere,
      whereArgs: orphanTxArgs,
      orderBy: 'transaction_date ASC, id ASC',
    );
    
    // جمع invoice_ids من الفواتير التي تم جلبها
    final fetchedInvoiceIds = invoices.map((inv) => inv['id'] as int).toSet();

    // 3. بناء قائمة السطور
    final List<Map<String, dynamic>> entries = [];
    
    // إضافة الفواتير
    for (final inv in invoices) {
      final invoiceId = inv['id'] as int;
      final invoiceDate = DateTime.parse(inv['invoice_date'] as String);
      final totalAmount = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
      final paymentType = inv['payment_type'] as String? ?? '';
      final paidAmount = (inv['paid_amount'] as num?)?.toDouble() ?? 0.0;
      
      // جلب المعاملات المرتبطة بهذه الفاتورة لحساب صافي الدين
      final invoiceTx = await db.query(
        'transactions',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'transaction_date ASC, id ASC',
      );
      
      // حساب صافي المبلغ من المعاملات الفعلية
      // هذا يعكس التأثير الحقيقي على الدين بغض النظر عن نوع الفاتورة الحالي
      double netDebtAmount = 0.0;
      for (final tx in invoiceTx) {
        netDebtAmount += (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
      }
      
      // تحديد نوع الفاتورة ووصفها
      String description;
      String entryType;
      bool wasConverted = false;
      String? originalPaymentType;
      
      // فحص سجل التعديلات لمعرفة إذا تحولت الفاتورة
      final snapshots = await db.query(
        'invoice_snapshots',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'created_at ASC',
      );
      
      // البحث عن نوع الدفع الأصلي من أول snapshot
      String? originalPaymentTypeFromSnapshot;
      if (snapshots.isNotEmpty) {
        final firstSnapshot = snapshots.first;
        originalPaymentTypeFromSnapshot = firstSnapshot['payment_type'] as String?;
      }
      
      // إذا كانت الفاتورة نقد ولا توجد معاملات مرتبطة بها، فهي فاتورة نقدية حقيقية
      // أما إذا كانت نقد ولها معاملات، فهي تحولت من دين إلى نقد
      final bool isTrueCashInvoice = paymentType == 'نقد' && invoiceTx.isEmpty;
      
      // فحص إذا تحولت من نقد إلى دين
      final bool convertedFromCashToDebt = paymentType == 'دين' && 
          originalPaymentTypeFromSnapshot == 'نقد';
      
      if (isTrueCashInvoice) {
        description = 'فاتورة رقم #$invoiceId نقد';
        entryType = 'cash_invoice';
        netDebtAmount = 0; // فاتورة نقدية حقيقية لا تؤثر على الدين
      } else if (paymentType == 'نقد' && invoiceTx.isNotEmpty) {
        // فاتورة تحولت من دين إلى نقد - نعرض مبلغ الفاتورة الأصلي
        description = 'فاتورة رقم #$invoiceId (تحولت لنقد)';
        entryType = 'converted_to_cash';
        wasConverted = true;
        originalPaymentType = 'دين';
      } else if (convertedFromCashToDebt) {
        // فاتورة تحولت من نقد إلى دين
        description = 'فاتورة رقم #$invoiceId (تحولت لدين)';
        entryType = 'converted_to_debt';
        wasConverted = true;
        originalPaymentType = 'نقد';
      } else {
        description = 'فاتورة رقم #$invoiceId';
        entryType = 'debt_invoice';
      }
      
      entries.add({
        'date': invoiceDate,
        'description': description,
        'invoiceAmount': totalAmount, // مبلغ الفاتورة الأصلي دائماً
        'netAmount': netDebtAmount, // صافي تأثير الدين
        'debtBefore': 0.0, // سيُحسب لاحقاً
        'debtAfter': 0.0, // سيُحسب لاحقاً
        'type': entryType,
        'invoiceId': invoiceId,
        'paymentType': paymentType,
        'paidAmount': paidAmount,
        'wasConverted': wasConverted,
        'originalPaymentType': originalPaymentType,
      });
    }
    
    // إضافة المعاملات اليدوية
    for (final tx in manualTx) {
      final txDate = DateTime.parse(tx['transaction_date'] as String);
      final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
      final txType = tx['transaction_type'] as String? ?? '';
      final note = tx['transaction_note'] as String?;
      
      String description;
      if (txType == 'manual_payment') {
        description = 'دفعة نقدية (تسديد)';
      } else if (txType == 'manual_debt') {
        description = 'دين يدوي';
      } else if (txType == 'opening_balance') {
        description = 'رصيد سابق';
      } else {
        description = note ?? 'معاملة يدوية';
      }
      
      entries.add({
        'date': txDate,
        'description': description,
        'invoiceAmount': amount.abs(),
        'netAmount': amount,
        'debtBefore': 0.0,
        'debtAfter': 0.0,
        'type': 'manual_transaction',
        'invoiceId': null,
        'paymentType': null,
        'paidAmount': null,
      });
    }
    
    // إضافة المعاملات المرتبطة بفواتير لم تظهر في قائمة الفواتير
    // (فواتير ليس لها customer_id مطابق أو حالتها ليست محفوظة)
    for (final tx in invoiceRelatedTx) {
      final invoiceId = tx['invoice_id'] as int?;
      // تخطي إذا كانت الفاتورة موجودة في القائمة
      if (invoiceId != null && fetchedInvoiceIds.contains(invoiceId)) {
        continue;
      }
      
      final txDate = DateTime.parse(tx['transaction_date'] as String);
      final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
      final txType = tx['transaction_type'] as String? ?? '';
      final note = tx['transaction_note'] as String?;
      
      String description = 'فاتورة #$invoiceId';
      if (note != null && note.isNotEmpty) {
        description += ' - $note';
      }
      
      entries.add({
        'date': txDate,
        'description': description,
        'invoiceAmount': amount.abs(),
        'netAmount': amount,
        'debtBefore': 0.0,
        'debtAfter': 0.0,
        'type': 'orphan_invoice_transaction',
        'invoiceId': invoiceId,
        'paymentType': null,
        'paidAmount': null,
      });
    }
    
    // ترتيب حسب التاريخ
    entries.sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    
    // 4. حساب الدين قبل والدين بعد لكل سطر
    // أولاً: حساب الرصيد قبل الفترة
    double debtBeforePeriod = 0.0;
    if (startDate != null) {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(amount_changed), 0) as total
        FROM transactions
        WHERE customer_id = ? AND DATE(transaction_date) < DATE(?)
      ''', [customerId, startDate.toIso8601String()]);
      debtBeforePeriod = (result.first['total'] as num?)?.toDouble() ?? 0.0;
    }
    
    double runningDebt = debtBeforePeriod;
    for (final entry in entries) {
      entry['debtBefore'] = runningDebt;
      runningDebt += (entry['netAmount'] as num?)?.toDouble() ?? 0.0;
      entry['debtAfter'] = runningDebt;
    }
    
    // 5. حساب الملخص المفصل
    int totalDebtInvoices = 0;      // فواتير دين حالية
    int totalCashInvoices = 0;      // فواتير نقد حالية
    int convertedToCash = 0;        // فواتير تحولت من دين إلى نقد
    int convertedToDebt = 0;        // فواتير تحولت من نقد إلى دين
    
    // حساب عدد الفواتير وتتبع التحويلات
    for (final entry in entries) {
      final type = entry['type'] as String;
      
      if (type == 'debt_invoice') {
        totalDebtInvoices++;
      } else if (type == 'cash_invoice') {
        totalCashInvoices++;
      } else if (type == 'converted_to_cash') {
        convertedToCash++;
      } else if (type == 'converted_to_debt') {
        convertedToDebt++;
      }
    }
    
    // جلب كل المعاملات لحساب الإجماليات المفصلة
    String allTxWhere = 'customer_id = ?';
    List<dynamic> allTxArgs = [customerId];
    
    if (startDate != null) {
      allTxWhere += ' AND DATE(transaction_date) >= DATE(?)';
      allTxArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      allTxWhere += ' AND DATE(transaction_date) <= DATE(?)';
      allTxArgs.add(endDate.toIso8601String());
    }
    
    final allTransactions = await db.query(
      'transactions',
      where: allTxWhere,
      whereArgs: allTxArgs,
    );
    
    // تفصيل الديون والمدفوعات
    double invoiceDebts = 0.0;      // ديون الفواتير
    double manualDebts = 0.0;       // ديون يدوية
    double invoicePayments = 0.0;   // مدفوعات الفواتير (تسديدات)
    double manualPayments = 0.0;    // مدفوعات يدوية
    
    for (final tx in allTransactions) {
      final amount = (tx['amount_changed'] as num?)?.toDouble() ?? 0.0;
      final invoiceId = tx['invoice_id'];
      final isInvoiceRelated = invoiceId != null;
      
      if (amount > 0) {
        // زيادة في الدين
        if (isInvoiceRelated) {
          invoiceDebts += amount;
        } else {
          manualDebts += amount;
        }
      } else {
        // تسديد (نقص في الدين)
        if (isInvoiceRelated) {
          invoicePayments += amount.abs();
        } else {
          manualPayments += amount.abs();
        }
      }
    }
    
    final summary = {
      'totalDebtInvoices': totalDebtInvoices,   // عدد فواتير الدين الحالية
      'totalCashInvoices': totalCashInvoices,   // عدد الفواتير النقدية
      'convertedToCash': convertedToCash,       // فواتير تحولت من دين إلى نقد
      'convertedToDebt': convertedToDebt,       // فواتير تحولت من نقد إلى دين
      'totalInvoices': totalDebtInvoices + totalCashInvoices + convertedToCash, // إجمالي الفواتير
      'invoiceDebts': invoiceDebts,             // إجمالي ديون الفواتير
      'manualDebts': manualDebts,               // إجمالي الديون اليدوية
      'totalDebts': invoiceDebts + manualDebts, // إجمالي الديون
      'invoicePayments': invoicePayments,       // إجمالي مدفوعات الفواتير
      'manualPayments': manualPayments,         // إجمالي المدفوعات اليدوية
      'totalPayments': invoicePayments + manualPayments, // إجمالي المدفوعات
      'remainingBalance': runningDebt,          // الرصيد المتبقي
    };
    
    return {
      'entries': entries,
      'summary': summary,
      'finalBalance': runningDebt,
      'openingBalance': debtBeforePeriod,
    };
  }
}
