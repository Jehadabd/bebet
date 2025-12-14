// screens/overdue_debts_screen.dart
// شاشة الديون المتأخرة - العملاء الذين لم يسددوا منذ فترة
import 'package:flutter/material.dart';
import '../services/reports_service.dart';
import 'package:intl/intl.dart';
import 'customer_details_screen.dart';
import '../models/customer.dart';
import '../services/database_service.dart';

class OverdueDebtsScreen extends StatefulWidget {
  const OverdueDebtsScreen({super.key});

  @override
  State<OverdueDebtsScreen> createState() => _OverdueDebtsScreenState();
}

class _OverdueDebtsScreenState extends State<OverdueDebtsScreen> {
  final ReportsService _reportsService = ReportsService();
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _overdueDebts = [];
  bool _isLoading = true;
  int _selectedDays = 30; // الفترة الافتراضية
  double _minimumDebt = 0; // الحد الأدنى للدين
  
  final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final debts = await _reportsService.getOverdueDebts(
        daysSinceLastPayment: _selectedDays,
        minimumDebt: _minimumDebt,
      );
      
      setState(() {
        _overdueDebts = debts;
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

  @override
  Widget build(BuildContext context) {
    // حساب إجمالي الديون المتأخرة
    double totalOverdue = 0;
    for (var debt in _overdueDebts) {
      totalOverdue += (debt['current_total_debt'] as num?)?.toDouble() ?? 0;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('الديون المتأخرة'),
        backgroundColor: const Color(0xFFE91E63),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'تصفية',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Column(
        children: [
          // ملخص
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE91E63),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryItem(
                      icon: Icons.people,
                      label: 'عدد العملاء',
                      value: '${_overdueDebts.length}',
                    ),
                    _buildSummaryItem(
                      icon: Icons.account_balance_wallet,
                      label: 'إجمالي الديون',
                      value: '${_fmt(totalOverdue)} د.ع',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'العملاء الذين لم يسددوا منذ $_selectedDays يوم أو أكثر',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          
          // القائمة
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE91E63)))
                : _overdueDebts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, size: 64, color: Colors.green.withOpacity(0.5)),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد ديون متأخرة!',
                              style: TextStyle(fontSize: 18, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _overdueDebts.length,
                          itemBuilder: (context, index) {
                            final debt = _overdueDebts[index];
                            return _buildDebtCard(debt, index);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildDebtCard(Map<String, dynamic> debt, int index) {
    final name = debt['name']?.toString() ?? 'غير معروف';
    final phone = debt['phone']?.toString() ?? '';
    final totalDebt = (debt['current_total_debt'] as num?)?.toDouble() ?? 0;
    final lastPaymentStr = debt['last_payment_date'] as String?;
    final lastTransactionStr = debt['last_transaction_date'] as String?;
    
    String lastPaymentText = 'لم يسدد أبداً';
    int daysSincePayment = 999;
    
    if (lastPaymentStr != null) {
      try {
        final lastPayment = DateTime.parse(lastPaymentStr);
        daysSincePayment = DateTime.now().difference(lastPayment).inDays;
        lastPaymentText = 'آخر تسديد: ${DateFormat('yyyy-MM-dd').format(lastPayment)} (منذ $daysSincePayment يوم)';
      } catch (e) {}
    }
    
    // تحديد لون البطاقة بناءً على خطورة التأخير
    Color cardColor;
    if (daysSincePayment > 90) {
      cardColor = Colors.red.shade50;
    } else if (daysSincePayment > 60) {
      cardColor = Colors.orange.shade50;
    } else {
      cardColor = Colors.yellow.shade50;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openCustomerDetails(debt),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFE91E63).withOpacity(0.1),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: Color(0xFFE91E63), fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (phone.isNotEmpty)
                          Text(
                            phone,
                            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_fmt(totalDebt)} د.ع',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE91E63),
                        ),
                      ),
                      if (daysSincePayment > 90)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'متأخر جداً',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                lastPaymentText,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCustomerDetails(Map<String, dynamic> debt) async {
    final customerId = debt['id'] as int?;
    if (customerId == null) return;
    
    try {
      final customer = await _db.getCustomerById(customerId);
      if (customer != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CustomerDetailsScreen(customer: customer),
          ),
        ).then((_) {
          // 🔄 تحديث قائمة الديون عند الرجوع من صفحة العميل
          _loadData();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في فتح تفاصيل العميل: $e')),
        );
      }
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصفية الديون المتأخرة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('الفترة منذ آخر تسديد:'),
            const SizedBox(height: 8),
            DropdownButton<int>(
              value: _selectedDays,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 7, child: Text('7 أيام')),
                DropdownMenuItem(value: 14, child: Text('14 يوم')),
                DropdownMenuItem(value: 30, child: Text('30 يوم')),
                DropdownMenuItem(value: 60, child: Text('60 يوم')),
                DropdownMenuItem(value: 90, child: Text('90 يوم')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedDays = value);
                  Navigator.pop(context);
                  _loadData();
                }
              },
            ),
          ],
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
}
