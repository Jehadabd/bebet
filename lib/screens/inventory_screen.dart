import 'package:flutter/material.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final DatabaseService _db = DatabaseService();
  Map<String, MonthlySalesSummary> _monthlySummaries = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMonthlySummaries();
  }

  Future<void> _loadMonthlySummaries() async {
    setState(() => _isLoading = true);
    try {
      final summaries = await _db.getMonthlySalesSummary();
      setState(() {
        _monthlySummaries = summaries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل ملخص المبيعات: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sort months in descending order (most recent first)
    final sortedMonthYears = _monthlySummaries.keys.toList();
    sortedMonthYears.sort((a, b) {
      // Ensure month is zero-padded for parsing
      final aDate = DateTime.parse('${a.split('-')[0]}-${a.split('-')[1].padLeft(2, '0')}-01');
      final bDate = DateTime.parse('${b.split('-')[0]}-${b.split('-')[1].padLeft(2, '0')}-01');
      return bDate.compareTo(aDate);
    });

    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('الجرد'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _monthlySummaries.isEmpty
              ? const Center(child: Text('لا توجد بيانات مبيعات متاحة.'))
              : ListView.builder(
                  itemCount: sortedMonthYears.length,
                  itemBuilder: (context, index) {
                    final monthYear = sortedMonthYears[index];
                    final summary = _monthlySummaries[monthYear]!;

                    // Format month and year for display
                    final date = DateTime.parse('${monthYear.split('-')[0]}-${monthYear.split('-')[1].padLeft(2, '0')}-01'); // Ensure month is zero-padded
                    final monthName = DateFormat.yMMMM('ar').format(date); // Format in Arabic
                    final isCurrentMonth = date.year == now.year && date.month == now.month;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$monthName ${isCurrentMonth ? '- الشهر الحالي' : ''}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text('إجمالي المبيعات: ${summary.totalSales.toStringAsFixed(2)} دينار عراقي'),
                            Text('صافي الأرباح: ${summary.netProfit.toStringAsFixed(2)} دينار عراقي'),
                            Text('البيع بالنقد: ${summary.cashSales.toStringAsFixed(2)} دينار عراقي'),
                            Text('البيع بالدين: ${summary.creditSales.toStringAsFixed(2)} دينار عراقي'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
} 