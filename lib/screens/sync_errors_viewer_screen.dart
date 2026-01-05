// lib/screens/sync_errors_viewer_screen.dart
// شاشة عرض سجل الأخطاء المكتشفة في المزامنة

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import '../services/database_service.dart';
import '../services/firebase_sync/cross_device_verifier.dart';

class SyncErrorsViewerScreen extends StatefulWidget {
  const SyncErrorsViewerScreen({super.key});

  @override
  State<SyncErrorsViewerScreen> createState() => _SyncErrorsViewerScreenState();
}

class _SyncErrorsViewerScreenState extends State<SyncErrorsViewerScreen> {
  final DatabaseService _db = DatabaseService();
  final CrossDeviceVerifier _verifier = CrossDeviceVerifier.instance;
  final NumberFormat _nf = NumberFormat('#,##0', 'en_US');
  
  List<Map<String, dynamic>> _unresolvedErrors = [];
  List<Map<String, dynamic>> _resolvedErrors = [];
  bool _isLoading = true;
  bool _showResolved = false;

  @override
  void initState() {
    super.initState();
    _loadErrors();
  }

  Future<void> _loadErrors() async {
    setState(() => _isLoading = true);
    
    try {
      final db = await _db.database;
      
      _unresolvedErrors = await db.query(
        'sync_integrity_errors',
        where: 'resolved = 0',
        orderBy: 'detected_at DESC',
      );
      
      _resolvedErrors = await db.query(
        'sync_integrity_errors',
        where: 'resolved = 1',
        orderBy: 'resolved_at DESC',
        limit: 50, // آخر 50 خطأ محلول
      );
      
    } catch (e) {
      print('❌ خطأ في تحميل سجل الأخطاء: $e');
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

  Future<void> _markAsResolved(int errorId) async {
    final notesController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعليم كمحلول'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('هل تم حل هذا الاختلاف؟'),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _verifier.markErrorAsResolved(errorId, notes: notesController.text);
      await _loadErrors();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تعليم الخطأ كمحلول'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _performManualCheck() async {
    setState(() => _isLoading = true);
    
    try {
      final mismatches = await _verifier.performManualVerification();
      
      if (mounted) {
        if (mismatches.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ جميع الأرصدة متطابقة!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ تم اكتشاف ${mismatches.length} اختلاف'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
      
      await _loadErrors();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الفحص: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final errors = _showResolved ? _resolvedErrors : _unresolvedErrors;
    
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('سجل الأخطاء المكتشفة'),
          backgroundColor: Colors.red[700],
          foregroundColor: Colors.white,
          actions: [
            // زر الفحص اليدوي
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'فحص الآن',
              onPressed: _performManualCheck,
            ),
            // تبديل عرض المحلولة
            IconButton(
              icon: Icon(_showResolved ? Icons.visibility_off : Icons.visibility),
              tooltip: _showResolved ? 'إخفاء المحلولة' : 'عرض المحلولة',
              onPressed: () {
                setState(() => _showResolved = !_showResolved);
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
                  // القائمة
                  Expanded(
                    child: errors.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: errors.length,
                            itemBuilder: (context, index) {
                              return _buildErrorCard(errors[index]);
                            },
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
      color: Colors.red[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'غير محلولة',
            '${_unresolvedErrors.length}',
            Icons.warning,
            Colors.orange,
          ),
          _buildStatItem(
            'محلولة',
            '${_resolvedErrors.length}',
            Icons.check_circle,
            Colors.green,
          ),
          _buildStatItem(
            'الإجمالي',
            '${_unresolvedErrors.length + _resolvedErrors.length}',
            Icons.list,
            Colors.blue,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _showResolved ? Icons.history : Icons.check_circle_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _showResolved
                ? 'لا توجد أخطاء محلولة'
                : '✅ لا توجد أخطاء مكتشفة',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          if (!_showResolved) ...[
            const SizedBox(height: 8),
            Text(
              'جميع الأرصدة متطابقة بين الأجهزة',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorCard(Map<String, dynamic> error) {
    final customerName = error['customer_name'] as String? ?? 'غير معروف';
    final localBalance = (error['local_balance'] as num?)?.toDouble() ?? 0;
    final remoteBalance = (error['remote_balance'] as num?)?.toDouble() ?? 0;
    final difference = (error['difference'] as num?)?.toDouble() ?? 0;
    final detectedAt = error['detected_at'] as String?;
    final resolvedAt = error['resolved_at'] as String?;
    final notes = error['notes'] as String?;
    final isResolved = error['resolved'] == 1;
    final errorId = error['id'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isResolved ? Colors.green[50] : Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العنوان
            Row(
              children: [
                Icon(
                  isResolved ? Icons.check_circle : Icons.warning,
                  color: isResolved ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    customerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!isResolved)
                  TextButton.icon(
                    onPressed: () => _markAsResolved(errorId),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('حل'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green,
                    ),
                  ),
              ],
            ),
            const Divider(),
            // تفاصيل الأرصدة
            Row(
              children: [
                Expanded(
                  child: _buildBalanceColumn(
                    'رصيده هنا',
                    localBalance,
                    Colors.blue,
                  ),
                ),
                const Icon(Icons.compare_arrows, color: Colors.grey),
                Expanded(
                  child: _buildBalanceColumn(
                    'رصيده هناك',
                    remoteBalance,
                    Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // الفرق
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.difference, size: 16, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    'الفرق: ${_nf.format(difference)} د.ع',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // التواريخ
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  'اكتُشف: ${_formatDate(detectedAt)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
            if (isResolved && resolvedAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.check, size: 14, color: Colors.green[500]),
                  const SizedBox(width: 4),
                  Text(
                    'حُل: ${_formatDate(resolvedAt)}',
                    style: TextStyle(fontSize: 11, color: Colors.green[600]),
                  ),
                ],
              ),
            ],
            // الملاحظات
            if (notes != null && notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.note, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        notes,
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceColumn(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 4),
        Text(
          '${_nf.format(value)} د.ع',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
