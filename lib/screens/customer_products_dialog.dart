// screens/customer_products_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/reports_service.dart';

enum SortOption { byQuantity, byAmount, byProfit }

class CustomerProductsDialog extends StatefulWidget {
  final int customerId;
  final String customerName;
  final int? year;
  final int? month;

  const CustomerProductsDialog({
    super.key,
    required this.customerId,
    required this.customerName,
    this.year,
    this.month,
  });

  @override
  State<CustomerProductsDialog> createState() => _CustomerProductsDialogState();
}

class _CustomerProductsDialogState extends State<CustomerProductsDialog> {
  final ReportsService _reportsService = ReportsService();
  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  SortOption _sortOption = SortOption.byQuantity;
  
  final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final products = await _reportsService.getCustomerProductsPurchased(
        customerId: widget.customerId,
        year: widget.year,
        month: widget.month,
      );
      setState(() {
        _products = products;
        _isLoading = false;
      });
      _sortProducts();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  void _sortProducts() {
    setState(() {
      switch (_sortOption) {
        case SortOption.byQuantity:
          _products.sort((a, b) => (b['totalQuantity'] as double).compareTo(a['totalQuantity'] as double));
          break;
        case SortOption.byAmount:
          _products.sort((a, b) => (b['totalAmount'] as double).compareTo(a['totalAmount'] as double));
          break;
        case SortOption.byProfit:
          _products.sort((a, b) => (b['totalProfit'] as double).compareTo(a['totalProfit'] as double));
          break;
      }
    });
  }

  String _getPeriodText() {
    if (widget.year != null && widget.month != null) {
      return '${widget.year}-${widget.month.toString().padLeft(2, '0')}';
    } else if (widget.year != null) {
      return 'سنة ${widget.year}';
    }
    return 'كل الفترات';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // العنوان
            Row(
              children: [
                const Icon(Icons.shopping_bag, color: Color(0xFF2196F3), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المنتجات المشتراة',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${widget.customerName} - ${_getPeriodText()}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            
            // خيارات الترتيب
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Text('ترتيب: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButton<SortOption>(
                      value: _sortOption,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: SortOption.byQuantity, child: Text('الأكثر سحباً (كمية)')),
                        DropdownMenuItem(value: SortOption.byAmount, child: Text('الأكثر سحباً (مبلغ)')),
                        DropdownMenuItem(value: SortOption.byProfit, child: Text('الأكثر ربحاً')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _sortOption = value;
                          _sortProducts();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // قائمة المنتجات
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _products.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('لا توجد منتجات', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _products.length,
                          itemBuilder: (context, index) => _buildProductCard(_products[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> product) {
    final totalAmount = product['totalAmount'] as double;
    final totalProfit = product['totalProfit'] as double;
    final hierarchicalDisplay = product['hierarchicalDisplay'] as String;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // اسم المنتج
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory, color: Color(0xFF2196F3), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    product['productName'] as String,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // الكمية مع التحويل الهرمي
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.straighten, color: Color(0xFF4CAF50), size: 18),
                  const SizedBox(width: 8),
                  const Text('الكمية: ', style: TextStyle(fontWeight: FontWeight.w500)),
                  Expanded(
                    child: Text(
                      hierarchicalDisplay,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4CAF50)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            
            // المبلغ والربح
            Row(
              children: [
                Expanded(
                  child: _buildInfoChip(
                    icon: Icons.attach_money,
                    label: 'المبلغ',
                    value: '${_fmt(totalAmount)} د.ع',
                    color: const Color(0xFF2196F3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildInfoChip(
                    icon: Icons.trending_up,
                    label: 'الربح',
                    value: '${_fmt(totalProfit)} د.ع',
                    color: totalProfit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
