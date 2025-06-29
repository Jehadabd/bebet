// screens/customer_details_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import 'add_transaction_screen.dart';
import 'create_invoice_screen.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../models/account_statement_item.dart';
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:process/process.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailsScreen({
    super.key,
    required this.customer,
  });

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => context.read<AppProvider>().selectCustomer(widget.customer));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customer.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Implement edit customer functionality
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'كشف الحساب',
            onPressed: () => _generateAccountStatement(),
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تأكيد الحذف'),
                  content: const Text('هل أنت متأكد من حذف هذا العميل؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('حذف'),
                    ),
                  ],
                ),
              );

              if (confirmed == true && mounted) {
                await context
                    .read<AppProvider>()
                    .deleteCustomer(widget.customer.id!);
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final customer = provider.selectedCustomer ?? widget.customer;
          final transactions = provider.customerTransactions;

          return Column(
            children: [
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'معلومات العميل',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                          'رقم الهاتف', customer.phone ?? 'غير متوفر'),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'إجمالي الدين',
                        '${customer.currentTotalDebt?.toStringAsFixed(2) ?? '0.00'} دينار',
                        valueColor: customer.currentTotalDebt > 0
                            ? Colors.red
                            : Colors.green,
                      ),
                      if (customer.generalNote != null) ...[
                        const SizedBox(height: 8),
                        _buildInfoRow('ملاحظات', customer.generalNote!),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'سجل المعاملات',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AddTransactionScreen(
                              customer: customer,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة معاملة'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: transactions.isEmpty
                    ? const Center(
                        child: Text('لا توجد معاملات'),
                      )
                    : ListView.builder(
                        itemCount: transactions.length,
                        itemBuilder: (context, index) {
                          final transaction = transactions[index];
                          return TransactionListTile(transaction: transaction);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Future<void> _generateAccountStatement() async {
    try {
      // إظهار مؤشر التحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // جلب جميع المعاملات للعميل
      final db = DatabaseService();
      final transactions =
          await db.getCustomerTransactions(widget.customer.id!);

      // دمج المعاملات وترتيبها حسب التاريخ
      final allTransactions = <AccountStatementItem>[];

      // إضافة المعاملات من قاعدة البيانات فقط
      for (var transaction in transactions) {
        if (transaction.transactionDate != null) {
          allTransactions.add(AccountStatementItem(
            date: transaction.transactionDate!,
            description: _getTransactionDescription(transaction),
            amount: transaction.amountChanged,
            type: 'transaction',
            transaction: transaction,
          ));
        }
      }

      // ترتيب المعاملات حسب التاريخ
      allTransactions.sort((a, b) => a.date.compareTo(b.date));

      // إبقاء فقط آخر 15 معاملة مالية
      final last15Transactions = allTransactions.length > 15
          ? allTransactions.sublist(allTransactions.length - 15)
          : allTransactions;

      // حساب الأرصدة بشكل صحيح
      double currentBalance = 0.0;

      // إذا كان لدينا معاملات، نحسب الرصيد قبل أول معاملة في القائمة المعروضة
      if (last15Transactions.isNotEmpty) {
        // حساب الرصيد قبل أول معاملة في القائمة المعروضة
        final firstTransactionDate = last15Transactions.first.date;

        for (var transaction in transactions) {
          if (transaction.transactionDate!.isBefore(firstTransactionDate)) {
            currentBalance += transaction.amountChanged;
          }
        }
      }

      // حساب الأرصدة للقائمة المعروضة
      for (var item in last15Transactions) {
        item.balanceBefore = currentBalance;
        currentBalance += item.amount;
        item.balanceAfter = currentBalance;
      }

      // التأكد من أن الرصيد النهائي يتطابق مع الرصيد الفعلي للعميل
      final actualCustomerBalance = widget.customer.currentTotalDebt;
      if ((currentBalance - actualCustomerBalance).abs() > 0.01) {
        // إذا كان هناك اختلاف كبير، نستخدم الرصيد الفعلي للعميل
        print(
            'Warning: Calculated balance ($currentBalance) differs from actual customer balance ($actualCustomerBalance)');
        currentBalance = actualCustomerBalance;
      }

      // إنشاء PDF مع الرصيد النهائي المحسوب
      final pdfService = PdfService();
      final pdf = await pdfService.generateAccountStatement(
        customer: widget.customer,
        transactions: last15Transactions,
        finalBalance: currentBalance, // تمرير الرصيد النهائي المحسوب
      );

      // إغلاق مؤشر التحميل
      if (mounted) {
        Navigator.pop(context);
      }

      // حفظ PDF وفتحه في المتصفح (مثل طباعة الفاتورة)
      if (Platform.isWindows) {
        final safeCustomerName = widget.customer.name
            .replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
        final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final fileName = 'كشف_حساب_${safeCustomerName}_$formattedDate.pdf';
        final directory = Directory(
            '${Platform.environment['USERPROFILE']}/Documents/account_statements');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pdf);

        // فتح PDF في المتصفح الافتراضي
        await Process.start('cmd', ['/c', 'start', '/min', '', filePath]);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إنشاء كشف الحساب وفتحه في المتصفح!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // للأنظمة الأخرى، عرض PDF مباشرة
        if (mounted) {
          await Printing.layoutPdf(
            onLayout: (format) async => pdf,
          );
        }
      }
    } catch (e) {
      // إغلاق مؤشر التحميل
      if (mounted) {
        Navigator.pop(context);
      }

      // إظهار رسالة الخطأ
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء إنشاء كشف الحساب: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getTransactionDescription(DebtTransaction transaction) {
    final hasInvoice = transaction.invoiceId != null;
    final invoicePart = hasInvoice ? ' (فاتورة #${transaction.invoiceId})' : '';
    if (transaction.transactionType == 'invoice_debt') {
      return 'معاملة مالية - إضافة دين$invoicePart';
    } else if (transaction.transactionType == 'manual_payment') {
      return 'دفعة نقدية (تسديد)';
    } else if (transaction.transactionType == 'manual_debt') {
      return 'معاملة يدوية (إضافة دين)';
    } else if (transaction.transactionType == 'Invoice_Debt_Adjustment') {
      return 'تعديل فاتورة رقم: ${transaction.invoiceId}';
    } else if (transaction.transactionType == 'Invoice_Debt_Reversal') {
      return 'حذف فاتورة رقم: ${transaction.invoiceId}';
    } else if (hasInvoice) {
      // أي معاملة أخرى مرتبطة بفاتورة
      return 'معاملة مالية$invoicePart';
    } else {
      return transaction.transactionNote ?? 'معاملة مالية';
    }
  }
}

class TransactionListTile extends StatelessWidget {
  final DebtTransaction transaction;

  const TransactionListTile({
    super.key,
    required this.transaction,
  });

  @override
  Widget build(BuildContext context) {
    final isDebt = transaction.amountChanged > 0;
    final color = isDebt ? Colors.red : Colors.green;
    final icon = isDebt ? Icons.add : Icons.remove;
    final isInvoiceRelated = transaction.invoiceId != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        onTap: isInvoiceRelated
            ? () => _navigateToInvoiceDetails(
                context, transaction.customerId, transaction.invoiceId!)
            : null,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(
          '${transaction.amountChanged.abs().toStringAsFixed(2)} دينار',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الرصيد بعد المعاملة: ${transaction.newBalanceAfterTransaction?.toStringAsFixed(2) ?? '0.00'} دينار',
            ),
            if (transaction.transactionNote != null)
              Text(transaction.transactionNote!),
            if (isInvoiceRelated)
              Text(
                'مرتبطة بالفاتورة #${transaction.invoiceId}',
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
          ],
        ),
        trailing: Text(
          _formatDate(transaction.transactionDate),
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day}';
  }

  void _navigateToInvoiceDetails(
      BuildContext context, int customerId, int invoiceId) async {
    try {
      final db =
          DatabaseService(); // Assuming DatabaseService can be accessed here
      final invoice = await db.getInvoiceById(invoiceId);
      // Find the related debt transaction for this invoice
      DebtTransaction? relatedDebtTransaction;
      final transactions = await db.getCustomerTransactions(
          customerId); // Get transactions for the current customer
      for (var transaction in transactions) {
        if (transaction.invoiceId == invoiceId &&
            transaction.amountChanged > 0) {
          relatedDebtTransaction = transaction;
          break; // Found the relevant transaction
        }
      }

      if (invoice != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateInvoiceScreen(
              existingInvoice: invoice,
              isViewOnly: invoice.status == 'محفوظة',
              relatedDebtTransaction: relatedDebtTransaction,
            ),
          ),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لم يتم العثور على الفاتورة المطلوبة.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('حدث خطأ عند تحميل الفاتورة: ${e.toString()}')),
        );
      }
    }
  }
}
