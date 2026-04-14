import 'dart:typed_data';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import '../models/supplier.dart';
import '../models/delegate.dart';
import '../models/product.dart';
import '../services/gemini_service.dart';
import '../services/multi_provider_ai_service.dart';
import '../services/suppliers_service.dart';
import '../services/database_service.dart';

class NewSupplierInvoiceScreen extends StatefulWidget {
  final Supplier supplier;
  const NewSupplierInvoiceScreen({Key? key, required this.supplier}) : super(key: key);

  @override
  State<NewSupplierInvoiceScreen> createState() => _NewSupplierInvoiceScreenState();
}

class _NewSupplierInvoiceScreenState extends State<NewSupplierInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _paidCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');
  String _paymentType = 'دين'; // نقد أو دين
  late String _currency; // عملة الفاتورة
  final _exchangeRateCtrl = TextEditingController();
  bool _saving = false;
  Uint8List? _pickedBytes;
  String? _pickedMime;
  String? _pickedName;
  final NumberFormat _nf = NumberFormat('#,##0.##', 'en');
  bool _formatting = false;

  final SuppliersService _service = SuppliersService();
  final DatabaseService _db = DatabaseService();
  // قائمة بنود الفاتورة
  List<SupplierInvoiceItem> _items = [];
  List<Product> _allProducts = [];
  List<Delegate> _delegates = [];
  Delegate? _selectedDelegate;

  // هل العملة مختلفة عن عملة المورد؟
  bool get _needsExchangeRate => _currency != widget.supplier.defaultCurrency;

  @override
  void initState() {
    super.initState();
    _currency = widget.supplier.defaultCurrency; // العملة الافتراضية من المورد
    _loadProducts();
    _dateCtrl.text = DateTime.now().toIso8601String().split('T')[0];
  }

  Future<void> _loadProducts() async {
    final products = await _db.getAllProducts();
    final dels = await _service.getDelegatesBySupplier(widget.supplier.id!);
    setState(() {
      _allProducts = products;
      _delegates = dels;
    });
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _numberCtrl.dispose();
    _totalCtrl.dispose();
    _paidCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  void _recalculateTotal() {
    final itemsTotal = _items.fold(0.0, (sum, item) => sum + item.totalPrice);
    setState(() {
      _totalCtrl.text = _nf.format(itemsTotal);
    });
  }

  void _addItem() {
    showDialog(
      context: context,
      builder: (context) => _AddItemDialog(
        allProducts: _allProducts,
        onAdd: (item) {
          setState(() {
            _items.add(item);
            _recalculateTotal();
          });
        },
      ),
    );
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _recalculateTotal();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate 50
      appBar: AppBar(
        title: const Text('فاتورة شراء جديدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF455A64),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'ملء تلقائي من صورة',
            onPressed: _onAutofillFromImage,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Form Container
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Row 1: Supplier & Date
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  enabled: false,
                                  initialValue: widget.supplier.companyName,
                                  decoration: const InputDecoration(
                                    labelText: 'المورد *',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.store),
                                    suffixIcon: Icon(Icons.arrow_drop_down),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: _dateCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'التاريخ',
                                    border: OutlineInputBorder(),
                                    suffixIcon: Icon(Icons.calendar_today),
                                  ),
                                  validator: (v) => (v == null || v.isEmpty) ? 'أدخل التاريخ' : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // Row 2: Invoice Number, Currency, Paid Amount, Payment Type
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _numberCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'رقم الفاتورة',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _currency,
                                  decoration: const InputDecoration(
                                    labelText: 'العملة',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.attach_money),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'IQD', child: Text('IQD')),
                                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                                  ],
                                  onChanged: (v) { if (v != null) setState(() { _currency = v; }); },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _paidCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'المبلغ المسدد',
                                    border: OutlineInputBorder(),
                                    suffixIcon: Icon(Icons.money),
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => _onFormatNumber(_paidCtrl),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _paymentType,
                                  decoration: const InputDecoration(
                                    labelText: 'نوع الدفع',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.credit_card),
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                                    DropdownMenuItem(value: 'دين', child: Text('دين')),
                                  ],
                                  onChanged: (v) { if (v != null) setState(() { _paymentType = v; }); },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Row 3: Discount and Delegate
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _discountCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'الخصم (اختياري)',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.money_off),
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => _onFormatNumber(_discountCtrl),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<Delegate>(
                                  value: _selectedDelegate,
                                  hint: const Text('اختيار المندوب'),
                                  decoration: const InputDecoration(
                                    labelText: 'المندوب',
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.person),
                                  ),
                                  items: _delegates.map((d) {
                                    return DropdownMenuItem(value: d, child: Text(d.name));
                                  }).toList(),
                                  onChanged: (v) { setState(() { _selectedDelegate = v; }); },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // Row 4: Exchange Rate (Show only if currency differs)
                          if (_needsExchangeRate) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _exchangeRateCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'سعر صرف الدولار (مثلاً 1500)',
                                      helperText: 'سيتم استخدامه لتحويل المبالغ لعملة المورد (${widget.supplier.defaultCurrency})',
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(Icons.currency_exchange, color: Colors.green),
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    validator: (v) {
                                      if (_needsExchangeRate && (v == null || v.isEmpty || double.tryParse(v) == 0)) {
                                        return 'الرجاء إدخال سعر الصرف';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          
                          // Row 4: Attachment
                          InkWell(
                            onTap: _onPickAttachment,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade400),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _pickedName == null ? 'اختيار ملف' : _pickedName!,
                                    style: TextStyle(color: _pickedName == null ? Colors.blue : Colors.black, fontWeight: FontWeight.bold),
                                  ),
                                  Row(
                                    children: [
                                      const Text('إرفاق صورة أو PDF (اختياري)', style: TextStyle(color: Colors.grey)),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.attach_file, color: Colors.grey),
                                      if (_pickedBytes != null)
                                        IconButton(
                                          icon: const Icon(Icons.clear, color: Colors.red),
                                          onPressed: () => setState(() { _pickedBytes = null; _pickedMime = null; _pickedName = null; }),
                                        )
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Products Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         ElevatedButton.icon(
                          onPressed: _addItem,
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة منتج'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF455A64),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                        const Text('المنتجات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Products Table
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          // Header Row
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            child: Row(
                              children: const [
                                Expanded(flex: 1, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                                Expanded(flex: 3, child: Text('المنتج', style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('سعر الوحدة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('الكمية', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('الوحدة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('الإجمالي', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                                SizedBox(width: 48), // space for delete icon
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFFE2E8F0)),
                          
                          // Body
                          if (_items.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(48.0),
                              child: Center(
                                child: Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey.shade300),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _items.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                  child: Row(
                                    children: [
                                      Expanded(flex: 1, child: Text('${index + 1}', style: const TextStyle(color: Colors.grey))),
                                      Expanded(flex: 3, child: Text(item.productName)),
                                      Expanded(flex: 2, child: Text(item.unitPrice.toStringAsFixed(2), textAlign: TextAlign.center)),
                                      Expanded(flex: 2, child: Text(item.quantity.toString(), textAlign: TextAlign.center)),
                                      Expanded(flex: 2, child: Text(item.unit ?? 'قطعة', textAlign: TextAlign.center)),
                                      Expanded(flex: 2, child: Text(item.totalPrice.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                                      SizedBox(
                                        width: 48,
                                        child: IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                          onPressed: () => _removeItem(index),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Bottom Bar
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -4)),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _saving ? null : () => _onSave(false),
                      icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline),
                      label: const Text('تأكيد واستلام'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _onSave(true),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('حفظ كمسودة'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF4F46E5),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
                Text(
                  'الإجمالي: IQD ${_totalCtrl.text.isEmpty ? '0' : _totalCtrl.text}',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF455A64)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onAutofillFromImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');

    setState(() {
      _pickedBytes = file.bytes!;
      _pickedMime = mime;
      _pickedName = file.name;
    });

    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final apiKey2 = dotenv.env['GEMINI_API_KEY_2'] ?? '';
    final apiKey3 = dotenv.env['GEMINI_API_KEY_3'] ?? '';
    final apiKey4 = dotenv.env['GEMINI_API_KEY_4'] ?? '';
    final openRouterKey = dotenv.env['OPENROUTER_API_KEY'] ?? '';
    final groqKey = dotenv.env['GROQ_API_KEY'] ?? '';
    final cloudflareToken = dotenv.env['CLOUDFLARE_API_TOKEN'] ?? '';
    final cloudflareAccount = dotenv.env['CLOUDFLARE_ACCOUNT_ID'] ?? '';
    final googleVisionKey = dotenv.env['GOOGLE_VISION_API_KEY'] ?? '';
    final ocrSpaceKey = dotenv.env['OCR_SPACE_API_KEY'] ?? '';  // ✅ جديد
    
    if (apiKey.isEmpty && apiKey2.isEmpty && apiKey3.isEmpty && apiKey4.isEmpty && groqKey.isEmpty && cloudflareToken.isEmpty && openRouterKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد مفتاح API مضبوط في .env')));
      return;
    }

    try {
      final aiService = MultiProviderAIService(
        geminiApiKey: apiKey,
        geminiApiKey2: apiKey2.isNotEmpty ? apiKey2 : null,
        geminiApiKey3: apiKey3.isNotEmpty ? apiKey3 : null,
        geminiApiKey4: apiKey4.isNotEmpty ? apiKey4 : null,
        openRouterApiKey: openRouterKey.isNotEmpty ? openRouterKey : null,
        groqApiKey: groqKey.isNotEmpty ? groqKey : null,
        cloudflareApiToken: cloudflareToken.isNotEmpty ? cloudflareToken : null,
        cloudflareAccountId: cloudflareAccount.isNotEmpty ? cloudflareAccount : null,
        ocrSpaceApiKey: ocrSpaceKey.isNotEmpty ? ocrSpaceKey : null,  // ✅ جديد
      );
      
      final data = await aiService.extractInvoiceOrReceiptStructured(
        fileBytes: _pickedBytes!,
        fileMimeType: _pickedMime!,
        extractType: 'invoice',
        products: _allProducts.map((p) => {
          'id': p.id,
          'name': p.name,
          'cost_price': p.costPrice,
          'unit_hierarchy': p.unitHierarchy,
        }).toList(),
      );
      
      // عرض المزود المستخدم
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الاستخراج باستخدام: ${aiService.currentProvider.toUpperCase()}')),
      );
      final date = (data['invoice_date'] ?? '').toString();
      final num = (data['invoice_number'] ?? '').toString();
      final total = (data['totals']?['grand_total'] ?? data['grand_total'] ?? data['total'] ?? '');
      final lineItems = data['line_items'] as List<dynamic>? ?? [];
      
      setState(() {
        if (date.isNotEmpty) _dateCtrl.text = date;
        if (num.isNotEmpty) _numberCtrl.text = num;
        if (total != null && total.toString().isNotEmpty) { 
          _totalCtrl.text = _nf.format(double.tryParse(total.toString()) ?? 0); 
        }
        
        // Add extracted items
        _items.clear();
        for (var item in lineItems) {
          final matchedId = item['matched_product_id'];
          final name = item['name']?.toString() ?? 'منتج غير معروف';
          final originalName = item['original_name']?.toString() ?? name;
          final qty = double.tryParse(item['qty']?.toString() ?? '0') ?? 0.0;
          final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
          final amount = double.tryParse(item['amount']?.toString() ?? '0') ?? (qty * price);
          final reason = item['reason']?.toString() ?? '';
          final unitType = item['unit_type']?.toString() ?? 'piece';
          final unitsCount = double.tryParse(item['units_count']?.toString() ?? '1') ?? 1.0;
          final saleUnit = item['sale_unit']?.toString();
          final unitsMultiplier = double.tryParse(item['units_multiplier']?.toString() ?? '1') ?? 1.0;
          
          double unitPrice = price;
          String? unit;

          if (saleUnit != null && saleUnit.isNotEmpty) {
             unit = saleUnit;
             if (unitsMultiplier > 1) {
                // calculate price per basic unit (e.g. piece)
                unitPrice = price / unitsMultiplier; 
             }
          } else {
             // fallback
             if (unitType == 'meter' && unitsCount > 1) {
               unitPrice = price / unitsCount; // cost per meter
               unit = 'متر';
             } else {
               unit = 'قطعة';
             }
          }
          
          _items.add(SupplierInvoiceItem(
            invoiceId: 0, // سيتم تحديثه لاحقاً
            productId: matchedId != null ? int.tryParse(matchedId.toString()) : null,
            productName: name,
            quantity: qty,
            unitPrice: unitPrice, // cost per meter for meter products
            totalPrice: amount,
            unit: unit,
            notes: reason.isNotEmpty ? "AI: $reason | الأصلي: $originalName" : "الأصلي: $originalName",
          ));
        }
        _recalculateTotal();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحليل: $e')));
    }
  }

  Future<void> _onPickAttachment() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : 'image/jpeg');
    
    setState(() {
      _pickedBytes = file.bytes!;
      _pickedMime = mime;
      _pickedName = file.name;
    });

    // إضافة: المعالجة التلقائية بالذكاء الاصطناعي عند إرفاق ملف
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تحليل الفاتورة بالذكاء الاصطناعي...')),
    );

    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final apiKey2 = dotenv.env['GEMINI_API_KEY_2'] ?? '';
    final apiKey3 = dotenv.env['GEMINI_API_KEY_3'] ?? '';
    final apiKey4 = dotenv.env['GEMINI_API_KEY_4'] ?? '';
    final groqKey = dotenv.env['GROQ_API_KEY'] ?? '';
    final cloudflareToken = dotenv.env['CLOUDFLARE_API_TOKEN'] ?? '';
    final cloudflareAccount = dotenv.env['CLOUDFLARE_ACCOUNT_ID'] ?? '';
    final googleVisionKey = dotenv.env['GOOGLE_VISION_API_KEY'] ?? '';
    final ocrSpaceKey = dotenv.env['OCR_SPACE_API_KEY'] ?? '';  // ✅ جديد
    
    if (apiKey.isEmpty && apiKey2.isEmpty && apiKey3.isEmpty && apiKey4.isEmpty && groqKey.isEmpty && cloudflareToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد مفتاح API مضبوط في .env')));
      return;
    }

    try {
      final aiService = MultiProviderAIService(
        geminiApiKey: apiKey,
        geminiApiKey2: apiKey2.isNotEmpty ? apiKey2 : null,
        geminiApiKey3: apiKey3.isNotEmpty ? apiKey3 : null,
        geminiApiKey4: apiKey4.isNotEmpty ? apiKey4 : null,
        groqApiKey: groqKey.isNotEmpty ? groqKey : null,
        cloudflareApiToken: cloudflareToken.isNotEmpty ? cloudflareToken : null,
        cloudflareAccountId: cloudflareAccount.isNotEmpty ? cloudflareAccount : null,
        ocrSpaceApiKey: ocrSpaceKey.isNotEmpty ? ocrSpaceKey : null,  // ✅ جديد
      );
      
      final data = await aiService.extractInvoiceOrReceiptStructured(
        fileBytes: _pickedBytes!,
        fileMimeType: _pickedMime!,
        extractType: 'invoice',
        products: _allProducts.map((p) => {
          'id': p.id,
          'name': p.name,
          'cost_price': p.costPrice,
        }).toList(),
      );
      
      final date = (data['invoice_date'] ?? '').toString();
      final num = (data['invoice_number'] ?? '').toString();
      final total = (data['totals']?['grand_total'] ?? data['grand_total'] ?? data['total'] ?? '');
      final lineItems = data['line_items'] as List<dynamic>? ?? [];
      
      setState(() {
        if (date.isNotEmpty) _dateCtrl.text = date;
        if (num.isNotEmpty) _numberCtrl.text = num;
        if (total != null && total.toString().isNotEmpty) { 
          _totalCtrl.text = _nf.format(double.tryParse(total.toString()) ?? 0); 
        }
        
        // Add extracted items
        _items.clear();
        for (var item in lineItems) {
          final matchedId = item['matched_product_id'];
          final name = item['name']?.toString() ?? 'منتج غير معروف';
          final originalName = item['original_name']?.toString() ?? name;
          final qty = double.tryParse(item['qty']?.toString() ?? '0') ?? 0.0;
          final price = double.tryParse(item['price']?.toString() ?? '0') ?? 0.0;
          final amount = double.tryParse(item['amount']?.toString() ?? '0') ?? (qty * price);
          final reason = item['reason']?.toString() ?? '';
          final unitType = item['unit_type']?.toString() ?? 'piece';
          final unitsCount = double.tryParse(item['units_count']?.toString() ?? '1') ?? 1.0;
          
          // For meter products, calculate cost per meter (not per roll)
          // price is the roll price, unitsCount is meters per roll
          double unitPrice = price;
          String? unit;
          if (unitType == 'meter' && unitsCount > 1) {
            unitPrice = price / unitsCount; // cost per meter
            unit = 'متر';
          } else {
            unit = 'قطعة';
          }
          
          _items.add(SupplierInvoiceItem(
            invoiceId: 0, // سيتم تحديثه لاحقاً
            productId: matchedId != null ? int.tryParse(matchedId.toString()) : null,
            productName: name,
            quantity: qty,
            unitPrice: unitPrice, // cost per meter for meter products
            totalPrice: amount,
            unit: unit,
            notes: reason.isNotEmpty ? "AI: $reason | الأصلي: $originalName" : "الأصلي: $originalName",
          ));
        }
        _recalculateTotal();
      });
      
      if (mounted) {
        final providerName = aiService.currentProvider == 'gemini' ? 'Gemini' : 'Scitely (احتياطي)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم الاستخراج بواسطة $providerName: ${_items.length} منتج'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحليل: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _onSave([bool isDraft = false]) async {
    if (!_formKey.currentState!.validate()) return;
    
    // منع الضغط المتكرر
    if (_saving) return;
    
    setState(() => _saving = true);
    
    try {
      print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🚀 بدء عملية الحفظ...');
      
      final total = double.tryParse(_totalCtrl.text.replaceAll(',', '').trim()) ?? 0;
      final discount = double.tryParse(_discountCtrl.text.replaceAll(',', '').trim()) ?? 0;
      final paid = double.tryParse(_paidCtrl.text.replaceAll(',', '').trim()) ?? 0;
      
      // منطق تحويل العملات
      double exchangeRate = 1.0;
      if (_needsExchangeRate) {
        exchangeRate = double.tryParse(_exchangeRateCtrl.text.trim()) ?? 1.0;
        if (exchangeRate <= 0) exchangeRate = 1.0;
      }

      double convertedTotal = total;
      double convertedPaid = paid;
      double convertedDiscount = discount;
      
      // تحويل المبالغ لعملة المورد (للدين)
      if (_currency == 'USD' && widget.supplier.defaultCurrency == 'IQD') {
        convertedTotal = total * exchangeRate;
        convertedPaid = paid * exchangeRate;
        convertedDiscount = discount * exchangeRate;
      } else if (_currency == 'IQD' && widget.supplier.defaultCurrency == 'USD') {
        convertedTotal = total / exchangeRate;
        convertedPaid = paid / exchangeRate;
        convertedDiscount = discount / exchangeRate;
      }

      // تحويل التكلفة للدينار دائماً لتحديث أسعار المنتجات
      double costExchangeRate = 1.0;
      if (_currency == 'USD') {
        costExchangeRate = exchangeRate; // نحتاج السعر لتحويل التكلفة للدينار
      }
      
      final inv = SupplierInvoice(
        supplierId: widget.supplier.id!,
        delegateId: _selectedDelegate?.id,
        status: isDraft ? 'مسودة' : 'آجل',
        invoiceNumber: _numberCtrl.text.trim().isEmpty ? null : _numberCtrl.text.trim(),
        invoiceDate: DateTime.tryParse(_dateCtrl.text.trim()) ?? DateTime.now(),
        totalAmount: convertedTotal, // القيمة بعملة المورد
        discount: convertedDiscount, // القيمة بعملة المورد
        amountPaid: convertedPaid,   // القيمة بعملة المورد
        paymentType: _paymentType,
        currency: widget.supplier.defaultCurrency, // العملة التي يتسجل بها الدين
        exchangeRate: exchangeRate,
      );
      
      // الخطوة 1: حفظ الفاتورة
      print('📝 [1/5] حفظ الفاتورة (${isDraft ? 'كمسودة' : 'نهائية'})...');
      final invoiceId = await _service.insertSupplierInvoice(inv);
      print('✅ تم حفظ الفاتورة برقم: $invoiceId');
      
      // الخطوة 2: حفظ البنود
      print('📝 [2/5] حفظ ${_items.length} بنود...');
      int savedItems = 0;
      List<String> failedItems = [];
      
      for (var item in _items) {
        try {
          // تحويل سعر البند لعملة المورد للتخزين في الفاتورة (للمحاسبة)
          // وتجهيز سعر التكلفة بالدينار لتحديث قاعدة البيانات
          double itemConvertedUnitPrice = item.unitPrice;
          double itemConvertedTotalPrice = item.totalPrice;
          
          if (_currency == 'USD' && widget.supplier.defaultCurrency == 'IQD') {
            itemConvertedUnitPrice = item.unitPrice * exchangeRate;
            itemConvertedTotalPrice = item.totalPrice * exchangeRate;
          } else if (_currency == 'IQD' && widget.supplier.defaultCurrency == 'USD') {
            itemConvertedUnitPrice = item.unitPrice / exchangeRate;
            itemConvertedTotalPrice = item.totalPrice / exchangeRate;
          }

          item.invoiceId = invoiceId;
          final originalUnitPrice = item.unitPrice;
          final originalTotalPrice = item.totalPrice;
          
          item.unitPrice = itemConvertedUnitPrice;
          item.totalPrice = itemConvertedTotalPrice;
          
          await _service.insertInvoiceItem(item);
          savedItems++;
          print('  ✓ حفظ بند $savedItems/${_items.length}: ${item.productName}');
          
          // إعادة القيم الأصلية للبند (لأغراض العرض إذا لزم الأمر أو الاستمرار في الحلقة)
          // ملاحظة: التحديث الفعلي للتكاليف في الخطوة 3 سيستخدم القيم المخزنة في InvoiceItem
          // والتي أصبحت الآن بعملة المورد. 
          // إذا كانت عملة المورد دولار، updateProductCostsFromInvoice سيعمل بالدولار؟
          // يجب التأكد أن updateProductCostsFromInvoice يحول للدينار.

        } catch (e) {
          print('  ❌ فشل حفظ بند: ${item.productName} - خطأ: $e');
          failedItems.add(item.productName);
        }
      }
      
      // التحقق من أن جميع البنود حُفظت بنجاح
      if (savedItems != _items.length) {
        final errorMsg = 'فشل حفظ ${_items.length - savedItems} من ${_items.length} بند!\nالبنود الفاشلة: ${failedItems.join(", ")}';
        print('❌ $errorMsg');
        throw Exception(errorMsg);
      }
      
      print('✅ تم حفظ جميع البنود بنجاح ($savedItems/${_items.length})');
      
      // التحقق النهائي: قراءة البنود من قاعدة البيانات للتأكد
      print('🔍 [2.5/5] التحقق من البنود في قاعدة البيانات...');
      final savedItemsInDb = await _service.getInvoiceItems(invoiceId);
      if (savedItemsInDb.length != _items.length) {
        final errorMsg = 'خطأ في التحقق: تم حفظ ${savedItemsInDb.length} بند في قاعدة البيانات بدلاً من ${_items.length}!';
        print('❌ $errorMsg');
        throw Exception(errorMsg);
      }
      print('✅ تم التحقق: جميع البنود موجودة في قاعدة البيانات (${savedItemsInDb.length}/${_items.length})');
      
      // الخطوة 3: تحديث أسعار المنتجات
      print('🔄 [3/5] تحديث أسعار المنتجات...');
      final updatedProducts = await _service.updateProductCostsFromInvoice(invoiceId);
      print('✅ تم تحديث ${updatedProducts.length} منتج');
      
      // الخطوة 4: حفظ المرفق
      if (_pickedBytes != null && _pickedMime != null) {
        print('📎 [4/5] حفظ المرفق...');
        final ext = _pickedMime == 'application/pdf' ? 'pdf' : (_pickedMime == 'image/png' ? 'png' : 'jpg');
        final path = await _service.saveAttachmentFile(bytes: _pickedBytes!, extension: ext);
        await _service.insertAttachment(Attachment(
          ownerType: 'SupplierInvoice',
          ownerId: invoiceId,
          filePath: path,
          fileType: ext == 'pdf' ? 'pdf' : 'image',
          extractedText: null,
          extractionConfidence: null,
        ));
        print('✅ تم حفظ المرفق');
      } else {
        print('⏭️ [4/5] لا يوجد مرفق');
      }
      
      // الخطوة 5: عرض رسالة التحديث (إذا لزم الأمر)
      if (updatedProducts.isNotEmpty && mounted) {
        print('📢 [5/5] عرض رسالة التحديث...');
        await showDialog<bool>(
          context: context,
          barrierDismissible: false, // منع الإغلاق بالنقر خارج الحوار
          builder: (context) => WillPopScope(
            onWillPop: () async => false, // منع الإغلاق بزر الرجوع
            child: AlertDialog(
              title: const Text('✅ تم الحفظ بنجاح'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تم تحديث أسعار المنتجات التالية:'),
                    const SizedBox(height: 8),
                    ...updatedProducts.map((p) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• $p', style: const TextStyle(fontSize: 14)),
                    )),
                  ],
                ),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('موافق'),
                ),
              ],
            ),
          ),
        );
      } else {
        print('⏭️ [5/5] لا توجد منتجات محدثة');
      }
      
      print('✅ اكتملت جميع العمليات بنجاح');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
      
      // العودة إلى الشاشة السابقة
      if (!mounted) return;
      Navigator.of(context).pop(true);
      
    } catch (e, stackTrace) {
      print('❌ خطأ في الحفظ: $e');
      print('Stack trace: $stackTrace');
      
      if (!mounted) return;
      
      // عرض رسالة خطأ واضحة
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('❌ فشل الحفظ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('حدث خطأ أثناء حفظ الفاتورة:'),
                const SizedBox(height: 8),
                Text(
                  e.toString(),
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
      
      // إعادة تفعيل الزر في حالة الخطأ فقط
      if (mounted) setState(() => _saving = false);
    }
    // ملاحظة: لا يوجد finally هنا - الزر يبقى معطلاً حتى تكتمل العملية أو يحدث خطأ
  }

  void _onFormatNumber(TextEditingController ctrl) {
    if (_formatting) return;
    _formatting = true;
    final raw = ctrl.text.replaceAll(',', '').trim();
    if (raw.isEmpty) { _formatting = false; return; }
    final val = double.tryParse(raw);
    if (val != null) {
      ctrl.text = _nf.format(val);
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
    _formatting = false;
  }
}

// حوار إضافة منتج
class _AddItemDialog extends StatefulWidget {
  final List<Product> allProducts;
  final Function(SupplierInvoiceItem) onAdd;

  const _AddItemDialog({required this.allProducts, required this.onAdd});

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _productNameCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _totalPriceCtrl = TextEditingController(); // السعر الإجمالي للوحدة المختارة
  final _costPriceCtrl = TextEditingController(); // سعر التكلفة
  final _metersPerRollCtrl = TextEditingController(); // عدد الأمتار في اللفة
  Product? _selectedProduct;
  List<Product> _filteredProducts = [];
  String? _selectedUnit; // الوحدة المختارة (قطعة، كرتون، إلخ)
  String _unitType = 'piece'; // نوع الوحدة: piece أو meter
  List<String> _availableUnits = ['قطعة']; // الوحدات المتاحة
  Map<String, int> _unitQuantities = {}; // عدد القطع في كل وحدة
  final _calculatedCostCtrl = TextEditingController(); // التكلفة المحسوبة للقطعة

  @override
  void dispose() {
    _productNameCtrl.dispose();
    _quantityCtrl.dispose();
    _totalPriceCtrl.dispose();
    _costPriceCtrl.dispose();
    _metersPerRollCtrl.dispose();
    _calculatedCostCtrl.dispose();
    super.dispose();
  }

  void _searchProducts(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredProducts = [];
      });
      return;
    }
    
    setState(() {
      _filteredProducts = widget.allProducts
          .where((p) => p.name.contains(query))
          .take(10)
          .toList();
    });
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _productNameCtrl.text = product.name;
      _filteredProducts = [];
      
      // تحديد نوع الوحدة من المنتج
      _unitType = product.unit; // 'piece' أو 'meter'
      
      // بناء قائمة الوحدات المتاحة
      _availableUnits = ['قطعة'];
      _unitQuantities = {};
      
      if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
        try {
          final List<dynamic> hierarchy = json.decode(product.unitHierarchy!);
          int cumulativeQty = 1;
          for (var level in hierarchy) {
            final unitName = level['unit_name'] as String?;
            final qty = level['quantity'] as int?;
            if (unitName != null && qty != null && qty > 0) {
              cumulativeQty *= qty;
              _availableUnits.add(unitName);
              _unitQuantities[unitName] = cumulativeQty;
            }
          }
        } catch (e) {
          print('خطأ في قراءة الهرمية: $e');
        }
      }
      
      // إذا كان المنتج بالمتر، أضف خيار اللفة
      if (_unitType == 'meter') {
        if (!_availableUnits.contains('لفة')) {
          _availableUnits.add('لفة');
          // عدد الأمتار في اللفة
          if (product.lengthPerUnit != null && product.lengthPerUnit! > 0) {
            _unitQuantities['لفة'] = product.lengthPerUnit!.toInt();
            _metersPerRollCtrl.text = product.lengthPerUnit!.toString();
          }
        }
      }
      
      _selectedUnit = 'قطعة';
      _costPriceCtrl.text = (product.costPrice ?? 0).toString();
      _totalPriceCtrl.text = (product.costPrice ?? 0).toString();
      _recalculateCost();
    });
  }

  void _recalculateCost() {
    if (_totalPriceCtrl.text.isEmpty  || _selectedUnit == null) return;
    
    final totalPrice = double.tryParse(_totalPriceCtrl.text.trim()) ?? 0;
    if (_selectedUnit == 'قطعة') {
      _calculatedCostCtrl.text = totalPrice.toStringAsFixed(2);
    } else {
      final unitQty = _unitQuantities[_selectedUnit] ?? 1;
      final costPerPiece = totalPrice / unitQty;
      _calculatedCostCtrl.text = costPerPiece.toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة منتج'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // حقل اسم المنتج مع البحث
              TextFormField(
                controller: _productNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المنتج',
                  hintText: 'ابحث عن منتج...',
                ),
                onChanged: _searchProducts,
                validator: (v) => (v == null || v.isEmpty) ? 'أدخل اسم المنتج' : null,
              ),
              // نتائج البحث
              if (_filteredProducts.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      return ListTile(
                        title: Text(product.name),
                        subtitle: Text('التكلفة: ${product.costPrice?.toStringAsFixed(2) ?? '-'}'),
                        onTap: () => _selectProduct(product),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              // نوع المنتج: قطعة أو متر
              DropdownButtonFormField<String>(
                value: _unitType,
                decoration: const InputDecoration(
                  labelText: 'نوع البيع',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: const [
                  DropdownMenuItem(value: 'piece', child: Text('قطعة')),
                  DropdownMenuItem(value: 'meter', child: Text('متر')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _unitType = v;
                      // إذا تحول إلى متر، أضف خيار اللفة
                      if (v == 'meter' && !_availableUnits.contains('لفة')) {
                        _availableUnits.add('لفة');
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              // إذا كان المنتج بالمتر، أظهر حقل عدد الأمتار في اللفة
              if (_unitType == 'meter')
                TextFormField(
                  controller: _metersPerRollCtrl,
                  decoration: const InputDecoration(
                    labelText: 'عدد الأمتار في اللفة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.straighten),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    if (v.isNotEmpty) {
                      final meters = double.tryParse(v);
                      if (meters != null && meters > 0) {
                        setState(() {
                          _unitQuantities['لفة'] = meters.toInt();
                        });
                      }
                    }
                  },
                ),
              if (_unitType == 'meter') const SizedBox(height: 12),
              // اختيار الوحدة
              if (_selectedProduct != null)
                DropdownButtonFormField<String>(
                  value: _selectedUnit,
                  decoration: const InputDecoration(labelText: 'الوحدة في الفاتورة'),
                  items: _availableUnits.map((unit) {
                    String label = unit;
                    if (unit != 'قطعة' && _unitQuantities.containsKey(unit)) {
                      label = '$unit (${_unitQuantities[unit]} قطعة)';
                    }
                    return DropdownMenuItem(value: unit, child: Text(label));
                  }).toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedUnit = v;
                      _recalculateCost();
                    });
                  },
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityCtrl,
                decoration: InputDecoration(
                  labelText: 'الكمية ($_selectedUnit)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.production_quantity_limits),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'أدخل كمية صحيحة' : null,
              ),
              const SizedBox(height: 12),
              // سعر التكلفة
              TextFormField(
                controller: _costPriceCtrl,
                decoration: const InputDecoration(
                  labelText: 'سعر التكلفة',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money),
                  helperText: 'سعر التكلفة للقطعة الواحدة',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) {
                  // تحديث السعر الإجمالي بناءً على الوحدة المختارة
                  if (v.isNotEmpty) {
                    final cost = double.tryParse(v);
                    if (cost != null) {
                      if (_selectedUnit == 'قطعة') {
                        _totalPriceCtrl.text = cost.toString();
                      } else {
                        final unitQty = _unitQuantities[_selectedUnit] ?? 1;
                        _totalPriceCtrl.text = (cost * unitQty).toString();
                      }
                      _recalculateCost();
                    }
                  }
                },
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'أدخل سعر صحيح' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _totalPriceCtrl,
                decoration: InputDecoration(
                  labelText: 'سعر التكلفة الإجمالي (لـ $_selectedUnit)',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.calculate),
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _recalculateCost(),
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'أدخل سعر صحيح' : null,
              ),
              const SizedBox(height: 12),
              // التكلفة المحسوبة للقطعة
              if (_calculatedCostCtrl.text.isNotEmpty && _selectedUnit != 'قطعة')
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تكلفة القطعة: ${_calculatedCostCtrl.text} دينار',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            
            final quantity = double.parse(_quantityCtrl.text.trim());
            final totalPriceForUnit = double.parse(_totalPriceCtrl.text.trim());
            final costPrice = double.tryParse(_costPriceCtrl.text.trim()) ?? totalPriceForUnit;
            
            // حساب سعر القطعة
            double unitPricePerPiece;
            if (_selectedUnit == 'قطعة') {
              unitPricePerPiece = totalPriceForUnit;
            } else {
              final unitQty = _unitQuantities[_selectedUnit] ?? 1;
              unitPricePerPiece = totalPriceForUnit / unitQty;
            }
            
            // بناء ملاحظات تحتوي على معلومات إضافية
            String? notes;
            if (_selectedUnit != 'قطعة') {
              notes = 'من $_selectedUnit (${_unitQuantities[_selectedUnit]} قطعة) بسعر $totalPriceForUnit';
            }
            if (_unitType == 'meter' && _metersPerRollCtrl.text.isNotEmpty) {
              final metersInfo = ' | نوع: متر | عدد الأمتار في اللفة: ${_metersPerRollCtrl.text}';
              notes = (notes ?? '') + metersInfo;
            }
            
            final item = SupplierInvoiceItem(
              invoiceId: 0, // سيتم تحديثه لاحقاً
              productId: _selectedProduct?.id,
              productName: _productNameCtrl.text.trim(),
              quantity: quantity,
              unitPrice: unitPricePerPiece, // سعر القطعة الواحدة
              totalPrice: quantity * totalPriceForUnit, // الإجمالي في الفاتورة
              unit: _selectedUnit,
              notes: notes?.isEmpty == true ? null : notes,
            );
            
            widget.onAdd(item);
            Navigator.pop(context);
          },
          child: const Text('إضافة'),
        ),
      ],
    );
  }
}
