import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/gemini_service.dart';
import '../services/suppliers_service.dart';
import '../models/supplier.dart';
import '../services/database_service.dart';
import '../models/product.dart';

class AiImportReviewScreen extends StatefulWidget {
  final Uint8List fileBytes;
  final String mimeType; // image/png, image/jpeg, application/pdf
  final String type; // 'invoice' | 'receipt'
  final String apiKey;
  final int? supplierId; // إن تم تمرير المورد

  const AiImportReviewScreen({
    Key? key,
    required this.fileBytes,
    required this.mimeType,
    required this.type,
    required this.apiKey,
    this.supplierId,
  }) : super(key: key);

  @override
  State<AiImportReviewScreen> createState() => _AiImportReviewScreenState();
}

class _AiImportReviewScreenState extends State<AiImportReviewScreen> {
  Map<String, dynamic>? _extracted;
  bool _loading = true;
  String? _error;
  final SuppliersService _suppliersService = SuppliersService();
  List<Supplier> _suppliers = const [];
  int? _selectedSupplierId;
  Set<String> _knownProductNames = {};
  Set<String> _knownProductNamesNorm = {};
  String _paymentType = 'دين';
  final NumberFormat _nf = NumberFormat('#,##0.##', 'en');

  String _fmt(num v) => _nf.format(v);
  double? _supplierCurrentBalance; // الرصيد قبل العملية

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Load suppliers if supplierId not passed
      if (widget.supplierId == null) {
        await _suppliersService.ensureTables();
        final list = await _suppliersService.getAllSuppliers();
        if (!mounted) return;
        _suppliers = list;
      } else {
        _selectedSupplierId = widget.supplierId;
        await _loadSupplierBalance(_selectedSupplierId!);
      }
      // Load known product names for lookup
      try {
        final db = await DatabaseService().database;
        final rows = await db.query('products', columns: ['name']);
        if (!mounted) return;
        final names = rows
            .map((e) => (e['name']?.toString().trim() ?? ''))
            .where((s) => s.isNotEmpty)
            .toSet();
        _knownProductNames = names;
        _knownProductNamesNorm = names.map(_normalizeName).toSet();
      } catch (_) {}
    } catch (e) {
      if (!mounted) return;
      _error = e.toString();
    }
    await _runExtraction();
  }

  Future<void> _loadSupplierBalance(int supplierId) async {
    try {
      final db = await DatabaseService().database;
      final rows = await db.query('suppliers', columns: ['current_balance'], where: 'id = ?', whereArgs: [supplierId], limit: 1);
      if (!mounted) return;
      _supplierCurrentBalance = rows.isNotEmpty ? ((rows.first['current_balance'] as num?)?.toDouble() ?? 0.0) : 0.0;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      _supplierCurrentBalance = null;
      setState(() {});
    }
  }

  Future<void> _runExtraction() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = GeminiService(apiKey: widget.apiKey);
      final result = await service.extractInvoiceOrReceiptStructured(
        fileBytes: widget.fileBytes,
        fileMimeType: widget.mimeType,
        extractType: widget.type,
      );
      if (!mounted) return;
      final normalized = _normalizeResult(result);
      // طباعة العناصر المستخرجة ومطابقتها مع المنتجات في القاعدة للتشخيص في الـ terminal
      if (widget.type == 'invoice') {
        final items = (normalized['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        print('DEBUG AI ITEMS: extracted ${items.length} items');
        for (final it in items) {
          final name = (it['name'] ?? '').toString();
          final norm = _normalizeName(name);
          final exact = _knownProductNames.contains(name.trim());
          final normHit = _knownProductNamesNorm.contains(norm);
          bool partial = false;
          if (!exact && !normHit) {
            for (final k in _knownProductNamesNorm) {
              if (k.contains(norm) || norm.contains(k)) { partial = true; break; }
            }
          }
          print('DEBUG AI ITEM: name="$name" norm="$norm" => exact:$exact norm:$normHit partial:$partial');
        }
      }
      setState(() {
        _extracted = normalized;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _normalizeResult(Map<String, dynamic> raw) {
    // يدعم تنويعات شائعة في مفاتيح JSON
    if (widget.type == 'invoice') {
      final invoiceDate = raw['invoice_date'] ?? raw['date'] ?? raw['invoiceDate'];
      final invoiceNumber = raw['invoice_number'] ?? raw['number'] ?? raw['invoiceNumber'];
      final totals = raw['totals'] ?? {};
      final grand = totals is Map
          ? (totals['grand_total'] ?? totals['total'] ?? totals['final'])
          : (raw['grand_total'] ?? raw['total'] ?? raw['final_total']);
      // استنتاج المدفوع والمتبقي
      double amountPaid = _toDouble(raw['amount_paid'] ?? raw['paid'] ?? raw['paid_amount'] ?? raw['amountReceived']);
      double remaining = _toDouble(raw['remaining'] ?? raw['balance_due'] ?? raw['due'] ?? raw['rest'] ?? raw['متبقي'] ?? raw['الدين_المتبقي']);
      final grandNum = _toDouble(grand);
      if (amountPaid == 0 && remaining > 0 && grandNum > 0) {
        amountPaid = (grandNum - remaining);
      }
      if (remaining == 0 && amountPaid > 0 && grandNum > 0) {
        remaining = (grandNum - amountPaid);
      }
      // تطبيع عناصر الفاتورة
      final dynamicLines = raw['line_items'] ?? raw['items'] ?? raw['details'] ?? raw['products'];
      final List<Map<String, dynamic>> lineItems = [];
      if (dynamicLines is List) {
        for (final e in dynamicLines) {
          if (e is Map) {
            final name = e['name'] ?? e['item'] ?? e['product'] ?? e['details'] ?? e['description'] ?? '';
            final qty = _toDouble(e['qty'] ?? e['quantity'] ?? e['count'] ?? 1);
            final price = _toDouble(e['price'] ?? e['unit_price'] ?? e['rate'] ?? 0);
            final amount = _toDouble(e['amount'] ?? e['line_total'] ?? (qty * price));
            lineItems.add({
              'name': name.toString(),
              'qty': qty,
              'price': price,
              'amount': amount,
            });
          }
        }
      }
      return {
        'invoice_date': invoiceDate,
        'invoice_number': invoiceNumber,
        'totals': {'grand_total': grandNum},
        'amount_paid': amountPaid,
        'remaining': remaining,
        if (lineItems.isNotEmpty) 'line_items': lineItems,
      };
    } else {
      final receiptDate = raw['receipt_date'] ?? raw['date'] ?? raw['receiptDate'];
      final receiptNumber = raw['receipt_number'] ?? raw['number'] ?? raw['receiptNumber'];
      final amount = raw['amount'] ?? raw['total'] ?? raw['value'];
      return {
        'receipt_date': receiptDate,
        'receipt_number': receiptNumber,
        'amount': amount,
      };
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(',', '').trim();
    return double.tryParse(s) ?? 0;
  }

  bool _isKnownProduct(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return true; // لا نعرض تحذيراً للحقل الفارغ
    if (_knownProductNames.contains(trimmed)) return true;
    final norm = _normalizeName(trimmed);
    if (_knownProductNamesNorm.contains(norm)) return true;
    // تطابق جزئي بعد التطبيع
    for (final k in _knownProductNamesNorm) {
      if (k.contains(norm) || norm.contains(k)) return true;
    }
    // تطابق ضبابي (Levenshtein) بعد التطبيع
    for (final k in _knownProductNamesNorm) {
      final dist = _levenshtein(norm, k);
      final maxLen = norm.length > k.length ? norm.length : k.length;
      final threshold = (maxLen * 0.15).ceil(); // 15%
      if (dist <= threshold || dist <= 2) return true;
    }
    return false;
  }

  String _normalizeName(String input) {
    String s = input.toLowerCase();
    // إزالة التشكيل العربي
    final diacritics = RegExp('[\u0610-\u061A\u064B-\u065F\u06D6-\u06ED]');
    s = s.replaceAll(diacritics, '');
    // إزالة التطويل
    s = s.replaceAll('\u0640', '');
    // توحيد الألفات والهمزات
    s = s.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');
    // توحيد الياء والألف المقصورة
    s = s.replaceAll('ى', 'ي');
    // توحيد الفارسية إلى العربية (ک -> ك، ی -> ي)
    s = s.replaceAll('ک', 'ك').replaceAll('ی', 'ي');
    // توحيد الكاف العربية/الفارسية في الاتجاه الآخر أيضاً (ك -> ك ثابت)
    // توحيد الأرقام العربية والهندية والفارسية إلى ASCII
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const persianIndic = '۰۱۲۳۴۵۶۷۸۹';
    for (int i = 0; i < 10; i++) {
      s = s.replaceAll(arabicIndic[i], i.toString());
      s = s.replaceAll(persianIndic[i], i.toString());
    }
    // توحيد التاء المربوطة والهاء (اختياري)
    s = s.replaceAll('ة', 'ه');
    // إزالة الرموز غير المهمة
    s = s.replaceAll(RegExp('[^\u0600-\u06FF0-9 ]'), ' ');
    // تصغير المسافات
    s = s.replaceAll(RegExp(' +'), ' ').trim();
    return s;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length;
    final n = b.length;
    List<int> prev = List<int>.generate(n + 1, (j) => j);
    List<int> curr = List<int>.filled(n + 1, 0);
    for (int i = 1; i <= m; i++) {
      curr[0] = i;
      for (int j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1, // insertion
          prev[j] + 1, // deletion
          prev[j - 1] + cost, // substitution
        ].reduce((v, e) => v < e ? v : e);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }

  Future<String?> _showAddProductDialog(String initialName) async {
    final nameCtrl = TextEditingController(text: initialName);
    final costCtrl = TextEditingController();
    final unitPriceCtrl = TextEditingController();
    String saleUnit = 'piece';
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة منتج جديد'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم المنتج'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: saleUnit,
                  decoration: const InputDecoration(labelText: 'نوع البيع'),
                  items: const [
                    DropdownMenuItem(value: 'piece', child: Text('قطعة')),
                    DropdownMenuItem(value: 'meter', child: Text('متر')),
                  ],
                  onChanged: (v) { if (v != null) saleUnit = v; },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: costCtrl,
                  decoration: const InputDecoration(labelText: 'سعر التكلفة'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: unitPriceCtrl,
                  decoration: const InputDecoration(labelText: 'سعر المفرد (سعر 1)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final db = DatabaseService();
              final now = DateTime.now();
              final product = Product(
                name: nameCtrl.text.trim(),
                unit: saleUnit, // فقط قطعة أو متر وفق طلبك
                unitPrice: double.tryParse(unitPriceCtrl.text.trim()) ?? 0.0,
                price1: double.tryParse(unitPriceCtrl.text.trim()) ?? 0.0,
                costPrice: double.tryParse(costCtrl.text.trim()),
                piecesPerUnit: null,
                lengthPerUnit: null,
                price2: null,
                price3: null,
                price4: null,
                price5: null,
                unitHierarchy: null,
                unitCosts: null,
                createdAt: now,
                lastModifiedAt: now,
              );
              try {
                await db.insertProduct(product);
                if (!mounted) return;
                Navigator.of(context).pop(true);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل إنشاء المنتج: $e')));
              }
            },
            child: const Text('حفظ'),
          )
        ],
      ),
    );

    if (result == true) {
      // أعد تحميل قائمة المنتجات المعروفة لتحديث التحذيرات
      try {
        final db = await DatabaseService().database;
        final rows = await db.query('products', columns: ['name']);
        final names = rows
            .map((e) => (e['name']?.toString().trim() ?? ''))
            .where((s) => s.isNotEmpty)
            .toSet();
        setState(() {
          _knownProductNames = names;
          _knownProductNamesNorm = names.map(_normalizeName).toSet();
        });
      } catch (_) {}
      return nameCtrl.text.trim();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مراجعة الاستخراج')), 
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildForm(),
    );
  }

  Widget _buildError() {
    final message = _error ?? '';
    // رسائل لطيفة لحالات 429/503
    String friendly = message;
    if (message.contains(' 429 ') || message.contains('code": 429') || message.contains('RESOURCE_EXHAUSTED')) {
      friendly = 'الخدمة مشغولة الآن (429). الرجاء المحاولة بعد قليل.';
    } else if (message.contains(' 503 ') || message.contains('UNAVAILABLE') || message.contains('code": 503')) {
      friendly = 'الخدمة غير متاحة مؤقتاً (503). سنحاول مجدداً.';
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(friendly, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _runExtraction,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() => _error = null);
            },
            child: const Text('تجاهل والملء يدوياً'),
          )
        ],
      ),
    );
  }

  Widget _buildForm() {
    final data = _extracted ?? {};
    final isInvoice = widget.type == 'invoice';
    final TextEditingController dateCtrl = TextEditingController(
      text: data[isInvoice ? 'invoice_date' : 'receipt_date']?.toString() ?? '',
    );
    final TextEditingController numCtrl = TextEditingController(
      text: data[isInvoice ? 'invoice_number' : 'receipt_number']?.toString() ?? '',
    );
    final TextEditingController amountCtrl = TextEditingController(
      text: isInvoice
          ? (() { final t = data['totals']?['grand_total']; return t == null ? '' : _fmt(_toDouble(t)); })()
          : (() { final a = data['amount']; return a == null ? '' : _fmt(_toDouble(a)); })(),
    );
    final TextEditingController paidCtrl = TextEditingController(
      text: isInvoice ? _fmt(_toDouble(data['amount_paid'] ?? 0)) : '0',
    );
    double remaining = 0.0;
    try {
      final total = double.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
      final paid = double.tryParse(paidCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
      remaining = (total - paid);
    } catch (_) {}

    final List<Map<String, dynamic>> lineItems = isInvoice
        ? ((data['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? const [])
        : const [];
    double lineItemsTotal = 0;
    for (final it in lineItems) {
      final qty = _toDouble(it['qty'] ?? 0);
      final price = _toDouble(it['price'] ?? 0);
      final amt = _toDouble(it['amount'] ?? (qty * price));
      it['qty'] = qty;
      it['price'] = price;
      it['amount'] = amt;
      lineItemsTotal += amt;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          if (isInvoice) ...[
            DropdownButtonFormField<String>(
              value: _paymentType,
              decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              items: const [
                DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                DropdownMenuItem(value: 'دين', child: Text('دين')),
              ],
              onChanged: (v) { if (v != null) setState(() { _paymentType = v; }); },
            ),
            const SizedBox(height: 12),
          ],
          if (isInvoice && lineItems.isNotEmpty) ...[
            const Text('عناصر الفاتورة', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 8,
                headingRowHeight: 38,
                dataRowHeight: 44,
                columns: const [
                  DataColumn(label: SizedBox(width: 28)),
                  DataColumn(label: SizedBox(width: 220, child: Text('التفاصيل'))),
                  DataColumn(label: SizedBox(width: 80, child: Text('العدد')), numeric: true),
                  DataColumn(label: SizedBox(width: 100, child: Text('السعر')), numeric: true),
                  DataColumn(label: SizedBox(width: 120, child: Text('المبلغ')), numeric: true),
                ],
                rows: [
                  ...List.generate(lineItems.length, (index) {
                    final item = lineItems[index];
                    return DataRow(cells: [
                      DataCell(SizedBox(
                        width: 28,
                        child: Center(child: Text('${index + 1}')),
                      )),
                      DataCell(Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: (item['name'] ?? '').toString(),
                              decoration: const InputDecoration(border: InputBorder.none),
                              onChanged: (v) {
                                item['name'] = v;
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (!_isKnownProduct((item['name'] ?? '').toString())) ...[
                            const Tooltip(
                              message: 'غير موجود في المنتجات',
                              child: Icon(Icons.error_outline, color: Colors.orange),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                              tooltip: 'إضافة المنتج',
                              onPressed: () async {
                                final createdName = await _showAddProductDialog((item['name'] ?? '').toString());
                                if (createdName != null) {
                                  item['name'] = createdName;
                                  setState(() {});
                                }
                              },
                            )
                          ],
                        ],
                      )),
                      DataCell(TextFormField(
                        initialValue: (item['qty'] ?? 0).toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(border: InputBorder.none),
                        onChanged: (v) {
                          final val = double.tryParse(v) ?? 0;
                          item['qty'] = val;
                          item['amount'] = val * (_toDouble(item['price']));
                          setState(() {});
                        },
                      )),
                      DataCell(TextFormField(
                        initialValue: (item['price'] ?? 0).toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(border: InputBorder.none),
                        onChanged: (v) {
                          final val = double.tryParse(v) ?? 0;
                          item['price'] = val;
                          item['amount'] = (_toDouble(item['qty'])) * val;
                          setState(() {});
                        },
                      )),
                      DataCell(Align(
                        alignment: Alignment.centerRight,
                        child: Text(_fmt(_toDouble(item['amount'] ?? 0))),
                      )),
                    ]);
                  })
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('مجموع العناصر: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(_fmt(lineItems.fold<double>(0, (s, e) => s + _toDouble(e['amount']))),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (widget.supplierId == null) ...[
            DropdownButtonFormField<int>(
              value: _selectedSupplierId,
              decoration: const InputDecoration(
                labelText: 'اختر المورد',
                border: OutlineInputBorder(),
              ),
              items: _suppliers
                  .map((s) => DropdownMenuItem<int>(
                        value: s.id,
                        child: Text(s.companyName),
                      ))
                  .toList(),
              onChanged: (v) async {
                setState(() => _selectedSupplierId = v);
                if (v != null) await _loadSupplierBalance(v);
              },
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: dateCtrl,
            decoration: InputDecoration(
              labelText: isInvoice ? 'تاريخ الفاتورة' : 'تاريخ السند',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: numCtrl,
            decoration: InputDecoration(
              labelText: isInvoice ? 'رقم الفاتورة' : 'رقم السند',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amountCtrl,
            decoration: InputDecoration(
              labelText: isInvoice ? 'الإجمالي' : 'المبلغ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          if (isInvoice) ...[
            const SizedBox(height: 12),
            TextField(
              controller: paidCtrl,
              decoration: const InputDecoration(labelText: 'المدفوع'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                // حدث قيمة نوع الدفع تلقائياً حسب المتبقي
                final total = double.tryParse(amountCtrl.text.replaceAll(',', '').trim()) ?? 0.0;
                final paid = double.tryParse(v.replaceAll(',', '').trim()) ?? 0.0;
                final rem = total - paid;
                setState(() {
                  _paymentType = rem <= 0 ? 'نقد' : 'دين';
                });
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('المتبقي (يُضاف للدين إن كان دين):',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(remaining.toStringAsFixed(2),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if ((_selectedSupplierId ?? widget.supplierId) != null) _buildBalancePreview(
            isInvoice: isInvoice,
            totalText: amountCtrl.text,
            paidText: paidCtrl.text,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              if ((_selectedSupplierId ?? widget.supplierId) == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('الرجاء اختيار المورد أولاً')),
                );
                return;
              }
              await _saveRecord(
                isInvoice: isInvoice,
                dateText: dateCtrl.text,
                numberText: numCtrl.text,
                amountText: amountCtrl.text,
                paidText: paidCtrl.text,
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          )
        ],
      ),
    );
  }

  Widget _buildBalancePreview({
    required bool isInvoice,
    required String totalText,
    required String paidText,
  }) {
    final current = (_supplierCurrentBalance ?? 0.0);
    final total = double.tryParse(totalText.replaceAll(',', '').trim()) ?? 0.0;
    final paid = double.tryParse(paidText.replaceAll(',', '').trim()) ?? 0.0;
    double delta;
    if (isInvoice) {
      final remaining = (total - paid);
      delta = _paymentType == 'نقد' ? 0.0 : (remaining < 0 ? 0.0 : remaining);
    } else {
      delta = -total;
    }
    final after = current + delta;
    return Card(
      margin: const EdgeInsets.only(top: 4),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('قبل: ${_fmt(current)}'),
            Text('التغير: ${_fmt(delta)}'),
            Text('بعد: ${_fmt(after)}'),
          ],
        ),
      ),
    );
  }

  Future<void> _saveRecord({
    required bool isInvoice,
    required String dateText,
    required String numberText,
    required String amountText,
    String? paidText,
  }) async {
    try {
      // احفظ الملف أولاً كمرفق
      final ext = widget.mimeType == 'application/pdf'
          ? 'pdf'
          : (widget.mimeType == 'image/png' ? 'png' : 'jpg');
      final path = await _suppliersService.saveAttachmentFile(
        bytes: widget.fileBytes,
        extension: ext,
      );

      int? ownerId;
      final supplierId = widget.supplierId ?? _selectedSupplierId ?? 0;
      if (isInvoice) {
        final lineItems = (_extracted?['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final total = _toDouble(amountText);
        final paid = _toDouble((paidText ?? '0'));
        String status;
        if (paid >= total && total > 0) {
          status = 'مسدد';
        } else if (paid > 0 && paid < total) {
          status = 'جزئي';
        } else {
          status = 'آجل';
        }
        final inv = SupplierInvoice(
          supplierId: supplierId,
          invoiceNumber: numberText.isEmpty ? null : numberText,
          invoiceDate: DateTime.tryParse(dateText) ?? DateTime.now(),
          totalAmount: total,
          amountPaid: paid,
          status: status,
          paymentType: _paymentType,
        );
        ownerId = await _suppliersService.insertSupplierInvoice(inv);
        await _suppliersService.insertAttachment(Attachment(
          ownerType: 'SupplierInvoice',
          ownerId: ownerId,
          filePath: path,
          fileType: ext == 'pdf' ? 'pdf' : 'image',
          extractedText: _extracted == null ? null : {
            'line_items': lineItems,
          }.toString(),
          extractionConfidence: null,
        ));
      } else {
        final rec = SupplierReceipt(
          supplierId: supplierId,
          receiptNumber: numberText.isEmpty ? null : numberText,
          receiptDate: DateTime.tryParse(dateText) ?? DateTime.now(),
          amount: double.tryParse(amountText) ?? 0,
        );
        ownerId = await _suppliersService.insertSupplierReceipt(rec);
        await _suppliersService.insertAttachment(Attachment(
          ownerType: 'SupplierReceipt',
          ownerId: ownerId,
          filePath: path,
          fileType: ext == 'pdf' ? 'pdf' : 'image',
          extractedText: _extracted == null ? null : _extracted.toString(),
          extractionConfidence: null,
        ));
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الحفظ: $e')),
      );
    }
  }
}


