// screens/invoice_history_screen.dart
// شاشة عرض سجل تعديلات الفاتورة

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../services/database_service.dart';

class InvoiceHistoryScreen extends StatefulWidget {
  final int invoiceId;
  final String? customerName;

  const InvoiceHistoryScreen({
    super.key,
    required this.invoiceId,
    this.customerName,
  });

  @override
  State<InvoiceHistoryScreen> createState() => _InvoiceHistoryScreenState();
}

class _InvoiceHistoryScreenState extends State<InvoiceHistoryScreen> {
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _snapshots = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSnapshots();
  }

  Future<void> _loadSnapshots() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final snapshots = await _db.getInvoiceSnapshots(widget.invoiceId);
      setState(() {
        _snapshots = snapshots;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'خطأ في تحميل سجل التعديلات: $e';
        _isLoading = false;
      });
    }
  }


  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'غير محدد';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy/MM/dd - HH:mm', 'en_US').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  String _getSnapshotTypeLabel(String type) {
    switch (type) {
      case 'original':
        return '📄 النسخة الأصلية';
      case 'before_edit':
        return '✏️ قبل التعديل';
      case 'after_edit':
        return '✅ بعد التعديل';
      default:
        return type;
    }
  }

  Color _getSnapshotColor(String type) {
    switch (type) {
      case 'original':
        return Colors.blue;
      case 'before_edit':
        return Colors.orange;
      case 'after_edit':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatCurrency(dynamic value) {
    if (value == null) return '0';
    final number = (value is num) ? value : double.tryParse(value.toString()) ?? 0;
    return NumberFormat('#,##0', 'en_US').format(number);
  }

  void _showSnapshotDetails(Map<String, dynamic> snapshot) {
    // تحليل الأصناف
    List<dynamic> items = [];
    try {
      if (snapshot['items_json'] != null) {
        items = jsonDecode(snapshot['items_json']);
      }
    } catch (e) {
      print('خطأ في تحليل الأصناف: $e');
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.receipt_long,
              color: _getSnapshotColor(snapshot['snapshot_type'] ?? ''),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getSnapshotTypeLabel(snapshot['snapshot_type'] ?? ''),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInfoCard('معلومات الفاتورة', [
                  _buildDetailRow('العميل', snapshot['customer_name'] ?? '-'),
                  _buildDetailRow('الهاتف', snapshot['customer_phone'] ?? '-'),
                  _buildDetailRow('التاريخ', _formatDate(snapshot['invoice_date'])),
                  _buildDetailRow('نوع الدفع', snapshot['payment_type'] ?? '-'),
                ]),
                const SizedBox(height: 12),
                _buildInfoCard('المبالغ', [
                  _buildDetailRow('الإجمالي', '${_formatCurrency(snapshot['total_amount'])} دينار'),
                  _buildDetailRow('الخصم', '${_formatCurrency(snapshot['discount'])} دينار'),
                  _buildDetailRow('أجور التحميل', '${_formatCurrency(snapshot['loading_fee'])} دينار'),
                  _buildDetailRow('المدفوع', '${_formatCurrency(snapshot['amount_paid'])} دينار'),
                ]),
                if (items.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoCard('الأصناف (${items.length})', [
                    ...items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${item['product_name'] ?? '-'} × ${item['quantity_individual'] ?? item['quantity_large_unit'] ?? 0}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            '${_formatCurrency(item['item_total'])}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    )),
                  ]),
                ],
                const SizedBox(height: 8),
                Text(
                  'تاريخ الحفظ: ${_formatDate(snapshot['created_at'])}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (snapshot['notes'] != null && snapshot['notes'].toString().isNotEmpty)
                  Text(
                    'ملاحظات: ${snapshot['notes']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      elevation: 0,
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('سجل تعديلات الفاتورة #${widget.invoiceId}'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: _loadSnapshots,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFF3F51B5)),
            SizedBox(height: 16),
            Text('جاري تحميل سجل التعديلات...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadSnapshots,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_snapshots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 80, color: Colors.green[400]),
            const SizedBox(height: 16),
            const Text(
              'لم يتم تعديل هذه الفاتورة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'الفاتورة بحالتها الأصلية منذ إنشائها',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ملخص
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue[50],
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'تم تعديل هذه الفاتورة ${_snapshots.length} مرة',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        // قائمة النسخ
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _snapshots.length,
            itemBuilder: (context, index) {
              final snapshot = _snapshots[index];
              final snapshotType = snapshot['snapshot_type'] ?? '';
              final versionNumber = snapshot['version_number'] ?? (index + 1);
              
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                elevation: 2,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getSnapshotColor(snapshotType).withOpacity(0.2),
                    child: Text(
                      '$versionNumber',
                      style: TextStyle(
                        color: _getSnapshotColor(snapshotType),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    _getSnapshotTypeLabel(snapshotType),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_formatDate(snapshot['created_at'])),
                      Text(
                        'الإجمالي: ${_formatCurrency(snapshot['total_amount'])} دينار',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => _showSnapshotDetails(snapshot),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
