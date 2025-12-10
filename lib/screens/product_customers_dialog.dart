// screens/product_customers_dialog.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/reports_service.dart';

enum SortOption { byQuantity, byAmount, byProfit }

class ProductCustomersDialog extends StatefulWidget {
  final int productId;
  final String productName;
  final String baseUnit;
  final String? unitHierarchyJson;
  final double? lengthPerUnit;
  final int? year;
  final int? month;

  const ProductCustomersDialog({
    super.key,
    required this.productId,
    required this.productName,
    required this.baseUnit,
    this.unitHierarchyJson,
    this.lengthPerUnit,
    this.year,
    this.month,
  });

  @override
  State<ProductCustomersDialog> createState() => _ProductCustomersDialogState();
}

class _ProductCustomersDialogState extends State<ProductCustomersDialog> {
  final ReportsService _reportsService = ReportsService();
  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;
  SortOption _sortOption = SortOption.byQuantity;
  
  final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      final customers = await _reportsService.getProductCustomersBought(
        productId: widget.productId,
        productName: widget.productName,
        baseUnit: widget.baseUnit,
        unitHierarchyJson: widget.unitHierarchyJson,
        lengthPerUnit: widget.lengthPerUnit,
        year: widget.year,
        month: widget.month,
      );
      setState(() {
        _customers = customers;
        _isLoading = false;
      });
      _sortCustomers();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  void _sortCustomers() {
    setState(() {
      switch (_sortOption) {
        case SortOption.byQuantity:
          _customers.sort((a, b) => (b['totalQuantity'] as double).compareTo(a['totalQuantity'] as double));
          break;
        case SortOption.byAmount:
          _customers.sort((a, b) => (b['totalAmount'] as double).compareTo(a['totalAmount'] as double));
          break;
        case SortOption.byProfit:
          _customers.sort((a, b) => (b['totalProfit'] as double).compareTo(a['totalProfit'] as double));
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
                const Icon(Icons.people, color: Color(0xFF4CAF50), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'العملاء المشترين',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${widget.productName} - ${_getPeriodText()}',
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
                          _sortCustomers();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // قائمة العملاء
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _customers.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('لا يوجد عملاء', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _customers.length,
                          itemBuilder: (context, index) => _buildCustomerCard(_customers[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer) {
    final totalAmount = customer['totalAmount'] as double;
    final totalProfit = customer['totalProfit'] as double;
    final hierarchicalDisplay = customer['hierarchicalDisplay'] as String;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // اسم العميل
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.person, color: Color(0xFF4CAF50), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    customer['customerName'] as String,
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
                color: const Color(0xFF2196F3).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.straighten, color: Color(0xFF2196F3), size: 18),
                  const SizedBox(width: 8),
                  const Text('الكمية: ', style: TextStyle(fontWeight: FontWeight.w500)),
                  Expanded(
                    child: Text(
                      hierarchicalDisplay,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2196F3)),
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
