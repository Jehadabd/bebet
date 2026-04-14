import 'package:flutter/material.dart';
import '../models/supplier.dart';
import '../models/delegate.dart';
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
  List<Delegate> _delegates = const [];
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
    
    final dels = await _service.getDelegatesBySupplier(widget.supplier.id!);
    print('💰 الرصيد الحالي: ${updatedSupplier.currentBalance}');
    
    setState(() {
      _currentSupplier = updatedSupplier;
      _invoices = inv;
      _receipts = rec;
      _attachments = att;
      _delegates = dels;
    });
    _computeRunningBalances();
    print('✅ تم تحديث البيانات بنجاح\n');
  }

  Future<void> _deleteDelegate(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المندوب'),
        content: const Text('هل أنت متأكد من حذف هذا المندوب؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await _service.deleteDelegate(id);
      _loadData();
    }
  }

  void _showAddDelegateDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مندوب'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم المندوب *'),
                validator: (v) => v == null || v.isEmpty ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                final d = Delegate(
                  supplierId: widget.supplier.id!,
                  name: nameCtrl.text.trim(),
                  phoneNumber: phoneCtrl.text.trim(),
                );
                await _service.insertDelegate(d);
                Navigator.pop(ctx);
                _loadData();
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Background Navy Header
          Container(
            height: 260,
            color: const Color(0xFF151C2C),
          ),
          SafeArea(
            child: Column(
              children: [
                // Top App Bar Area
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Row(
                    children: [
                      // Temporary Edit Icon as Placeholder
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.white),
                        onPressed: () {},
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Avatar and Details Row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _currentSupplier.companyName,
                                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text('نقدي', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ),
                                      if (_currentSupplier.phoneNumber != null && _currentSupplier.phoneNumber!.isNotEmpty) ...[
                                        const SizedBox(width: 12),
                                        Text(_currentSupplier.phoneNumber!, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                                        const SizedBox(width: 4),
                                        const Icon(Icons.phone, color: Colors.white70, size: 16),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(0.1),
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _currentSupplier.companyName.isNotEmpty ? _currentSupplier.companyName[0] : '?',
                                  style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Stats Cards
                        Padding(
                          padding: const EdgeInsets.only(top: 32.0, left: 24, right: 24),
                          child: Row(
                            children: [
                              _buildTopStatCard('المدفوعات', '${_receipts.length}', Icons.payments, const Color(0xFFF3E5F5), const Color(0xFF8E24AA)),
                              const SizedBox(width: 16),
                              _buildTopStatCard('الفواتير', '${_invoices.length}', Icons.receipt_long, const Color(0xFFE3F2FD), const Color(0xFF1E88E5)),
                              const SizedBox(width: 16),
                              _buildTopStatCard('الرصيد الكلي', 'IQD ${_formatCompact(_currentSupplier.currentBalance)}', Icons.account_balance_wallet, const Color(0xFFE8F5E9), const Color(0xFF43A047)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Delegates Section
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton.icon(
                                    onPressed: _showAddDelegateDialog,
                                    icon: const Icon(Icons.add_circle_outline, size: 18),
                                    label: const Text('إضافة مندوب', style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF4F46E5)),
                                  ),
                                  Row(
                                    children: const [
                                      Text('المندوبين', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                      SizedBox(width: 8),
                                      Icon(Icons.people_outline, color: Color(0xFF64748B), size: 20),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_delegates.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFFE2E8F0)),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(Icons.group_off_outlined, color: Colors.grey[300], size: 48),
                                      const SizedBox(height: 12),
                                      const Text('لا يوجد مندوبين مرتبطين', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _delegates.length,
                                  itemBuilder: (context, index) {
                                    final delegate = _delegates[index];
                                    return Card(
                                      elevation: 0,
                                      margin: const EdgeInsets.only(bottom: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE2E8F0))),
                                      child: ListTile(
                                        leading: const CircleAvatar(backgroundColor: Color(0xFFF8FAFC), child: Icon(Icons.person, color: Color(0xFF64748B))),
                                        title: Text(delegate.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: delegate.phoneNumber != null && delegate.phoneNumber!.isNotEmpty 
                                            ? Text(delegate.phoneNumber!) 
                                            : null,
                                        trailing: IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                                          onPressed: () => _deleteDelegate(delegate.id!),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Invoices Section
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: const [
                                  Text('آخر الفواتير', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                                  SizedBox(width: 8),
                                  Icon(Icons.receipt_long_outlined, color: Color(0xFF64748B), size: 20),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _buildUnifiedTimeline(context),
                              const SizedBox(height: 80), // Fab space
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openQuickActions,
        backgroundColor: const Color(0xFF151C2C),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('إجراء جديد', style: TextStyle(color: Colors.white)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildTopStatCard(String title, String value, IconData icon, Color iconBgColor, Color iconColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatCompact(double number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
    return _nf.format(number);
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
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
    // جلب المرفقات وأصناف الفاتورة
    final atts = await _service.getAttachmentsForOwner(ownerType: 'SupplierInvoice', ownerId: inv.id!);
    final items = await _service.getInvoiceItems(inv.id!);
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Expanded(child: Text('فاتورة ${inv.invoiceNumber ?? ''}')),
            // زر التعديل
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              tooltip: 'تعديل الفاتورة',
              onPressed: () {
                Navigator.of(ctx).pop();
                _editInvoice(inv);
              },
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // معلومات الفاتورة الأساسية
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('التاريخ: ${_formatDate(inv.invoiceDate)}', style: const TextStyle(fontSize: 14))),
                            Expanded(child: Text('نوع الدفع: ${inv.paymentType}', style: const TextStyle(fontSize: 14))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: Text('الإجمالي: ${_nf.format(inv.totalAmount)} د.ع', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green))),
                            if (inv.amountPaid > 0)
                              Expanded(child: Text('المدفوع: ${_nf.format(inv.amountPaid)} د.ع', style: const TextStyle(fontSize: 14, color: Colors.blue))),
                          ],
                        ),
                        if (_invoiceBalances[inv.id ?? -1] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'الرصيد: ${_nf.format(_invoiceBalances[inv.id]!['before']!)} → ${_nf.format(_invoiceBalances[inv.id]!['after']!)} د.ع',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // أصناف الفاتورة
                const Text('أصناف الفاتورة:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Text('لا توجد أصناف', style: TextStyle(color: Colors.grey))
                else
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
                          child: Row(
                            children: const [
                              Expanded(flex: 3, child: Text('المنتج', style: TextStyle(fontWeight: FontWeight.bold))),
                              Expanded(child: Text('الكمية', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                              Expanded(child: Text('السعر', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                              Expanded(child: Text('الإجمالي', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                            ],
                          ),
                        ),
                        // Items
                        ...items.map((item) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text(item.productName ?? 'غير معروف')),
                              Expanded(child: Text('${_nf.format(item.quantity)}', textAlign: TextAlign.center)),
                              Expanded(child: Text('${_nf.format(item.unitPrice)}', textAlign: TextAlign.center)),
                              Expanded(child: Text('${_nf.format(item.totalPrice)}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                
                // المرفقات
                const Text('المرفقات:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (atts.isEmpty)
                  const Text('لا يوجد مرفقات', style: TextStyle(color: Colors.grey))
                else
                  Column(
                    children: atts.map((a) => Card(
                      child: ListTile(
                        leading: Icon(a.fileType == 'pdf' ? Icons.picture_as_pdf : Icons.image, color: Colors.red),
                        title: Text(a.filePath.split('/').last),
                        subtitle: Text(a.filePath, style: const TextStyle(fontSize: 10)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.folder_open, color: Colors.blue),
                              tooltip: 'فتح المجلد',
                              onPressed: () => _openFileLocation(a.filePath),
                            ),
                            IconButton(
                              icon: const Icon(Icons.open_in_new, color: Colors.green),
                              tooltip: 'فتح الملف',
                              onPressed: () => _openAttachment(a),
                            ),
                          ],
                        ),
                      ),
                    )).toList(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  /// تعديل الفاتورة
  void _editInvoice(SupplierInvoice inv) {
    // TODO: Implement invoice editing
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الفاتورة'),
        content: const Text('سيتم فتح شاشة تعديل الفاتورة'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: Navigate to edit screen
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('جاري فتح شاشة التعديل...')),
              );
            },
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
  }

  /// فتح موقع الملف
  Future<void> _openFileLocation(String filePath) async {
    try {
      final uri = Uri.file(filePath);
      await launchUrl(uri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لا يمكن فتح المجلد: $e')),
        );
      }
    }
  }

  /// تنسيق التاريخ
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
    final geminiApiKey4 = dotenv.env['GEMINI_API_KEY_4'] ?? '';
    final openRouterApiKey = dotenv.env['OPENROUTER_API_KEY'] ?? '';
    final groqApiKey = dotenv.env['GROQ_API_KEY'] ?? '';
    final cloudflareApiToken = dotenv.env['CLOUDFLARE_API_TOKEN'] ?? '';
    final cloudflareAccountId = dotenv.env['CLOUDFLARE_ACCOUNT_ID'] ?? '';
    final googleVisionApiKey = dotenv.env['GOOGLE_VISION_API_KEY'] ?? '';
    final ocrSpaceApiKey = dotenv.env['OCR_SPACE_API_KEY'] ?? '';
    final glmApiKey = dotenv.env['GLM_API_KEY'] ?? '';
    final mistralApiKey = dotenv.env['MISTRAL_API_KEY'] ?? '';  // ✅ Mistral Pixtral
    
    if (geminiApiKey.isEmpty && groqApiKey.isEmpty && cloudflareApiToken.isEmpty && openRouterApiKey.isEmpty && glmApiKey.isEmpty && mistralApiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لم يتم العثور على مفتاح API')),
      );
      return;
    }
    
    print('🟢 تم شحن المفاتيح بنجاح ✅');
    
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
          geminiApiKey4: geminiApiKey4.isNotEmpty ? geminiApiKey4 : null,
          openRouterApiKey: openRouterApiKey.isNotEmpty ? openRouterApiKey : null,
          groqApiKey: groqApiKey.isNotEmpty ? groqApiKey : null,
          cloudflareApiToken: cloudflareApiToken.isNotEmpty ? cloudflareApiToken : null,
          cloudflareAccountId: cloudflareAccountId.isNotEmpty ? cloudflareAccountId : null,
          ocrSpaceApiKey: ocrSpaceApiKey.isNotEmpty ? ocrSpaceApiKey : null,
          glmApiKey: glmApiKey.isNotEmpty ? glmApiKey : null,
          mistralApiKey: mistralApiKey.isNotEmpty ? mistralApiKey : null,  // ✅ Mistral Pixtral
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


