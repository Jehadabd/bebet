// screens/people_reports_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/customer.dart';
import 'person_details_screen.dart';

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
    if (query.isEmpty) {
      setState(() {
        _filteredPeople = _people;
      });
    } else {
      setState(() {
        _filteredPeople = _people.where((person) {
          return person.customer.name.toLowerCase().contains(query) ||
                 person.customer.phone?.toLowerCase().contains(query) == true ||
                 person.customer.address?.toLowerCase().contains(query) == true;
        }).toList();
      });
    }
  }

  Future<void> _loadPeopleReports() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('=== تحميل سجل الديون ===');
      final customers = await _databaseService.getAllCustomers();
      print('عدد العملاء: ${customers.length}');
      final List<PersonReportData> peopleReports = [];

      for (final customer in customers) {
        print('--- عميل: ${customer.name} ---');
        print('معرف العميل: ${customer.id}');
        print('رقم الهاتف: ${customer.phone ?? "غير متوفر"}');
        print('العنوان: ${customer.address ?? "غير متوفر"}');
        print('الدين الحالي: ${customer.currentTotalDebt}');
        print('تاريخ الإنشاء: ${customer.createdAt}');
        print('آخر تعديل: ${customer.lastModifiedAt}');
        
        final profitData =
            await _databaseService.getCustomerProfitData(customer.id!);

        peopleReports.add(PersonReportData(
          customer: customer,
          totalProfit: profitData['totalProfit'] ?? 0.0,
          totalSales: profitData['totalSales'] ?? 0.0,
          totalInvoices: profitData['totalInvoices'] ?? 0,
          totalTransactions: profitData['totalTransactions'] ?? 0,
        ));
        
        print('إجمالي المبيعات: ${profitData['totalSales'] ?? 0.0}');
        print('إجمالي الأرباح: ${profitData['totalProfit'] ?? 0.0}');
        print('عدد الفواتير: ${profitData['totalInvoices'] ?? 0}');
        print('عدد المعاملات: ${profitData['totalTransactions'] ?? 0}');
        
        // جلب معاملات الدين للعميل
        try {
          final debtTransactions = await _databaseService.getDebtTransactionsForCustomer(customer.id!);
          print('معاملات الدين: ${debtTransactions.length}');
          for (int i = 0; i < debtTransactions.length; i++) {
            final transaction = debtTransactions[i];
            print('  معاملة ${i + 1}: ${transaction.description} - ${transaction.amountChanged} - ${transaction.newBalanceAfterTransaction}');
          }
        } catch (e) {
          print('خطأ في جلب معاملات الدين: $e');
        }
        
        print('--- نهاية عميل: ${customer.name} ---');
      }
      
      print('=== نهاية تحميل سجل الديون ===');

      // ترتيب الأشخاص من الأكثر سحباً (أعلى قيمة مبيعات)
      peopleReports.sort((a, b) => b.totalSales.compareTo(a.totalSales));

      setState(() {
        _people = peopleReports;
        _filteredPeople = peopleReports; // Initialize filtered list
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
        title: const Text('تقارير الأشخاص', style: TextStyle(fontSize: 24)),
        centerTitle: true,
        backgroundColor: const Color(0xFF2196F3),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPeopleReports,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF2196F3),
              ),
            )
          : Column(
              children: [
                // حقل البحث
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'البحث في الأشخاص...',
                      border: InputBorder.none,
                      icon: Icon(Icons.search, color: Color(0xFF2196F3)),
                      suffixIcon: Icon(Icons.filter_list, color: Color(0xFF2196F3)),
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                // قائمة الأشخاص
                Expanded(
                  child: _filteredPeople.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people,
                                size: 80,
                                color: Color(0xFFCCCCCC),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'لا توجد أشخاص',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF666666),
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadPeopleReports,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredPeople.length,
                            itemBuilder: (context, index) {
                              final personData = _filteredPeople[index];
                              return _buildPersonCard(personData);
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildPersonCard(PersonReportData person) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        onTap: () => _navigateToPersonDetails(person),
        borderRadius: BorderRadius.circular(16),
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
                      Icons.person,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.customer.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'عدد الفواتير: ${person.totalInvoices}',
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
              Row(
                children: [
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.trending_up,
                      title: 'الربح',
                      value:
                          '${person.totalProfit >= 0 ? person.totalProfit.toStringAsFixed(2) : (-person.totalProfit).toStringAsFixed(2)} د.ع',
                      color: const Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildInfoItem(
                      icon: Icons.shopping_cart,
                      title: 'المبيعات',
                      value: '${person.totalSales.toStringAsFixed(2)} د.ع',
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

  Future<void> _navigateToPersonDetails(PersonReportData person) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PersonDetailsScreen(
          customer: person.customer,
        ),
      ),
    );
    if (!mounted) return;
    // بعد الرجوع: امسح البحث وأعد القائمة كاملة كأنها أول مرة
    _searchController.text = '';
    FocusScope.of(context).unfocus();
    setState(() {
      _filteredPeople = _people;
    });
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
