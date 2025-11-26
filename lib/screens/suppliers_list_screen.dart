import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/supplier.dart';
import 'add_supplier_screen.dart';
import 'supplier_details_screen.dart';
import 'ai_import_review_screen.dart';
import '../services/suppliers_service.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';

class SuppliersListScreen extends StatefulWidget {
  const SuppliersListScreen({Key? key}) : super(key: key);

  @override
  State<SuppliersListScreen> createState() => _SuppliersListScreenState();
}

class _SuppliersListScreenState extends State<SuppliersListScreen> {
  final List<Supplier> _suppliers = [];
  final SuppliersService _suppliersService = SuppliersService();
  String _query = '';
  final NumberFormat _nf = NumberFormat('#,##0', 'en');

  @override
  Widget build(BuildContext context) {
    final filtered = _suppliers
        .where((s) => s.companyName.contains(_query))
        .toList();
    final Color primaryColor = const Color(0xFF3F51B5); // Indigo 700
    final Color accentColor = const Color(0xFF8C9EFF); // Indigo A200
    final Color textColor = const Color(0xFF212121);
    final Color successColor = Colors.green.shade600;
    final Color errorColor = Colors.red.shade700;

    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white,
          secondary: accentColor,
          onSecondary: Colors.black,
          surface: Colors.white,
          onSurface: textColor,
          background: Colors.white,
          onBackground: textColor,
          error: errorColor,
          onError: Colors.white,
          tertiary: successColor,
        ),
        fontFamily: 'Roboto',
        textTheme: TextTheme(
          titleLarge: const TextStyle(fontSize: 22.0, fontWeight: FontWeight.bold, color: Colors.white),
          titleMedium: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w600, color: textColor),
          bodyLarge: TextStyle(fontSize: 16.0, color: textColor),
          bodyMedium: TextStyle(fontSize: 14.0, color: textColor),
          labelLarge: const TextStyle(fontSize: 16.0, color: Colors.white, fontWeight: FontWeight.w600),
          labelMedium: TextStyle(fontSize: 14.0, color: Colors.grey[600]),
          bodySmall: TextStyle(fontSize: 12.0, color: Colors.grey[700]),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 4,
          titleTextStyle: const TextStyle(fontSize: 24.0, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        cardTheme: const CardThemeData(
          elevation: 3,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12.0))),
        ),
        listTileTheme: ListTileThemeData(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          tileColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الموردون'),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add, color: Colors.white),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'قائمة الموردين',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  TextButton.icon(
                    onPressed: _onAddSupplier,
                    icon: Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.secondary, size: 28),
                    label: Text('إضافة مورد',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.secondary)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final supplier = filtered[index];
                    final colorScheme = Theme.of(context).colorScheme;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: colorScheme.primary.withOpacity(0.1),
                          child: Icon(Icons.factory, color: colorScheme.primary),
                        ),
                        title: Text(
                          supplier.companyName,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'المبلغ المطلوب: ${_nf.format(supplier.currentBalance)}',
                              style: TextStyle(
                                color: supplier.currentBalance > 0 ? errorColor : successColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text('إجمالي المشتريات: ${_nf.format(supplier.totalPurchases)}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                        trailing: Icon(Icons.chevron_left, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
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
    ).then((_) => _reload()); // بعد العودة حدّث القائمة لتحديث الأرصدة
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

    final groqApiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    final geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final huggingfaceApiKey = dotenv.env['HUGGINGFACE_API_KEY'] ?? '';
    
    if (groqApiKey.isEmpty && geminiApiKey.isEmpty && huggingfaceApiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم العثور على أي API Key في .env')),
      );
      return;
    }

    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AiImportReviewScreen(
          fileBytes: bytes,
          mimeType: mime,
          type: selectedType,
          groqApiKey: groqApiKey,
          geminiApiKey: geminiApiKey,
          huggingfaceApiKey: huggingfaceApiKey,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _reload();
    }
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
}


