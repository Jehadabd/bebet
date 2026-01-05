// lib/screens/sync_history_viewer_screen.dart
// شاشة عرض سجلات عمليات المزامنة (ناجحة/فاشلة)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import '../services/database_service.dart';

class SyncHistoryViewerScreen extends StatefulWidget {
  const SyncHistoryViewerScreen({super.key});

  @override
  State<SyncHistoryViewerScreen> createState() => _SyncHistoryViewerScreenState();
}

class _SyncHistoryViewerScreenState extends State<SyncHistoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _db = DatabaseService();
  final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  
  // السنة المحددة
  int _selectedYear = DateTime.now().year;
  
  // البيانات
  List<Map<String, dynamic>> _successByName = [];
  List<Map<String, dynamic>> _successByDate = [];
  List<Map<String, dynamic>> _failedByName = [];
  List<Map<String, dynamic>> _failedByDate = [];
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final db = await _db.database;
      
      // جلب العمليات الناجحة مرتبة بالاسم
      _successByName = await db.query(
        'sync_operations_history',
        where: 'year = ? AND status = ?',
        whereArgs: [_selectedYear, 'success'],
        orderBy: 'customer_name ASC, created_at DESC',
      );
      
      // جلب العمليات الناجحة مرتبة بالتاريخ
      _successByDate = await db.query(
        'sync_operations_history',
        where: 'year = ? AND status = ?',
        whereArgs: [_selectedYear, 'success'],
        orderBy: 'created_at DESC',
      );
      
      // جلب العمليات الفاشلة مرتبة بالاسم
      _failedByName = await db.query(
        'sync_operations_history',
        where: 'year = ? AND status = ?',
        whereArgs: [_selectedYear, 'failed'],
        orderBy: 'customer_name ASC, created_at DESC',
      );
      
      // جلب العمليات الفاشلة مرتبة بالتاريخ
      _failedByDate = await db.query(
        'sync_operations_history',
        where: 'year = ? AND status = ?',
        whereArgs: [_selectedYear, 'failed'],
        orderBy: 'created_at DESC',
      );
      
    } catch (e) {
      print('❌ خطأ في تحميل سجل المزامنة: $e');
    }
    
    setState(() => _isLoading = false);
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy-MM-dd HH:mm', 'ar').format(date);
    } catch (_) {
      return dateStr;
    }
  }

  String _getOperationTypeLabel(String? type) {
    switch (type) {
      case 'debt':
        return 'إضافة دين';
      case 'payment':
        return 'تسديد';
      default:
        return type ?? 'غير محدد';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('سجل عمليات المزامنة'),
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(text: 'ناجحة (اسم)'),
              Tab(text: 'ناجحة (تاريخ)'),
              Tab(text: 'فاشلة (اسم)'),
              Tab(text: 'فاشلة (تاريخ)'),
            ],
          ),
          actions: [
            // اختيار السنة
            PopupMenuButton<int>(
              icon: const Icon(Icons.calendar_today),
              tooltip: 'اختر السنة',
              onSelected: (year) {
                setState(() => _selectedYear = year);
                _loadData();
              },
              itemBuilder: (context) {
                final currentYear = DateTime.now().year;
                return List.generate(5, (index) {
                  final year = currentYear - index;
                  return PopupMenuItem(
                    value: year,
                    child: Row(
                      children: [
                        if (year == _selectedYear)
                          const Icon(Icons.check, color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text('$year'),
                      ],
                    ),
                  );
                });
              },
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // شريط الإحصائيات
                  _buildStatsBar(),
                  // التبويبات
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOperationsList(_successByName, Colors.green),
                        _buildOperationsList(_successByDate, Colors.green),
                        _buildOperationsList(_failedByName, Colors.red),
                        _buildOperationsList(_failedByDate, Colors.red),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'السنة',
            '$_selectedYear',
            Icons.calendar_today,
            Colors.blue,
          ),
          _buildStatItem(
            'ناجحة',
            '${_successByName.length}',
            Icons.check_circle,
            Colors.green,
          ),
          _buildStatItem(
            'فاشلة',
            '${_failedByName.length}',
            Icons.error,
            Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildOperationsList(List<Map<String, dynamic>> operations, Color color) {
    if (operations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'لا توجد عمليات',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: operations.length,
      itemBuilder: (context, index) {
        final op = operations[index];
        return _buildOperationCard(op, color);
      },
    );
  }

  Widget _buildOperationCard(Map<String, dynamic> op, Color color) {
    final customerName = op['customer_name'] as String? ?? 'غير معروف';
    final operationType = op['operation_type'] as String?;
    final amount = (op['amount'] as num?)?.toDouble() ?? 0;
    final status = op['status'] as String?;
    final errorMessage = op['error_message'] as String?;
    final createdAt = op['created_at'] as String?;
    final sourceDeviceId = op['source_device_id'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(
            status == 'success' ? Icons.check : Icons.error,
            color: color,
          ),
        ),
        title: Text(
          customerName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_getOperationTypeLabel(operationType)),
                const SizedBox(width: 8),
                Text(
                  '${_nf.format(amount)} د.ع',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Text(
              _formatDate(createdAt),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
            if (errorMessage != null && errorMessage.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  errorMessage,
                  style: TextStyle(fontSize: 11, color: Colors.red[700]),
                ),
              ),
          ],
        ),
        trailing: sourceDeviceId != null
            ? Tooltip(
                message: 'من جهاز: ${sourceDeviceId.substring(0, 8)}...',
                child: const Icon(Icons.devices, size: 16, color: Colors.grey),
              )
            : null,
      ),
    );
  }
}
