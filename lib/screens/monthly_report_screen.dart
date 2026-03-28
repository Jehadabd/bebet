// screens/monthly_report_screen.dart
// شاشة التقرير الشهري المفصل - مدمجة مع الجرد
import 'package:flutter/material.dart';
import '../services/reports_service.dart';
import '../services/database_service.dart';
import '../models/monthly_overview.dart';
import 'week_drilldown_screen.dart';
import 'package:intl/intl.dart';
import 'transactions_list_dialog.dart';

class MonthlyReportScreen extends StatefulWidget {
  final int? initialYear;
  final int? initialMonth;
  const MonthlyReportScreen({super.key, this.initialYear, this.initialMonth});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen>
    with SingleTickerProviderStateMixin {
  final ReportsService _reportsService = ReportsService();
  final DatabaseService _db = DatabaseService();
  late TabController _tabController;
  Map<String, dynamic>? _reportData;
  bool _isLoading = true;
  late int _selectedYear;
  late int _selectedMonth;
  
  // بيانات الجرد الشهري
  Map<String, MonthlyOverview> _monthlySummaries = {};
  MonthlyOverview? _currentMonth;
  MonthlyOverview? _lastMonth;
  List<Map<String, dynamic>> _topCustomersBySales = [];
  List<Map<String, dynamic>> _topCustomersByProfit = [];
  List<Map<String, dynamic>> _topProductsBySales = [];
  List<Map<String, dynamic>> _topProductsByProfit = [];
  
  final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);
  String get _selectedMonthKey => '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    final now = DateTime.now();
    _selectedYear  = widget.initialYear  ?? now.year;
    _selectedMonth = widget.initialMonth ?? now.month;
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      // تحميل بيانات التقرير الشهري
      final data = await _reportsService.getMonthlyDetailedReport(
        year: _selectedYear, month: _selectedMonth,
      );
      // تحميل بيانات الجرد
      final summaries = await _db.getMonthlySalesSummary();
      final now = DateTime.now();
      final currentKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final lastDate = DateTime(now.year, now.month - 1, 1);
      final lastKey = '${lastDate.year}-${lastDate.month.toString().padLeft(2, '0')}';
      final topCustSales = await _db.getTopCustomersBySales(limit: 10, year: _selectedYear, month: _selectedMonth);
      final topCustProfit = await _db.getTopCustomersByProfit(limit: 10, year: _selectedYear, month: _selectedMonth);
      final topProdSales = await _db.getTopProductsBySales(limit: 10, year: _selectedYear, month: _selectedMonth);
      final topProdProfit = await _db.getTopProductsByProfit(limit: 10, year: _selectedYear, month: _selectedMonth);

