// screens/product_details_screen.dart
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import 'product_year_details_screen.dart';
import 'package:intl/intl.dart';

class ProductDetailsScreen extends StatefulWidget {
  final Product product;

  const ProductDetailsScreen({
    super.key,
    required this.product,
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  Map<int, double> _yearlySales = {};
  Map<int, double> _yearlyProfit = {};
  bool _isLoading = true;
  double _averageSellingPrice = 0.0;
  double _totalSales = 0.0; // 🔧 إضافة: إجمالي المبيعات الفعلي
  double _totalProfit = 0.0; // 🔧 إضافة: إجمالي الربح الفعلي
  double _totalQuantity = 0.0; // 🔧 إضافة: إجمالي الكمية
  late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _loadYearlyData();
  }

  Future<void> _loadYearlyData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final yearlySales =
          await _databaseService.getProductYearlySales(widget.product.id!);
      final yearlyProfit =
          await _databaseService.getProductYearlyProfit(widget.product.id!);
      final salesData =
          await _databaseService.getProductSalesData(widget.product.id!);
      setState(() {
        _yearlySales = yearlySales;
        _yearlyProfit = yearlyProfit;
        _averageSellingPrice = (salesData['averageSellingPrice'] ?? 0.0) as double;
        _totalSales = (salesData['totalSales'] ?? 0.0) as double;
        _totalProfit = (salesData['totalProfit'] ?? 0.0) as double;
        _totalQuantity = (salesData['totalQuantity'] ?? 0.0) as double;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في تحميل البيانات: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(
          'تفاصيل ${widget.product.name}',
          style: const TextStyle(fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF4CAF50),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadYearlyData,
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _testProfitCalculation,
            tooltip: 'اختبار حساب الأرباح',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4CAF50),
              ),
            )
          : Column(
              children: [
                _buildProductHeader(),
                Expanded(
                  child: _yearlySales.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.timeline,
                                size: 80,
                                color: Color(0xFFCCCCCC),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'لا توجد مبيعات لهذا المنتج',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF666666),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadYearlyData,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _yearlySales.length,
                            itemBuilder: (context, index) {
                              final year = _yearlySales.keys.elementAt(index);
                              final quantity = _yearlySales[year]!;
                              final profit = _yearlyProfit[year] ?? 0.0;
                              return _buildYearCard(year, quantity, profit);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildProductHeader() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.product.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C3E50),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.product.unit,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF4CAF50),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildHeaderInfo(
                  icon: Icons.attach_money,
                  title: 'متوسط سعر البيع',
                  value: '${_fmt(_averageSellingPrice)} د.ع',
                  color: const Color(0xFFFF9800),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildHeaderInfo(
                  icon: Icons.price_change,
                  title: 'التكلفة',
                  value: widget.product.costPrice != null
                      ? '${_fmt(widget.product.costPrice!)} د.ع'
                      : 'غير محدد',
                  color: const Color(0xFFF44336),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildHeaderInfo(
                  icon: Icons.trending_up,
                  title: 'الربح المتوقع',
                  value: _calculateExpectedProfit(),
                  color: const Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildHeaderInfo(
                  icon: Icons.percent,
                  title: 'نسبة الربح',
                  value: _calculateProfitPercentage(),
                  color: const Color(0xFF9C27B0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // حساب الربح المتوقع بناءً على البيانات الفعلية
  // 🔧 إصلاح: استخدام البيانات الفعلية من getProductSalesData
  String _calculateExpectedProfit() {
    if (_totalQuantity <= 0) return 'غير محدد';
    
    // الربح من الوحدة = إجمالي الربح ÷ إجمالي الكمية المباعة
    final profitPerUnit = _totalProfit / _totalQuantity;
    return '${_fmt(profitPerUnit)} د.ع';
  }

  // حساب نسبة الربح بناءً على البيانات الفعلية
  // 🔧 إصلاح: استخدام البيانات الفعلية من getProductSalesData
  String _calculateProfitPercentage() {
    if (_totalSales <= 0) return 'غير محدد';
    
    // نسبة الربح = (إجمالي الربح ÷ إجمالي المبيعات) × 100
    final percentage = (_totalProfit / _totalSales) * 100;
    return '${percentage.toStringAsFixed(1)}%';
  }

  Widget _buildHeaderInfo({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildYearCard(int year, double quantity, double profit) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        onTap: () => _navigateToYearDetails(year),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.blue.withOpacity(0.1),
                Colors.blue.withOpacity(0.05),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.calendar_today,
                      color: Colors.blue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'سنة $year',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'كمية مباعة: ${_fmt(quantity)} ${widget.product.unit}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'الربح: ${_fmt(profit)} د.ع',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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

  void _navigateToYearDetails(int year) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductYearDetailsScreen(
          product: widget.product,
          year: year,
        ),
      ),
    );
  }

  Future<void> _testProfitCalculation() async {
    try {
      final result = await _databaseService.testProfitCalculation(widget.product.id!);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('اختبار حساب الأرباح - ${result['product_name']}'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('تكلفة المنتج: ${result['product_cost_price']} د.ع'),
                  Text('الكمية الإجمالية: ${result['total_quantity']}'),
                  Text('إجمالي المبيعات: ${result['total_sales']} د.ع'),
                  Text('إجمالي التكلفة: ${result['total_cost']} د.ع'),
                  Text('إجمالي الربح: ${result['total_profit']} د.ع'),
                  const Divider(),
                  Text('صيغة الحساب: ${result['calculation_formula']}'),
                  Text('التحقق: ${result['verification']}'),
                  const Divider(),
                  const Text('تفاصيل الفواتير:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...(result['detailed_results'] as List).map((item) => 
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('فاتورة #${item['invoice_id']} - ${item['date']}'),
                          Text('الكمية: ${item['quantity']}'),
                          Text('التكلفة: ${item['cost_price']} د.ع'),
                          Text('سعر البيع: ${item['selling_price']} د.ع'),
                          Text('الربح: ${item['profit']} د.ع'),
                        ],
                      ),
                    )
                  ).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ في اختبار حساب الأرباح: $e'),
          ),
        );
      }
    }
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
