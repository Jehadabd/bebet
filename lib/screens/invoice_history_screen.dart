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
                    // 🔧 إصلاح: استخدام applied_price بدلاً من unit_price لأنه السعر الفعلي المطبق
                    final appliedPrice = item['applied_price'] ?? item['unit_price'] ?? 0;
                    // 🔧 إصلاح: عرض الكمية الفعلية (quantity) بدلاً من units_in_large_unit
                    final displayQuantity = item['quantity_individual'] ?? item['quantity_large_unit'] ?? 0;
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
                        DataCell(Text(_formatCurrency(appliedPrice))),
                        DataCell(Text(displayQuantity.toString())),
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

  // بناء ويدجت لعرض تغيير واحد بشكل جميل وعصري
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
      beforeStr = '${_formatCurrency(change['before'])} د.ع';
      afterStr = '${_formatCurrency(change['after'])} د.ع';
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Text(
                  field,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color.darken(0.2),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: _buildComparisonBox(
                    title: 'القيمة السابقة',
                    value: beforeStr,
                    color: Colors.red[400]!,
                    isBefore: true,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.keyboard_double_arrow_left, color: Colors.grey[400], size: 24),
                ),
                Expanded(
                  child: _buildComparisonBox(
                    title: 'القيمة الجديدة',
                    value: afterStr,
                    color: Colors.green[600]!,
                    isBefore: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonBox({
    required String title,
    required String value,
    required Color color,
    required bool isBefore,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // إضافة extension لتغميق اللون
  // سأضيفه في نهاية الملف أو أستخدم دالة بديلة

  // بناء ويدجت لعرض تغييرات الأصناف بشكل عصري
  Widget _buildItemsChangeWidget(Map<String, dynamic> change) {
    final itemsChanges = change['itemsChanges'] as List<Map<String, dynamic>>;
    
    // تقسيم التغييرات حسب النوع
    final addedItems = itemsChanges.where((i) => i['type'] == 'added').toList();
    final removedItems = itemsChanges.where((i) => i['type'] == 'removed').toList();
    final modifiedItems = itemsChanges.where((i) => i['type'] == 'modified').toList();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.cyan.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.cyan.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.cyan.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(Icons.inventory_2, size: 20, color: Colors.cyan[800]),
                const SizedBox(width: 12),
                Text(
                  'تغييرات الأصناف',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.cyan[900],
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.cyan[800],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${itemsChanges.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          
          if (addedItems.isNotEmpty) _buildItemCategorySection('عناصر تمت إضافتها', addedItems, Colors.green),
          if (removedItems.isNotEmpty) _buildItemCategorySection('عناصر تم حذفها', removedItems, Colors.red),
          if (modifiedItems.isNotEmpty) _buildItemCategorySection('عناصر تم تعديلها', modifiedItems, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildItemCategorySection(String title, List<Map<String, dynamic>> items, Color color) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((item) => _buildItemChangeRow(item, color)),
        ],
      ),
    );
  }

  Widget _buildItemChangeRow(Map<String, dynamic> item, Color color) {
    final type = item['type'];
    
    if (type == 'modified') {
      final qtyChanged = item['qtyBefore'] != item['qtyAfter'];
      final priceChanged = item['priceBefore'] != item['priceAfter'];
      
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item['name'],
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (qtyChanged) Expanded(child: _buildMiniComp('العدد', item['qtyBefore'], item['qtyAfter'])),
                if (priceChanged) Expanded(child: _buildMiniComp('السعر', _formatCurrency(item['priceBefore']), _formatCurrency(item['priceAfter']))),
                Expanded(child: _buildMiniComp('إجمالي', _formatCurrency(item['totalBefore']), _formatCurrency(item['totalAfter']))),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Icon(type == 'added' ? Icons.add_circle_outline : Icons.remove_circle_outline, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${item['name']} (الكمية: ${item['quantity']})',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Text(
            '${_formatCurrency(item['total'])} د.ع',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniComp(String label, dynamic before, dynamic after) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$before', style: TextStyle(fontSize: 11, color: Colors.red[800], decoration: TextDecoration.lineThrough)),
            const Icon(Icons.arrow_left, size: 12, color: Colors.grey),
            Text('$after', style: TextStyle(fontSize: 11, color: Colors.green[800], fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('سجل تعديلات الفاتورة', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('فاتورة رقم #${widget.invoiceId}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF3F51B5), Color(0xFF5C6BC0)],
            ),
          ),
        ),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
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
        // ملخص جذاب
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[700]!, Colors.blue[500]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.history_edu_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'حالة التعديلات',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      'تم تعديل هذه الفاتورة $editCount مرة',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
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

  // بطاقة النسخة الأصلية بشكل جذاب
  Widget _buildOriginalCard(Map<String, dynamic> snapshot) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.article_rounded, color: Colors.blue[700], size: 24),
        ),
        title: const Text(
          'النسخة الأصلية',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1A237E)),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_month_rounded, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(_formatDate(snapshot['created_at']), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'الإجمالي: ${_formatCurrency(snapshot['total_amount'])} د.ع',
              style: TextStyle(color: Colors.blue[800], fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.chevron_left_rounded, color: Colors.blue),
        ),
        onTap: () => _showSnapshotDetails(snapshot),
      ),
    );
  }

  // بطاقة التعديل بشكل عصري ومنظم
  Widget _buildEditCard(Map<String, dynamic> before, Map<String, dynamic>? after, int editNumber) {
    final changes = after != null ? _compareSnapshots(before, after) : <Map<String, dynamic>>[];
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange[400]!, Colors.orange[700]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '$editNumber',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
          title: Text(
            'التعديل رقم $editNumber',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2E7D32)),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.access_time_rounded, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(_formatDate(after?['created_at'] ?? before['created_at']), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              if (changes.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${changes.length} تغييرات مكتشفة',
                    style: TextStyle(color: Colors.orange[900], fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.expand_more_rounded, color: Colors.grey),
          ),
          children: [
            const Divider(height: 1),
            if (changes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('لم يتم رصد تغييرات جوهرية في القيم', style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
              )
            else
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ...changes.map((change) => _buildChangePreview(change)).toList(),
                    const SizedBox(height: 12),
                    // زر المقارنة التفصيلية
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: after != null ? () => _showChangesDialog(before, after, editNumber) : null,
                        icon: const Icon(Icons.compare_arrows_rounded),
                        label: const Text('رؤية التغييرات بالتفصيل'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // أزرار المعاينة
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('قبل التعديل'),
                      onPressed: () => _showSnapshotDetails(before),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (after != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('بعد التعديل'),
                        onPressed: () => _showSnapshotDetails(after),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
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

// دالة مساعدة لتغميق الألوان
extension ColorDarken on Color {
  Color darken([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}
