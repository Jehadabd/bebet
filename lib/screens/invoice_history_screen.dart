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

  // مقارنة نسختين وإرجاع قائمة التغييرات
  List<Map<String, dynamic>> _compareSnapshots(Map<String, dynamic> before, Map<String, dynamic> after) {
    List<Map<String, dynamic>> changes = [];
    
    // مقارنة الإجمالي
    final totalBefore = _toDouble(before['total_amount']);
    final totalAfter = _toDouble(after['total_amount']);
    if (totalBefore != totalAfter) {
      changes.add({
        'field': 'إجمالي الفاتورة',
        'before': totalBefore,
        'after': totalAfter,
        'icon': Icons.receipt,
        'color': Colors.blue,
      });
    }
    
    // مقارنة المبلغ المسدد
    final paidBefore = _toDouble(before['amount_paid']);
    final paidAfter = _toDouble(after['amount_paid']);
    if (paidBefore != paidAfter) {
      changes.add({
        'field': 'المبلغ المسدد',
        'before': paidBefore,
        'after': paidAfter,
        'icon': Icons.payments,
        'color': Colors.green,
      });
    }
    
    // مقارنة الخصم
    final discountBefore = _toDouble(before['discount']);
    final discountAfter = _toDouble(after['discount']);
    if (discountBefore != discountAfter) {
      changes.add({
        'field': 'الخصم',
        'before': discountBefore,
        'after': discountAfter,
        'icon': Icons.discount,
        'color': Colors.orange,
      });
    }
    
    // مقارنة أجور التحميل
    final loadingBefore = _toDouble(before['loading_fee']);
    final loadingAfter = _toDouble(after['loading_fee']);
    if (loadingBefore != loadingAfter) {
      changes.add({
        'field': 'أجور التحميل',
        'before': loadingBefore,
        'after': loadingAfter,
        'icon': Icons.local_shipping,
        'color': Colors.purple,
      });
    }
    
    // مقارنة نوع الدفع
    final paymentTypeBefore = before['payment_type'] ?? '';
    final paymentTypeAfter = after['payment_type'] ?? '';
    if (paymentTypeBefore != paymentTypeAfter) {
      changes.add({
        'field': 'نوع الدفع',
        'before': paymentTypeBefore,
        'after': paymentTypeAfter,
        'icon': Icons.credit_card,
        'color': Colors.teal,
        'isText': true,
      });
    }
    
    // مقارنة العميل
    final customerBefore = before['customer_name'] ?? '';
    final customerAfter = after['customer_name'] ?? '';
    if (customerBefore != customerAfter) {
      changes.add({
        'field': 'العميل',
        'before': customerBefore,
        'after': customerAfter,
        'icon': Icons.person,
        'color': Colors.indigo,
        'isText': true,
      });
    }
    
    // مقارنة التاريخ
    final dateBefore = before['invoice_date'] ?? '';
    final dateAfter = after['invoice_date'] ?? '';
    if (dateBefore != dateAfter) {
      changes.add({
        'field': 'تاريخ الفاتورة',
        'before': _formatDateOnly(dateBefore),
        'after': _formatDateOnly(dateAfter),
        'icon': Icons.calendar_today,
        'color': Colors.brown,
        'isText': true,
      });
    }
    
    // مقارنة الملاحظات
    final notesBefore = before['notes'] ?? '';
    final notesAfter = after['notes'] ?? '';
    if (notesBefore != notesAfter) {
      changes.add({
        'field': 'الملاحظات',
        'before': notesBefore.isEmpty ? '(فارغ)' : notesBefore,
        'after': notesAfter.isEmpty ? '(فارغ)' : notesAfter,
        'icon': Icons.note,
        'color': Colors.grey,
        'isText': true,
      });
    }
    
    // مقارنة الأصناف
    final itemsChanges = _compareItems(before['items_json'], after['items_json']);
    if (itemsChanges.isNotEmpty) {
      changes.add({
        'field': 'الأصناف',
        'itemsChanges': itemsChanges,
        'icon': Icons.inventory_2,
        'color': Colors.cyan,
        'isItems': true,
      });
    }
    
    return changes;
  }
  
  // مقارنة الأصناف
  List<Map<String, dynamic>> _compareItems(String? beforeJson, String? afterJson) {
    List<Map<String, dynamic>> changes = [];
    
    List<dynamic> itemsBefore = [];
    List<dynamic> itemsAfter = [];
    
    try {
      if (beforeJson != null) itemsBefore = jsonDecode(beforeJson);
      if (afterJson != null) itemsAfter = jsonDecode(afterJson);
    } catch (e) {
      return changes;
    }
    
    // إنشاء خريطة للأصناف قبل وبعد
    Map<String, dynamic> beforeMap = {};
    Map<String, dynamic> afterMap = {};
    
    for (var item in itemsBefore) {
      final key = item['product_name'] ?? item['product_id']?.toString() ?? '';
      beforeMap[key] = item;
    }
    
    for (var item in itemsAfter) {
      final key = item['product_name'] ?? item['product_id']?.toString() ?? '';
      afterMap[key] = item;
    }
    
    // البحث عن الأصناف المحذوفة
    for (var key in beforeMap.keys) {
      if (!afterMap.containsKey(key)) {
        changes.add({
          'type': 'removed',
          'name': key,
          'quantity': beforeMap[key]['quantity_individual'] ?? beforeMap[key]['quantity_large_unit'] ?? 0,
          'total': beforeMap[key]['item_total'] ?? 0,
        });
      }
    }
    
    // البحث عن الأصناف المضافة
    for (var key in afterMap.keys) {
      if (!beforeMap.containsKey(key)) {
        changes.add({
          'type': 'added',
          'name': key,
          'quantity': afterMap[key]['quantity_individual'] ?? afterMap[key]['quantity_large_unit'] ?? 0,
          'total': afterMap[key]['item_total'] ?? 0,
        });
      }
    }
    
    // البحث عن الأصناف المعدلة
    for (var key in beforeMap.keys) {
      if (afterMap.containsKey(key)) {
        final before = beforeMap[key];
        final after = afterMap[key];
        
        final qtyBefore = before['quantity_individual'] ?? before['quantity_large_unit'] ?? 0;
        final qtyAfter = after['quantity_individual'] ?? after['quantity_large_unit'] ?? 0;
        final totalBefore = before['item_total'] ?? 0;
        final totalAfter = after['item_total'] ?? 0;
        final priceBefore = before['unit_price'] ?? 0;
        final priceAfter = after['unit_price'] ?? 0;
        
        if (qtyBefore != qtyAfter || totalBefore != totalAfter || priceBefore != priceAfter) {
          changes.add({
            'type': 'modified',
            'name': key,
            'qtyBefore': qtyBefore,
            'qtyAfter': qtyAfter,
            'totalBefore': totalBefore,
            'totalAfter': totalAfter,
            'priceBefore': priceBefore,
            'priceAfter': priceAfter,
          });
        }
      }
    }
    
    return changes;
  }
  
  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
  
  String _formatDateOnly(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return 'غير محدد';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('yyyy/MM/dd', 'en_US').format(date);
    } catch (e) {
      return dateStr;
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
                  _buildItemsTable(items),
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

  // بناء جدول الأصناف بشكل منظم
  Widget _buildItemsTable(List<dynamic> items) {
    return Card(
      elevation: 0,
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2, size: 18, color: Colors.cyan[700]),
                const SizedBox(width: 8),
                Text(
                  'الأصناف (${items.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const Divider(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 40,
                columnSpacing: 16,
                horizontalMargin: 8,
                headingRowColor: WidgetStateProperty.all(Colors.blue[50]),
                columns: const [
                  DataColumn(label: Text('ت', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('المبلغ', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('ID', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('التفاصيل', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('العدد', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('نوع البيع', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('السعر', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('عدد الوحدات', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: List<DataRow>.generate(
                  items.length,
                  (index) {
                    final item = items[index];
                    final productId = item['product_id']?.toString() ?? '-';
                    final productName = item['product_name'] ?? '-';
                    final quantity = item['quantity_individual'] ?? item['quantity_large_unit'] ?? 0;
                    final saleType = item['sale_type'] ?? (item['quantity_individual'] != null ? 'مفرد' : 'جملة');
                    final unitPrice = item['unit_price'] ?? 0;
                    final unitsInLargeUnit = item['units_in_large_unit'] ?? item['quantity_large_unit'] ?? 0;
                    final itemTotal = item['item_total'] ?? 0;
                    
                    return DataRow(
                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                        if (index.isEven) return Colors.grey[50];
                        return null;
                      }),
                      cells: [
                        DataCell(Text('${index + 1}')),
                        DataCell(Text(
                          _formatCurrency(itemTotal),
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                        )),
                        DataCell(Text(productId)),
                        DataCell(Text(productName, style: const TextStyle(fontWeight: FontWeight.w500))),
                        DataCell(Text(quantity.toString())),
                        DataCell(Text(saleType)),
                        DataCell(Text(_formatCurrency(unitPrice))),
                        DataCell(Text(unitsInLargeUnit.toString())),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
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

  // عرض التغييرات بين نسختين
  void _showChangesDialog(Map<String, dynamic> before, Map<String, dynamic> after, int editNumber) {
    final changes = _compareSnapshots(before, after);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.compare_arrows, color: Colors.blue),
            const SizedBox(width: 8),
            Text('التعديل رقم $editNumber', style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'تاريخ التعديل: ${_formatDate(after['created_at'])}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                if (changes.isEmpty)
                  const Center(
                    child: Text('لا توجد تغييرات مسجلة', style: TextStyle(color: Colors.grey)),
                  )
                else
                  ...changes.map((change) => _buildChangeWidget(change)),
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

  // بناء ويدجت لعرض تغيير واحد
  Widget _buildChangeWidget(Map<String, dynamic> change) {
    if (change['isItems'] == true) {
      return _buildItemsChangeWidget(change);
    }
    
    final isText = change['isText'] == true;
    final icon = change['icon'] as IconData;
    final color = change['color'] as Color;
    final field = change['field'] as String;
    
    String beforeStr, afterStr;
    if (isText) {
      beforeStr = change['before'].toString();
      afterStr = change['after'].toString();
    } else {
      beforeStr = '${_formatCurrency(change['before'])} دينار';
      afterStr = '${_formatCurrency(change['after'])} دينار';
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Text(field, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('قبل:', style: TextStyle(fontSize: 10, color: Colors.red)),
                        Text(beforeStr, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('بعد:', style: TextStyle(fontSize: 10, color: Colors.green)),
                        Text(afterStr, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // بناء ويدجت لعرض تغييرات الأصناف
  Widget _buildItemsChangeWidget(Map<String, dynamic> change) {
    final itemsChanges = change['itemsChanges'] as List<Map<String, dynamic>>;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.cyan.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2, size: 18, color: Colors.cyan[700]),
                const SizedBox(width: 8),
                Text('تغييرات الأصناف', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.cyan[700])),
              ],
            ),
            const SizedBox(height: 8),
            ...itemsChanges.map((itemChange) {
              final type = itemChange['type'];
              IconData icon;
              Color color;
              String label;
              
              switch (type) {
                case 'added':
                  icon = Icons.add_circle;
                  color = Colors.green;
                  label = 'إضافة: ${itemChange['name']} (${itemChange['quantity']} × ${_formatCurrency(itemChange['total'])})';
                  break;
                case 'removed':
                  icon = Icons.remove_circle;
                  color = Colors.red;
                  label = 'حذف: ${itemChange['name']} (${itemChange['quantity']} × ${_formatCurrency(itemChange['total'])})';
                  break;
                case 'modified':
                  icon = Icons.edit;
                  color = Colors.orange;
                  final qtyChanged = itemChange['qtyBefore'] != itemChange['qtyAfter'];
                  final priceChanged = itemChange['priceBefore'] != itemChange['priceAfter'];
                  String details = itemChange['name'];
                  if (qtyChanged) {
                    details += '\n  الكمية: ${itemChange['qtyBefore']} ← ${itemChange['qtyAfter']}';
                  }
                  if (priceChanged) {
                    details += '\n  السعر: ${_formatCurrency(itemChange['priceBefore'])} ← ${_formatCurrency(itemChange['priceAfter'])}';
                  }
                  details += '\n  الإجمالي: ${_formatCurrency(itemChange['totalBefore'])} ← ${_formatCurrency(itemChange['totalAfter'])}';
                  label = 'تعديل: $details';
                  break;
                default:
                  icon = Icons.help;
                  color = Colors.grey;
                  label = 'غير معروف';
              }
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 16, color: color),
                    const SizedBox(width: 8),
                    Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: color))),
                  ],
                ),
              );
            }),
          ],
        ),
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

    // تجميع التعديلات (كل تعديل = before_edit + after_edit)
    List<Map<String, dynamic>> edits = [];
    Map<String, dynamic>? originalSnapshot;
    
    for (int i = 0; i < _snapshots.length; i++) {
      final snapshot = _snapshots[i];
      final type = snapshot['snapshot_type'] ?? '';
      
      if (type == 'original') {
        originalSnapshot = snapshot;
      } else if (type == 'before_edit') {
        // البحث عن after_edit المقابل
        Map<String, dynamic>? afterSnapshot;
        if (i + 1 < _snapshots.length && _snapshots[i + 1]['snapshot_type'] == 'after_edit') {
          afterSnapshot = _snapshots[i + 1];
        }
        edits.add({
          'before': snapshot,
          'after': afterSnapshot,
          'editNumber': edits.length + 1,
        });
      }
    }
    
    // حساب عدد التعديلات الفعلية
    final editCount = edits.length;

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
                  'تم تعديل هذه الفاتورة $editCount مرة',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        // قائمة التعديلات
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: edits.length + (originalSnapshot != null ? 1 : 0),
            itemBuilder: (context, index) {
              // عرض النسخة الأصلية أولاً
              if (originalSnapshot != null && index == 0) {
                return _buildOriginalCard(originalSnapshot!);
              }
              
              final editIndex = originalSnapshot != null ? index - 1 : index;
              final edit = edits[editIndex];
              final before = edit['before'] as Map<String, dynamic>;
              final after = edit['after'] as Map<String, dynamic>?;
              final editNumber = edit['editNumber'] as int;
              
              return _buildEditCard(before, after, editNumber);
            },
          ),
        ),
      ],
    );
  }

  // بطاقة النسخة الأصلية
  Widget _buildOriginalCard(Map<String, dynamic> snapshot) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 2,
      color: Colors.blue[50],
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.2),
          child: const Icon(Icons.description, color: Colors.blue, size: 20),
        ),
        title: const Text('📄 النسخة الأصلية', style: TextStyle(fontWeight: FontWeight.bold)),
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
  }

  // بطاقة التعديل مع التغييرات
  Widget _buildEditCard(Map<String, dynamic> before, Map<String, dynamic>? after, int editNumber) {
    final changes = after != null ? _compareSnapshots(before, after) : <Map<String, dynamic>>[];
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      elevation: 2,
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withOpacity(0.2),
          child: Text(
            '$editNumber',
            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text('التعديل رقم $editNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_formatDate(after?['created_at'] ?? before['created_at'])),
            if (changes.isNotEmpty)
              Text(
                '${changes.length} تغيير',
                style: const TextStyle(color: Colors.orange, fontSize: 12),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.compare_arrows, size: 20),
              tooltip: 'عرض التغييرات',
              onPressed: after != null ? () => _showChangesDialog(before, after, editNumber) : null,
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: [
          if (changes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('لا توجد تغييرات مسجلة', style: TextStyle(color: Colors.grey)),
            )
          else
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: changes.map((change) => _buildChangePreview(change)).toList(),
              ),
            ),
          // أزرار لعرض التفاصيل
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('قبل التعديل'),
                  onPressed: () => _showSnapshotDetails(before),
                ),
                if (after != null)
                  TextButton.icon(
                    icon: const Icon(Icons.visibility, size: 16),
                    label: const Text('بعد التعديل'),
                    onPressed: () => _showSnapshotDetails(after),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // معاينة مختصرة للتغيير
  Widget _buildChangePreview(Map<String, dynamic> change) {
    if (change['isItems'] == true) {
      final itemsChanges = change['itemsChanges'] as List<Map<String, dynamic>>;
      return ListTile(
        dense: true,
        leading: Icon(Icons.inventory_2, size: 18, color: Colors.cyan[700]),
        title: Text('تغييرات الأصناف (${itemsChanges.length})', style: const TextStyle(fontSize: 13)),
      );
    }
    
    final icon = change['icon'] as IconData;
    final color = change['color'] as Color;
    final field = change['field'] as String;
    final isText = change['isText'] == true;
    
    String changeText;
    if (isText) {
      changeText = '${change['before']} ← ${change['after']}';
    } else {
      changeText = '${_formatCurrency(change['before'])} ← ${_formatCurrency(change['after'])}';
    }
    
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 18, color: color),
      title: Text(field, style: const TextStyle(fontSize: 13)),
      subtitle: Text(changeText, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    );
  }
}
