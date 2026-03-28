// screens/product_reports_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/product.dart';
import 'product_details_screen.dart';
import 'product_hierarchy_details_screen.dart';
import '../widgets/date_range_input_dialog.dart';
import 'package:intl/intl.dart';

enum ProductSortOption {
  mostProfitable,
  mostSalesByAmount,
  mostSalesByQuantity,
}

class ProductReportsScreen extends StatefulWidget {
  const ProductReportsScreen({super.key});

  @override
  State<ProductReportsScreen> createState() => _ProductReportsScreenState();
}

class _ProductReportsScreenState extends State<ProductReportsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<ProductReportData> _products = [];
  List<ProductReportData> _filteredProducts = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  // فلتر التاريخ — الافتراضي من 1/1/2026 حتى اليوم
  DateTime _fromDate = DateTime(2026, 1, 1);
  DateTime _toDate = DateTime.now();

  // خيار الترتيب
  ProductSortOption _sortOption = ProductSortOption.mostSalesByAmount;

  @override
  void initState() {
    super.initState();
    _loadProductReports();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterProducts() {
    final query = _searchController.text.trim().toLowerCase();
    List<ProductReportData> source = List.from(_products);
    if (query.isNotEmpty) {
      source = source.where((p) =>
        p.product.name.toLowerCase().contains(query) ||
        p.product.unit.toLowerCase().contains(query)
      ).toList();
    }
    _applySorting(source);
  }

  void _applySorting(List<ProductReportData> list) {
    switch (_sortOption) {
      case ProductSortOption.mostProfitable:
        list.sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
        break;
      case ProductSortOption.mostSalesByAmount:
        list.sort((a, b) => b.totalSales.compareTo(a.totalSales));
        break;
      case ProductSortOption.mostSalesByQuantity:
        list.sort((a, b) => b.totalQuantitySold.compareTo(a.totalQuantitySold));
        break;
    }
    setState(() { _filteredProducts = list; });
  }

  Future<void> _loadProductReports() async {
    setState(() { _isLoading = true; });
    try {
      final products = await _databaseService.getAllProducts();
      final List<ProductReportData> productReports = [];

      for (final product in products) {
        final salesData = await _databaseService.getProductSalesData(
          product.id!,
          fromDate: _fromDate,
          toDate: _toDate,
        );
        productReports.add(ProductReportData(
          product: product,
          totalQuantitySold: salesData['totalQuantity'] ?? 0.0,
          totalProfit: salesData['totalProfit'] ?? 0.0,
          totalSales: salesData['totalSales'] ?? 0.0,
          averageSellingPrice: salesData['averageSellingPrice'] ?? 0.0,
          totalCost: salesData['totalCost'] ?? 0.0,
          profitMargin: salesData['profitMargin'] ?? 0.0,
        ));
      }

      final visible = productReports.where((p) => p.totalSales > 0 || p.totalQuantitySold > 0).toList();

      setState(() {
        _products = visible;
        _isLoading = false;
      });
      _applySorting(List.from(visible));
    } catch (e) {
      setState(() { _isLoading = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangeInputDialog(
      context: context,
      initialStart: _fromDate,
      initialEnd: _toDate,
      accentColor: const Color(0xFF4CAF50),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _loadProductReports();
    }
  }

  String _formatDate(DateTime d) => DateFormat('d/M/yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('تقارير البضاعة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF4CAF50)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
          ),
        ),
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadProductReports,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          _buildSearchBar(),
          _buildSortBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return GestureDetector(
      onTap: _pickDateRange,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green[700]!, Colors.green[500]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
              child: const Icon(Icons.date_range_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الفترة الزمنية', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  Text(
                    '${_formatDate(_fromDate)}  ←  ${_formatDate(_toDate)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('تغيير', style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: TextField(
        controller: _searchController,
        decoration: const InputDecoration(
          hintText: 'البحث في المنتجات...',
          border: InputBorder.none,
          icon: Icon(Icons.search, color: Color(0xFF4CAF50)),
        ),
        style: const TextStyle(fontSize: 15),
      ),
    );
  }

  Widget _buildSortBar() {
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _sortChip('الأعلى مبيعاً (مبلغ)', ProductSortOption.mostSalesByAmount, Icons.monetization_on_rounded),
            const SizedBox(width: 8),
            _sortChip('الأكثر ربحاً', ProductSortOption.mostProfitable, Icons.trending_up_rounded),
            const SizedBox(width: 8),
            _sortChip('الأكثر مبيعاً (عدد)', ProductSortOption.mostSalesByQuantity, Icons.inventory_2_rounded),
          ],
        ),
      ),
    );
  }

  Widget _sortChip(String label, ProductSortOption option, IconData icon) {
    final isSelected = _sortOption == option;
    return GestureDetector(
      onTap: () {
        setState(() => _sortOption = option);
        _filterProducts();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4CAF50) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 5, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50)));
    }
    if (_filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('لا توجد مبيعات في هذه الفترة', style: TextStyle(fontSize: 16, color: Colors.grey[500])),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.date_range_rounded),
              label: const Text('تغيير الفترة'),
              onPressed: _pickDateRange,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadProductReports,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: _filteredProducts.length,
        itemBuilder: (context, index) => _buildProductCard(_filteredProducts[index], index + 1),
      ),
    );
  }

  Widget _buildProductCard(ProductReportData product, int rank) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green.withOpacity(0.2), width: 1),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailsScreen(product: product.product),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: rank <= 3 ? Colors.amber[600] : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: rank <= 3 ? Colors.white : Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.product.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(
                          'الكمية المباعة: ${_fmt(product.totalQuantitySold)}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: product.profitMargin >= 0 ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: product.profitMargin >= 0 ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      '${product.profitMargin.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: product.profitMargin >= 0 ? Colors.green[700] : Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.trending_up_rounded,
                      title: 'الربح',
                      value: '${_fmt(product.totalProfit.abs())} د.ع',
                      color: product.totalProfit >= 0 ? const Color(0xFF4CAF50) : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.shopping_bag_rounded,
                      title: 'المبيعات',
                      value: '${_fmt(product.totalSales)} د.ع',
                      color: const Color(0xFF2196F3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.price_change_rounded,
                      title: 'التكلفة',
                      value: '${_fmt(product.totalCost)} د.ع',
                      color: Colors.orange[700]!,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (context) => ProductHierarchyDetailsScreen(product: product.product),
                  )),
                  icon: const Icon(Icons.account_tree_rounded, size: 16),
                  label: const Text('عرض النظام الهرمي'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF4CAF50),
                    side: const BorderSide(color: Color(0xFF4CAF50)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem({required IconData icon, required String title, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 3),
          Text(title, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class ProductReportData {
  final Product product;
  final double totalQuantitySold;
  final double totalProfit;
  final double totalSales;
  final double averageSellingPrice;
  final double totalCost;
  final double profitMargin;

  ProductReportData({
    required this.product,
    required this.totalQuantitySold,
    required this.totalProfit,
    required this.totalSales,
    required this.averageSellingPrice,
    required this.totalCost,
    required this.profitMargin,
  });
}
