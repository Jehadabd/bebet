// screens/create_invoice_screen.dart
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../models/invoice_item.dart';
import '../models/invoice.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import '../models/transaction.dart';
import '../models/customer.dart';
import '../models/installer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/printing_service.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/pdf_service.dart';
import 'package:alnaser/services/printing_service_platform_io.dart';

class CreateInvoiceScreen extends StatefulWidget {
  final Invoice? existingInvoice;
  final bool isViewOnly;
  final DebtTransaction? relatedDebtTransaction;

  const CreateInvoiceScreen({
    super.key,
    this.existingInvoice,
    this.isViewOnly = false,
    this.relatedDebtTransaction,
  });

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerAddressController = TextEditingController();
  final _installerNameController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _quantityController = TextEditingController();
  final _itemsController = TextEditingController();
  final _totalAmountController = TextEditingController();
  double? _selectedPriceLevel;
  DateTime _selectedDate = DateTime.now();
  bool _useLargeUnit = false;
  String _paymentType = 'نقد';
  final _paidAmountController = TextEditingController();
  double _discount = 0.0;
  final _discountController = TextEditingController();

  String formatNumber(num value) {
    if (value % 1 == 0) {
      return value.toInt().toString();
    } else {
      return value.toStringAsFixed(2);
    }
  }

  List<Product> _searchResults = [];
  Product? _selectedProduct;
  List<InvoiceItem> _invoiceItems = [];

  final DatabaseService _db = DatabaseService();
  PrinterDevice? _selectedPrinter;
  late final PrintingService _printingService;

  @override
  void initState() {
    super.initState();
    _printingService = getPlatformPrintingService();
    if (widget.existingInvoice != null) {
      print(
          'CreateInvoiceScreen: Init with existing invoice: ${widget.existingInvoice!.id}');
      print('Invoice Status on Init: ${widget.existingInvoice!.status}');
      print('Is View Only on Init: ${widget.isViewOnly}');
      // Load existing invoice data
      _customerNameController.text = widget.existingInvoice!.customerName;
      _customerPhoneController.text =
          widget.existingInvoice!.customerPhone ?? '';
      _customerAddressController.text =
          widget.existingInvoice!.customerAddress ?? '';
      _installerNameController.text =
          widget.existingInvoice!.installerName ?? '';
      _selectedDate = widget.existingInvoice!.invoiceDate;
      _paymentType = widget.existingInvoice!.paymentType; // Load payment type
      _totalAmountController.text =
          widget.existingInvoice!.totalAmount.toString();
      _paidAmountController.text = widget.existingInvoice!.amountPaidOnInvoice
          .toString(); // Load amount paid
      _discount = widget.existingInvoice!.discount; // Load discount
      _discountController.text = _discount.toStringAsFixed(2);

      // Load invoice items
      _loadInvoiceItems();
    } else {
      print('CreateInvoiceScreen: Init with new invoice');
      // For new invoices, initialize total amount controller
      _totalAmountController.text = '0.00';
    }
  }

