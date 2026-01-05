// lib/screens/sync_stats_screen.dart
// شاشة إحصائيات المزامنة

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sync_stat.dart';
import '../services/sync_stats_service.dart';

class SyncStatsScreen extends StatefulWidget {
  const SyncStatsScreen({Key? key}) : super(key: key);

  @override
  State<SyncStatsScreen> createState() => _SyncStatsScreenState();
}

class _SyncStatsScreenState extends State<SyncStatsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final SyncStatsService _statsService = SyncStatsService();

  // Filters
  String? _selectedCustomerName;
  SyncStatType? _selectedType;
  DateTime? _startDate;
  DateTime? _endDate;

  // Data
  List<SyncStat> _successfulStats = [];
  List<SyncStat> _failedStats = [];
  SyncStatsSummary? _summary;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// تحميل البيانات (lazy loading)
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // تحميل البيانات بشكل متوازي
      final results = await Future.wait([
        _statsService.getSuccessfulTransactions(
          customerName: _selectedCustomerName,
          type: _selectedType,
          startDate: _startDate,
          endDate: _endDate,
        ),
        _statsService.getFailedOperations(
          customerName: _selectedCustomerName,
          startDate: _startDate,
          endDate: _endDate,
        ),
        _statsService.getSummary(),
      ]);

      setState(() {
        _successfulStats = results[0] as List<SyncStat>;
        _failedStats = results[1] as List<SyncStat>;
        _summary = results[2] as SyncStatsSummary;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تحميل الإحصائيات: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📊 إحصائيات المزامنة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.check_circle), text: 'العمليات الناجحة'),
            Tab(icon: Icon(Icons.error), text: 'العمليات الفاشلة'),
          ],
        ),
      ),
      body: Column(
        children: [
          // الملخص
          if (_summary != null) _buildSummaryCard(),

          // الفلاتر
          _buildFilters(),

          // المحتوى
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSuccessfulTab(),
                      _buildFailedTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// بطاقة الملخص
  Widget _buildSummaryCard() {
    final summary = _summary!;
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem(
                  '✅ ناجح',
                  summary.totalSuccess.toString(),
                  Colors.green,
                ),
                _buildSummaryItem(
                  '❌ فاشل',
                  summary.totalFailed.toString(),
                  Colors.red,
                ),
                _buildSummaryItem(
                  '📤 مرسل',
                  summary.sentCount.toString(),
                  Colors.blue,
                ),
                _buildSummaryItem(
                  '📥 مستقبل',
                  summary.receivedCount.toString(),
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'نسبة النجاح: ${summary.successRate.toStringAsFixed(1)}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: summary.successRate >= 95 ? Colors.green : Colors.orange,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  /// الفلاتر
  Widget _buildFilters() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // فلتر النوع
            if (_tabController.index == 0)
              DropdownButton<SyncStatType?>(
                value: _selectedType,
                hint: const Text('نوع العملية'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('الكل')),
                  DropdownMenuItem(
                    value: SyncStatType.sent,
                    child: Text('📤 تم التسليم'),
                  ),
                  DropdownMenuItem(
                    value: SyncStatType.received,
                    child: Text('📥 تم الاستلام'),
                  ),
                ],
                onChanged: (value) {
                  setState(() => _selectedType = value);
                  _loadData();
                },
              ),

            // زر اختيار التاريخ
            ElevatedButton.icon(
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(_startDate == null
                  ? 'اختر التاريخ'
                  : '${DateFormat('yyyy-MM-dd').format(_startDate!)} - ${_endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : 'الآن'}'),
              onPressed: _selectDateRange,
            ),

            // زر إعادة تعيين الفلاتر
            if (_selectedType != null || _startDate != null)
              TextButton.icon(
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('مسح الفلاتر'),
                onPressed: () {
                  setState(() {
                    _selectedType = null;
                    _startDate = null;
                    _endDate = null;
                  });
                  _loadData();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// اختيار نطاق التاريخ
  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate ?? DateTime.now())
          : null,
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }

  /// تبويب العمليات الناجحة
  Widget _buildSuccessfulTab() {
    if (_successfulStats.isEmpty) {
      return const Center(
        child: Text('لا توجد عمليات ناجحة'),
      );
    }

    // تجميع حسب العميل
    final groupedByCustomer = <String, List<SyncStat>>{};
    for (final stat in _successfulStats) {
      groupedByCustomer.putIfAbsent(stat.customerName, () => []).add(stat);
    }

    return ListView.builder(
      itemCount: groupedByCustomer.length,
      itemBuilder: (context, index) {
        final customerName = groupedByCustomer.keys.elementAt(index);
        final stats = groupedByCustomer[customerName]!;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ExpansionTile(
            title: Text(
              customerName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${stats.length} عملية'),
            children: stats.map((stat) => _buildStatTile(stat)).toList(),
          ),
        );
      },
    );
  }

  /// تبويب العمليات الفاشلة
  Widget _buildFailedTab() {
    if (_failedStats.isEmpty) {
      return const Center(
        child: Text('لا توجد عمليات فاشلة 🎉'),
      );
    }

    // تجميع حسب العميل
    final groupedByCustomer = <String, List<SyncStat>>{};
    for (final stat in _failedStats) {
      groupedByCustomer.putIfAbsent(stat.customerName, () => []).add(stat);
    }

    return ListView.builder(
      itemCount: groupedByCustomer.length,
      itemBuilder: (context, index) {
        final customerName = groupedByCustomer.keys.elementAt(index);
        final stats = groupedByCustomer[customerName]!;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Colors.red.shade50,
          child: ExpansionTile(
            title: Text(
              customerName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${stats.length} عملية فاشلة'),
            children: stats.map((stat) => _buildStatTile(stat)).toList(),
          ),
        );
      },
    );
  }

  /// عنصر إحصائية واحدة
  Widget _buildStatTile(SyncStat stat) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    return ListTile(
      leading: Text(
        '${stat.typeIcon} ${stat.statusIcon}',
        style: const TextStyle(fontSize: 20),
      ),
      title: Text(stat.typeLabel),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🕒 ${dateFormat.format(stat.timestamp)}'),
          Text('💰 المبلغ: ${stat.amount.toStringAsFixed(2)}'),
          Text('📊 قبل: ${stat.balanceBefore.toStringAsFixed(2)} → بعد: ${stat.balanceAfter.toStringAsFixed(2)}'),
          if (stat.errorMessage != null)
            Text(
              '⚠️ ${stat.errorMessage}',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          if (stat.retryCount != null && stat.retryCount! > 0)
            Text(
              '🔄 محاولات: ${stat.retryCount}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      isThreeLine: true,
    );
  }
}
