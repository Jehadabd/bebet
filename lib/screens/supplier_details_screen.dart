import 'package:flutter/material.dart';
import '../models/supplier.dart';
import '../services/suppliers_service.dart';
import '../services/database_service.dart';
import 'ai_import_review_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'new_supplier_invoice_screen.dart';
import 'new_supplier_receipt_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

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
  final NumberFormat _nf = NumberFormat('#,##0', 'en');
  final Map<int, Map<String, double>> _invoiceBalances = {}; // id -> {before, after}
  final Map<int, Map<String, double>> _receiptBalances = {}; // id -> {before, after}

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
    _computeRunningBalances();
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
                      'المبلغ المطلوب: ${_nf.format(widget.supplier.currentBalance)}',
                      style: TextStyle(
                        color: widget.supplier.currentBalance > 0
                            ? Colors.red.shade700
                            : Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'إجمالي المشتريات: ${_nf.format(widget.supplier.totalPurchases)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(inv.invoiceDate.toIso8601String()),
              if (_invoiceBalances[inv.id ?? -1] != null)
                Text(
                  'قبل: ${_nf.format(_invoiceBalances[inv.id]!['before']!)}  →  بعد: ${_nf.format(_invoiceBalances[inv.id]!['after']!)}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
          trailing: Text(_nf.format(inv.totalAmount)),
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
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rec.receiptDate.toIso8601String()),
              if (_receiptBalances[rec.id ?? -1] != null)
                Text(
                  'قبل: ${_nf.format(_receiptBalances[rec.id]!['before']!)}  →  بعد: ${_nf.format(_receiptBalances[rec.id]!['after']!)}',
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
          trailing: Text(_nf.format(rec.amount)),
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
              Text('الإجمالي: ${_nf.format(inv.totalAmount)}'),
              if (_invoiceBalances[inv.id ?? -1] != null)
                Text('الرصيد قبل: ${_nf.format(_invoiceBalances[inv.id]!['before']!)}  →  بعد: ${_nf.format(_invoiceBalances[inv.id]!['after']!)}'),
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
              Text('المبلغ: ${_nf.format(rec.amount)}'),
              if (_receiptBalances[rec.id ?? -1] != null)
                Text('الرصيد قبل: ${_nf.format(_receiptBalances[rec.id]!['before']!)}  →  بعد: ${_nf.format(_receiptBalances[rec.id]!['after']!)}'),
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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.receipt_long),
                label: const Text('فاتورة جديدة (يدوي)'),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => NewSupplierInvoiceScreen(supplier: widget.supplier),
                    ),
                  );
                  if (saved == true) await _loadData();
                },
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('فاتورة بالذكاء (PDF/صورة)'),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await _onAddByAI();
                },
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.payments),
                label: const Text('سند قبض جديد'),
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => NewSupplierReceiptScreen(supplier: widget.supplier),
                    ),
                  );
                  if (saved == true) await _loadData();
                },
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
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

  void _computeRunningBalances() async {
    _invoiceBalances.clear();
    _receiptBalances.clear();
    // جهّز تسلسل موحد للعمليات حسب التاريخ ثم id
    final List<_Entry> entries = [];
    for (final inv in _invoices) {
      final remaining = inv.paymentType == 'نقد'
          ? 0.0
          : (inv.totalAmount - (inv.amountPaid));
      entries.add(_Entry(
        dt: inv.invoiceDate,
        id: inv.id ?? -1,
        kind: 'invoice',
        delta: remaining < 0 ? 0.0 : remaining,
      ));
    }
    for (final r in _receipts) {
      entries.add(_Entry(
        dt: r.receiptDate,
        id: r.id ?? -1,
        kind: 'receipt',
        delta: -r.amount,
      ));
    }
    // رتب من الأحدث إلى الأقدم
    entries.sort((a, b) {
      final c = b.dt.compareTo(a.dt);
      if (c != 0) return c;
      return b.id.compareTo(a.id);
    });

    // احسب الرصيد الرجعي بدءاً من current_balance الحالي من القاعدة لضمان التطابق
    try {
      final db = await DatabaseService().database;
      final row = await db.query('suppliers', columns: ['current_balance'], where: 'id = ?', whereArgs: [widget.supplier.id], limit: 1);
      double runningAfter = row.isNotEmpty ? ((row.first['current_balance'] as num?)?.toDouble() ?? widget.supplier.currentBalance) : widget.supplier.currentBalance;
      for (final e in entries) {
        final after = runningAfter;
        final before = after - e.delta;
        if (e.kind == 'invoice') {
          _invoiceBalances[e.id] = {'before': before, 'after': after};
        } else {
          _receiptBalances[e.id] = {'before': before, 'after': after};
        }
        runningAfter = before;
      }
    } catch (_) {
      // في حالة الفشل، لا نُظهر الأرقام لتجنب التضليل
    }
    if (mounted) setState(() {});
  }
}

class _Entry {
  final DateTime dt;
  final int id;
  final String kind; // invoice | receipt
  final double delta;
  _Entry({required this.dt, required this.id, required this.kind, required this.delta});
}


