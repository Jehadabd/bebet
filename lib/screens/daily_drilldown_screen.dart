// screens/daily_drilldown_screen.dart
// شاشة تفاصيل يوم محدد - تُجلب البيانات لحظياً
import 'package:flutter/material.dart';
import '../services/reports_service.dart';
import 'package:intl/intl.dart';
import 'transactions_list_dialog.dart';

class DailyDrillDownScreen extends StatefulWidget {
  final DateTime date;
  const DailyDrillDownScreen({super.key, required this.date});

  @override
  State<DailyDrillDownScreen> createState() => _DailyDrillDownScreenState();
}

class _DailyDrillDownScreenState extends State<DailyDrillDownScreen> {
  final ReportsService _svc = ReportsService();
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _topProducts = [];
  List<Map<String, dynamic>> _topCustomers = [];
  bool _isLoading = true;

  final _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  late final DateTime _start;
  late final DateTime _end;

  @override
  void initState() {
    super.initState();
    _start = DateTime(widget.date.year, widget.date.month, widget.date.day);
    _end   = DateTime(widget.date.year, widget.date.month, widget.date.day, 23, 59, 59);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final summary  = await _svc.getPeriodSummary(startDate: _start, endDate: _end);
      final products = await _svc.getTopProductsInPeriod(startDate: _start, endDate: _end, limit: 10);
      final customers= await _svc.getTopCustomersInPeriod(startDate: _start, endDate: _end, limit: 10);
      setState(() {
        _summary  = summary;
        _topProducts  = products;
        _topCustomers = customers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  String _dayName(DateTime d) {
    const days = ['الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];
    return days[d.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final title = '${_dayName(widget.date)} ${widget.date.day}/${widget.date.month}/${widget.date.year}';
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF6F00), Color(0xFFFF9800)],
              begin: Alignment.topRight, end: Alignment.bottomLeft,
            ),
          ),
        ),
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF9800)))
          : _summary == null
              ? const Center(child: Text('لا توجد بيانات لهذا اليوم'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummary(),
                        const SizedBox(height: 20),
                        if (_topProducts.isNotEmpty) ...[
                          _sectionTitle('أفضل المنتجات'),
                          const SizedBox(height: 10),
                          _buildProductList(),
                          const SizedBox(height: 20),
                        ],
                        if (_topCustomers.isNotEmpty) ...[
                          _sectionTitle('أفضل العملاء'),
                          const SizedBox(height: 10),
                          _buildCustomerList(),
                          const SizedBox(height: 20),
                        ],
                        if (_topProducts.isEmpty && _topCustomers.isEmpty)
                          Center(
                            child: Column(
                              children: [
                                const SizedBox(height: 40),
                                Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[300]),
                                const SizedBox(height: 12),
                                Text('لا توجد فواتير في هذا اليوم', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSummary() {
    final totalSales  = (_summary!['totalSales'] as num?)?.toDouble() ?? 0;
    final netProfit   = (_summary!['netProfit'] as num?)?.toDouble() ?? 0;
    final invoiceCount= (_summary!['invoiceCount'] as num?)?.toInt() ?? 0;
    final cashSales   = (_summary!['cashSales'] as num?)?.toDouble() ?? 0;
    final creditSales = (_summary!['creditSales'] as num?)?.toDouble() ?? 0;

    return Column(
      children: [
        Row(children: [
          Expanded(child: _statCard('إجمالي المبيعات', '${_fmt(totalSales)} د.ع', Icons.shopping_cart, const Color(0xFF2196F3))),
          const SizedBox(width: 12),
          Expanded(child: _statCard('صافي الربح', '${_fmt(netProfit)} د.ع', Icons.trending_up, const Color(0xFF4CAF50))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _statCard('عدد الفواتير', '$invoiceCount فاتورة', Icons.receipt_long, const Color(0xFF607D8B))),
          const SizedBox(width: 12),
          Expanded(child: _statCard('نقداً', '${_fmt(cashSales)} د.ع', Icons.payments, Colors.green[700]!)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _buildClickableStatCard('إضافة دين (يدوي)', '${_fmt(_summary!['totalManualDebt'] ?? 0)} د.ع', Icons.add_circle, const Color(0xFFFF5722), _showDebtAdditions)),
          const SizedBox(width: 12),
          Expanded(child: _buildClickableStatCard('تسديد دين (يدوي)', '${_fmt(_summary!['totalManualPayment'] ?? 0)} د.ع', Icons.remove_circle, const Color(0xFF4CAF50), _showDebtPayments)),
        ]),
        const SizedBox(height: 12),
        _buildClickableStatCard('تسديد دين (راجع)', '${_fmt(_summary!['totalManualPaymentReturn'] ?? 0)} د.ع', Icons.assignment_return, const Color(0xFFE91E63), _showDebtPaymentReturns),
      ],
    );
  }

  Widget _buildClickableStatCard(String title, String value, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0,2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
            Icon(Icons.touch_app, color: color.withOpacity(0.4), size: 14),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0,2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
        ]),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  Widget _sectionTitle(String t) => Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)));

  Widget _buildProductList() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.2))),
      child: ListView.separated(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: _topProducts.length,
        separatorBuilder: (_,__) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = _topProducts[i];
          return ListTile(
            leading: CircleAvatar(backgroundColor: const Color(0xFF2196F3).withOpacity(0.1),
              child: Text('${i+1}', style: const TextStyle(color: Color(0xFF2196F3), fontWeight: FontWeight.bold))),
            title: Text(p['product_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('الكمية: ${_fmt(p['total_quantity'] ?? 0)}'),
            trailing: Text('${_fmt(p['total_sales'] ?? 0)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2196F3))),
          );
        },
      ),
    );
  }

  Widget _buildCustomerList() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.2))),
      child: ListView.separated(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: _topCustomers.length,
        separatorBuilder: (_,__) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final c = _topCustomers[i];
          return ListTile(
            leading: CircleAvatar(backgroundColor: const Color(0xFF4CAF50).withOpacity(0.1),
              child: Text('${i+1}', style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold))),
            title: Text(c['customer_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text('${c['invoice_count'] ?? 0} فاتورة'),
            trailing: Text('${_fmt(c['total_purchases'] ?? 0)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4CAF50))),
          );
        },
      ),
    );
  }

  void _showDebtAdditions() {
    TransactionsListDialog.showDebtAdditions(
      context: context,
      startDate: _start,
      endDate: _end,
      periodTitle: DateFormat('yyyy-MM-dd').format(widget.date),
    );
  }

  void _showDebtPayments() {
    TransactionsListDialog.showDebtPayments(
      context: context,
      startDate: _start,
      endDate: _end,
      periodTitle: DateFormat('yyyy-MM-dd').format(widget.date),
      excludeReturns: true,
    );
  }

  void _showDebtPaymentReturns() {
    TransactionsListDialog.showDebtPayments(
      context: context,
      startDate: _start,
      endDate: _end,
      periodTitle: DateFormat('yyyy-MM-dd').format(widget.date),
      onlyReturns: true,
    );
  }
}
