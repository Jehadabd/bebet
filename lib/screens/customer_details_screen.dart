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

      // جلب جميع الفواتير للعميل
      final invoices = await db.getAllInvoices();
      final customerInvoices = invoices
          .where((invoice) => invoice.customerId == widget.customer.id)
          .toList();

      // دمج المعاملات والفواتير وترتيبها حسب التاريخ
      final allTransactions = <AccountStatementItem>[];

      // إضافة المعاملات اليدوية
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

      // إضافة الفواتير
      for (var invoice in customerInvoices) {
        if (invoice.invoiceDate != null) {
          // البحث عن المعاملة المرتبطة بالفاتورة
          final relatedTransaction = transactions.firstWhere(
            (t) => t.invoiceId == invoice.id && t.amountChanged > 0,
            orElse: () => DebtTransaction(
              id: null,
              customerId: widget.customer.id!,
              amountChanged:
                  invoice.paymentType == 'دين' ? invoice.totalAmount : 0,
              transactionDate: invoice.invoiceDate!,
              newBalanceAfterTransaction: 0,
              transactionNote: 'فاتورة رقم ${invoice.id}',
              transactionType: 'invoice_debt',
              createdAt: invoice.createdAt,
            ),
          );

          allTransactions.add(AccountStatementItem(
            date: invoice.invoiceDate!,
            description: 'فاتورة رقم: ${invoice.id}',
            amount: invoice.paymentType == 'دين' ? invoice.totalAmount : 0,
            type: 'invoice',
            invoice: invoice,
            transaction: relatedTransaction,
          ));
        }
      }

      // ترتيب المعاملات حسب التاريخ
      allTransactions.sort((a, b) => a.date.compareTo(b.date));

      // حساب الأرصدة
      double currentBalance = 0.0;
      for (var item in allTransactions) {
        item.balanceBefore = currentBalance;
        currentBalance += item.amount;
        item.balanceAfter = currentBalance;
      }

      // إنشاء PDF
      final pdfService = PdfService();
      final pdf = await pdfService.generateAccountStatement(
        customer: widget.customer,
        transactions: allTransactions,
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
    if (transaction.transactionType == 'invoice_debt') {
      return 'فاتورة رقم: ${transaction.invoiceId}';
    } else if (transaction.transactionType == 'manual_payment') {
      return 'دفعة نقدية (تسديد)';
    } else if (transaction.transactionType == 'manual_debt') {
      return 'معاملة يدوية (إضافة دين)';
    } else if (transaction.transactionType == 'Invoice_Debt_Adjustment') {
      return 'تعديل فاتورة رقم: ${transaction.invoiceId}';
    } else if (transaction.transactionType == 'Invoice_Debt_Reversal') {
      return 'حذف فاتورة رقم: ${transaction.invoiceId}';
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
