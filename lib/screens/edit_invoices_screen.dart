// screens/edit_invoices_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/invoice.dart';
import 'create_invoice_screen.dart';

class EditInvoicesScreen extends StatefulWidget {
  const EditInvoicesScreen({super.key});

  @override
  State<EditInvoicesScreen> createState() => _EditInvoicesScreenState();
}

class _EditInvoicesScreenState extends State<EditInvoicesScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  String _searchName = '';
  String _searchId = '';
  List<Invoice> _filteredInvoices = [];
  List<Invoice> _allInvoices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchInvoices();
    _nameController.addListener(_onNameChanged);
    _idController.addListener(_onIdChanged);
  }

  void _fetchInvoices() async {
    setState(() => _loading = true);
    final provider = Provider.of<AppProvider>(context, listen: false);
    final invoices = await provider.getAllInvoices();
    setState(() {
      _allInvoices = invoices;
      _applyFilters();
      _loading = false;
    });
  }

  void _onNameChanged() {
    setState(() {
      _searchName = _nameController.text.trim();
      _applyFilters();
    });
  }

  void _onIdChanged() {
    setState(() {
      _searchId = _idController.text.trim();
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Invoice> filtered = _allInvoices;
    if (_searchName.isNotEmpty) {
      filtered = filtered
          .where((inv) => inv.customerName.contains(_searchName))
          .toList();
    }
    if (_searchId.isNotEmpty) {
      final id = int.tryParse(_searchId);
      if (id != null) {
        filtered = filtered.where((inv) => inv.id == id).toList();
      }
    }
    _filteredInvoices = filtered;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل القوائم (الفواتير)'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'بحث باسم العميل',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _idController,
                          decoration: const InputDecoration(
                            labelText: 'بحث برقم الفاتورة',
                            prefixIcon: Icon(Icons.numbers),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _filteredInvoices.isEmpty
                        ? const Center(child: Text('لا توجد قوائم مطابقة'))
                        : ListView.builder(
                            itemCount: _filteredInvoices.length,
                            itemBuilder: (context, index) {
                              final invoice = _filteredInvoices[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: ListTile(
                                  title: Text(invoice.customerName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                      'التاريخ: ${invoice.invoiceDate.toString().split(' ')[0]}'),
                                  trailing: Text(
                                      '${invoice.totalAmount.toStringAsFixed(2)} دينار'),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            CreateInvoiceScreen(
                                          existingInvoice: invoice,
                                          isViewOnly:
                                              invoice.status == 'محفوظة',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
