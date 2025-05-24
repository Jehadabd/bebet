import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import 'add_transaction_screen.dart';

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
    Future.microtask(() => context.read<AppProvider>().selectCustomer(widget.customer));
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
                await context.read<AppProvider>().deleteCustomer(widget.customer.id!);
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
                      _buildInfoRow('رقم الهاتف', customer.phone ?? 'غير متوفر'),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        'إجمالي الدين',
                        '${customer.currentTotalDebt.toStringAsFixed(2)} ريال',
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(
          '${transaction.amountChanged.abs().toStringAsFixed(2)} ريال',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الرصيد بعد المعاملة: ${transaction.newBalanceAfterTransaction.toStringAsFixed(2)} ريال',
            ),
            if (transaction.transactionNote != null)
              Text(transaction.transactionNote!),
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
} 