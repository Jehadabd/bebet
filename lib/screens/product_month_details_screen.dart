// screens/product_month_details_screen.dart
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';
import 'invoice_details_screen.dart';
import '../services/database_service.dart' show InvoiceWithProductData;
import 'package:intl/intl.dart';
import 'product_customers_dialog.dart';

class ProductMonthDetailsScreen extends StatefulWidget {
  final Product product;
  final int year;
  final int month;

  const ProductMonthDetailsScreen({
    super.key,
    required this.product,
    required this.year,
    required this.month,
  });

  @override
  State<ProductMonthDetailsScreen> createState() =>
      _ProductMonthDetailsScreenState();
}

class _ProductMonthDetailsScreenState extends State<ProductMonthDetailsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<InvoiceWithProductData> _invoices = [];
  double _monthProfit = 0.0;
  double _monthQuantity = 0.0;
  double _monthSellingPrice = 0.0; // إضافة متغير لحساب إجمالي سعر البيع
  bool _isLoading = true;
   late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _loadMonthData();
  }

  Future<void> _loadMonthData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final invoices = await _databaseService.getProductInvoicesForMonth(
        widget.product.id!,
        widget.year,
        widget.month,
      );
      final monthlyProfitMap = await _databaseService.getProductMonthlyProfit(
        widget.product.id!,
        widget.year,
      );
      final profit = monthlyProfitMap[widget.month] ?? 0.0;
      double totalQuantity = 0.0;
      double totalSellingPrice = 0.0;
      for (final inv in invoices) {
        totalQuantity += inv.quantitySold;
        totalSellingPrice += inv.sellingPrice! * inv.quantitySold;
      }
      setState(() {
        _invoices = invoices;
        _monthProfit = profit;
        _monthQuantity = totalQuantity;
        _monthSellingPrice = totalSellingPrice;
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

  String _numericMonth(int year, int month) => '${year}-${month.toString().padLeft(2, '0')}';

  void _showCustomersBuying() {
    showDialog(
      context: context,
      builder: (context) => ProductCustomersDialog(
        productId: widget.product.id!,
        productName: widget.product.name,
        year: widget.year,
        month: widget.month,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // حساب الربح من الوحدة مع مراعاة الوحدات الهيراركية
  double _calculateProfitPerUnit() {
    if (_monthQuantity <= 0) {
      return 0.0;
    }
    
    // حساب الربح من الوحدة بناءً على إجمالي الربح والكمية
    // مع مراعاة أن الكمية محسوبة بالوحدات الأساسية (قطع)
    return _monthProfit / _monthQuantity;
  }

  // حساب الربح من الوحدة للفاتورة محددة
  double _calculateInvoiceProfitPerUnit(double profit, double quantity) {
    if (quantity <= 0) {
      return 0.0;
    }
    
    return profit / quantity;
  }

  @override
  Widget build(BuildContext context) {
    final monthName = _numericMonth(widget.year, widget.month);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: Text(
          '${widget.product.name} - ${monthName}',
          style: const TextStyle(fontSize: 16),
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
            onPressed: _loadMonthData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4CAF50),
              ),
            )
          : _invoices.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 80,
                        color: Color(0xFFCCCCCC),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'لا توجد فواتير في هذا الشهر',
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFF666666),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMonthData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _invoices.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        // زر العملاء المشترين + ملخص الشهر
                        return Column(
                          children: [
                            // زر العملاء المشترين
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _showCustomersBuying,
                                  icon: const Icon(Icons.people),
                                  label: const Text('تفصيل العملاء المشترين'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4CAF50),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // ملخص الشهر
                            _buildMonthSummaryCard(),
                          ],
                        );
                      } else {
                        final invoiceData = _invoices[index - 1];
                        return _buildInvoiceCard(invoiceData);
                      }
                    },
                  ),
                ),
    );
  }

  Widget _buildMonthSummaryCard() {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green.withOpacity(0.3), width: 1),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.green.withOpacity(0.1),
              Colors.green.withOpacity(0.05),
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
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.calendar_month,
                    color: Colors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ملخص الشهر',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الكمية المباعة: ${_fmt(_monthQuantity)} ${widget.product.unit}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الربح من الوحدة: ${_fmt(_calculateProfitPerUnit())} د.ع',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'إجمالي الربح: ${_fmt(_monthProfit)} د.ع',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailInfo(
                          title: 'تكلفة الوحدة',
                          value: widget.product.costPrice != null
                              ? '${_fmt(widget.product.costPrice!)} د.ع'
                              : 'غير محدد',
                          color: const Color(0xFFF44336),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDetailInfo(
                          title: 'متوسط سعر البيع',
                          value: _monthQuantity > 0
                              ? '${_fmt(_monthSellingPrice / _monthQuantity)} د.ع'
                              : 'غير محدد',
                          color: const Color(0xFFFF9800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailInfo(
                          title: 'الربح من الوحدة',
                          value: _monthQuantity > 0
                              ? '${_fmt(_calculateProfitPerUnit())} د.ع'
                              : 'غير محدد',
                          color: const Color(0xFF4CAF50),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildDetailInfo(
                          title: 'نسبة الربح',
                          // 🔧 إصلاح: حساب نسبة الربح بناءً على إجمالي المبيعات (الربح ÷ المبيعات × 100)
                          value: _monthSellingPrice > 0
                              ? '${((_monthProfit / _monthSellingPrice) * 100).toStringAsFixed(1)}%'
                              : 'غير محدد',
                          color: const Color(0xFF9C27B0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceCard(InvoiceWithProductData invoiceData) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        onTap: () => _navigateToInvoiceDetails(invoiceData.invoice),
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
                      Icons.receipt,
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
                          'فاتورة رقم: ${invoiceData.invoice.id}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'التاريخ: ${_formatDate(invoiceData.invoice.invoiceDate)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // معلومات تفصيلية عن المنتج
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailInfo(
                            title: 'الكمية المباعة',
                            value: '${_fmt(invoiceData.quantitySold)} ${widget.product.unit}',
                            color: const Color(0xFF2196F3),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildDetailInfo(
                            title: 'تكلفة الوحدة',
                            value: '${_fmt(invoiceData.unitCostAtSale)} د.ع',
                            color: const Color(0xFFF44336),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailInfo(
                            title: 'سعر البيع للوحدة',
                            value: '${invoiceData.sellingPrice != null ? _fmt(invoiceData.sellingPrice!) : 'غير محدد'} د.ع',
                            color: const Color(0xFFFF9800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildDetailInfo(
                            title: 'الربح من الفاتورة',
                            value: '${_fmt(invoiceData.profit)} د.ع',
                            color: const Color(0xFF4CAF50),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDetailInfo(
                            title: 'الربح من الوحدة',
                            value: '${_fmt(_calculateInvoiceProfitPerUnit(invoiceData.profit, invoiceData.quantitySold))} د.ع',
                            color: const Color(0xFF4CAF50),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildDetailInfo(
                            title: 'نسبة الربح',
                            value: invoiceData.unitCostAtSale > 0
                                ? '${((invoiceData.profit / (invoiceData.unitCostAtSale * invoiceData.quantitySold)) * 100).toStringAsFixed(1)}%'
                                : 'غير محدد',
                            color: const Color(0xFF9C27B0),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailInfo({
    required String title,
    required String value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _navigateToInvoiceDetails(Invoice invoice) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InvoiceDetailsScreen(invoiceId: invoice.id!),
      ),
    );
  }
}
