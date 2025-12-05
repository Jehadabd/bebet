// screens/edit_invoices_screen.dart
// screens/edit_invoices_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/invoice.dart';
import 'create_invoice_screen.dart';
import 'package:intl/intl.dart'; // Import for NumberFormat
import '../services/database_service.dart'; // Added for DatabaseService
import '../models/product.dart'; // Added for Product model
import '../models/invoice_adjustment.dart'; // Added for InvoiceAdjustment model
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../services/invoice_pdf_service.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';

class EditInvoicesScreen extends StatefulWidget {
  const EditInvoicesScreen({super.key});

  @override
  State<EditInvoicesScreen> createState() => _EditInvoicesScreenState();
}

class _EditInvoicesScreenState extends State<EditInvoicesScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  String _searchName = '';
  String _searchId = '';
  List<Invoice> _filteredInvoices = [];
  List<Invoice> _allInvoices = [];
  bool _loading = true;
  Map<int, List<InvoiceAdjustment>> _invoiceAdjustments = {};
  Map<int, double> _settlementTotals = {}; // إجمالي التسويات لكل فاتورة

  @override
  void initState() {
    super.initState();
    _fetchInvoices();
    _nameController.addListener(_onNameChanged);
    _idController.addListener(_onIdChanged);
  }

  void _fetchInvoices() async {
    setState(() => _loading = true);
    // Ensure `listen: false` when calling provider methods in initState or async methods
    final provider = Provider.of<AppProvider>(context, listen: false);
    final invoices = await provider.getAllInvoices();
    
    // جلب معلومات التسويات لكل فاتورة
    final db = DatabaseService();
    Map<int, List<InvoiceAdjustment>> adjustments = {};
    Map<int, double> totals = {};
    
    for (final invoice in invoices) {
      final invoiceAdjustments = await db.getInvoiceAdjustments(invoice.id!);
      adjustments[invoice.id!] = invoiceAdjustments;
      
      // حساب إجمالي التسويات (amountDelta يحمل الإشارة: موجب للزيادة وسالب للإرجاع)
      double total = 0.0;
      for (final adj in invoiceAdjustments) {
        total += adj.amountDelta;
      }
      totals[invoice.id!] = total;
    }
    
    setState(() {
      _allInvoices = invoices;
      _invoiceAdjustments = adjustments;
      _settlementTotals = totals;
      _applyFilters();
      _loading = false;
    });
  }

  void _onNameChanged() {
    setState(() {
      _searchName = _nameController.text.trim();
      _applyFilters();
    });
  }

  void _onIdChanged() {
    setState(() {
      _searchId = _idController.text.trim();
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Invoice> filtered = _allInvoices;
    if (_searchName.isNotEmpty) {
      filtered = filtered
          .where((inv) => inv.customerName
              .toLowerCase()
              .contains(_searchName.toLowerCase()))
          .toList();
    }
    if (_searchId.isNotEmpty) {
      final id = int.tryParse(_searchId);
      if (id != null) {
        filtered = filtered.where((inv) => inv.id == id).toList();
      }
    }
    _filteredInvoices = filtered;
  }

  // دالة لاعتراض زر الرجوع
  Future<bool> _onWillPop() async {
    // في شاشة تعديل الفواتير، لا نحتاج لمعالجة خاصة
    // لأنها لا تحتوي على تعديلات غير محفوظة
    return true;
  }

  @override
  void dispose() {
    _nameController
        .removeListener(_onNameChanged); // Remove listeners before disposing
    _idController
        .removeListener(_onIdChanged); // Remove listeners before disposing
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
  }

  // Helper to format currency consistently
  String formatCurrency(num value) {
    return NumberFormat('#,##0.00', 'en_US')
        .format(value); // Thousand separators + two decimals
  }

  @override
  Widget build(BuildContext context) {
    // Define the consistent theme colors for the screen
    final Color primaryColor = const Color(0xFF3F51B5); // Indigo 700
    final Color accentColor =
        const Color(0xFF8C9EFF); // Light Indigo Accent (Indigo A200)
    final Color textColor =
        const Color(0xFF212121); // Dark grey for general text
    final Color lightBackgroundColor =
        const Color(0xFFF8F8F8); // Very light grey for text field fill
    final Color successColor = Colors.green[600]!; // Green for success messages
    final Color errorColor = Colors.red[700]!; // Red for error messages

    return Theme(
      data: ThemeData(
        // Define color scheme for light theme
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white, // Text/icons on primary color
          secondary: accentColor,
          onSecondary: Colors.black, // Text/icons on secondary color
          surface: Colors.white, // Card/sheet background
          onSurface: textColor, // Text/icons on surface
          background: Colors.white, // Scaffold background
          onBackground: textColor, // Text/icons on background
          error: errorColor,
          onError: Colors.white, // Text/icons on error color
          tertiary: successColor, // Custom color for success, used in SnackBars
        ),
        // Define typography (font family and text styles)
        fontFamily: 'Roboto', // Modern, clean font
        textTheme: TextTheme(
          titleLarge: TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.bold,
              color: Colors.white), // AppBar title
          titleMedium: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: textColor), // Section titles
          bodyLarge:
              TextStyle(fontSize: 16.0, color: textColor), // General body text
          bodyMedium:
              TextStyle(fontSize: 14.0, color: textColor), // Smaller body text
          labelLarge: TextStyle(
              fontSize: 16.0,
              color: Colors.white,
              fontWeight: FontWeight.w600), // Button text
          labelMedium: TextStyle(
              fontSize: 14.0, color: Colors.grey[600]), // Input field labels
          bodySmall: TextStyle(
              fontSize: 12.0, color: Colors.grey[700]), // Hint text / captions
        ),
        // Define input field decoration theme
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            // Default border style
            borderRadius: BorderRadius.circular(10.0), // Rounded corners
            borderSide:
                BorderSide(color: Colors.grey[400]!), // Light grey border
          ),
          enabledBorder: OutlineInputBorder(
            // Border when enabled and not focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder(
            // Border when focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
                color: primaryColor, width: 2.0), // Primary color, thicker
          ),
          errorBorder: OutlineInputBorder(
            // Border when in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
                color: errorColor, width: 2.0), // Error color, thicker
          ),
          focusedErrorBorder: OutlineInputBorder(
            // Border when focused and in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          labelStyle: TextStyle(
              color: Colors.grey[700], fontSize: 15.0), // Label text style
          hintStyle: TextStyle(
              color: Colors.grey[500], fontSize: 14.0), // Hint text style
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16.0, horizontal: 16.0), // Inner padding
          filled: true, // Enable fill color
          fillColor: lightBackgroundColor, // Light background for fields
        ),
        // Define AppBar theme
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor, // AppBar background color
          foregroundColor: Colors.white, // AppBar text/icon color
          centerTitle: true, // Center title
          elevation: 4, // Shadow elevation
          titleTextStyle: TextStyle(
            // Title text style (inherits from TextTheme.titleLarge)
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        // Define Card theme
        cardTheme: CardThemeData(
          elevation: 3, // Consistent shadow for cards
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(12.0), // Rounded corners for cards
          ),
          margin: EdgeInsets
              .zero, // Reset default card margin to manage it manually
        ),
        // Define ListTile theme
        listTileTheme: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          tileColor: Colors.transparent, // Default transparent
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
        // Define TextButton theme (if any are used in future updates)
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        // Define IconButton theme (if any are used in future updates)
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
      ),
      child: WillPopScope(
        onWillPop: _onWillPop,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('تعديل القوائم (الفواتير)'),
            // The title style is now managed by appBarTheme.titleTextStyle
          ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color:
                      Color(0xFF3F51B5), // Explicitly set color for indicator
                ),
              )
            : Padding(
                padding:
                    const EdgeInsets.all(24.0), // Increased overall padding
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            // Changed from TextField to TextFormField for consistency
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'بحث باسم العميل',
                              prefixIcon: Icon(Icons.person_search,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary), // Themed icon
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge, // Themed text style
                          ),
                        ),
                        const SizedBox(width: 16), // Increased spacing
                        Expanded(
                          child: TextFormField(
                            // Changed from TextField to TextFormField for consistency
                            controller: _idController,
                            decoration: InputDecoration(
                              labelText: 'بحث برقم الفاتورة',
                              prefixIcon: Icon(
                                  Icons.confirmation_number_outlined,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary), // Themed icon
                            ),
                            keyboardType: TextInputType.number,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge, // Themed text style
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24), // Increased spacing
                    Expanded(
                      child: _filteredInvoices.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد قوائم مطابقة',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                        color: Colors
                                            .grey[600]), // Themed text style
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  vertical:
                                      12.0), // Padding for the list itself
                              itemCount: _filteredInvoices.length,
                              itemBuilder: (context, index) {
                                final invoice = _filteredInvoices[index];
                                return Card(
                                  // Card theme applied from ThemeData
                                  margin: const EdgeInsets.only(
                                      bottom: 12.0), // Spacing between cards
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 20.0,
                                        vertical:
                                            12.0), // Increased internal padding for ListTile
                                    title: Text(
                                      invoice.customerName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                          ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'التاريخ: ${DateFormat('yyyy/MM/dd').format(invoice.invoiceDate)}', // Consistent date format
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                  color: Colors.grey[
                                                      700]), // Themed text style
                                        ),
                                        // عرض معلومات التسويات
                                        if (_invoiceAdjustments[invoice.id]?.isNotEmpty == true) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.blue[50],
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.blue[200]!),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.edit, size: 16, color: Colors.blue[700]),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'تم تسويتها (${_invoiceAdjustments[invoice.id]!.length} تعديل)',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.blue[700],
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${_settlementTotals[invoice.id]! > 0 ? '+' : ''}${formatCurrency(_settlementTotals[invoice.id]!)}',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: _settlementTotals[invoice.id]! > 0 ? Colors.green[700] : Colors.red[700],
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Builder(
                                                  builder: (context) {
                                                    final double totalAfterDiscount = (invoice.totalAmount - invoice.discount);
                                                    final double totalAfterAdjustments = totalAfterDiscount + (_settlementTotals[invoice.id] ?? 0.0);
                                                    return Text(
                                                      'إجمالي القائمة بعد التعديلات: ${formatCurrency(totalAfterAdjustments)} دينار',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.blueGrey[800],
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${formatCurrency(invoice.totalAmount)} دينار',
                                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Theme.of(context).colorScheme.primary,
                                                  ),
                                            ),
                                            Text(
                                              invoice.status == 'معلقة' ? 'معلقة' : 'محفوظة',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: invoice.status == 'معلقة'
                                                        ? Theme.of(context).colorScheme.error
                                                        : Theme.of(context).colorScheme.tertiary,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          tooltip: 'مشاركة الفاتورة PDF',
                                          icon: const Icon(Icons.share),
                                          onPressed: () => _shareInvoicePdf(invoice),
                                        ),
                                      ],
                                    ),
                                    onTap: () async {
                                      // 🔍 DEBUG: طباعة عند فتح الفاتورة للتعديل
                                      print('═══════════════════════════════════════════════════════════════════');
                                      print('🔍 DEBUG OPEN: فتح الفاتورة رقم ${invoice.id} للتعديل/العرض');
                                      print('   - العميل: ${invoice.customerName}');
                                      print('   - الإجمالي: ${invoice.totalAmount}');
                                      print('   - الحالة: ${invoice.status}');
                                      print('   - isViewOnly: ${invoice.status == 'محفوظة'}');
                                      
                                      // جلب أصناف الفاتورة مع طباعة
                                      final items = await DatabaseService()
                                          .getInvoiceItems(invoice.id!);
                                      
                                      print('🔍 DEBUG OPEN: تم جلب ${items.length} صنف من قاعدة البيانات');
                                      for (int i = 0; i < items.length; i++) {
                                        final item = items[i];
                                        print('   [$i] ${item.productName}: ${item.quantityIndividual ?? item.quantityLargeUnit} × ${item.appliedPrice} = ${item.itemTotal}');
                                      }
                                      print('═══════════════════════════════════════════════════════════════════');
                                      
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              CreateInvoiceScreen(
                                            existingInvoice: invoice,
                                            isViewOnly: invoice.status == 'محفوظة', // الفواتير المحفوظة للعرض فقط، المعلقة للتعديل
                                          ),
                                        ),
                                      ).then((_) {
                                        _fetchInvoices();
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Future<void> _shareInvoicePdf(Invoice invoice) async {
    try {
      final db = DatabaseService();
      final items = await db.getInvoiceItems(invoice.id!);
      final products = await db.getAllProducts();

      // تحميل الخطوط والشعار
      final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      final alnaserFontData = await rootBundle.load('assets/fonts/PTBLDHAD.TTF');
      final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
      final font = pw.Font.ttf(fontData);
      final alnaserFont = pw.Font.ttf(alnaserFontData);
      final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

      // تحميل الإعدادات العامة
      final appSettings = await SettingsManager.getAppSettings();

      // احتساب أجور التحميل من الفرق بين إجمالي الفاتورة ومجموع البنود
      final double itemsTotal =
          items.fold(0.0, (sum, item) => sum + item.itemTotal);
      final double loadingFee = (invoice.totalAmount - itemsTotal);

      final doc = await InvoicePdfService.generateInvoicePdf(
        invoiceItems: items,
        allProducts: products,
        customerName: invoice.customerName,
        customerAddress: invoice.customerAddress ?? '',
        invoiceId: invoice.id ?? 0,
        selectedDate: invoice.invoiceDate,
        discount: invoice.discount,
        loadingFee: loadingFee,
        paid: invoice.amountPaidOnInvoice,
        paymentType: invoice.paymentType,
        invoiceToManage: invoice,
        previousDebt: 0,
        currentDebt: 0,
        afterDiscount: (invoice.totalAmount - invoice.discount),
        remaining: (invoice.totalAmount - invoice.discount - invoice.amountPaidOnInvoice),
        font: font,
        alnaserFont: alnaserFont,
        logoImage: logoImage,
        createdAt: invoice.createdAt,
        appSettings: appSettings,
      );

      // حفظ الملف
      final safeCustomerName = invoice.customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
      final formattedDate = DateFormat('yyyy-MM-dd').format(invoice.invoiceDate);
      final fileName = '${safeCustomerName}_$formattedDate.pdf';
      final directory = Directory('${Platform.environment['USERPROFILE']}/Documents/invoices');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(await doc.save());

      await Share.shareFiles([file.path], text: 'فاتورة ${invoice.customerName}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل مشاركة الفاتورة: $e')),
        );
      }
    }
  }

  Future<void> _openSettlementDialog(BuildContext context, int invoiceId) async {
    String type = 'debit';
    bool byItem = true;
    final db = DatabaseService();
    final TextEditingController productCtrl = TextEditingController();
    final TextEditingController qtyCtrl = TextEditingController();
    final TextEditingController priceCtrl = TextEditingController();
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    Product? selectedProduct;
    List<Product> productSuggestions = [];

    Future<void> fetchSuggestions(String q) async {
      if (q.trim().isEmpty) {
        productSuggestions = [];
      } else {
        productSuggestions = (await db.searchProductsSmart(q.trim())).take(10).toList();
      }
    }

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسوية الفاتورة'),
        content: StatefulBuilder(builder: (context, setLocal) {
          final double _maxH = MediaQuery.of(context).size.height * 0.7;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _maxH, minWidth: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    items: const [
                      DropdownMenuItem(value: 'debit', child: Text('إشعار مدين (زيادة)')),
                      DropdownMenuItem(value: 'credit', child: Text('إشعار دائن (نقص)')),
                    ],
                    onChanged: (v) => setLocal(() => type = v ?? 'debit'),
                    decoration: const InputDecoration(labelText: 'نوع التسوية'),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: ChoiceChip(label: const Text('بند'), selected: byItem, onSelected: (s){ setLocal(()=> byItem = true); })),
                    const SizedBox(width: 8),
                    Expanded(child: ChoiceChip(label: const Text('مبلغ مباشر'), selected: !byItem, onSelected: (s){ setLocal(()=> byItem = false); })),
                  ]),
                  const SizedBox(height: 8),
                  if (byItem) ...[
                    TextField(
                      controller: productCtrl,
                      decoration: const InputDecoration(labelText: 'المنتج', hintText: 'اكتب اسم المنتج'),
                      onChanged: (v) async {
                        selectedProduct = null;
                        await fetchSuggestions(v);
                        setLocal((){});
                      },
                    ),
                    if (productSuggestions.isNotEmpty)
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(6)),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: productSuggestions.length,
                          itemBuilder: (c,i){
                            final p = productSuggestions[i];
                            return ListTile(
                              dense: true,
                              title: Text(p.name),
                              subtitle: Text('ID: ${p.id ?? ''}'),
                              onTap: (){
                                selectedProduct = p;
                                productCtrl.text = p.name;
                                productSuggestions = [];
                                setLocal((){});
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(children:[
                      Expanded(child: TextField(controller: qtyCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'الكمية'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: priceCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'السعر'))),
                    ]),
                  ] else ...[
                    TextField(controller: amountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'مبلغ التسوية')),
                  ],
                  const SizedBox(height: 8),
                  TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
                ],
              ),
            ),
          );
        }),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () async {
            try {
              double delta = 0; int? productId; String? productName; double? qty; double? price;
              if (byItem) {
                if (selectedProduct == null) throw 'اختر منتجاً';
                qty = double.tryParse(qtyCtrl.text.trim());
                price = double.tryParse(priceCtrl.text.trim());
                if (qty == null || price == null) throw 'أدخل الكمية والسعر بشكل صحيح';
                delta = (qty * price).toDouble();
                productId = selectedProduct!.id;
                productName = selectedProduct!.name;
              } else {
                final v = double.tryParse(amountCtrl.text.trim());
                if (v == null) throw 'أدخل مبلغاً صحيحاً';
                delta = v;
              }
              if (type == 'credit') delta = -delta.abs(); else delta = delta.abs();
              await db.insertInvoiceAdjustment(InvoiceAdjustment(invoiceId: invoiceId, type: type, amountDelta: delta, productId: productId, productName: productName, quantity: qty, price: price, note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة التسوية')));
              }
              Navigator.pop(ctx, true);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            }
          }, child: const Text('حفظ')), 
        ],
      ),
    );
  }
}
