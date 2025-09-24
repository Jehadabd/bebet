import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/supplier.dart';
import 'add_supplier_screen.dart';
import 'supplier_details_screen.dart';
import 'ai_import_review_screen.dart';
import '../services/suppliers_service.dart';
import '../services/database_service.dart';

class SuppliersListScreen extends StatefulWidget {
  const SuppliersListScreen({Key? key}) : super(key: key);

  @override
  State<SuppliersListScreen> createState() => _SuppliersListScreenState();
}

class _SuppliersListScreenState extends State<SuppliersListScreen> {
  final List<Supplier> _suppliers = [];
  final SuppliersService _suppliersService = SuppliersService();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _suppliers
        .where((s) => s.companyName.contains(_query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('الموردون'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _onAddSupplier,
            tooltip: 'إضافة مورد',
          ),
        ],
      ),
      body: Column(
        children: [
          FutureBuilder<void>(
            future: _suppliersService.ensureTables(),
            builder: (context, snapshot) => const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'ابحث باسم الشركة',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final supplier = filtered[index];
                  final colorScheme = Theme.of(context).colorScheme;
                  return Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primary.withOpacity(0.1),
                        child: Icon(Icons.factory, color: colorScheme.primary),
                      ),
                      title: Text(
                        supplier.companyName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'الرصيد الحالي: ${supplier.currentBalance.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: supplier.currentBalance > 0
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      trailing: Icon(Icons.chevron_left, color: colorScheme.onSurface.withOpacity(0.6)),
                      onTap: () => _openSupplierDetails(supplier),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'addInvoiceAI',
            icon: const Icon(Icons.auto_awesome),
            label: const Text('إضافة عبر الذكاء'),
            onPressed: _onAddByAI,
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'addSupplier',
            onPressed: _onAddSupplier,
            child: const Icon(Icons.add),
            tooltip: 'إضافة مورد',
          ),
        ],
      ),
    );
  }

  void _onAddSupplier() {
    Navigator.of(context)
        .push<Supplier>(
      MaterialPageRoute(builder: (_) => const AddSupplierScreen()),
    )
        .then((created) {
      if (created != null) {
        _insertSupplier(created);
      }
    });
  }

  void _onAddByAI() {
    _askTypeThenPick();
  }

  void _openSupplierDetails(Supplier supplier) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupplierDetailsScreen(supplier: supplier),
      ),
    );
  }

  Future<void> _pickFileAndOpenAI() async {
    // Default to invoice unless user chose otherwise earlier
    final selectedType = _pendingAIType ?? 'invoice';
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png'
            ? 'image/png'
            : 'image/jpeg');

    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم العثور على مفتاح GEMINI_API_KEY في .env')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiImportReviewScreen(
          fileBytes: bytes,
          mimeType: mime,
          type: selectedType,
          apiKey: apiKey,
        ),
      ),
    );
  }

  String? _pendingAIType; // 'invoice' or 'receipt'

  Future<void> _askTypeThenPick() async {
    final type = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر نوع العملية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('فاتورة شراء'),
              onTap: () => Navigator.of(context).pop('invoice'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.payments),
              title: const Text('سند قبض'),
              onTap: () => Navigator.of(context).pop('receipt'),
            ),
          ],
        ),
      ),
    );
    if (type == null) return;
    _pendingAIType = type;
    await _pickFileAndOpenAI();
    _pendingAIType = null;
  }

  @override
  void initState() {
    super.initState();
    _reload();
    _debugPrintAllProducts();
  }

  Future<void> _reload() async {
    final list = await _suppliersService.getAllSuppliers();
    setState(() {
      _suppliers
        ..clear()
        ..addAll(list);
    });
  }

  Future<void> _insertSupplier(Supplier s) async {
    final id = await _suppliersService.insertSupplier(s);
    final created = s.copyWith(id: id);
    setState(() {
      _suppliers.add(created);
    });
  }

  Future<void> _debugPrintAllProducts() async {
    try {
      final db = await DatabaseService().database;
      final rows = await db.query('products', columns: ['name']);
      final names = rows.map((e) => (e['name'] ?? '').toString()).where((s) => s.trim().isNotEmpty).toList();
      print('DEBUG SUPPLIERS: Loaded ${names.length} products from DB');
      for (final n in names) {
        print('DEBUG SUPPLIERS PRODUCT: $n');
      }
    } catch (e) {
      print('DEBUG SUPPLIERS: Failed to list products: $e');
    }
  }
}