  Future<void> _loadInvoiceItems() async {
    if (widget.existingInvoice != null && widget.existingInvoice!.id != null) {
      // Ensure invoice and its ID are not null
      try {
        final items = await _db.getInvoiceItems(widget.existingInvoice!.id!);
        setState(() {
          _invoiceItems = items;
          // Update total amount based on loaded items (important for existing invoices)
          _totalAmountController.text = _invoiceItems
              .fold(0.0, (sum, item) => sum + item.itemTotal)
              .toStringAsFixed(2);
        });
      } catch (e) {
        print('Error loading invoice items: $e');
        // Optionally show an error message to the user
      }
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerAddressController.dispose();
    _installerNameController.dispose();
    _productSearchController.dispose();
    _quantityController.dispose();
    _paidAmountController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ar', 'SA'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _searchProducts(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }
    final results = await _db.searchProducts(query);
    setState(() {
      _searchResults = results;
    });
  }

  void _addInvoiceItem() {
    if (_formKey.currentState!.validate() &&
        _selectedProduct != null &&
        _selectedPriceLevel != null) {
      final quantity = double.tryParse(_quantityController.text.trim()) ?? 0.0;
      if (quantity <= 0) return;
      double itemCostPriceForInvoiceItem;
      double appliedPricePerUnitSold;
      double quantitySold;
      final unitsInLargeUnit = (_selectedProduct!.unit == 'piece'
              ? _selectedProduct!.piecesPerUnit
              : _selectedProduct!.lengthPerUnit) ??
          1.0;
      String saleType = '';
      if (_selectedProduct!.unit == 'piece') {
        saleType = _useLargeUnit ? 'ك' : 'ق';
      } else if (_selectedProduct!.unit == 'meter') {
        saleType = _useLargeUnit ? 'ل' : 'م';
      }
      if (_useLargeUnit) {
        quantitySold = quantity;
        appliedPricePerUnitSold =
            (_selectedPriceLevel ?? _selectedProduct!.unitPrice ?? 0.0) *
                unitsInLargeUnit;
        final totalSmallUnits = quantity * unitsInLargeUnit;
        itemCostPriceForInvoiceItem =
            (_selectedProduct!.costPrice ?? 0.0) * totalSmallUnits;
      } else {
        quantitySold = quantity;
        appliedPricePerUnitSold =
            _selectedPriceLevel ?? _selectedProduct!.unitPrice ?? 0.0;
        itemCostPriceForInvoiceItem =
            (_selectedProduct!.costPrice ?? 0.0) * quantitySold;
      }
      final newItem = InvoiceItem(
        invoiceId: 0,
        productName: _selectedProduct!.name,
        unit: _selectedProduct!.unit,
        unitPrice: _selectedProduct!.unitPrice,
        costPrice: itemCostPriceForInvoiceItem,
        quantityIndividual: _useLargeUnit ? null : quantitySold,
        quantityLargeUnit: _useLargeUnit ? quantitySold : null,
        appliedPrice: appliedPricePerUnitSold,
        itemTotal: quantitySold * appliedPricePerUnitSold,
        saleType: saleType,
      );
      setState(() {
        _invoiceItems.add(newItem);
        _productSearchController.clear();
        _quantityController.clear();
        _selectedProduct = null;
        _selectedPriceLevel = null;
        _useLargeUnit = false;
        _searchResults = [];
      });
    }
  }

  void _removeInvoiceItem(int index) {
    setState(() {
      _invoiceItems.removeAt(index);
    });
  }

  Future<void> _saveInvoice() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      // Find or create customer BEFORE creating the invoice object
      Customer? customer;
      if (_customerNameController.text.trim().isNotEmpty) {
        // Attempt to find customer by name and optionally phone
        final customers =
            await _db.getAllCustomers(); // Consider optimizing this search
        try {
          customer = customers.firstWhere(
            (c) =>
                c.name.trim() == _customerNameController.text.trim() &&
                (c.phone == null ||
                    c.phone!.isEmpty ||
                    _customerPhoneController.text.trim().isEmpty ||
                    c.phone ==
                        _customerPhoneController.text
                            .trim()), // Modified condition
          );
        } catch (e) {
          customer = null; // Customer not found
        }

        if (customer == null) {
          // Create a new customer if not found
          customer = Customer(
            id: null,
            name: _customerNameController.text.trim(),
            phone: _customerPhoneController.text.trim().isEmpty
                ? null
                : _customerPhoneController.text.trim(),
            address: _customerAddressController.text.trim(),
            createdAt: DateTime.now(),
            lastModifiedAt: DateTime.now(),
            currentTotalDebt: 0.0,
          );
          final insertedId = await _db.insertCustomer(customer);
          customer = customer.copyWith(id: insertedId);
        }
      }

      double currentTotalAmount =
          _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      double paid = double.tryParse(_paidAmountController.text) ?? 0.0;
      double debt = (currentTotalAmount - _discount) - paid;
      double totalAmount = currentTotalAmount - _discount;

      print('DEBUG: currentTotalAmount: $currentTotalAmount');
      print('DEBUG: _discount: $_discount');
      print('DEBUG: paid: $paid');
      print('DEBUG: calculated debt: $debt');

      Invoice invoice = Invoice(
        id: widget.existingInvoice?.id,
        customerName: _customerNameController.text,
        customerPhone: _customerPhoneController.text,
        customerAddress: _customerAddressController.text,
        installerName: _installerNameController.text.isEmpty
            ? null
            : _installerNameController.text,
        invoiceDate: _selectedDate,
        paymentType: _paymentType,
        totalAmount: totalAmount,
        discount: _discount,
        amountPaidOnInvoice: paid,
        createdAt: widget.existingInvoice?.createdAt ?? DateTime.now(),
        lastModifiedAt: DateTime.now(),
        customerId: customer?.id,
        status: 'محفوظة',
      );

      // Check if installer exists and add if not
      if (invoice.installerName != null && invoice.installerName!.isNotEmpty) {
        final existingInstaller =
            await _db.getInstallerByName(invoice.installerName!);
        if (existingInstaller == null) {
          final newInstaller = Installer(
            id: null,
            name: invoice.installerName!,
            totalBilledAmount: 0.0, // Starting amount is zero
          );
          await _db.insertInstaller(newInstaller);
        }
      }

      int invoiceId;
      if (widget.existingInvoice != null) {
        invoiceId = widget.existingInvoice!.id!;
        await context
            .read<AppProvider>()
            .updateInvoice(invoice); // Use AppProvider to update and notify
        print(
            'Updated existing invoice via AppProvider. Invoice ID: $invoiceId, New Status: ${invoice.status}');
      } else {
        invoiceId = await _db
            .insertInvoice(invoice); // For new invoices, still insert directly
        // Update the invoice object with the new ID for potential use later if needed
        if (invoice.id == null) {
          invoice = invoice.copyWith(id: invoiceId);
        }
        print(
            'Inserted new invoice. Invoice ID: $invoiceId, Status: ${invoice.status}');
      }

      // إذا كانت الفاتورة بالدين، أضف المبلغ فورًا إلى حساب العميل (جديد أو موجود)
      if (_paymentType == 'دين' && customer != null && debt > 0) {
        final updatedCustomer = customer.copyWith(
          currentTotalDebt: (customer.currentTotalDebt) + debt,
          lastModifiedAt: DateTime.now(),
        );
        await _db.updateCustomer(updatedCustomer);

        // Record the debt transaction
        final debtTransaction = DebtTransaction(
          id: null,
          customerId: customer.id!,
          amountChanged: debt, // Positive for new debt
          transactionType: 'invoice_debt',
          description:
              'دين فاتورة رقم ${invoiceId ?? widget.existingInvoice?.id}',
          newBalanceAfterTransaction: updatedCustomer.currentTotalDebt,
          invoiceId: invoiceId, // Link to the invoice
        );
        await _db.insertDebtTransaction(debtTransaction);
      }

      // Save invoice items (ensure they are linked to the correct invoice ID)
      for (var item in _invoiceItems) {
        item.invoiceId = invoiceId; // Assign the correct invoice ID
        if (item.id == null) {
          await _db.insertInvoiceItem(
              item); // Assuming you have insertInvoiceItem method
        } else {
          await _db.updateInvoiceItem(
              item); // Assuming you have updateInvoiceItem method
        }
      }
      // رسالة توضيحية للعميل عن الدين
      String extraMsg = '';
      if (_paymentType == 'دين') {
        extraMsg =
            '\nتمت إضافة ${debt.toStringAsFixed(2)} دينار كدين للعميل لأن الفاتورة ${currentTotalAmount.toStringAsFixed(2)} - خصم ${_discount.toStringAsFixed(2)} - مسدد ${paid.toStringAsFixed(2)}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الفاتورة بنجاح$extraMsg'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      // نستخدم رسالة الخطأ المفهومة التي جاءت مع الاستثناء من DatabaseService
      String errorMessage =
          'حدث خطأ عند حفظ الفاتورة: ${e.toString()}'; // رسالة افتراضية
      // The _handleDatabaseError is in DatabaseService, not here.
      // We can refine error handling later if needed.

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage), // عرض الرسالة المفهومة
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _suspendInvoice() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      Customer? customer;
      int? customerId;
      if (_customerNameController.text.trim().isNotEmpty) {
        // Only search for an existing customer, do NOT create a new one.
        final customers =
            await _db.searchCustomers(_customerNameController.text.trim());
        customer = customers.isNotEmpty ? customers.first : null;
        customerId = customer?.id; // Set customerId only if customer exists
      }
      double currentTotalAmount =
          _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      double totalAmount = currentTotalAmount - _discount;
      double paid = double.tryParse(_paidAmountController.text.trim()) ?? 0.0;
      final invoice = Invoice(
        customerName: _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim(),
        customerAddress: _customerAddressController.text.trim(),
        installerName: _installerNameController.text.trim(),
        invoiceDate: _selectedDate,
        paymentType: _paymentType,
        totalAmount: totalAmount,
        discount: _discount,
        amountPaidOnInvoice: paid,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
        customerId: customerId,
        status: 'معلقة',
      );
      final invoiceId = await _db.insertInvoice(invoice);
      print(
          'Suspended invoice. Invoice ID: $invoiceId, Status: ${invoice.status}');
      for (final item in _invoiceItems) {
        await _db.insertInvoiceItem(item.copyWith(invoiceId: invoiceId));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'تم تعليق الفاتورة بنجاح ويمكن تعديلها لاحقاً من القوائم المعلقة.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      String errorMessage = 'حدث خطأ عند تعليق الفاتورة: \${e.toString()}';
      print('Error suspending invoice: $e'); // Log error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  // دالة توليد ملف PDF للفاتورة
  Future<pw.Document> _generateInvoicePdf() async {
    final pdf = pw.Document();
    final font =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    final currentTotalAmount =
        _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final discount = _discount;
    final afterDiscount =
        (currentTotalAmount - discount).clamp(0, double.infinity);

    // --- منطق الحساب السابق والحالي ---
    double previousDebt = 0.0;
    double currentDebt = 0.0;
    final customerName = _customerNameController.text.trim();
    final customerPhone = _customerPhoneController.text.trim();
    if (customerName.isNotEmpty) {
      final customers = await _db.searchCustomers(customerName);
      Customer? matchedCustomer;
      if (customerPhone.isNotEmpty) {
        matchedCustomer = customers
                .where(
                  (c) =>
                      c.name.trim() == customerName &&
                      (c.phone ?? '').trim() == customerPhone,
                )
                .isNotEmpty
            ? customers
                .where(
                  (c) =>
                      c.name.trim() == customerName &&
                      (c.phone ?? '').trim() == customerPhone,
                )
                .first
            : null;
      } else {
        matchedCustomer = customers
                .where(
                  (c) => c.name.trim() == customerName,
                )
                .isNotEmpty
            ? customers
                .where(
                  (c) => c.name.trim() == customerName,
                )
                .first
            : null;
      }
      if (matchedCustomer != null) {
        previousDebt = matchedCustomer.currentTotalDebt;
      }
    }
    // حساب المتبقي من الفاتورة
    final paid = double.tryParse(_paidAmountController.text) ?? 0.0;
    final isCash = _paymentType == 'نقد';
    final remaining = isCash ? 0.0 : (afterDiscount - paid);
    // حساب الحساب الحالي
    if (isCash) {
      currentDebt = previousDebt;
    } else {
      currentDebt = previousDebt + remaining;
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // رأس الفاتورة الثابت
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('النــاصر',
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 32,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.green800)),
                        pw.Text('تجارة المواد الكهربائية والكابلات',
                            style: pw.TextStyle(font: font, fontSize: 18)),
                        pw.Text('الموصل - الجدعة، مقابل البرج',
                            style: pw.TextStyle(font: font, fontSize: 14)),
                        pw.Text('0773 284 5260  |  0770 304 0821',
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 14,
                                color: PdfColors.orange)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    // عرض الرقم التسلسلي للفاتورة
                    if (widget.existingInvoice?.serialNumber != null)
                      pw.Text(
                          'رقم الفاتورة: ${widget.existingInvoice!.serialNumber}',
                          style: pw.TextStyle(
                              font: font,
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 16)),
                    pw.Text(
                        'التاريخ: ${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}',
                        style: pw.TextStyle(font: font)),
                  ],
                ),
                pw.SizedBox(height: 8),
                // تنسيق حضرة السيد والعنوان
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(
                                text: 'حضرة السيد: ',
                                style: pw.TextStyle(font: font)),
                            pw.TextSpan(
                              text: _customerNameController.text.length > 17
                                  ? '${_customerNameController.text.substring(0, 17)}...'
                                  : _customerNameController.text,
                              style: pw.TextStyle(
                                  font: font, fontWeight: pw.FontWeight.bold),
                            ),
                            if (_customerAddressController.text.isNotEmpty)
                              pw.TextSpan(
                                  text: '  العنوان: ',
                                  style: pw.TextStyle(font: font)),
                            if (_customerAddressController.text.isNotEmpty)
                              pw.TextSpan(
                                text: _customerAddressController.text.length >
                                        12
                                    ? '${_customerAddressController.text.substring(0, 12)}...'
                                    : _customerAddressController.text,
                                style: pw.TextStyle(
                                    font: font, fontWeight: pw.FontWeight.bold),
                              ),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    // Keep the date here or remove if already above.
                    // Since it's already above, no need to duplicate.
                  ],
                ),
                pw.SizedBox(height: 12),
                // جدول الأصناف بشكل يدوي مطابق للصورة
                pw.Table(
                  border: pw.TableBorder.all(width: 1),
                  defaultVerticalAlignment:
                      pw.TableCellVerticalAlignment.middle,
                  columnWidths: <int, pw.TableColumnWidth>{
                    0: pw.FixedColumnWidth(20), // ت
                    1: pw.FlexColumnWidth(4), // التفاصيل
                    2: pw.FixedColumnWidth(40), // نوع البيع (تم تصغيره)
                    3: pw.FlexColumnWidth(1.5), // العدد
                    4: pw.FlexColumnWidth(2), // السعر
                    5: pw.FlexColumnWidth(2.5), // المبلغ
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(),
                      children: [
                        pw.Container(
                          alignment: pw.Alignment.center,
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('ت',
                              style: pw.TextStyle(
                                  font: font, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Container(
                          alignment: pw.Alignment.center,
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('التفاصيل',
                              style: pw.TextStyle(
                                  font: font, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Container(
                          alignment: pw.Alignment.center,
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('نوع البيع',
                              style: pw.TextStyle(
                                  font: font, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Container(
                          alignment: pw.Alignment.center,
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('العدد',
                              style: pw.TextStyle(
                                  font: font, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Container(
                          alignment: pw.Alignment.center,
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('السعر',
                              style: pw.TextStyle(
                                  font: font, fontWeight: pw.FontWeight.bold)),
                        ),
                        pw.Container(
                          alignment: pw.Alignment.center,
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text('المبلغ',
                              style: pw.TextStyle(
                                  font: font, fontWeight: pw.FontWeight.bold)),
                        ),
                      ],
                    ),
                    ...[
                      for (int i = 0; i < _invoiceItems.length; i++)
                        pw.TableRow(
                          children: [
                            pw.Container(
                              alignment: pw.Alignment.center,
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text((i + 1).toString(),
                                  style: pw.TextStyle(font: font)),
                            ),
                            pw.Container(
                              alignment: pw.Alignment.center,
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(_invoiceItems[i].productName,
                                  style: pw.TextStyle(font: font)),
                            ),
                            pw.Container(
                              alignment: pw.Alignment.center,
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(_invoiceItems[i].saleType ?? '',
                                  style: pw.TextStyle(font: font)),
                            ),
                            pw.Container(
                              alignment: pw.Alignment.center,
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(
                                  formatNumber(
                                      _invoiceItems[i].quantityIndividual ??
                                          _invoiceItems[i].quantityLargeUnit ??
                                          0),
                                  style: pw.TextStyle(font: font)),
                            ),
                            pw.Container(
                              alignment: pw.Alignment.center,
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(
                                  formatNumber(_invoiceItems[i].appliedPrice),
                                  style: pw.TextStyle(font: font)),
                            ),
                            pw.Container(
                              alignment: pw.Alignment.center,
                              padding: const pw.EdgeInsets.all(4),
                              child: pw.Text(
                                  formatNumber(_invoiceItems[i].itemTotal),
                                  style: pw.TextStyle(font: font)),
                            ),
                          ],
                        ),
                    ]
                  ],
                ),
                pw.SizedBox(height: 12),
                // صف الإجماليات والحسابات
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      flex: 3, // مساحة أكبر لقسم الإجماليات
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                              'الإجمالي قبل الخصم: ${formatNumber(currentTotalAmount)} دينار',
                              style: pw.TextStyle(
                                  font: font,
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11)),
                          pw.Text('الخصم: ${formatNumber(discount)} دينار',
                              style: pw.TextStyle(
                                  font: font,
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11)),
                          pw.Text(
                              'المبلغ المسدد: ${formatNumber(isCash ? afterDiscount : paid)} دينار',
                              style: pw.TextStyle(
                                  font: font,
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11)),
                          pw.Text(
                              'الإجمالي بعد الخصم: ${formatNumber(afterDiscount)} دينار',
                              style: pw.TextStyle(
                                  font: font,
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11)),
                          pw.Text(
                              'باقي الحساب: ${formatNumber(afterDiscount - (isCash ? afterDiscount : paid))} دينار',
                              style: pw.TextStyle(
                                  font: font,
                                  fontWeight: pw.FontWeight.bold,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                    pw.Expanded(
                      flex: 2, // مساحة أقل لقسم الحسابات
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                              'الحساب السابق: ${formatNumber(previousDebt)} دينار',
                              style: pw.TextStyle(font: font, fontSize: 14)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                              'الحساب الحالي: ${formatNumber(currentDebt)} دينار',
                              style: pw.TextStyle(font: font, fontSize: 14)),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.Text('التوقيع: _______________',
                    style: pw.TextStyle(font: font)),
              ],
            ),
          );
        },
      ),
    );
    return pdf;
  }

  Future<String> _saveInvoicePdf(
      pw.Document pdf, String customerName, DateTime invoiceDate) async {
    // تنظيف اسم العميل ليكون صالحًا كاسم ملف
    final safeCustomerName =
        customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
    final formattedDate = DateFormat('yyyy-MM-dd').format(invoiceDate);
    final fileName = '${safeCustomerName}_$formattedDate.pdf';
    final directory =
        Directory('${Platform.environment['USERPROFILE']}/Documents/invoices');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return filePath;
  }

  Future<void> _printInvoice() async {
    // إذا كانت الفاتورة جديدة ولم يتم حفظها بعد، قم بحفظها أولاً للحصول على رقم تسلسلي ومعرف
    if (widget.existingInvoice == null) {
      await _saveInvoice();
      // بعد الحفظ، _saveInvoice سيقوم بتحديث widget.existingInvoice و Navigator.pop(context).
      // يجب أن نتأكد أننا ما زلنا في نفس الشاشة لكي نتابع الطباعة.
      // للتبسيط في هذا السياق، سنفترض أن المستخدم سيعيد الضغط على زر الطباعة بعد الحفظ التلقائي.
      // أو يمكن إعادة بناء منطق _saveInvoice ليعيد المعرف ويتم استخدامه هنا مباشرة.
      // لكن الأفضل هو فصل عملية الحفظ عن الطباعة بشكل أوضح في تدفق المستخدم.
      // لذلك، سنتأكد أن الفاتورة الحالية موجودة ولها رقم تسلسلي قبل محاولة الطباعة
      if (widget.existingInvoice?.id == null ||
          widget.existingInvoice?.serialNumber == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'الرجاء حفظ الفاتورة أولاً للحصول على رقم تسلسلي قبل الطباعة.')),
        );
        return;
      }
    }

    final pdf = await _generateInvoicePdf();
    if (Platform.isWindows) {
      final filePath = await _saveInvoicePdf(
          pdf, _customerNameController.text, _selectedDate);
      await Process.start('cmd', ['/c', 'start', '/min', '', filePath, '/p']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم حفظ الفاتورة وإرسالها للطابعة مباشرة!')),
        );
      }
      return;
    }
    if (Platform.isAndroid) {
      if (_selectedPrinter == null) {
        List<PrinterDevice> printers = [];
        final bluetoothPrinters =
            await _printingService.findBluetoothPrinters();
        final systemPrinters = await _printingService.findSystemPrinters();
        printers = [...bluetoothPrinters, ...systemPrinters];
        if (printers.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('لا توجد طابعات متاحة.')),
            );
          }
          return;
        }
        final selected = await showDialog<PrinterDevice>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('اختر الطابعة'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: printers.length,
                  itemBuilder: (context, index) {
                    final printer = printers[index];
                    return ListTile(
                      title: Text(printer.name),
                      subtitle: Text(printer.connectionType.name),
                      onTap: () => Navigator.of(context).pop(printer),
                    );
                  },
                ),
              ),
            );
          },
        );
        if (selected == null) return;
        setState(() {
          _selectedPrinter = selected;
        });
      }
      if (_selectedPrinter != null) {
        try {
          await _printingService.printData(
            await pdf.save(),
            printerDevice: _selectedPrinter,
            escPosCommands: null,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      'تم إرسال الفاتورة إلى الطابعة: ${_selectedPrinter!.name}')),
            );
          }
        } catch (e) {
          print('Error during print: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('حدث خطأ أثناء الطباعة: ${e.toString()}')),
            );
          }
        }
      }
      return;
    }
    // ... منطق المنصات الأخرى (إن وجد) ...
  }

  @override
  Widget build(BuildContext context) {
    print(
        'CreateInvoiceScreen: Building with isViewOnly: ${widget.isViewOnly}');
    final currentTotalAmount =
        _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final isViewOnly = widget.isViewOnly;
    final relatedDebtTransaction = widget.relatedDebtTransaction;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingInvoice != null && !widget.isViewOnly
            ? 'تعديل فاتورة'
            : (widget.isViewOnly ? 'عرض فاتورة' : 'إنشاء فاتورة')),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'طباعة الفاتورة',
            onPressed: _invoiceItems.isEmpty ? null : _printInvoice,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              ListTile(
                title: const Text('تاريخ الفاتورة'),
                subtitle: Text(
                  '${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _selectDate(context),
              ),
              const SizedBox(height: 16.0),
              // Grouping customer and installer info in one row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _customerNameController,
                      decoration:
                          const InputDecoration(labelText: 'اسم العميل'),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'الرجاء إدخال اسم العميل';
                        }
                        return null;
                      },
                      enabled: !isViewOnly,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _customerPhoneController,
                      decoration: const InputDecoration(
                          labelText: 'رقم الجوال (اختياري)'),
                      keyboardType: TextInputType.phone,
                      enabled: !isViewOnly,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _customerAddressController,
                      decoration:
                          const InputDecoration(labelText: 'العنوان (اختياري)'),
                      enabled: !isViewOnly,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _installerNameController,
                      decoration: const InputDecoration(
                          labelText: 'اسم المؤسس/الفني (اختياري)'),
                      enabled: !isViewOnly,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24.0),

              if (!isViewOnly) ...[
                const Text(
                  'إضافة أصناف للفاتورة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8.0),
                TextFormField(
                  controller: _productSearchController,
                  decoration: InputDecoration(
                    labelText: 'البحث عن صنف',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: isViewOnly
                          ? null
                          : () {
                              _productSearchController.clear();
                              setState(() {
                                _searchResults = [];
                                _selectedProduct = null;
                                _quantityController.clear();
                                _selectedPriceLevel = null;
                                _useLargeUnit = false;
                              });
                            },
                    ),
                  ),
                  onChanged: isViewOnly ? null : _searchProducts,
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final product = _searchResults[index];
                        return ListTile(
                          title: Text(product.name),
                          onTap: isViewOnly
                              ? null
                              : () {
                                  setState(() {
                                    _selectedProduct = product;
                                    _productSearchController.text =
                                        product.name;
                                    _searchResults = [];
                                    _selectedPriceLevel =
                                        product.price1 ?? product.unitPrice;
                                  });
                                },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 16.0),
                if (_selectedProduct != null) ...[
                  Text('الصنف المحدد: ${_selectedProduct!.name}'),
                  const SizedBox(height: 8.0),
                  if (_selectedProduct!.unit == 'piece' &&
                          _selectedProduct!.piecesPerUnit != null ||
                      _selectedProduct!.unit == 'meter' &&
                          _selectedProduct!.lengthPerUnit != null)
                    SwitchListTile(
                      title: Text(
                        _selectedProduct!.unit == 'piece'
                            ? 'استخدام الكرتون/الباكيت'
                            : 'استخدام القطعة الكاملة',
                      ),
                      value: _useLargeUnit,
                      onChanged: isViewOnly
                          ? null
                          : (bool value) {
                              setState(() {
                                _useLargeUnit = value;
                                _quantityController.clear();
                              });
                            },
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _quantityController,
                          decoration: InputDecoration(
                            labelText: _useLargeUnit
                                ? (_selectedProduct!.unit == 'piece'
                                    ? 'عدد الكراتين/الباكيت'
                                    : 'عدد القطع الكاملة')
                                : 'الكمية (${_selectedProduct!.unit == 'piece' ? 'قطعة' : 'متر'})',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'الرجاء إدخال الكمية';
                            }
                            if (double.tryParse(value) == null ||
                                double.parse(value) <= 0) {
                              return 'الرجاء إدخال رقم موجب صحيح';
                            }
                            return null;
                          },
                          enabled: !isViewOnly,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<double?>(
                          decoration:
                              const InputDecoration(labelText: 'مستوى السعر'),
                          value: _selectedPriceLevel,
                          items: () {
                            // بناء قائمة أسعار فريدة
                            final Set<double> priceSet = {};
                            final List<double> uniquePrices = [];

                            // Add all potential prices to the set
                            if (_selectedProduct!.price1 != null)
                              priceSet.add(_selectedProduct!.price1);
                            if (_selectedProduct!.price2 != null)
                              priceSet.add(_selectedProduct!.price2!);
                            if (_selectedProduct!.price3 != null)
                              priceSet.add(_selectedProduct!.price3!);
                            if (_selectedProduct!.price4 != null)
                              priceSet.add(_selectedProduct!.price4!);
                            if (_selectedProduct!.price5 != null)
                              priceSet.add(_selectedProduct!.price5!);
                            if (_selectedProduct!.unitPrice != null)
                              priceSet.add(_selectedProduct!.unitPrice);

                            // Add unique prices from the set to the list
                            uniquePrices.addAll(priceSet);
                            uniquePrices.sort(); // Optional: sort prices

                            final List<DropdownMenuItem<double?>> priceItems =
                                [];

                            // Create DropdownMenuItems for unique prices
                            for (var price in uniquePrices) {
                              // Determine the text for the price based on which field it matches
                              String priceText = 'سعر غير معروف';
                              if (price == _selectedProduct!.price1)
                                priceText = 'سعر 1';
                              else if (price == _selectedProduct!.price2)
                                priceText = 'سعر 2';
                              else if (price == _selectedProduct!.price3)
                                priceText = 'سعر 3';
                              else if (price == _selectedProduct!.price4)
                                priceText = 'سعر 4';
                              else if (price == _selectedProduct!.price5)
                                priceText = 'سعر 5';
                              else if (price == _selectedProduct!.unitPrice)
                                priceText = 'سعر الوحدة الأصلي';

                              priceItems.add(DropdownMenuItem(
                                  value: price, child: Text(priceText)));
                            }

                            // إذا كان السعر المخصص غير null وغير موجود في القائمة، أضفه
                            // This case might occur if an existing invoice item has a custom price
                            if (_selectedPriceLevel != null &&
                                _selectedPriceLevel != -1 &&
                                !uniquePrices.contains(_selectedPriceLevel!)) {
                              priceItems.add(DropdownMenuItem(
                                  value: _selectedPriceLevel,
                                  child: const Text('سعر مخصص حالي')));
                            }

                            // أضف خيار سعر مخصص
                            priceItems.add(const DropdownMenuItem(
                                value: -1, child: Text('سعر مخصص')));
                            return priceItems;
                          }(),
                          onChanged: isViewOnly
                              ? null
                              : (value) async {
                                  if (value == -1) {
                                    // فتح Dialog لإدخال السعر المخصص مع فاليديشن قوي
                                    final customPrice =
                                        await showDialog<double>(
                                      context: context,
                                      builder: (context) {
                                        final controller =
                                            TextEditingController();
                                        String? errorText;
                                        return StatefulBuilder(
                                          builder: (context, setState) {
                                            return AlertDialog(
                                              title:
                                                  const Text('إدخال سعر مخصص'),
                                              content: TextField(
                                                controller: controller,
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                        decimal: true),
                                                decoration: InputDecoration(
                                                    hintText: 'أدخل السعر',
                                                    errorText: errorText),
                                                onChanged: (val) {
                                                  final v = double.tryParse(
                                                      val.trim());
                                                  setState(() {
                                                    if (v == null || v <= 0) {
                                                      errorText =
                                                          'أدخل رقمًا موجبًا';
                                                    } else {
                                                      errorText = null;
                                                    }
                                                  });
                                                },
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('إلغاء'),
                                                ),
                                                TextButton(
                                                  onPressed: () {
                                                    final val = double.tryParse(
                                                        controller.text.trim());
                                                    if (val != null &&
                                                        val > 0) {
                                                      Navigator.pop(
                                                          context, val);
                                                    } else {
                                                      setState(() {
                                                        errorText =
                                                            'أدخل رقمًا موجبًا';
                                                      });
                                                    }
                                                  },
                                                  child: const Text('موافق'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    );
                                    if (customPrice != null &&
                                        customPrice > 0) {
                                      setState(() {
                                        _selectedPriceLevel = customPrice;
                                      });
                                    }
                                  } else {
                                    setState(() {
                                      _selectedPriceLevel = value;
                                    });
                                  }
                                },
                          validator: (value) {
                            if (value == null) {
                              return 'الرجاء اختيار مستوى السعر';
                            }
                            return null;
                          },
                          isDense: isViewOnly,
                          menuMaxHeight: isViewOnly ? 0 : 200,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  ElevatedButton(
                    onPressed: isViewOnly ? null : _addInvoiceItem,
                    child: const Text('إضافة الصنف للفاتورة'),
                  ),
                ],
              ],

              const SizedBox(height: 24.0),

              const Text(
                'أصناف الفاتورة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8.0),
              if (_invoiceItems.isEmpty)
                const Text('لا يوجد أصناف مضافة حتى الآن')
              else
                // Table Headers
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 1,
                          child: Text('ت',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          flex: 2,
                          child: Text('المبلغ',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          flex: 4,
                          child: Text('التفاصيل',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          flex: 1,
                          child: Text('العدد',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          flex: 1,
                          child: Text('نوع البيع',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(
                          flex: 2,
                          child: Text('السعر',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold))),
                      if (!isViewOnly)
                        SizedBox(width: 40), // Space for delete icon
                    ],
                  ),
                ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _invoiceItems.length,
                itemBuilder: (context, index) {
                  final item = _invoiceItems[index];
                  // Determine the quantity and unit to display
                  // Display quantity is the actual quantity sold (either individual or large unit quantity)
                  final displayQuantity =
                      item.quantityIndividual ?? item.quantityLargeUnit ?? 0;
                  String displayUnit;
                  if (item.unit == 'piece') {
                    displayUnit = item.quantityIndividual != null ? 'ق' : 'ك';
                  } else if (item.unit == 'meter') {
                    displayUnit =
                        'م'; // Always 'م' when sold by meter, regardless of large or small unit representation
                  } else {
                    displayUnit = '';
                  }

                  // Display quantity as integer if it's a whole number, otherwise keep decimals
                  final quantityText =
                      displayQuantity == displayQuantity.toInt()
                          ? displayQuantity.toInt().toString()
                          : displayQuantity.toStringAsFixed(2);

                  // Item total is already calculated and stored correctly in item.itemTotal
                  final itemTotalAmount = item.itemTotal;

                  return Card(
                    margin: const EdgeInsets.symmetric(
                        vertical: 4.0, horizontal: 0.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 4.0),
                      child: Row(
                        children: [
                          Expanded(
                              flex: 1,
                              child: Text((index + 1).toString(),
                                  textAlign: TextAlign.center)),
                          Expanded(
                              flex: 2,
                              child: Text(formatNumber(itemTotalAmount),
                                  textAlign: TextAlign.center)),
                          Expanded(
                              flex: 4,
                              child: Text(item.productName,
                                  textAlign: TextAlign.center)),
                          Expanded(
                              flex: 1,
                              child: Text(quantityText,
                                  textAlign: TextAlign.center)),
                          Expanded(
                              flex: 1,
                              child: Text(item.saleType ?? '',
                                  textAlign: TextAlign.center)),
                          Expanded(
                              flex: 2,
                              child: Text(formatNumber(item.appliedPrice),
                                  textAlign: TextAlign.center)),
                          if (!isViewOnly)
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.red, size: 20),
                              onPressed: () => _removeInvoiceItem(index),
                              tooltip: 'حذف الصنف',
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24.0),
              // ويدجت عرض القيم الثلاثة (أو الأربعة الآن)
              // تم إزالة ValueListenableBuilder لضمان التفاعل مع تغيرات paymentType أيضاً
              // حيث أن تغيير paymentType يقوم باستدعاء setState ويعيد بناء الشاشة.
              Builder(
                builder: (context) {
                  final totalBeforeDiscount =
                      currentTotalAmount; // الإجمالي قبل الخصم
                  final total =
                      currentTotalAmount - _discount; // الإجمالي بعد الخصم
                  double enteredPaidAmount =
                      double.tryParse(_paidAmountController.text) ?? 0.0;
                  double displayedPaidAmount = enteredPaidAmount;
                  double displayedRemainingAmount = total - enteredPaidAmount;

                  if (_paymentType == 'نقد') {
                    displayedPaidAmount =
                        total; // إذا كانت الفاتورة نقد، المبلغ المسدد هو الإجمالي
                    displayedRemainingAmount = 0.0; // والمتبقي صفر
                  } else {
                    // إذا كانت دين
                    // القيم كما هي من المدخلات
                  }

                  return Card(
                    color: Colors.grey[100],
                    margin: const EdgeInsets.only(bottom: 16.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'المبلغ الإجمالي قبل الخصم:  ${formatNumber(totalBeforeDiscount)} دينار',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('المبلغ الإجمالي:  ${formatNumber(total)} دينار',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                              'المبلغ المسدد:    ${formatNumber(displayedPaidAmount)} دينار',
                              style: const TextStyle(color: Colors.green)),
                          const SizedBox(height: 4),
                          Text(
                              'المتبقي:         ${formatNumber(displayedRemainingAmount)} دينار',
                              style: const TextStyle(color: Colors.red)),
                          if (_paymentType == 'دين')
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                  'أصبح الدين: ${formatNumber(displayedRemainingAmount)} دينار',
                                  style:
                                      const TextStyle(color: Colors.black87)),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              if (isViewOnly)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'نوع الدفع: ${widget.existingInvoice?.paymentType ?? 'غير محدد'}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (widget.existingInvoice?.paymentType == 'دين' &&
                        relatedDebtTransaction != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'أصبح الدين: ${relatedDebtTransaction.amountChanged.abs().toStringAsFixed(2)} دينار',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                  ],
                )
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Radio<String>(
                      value: 'نقد',
                      groupValue: _paymentType,
                      onChanged: isViewOnly
                          ? null
                          : (value) {
                              setState(() {
                                _paymentType = value!;
                                // إذا كان نقداً، اجعل المبلغ المسدد هو إجمالي الفاتورة بعد الخصم
                                _paidAmountController.text = formatNumber(
                                    (currentTotalAmount - _discount)
                                        .clamp(0, double.infinity));
                              });
                            },
                    ),
                    const Text('نقد'),
                    const SizedBox(width: 24),
                    Radio<String>(
                      value: 'دين',
                      groupValue: _paymentType,
                      onChanged: isViewOnly
                          ? null
                          : (value) {
                              setState(() {
                                _paymentType = value!;
                                // إذا كان ديناً، لا تعدل المبلغ المسدد تلقائياً، دعه فارغاً أو ما أدخله المستخدم
                                // إذا لم يكن قد أدخل شيئاً، يمكن إعادته إلى '0' ليكون واضحاً
                                if (_paidAmountController.text.isEmpty) {
                                  _paidAmountController.text = '0';
                                }
                              });
                            },
                    ),
                    const Text('دين'),
                  ],
                ),
                if (_paymentType == 'دين') ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _paidAmountController,
                    decoration: const InputDecoration(
                        labelText: 'المبلغ المسدد (اختياري)'),
                    keyboardType: TextInputType.number,
                    enabled:
                        !isViewOnly && _paymentType == 'دين', // فقط إذا كان دين
                    onChanged: (value) {
                      setState(() {
                        // هذا الـ setState فارغ لكنه يجبر الواجهة على إعادة البناء وتحديث الحسابات
                      });
                    },
                  ),
                ],
              ],
              const SizedBox(height: 24.0),
              // حقل الخصم
              TextFormField(
                decoration:
                    const InputDecoration(labelText: 'الخصم (مبلغ وليس نسبة)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: isViewOnly
                    ? null
                    : (val) {
                        setState(() {
                          _discount = double.tryParse(val) ?? 0.0;
                        });
                      },
                initialValue: _discount > 0 ? _discount.toString() : '',
                enabled: !isViewOnly,
              ),
              const SizedBox(height: 24.0),
              if (!isViewOnly) // Only show action buttons if not in view-only mode
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _saveInvoice,
                      icon: const Icon(Icons.save),
                      label: const Text('حفظ الفاتورة'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _suspendInvoice,
                      icon: const Icon(Icons.pause),
                      label: const Text('تعليق الفاتورة'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
