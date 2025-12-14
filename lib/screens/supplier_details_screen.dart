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
import 'audit_log_screen.dart';

class SupplierDetailsScreen extends StatefulWidget {
  final Supplier supplier;
  const SupplierDetailsScreen({Key? key, required this.supplier}) : super(key: key);

  @override
  State<SupplierDetailsScreen> createState() => _SupplierDetailsScreenState();
}

class _SupplierDetailsScreenState extends State<SupplierDetailsScreen> with SingleTickerProviderStateMixin {
  final SuppliersService _service = SuppliersService();
  List<SupplierInvoice> _invoices = const [];
  List<SupplierReceipt> _receipts = const [];
  List<Attachment> _attachments = const [];
  final NumberFormat _nf = NumberFormat('#,##0', 'en');
  final Map<int, Map<String, double>> _invoiceBalances = {}; // id -> {before, after}
  final Map<int, Map<String, double>> _receiptBalances = {}; // id -> {before, after}
  late final NumberFormat _nfCompact = NumberFormat('#,##0', 'en');
  late Supplier _currentSupplier; // المورد الحالي مع البيانات المحدثة
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _currentSupplier = widget.supplier; // نسخ البيانات الأولية
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    print('\n🔄 تحديث بيانات المورد ${widget.supplier.companyName}...');
    
    // إعادة تحميل بيانات المورد من قاعدة البيانات للحصول على الرصيد المحدث
    final suppliers = await _service.getAllSuppliers();
    final updatedSupplier = suppliers.firstWhere(
      (s) => s.id == widget.supplier.id,
      orElse: () => widget.supplier,
    );
    
    final inv = await _service.getInvoicesBySupplier(widget.supplier.id!);
    final rec = await _service.getReceiptsBySupplier(widget.supplier.id!);
    final att = await _service.getAttachmentsForSupplier(widget.supplier.id!);
    
    print('📊 عدد الفواتير: ${inv.length}');
    if (inv.isNotEmpty) {
      for (var i in inv) {
        print('  📄 فاتورة ${i.id}: ${i.invoiceNumber}, ${i.totalAmount} دينار, نوع: ${i.paymentType}');
      }
    }
    
    print('📊 عدد سندات القبض: ${rec.length}');
    if (rec.isNotEmpty) {
      for (var r in rec) {
        print('  💰 سند ${r.id}: ${r.receiptNumber}, ${r.amount} دينار, تاريخ: ${r.receiptDate}');
      }
    } else {
      print('  ⚠️ لا توجد سندات قبض لهذا المورد!');
    }
    
    print('📊 عدد المرفقات: ${att.length}');
    print('💰 الرصيد الحالي: ${updatedSupplier.currentBalance}');
    
