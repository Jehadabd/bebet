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
  late final NumberFormat _nfCompact = NumberFormat('#,##0', 'en');

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
    // Match the exact theme/colors used in customer_details_screen.dart
    final Color primaryColor = const Color(0xFF3F51B5); // Indigo 700
    final Color accentColor = const Color(0xFF8C9EFF); // Indigo A200
    final Color textColor = const Color(0xFF212121);
    final Color successColor = Colors.green[600]!;
    final Color errorColor = Colors.red[700]!;

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
          title: Text(widget.supplier.companyName),
          actions: [
            IconButton(
              icon: const Icon(Icons.receipt_long, color: Colors.white),
              tooltip: 'فاتورة جديدة (دين)',
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
              icon: const Icon(Icons.payments, color: Colors.white),
              tooltip: 'سند قبض (تسديد دين)',
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
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
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
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'معلومات المورد',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(context, 'الهاتف', (widget.supplier.phoneNumber ?? '').isEmpty ? 'غير متوفر' : widget.supplier.phoneNumber!),
                      const SizedBox(height: 12),
                      _buildInfoRow(context, 'العنوان', (widget.supplier.address ?? '').isEmpty ? 'غير متوفر' : widget.supplier.address!),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        context,
                        'إجمالي المديونية',
                        '${_nf.format(widget.supplier.currentBalance)} دينار',
                        valueColor: (widget.supplier.currentBalance) > 0
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.tertiary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'سجل المعاملات',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  TextButton.icon(
                    onPressed: _openQuickActions,
                    icon: Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.secondary, size: 28),
                    label: Text('إضافة معاملة',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.secondary)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(child: _buildUnifiedTimeline(context)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openQuickActions,
          icon: const Icon(Icons.add),
          label: const Text('إضافة'),
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
        Text(value, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }

  Widget _buildUnifiedTimeline(BuildContext context) {
    // Merge invoices (debt) and receipts (payment)
    final List<_Entry> entries = [];
    for (final inv in _invoices) {
      final remaining = inv.paymentType == 'نقد' ? 0.0 : (inv.totalAmount - inv.amountPaid);
      final delta = remaining < 0 ? 0.0 : remaining; // add debt
      entries.add(_Entry(dt: inv.invoiceDate, id: inv.id ?? -1, kind: 'invoice', delta: delta));
    }
    for (final r in _receipts) {
      entries.add(_Entry(dt: r.receiptDate, id: r.id ?? -1, kind: 'receipt', delta: -r.amount)); // payment reduces debt
    }
    entries.sort((a, b) {
      final c = b.dt.compareTo(a.dt);
      if (c != 0) return c;
      return b.id.compareTo(a.id);
    });

    if (entries.isEmpty) {
      return Center(child: Text('لا توجد معاملات', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final e = entries[index];
        final isDebt = e.delta > 0;
        final color = isDebt ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.tertiary;
        final icon = isDebt ? Icons.add : Icons.remove;
        final titleAmount = _nf.format(e.delta.abs());

        String subtitle = '';
        Map<String, double>? balanceMap;
        if (e.kind == 'invoice') {
          balanceMap = _invoiceBalances[e.id];
          subtitle = 'فاتورة مشتريات';
        } else {
          balanceMap = _receiptBalances[e.id];
          subtitle = 'سند قبض';
        }
        final dateStr = DateFormat('yyyy/MM/dd').format(e.dt);

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color, size: 28),
            ),
            title: Text('$titleAmount دينار', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color, fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (balanceMap != null)
                  Text('الرصيد بعد المعاملة: ${_nf.format(balanceMap['after'] ?? 0)} دينار'),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            trailing: Text(dateStr, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700], fontSize: 12)),
            onTap: () async {
              if (e.kind == 'invoice') {
                final inv = _invoices.firstWhere((x) => (x.id ?? -999) == e.id, orElse: () => _invoices.first);
                await _openInvoice(inv);
              } else {
                final rec = _receipts.firstWhere((x) => (x.id ?? -999) == e.id, orElse: () => _receipts.first);
                await _openReceipt(rec);
              }
            },
          ),
        );
      },
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