      setState(() {
        _reportData = data;
        _monthlySummaries = summaries;
        _currentMonth = summaries[currentKey];
        _lastMonth = summaries[lastKey];
        _topCustomersBySales = topCustSales;
        _topCustomersByProfit = topCustProfit;
        _topProductsBySales = topProdSales;
        _topProductsByProfit = topProdProfit;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _getMonthName(int month) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('التقرير الشهري '),
        backgroundColor: const Color(0xFF673AB7),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAllData),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'التقرير', icon: Icon(Icons.assessment, size: 20)),
            Tab(text: 'الجرد الشهري', icon: Icon(Icons.calendar_month, size: 20)),
            Tab(text: 'المقارنة', icon: Icon(Icons.compare_arrows, size: 20)),
            Tab(text: 'عملاء (شراء)', icon: Icon(Icons.people, size: 20)),
            Tab(text: 'عملاء (ربح)', icon: Icon(Icons.emoji_events, size: 20)),
            Tab(text: 'المنتجات', icon: Icon(Icons.inventory_2, size: 20)),
          ],
        ),
      ),
      body: Column(
        children: [
          // اختيار الشهر
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF673AB7).withOpacity(0.9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                  onPressed: () {
                    setState(() { if (_selectedMonth == 1) { _selectedMonth = 12; _selectedYear--; } else { _selectedMonth--; } });
                    _loadAllData();
                  },
                ),
                GestureDetector(
                  onTap: _showMonthPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                    child: Text('${_getMonthName(_selectedMonth)} $_selectedYear', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                  onPressed: () {
                    final now = DateTime.now();
                    if (_selectedYear < now.year || (_selectedYear == now.year && _selectedMonth < now.month)) {
                      setState(() { if (_selectedMonth == 12) { _selectedMonth = 1; _selectedYear++; } else { _selectedMonth++; } });
                      _loadAllData();
                    }
                  },
                ),
              ],
            ),
          ),
          // المحتوى
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF673AB7)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildReportTab(),
                      _buildInventoryTab(),
                      _buildComparisonTab(),
                      _buildTopCustomersBySalesTab(),
                      _buildTopCustomersByProfitTab(),
                      _buildTopProductsTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ==================== تبويب التقرير الشهري ====================
  Widget _buildReportTab() {
    if (_reportData == null) return const Center(child: Text('لا توجد بيانات'));
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('ملخص المبيعات'), const SizedBox(height: 12),
            _buildSummaryCards(), const SizedBox(height: 20),
            _buildSectionTitle('أسابيع الشهر'), const SizedBox(height: 12),
            _buildWeeksSection(), const SizedBox(height: 20),
            _buildSectionTitle('تحليل الاتجاه'), const SizedBox(height: 12),
            _buildTrendCard(), const SizedBox(height: 20),
            _buildSectionTitle('مقارنة مع الشهر الماضي'), const SizedBox(height: 12),
            _buildComparisonCard(), const SizedBox(height: 20),
            _buildSectionTitle('أفضل 10 منتجات'), const SizedBox(height: 12),
            _buildTopProductsList(), const SizedBox(height: 20),
            _buildSectionTitle('أفضل 10 عملاء'), const SizedBox(height: 12),
            _buildTopCustomersList(), const SizedBox(height: 20),
            _buildSectionTitle('العملاء الجدد'), const SizedBox(height: 12),
            _buildNewCustomersCard(), const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ─── أسابيع الشهر ────────────────────────────────────────
  Widget _buildWeeksSection() {
    // تقسيم الشهر إلى 4 أسابيع
    final daysInMonth = DateTime(_selectedYear, _selectedMonth + 1, 0).day;
    final weeks = [
      {
        'label': 'الأسبوع الأول',
        'start': DateTime(_selectedYear, _selectedMonth, 1),
        'end': DateTime(_selectedYear, _selectedMonth, 7, 23, 59, 59),
        'display': '1 - 7',
      },
      {
        'label': 'الأسبوع الثاني',
        'start': DateTime(_selectedYear, _selectedMonth, 8),
        'end': DateTime(_selectedYear, _selectedMonth, 14, 23, 59, 59),
        'display': '8 - 14',
      },
      {
        'label': 'الأسبوع الثالث',
        'start': DateTime(_selectedYear, _selectedMonth, 15),
        'end': DateTime(_selectedYear, _selectedMonth, 21, 23, 59, 59),
        'display': '15 - 21',
      },
      {
        'label': 'الأسبوع الرابع',
        'start': DateTime(_selectedYear, _selectedMonth, 22),
        'end': DateTime(_selectedYear, _selectedMonth, daysInMonth, 23, 59, 59),
        'display': '22 - $daysInMonth',
      },
    ];

    return Column(
      children: weeks.asMap().entries.map((entry) {
        final w = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildWeekCard(
            label: w['label'] as String,
            display: w['display'] as String,
            weekStart: w['start'] as DateTime,
            weekEnd: w['end'] as DateTime,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWeekCard({
    required String label,
    required String display,
    required DateTime weekStart,
    required DateTime weekEnd,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: const Color(0xFF673AB7).withOpacity(0.25)),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => WeekDrillDownScreen(
              weekStart: weekStart,
              weekEnd: weekEnd,
              weekLabel: label,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF673AB7).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.calendar_view_week_rounded, color: Color(0xFF673AB7), size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
                    Text('أيام $display', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF673AB7)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2C3E50),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final summary = _reportData!['summary'] as Map<String, dynamic>;
    final profitPercent = (_reportData!['profitPercent'] as num?)?.toDouble() ?? 0.0;
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'إجمالي المبيعات',
                value: '${_fmt(summary['totalSales'])} د.ع',
                icon: Icons.shopping_cart,
                color: const Color(0xFF2196F3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'صافي الربح',
                value: '${_fmt(summary['netProfit'])} د.ع',
                icon: Icons.trending_up,
                color: const Color(0xFF4CAF50),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'نسبة الربح',
                value: '${profitPercent.toStringAsFixed(1)}%',
                icon: Icons.percent,
                color: const Color(0xFF9C27B0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'عدد الفواتير',
                value: '${summary['invoiceCount']}',
                icon: Icons.receipt_long,
                color: const Color(0xFF607D8B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                title: 'البيع بالنقد',
                value: '${_fmt(summary['cashSales'])} د.ع',
                icon: Icons.payments,
                color: const Color(0xFF4CAF50),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                title: 'البيع بالدين',
                value: '${_fmt(summary['creditSales'])} د.ع',
                icon: Icons.credit_card,
                color: const Color(0xFFFF9800),
              ),
            ),
          ],
        ),
        // بطاقة إجمالي الراجع
        if ((summary['totalReturns'] as num?)?.toDouble() != null && 
            (summary['totalReturns'] as num).toDouble() > 0) ...[
          const SizedBox(height: 12),
          _buildStatCard(
            title: 'إجمالي الراجع',
            value: '${_fmt(summary['totalReturns'])} د.ع',
            icon: Icons.keyboard_return,
            color: const Color(0xFF9C27B0),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildClickableStatCard(
                title: 'إضافة دين (يدوي)',
                value: '${_fmt(summary['totalManualDebt'])} د.ع',
                subtitle: '${summary['manualDebtCount']} معاملة',
                icon: Icons.add_circle,
                color: const Color(0xFFFF5722),
                onTap: () => _showDebtAdditions(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildClickableStatCard(
                title: 'تسديد دين (يدوي)',
                value: '${_fmt(summary['totalManualPayment'])} د.ع',
                subtitle: '${summary['manualPaymentCount']} معاملة',
                icon: Icons.remove_circle,
                color: const Color(0xFF4CAF50),
                onTap: () => _showDebtPayments(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildClickableStatCard(
          title: 'تسديد دين (راجع)',
          value: '${_fmt(summary['totalManualPaymentReturn'] ?? 0)} د.ع',
          subtitle: '${summary['manualPaymentReturnCount'] ?? 0} معاملة',
          icon: Icons.assignment_return,
          color: const Color(0xFFE91E63),
          onTap: () => _showDebtPaymentReturns(),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildClickableStatCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(Icons.touch_app, color: color.withOpacity(0.5), size: 16),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(اضغط للتفاصيل)',
                    style: TextStyle(
                      fontSize: 10,
                      color: color.withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrendCard() {
    final trend = _reportData!['trend'] as Map<String, dynamic>;
    final trendArabic = trend['trendArabic'] as String? ?? 'غير محدد';
    final avgDailySales = (trend['averageDailySales'] as num?)?.toDouble() ?? 0.0;
    final changePercent = (trend['changePercent'] as num?)?.toDouble() ?? 0.0;
    
    Color trendColor;
    IconData trendIcon;
    if (trend['trend'] == 'increasing') {
      trendColor = Colors.green;
      trendIcon = Icons.trending_up;
    } else if (trend['trend'] == 'decreasing') {
      trendColor = Colors.red;
      trendIcon = Icons.trending_down;
    } else {
      trendColor = Colors.orange;
      trendIcon = Icons.trending_flat;
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: trendColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: trendColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(trendIcon, color: trendColor, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الاتجاه: $trendArabic',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: trendColor),
                ),
                const SizedBox(height: 4),
                Text(
                  'متوسط المبيعات اليومية: ${_fmt(avgDailySales)} د.ع',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard() {
    final comparison = _reportData!['comparison'] as Map<String, dynamic>;
    final changes = comparison['changes'] as Map<String, dynamic>;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          _buildComparisonRow('المبيعات', changes['salesChange'] ?? 0.0),
          const Divider(),
          _buildComparisonRow('الأرباح', changes['profitChange'] ?? 0.0),
          const Divider(),
          _buildComparisonRow('عدد الفواتير', changes['invoiceCountChange'] ?? 0.0),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String title, double changePercent) {
    final isPositive = changePercent >= 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isPositive ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: isPositive ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  '${changePercent.abs().toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductsList() {
    final topProducts = _reportData!['topProducts'] as List<Map<String, dynamic>>;
    
    if (topProducts.isEmpty) {
      return const Center(child: Text('لا توجد بيانات'));
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.3)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: topProducts.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final product = topProducts[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF2196F3).withOpacity(0.1),
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Color(0xFF2196F3), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              product['product_name']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text('الكمية: ${_fmt(product['total_quantity'] ?? 0)}'),
            trailing: Text(
              '${_fmt(product['total_sales'] ?? 0)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2196F3)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopCustomersList() {
    final topCustomers = _reportData!['topCustomers'] as List<Map<String, dynamic>>;
    
    if (topCustomers.isEmpty) {
      return const Center(child: Text('لا توجد بيانات'));
    }
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.3)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: topCustomers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final customer = topCustomers[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF4CAF50).withOpacity(0.1),
              child: Text(
                '${index + 1}',
                style: const TextStyle(color: Color(0xFF4CAF50), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              customer['customer_name']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text('${customer['invoice_count'] ?? 0} فاتورة'),
            trailing: Text(
              '${_fmt(customer['total_purchases'] ?? 0)} د.ع',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewCustomersCard() {
    final newCustomersCount = _reportData!['newCustomersCount'] as int? ?? 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00BCD4).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF00BCD4).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_add, color: Color(0xFF00BCD4), size: 32),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'العملاء الجدد هذا الشهر',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              Text(
                '$newCustomersCount عميل',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00BCD4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMonthPicker() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر الشهر'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 2,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              final isSelected = month == _selectedMonth;
              return InkWell(
                onTap: () {
                  setState(() => _selectedMonth = month);
                  Navigator.pop(context);
                  _loadAllData();
                },
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF673AB7) : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _getMonthName(month),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // عرض معاملات إضافة الدين للشهر
  void _showDebtAdditions() {
    final startOfMonth = DateTime(_selectedYear, _selectedMonth, 1);
    final endOfMonth = DateTime(_selectedYear, _selectedMonth + 1, 0, 23, 59, 59);
    
    TransactionsListDialog.showDebtAdditions(
      context: context,
      startDate: startOfMonth,
      endDate: endOfMonth,
      periodTitle: 'الشهر (${_selectedMonth}/$_selectedYear)',
    );
  }

  // عرض معاملات تسديد الدين للشهر
  void _showDebtPayments() {
    final startOfMonth = DateTime(_selectedYear, _selectedMonth, 1);
    final endOfMonth = DateTime(_selectedYear, _selectedMonth + 1, 0, 23, 59, 59);
    
    TransactionsListDialog.showDebtPayments(
      context: context,
      startDate: startOfMonth,
      endDate: endOfMonth,
      periodTitle: 'الشهر (${_selectedMonth}/$_selectedYear)',
      excludeReturns: true,
    );
  }

  // عرض معاملات تسديد الدين الراجع للشهر
  void _showDebtPaymentReturns() {
    final startOfMonth = DateTime(_selectedYear, _selectedMonth, 1);
    final endOfMonth = DateTime(_selectedYear, _selectedMonth + 1, 0, 23, 59, 59);
    
    TransactionsListDialog.showDebtPayments(
      context: context,
      startDate: startOfMonth,
      endDate: endOfMonth,
      periodTitle: 'الشهر (${_selectedMonth}/$_selectedYear)',
      onlyReturns: true,
    );
  }

  // ==================== تبويب الجرد الشهري ====================
  Widget _buildInventoryTab() {
    final sortedKeys = _monthlySummaries.keys.toList()..sort((a, b) => b.compareTo(a));
    final now = DateTime.now();
    if (sortedKeys.isEmpty) return const Center(child: Text('لا توجد بيانات مبيعات متاحة.'));
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sortedKeys.length,
        itemBuilder: (context, index) {
          final key = sortedKeys[index];
          final s = _monthlySummaries[key]!;
          final d = DateTime.parse('${key.split('-')[0]}-${key.split('-')[1].padLeft(2, '0')}-01');
          final isCurrent = d.year == now.year && d.month == now.month;
          return _buildMonthCard(key, s, isCurrent);
        },
      ),
    );
  }

  Widget _buildMonthCard(String monthYear, MonthlyOverview s, bool isCurrent) {
    final invoiceCreditSales = s.creditSales - s.totalManualDebt;
    final invoiceCredit = invoiceCreditSales > 0 ? invoiceCreditSales : 0.0;
    final totalInvSales = s.cashSales + invoiceCredit;
    final cashPct = totalInvSales > 0 ? (s.cashSales / totalInvSales * 100) : 0.0;
    final creditPct = totalInvSales > 0 ? (invoiceCredit / totalInvSales * 100) : 0.0;
    final invProfitPct = s.totalSales > 0 ? (s.netProfit / s.totalSales * 100) : 0.0;
    final manualDebt = s.totalManualDebt;
    final manualProfit = s.manualDebtProfit;
    final totalSalesAll = s.totalSales + manualDebt;
    final totalProfitAll = s.netProfit + manualProfit;
    final totalProfitPctAll = totalSalesAll > 0 ? (totalProfitAll / totalSalesAll * 100) : 0.0;
    final totalDebtAll = invoiceCredit + manualDebt;
    final c = isCurrent ? const Color(0xFF3F51B5) : Colors.grey;
    return Card(
      elevation: 4, margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.withOpacity(0.4), width: 2)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: LinearGradient(colors: [c.withOpacity(0.12), c.withOpacity(0.05)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: c.withOpacity(0.15), shape: BoxShape.circle), child: Icon(Icons.calendar_month, color: c, size: 28)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(monthYear, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c)),
              if (isCurrent) Text('الشهر الحالي', style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500)),
            ]),
          ]),
          const SizedBox(height: 16),
          _invSection('🧾 الفواتير', const Color(0xFF2196F3)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _invItem(Icons.shopping_cart, 'مبيعات الفواتير', '${_fmt(s.totalSales)} د.ع', null, const Color(0xFF2196F3))),
            const SizedBox(width: 8),
            Expanded(child: _invItem(Icons.trending_up, 'أرباح الفواتير', '${_fmt(s.netProfit)} د.ع', '${invProfitPct.toStringAsFixed(1)}%', const Color(0xFF4CAF50))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _invItem(Icons.money_off, 'تكلفة الفواتير', '${_fmt(s.totalCost)} د.ع', null, const Color(0xFFF44336))),
            const SizedBox(width: 8),
            Expanded(child: _invItem(Icons.receipt_long, 'عدد الفواتير', '${s.invoiceCount} فاتورة', null, const Color(0xFF607D8B))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _invItem(Icons.payments, 'نقد (فواتير)', '${_fmt(s.cashSales)} د.ع', '${cashPct.toStringAsFixed(1)}%', const Color(0xFF4CAF50))),
            const SizedBox(width: 8),
            Expanded(child: _invItem(Icons.credit_card, 'دين (فواتير)', '${_fmt(invoiceCredit)} د.ع', '${creditPct.toStringAsFixed(1)}%', const Color(0xFFFF9800))),
          ]),
          if (manualDebt > 0 || manualProfit > 0 || s.totalDebtPayments > 0 || s.totalManualPaymentReturn > 0) ...[
            const SizedBox(height: 16),
            _invSection('✋ المعاملات اليدوية', const Color(0xFFE91E63)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _invClickable(Icons.person_add, 'إضافة دين يدوية', '${_fmt(manualDebt)} د.ع', '${s.manualDebtCount} معاملة', const Color(0xFFE91E63), () => _showInvDebtAdditions(monthYear))),
              const SizedBox(width: 8),
              Expanded(child: _invItem(Icons.account_balance_wallet, 'ربح يدوي (15%)', '${_fmt(manualProfit)} د.ع', null, const Color(0xFF00BCD4))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _invClickable(Icons.remove_circle, 'تسديد دين (يدوي)', '${_fmt(s.totalDebtPayments)} د.ع', '${s.manualPaymentCount} معاملة', const Color(0xFF009688), () => _showInvDebtPayments(monthYear))),
              const SizedBox(width: 8),
              Expanded(child: _invClickable(Icons.assignment_return, 'تسديد دين (راجع)', '${_fmt(s.totalManualPaymentReturn)} د.ع', '${s.manualPaymentReturnCount} معاملة', const Color(0xFFE91E63), () => _showInvDebtPaymentReturns(monthYear))),
            ]),
          ],
          const SizedBox(height: 16),
          _invSection('📊 الإجماليات الشاملة', const Color(0xFF673AB7)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _invItem(Icons.shopping_bag, 'إجمالي المبيعات', '${_fmt(totalSalesAll)} د.ع', null, const Color(0xFF673AB7))),
            const SizedBox(width: 8),
            Expanded(child: _invItem(Icons.assessment, 'إجمالي الأرباح', '${_fmt(totalProfitAll)} د.ع', '${totalProfitPctAll.toStringAsFixed(1)}%', const Color(0xFF8BC34A))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _invItem(Icons.account_balance, 'إجمالي الدين', '${_fmt(totalDebtAll)} د.ع', null, const Color(0xFFFF5722))),
            const SizedBox(width: 8),
            Expanded(child: _invItem(Icons.check_circle, 'إجمالي التسديد', '${_fmt(s.totalDebtPayments)} د.ع', null, const Color(0xFF009688))),
          ]),
        ]),
      ),
    );
  }

  Widget _invSection(String title, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border(left: BorderSide(color: c, width: 4))),
    child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c)),
  );

  Widget _invItem(IconData icon, String title, String value, String? badge, Color c) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withOpacity(0.3), width: 1.5)),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: c, size: 24),
        if (badge != null) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: Text(badge, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c)))],
      ]),
      const SizedBox(height: 8),
      Text(title, style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c), textAlign: TextAlign.center),
    ]),
  );

  Widget _invClickable(IconData icon, String title, String value, String sub, Color c, VoidCallback onTap) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withOpacity(0.3), width: 1.5)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: c, size: 24), const SizedBox(width: 6), Icon(Icons.touch_app, color: c.withOpacity(0.5), size: 16)]),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: c), textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey[600]), textAlign: TextAlign.center),
      ]),
    ),
  );

  void _showInvDebtAdditions(String my) { final y = int.parse(my.split('-')[0]); final m = int.parse(my.split('-')[1]); TransactionsListDialog.showDebtAdditions(context: context, startDate: DateTime(y, m, 1), endDate: m == 12 ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1), periodTitle: my); }
  void _showInvDebtPayments(String my) { final y = int.parse(my.split('-')[0]); final m = int.parse(my.split('-')[1]); TransactionsListDialog.showDebtPayments(context: context, startDate: DateTime(y, m, 1), endDate: m == 12 ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1), periodTitle: my, excludeReturns: true); }
  void _showInvDebtPaymentReturns(String my) { final y = int.parse(my.split('-')[0]); final m = int.parse(my.split('-')[1]); TransactionsListDialog.showDebtPayments(context: context, startDate: DateTime(y, m, 1), endDate: m == 12 ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1), periodTitle: my, onlyReturns: true); }

  // ==================== تبويب المقارنة ====================
  Widget _buildComparisonTab() {
    if (_currentMonth == null && _lastMonth == null) return const Center(child: Text('لا توجد بيانات كافية للمقارنة'));
    final now = DateTime.now();
    final curName = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final lastDate = DateTime(now.year, now.month - 1, 1);
    final lastName = '${lastDate.year}-${lastDate.month.toString().padLeft(2, '0')}';
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8)]),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Column(children: [const Icon(Icons.calendar_today, color: Color(0xFF3F51B5), size: 30), const SizedBox(height: 8), Text(curName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const Text('الشهر الحالي', style: TextStyle(color: Colors.grey))]),
              const Icon(Icons.compare_arrows, size: 40, color: Color(0xFF3F51B5)),
              Column(children: [const Icon(Icons.history, color: Color(0xFF607D8B), size: 30), const SizedBox(height: 8), Text(lastName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const Text('الشهر الماضي', style: TextStyle(color: Colors.grey))]),
            ])),
          const SizedBox(height: 20),
          _invCompRow('إجمالي المبيعات', _currentMonth?.totalSales ?? 0, _lastMonth?.totalSales ?? 0, Icons.shopping_cart, const Color(0xFF2196F3)),
          _invCompRow('صافي الأرباح', _currentMonth?.netProfit ?? 0, _lastMonth?.netProfit ?? 0, Icons.trending_up, const Color(0xFF4CAF50)),
          _invCompRow('إجمالي التكلفة', _currentMonth?.totalCost ?? 0, _lastMonth?.totalCost ?? 0, Icons.money_off, const Color(0xFFF44336)),
          _invCompRow('عدد الفواتير', (_currentMonth?.invoiceCount ?? 0).toDouble(), (_lastMonth?.invoiceCount ?? 0).toDouble(), Icons.receipt_long, const Color(0xFF607D8B), isCount: true),
          _invCompRow('البيع بالنقد', _currentMonth?.cashSales ?? 0, _lastMonth?.cashSales ?? 0, Icons.payments, const Color(0xFF4CAF50)),
          _invCompRow('البيع بالدين', _currentMonth?.creditSales ?? 0, _lastMonth?.creditSales ?? 0, Icons.credit_card, const Color(0xFFFF9800)),
        ]),
      ),
    );
  }

  Widget _invCompRow(String title, double cur, double last, IconData icon, Color c, {bool isCount = false}) {
    final diff = cur - last; final pct = last > 0 ? ((diff / last) * 100) : (cur > 0 ? 100 : 0); final pos = diff >= 0;
    return Card(margin: const EdgeInsets.only(bottom: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: c, size: 24)), const SizedBox(width: 12), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)))]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(children: [Text(isCount ? cur.toInt().toString() : '${_fmt(cur)} د.ع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: c)), const Text('الحالي', style: TextStyle(fontSize: 12, color: Colors.grey))]),
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: (pos ? Colors.green : Colors.red).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(pos ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: pos ? Colors.green : Colors.red), const SizedBox(width: 4), Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, color: pos ? Colors.green : Colors.red))])),
          Column(children: [Text(isCount ? last.toInt().toString() : '${_fmt(last)} د.ع', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)), const Text('الماضي', style: TextStyle(fontSize: 12, color: Colors.grey))]),
        ]),
      ])));
  }

  // ==================== تبويب أفضل العملاء (شراء) ====================
  Widget _buildTopCustomersBySalesTab() {
    return RefreshIndicator(onRefresh: _loadAllData, child: ListView.builder(
      padding: const EdgeInsets.all(16), itemCount: _topCustomersBySales.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return Container(padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2196F3), Color(0xFF1976D2)]), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [const Icon(Icons.people, color: Colors.white, size: 30), const SizedBox(width: 12), Expanded(child: Text('أفضل 10 عملاء - الأكثر شراءً ($_selectedMonthKey)', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))]));
        if (_topCustomersBySales.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد بيانات لهذا الشهر')));
        final ci = i - 1; if (ci >= _topCustomersBySales.length) return const SizedBox();
        final c = _topCustomersBySales[ci];
        return _custRankCard(ci + 1, c['name'] ?? '', c['total_sales'] ?? 0, 'إجمالي المشتريات', const Color(0xFF2196F3));
      }));
  }

  // ==================== تبويب أفضل العملاء (ربح) ====================
  Widget _buildTopCustomersByProfitTab() {
    return RefreshIndicator(onRefresh: _loadAllData, child: ListView.builder(
      padding: const EdgeInsets.all(16), itemCount: _topCustomersByProfit.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return Container(padding: const EdgeInsets.all(16), margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF4CAF50), Color(0xFF388E3C)]), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [const Icon(Icons.emoji_events, color: Colors.white, size: 30), const SizedBox(width: 12), Expanded(child: Text('أفضل 10 عملاء - الأكثر ربحية ($_selectedMonthKey)', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))]));
        if (_topCustomersByProfit.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('لا توجد بيانات لهذا الشهر')));
        final ci = i - 1; if (ci >= _topCustomersByProfit.length) return const SizedBox();
        final c = _topCustomersByProfit[ci];
        return _custRankCard(ci + 1, c['name'] ?? '', c['total_profit'] ?? 0, 'صافي الربح', const Color(0xFF4CAF50));
      }));
  }

  Widget _custRankCard(int rank, String name, num value, String label, Color c) {
    Color rc; IconData ri;
    if (rank == 1) { rc = const Color(0xFFFFD700); ri = Icons.looks_one; }
    else if (rank == 2) { rc = const Color(0xFFC0C0C0); ri = Icons.looks_two; }
    else if (rank == 3) { rc = const Color(0xFFCD7F32); ri = Icons.looks_3; }
    else { rc = Colors.grey; ri = Icons.tag; }
    return Card(margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(width: 45, height: 45, decoration: BoxDecoration(color: rc.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: rc, width: 2)),
          child: Center(child: rank <= 3 ? Icon(ri, color: rc, size: 28) : Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: rc)))),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: Text('${_fmt(value)} د.ع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: c)),
      ));
  }

  // ==================== تبويب أفضل المنتجات ====================
  Widget _buildTopProductsTab() {
    return RefreshIndicator(onRefresh: _loadAllData, child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)]), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [const Icon(Icons.inventory_2, color: Colors.white, size: 30), const SizedBox(width: 12), Expanded(child: Text('أفضل 10 منتجات - الأكثر مبيعاً ($_selectedMonthKey)', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)))])),
        const SizedBox(height: 12),
        if (_topProductsBySales.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('لا توجد بيانات'))
        else ...List.generate(_topProductsBySales.length, (i) {
          final p = _topProductsBySales[i];
          return _prodCard(i + 1, p['name'] ?? '', '${_fmt(p['total_quantity'] ?? 0)} ${p['unit'] ?? ''}', 'الكمية المباعة', const Color(0xFF9C27B0));
        }),
        const SizedBox(height: 24),
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF9800), Color(0xFFF57C00)]), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [const Icon(Icons.monetization_on, color: Colors.white, size: 30), const SizedBox(width: 12), Expanded(child: Text('أفضل 10 منتجات - الأكثر ربحية ($_selectedMonthKey)', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)))])),
        const SizedBox(height: 12),
        if (_topProductsByProfit.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('لا توجد بيانات'))
        else ...List.generate(_topProductsByProfit.length, (i) {
          final p = _topProductsByProfit[i];
          return _prodCard(i + 1, p['name'] ?? '', '${_fmt(p['total_profit'] ?? 0)} د.ع', 'صافي الربح', const Color(0xFFFF9800));
        }),
      ])));
  }

  Widget _prodCard(int rank, String name, String val, String label, Color c) => Card(
    margin: const EdgeInsets.only(bottom: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    child: ListTile(
      leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Center(child: Text('$rank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: c)))),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
      trailing: Text(val, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: c)),
    ));
}