    setState(() {
      _currentSupplier = updatedSupplier;
      _invoices = inv;
      _receipts = rec;
      _attachments = att;
    });
    _computeRunningBalances();
    print('✅ تم تحديث البيانات بنجاح\n');
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
            // 📋 زر سجل التدقيق المالي
            IconButton(
              icon: const Icon(Icons.history, color: Colors.white),
              tooltip: 'سجل التدقيق المالي',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AuditLogScreen(
                      customerId: widget.supplier.id,
                      customerName: widget.supplier.companyName,
                      entityType: 'supplier',
                    ),
                  ),
                );
              },
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
                      _buildInfoRow(context, 'الهاتف', (_currentSupplier.phoneNumber ?? '').isEmpty ? 'غير متوفر' : _currentSupplier.phoneNumber!),
                      const SizedBox(height: 12),
                      _buildInfoRow(context, 'العنوان', (_currentSupplier.address ?? '').isEmpty ? 'غير متوفر' : _currentSupplier.address!),
                      const SizedBox(height: 12),
                      _buildInfoRow(
                        context,
                        'إجمالي المديونية',
                        '${_nf.format(_currentSupplier.currentBalance)} دينار',
                        valueColor: (_currentSupplier.currentBalance) > 0
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
              const SizedBox(height: 12),
              // التبويبات الثلاثة
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey[700],
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
                  tabs: [
                    Tab(
                      icon: const Icon(Icons.receipt_long, size: 20),
                      text: 'فواتير نقد',
                    ),
                    Tab(
                      icon: const Icon(Icons.credit_card, size: 20),
                      text: 'فواتير دين',
                    ),
                    Tab(
                      icon: const Icon(Icons.payments, size: 20),
                      text: 'سندات قبض',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCashInvoicesTab(context),
                    _buildCreditInvoicesTab(context),
                    _buildReceiptsTab(context),
                  ],
                ),
              ),
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

  // تبويب فواتير النقد
  Widget _buildCashInvoicesTab(BuildContext context) {
    final cashInvoices = _invoices.where((inv) => inv.paymentType == 'نقد').toList();
    cashInvoices.sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));

    if (cashInvoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا توجد فواتير نقد',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: cashInvoices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final inv = cashInvoices[index];
        return _buildInvoiceCard(context, inv, Colors.blue, Icons.receipt);
      },
    );
  }

  // تبويب فواتير الدين
  Widget _buildCreditInvoicesTab(BuildContext context) {
    final creditInvoices = _invoices.where((inv) => inv.paymentType == 'دين').toList();
    creditInvoices.sort((a, b) => b.invoiceDate.compareTo(a.invoiceDate));

    if (creditInvoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.credit_card, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا توجد فواتير دين',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: creditInvoices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final inv = creditInvoices[index];
        return _buildInvoiceCard(context, inv, Theme.of(context).colorScheme.error, Icons.add);
      },
    );
  }

  // تبويب سندات القبض
  Widget _buildReceiptsTab(BuildContext context) {
    final receipts = List<SupplierReceipt>.from(_receipts);
    receipts.sort((a, b) => b.receiptDate.compareTo(a.receiptDate));

    if (receipts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payments, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا توجد سندات قبض',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: receipts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final receipt = receipts[index];
        return _buildReceiptCard(context, receipt);
      },
    );
  }

  // بطاقة عرض الفاتورة
  Widget _buildInvoiceCard(BuildContext context, SupplierInvoice inv, Color color, IconData icon) {
    final DateFormat dateFormat = DateFormat('yyyy-MM-dd');
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showInvoiceDetails(inv),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'فاتورة ${inv.invoiceNumber}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(inv.invoiceDate),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    if (inv.paymentType == 'دين' && inv.totalAmount > inv.amountPaid) ...[
                      const SizedBox(height: 4),
                      Text(
                        'المتبقي: ${_nf.format(inv.totalAmount - inv.amountPaid)} دينار',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange[700],
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_nf.format(inv.totalAmount)} دينار',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: inv.paymentType == 'نقد' ? Colors.blue[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      inv.paymentType,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: inv.paymentType == 'نقد' ? Colors.blue[700] : Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // بطاقة عرض سند القبض
  Widget _buildReceiptCard(BuildContext context, SupplierReceipt receipt) {
    final DateFormat dateFormat = DateFormat('yyyy-MM-dd');
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showReceiptDetails(receipt),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.payments, color: Colors.green[700], size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'سند قبض ${receipt.receiptNumber}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dateFormat.format(receipt.receiptDate),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                    if (receipt.paymentMethod != null && receipt.paymentMethod!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'طريقة الدفع: ${receipt.paymentMethod}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '${_nf.format(receipt.amount)} دينار',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedTimeline(BuildContext context) {
    print('\n📋 بناء سجل المعاملات...');
    print('📊 عدد الفواتير: ${_invoices.length}');
    print('📊 عدد سندات القبض: ${_receipts.length}');
    
    // Merge invoices (debt) and receipts (payment)
    final List<_Entry> entries = [];
    
    // إضافة الفواتير
    for (final inv in _invoices) {
      // حساب المبلغ الذي يؤثر على الدين
      final remaining = inv.paymentType == 'نقد' ? 0.0 : (inv.totalAmount - inv.amountPaid);
      final delta = remaining < 0 ? 0.0 : remaining;
      
      // حفظ معلومات إضافية للعرض
      entries.add(_Entry(
        dt: inv.invoiceDate,
        id: inv.id ?? -1,
        kind: 'invoice',
        delta: delta,
        totalAmount: inv.totalAmount, // المبلغ الإجمالي للعرض
        paymentType: inv.paymentType, // نوع الدفع
        createdAt: inv.createdAt,
      ));
      print('  ➕ فاتورة ${inv.id}: ${inv.paymentType}, ${inv.totalAmount} دينار, تاريخ الإنشاء: ${inv.createdAt}');
    }
    
    // إضافة سندات القبض
    for (final r in _receipts) {
      entries.add(_Entry(
        dt: r.receiptDate,
        id: r.id ?? -1,
        kind: 'receipt',
        delta: -r.amount, // سالب لأنه يخفض الدين
        totalAmount: r.amount,
        createdAt: r.createdAt,
      ));
      print('  ➖ سند قبض ${r.id}: ${r.amount} دينار, تاريخ الإنشاء: ${r.createdAt}');
    }
    
    // ترتيب من الأحدث إلى الأقدم
    entries.sort((a, b) {
      // أولاً: حسب تاريخ المعاملة (الأحدث أولاً)
      final c = b.dt.compareTo(a.dt);
      if (c != 0) return c;
      // ثانياً: حسب وقت الإنشاء (الأحدث أولاً)
      return b.createdAt.compareTo(a.createdAt);
    });

    print('📊 إجمالي المعاملات في السجل: ${entries.length}');

    if (entries.isEmpty) {
      return Center(child: Text('لا توجد معاملات', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])));
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final e = entries[index];
        
        // تحديد نوع المعاملة والمبلغ المعروض
        String displayAmount;
        Color color;
        IconData icon;
        String subtitle;
        
        if (e.kind == 'invoice') {
          // فاتورة
          if (e.paymentType == 'نقد') {
            // فاتورة نقد: تظهر المبلغ الفعلي (وليس صفر)
            displayAmount = _nf.format(e.totalAmount ?? 0);
            color = Colors.blue;
            icon = Icons.receipt;
            subtitle = 'فاتورة مشتريات نقد';
          } else {
            // فاتورة دين: تظهر المبلغ الفعلي
            displayAmount = _nf.format(e.totalAmount ?? 0);
            color = Theme.of(context).colorScheme.error;
            icon = Icons.add;
            subtitle = 'فاتورة مشتريات آجل';
          }
        } else {
          // سند قبض: يخفض الدين
          displayAmount = _nf.format(e.totalAmount ?? 0);
          color = Theme.of(context).colorScheme.tertiary;
          icon = Icons.remove;
          subtitle = 'سند قبض';
        }
        
        Map<String, double>? balanceMap;
        if (e.kind == 'invoice') {
          balanceMap = _invoiceBalances[e.id];
        } else {
          balanceMap = _receiptBalances[e.id];
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
            title: Text('$displayAmount دينار', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color, fontWeight: FontWeight.bold)),
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
    print('\n🔑 تحميل مفاتيح API...');
    print('📂 محتويات dotenv.env:');
    dotenv.env.forEach((key, value) {
      if (key.contains('API_KEY')) {
        // إخفاء جزء من المفتاح للأمان
        final maskedValue = value.length > 10 
            ? '${value.substring(0, 10)}...${value.substring(value.length - 4)}'
            : '***';
        print('  $key = $maskedValue');
      }
    });
    
    final geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final geminiApiKey2 = dotenv.env['GEMINI_API_KEY_2'] ?? '';
    final geminiApiKey3 = dotenv.env['GEMINI_API_KEY_3'] ?? '';
    
    if (geminiApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم العثور على GEMINI_API_KEY')),
      );
      return;
    }
    
    print('🟢 GEMINI_API_KEY: موجود ✅');
    
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
          geminiApiKey: geminiApiKey,
          geminiApiKey2: geminiApiKey2.isNotEmpty ? geminiApiKey2 : null,
          geminiApiKey3: geminiApiKey3.isNotEmpty ? geminiApiKey3 : null,
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
    print('\n🔢 حساب الأرصدة...');
    _invoiceBalances.clear();
    _receiptBalances.clear();
    
    // جهّز تسلسل موحد للعمليات حسب التاريخ ثم id
    final List<_Entry> entries = [];
    
    print('📊 عدد الفواتير: ${_invoices.length}');
    for (final inv in _invoices) {
      final remaining = inv.paymentType == 'نقد'
          ? 0.0
          : (inv.totalAmount - (inv.amountPaid));
      entries.add(_Entry(
        dt: inv.invoiceDate,
        id: inv.id ?? -1,
        kind: 'invoice',
        delta: remaining < 0 ? 0.0 : remaining,
        createdAt: inv.createdAt,
      ));
      print('  ➕ فاتورة ${inv.id}: نوع=${inv.paymentType}, مبلغ=${inv.totalAmount}, مدفوع=${inv.amountPaid}, تأثير=$remaining');
    }
    
    print('📊 عدد سندات القبض: ${_receipts.length}');
    for (final r in _receipts) {
      entries.add(_Entry(
        dt: r.receiptDate,
        id: r.id ?? -1,
        kind: 'receipt',
        delta: -r.amount,
        createdAt: r.createdAt,
      ));
      print('  ➖ سند ${r.id}: مبلغ=${r.amount}, تأثير=${-r.amount}');
    }
    
    // رتب من الأقدم إلى الأحدث للحساب الصحيح
    entries.sort((a, b) {
      // أولاً: حسب تاريخ المعاملة (الأقدم أولاً)
      final c = a.dt.compareTo(b.dt);
      if (c != 0) return c;
      // ثانياً: حسب وقت الإنشاء (الأقدم أولاً)
      return a.createdAt.compareTo(b.createdAt);
    });

    print('📊 إجمالي المعاملات: ${entries.length}');
    
    // احسب الرصيد من الصفر إلى الحالي
    try {
      double runningBalance = 0.0;
      
      for (final e in entries) {
        final before = runningBalance;
        final after = before + e.delta;
        
        if (e.kind == 'invoice') {
          _invoiceBalances[e.id] = {'before': before, 'after': after};
          print('  📄 فاتورة ${e.id}: قبل=${before.toStringAsFixed(2)}، تغيير=${e.delta.toStringAsFixed(2)}, بعد=${after.toStringAsFixed(2)}');
        } else {
          _receiptBalances[e.id] = {'before': before, 'after': after};
          print('  💰 سند ${e.id}: قبل=${before.toStringAsFixed(2)}، تغيير=${e.delta.toStringAsFixed(2)}, بعد=${after.toStringAsFixed(2)}');
        }
        
        runningBalance = after;
      }
      
      print('💰 الرصيد النهائي المحسوب: ${runningBalance.toStringAsFixed(2)}');
      print('💰 الرصيد الفعلي في القاعدة: ${_currentSupplier.currentBalance.toStringAsFixed(2)}');
      
      // تحقق من التطابق
      final diff = (runningBalance - _currentSupplier.currentBalance).abs();
      if (diff > 0.01) {
        print('⚠️ تحذير: هناك فرق بين الرصيد المحسوب والفعلي: ${diff.toStringAsFixed(2)}');
      }
      
    } catch (e) {
      print('❌ خطأ في حساب الأرصدة: $e');
    }
    
    if (mounted) setState(() {});
    print('✅ انتهى حساب الأرصدة\n');
  }

  // عرض تفاصيل الفاتورة
  void _showInvoiceDetails(SupplierInvoice invoice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل فاتورة ${invoice.invoiceNumber ?? "بدون رقم"}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('رقم الفاتورة', invoice.invoiceNumber ?? 'غير محدد'),
              _buildDetailRow('التاريخ', DateFormat('yyyy-MM-dd').format(invoice.invoiceDate)),
              _buildDetailRow('المبلغ الإجمالي', '${_nf.format(invoice.totalAmount)} دينار'),
              _buildDetailRow('نوع الدفع', invoice.paymentType),
              _buildDetailRow('الحالة', invoice.status),
              if (invoice.paymentType == 'دين') ...[
                _buildDetailRow('المبلغ المدفوع', '${_nf.format(invoice.amountPaid)} دينار'),
                _buildDetailRow('المتبقي', '${_nf.format(invoice.totalAmount - invoice.amountPaid)} دينار'),
              ],
              if (invoice.discount > 0)
                _buildDetailRow('الخصم', '${_nf.format(invoice.discount)} دينار'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // عرض تفاصيل سند القبض
  void _showReceiptDetails(SupplierReceipt receipt) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل سند ${receipt.receiptNumber ?? "بدون رقم"}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('رقم السند', receipt.receiptNumber ?? 'غير محدد'),
              _buildDetailRow('التاريخ', DateFormat('yyyy-MM-dd').format(receipt.receiptDate)),
              _buildDetailRow('المبلغ', '${_nf.format(receipt.amount)} دينار'),
              if (receipt.paymentMethod != null && receipt.paymentMethod!.isNotEmpty)
                _buildDetailRow('طريقة الدفع', receipt.paymentMethod!),
              if (receipt.notes != null && receipt.notes!.isNotEmpty)
                _buildDetailRow('ملاحظات', receipt.notes!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // صف تفاصيل
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

class _Entry {
  final DateTime dt;
  final int id;
  final String kind; // invoice | receipt
  final double delta; // التغيير في الدين
  final double? totalAmount; // المبلغ الإجمالي للعرض
  final String? paymentType; // نوع الدفع (نقد/دين)
  final DateTime createdAt; // وقت الإنشاء للترتيب الصحيح
  
  _Entry({
    required this.dt,
    required this.id,
    required this.kind,
    required this.delta,
    this.totalAmount,
    this.paymentType,
    required this.createdAt,
  });
}


