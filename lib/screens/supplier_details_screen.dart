import 'package:flutter/material.dart';
import '../models/supplier.dart';
import '../services/suppliers_service.dart';
import 'ai_import_review_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'new_supplier_invoice_screen.dart';
import 'new_supplier_receipt_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class SupplierDetailsScreen extends StatefulWidget {
  final Supplier supplier;
  const SupplierDetailsScreen({Key? key, required this.supplier}) : super(key: key);

  @override
  State<SupplierDetailsScreen> createState() => _SupplierDetailsScreenState();
}

class _SupplierDetailsScreenState extends State<SupplierDetailsScreen> {
  final SuppliersService _service = SuppliersService();
  List<SupplierInvoice> _invoices = const [];
  List<SupplierReceipt> _receipts = const [];
  List<Attachment> _attachments = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final inv = await _service.getInvoicesBySupplier(widget.supplier.id!);
    final rec = await _service.getReceiptsBySupplier(widget.supplier.id!);
    final att = await _service.getAttachmentsForSupplier(widget.supplier.id!);
    setState(() {
      _invoices = inv;
      _receipts = rec;
      _attachments = att;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.supplier.companyName),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'إضافة فاتورة',
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => NewSupplierInvoiceScreen(supplier: widget.supplier),
                ),
              );
              if (saved == true) {
                await _loadData();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.payments),
            tooltip: 'إضافة سند قبض',
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => NewSupplierReceiptScreen(supplier: widget.supplier),
                ),
              );
              if (saved == true) {
                await _loadData();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'إضافة عبر الذكاء',
            onPressed: _onAddByAI,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 1.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  child: Icon(Icons.factory, color: Theme.of(context).colorScheme.primary),
                ),
                title: Text(
                  widget.supplier.companyName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'الرصيد الحالي: ${widget.supplier.currentBalance.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: widget.supplier.currentBalance > 0
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((widget.supplier.phoneNumber ?? '').isNotEmpty)
                      Text(widget.supplier.phoneNumber!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'الفواتير'),
                        Tab(text: 'سندات القبض'),
                        Tab(text: 'المرفقات'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(children: [
                        _buildInvoices(),
                        _buildReceipts(),
                        _buildAttachments(),
                      ]),
                    )
                  ],
                ),
              ),
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQuickActions,
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
      ),
    );
  }

  Widget _buildInvoices() {
    if (_invoices.isEmpty) return const Center(child: Text('لا فواتير'));
    return ListView.separated(
      itemCount: _invoices.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final inv = _invoices[i];
        return ListTile(
          leading: const Icon(Icons.receipt_long),
          title: Text(inv.invoiceNumber ?? 'بدون رقم'),
          subtitle: Text(inv.invoiceDate.toIso8601String()),
          trailing: Text(inv.totalAmount.toStringAsFixed(0)),
          onTap: () => _openInvoice(inv),
        );
      },
    );
  }

  Widget _buildReceipts() {
    if (_receipts.isEmpty) return const Center(child: Text('لا سندات'));
    return ListView.separated(
      itemCount: _receipts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final rec = _receipts[i];
        return ListTile(
          leading: const Icon(Icons.payments),
          title: Text(rec.receiptNumber ?? 'بدون رقم'),
          subtitle: Text(rec.receiptDate.toIso8601String()),
          trailing: Text(rec.amount.toStringAsFixed(0)),
          onTap: () => _openReceipt(rec),
        );
      },
    );
  }

  Widget _buildAttachments() {
    if (_attachments.isEmpty) return const Center(child: Text('لا مرفقات'));
    return ListView.separated(
      itemCount: _attachments.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final att = _attachments[i];
        return ListTile(
          leading: Icon(att.fileType == 'pdf' ? Icons.picture_as_pdf : Icons.image),
          title: Text(att.filePath.split('/').last),
          subtitle: Text(att.ownerType),
        );
      },
    );
  }

  Future<void> _openInvoice(SupplierInvoice inv) async {
    final atts = await _service.getAttachmentsForOwner(ownerType: 'SupplierInvoice', ownerId: inv.id!);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('فاتورة ${inv.invoiceNumber ?? ''}'),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('التاريخ: ${inv.invoiceDate.toIso8601String()}'),
              Text('الإجمالي: ${inv.totalAmount.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              const Text('المرفقات:'),
              if (atts.isEmpty) const Text('لا يوجد مرفقات'),
              if (atts.isNotEmpty)
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    itemCount: atts.length,
                    itemBuilder: (_, i) {
                      final a = atts[i];
                      return ListTile(
                        leading: Icon(a.fileType == 'pdf' ? Icons.picture_as_pdf : Icons.image),
                        title: Text(a.filePath.split('/').last),
                        onTap: () => _openAttachment(a),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Future<void> _openReceipt(SupplierReceipt rec) async {
    final atts = await _service.getAttachmentsForOwner(ownerType: 'SupplierReceipt', ownerId: rec.id!);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('سند ${rec.receiptNumber ?? ''}'),
        content: SizedBox(
          width: 600,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('التاريخ: ${rec.receiptDate.toIso8601String()}'),
              Text('المبلغ: ${rec.amount.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              const Text('المرفقات:'),
              if (atts.isEmpty) const Text('لا يوجد مرفقات'),
              if (atts.isNotEmpty)
                SizedBox(
                  height: 200,
                  child: ListView.builder(
                    itemCount: atts.length,
                    itemBuilder: (_, i) {
                      final a = atts[i];
                      return ListTile(
                        leading: Icon(a.fileType == 'pdf' ? Icons.picture_as_pdf : Icons.image),
                        title: Text(a.filePath.split('/').last),
                        onTap: () => _openAttachment(a),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Future<void> _openAttachment(Attachment a) async {
    try {
      final uri = Uri.file(a.filePath);
      await launchUrl(uri);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح الملف: $e')),
      );
    }
  }

  void _openQuickActions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.receipt_long),
                title: const Text('فاتورة جديدة (يدوي)'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => NewSupplierInvoiceScreen(supplier: widget.supplier),
                    ),
                  );
                  if (saved == true) await _loadData();
                },
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('فاتورة بالذكاء (PDF/صورة)'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _onAddByAI();
                },
              ),
              ListTile(
                leading: const Icon(Icons.payments),
                title: const Text('سند قبض جديد'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => NewSupplierReceiptScreen(supplier: widget.supplier),
                    ),
                  );
                  if (saved == true) await _loadData();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onAddByAI() async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GEMINI_API_KEY غير مضبوط')),
      );
      return;
    }
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
    // Pick file
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AiImportReviewScreen(
          fileBytes: bytes,
          mimeType: mime,
          type: type,
          apiKey: apiKey,
          supplierId: widget.supplier.id,
        ),
      ),
    );
    if (saved == true) {
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم الحفظ بنجاح')),
      );
    }
  }
}


