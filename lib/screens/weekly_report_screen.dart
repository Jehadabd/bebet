// screens/weekly_report_screen.dart
import 'package:flutter/material.dart';
import '../services/ai_chat_service.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart';
import 'transactions_list_dialog.dart';

class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  late final AIChatService _aiChatService;
  Map<String, dynamic>? _reportData;
  bool _isLoading = true;
  late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _aiChatService = AIChatService(DatabaseService());
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await _aiChatService.getWeeklyReport();
      setState(() {
        _reportData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في تحميل التقرير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final dateRangeStr = '${DateFormat('yyyy-MM-dd', 'ar').format(startOfWeek)} - ${DateFormat('yyyy-MM-dd', 'ar').format(endOfWeek)}';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('تقرير الأسبوع', style: TextStyle(fontSize: 24)),
        centerTitle: true,
        backgroundColor: const Color(0xFF9C27B0),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReport,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF9C27B0),
              ),
            )
          : _reportData == null
              ? const Center(
                  child: Text(
                    'لا توجد بيانات',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadReport,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // عنوان الفترة
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
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
                              const Icon(
                                Icons.date_range,
                                size: 40,
                                color: Color(0xFF9C27B0),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                dateRangeStr,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2C3E50),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'تقرير مفصل لمبيعات الأسبوع',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // المبيعات والأرباح
                        _buildSectionTitle('المبيعات والأرباح'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                title: 'إجمالي المبيعات',
                                value: '${_fmt(_reportData!['totalSales'])} د.ع',
                                icon: Icons.shopping_cart,
                                color: const Color(0xFF2196F3),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                title: 'صافي الربح',
                                value: '${_fmt(_reportData!['netProfit'])} د.ع',
                                icon: Icons.trending_up,
                                color: const Color(0xFF4CAF50),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildStatCard(
                          title: 'إجمالي التكلفة',
                          value: '${_fmt(_reportData!['totalCost'])} د.ع',
                          icon: Icons.money_off,
                          color: const Color(0xFFF44336),
                        ),
                        const SizedBox(height: 20),

                        // نوع المبيعات
                        _buildSectionTitle('تصنيف المبيعات'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                title: 'البيع بالنقد',
                                value: '${_fmt(_reportData!['cashSales'])} د.ع',
                                icon: Icons.payments,
                                color: const Color(0xFF4CAF50),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                title: 'البيع بالدين',
                                value: '${_fmt(_reportData!['creditSales'])} د.ع',
                                icon: Icons.credit_card,
                                color: const Color(0xFFFF9800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildStatCard(
                          title: 'إجمالي الراجع',
                          value: '${_fmt(_reportData!['totalReturns'])} د.ع',
                          icon: Icons.keyboard_return,
                          color: const Color(0xFF9C27B0),
                        ),
                        const SizedBox(height: 20),

                        // المعاملات المالية
                        _buildSectionTitle('المعاملات المالية'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildClickableStatCard(
                                title: 'إضافة دين',
                                value: '${_fmt(_reportData!['totalManualDebt'])} د.ع',
                                subtitle: '${_reportData!['manualDebtCount']} معاملة',
                                icon: Icons.add_circle,
                                color: const Color(0xFFFF5722),
                                onTap: () => _showDebtAdditions(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildClickableStatCard(
                                title: 'تسديد دين',
                                value: '${_fmt(_reportData!['totalManualPayment'])} د.ع',
                                subtitle: '${_reportData!['manualPaymentCount']} معاملة',
                                icon: Icons.remove_circle,
                                color: const Color(0xFF4CAF50),
                                onTap: () => _showDebtPayments(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // إحصائيات إضافية
                        _buildSectionTitle('إحصائيات إضافية'),
                        const SizedBox(height: 12),
                        _buildStatCard(
                          title: 'عدد الفواتير',
                          value: '${_reportData!['invoiceCount']} فاتورة',
                          icon: Icons.receipt_long,
                          color: const Color(0xFF607D8B),
                        ),
                        const SizedBox(height: 20),

                        // متوسطات
                        if (_reportData!['invoiceCount'] > 0) ...[
                          _buildSectionTitle('المتوسطات'),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  title: 'متوسط المبيعات/فاتورة',
                                  value: '${_fmt(_reportData!['totalSales'] / _reportData!['invoiceCount'])} د.ع',
                                  icon: Icons.calculate,
                                  color: const Color(0xFF00BCD4),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  title: 'متوسط الربح/فاتورة',
                                  value: '${_fmt(_reportData!['netProfit'] / _reportData!['invoiceCount'])} د.ع',
                                  icon: Icons.analytics,
                                  color: const Color(0xFF8BC34A),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
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

  Widget _buildStatCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
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
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // بطاقة قابلة للضغط لعرض تفاصيل المعاملات
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

  // عرض معاملات إضافة الدين
  void _showDebtAdditions() {
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final endOfWeek = startOfWeekDay.add(const Duration(days: 7));
    
    TransactionsListDialog.showDebtAdditions(
      context: context,
      startDate: startOfWeekDay,
      endDate: endOfWeek,
      periodTitle: 'الأسبوع',
    );
  }

  // عرض معاملات تسديد الدين
  void _showDebtPayments() {
    final today = DateTime.now();
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final endOfWeek = startOfWeekDay.add(const Duration(days: 7));
    
    TransactionsListDialog.showDebtPayments(
      context: context,
      startDate: startOfWeekDay,
      endDate: endOfWeek,
      periodTitle: 'الأسبوع',
    );
  }
}
