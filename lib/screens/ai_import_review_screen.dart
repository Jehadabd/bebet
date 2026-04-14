import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/ai_extraction_service.dart';
import '../services/suppliers_service.dart';
import '../services/product_specs_service.dart';
import '../models/supplier.dart';
import '../services/database_service.dart';
import '../models/product.dart';

class AiImportReviewScreen extends StatefulWidget {
  final Uint8List fileBytes;
  final String mimeType; // image/png, image/jpeg, application/pdf
  final String type; // 'invoice' | 'receipt'
  final String geminiApiKey;
  final String? geminiApiKey2;
  final String? geminiApiKey3;
  final String? geminiApiKey4;
  final String? openRouterApiKey;
  final String? groqApiKey;
  final String? cloudflareApiToken;
  final String? cloudflareAccountId;
  final String? ocrSpaceApiKey;
  final String? glmApiKey;
  final String? mistralApiKey;  // ✅ Mistral Pixtral - مجاني سخي!
  final int? supplierId;

  const AiImportReviewScreen({
    Key? key,
    required this.fileBytes,
    required this.mimeType,
    required this.type,
    required this.geminiApiKey,
    this.geminiApiKey2,
    this.geminiApiKey3,
    this.geminiApiKey4,
    this.openRouterApiKey,
    this.groqApiKey,
    this.cloudflareApiToken,
    this.cloudflareAccountId,
    this.ocrSpaceApiKey,
    this.glmApiKey,
    this.mistralApiKey,  // ✅ Mistral
    this.supplierId,
  }) : super(key: key);

  @override
  State<AiImportReviewScreen> createState() => _AiImportReviewScreenState();
}

class _AiImportReviewScreenState extends State<AiImportReviewScreen> {
  Map<String, dynamic>? _extracted;
  bool _loading = true;
  String? _error;
  String? _rawOcrText; 
  final SuppliersService _suppliersService = SuppliersService();
  List<Supplier> _suppliers = const [];
  int? _selectedSupplierId;
  String _invoiceCurrency = 'IQD';
  final _exchangeRateCtrl = TextEditingController(text: '1500');
  final _profitMarginCtrl = TextEditingController(text: '15'); // نسبة الربح الافتراضية 15%
  Set<String> _knownProductNames = {};
  Set<String> _knownProductNamesNorm = {};
  String _paymentType = 'دين';
  final NumberFormat _nf = NumberFormat('#,##0.##', 'en');
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en'); // للعملة بدون كسور

  String _fmt(num v) => _nf.format(v);
  double? _supplierCurrentBalance; 
  
