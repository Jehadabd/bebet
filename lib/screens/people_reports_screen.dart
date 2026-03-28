// screens/people_reports_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/customer.dart';
import 'person_details_screen.dart';
import '../widgets/date_range_input_dialog.dart';
import 'package:intl/intl.dart';

enum PeopleSortOption {
  mostProfitable,
  mostSalesByAmount,
  mostInvoices,
}

class PeopleReportsScreen extends StatefulWidget {
  const PeopleReportsScreen({super.key});

  @override
  State<PeopleReportsScreen> createState() => _PeopleReportsScreenState();
}

class _PeopleReportsScreenState extends State<PeopleReportsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  List<PersonReportData> _people = [];
  List<PersonReportData> _filteredPeople = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  late final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  String _fmt(num v) => _nf.format(v);

  // فلتر التاريخ — الافتراضي من 1/1/2026 حتى اليوم
  DateTime _fromDate = DateTime(2026, 1, 1);
  DateTime _toDate = DateTime.now();

  // خيار الترتيب
  PeopleSortOption _sortOption = PeopleSortOption.mostSalesByAmount;

  @override
  void initState() {
    super.initState();
    _loadPeopleReports();
    _searchController.addListener(_filterPeople);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterPeople() {
    final query = _searchController.text.trim().toLowerCase();
    List<PersonReportData> source = List.from(_people);
    if (query.isNotEmpty) {
      source = source.where((person) {
        return person.customer.name.toLowerCase().contains(query) ||
               person.customer.phone?.toLowerCase().contains(query) == true ||
               person.customer.address?.toLowerCase().contains(query) == true;
      }).toList();
    }
    _applySorting(source);
  }

  void _applySorting(List<PersonReportData> list) {
    switch (_sortOption) {
      case PeopleSortOption.mostProfitable:
        list.sort((a, b) => b.totalProfit.compareTo(a.totalProfit));
        break;
      case PeopleSortOption.mostSalesByAmount:
        list.sort((a, b) => b.totalSales.compareTo(a.totalSales));
        break;
      case PeopleSortOption.mostInvoices:
        list.sort((a, b) => b.totalInvoices.compareTo(a.totalInvoices));
        break;
    }
    setState(() {
      _filteredPeople = list;
    });
  }

  Future<void> _loadPeopleReports() async {
    setState(() { _isLoading = true; });

    try {
      try { await _databaseService.updateOldInvoicesWithCustomerIds(); } catch (_) {}

      final customers = await _databaseService.getAllCustomers();
      final List<PersonReportData> peopleReports = [];

      for (final customer in customers) {
        final profitData = await _databaseService.getCustomerProfitData(
          customer.id!,
          fromDate: _fromDate,
          toDate: _toDate,
        );

        peopleReports.add(PersonReportData(
          customer: customer,
          totalProfit: profitData['totalProfit'] ?? 0.0,
          totalSales: profitData['totalSales'] ?? 0.0,
          totalInvoices: profitData['totalInvoices'] ?? 0,
          totalTransactions: profitData['totalTransactions'] ?? 0,
        ));
      }

      final visiblePeople = peopleReports
          .where((p) => p.totalInvoices > 0 || p.totalSales > 0)
          .toList();

      setState(() {
        _people = visiblePeople;
        _isLoading = false;
      });
      _applySorting(List.from(visiblePeople));
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
      accentColor: const Color(0xFF2196F3),
    );
    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      _loadPeopleReports();
    }
  }

  String _formatDate(DateTime d) => DateFormat('d/M/yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('تقارير الأشخاص', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF2196F3)],
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
            onPressed: _loadPeopleReports,
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

  // ── شريط فلتر التاريخ ─────────────────────────────
  Widget _buildFilterBar() {
    return GestureDetector(
      onTap: _pickDateRange,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue[700]!, Colors.blue[500]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
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

  // ── شريط البحث ─────────────────────────────────────
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
          hintText: 'البحث في الأشخاص...',
          border: InputBorder.none,
          icon: Icon(Icons.search, color: Color(0xFF2196F3)),
        ),
        style: const TextStyle(fontSize: 15),
      ),
    );
  }

  // ── شريط الترتيب ───────────────────────────────────
  Widget _buildSortBar() {
    return Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _sortChip('الأعلى مبيعاً (مبلغ)', PeopleSortOption.mostSalesByAmount, Icons.monetization_on_rounded),
            const SizedBox(width: 8),
            _sortChip('الأكثر ربحاً', PeopleSortOption.mostProfitable, Icons.trending_up_rounded),
            const SizedBox(width: 8),
            _sortChip('الأكثر فواتير', PeopleSortOption.mostInvoices, Icons.receipt_long_rounded),
          ],
        ),
      ),
    );
  }

  Widget _sortChip(String label, PeopleSortOption option, IconData icon) {
    final isSelected = _sortOption == option;
    return GestureDetector(
      onTap: () {
        setState(() => _sortOption = option);
        _filterPeople();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.white,
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

  // ── جسم الشاشة ─────────────────────────────────────
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF2196F3)));
    }
    if (_filteredPeople.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline_rounded, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('لا توجد بيانات في هذه الفترة', style: TextStyle(fontSize: 16, color: Colors.grey[500])),
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
      onRefresh: _loadPeopleReports,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: _filteredPeople.length,
        itemBuilder: (context, index) => _buildPersonCard(_filteredPeople[index], index + 1),
      ),
    );
  }

  Widget _buildPersonCard(PersonReportData person, int rank) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green.withOpacity(0.2), width: 1),
      ),
      child: InkWell(
        onTap: () => _navigateToPersonDetails(person),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // رقم الترتيب
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
                        Text(
                          person.customer.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'الفواتير: ${person.totalInvoices}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_left_rounded, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.trending_up_rounded,
                      title: 'الربح',
                      value: '${person.totalProfit >= 0 ? _fmt(person.totalProfit) : _fmt(-person.totalProfit)} د.ع',
                      color: person.totalProfit >= 0 ? const Color(0xFF4CAF50) : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.shopping_bag_rounded,
                      title: 'المبيعات',
                      value: '${_fmt(person.totalSales)} د.ع',
                      color: const Color(0xFF2196F3),
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

  Widget _buildInfoItem({required IconData icon, required String title, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Future<void> _navigateToPersonDetails(PersonReportData person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PersonDetailsScreen(customer: person.customer)),
    );
    if (!mounted) return;
    _searchController.text = '';
    FocusScope.of(context).unfocus();
    setState(() { _filteredPeople = _people; });
  }
}

class PersonReportData {
  final Customer customer;
  final double totalProfit;
  final double totalSales;
  final int totalInvoices;
  final int totalTransactions;

  PersonReportData({
    required this.customer,
    required this.totalProfit,
    required this.totalSales,
    required this.totalInvoices,
    required this.totalTransactions,
  });
}
