import 'package:flutter/material.dart';
import '../models/installer.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';

class InstallerDetailsScreen extends StatefulWidget {
  final Installer installer;

  const InstallerDetailsScreen({
    super.key,
    required this.installer,
  });

  @override
  State<InstallerDetailsScreen> createState() => _InstallerDetailsScreenState();
}

class _InstallerDetailsScreenState extends State<InstallerDetailsScreen> {
  final DatabaseService _db = DatabaseService();
  List<Invoice> _invoices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() => _isLoading = true);
    try {
      final invoices = await _db.getInvoicesByInstaller(widget.installer.name);
      setState(() {
        _invoices = invoices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل الفواتير: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.installer.name),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'إجمالي المبلغ المفوتر',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.installer.totalBilledAmount.toStringAsFixed(2)} دينار عراقي',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Theme.of(context).primaryColor,
                        ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'الفواتير المرتبطة',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _invoices.isEmpty
                    ? const Center(child: Text('لا توجد فواتير مرتبطة'))
                    : ListView.builder(
                        itemCount: _invoices.length,
                        itemBuilder: (context, index) {
                          final invoice = _invoices[index];
                          return ListTile(
                            title: Text(invoice.customerName),
                            subtitle: Text(
                              'التاريخ: ${invoice.invoiceDate.toString().split(' ')[0]}\n'
                              'المبلغ: ${invoice.totalAmount.toStringAsFixed(2)} دينار عراقي',
                            ),
                            trailing: const Icon(Icons.receipt_long),
                            onTap: () {
                              // TODO: Navigate to invoice details - Keep this TODO for now
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
} 