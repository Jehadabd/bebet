// screens/week_drilldown_screen.dart
// شاشة تفاصيل أسبوع محدد — تُجلب البيانات لحظياً
import 'package:flutter/material.dart';
import '../services/reports_service.dart';
import 'daily_drilldown_screen.dart';
import 'package:intl/intl.dart';
import 'transactions_list_dialog.dart';

class WeekDrillDownScreen extends StatefulWidget {
  final DateTime weekStart;
  final DateTime weekEnd;
  final String weekLabel; // مثل "الأسبوع الأول"

  const WeekDrillDownScreen({
    super.key,
    required this.weekStart,
    required this.weekEnd,
    required this.weekLabel,
  });

  @override
  State<WeekDrillDownScreen> createState() => _WeekDrillDownScreenState();
}

class _WeekDrillDownScreenState extends State<WeekDrillDownScreen> {
  final ReportsService _svc = ReportsService();
  Map<String, dynamic>? _summary;
  final Map<int, Map<String, dynamic>> _daySummaries = {};
  bool _isLoading = true;

  final _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _daySummaries.clear(); });
    try {
      // ملخص الأسبوع كاملاً
      final summary = await _svc.getPeriodSummary(
        startDate: widget.weekStart,
        endDate: widget.weekEnd,
      );

      // ملخص كل يوم على حدة
      final days = <int, Map<String, dynamic>>{};
      DateTime current = widget.weekStart;
      while (!current.isAfter(widget.weekEnd)) {
        final dayStart = DateTime(current.year, current.month, current.day);
        final dayEnd   = DateTime(current.year, current.month, current.day, 23, 59, 59);
        final daySummary = await _svc.getPeriodSummary(startDate: dayStart, endDate: dayEnd);
        days[current.day] = daySummary;
        current = current.add(const Duration(days: 1));
      }

      setState(() {
        _summary = summary;
        _daySummaries.addAll(days);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  String _dayName(int weekday) {
    const days = ['الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت','الأحد'];
    return days[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d/M/yyyy');
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(widget.weekLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF7B1FA2), Color(0xFF9C27B0)],
              begin: Alignment.topRight, end: Alignment.bottomLeft,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF9C27B0)))
          : Column(
              children: [
                // شريط الفترة
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  color: const Color(0xFF9C27B0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.date_range, color: Colors.white70, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${df.format(widget.weekStart)} ← ${df.format(widget.weekEnd)}',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ملخص الأسبوع
                          if (_summary != null) ...[
                            _sectionTitle('ملخص الأسبوع'),
                            const SizedBox(height: 10),
                            _buildWeekSummary(),
                            const SizedBox(height: 20),
                          ],

                          _sectionTitle('أيام الأسبوع'),
                          const SizedBox(height: 10),
                          _buildDaysList(),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildWeekSummary() {
    final totalSales  = (_summary!['totalSales'] as num?)?.toDouble() ?? 0;
    final netProfit   = (_summary!['netProfit'] as num?)?.toDouble() ?? 0;
    final invoiceCount= (_summary!['invoiceCount'] as num?)?.toInt() ?? 0;

    return Column(
      children: [
        Row(children: [
          Expanded(child: _miniStat('المبيعات', '${_fmt(totalSales)} د.ع', const Color(0xFF2196F3))),
          const SizedBox(width: 10),
          Expanded(child: _miniStat('الربح', '${_fmt(netProfit)} د.ع', const Color(0xFF4CAF50))),
          const SizedBox(width: 10),
          Expanded(child: _miniStat('الفواتير', '$invoiceCount', const Color(0xFF9C27B0))),
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5, offset: const Offset(0,2))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 18)),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
            Icon(Icons.touch_app, color: color.withOpacity(0.4), size: 14),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }

  Widget _miniStat(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 5, offset: const Offset(0,2))],
      ),
      child: Column(children: [
        Text(title, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _buildDaysList() {
    final List<Widget> dayCards = [];
    DateTime current = widget.weekStart;
    while (!current.isAfter(widget.weekEnd)) {
      dayCards.add(_buildDayCard(current));
      if (current.day != widget.weekEnd.day) dayCards.add(const SizedBox(height: 8));
      current = current.add(const Duration(days: 1));
    }
    return Column(children: dayCards);
  }

  Widget _buildDayCard(DateTime day) {
    final dayData = _daySummaries[day.day];
    final sales   = (dayData?['totalSales'] as num?)?.toDouble() ?? 0;
    final profit  = (dayData?['netProfit'] as num?)?.toDouble() ?? 0;
    final invoices= (dayData?['invoiceCount'] as num?)?.toInt() ?? 0;
    final isEmpty = invoices == 0;

    return Card(
      elevation: isEmpty ? 0 : 3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isEmpty ? Colors.grey.withOpacity(0.2) : const Color(0xFF9C27B0).withOpacity(0.3),
        ),
      ),
      child: InkWell(
        onTap: isEmpty ? null : () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DailyDrillDownScreen(date: day)),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // أيقونة اليوم
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: isEmpty
                      ? Colors.grey.withOpacity(0.08)
                      : const Color(0xFF9C27B0).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold,
                      color: isEmpty ? Colors.grey[400] : const Color(0xFF9C27B0),
                    ),
                  ),
                  Text(
                    '${day.month}',
                    style: TextStyle(fontSize: 10, color: isEmpty ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ]),
              ),
              const SizedBox(width: 14),
              // اسم اليوم
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _dayName(day.weekday),
                    style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold,
                      color: isEmpty ? Colors.grey[400] : const Color(0xFF2C3E50),
                    ),
                  ),
                  if (isEmpty)
                    Text('لا توجد فواتير', style: TextStyle(fontSize: 12, color: Colors.grey[400]))
                  else
                    Text('$invoices فاتورة', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ]),
              ),
              // أرقام المبيعات والربح
              if (!isEmpty) ...[
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${_fmt(sales)} د.ع',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2196F3))),
                  Text('ربح: ${_fmt(profit)} د.ع',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF4CAF50))),
                ]),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Color(0xFF9C27B0)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)));

  void _showDebtAdditions() {
    TransactionsListDialog.showDebtAdditions(
      context: context,
      startDate: widget.weekStart,
      endDate: widget.weekEnd,
      periodTitle: widget.weekLabel,
    );
  }

  void _showDebtPayments() {
    TransactionsListDialog.showDebtPayments(
      context: context,
      startDate: widget.weekStart,
      endDate: widget.weekEnd,
      periodTitle: widget.weekLabel,
      excludeReturns: true,
    );
  }

  void _showDebtPaymentReturns() {
    TransactionsListDialog.showDebtPayments(
      context: context,
      startDate: widget.weekStart,
      endDate: widget.weekEnd,
      periodTitle: widget.weekLabel,
      onlyReturns: true,
    );
  }
}