  Supplier? get _selectedSupplier {
    if (_selectedSupplierId == null) return null;
    try {
      return _suppliers.firstWhere((s) => s.id == _selectedSupplierId);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _exchangeRateCtrl.dispose();
    _profitMarginCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _suppliersService.ensureTables();
      final list = await _suppliersService.getAllSuppliers();
      if (!mounted) return;
      _suppliers = list;
      
      if (widget.supplierId != null) {
        _selectedSupplierId = widget.supplierId;
        await _loadSupplierBalance(_selectedSupplierId!);
      }
      
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
      final service = AIExtractionService(
        geminiApiKey: widget.geminiApiKey,
        geminiApiKey2: widget.geminiApiKey2,
        geminiApiKey3: widget.geminiApiKey3,
        geminiApiKey4: widget.geminiApiKey4,
        openRouterApiKey: widget.openRouterApiKey,
        groqApiKey: widget.groqApiKey,
        cloudflareApiToken: widget.cloudflareApiToken,
        cloudflareAccountId: widget.cloudflareAccountId,
        ocrSpaceApiKey: widget.ocrSpaceApiKey,
        glmApiKey: widget.glmApiKey,
        mistralApiKey: widget.mistralApiKey,  // ✅ Mistral Pixtral
      );
      final extractionResult = await service.extractInvoiceOrReceiptStructured(
        fileBytes: widget.fileBytes,
        fileMimeType: widget.mimeType,
        extractType: widget.type,
      );
      
      if (!extractionResult.success) {
        throw Exception(extractionResult.error ?? 'فشل الاستخراج');
      }
      
      if (!mounted) return;
      var normalized = _normalizeResult(extractionResult.data);
      
      // Attempt supplier matching
      if (_selectedSupplierId == null && normalized['supplier_name'] != null) {
        final aiSupplierName = normalized['supplier_name'].toString().toLowerCase();
        for (final s in _suppliers) {
          if (s.companyName.toLowerCase().contains(aiSupplierName) || 
              aiSupplierName.contains(s.companyName.toLowerCase())) {
            _selectedSupplierId = s.id;
            await _loadSupplierBalance(s.id!);
            break;
          }
        }
      }

      // Detect Currency
      if (normalized['currency'] != null) {
        final aiCur = normalized['currency'].toString().toUpperCase();
        if (aiCur == 'USD' || aiCur == 'IQD') {
          _invoiceCurrency = aiCur;
        }
      } else if (_selectedSupplier != null) {
        _invoiceCurrency = _selectedSupplier!.defaultCurrency;
      }
      
      _rawOcrText = extractionResult.data['raw_text']?.toString();
      
      if (widget.type == 'invoice') {
        var items = (normalized['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        
        final specsService = ProductSpecsService();
        items = await specsService.enrichWithSpecs(items);
        normalized['line_items'] = items;
        
        await specsService.saveSpecsFromAIResult(items);
        await _loadProductCosts(items);
      }
      setState(() {
        _extracted = normalized;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      // عرض خيار إعادة المحاولة
      await _showRetryDialog(e.toString());
    }
  }

  /// عرض حوار إعادة المحاولة
  Future<void> _showRetryDialog(String error) async {
    if (!mounted) return;
    
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('فشل الاستخراج'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'حدث خطأ أثناء استخراج البيانات:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                error.length > 200 ? '${error.substring(0, 200)}...' : error,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ),
            const SizedBox(height: 16),
            const Text('ماذا تريد أن تفعل؟'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'other'),
            child: const Text('استخدام نموذج آخر'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, 'retry'),
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (result == 'retry') {
      // إعادة المحاولة مع Gemini
      print('🔄 إعادة المحاولة مع Gemini...');
      await _runExtraction();
    } else if (result == 'other') {
      // استخدام نموذج آخر
      print('🔄 الانتقال لنموذج آخر...');
      await _runExtractionSkipGemini();
    } else {
      // إلغاء
      setState(() {
        _error = error;
      });
    }
  }

  /// استخراج بدون Gemini (انتقال للنماذج الاحتياطية)
  Future<void> _runExtractionSkipGemini() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // إنشاء خدمة بدون مفاتيح Gemini
      final service = AIExtractionService(
        geminiApiKey: '', // فارغ لتخطي Gemini
        openRouterApiKey: widget.openRouterApiKey,
        groqApiKey: widget.groqApiKey,
        cloudflareApiToken: widget.cloudflareApiToken,
        cloudflareAccountId: widget.cloudflareAccountId,
        ocrSpaceApiKey: widget.ocrSpaceApiKey,
        glmApiKey: widget.glmApiKey,
        mistralApiKey: widget.mistralApiKey,
      );
      final extractionResult = await service.extractInvoiceOrReceiptStructured(
        fileBytes: widget.fileBytes,
        fileMimeType: widget.mimeType,
        extractType: widget.type,
      );
      
      if (!extractionResult.success) {
        throw Exception(extractionResult.error ?? 'فشل الاستخراج');
      }
      
      if (!mounted) return;
      var normalized = _normalizeResult(extractionResult.data);
      
      // مطابقة المورد
      if (_selectedSupplierId == null && normalized['supplier_name'] != null) {
        final aiSupplierName = normalized['supplier_name'].toString().toLowerCase();
        for (final s in _suppliers) {
          if (s.companyName.toLowerCase().contains(aiSupplierName) || 
              aiSupplierName.contains(s.companyName.toLowerCase())) {
            _selectedSupplierId = s.id;
            await _loadSupplierBalance(s.id!);
            break;
          }
        }
      }

      // تحديد العملة
      if (normalized['currency'] != null) {
        final aiCur = normalized['currency'].toString().toUpperCase();
        if (aiCur == 'USD' || aiCur == 'IQD') {
          _invoiceCurrency = aiCur;
        }
      } else if (_selectedSupplier != null) {
        _invoiceCurrency = _selectedSupplier!.defaultCurrency;
      }
      
      _rawOcrText = extractionResult.data['raw_text']?.toString();
      
      if (widget.type == 'invoice') {
        var items = (normalized['line_items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        
        final specsService = ProductSpecsService();
        items = await specsService.enrichWithSpecs(items);
        normalized['line_items'] = items;
        
        await specsService.saveSpecsFromAIResult(items);
        await _loadProductCosts(items);
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

  Future<void> _loadProductCosts(List<Map<String, dynamic>> items) async {
    try {
      final db = DatabaseService();
      for (final item in items) {
        final productName = (item['name'] ?? '').toString().trim();
        if (productName.isEmpty) continue;
        final products = await db.searchProductsSmart(productName);
        for (final product in products) {
          if (_normalizeName(product.name) == _normalizeName(productName)) {
            item['oldCostPrice'] = product.costPrice;
            item['matched_product_id'] = product.id;
            item['product_unit'] = product.unit; // 'piece' or 'meter'
            item['product_unit_hierarchy'] = product.unitHierarchy;
            item['product_unit_costs'] = product.unitCosts;
            item['is_new_product'] = false;
            
            // التعرف التلقائي على وحدة الشراء للمنتجات الموجودة
            _autoDetectSaleUnit(item, product);
            break;
          }
        }
        // إذا لم يُطابق = منتج جديد
        if (item['matched_product_id'] == null) {
          item['is_new_product'] = true;
        }
      }
    } catch (_) {}
  }

  /// التعرف التلقائي على وحدة الشراء بناءً على هرمية المنتج والاسم الأصلي
  void _autoDetectSaleUnit(Map<String, dynamic> item, Product product) {
    final saleUnit = (item['sale_unit'] ?? '').toString();
    final originalName = (item['original_name'] ?? '').toString().toLowerCase();
    final unitType = (item['unit_type'] ?? 'piece').toString();
    
    // الكلمات الدالة على الوحدات
    final unitKeywords = {
      'كرتون': ['كرتون', 'كارتون', 'ctn', 'carton'],
      'باكيت': ['باكيت', 'باكت', 'pkt', 'packet', 'pack'],
      'ربطة': ['ربطة', 'شدة', 'bundle'],
      'صندوق': ['صندوق', 'box'],
      'درزن': ['درزن', 'دزينة', 'dozen', 'dz'],
      'سيت': ['سيت', 'set'],
    };
    
    // ✅ إذا الذكاء الاصطناعي استخرج وحدة البيع مسبقاً
    String detectedUnit = saleUnit;
    
    // ✅ تصحيح التاء المربوطة (كارتون → كرتون، باكت → باكيت)
    detectedUnit = detectedUnit.replaceAll('كارتون', 'كرتون');
    detectedUnit = detectedUnit.replaceAll('باكت', 'باكيت');
    
    // إذا لم يستخرجها، نبحث في الاسم الأصلي
    if (detectedUnit.isEmpty) {
      for (final entry in unitKeywords.entries) {
        for (final keyword in entry.value) {
          if (originalName.contains(keyword)) {
            detectedUnit = entry.key;
            break;
          }
        }
        if (detectedUnit.isNotEmpty) break;
      }
    }
    
    // ✅ إذا كان المنتج بالمتر، نحدد الوحدة تلقائياً
    if (unitType == 'meter' && detectedUnit.isEmpty) {
      detectedUnit = 'لفة';
    }
    
    // ✅ حساب المُضاعِف بناءً على الهرمية
    if (detectedUnit.isNotEmpty && product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
      try {
        final List<dynamic> hierarchy = json.decode(product.unitHierarchy!);
        double multiplier = 1.0;
        bool found = false;
        
        for (final level in hierarchy) {
          final unitName = (level['unit_name'] ?? '').toString();
          final qty = _toDouble(level['quantity'] ?? 1);
          multiplier *= qty;
          if (unitName == detectedUnit) {
            found = true;
            break;
          }
        }
        
        if (found) {
          // ✅ الوحدة موجودة في الهرمي
          item['sale_unit'] = detectedUnit;
          item['hierarchy_multiplier'] = multiplier;
          item['needs_hierarchy_input'] = false;
          print('  🏗️ تعرف تلقائي: وحدة=$detectedUnit، مُضاعِف=$multiplier');
        } else {
          // ✅ الوحدة غير موجودة في الهرمي - تحتاج إضافة جديدة
          item['sale_unit'] = detectedUnit;
          item['hierarchy_multiplier'] = 1.0;
          item['needs_new_unit'] = true; // 🆕 يحتاج إضافة وحدة جديدة
          item['existing_hierarchy'] = hierarchy; // 🆕 حفظ الهرمي الموجود
          print('  ⚠️ الوحدة "$detectedUnit" غير موجودة في الهرمي - تحتاج إضافة');
        }
      } catch (e) {
        print('خطأ في قراءة هرمية المنتج: $e');
      }
    } else if (detectedUnit.isNotEmpty) {
      // وحدة مكتشفة لكن لا توجد هرمية في القاعدة
      item['sale_unit'] = detectedUnit;
      item['needs_hierarchy_input'] = true; // يحتاج إدخال يدوي كامل
    }
  }

  Map<String, dynamic> _normalizeResult(Map<String, dynamic> raw) {
    if (widget.type == 'invoice') {
      final totals = raw['totals'] ?? {};
      final grand = totals is Map 
          ? (totals['grand_total'] ?? totals['total'] ?? totals['final'])
          : (raw['grand_total'] ?? raw['total'] ?? raw['final_total']);
      
      final dynamicLines = raw['line_items'] ?? raw['items'] ?? raw['details'] ?? raw['products'];
      final List<Map<String, dynamic>> lineItems = [];
      if (dynamicLines is List) {
        for (final e in dynamicLines) {
          if (e is Map) {
            final name = e['name'] ?? e['item'] ?? e['product'] ?? '';
            final qty = _toDouble(e['qty'] ?? e['quantity'] ?? 1);
            final price = _toDouble(e['price'] ?? e['unit_price'] ?? 0);
            final amount = _toDouble(e['amount'] ?? (qty * price));
            
            lineItems.add({
              'name': name.toString(),
              'original_name': (e['original_name'] ?? name).toString(),
              'qty': qty,
              'price': price,
              'amount': amount,
              'unit_type': (e['unit_type'] ?? 'piece').toString(),
              'units_count': _toDouble(e['units_count'] ?? 1),
              'sale_unit': (e['sale_unit'] ?? '').toString(),
              'units_multiplier': _toDouble(e['units_multiplier'] ?? 1),
              'hierarchy_multiplier': _toDouble(e['units_multiplier'] ?? 1),
              'confidence': _toDouble(e['confidence'] ?? 0),
              'matched_product_id': e['matched_product_id'],
              'is_new_product': e['is_new_product'] ?? true,
            });
          }
        }
      }
      return {
        'invoice_date': raw['invoice_date'] ?? raw['date'] ?? DateTime.now().toString().substring(0, 10),
        'invoice_number': raw['invoice_number'] ?? raw['number'] ?? '',
        'supplier_name': raw['supplier_name'],
        'currency': raw['currency'],
        'totals': {'grand_total': _toDouble(grand)},
        'line_items': lineItems,
      };
    } else {
      return {
        'receipt_date': raw['receipt_date'] ?? raw['date'] ?? DateTime.now().toString().substring(0, 10),
        'receipt_number': raw['receipt_number'] ?? '',
        'amount': _toDouble(raw['amount'] ?? raw['total']),
      };
    }
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '').trim()) ?? 0;
  }

  /// استخراج رقم التعبئة من اسم المنتج (مثل: "تعبئة 100" أو "100 قطعة" أو "سلم 100")
  int _extractPackagingFromName(String name) {
    if (name.isEmpty) return 0;
    
    // البحث عن "تعبئة" متبوعة برقم
    final packagingRegex = RegExp(r'تعبئة\s*(\d+)');
    final match = packagingRegex.firstMatch(name);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    
    // البحث عن "سلم" متبوعة برقم
    final salmRegex = RegExp(r'سلم\s*(\d+)');
    final salmMatch = salmRegex.firstMatch(name);
    if (salmMatch != null) {
      return int.tryParse(salmMatch.group(1) ?? '0') ?? 0;
    }
    
    // البحث عن رقم متبوع بـ "قطعة" أو "قطع"
    final pieceRegex = RegExp(r'(\d+)\s*قطع?');
    final pieceMatch = pieceRegex.firstMatch(name);
    if (pieceMatch != null) {
      return int.tryParse(pieceMatch.group(1) ?? '0') ?? 0;
    }
    
    return 0;
  }

  String _normalizeName(String input) {
    String s = input.toLowerCase();
    s = s.replaceAll(RegExp('[\u0610-\u061A\u064B-\u065F\u06D6-\u06ED]'), '');
    s = s.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');
    s = s.replaceAll('ى', 'ي').replaceAll('ک', 'ك').replaceAll('ی', 'ي').replaceAll('ة', 'ه');
    s = s.replaceAll(RegExp('[^\u0600-\u06FF0-9 ]'), ' ');
    return s.replaceAll(RegExp(' +'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('مراجعة الاستخراج الذكي'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildForm(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(_error ?? 'خطأ غير معروف', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _runExtraction, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final data = _extracted ?? {};
    final isInvoice = widget.type == 'invoice';
    final List<Map<String, dynamic>> items = isInvoice ? (data['line_items'] as List).cast<Map<String, dynamic>>() : [];

    return Column(
      children: [
        // Header ثابت (لا يتحرك مع التمرير)
        _buildHeaderCard(data),
        _buildStatsRow(items),
        // ✅ جدول عناصر الفاتورة - مع تمرير أفقي وعمودي (تكبير المساحة)
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              width: 1100, // ✅ تكبير العرض لاستيعاب عمود التعبئة
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: Column(
                  children: [
                    // Header يتحرك مع التمرير
                    _buildTableHeader(),
                    // قائمة العناصر
                    ...items.asMap().entries.map((entry) => _buildItemCard(entry.value, entry.key)),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Bottom panel ثابت
        _buildBottomPanel(data, items),
      ],
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> data) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // اختيار المورد
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedSupplierId,
                  hint: const Text('اختر المورد'),
                  isExpanded: true,
                  items: _suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.companyName))).toList(),
                  onChanged: (id) {
                    if (id != null) {
                      setState(() => _selectedSupplierId = id);
                      _loadSupplierBalance(id);
                    }
                  },
                ),
              ),
              const Divider(),
              // الصف الأول: العملة + سعر الصرف (يظهر فقط للدولار) + نسبة الربح
              Row(
                children: [
                  // العملة
                  Expanded(
                    flex: _invoiceCurrency == 'USD' ? 2 : 3,
                    child: DropdownButton<String>(
                      value: _invoiceCurrency,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem(value: 'IQD', child: Text('دينار (IQD)')),
                        DropdownMenuItem(value: 'USD', child: Text('دولار (USD)')),
                      ],
                      onChanged: (v) { 
                        if (v != null) {
                          setState(() => _invoiceCurrency = v);
                          // إعادة حساب الأسعار عند تغيير العملة
                          _recalculateAllPrices(data);
                        }
                      },
                    ),
                  ),
                  // سعر الصرف - يظهر فقط إذا كانت العملة دولار
                  if (_invoiceCurrency == 'USD') ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _exchangeRateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'سعر الصرف',
                          isDense: true, 
                          border: OutlineInputBorder(),
                          suffixText: 'د/دولار',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          // إعادة حساب الأسعار عند تغيير سعر الصرف مباشرة
                          setState(() {
                            _recalculateAllPrices(data);
                          });
                        },
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  // نسبة الربح الافتراضية
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _profitMarginCtrl,
                      decoration: const InputDecoration(
                        labelText: 'الربح %',
                        isDense: true,
                        border: OutlineInputBorder(),
                        suffixText: '%',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        // إعادة حساب أسعار البيع عند تغيير نسبة الربح مباشرة
                        setState(() {
                          _recalculateAllPrices(data);
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // الصف الثاني: التاريخ + رقم الفاتورة
              Row(
                children: [
                  Expanded(child: _buildSmallField('التاريخ', data['invoice_date'] ?? '', (v) => data['invoice_date'] = v)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildSmallField('رقم الفاتورة', data['invoice_number'] ?? '', (v) => data['invoice_number'] = v)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// إعادة حساب جميع الأسعار
  void _recalculateAllPrices(Map<String, dynamic> data) {
    final items = data['line_items'] as List<dynamic>? ?? [];
    final exchangeRate = double.tryParse(_exchangeRateCtrl.text) ?? 1500;
    final profitMargin = double.tryParse(_profitMarginCtrl.text) ?? 15;
    
    for (var item in items) {
      final itemMap = item as Map<String, dynamic>;
      final amount = _toDouble(itemMap['amount'] ?? 0);
      final qty = _toDouble(itemMap['qty'] ?? 1);
      final unitsCount = _toDouble(itemMap['units_count'] ?? 1);
      final unitType = itemMap['unit_type'] ?? 'piece';
      final hierarchyMultiplier = _toDouble(itemMap['hierarchy_multiplier'] ?? 1);
      final originalName = itemMap['original_name']?.toString() ?? itemMap['name']?.toString() ?? '';
      
      // ✅ استخراج التعبئة من الاسم
      final packaging = _extractPackagingFromName(originalName);
      
      // ✅ استخدام سعر التكلفة الموجود إذا كان محفوظاً
      double costPerUnit = _toDouble(itemMap['cost_per_unit_iqd'] ?? 0);
      
      // فقط إذا لم يكن هناك سعر تكلفة محفوظ، احسبه من المبلغ
      if (costPerUnit == 0 && qty > 0) {
        // تحويل الإجمالي إلى دينار
        double amountInIqd = amount;
        if (_invoiceCurrency == 'USD') {
          amountInIqd = amount * exchangeRate;
        }
        
        // حساب تكلفة الوحدة
        if (unitType == 'meter' && unitsCount > 0) {
          // منتجات المتر: المبلغ ÷ (الكمية × الأمتار)
          costPerUnit = amountInIqd / (qty * unitsCount);
        } else if (packaging > 1) {
          // ✅ منتجات بتعبئة (كرتون/باكيت): المبلغ ÷ (الكمية × التعبئة)
          costPerUnit = amountInIqd / (qty * packaging);
        } else if (hierarchyMultiplier > 1) {
          // منتجات بتسلسل هرمي: المبلغ ÷ (الكمية × المُضاعِف)
          costPerUnit = amountInIqd / (qty * hierarchyMultiplier);
        } else {
          // منتجات بالقطعة العادية
          costPerUnit = amountInIqd / qty;
        }
      }
      
      // ✅ حساب سعر البيع من التكلفة المحفوظة + نسبة الربح
      double sellingPrice = costPerUnit * (1 + profitMargin / 100);
      
      // تحديث البيانات
      itemMap['cost_per_unit_iqd'] = costPerUnit;
      itemMap['selling_price_iqd'] = sellingPrice;
      itemMap['profit_margin'] = profitMargin;
    }
    
    setState(() {});
  }

  Widget _buildSmallField(String label, String value, Function(String) onChanged) {
    return TextFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(),contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
      style: const TextStyle(fontSize: 12),
      onChanged:onChanged,
    );
  }

  Widget _buildStatsRow(List<Map<String, dynamic>> items) {
    final double total = items.fold(0, (sum, it) => sum + _toDouble(it['amount']));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children:[
          _buildStatPill(Icons.list, '${items.length} بنود', Colors.blue),
          _buildStatPill(Icons.payments, '${_fmt(total)} $_invoiceCurrency', Colors.green),
          _buildStatPill(Icons.auto_awesome, 'الذكاء الاصطناعي', Colors.purple),
        ],
      ),
    );
  }
  Widget _buildStatPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11))]),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item, int index) {
    final name = item['name']?.toString() ?? '';
    final originalName = item['original_name']?.toString() ?? name;
    final isNew = item['matched_product_id'] == null;
    final unitType = item['unit_type'] ?? 'piece';
    final unitsCount = _toDouble(item['units_count'] ?? 1);
    final qty = _toDouble(item['qty'] ?? 1);
    final price = _toDouble(item['price'] ?? 0);
    final amount = _toDouble(item['amount'] ?? (qty * price));
    final saleUnit = (item['sale_unit'] ?? '').toString();
    final hierarchyMultiplier = _toDouble(item['hierarchy_multiplier'] ?? 1);
    final needsInput = item['needs_hierarchy_input'] == true;
    // استخراج التعبئة من الفاتورة (مثل: "تعبئة 100" أو "100 قطعة")
    final packaging = _extractPackagingFromName(originalName);
    
    // قراءة سعر الصرف ونسبة الربح
    final exchangeRate = double.tryParse(_exchangeRateCtrl.text) ?? 1500;
    final profitMargin = double.tryParse(_profitMarginCtrl.text) ?? 15;
    
    // ✅ حساب سعر التكلفة للوحدة الواحدة (القطعة) بالدينار
    // السعر في الفاتورة يمثل سعر الكرتون/الباكيت، يجب تقسيمه على التعبئة
    double costPerUnit = item['cost_per_unit_iqd'] ?? 0;
    if (costPerUnit == 0) {
      double amountInIqd = amount;
      if (_invoiceCurrency == 'USD') {
        amountInIqd = amount * exchangeRate;
      }
      if (qty > 0) {
        // ✅ التعبئة: عدد القطع في الكرتون/الباكيت
        final packagingCount = packaging > 0 ? packaging : (unitType == 'meter' ? unitsCount : hierarchyMultiplier);
        
        if (unitType == 'meter' && unitsCount > 0) {
          // للمنتجات بالمتر: السعر ÷ (الكمية × عدد الأمتار)
          costPerUnit = amountInIqd / (qty * unitsCount);
        } else if (packagingCount > 1) {
          // ✅ للمنتجات بالقطعة مع تعبئة: السعر ÷ (الكمية × التعبئة)
          // مثال: سعر الكرتون 364,800 ÷ (2 كرتون × 100 قطعة) = 1,824 للقطعة
          costPerUnit = amountInIqd / (qty * packagingCount);
        } else {
          // للمنتجات بدون تعبئة: السعر ÷ الكمية
          costPerUnit = amountInIqd / qty;
        }
      }
    }
    
    // حساب سعر البيع
    double sellingPrice = item['selling_price_iqd'] ?? 0;
    if (sellingPrice == 0 && costPerUnit > 0) {
      sellingPrice = costPerUnit * (1 + profitMargin / 100);
    }
    
    // تحديث البيانات
    item['cost_per_unit_iqd'] = costPerUnit;
    item['selling_price_iqd'] = sellingPrice;

    // بناء نص الوحدة
    String unitLabel = '';
    if (unitType == 'meter') {
      unitLabel = '(${unitsCount.toStringAsFixed(0)}م)';
    } else if (saleUnit.isNotEmpty && saleUnit != 'قطعة') {
      unitLabel = '($saleUnit×${hierarchyMultiplier.toStringAsFixed(0)})';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      height: 85,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
        color: isNew ? Colors.green.withOpacity(0.05) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ✅ رقم تسلسلي
          SizedBox(
            width: 40,
            child: Container(
              alignment: Alignment.center,
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ),
          ),
          // ✅ اسم المنتج + حالة جديد/موجود + وحدة الشراء (تكبير العرض)
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ✅ اسم المنتج بحجم أكبر
                  Text(
                    name, 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (originalName != name && originalName != '')
                    Text(
                      originalName, 
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // ✅ تكبير حالة "موجود" أو "جديد"
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isNew ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isNew ? Icons.add_circle : Icons.check_circle,
                              size: 14,
                              color: isNew ? Colors.green : Colors.blue,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              isNew ? 'جديد' : 'موجود',
                              style: TextStyle(
                                color: isNew ? Colors.green : Colors.blue,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ✅ تكبير كلمة "كرتون"
                      if (packaging > 0 || (unitType == 'meter' && unitsCount > 0))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            unitType == 'meter' ? '${unitsCount.toStringAsFixed(0)}م' : 'كرتون',
                            style: TextStyle(fontSize: 12, color: Colors.purple.shade700, fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (unitLabel.isNotEmpty && packaging == 0)
                        Text(
                          unitLabel,
                          style: TextStyle(fontSize: 11, color: Colors.purple.shade600, fontWeight: FontWeight.bold),
                        ),
                      // زر تحديد الهيراركية للمنتجات الجديدة أو التي تحتاج إدخال
                      if ((isNew || needsInput) && unitType != 'meter')
                        InkWell(
                          onTap: () => _showHierarchyDialog(item, index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.account_tree, size: 10, color: Colors.purple.shade700),
                                const SizedBox(width: 2),
                                Text(
                                  hierarchyMultiplier > 1 ? 'تعديل' : 'وحدات',
                                  style: TextStyle(fontSize: 8, color: Colors.purple.shade700, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // 🆕 زر إضافة وحدة جديدة غير موجودة في الهرمي
                      if (item['needs_new_unit'] == true)
                        InkWell(
                          onTap: () => _showNewUnitDialog(item, index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_circle, size: 10, color: Colors.orange.shade800),
                                const SizedBox(width: 2),
                                Text(
                                  'إضافة ${item['sale_unit']}',
                                  style: TextStyle(fontSize: 8, color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // الإجمالي
          Expanded(
            flex: 2,
            child: _FormattedNumberField(
              key: ValueKey('amount_$index'),
              value: amount,
              onChanged: (v) {
                item['amount'] = v;
                _recalculateAllPrices(_extracted!);
              },
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          // سعر الوحدة في الفاتورة
          Expanded(
            flex: 2,
            child: _FormattedNumberField(
              key: ValueKey('price_$index'),
              value: price,
              allowDecimal: true,
              onChanged: (v) {
                item['price'] = v;
                setState(() {});
              },
              style: const TextStyle(fontSize: 12),
            ),
          ),
          // ✅ عمود التعبئة (عدد الأمتار في اللفة أو القطع في الكرتون)
          Expanded(
            flex: 1,
            child: Container(
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ✅ للمنتجات بالمتر: عرض units_count (عدد الأمتار)
                  // ✅ للمنتجات بالقطعة: عرض packaging المستخرج من الاسم
                  Text(
                    unitType == 'meter' && unitsCount > 0 
                        ? unitsCount.toStringAsFixed(0)
                        : (packaging > 0 ? packaging.toString() : '-'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: (unitType == 'meter' && unitsCount > 0) || packaging > 0 
                          ? Colors.purple 
                          : Colors.grey,
                    ),
                  ),
                  // ✅ عرض نوع التعبئة حسب نوع المنتج
                  if ((unitType == 'meter' && unitsCount > 0) || packaging > 0)
                    Text(
                      unitType == 'meter' ? 'متر' : 'قطعة',
                      style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
          ),
          // ✅ سعر التكلفة للقطعة (قابل للتعديل)
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: _FormattedNumberField(
                key: ValueKey('cost_$index'),
                value: costPerUnit,
                onChanged: (v) {
                  item['cost_per_unit_iqd'] = v;
                  // إعادة حساب سعر البيع
                  item['selling_price_iqd'] = v * (1 + profitMargin / 100);
                  setState(() {});
                },
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                hintText: 'د.ع',
              ),
            ),
          ),
          // سعر البيع (قابل للتعديل)
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: _FormattedNumberField(
                key: ValueKey('sell_$index'),
                value: sellingPrice,
                onChanged: (v) {
                  item['selling_price_iqd'] = v;
                  setState(() {});
                },
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                hintText: 'د.ع',
              ),
            ),
          ),
          // ✅ عمود الإجراءات (تعديل/حذف)
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // زر التعديل
                InkWell(
                  onTap: () => _showEditProductDialog(item, index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.edit, size: 16, color: Colors.blue),
                  ),
                ),
                const SizedBox(width: 4),
                // زر الحذف
                InkWell(
                  onTap: () => _deleteItem(index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.delete, size: 16, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// حذف عنصر من القائمة
  void _deleteItem(int index) {
    final data = _extracted ?? {};
    final List<Map<String, dynamic>> items = (data['line_items'] as List).cast<Map<String, dynamic>>();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل تريد حذف هذا المنتج من القائمة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                items.removeAt(index);
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  /// نافذة تعديل اسم المنتج مع البحث التلقائي
  void _showEditProductDialog(Map<String, dynamic> item, int index) {
    final controller = TextEditingController(text: item['name']?.toString() ?? '');
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل اسم المنتج'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // حقل البحث مع Autocomplete
                Autocomplete<Product>(
                  initialValue: TextEditingValue(text: controller.text),
                  fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                    return TextField(
                      controller: textController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        hintText: 'اكتب للبحث في المنتجات...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        controller.text = value;
                      },
                    );
                  },
                  optionsBuilder: (TextEditingValue textEditingValue) async {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<Product>.empty();
                    }
                    // البحث في قاعدة البيانات
                    final db = DatabaseService();
                    final results = await db.searchProductsSmart(textEditingValue.text);
                    return results.take(10);
                  },
                  displayStringForOption: (Product product) => product.name,
                  onSelected: (Product product) {
                    controller.text = product.name;
                    setDialogState(() {});
                  },
                ),
                const SizedBox(height: 16),
                // خيار إضافة منتج جديد
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    // فتح نافذة إضافة منتج جديد
                    _showAddNewProductDialog(controller.text, item, index);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة كمنتج جديد'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  item['name'] = newName;
                  setState(() {});
                }
                Navigator.pop(context);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  /// نافذة إضافة منتج جديد
  void _showAddNewProductDialog(String initialName, Map<String, dynamic> item, int index) {
    final nameController = TextEditingController(text: initialName);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة منتج جديد'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'اسم المنتج',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty) {
                item['name'] = newName;
                item['is_new_product'] = true;
                item['matched_product_id'] = null;
                
                setState(() {});
              }
              Navigator.pop(context);
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  /// نافذة حوار لتحديد هيراركية الوحدات (كرتون/باكيت/قطعة)
  void _showHierarchyDialog(Map<String, dynamic> item, int index) {
    final saleUnit = (item['sale_unit'] ?? '').toString();
    String selectedUnit = saleUnit.isNotEmpty ? saleUnit : 'قطعة';
    int qty1 = 1; // عدد الباكيتات في الكرتون أو عدد القطع في الوحدة
    int qty2 = 1; // عدد القطع في الباكيت (فقط إذا كرتون)
    
    final amount = _toDouble(item['amount'] ?? 0);
    final qty = _toDouble(item['qty'] ?? 1);
    final exchangeRate = double.tryParse(_exchangeRateCtrl.text) ?? 1500;
    
    // الأرقام المتاحة للاختيار
    final List<int> numberOptions = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 24, 25, 30, 36, 40, 48, 50, 60, 72, 80, 96, 100, 120, 144, 200, 250, 500, 1000];
    
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          // حساب المُضاعِف والتكلفة المتوقعة
          double multiplier = 1;
          if (selectedUnit == 'كرتون') {
            multiplier = (qty1 * qty2).toDouble();
          } else if (selectedUnit != 'قطعة') {
            multiplier = qty1.toDouble();
          }
          
          double amountInIqd = amount;
          if (_invoiceCurrency == 'USD') amountInIqd = amount * exchangeRate;
          double expectedCost = (qty > 0 && multiplier > 0) ? amountInIqd / (qty * multiplier) : 0;
          
          return AlertDialog(
            title: const Text('تحديد وحدة الشراء', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('المنتج: ${item['name']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const Divider(),
                  const Text('ما هي وحدة الشراء في الفاتورة؟', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ['قطعة', 'باكيت', 'كرتون', 'ربطة', 'صندوق', 'درزن', 'لفة'].map((unit) {
                      return ChoiceChip(
                        label: Text(unit, style: const TextStyle(fontSize: 11)),
                        selected: selectedUnit == unit,
                        selectedColor: Colors.purple.shade100,
                        onSelected: (v) {
                          setDialogState(() {
                            selectedUnit = unit;
                            qty1 = 1;
                            qty2 = 1;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  if (selectedUnit != 'قطعة') ...[
                    const SizedBox(height: 16),
                    if (selectedUnit == 'كرتون') ...[
                      // الكرتون → باكيت
                      _buildDropdownRow(
                        label: 'الكرتون يحتوي كم باكيت؟',
                        value: qty1,
                        options: numberOptions,
                        onChanged: (v) => setDialogState(() => qty1 = v ?? 1),
                      ),
                      const SizedBox(height: 8),
                      // الباكيت → قطعة
                      _buildDropdownRow(
                        label: 'الباكيت يحتوي كم قطعة؟',
                        value: qty2,
                        options: numberOptions,
                        onChanged: (v) => setDialogState(() => qty2 = v ?? 1),
                      ),
                    ] else ...[
                      _buildDropdownRow(
                        label: '$selectedUnit يحتوي كم قطعة/متر؟',
                        value: qty1,
                        options: numberOptions,
                        onChanged: (v) => setDialogState(() => qty1 = v ?? 1),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // معاينة حية للحساب
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calculate, size: 16, color: Colors.blue.shade700),
                              const SizedBox(width: 4),
                              Text('معاينة الحساب:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'المُضاعِف: ${multiplier.toStringAsFixed(0)} قطعة',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            'تكلفة القطعة: ${_currencyFmt.format(expectedCost)} د.ع',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                onPressed: () {
                  List<Map<String, dynamic>> hierarchy = [];
                  
                  if (selectedUnit == 'قطعة') {
                    multiplier = 1;
                  } else if (selectedUnit == 'كرتون') {
                    hierarchy = [
                      {'unit_name': 'باكيت', 'quantity': qty2},
                      {'unit_name': 'كرتون', 'quantity': qty1},
                    ];
                  } else {
                    hierarchy = [
                      {'unit_name': selectedUnit, 'quantity': qty1},
                    ];
                  }
                  
                  setState(() {
                    item['sale_unit'] = selectedUnit;
                    item['hierarchy_multiplier'] = multiplier;
                    item['needs_hierarchy_input'] = false;
                    item['new_unit_hierarchy'] = hierarchy.isNotEmpty ? hierarchy : null;
                    // إعادة حساب مع المُضاعِف الجديد
                    item['cost_per_unit_iqd'] = 0; // reset to force recalc
                    item['selling_price_iqd'] = 0;
                    _recalculateAllPrices(_extracted!);
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('تأكيد', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  /// 🆕 نافذة حوار لإضافة وحدة جديدة غير موجودة في الهرمي
  void _showNewUnitDialog(Map<String, dynamic> item, int index) {
    final saleUnit = (item['sale_unit'] ?? '').toString();
    final existingHierarchy = item['existing_hierarchy'] as List<dynamic>? ?? [];
    
    // استخراج الوحدات الموجودة في الهرمي
    final existingUnits = existingHierarchy.map((h) => h['unit_name'].toString()).toList();
    final smallestUnit = existingUnits.isNotEmpty ? existingUnits.first : 'قطعة';
    
    int qtyToSmallest = 1; // عدد الوحدات الصغيرة في الوحدة الجديدة
    
    // الأرقام المتاحة للاختيار
    final List<int> numberOptions = [1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 24, 25, 30, 36, 40, 48, 50, 60, 72, 80, 96, 100, 120, 144, 200, 250, 500, 1000];
    
    final amount = _toDouble(item['amount'] ?? 0);
    final qty = _toDouble(item['qty'] ?? 1);
    final exchangeRate = double.tryParse(_exchangeRateCtrl.text) ?? 1500;
    
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          double amountInIqd = amount;
          if (_invoiceCurrency == 'USD') amountInIqd = amount * exchangeRate;
          double costPerSmallest = (qty > 0 && qtyToSmallest > 0) ? amountInIqd / (qty * qtyToSmallest) : 0;
          
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.add_circle, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                const Text('إضافة وحدة جديدة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // معلومات المنتج
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('المنتج: ${item['name']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('الوحدة في الفاتورة: $saleUnit', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                        Text('الوحدات الموجودة: ${existingUnits.join(" → ")}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  
                  // شرح
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('⚠️ الوحدة "$saleUnit" غير موجودة في الهرمي', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                        const SizedBox(height: 4),
                        Text('يجب تحديد كم $smallestUnit في $saleUnit الواحد', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // اختيار العدد
                  _buildDropdownRow(
                    label: 'ال$saleUnit يحتوي كم $smallestUnit؟',
                    value: qtyToSmallest,
                    options: numberOptions,
                    onChanged: (v) => setDialogState(() => qtyToSmallest = v ?? 1),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // معاينة الحساب
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الهرمي الجديد:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                        const SizedBox(height: 4),
                        Text('$smallestUnit ← $saleUnit ($qtyToSmallest)', style: const TextStyle(fontSize: 11)),
                        const Divider(height: 12),
                        Text(
                          'تكلفة ال$smallestUnit: ${_currencyFmt.format(costPerSmallest)} د.ع',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                onPressed: () {
                  // بناء الهرمي الجديد مع إضافة الوحدة الجديدة
                  List<Map<String, dynamic>> newHierarchy = [];
                  
                  // إضافة الوحدة الجديدة في الأعلى
                  newHierarchy.add({'unit_name': saleUnit, 'quantity': qtyToSmallest});
                  
                  // إضافة الهرمي الموجود
                  for (final level in existingHierarchy) {
                    newHierarchy.add({
                      'unit_name': level['unit_name'],
                      'quantity': level['quantity'],
                    });
                  }
                  
                  setState(() {
                    item['hierarchy_multiplier'] = qtyToSmallest.toDouble();
                    item['needs_new_unit'] = false;
                    item['new_unit_hierarchy'] = newHierarchy;
                    item['is_hierarchy_updated'] = true; // 🆕 علامة لتحديث المنتج في قاعدة البيانات
                    // إعادة حساب
                    item['cost_per_unit_iqd'] = 0;
                    item['selling_price_iqd'] = 0;
                    _recalculateAllPrices(_extracted!);
                  });
                  
                  Navigator.pop(ctx);
                  
                  // 🆕 عرض رسالة تأكيد
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ تم إضافة "$saleUnit" إلى هرمي المنتج'),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                child: const Text('إضافة الوحدة', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildDropdownRow({
    required String label,
    required int value,
    required List<int> options,
    required void Function(int?) onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.purple.shade200),
              borderRadius: BorderRadius.circular(8),
              color: Colors.purple.shade50,
            ),
            child: DropdownButton<int>(
              value: options.contains(value) ? value : 1,
              isExpanded: true,
              underline: const SizedBox(),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
              items: options.map((n) => DropdownMenuItem(value: n, child: Text('$n', textAlign: TextAlign.center))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildCompactIn(String label, String val, Function(String) onC, {bool expanded = true}) {
    final field = TextFormField(
      initialValue: val,
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
      style: const TextStyle(fontSize: 11),
      onChanged: onC,
    );
    return expanded ? Expanded(child: field) : field;
  }

  /// تنسيق رقم مع فواصل
  String _formatNumber(dynamic value) {
    if (value == null) return '';
    final numValue = _toDouble(value.toString());
    if (numValue == 0) return '';
    return _currencyFmt.format(numValue);
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: const [
          SizedBox(width: 40, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center)),
          Expanded(flex: 4, child: Text('المنتج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
          Expanded(flex: 2, child: Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('سعر الوحدة\nفي الفاتورة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
          Expanded(flex: 1, child: Text('التعبئة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('التكلفة\nللقطعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text('سعر البيع', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center)),
          SizedBox(width: 80, child: Text('إجراء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(Map<String, dynamic> data, List<Map<String, dynamic>> items) {
    final double total = items.fold(0, (sum, it) => sum + _toDouble(it['amount']));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
      child: SafeArea(child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          const Text('إجمالي الفاتورة', style: TextStyle(fontSize: 12, color: Colors.grey)),
          Text('${_fmt(total)} $_invoiceCurrency', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ])),
        ElevatedButton(
          onPressed: _onSave,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          child: const Text('حفظ الفاتورة'),
        ),
      ])),
    );
  }

  Future<void> _onSave() async {
    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار المورد')));
      return;
    }
    
    setState(() => _loading = true);
    try {
      final isInvoice = widget.type == 'invoice';
      final data = _extracted ?? {};
      final List<Map<String, dynamic>> lineItems = isInvoice ? (data['line_items'] as List).cast<Map<String, dynamic>>() : [];
      final double total = lineItems.fold(0, (sum, it) => sum + _toDouble(it['amount']));
      
      final exchangeRate = double.tryParse(_exchangeRateCtrl.text) ?? 1500.0;
      
      // Calculate currency conversions for debt
      double convertedTotal = total;
      if (_invoiceCurrency == 'USD' && _selectedSupplier!.defaultCurrency == 'IQD') {
        convertedTotal = total * exchangeRate;
      } else if (_invoiceCurrency == 'IQD' && _selectedSupplier!.defaultCurrency == 'USD') {
        convertedTotal = total / exchangeRate;
      }
      
      // Invoice Object
      final inv = SupplierInvoice(
        supplierId: _selectedSupplierId!,
        status: 'آجل',
        invoiceNumber: data['invoice_number']?.toString(),
        invoiceDate: DateTime.tryParse(data['invoice_date'] ?? '') ?? DateTime.now(),
        totalAmount: convertedTotal,
        amountPaid: 0,
        currency: _selectedSupplier!.defaultCurrency,
        exchangeRate: exchangeRate,
      );
      
      final db = DatabaseService();
      final invoiceId = await _suppliersService.insertSupplierInvoice(inv);
      
      // Items and Cost Updates
      for (var it in lineItems) {
        final qty = _toDouble(it['qty']);
        final price = _toDouble(it['price']);
        final amount = _toDouble(it['amount']);
        final unitsCount = _toDouble(it['units_count'] ?? 1);
        final unitType = it['unit_type'] ?? 'piece';
        final hierarchyMultiplier = _toDouble(it['hierarchy_multiplier'] ?? 1);
        final saleUnit = (it['sale_unit'] ?? '').toString();
        
        // حساب التكلفة المحسوبة مسبقاً (المعروضة في الشاشة)
        double costPerUnit = _toDouble(it['cost_per_unit_iqd'] ?? 0);
        
        // إذا لم تحسب بعد
        if (costPerUnit == 0) {
          double amountInIqd = amount;
          if (_invoiceCurrency == 'USD') amountInIqd = amount * exchangeRate;
          
          if (unitType == 'meter' && unitsCount > 1 && qty > 0) {
            costPerUnit = amountInIqd / (qty * unitsCount);
          } else if (hierarchyMultiplier > 1 && qty > 0) {
            costPerUnit = amountInIqd / (qty * hierarchyMultiplier);
          } else if (qty > 0) {
            costPerUnit = amountInIqd / qty;
          }
        }

        // سعر البيع
        final profitMargin = double.tryParse(_profitMarginCtrl.text) ?? 15;
        final sellingPrice = _toDouble(it['selling_price_iqd'] ?? (costPerUnit * (1 + profitMargin / 100)));
        
        // Search or Create Product
        int? pid = it['matched_product_id'];
        if (pid == null) {
          // منتج جديد - بناء الهرمية
          String? unitHierarchy;
          String? unitCosts;
          double? lengthPerUnit;
          
          if (unitType == 'meter' && unitsCount > 1) {
            // منتج بالمتر
            lengthPerUnit = unitsCount;
            unitHierarchy = jsonEncode([{'unit_name': 'لفة', 'quantity': unitsCount.toInt()}]);
            unitCosts = jsonEncode({'متر': costPerUnit, 'لفة': costPerUnit * unitsCount});
          } else if (it['new_unit_hierarchy'] != null) {
            // منتج بالقطعة مع هرمية محددة من قبل المستخدم
            final hierarchy = it['new_unit_hierarchy'] as List<Map<String, dynamic>>;
            unitHierarchy = jsonEncode(hierarchy);
            
            // بناء تكاليف الوحدات
            final costsMap = <String, double>{'قطعة': costPerUnit};
            double runningCost = costPerUnit;
            for (final level in hierarchy) {
              final unitName = level['unit_name'].toString();
              final levelQty = _toDouble(level['quantity'] ?? 1);
              runningCost *= levelQty;
              costsMap[unitName] = runningCost;
            }
            unitCosts = jsonEncode(costsMap);
          }
          
          final newP = Product(
            name: it['name'], 
            unit: unitType == 'meter' ? 'meter' : 'piece', 
            unitPrice: sellingPrice,
            costPrice: costPerUnit,
            lengthPerUnit: lengthPerUnit,
            price1: sellingPrice,
            createdAt: DateTime.now(), 
            lastModifiedAt: DateTime.now(),
            unitHierarchy: unitHierarchy,
            unitCosts: unitCosts,
          );
          pid = await db.insertProduct(newP);
        } else {
          // تحديث منتج موجود
          final prod = await db.getProductById(pid);
          if (prod != null) {
            String? newHierarchy = prod.unitHierarchy;
            String? newUnitCosts = prod.unitCosts;
            double? newLengthPerUnit = prod.lengthPerUnit;
            
            if (unitType == 'meter' && unitsCount > 1) {
              newLengthPerUnit = unitsCount;
              newHierarchy = jsonEncode([{'unit_name': 'لفة', 'quantity': unitsCount.toInt()}]);
              newUnitCosts = jsonEncode({'متر': costPerUnit, 'لفة': costPerUnit * unitsCount});
            } else if (it['new_unit_hierarchy'] != null) {
              // المستخدم حدد هرمية جديدة لمنتج موجود
              final hierarchy = it['new_unit_hierarchy'] as List<Map<String, dynamic>>;
              newHierarchy = jsonEncode(hierarchy);
              
              final costsMap = <String, double>{'قطعة': costPerUnit};
              double runningCost = costPerUnit;
              for (final level in hierarchy) {
                final unitName = level['unit_name'].toString();
                final levelQty = _toDouble(level['quantity'] ?? 1);
                runningCost *= levelQty;
                costsMap[unitName] = runningCost;
              }
              newUnitCosts = jsonEncode(costsMap);
            } else if (prod.unitCosts != null && prod.unitCosts!.isNotEmpty) {
              // تحديث تكاليف الوحدات الموجودة بالتكلفة الجديدة
              try {
                final existingCosts = json.decode(prod.unitCosts!) as Map<String, dynamic>;
                existingCosts['قطعة'] = costPerUnit;
                
                // إعادة حساب تكاليف الوحدات الأعلى
                if (prod.unitHierarchy != null) {
                  final hierarchy = json.decode(prod.unitHierarchy!) as List<dynamic>;
                  double runningCost = costPerUnit;
                  for (final level in hierarchy) {
                    final unitName = (level['unit_name'] ?? '').toString();
                    final levelQty = _toDouble(level['quantity'] ?? 1);
                    runningCost *= levelQty;
                    existingCosts[unitName] = runningCost;
                  }
                }
                newUnitCosts = jsonEncode(existingCosts);
              } catch (_) {}
            }
            
            await db.updateProduct(prod.copyWith(
              costPrice: costPerUnit, 
              unitPrice: sellingPrice,
              price1: sellingPrice,
              lengthPerUnit: newLengthPerUnit,
              unitHierarchy: newHierarchy,
              unitCosts: newUnitCosts,
              lastModifiedAt: DateTime.now(),
            ));
          }
        }
        
        // Insert Invoice Item
        String invoiceUnit = 'قطعة';
        if (unitType == 'meter') {
          invoiceUnit = 'متر';
        } else if (saleUnit.isNotEmpty) {
          invoiceUnit = saleUnit;
        }
        
        await _suppliersService.insertInvoiceItem(SupplierInvoiceItem(
          invoiceId: invoiceId, productId: pid, productName: it['name'],
          quantity: qty, unitPrice: _invoiceCurrency == 'USD' ? price : price, totalPrice: amount,
          unit: invoiceUnit,
        ));
      }
      
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في الحفظ: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

/// حقل رقم منسق مع فواصل آلية
class _FormattedNumberField extends StatefulWidget {
  final double value;
  final Function(double) onChanged;
  final TextStyle? style;
  final String? hintText;
  final bool allowDecimal;

  const _FormattedNumberField({
    Key? key,
    required this.value,
    required this.onChanged,
    this.style,
    this.hintText,
    this.allowDecimal = false,
  }) : super(key: key);

  @override
  State<_FormattedNumberField> createState() => _FormattedNumberFieldState();
}

class _FormattedNumberFieldState extends State<_FormattedNumberField> {
  late TextEditingController _controller;
  late NumberFormat _formatter;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _formatter = NumberFormat('#,##0', 'en');
    if (widget.allowDecimal) {
      _formatter = NumberFormat('#,##0.##', 'en');
    }
    _controller = TextEditingController(text: _formatValue(widget.value));
  }

  @override
  void didUpdateWidget(_FormattedNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // تحديث النص فقط إذا لم يكن المستخدم يعدل
    if (!_isEditing && oldWidget.value != widget.value) {
      _controller.text = _formatValue(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatValue(double value) {
    if (value == 0) return '';
    return _formatter.format(value);
  }

  double _parseValue(String text) {
    final plain = text.replaceAll(',', '');
    return double.tryParse(plain) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      textAlign: TextAlign.center,
      style: widget.style,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        border: InputBorder.none,
        hintText: widget.hintText,
        hintStyle: const TextStyle(fontSize: 10),
      ),
      keyboardType: TextInputType.numberWithOptions(decimal: widget.allowDecimal),
      onTap: () => _isEditing = true,
      onEditingComplete: () => _isEditing = false,
      onChanged: (v) {
        // إزالة الفواصل
        final plainValue = v.replaceAll(',', '');
        final numberValue = double.tryParse(plainValue) ?? 0;
        
        // إعلام الأب بالتغيير
        widget.onChanged(numberValue);
        
        // إعادة تنسيق النص مع الفواصل
        final formatted = _formatValue(numberValue);
        
        // تحديث النص في الحقل
        _controller.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      },
    );
  }
}
