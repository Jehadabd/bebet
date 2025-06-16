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
import 'dart:io';

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

  List<Product> _searchResults = [];
  Product? _selectedProduct;
  List<InvoiceItem> _invoiceItems = [];

  final DatabaseService _db = DatabaseService();
  PrinterDevice? _selectedPrinter;
  final PrintingService _printingService = PrintingService();

  @override
  void initState() {
    super.initState();
    if (widget.existingInvoice != null) {
      // Load existing invoice data
      _customerNameController.text = widget.existingInvoice!.customerName;
      _customerPhoneController.text = widget.existingInvoice!.customerPhone ?? '';
      _customerAddressController.text = widget.existingInvoice!.customerAddress ?? '';
      _installerNameController.text = widget.existingInvoice!.installerName ?? '';
      _selectedDate = widget.existingInvoice!.invoiceDate;
      _paymentType = widget.existingInvoice!.paymentType; // Load payment type
      _totalAmountController.text = widget.existingInvoice!.totalAmount.toString();
      _paidAmountController.text = widget.existingInvoice!.amountPaidOnInvoice.toString(); // Load amount paid
      _discount = widget.existingInvoice!.discount; // Load discount

      // Load invoice items
      _loadInvoiceItems();
    } else {
      // For new invoices, initialize total amount controller
      _totalAmountController.text = '0.00';
    }
  }

  Future<void> _loadInvoiceItems() async {
    if (widget.existingInvoice != null && widget.existingInvoice!.id != null) { // Ensure invoice and its ID are not null
      try {
        final items = await _db.getInvoiceItems(widget.existingInvoice!.id!);
        setState(() {
          _invoiceItems = items;
          // Update total amount based on loaded items (important for existing invoices)
          _totalAmountController.text = _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal).toStringAsFixed(2);
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
    if (_formKey.currentState!.validate() && _selectedProduct != null && _selectedPriceLevel != null) {
      final quantity = double.tryParse(_quantityController.text.trim()) ?? 0.0;
      if (quantity <= 0) return;

      // Calculate itemCostPrice based on total quantity in small units
      double itemCostPriceForInvoiceItem;
      // Calculate the applied price per unit sold (either small or large unit)
      double appliedPricePerUnitSold;
      double quantitySold;

      final unitsInLargeUnit = (_selectedProduct!.unit == 'piece' ? _selectedProduct!.piecesPerUnit : _selectedProduct!.lengthPerUnit) ?? 1.0;

      if (_useLargeUnit) {
         // Selling by large unit
         quantitySold = quantity; // quantity is in large units
         // Calculate the price per large unit based on the selected price per small unit
         appliedPricePerUnitSold = (_selectedPriceLevel ?? _selectedProduct!.unitPrice ?? 0.0) * unitsInLargeUnit;

         // Cost calculation based on total small units
         final totalSmallUnits = quantity * unitsInLargeUnit;
         itemCostPriceForInvoiceItem = (_selectedProduct!.costPrice ?? 0.0) * totalSmallUnits;

      } else {
        // Selling by small unit
        quantitySold = quantity; // quantity is in small units
        appliedPricePerUnitSold = _selectedPriceLevel ?? _selectedProduct!.unitPrice ?? 0.0; // Price is already per small unit

        // Cost calculation based on total small units (same as quantitySold in this case)
        itemCostPriceForInvoiceItem = (_selectedProduct!.costPrice ?? 0.0) * quantitySold;
      }

      final newItem = InvoiceItem(
        invoiceId: 0, // Will be updated when saving the invoice
        productName: _selectedProduct!.name,
        unit: _selectedProduct!.unit, // Store original unit
        unitPrice: _selectedProduct!.unitPrice, // Store original small unit price
        costPrice: itemCostPriceForInvoiceItem, // Store total cost for the quantity sold
        quantityIndividual: _useLargeUnit ? null : quantitySold, // Store quantity in small units if applicable
        quantityLargeUnit: _useLargeUnit ? quantitySold : null, // Store quantity in large units if applicable
        appliedPrice: appliedPricePerUnitSold, // Store the applied price PER UNIT SOLD (large or small)
        itemTotal: quantitySold * appliedPricePerUnitSold,
      );

      setState(() {
        _invoiceItems.add(newItem);
        // Clear fields for next item
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
        final customers = await _db.getAllCustomers(); // Consider optimizing this search
         try {
            customer = customers.firstWhere(
              (c) => c.name.trim() == _customerNameController.text.trim() &&
                  (c.phone == null || c.phone!.isEmpty || _customerPhoneController.text.trim().isEmpty || c.phone == _customerPhoneController.text.trim()), // Modified condition
            );
          } catch (e) {
            customer = null; // Customer not found
          }

        if (customer == null) {
          // Create a new customer if not found
          customer = Customer(
            id: null,
            name: _customerNameController.text.trim(),
            phone: _customerPhoneController.text.trim().isEmpty ? null : _customerPhoneController.text.trim(),
            address: _customerAddressController.text.trim(),
            createdAt: DateTime.now(),
            lastModifiedAt: DateTime.now(),
            currentTotalDebt: 0.0,
          );
          final insertedId = await _db.insertCustomer(customer);
          customer = customer.copyWith(id: insertedId);
        }
      }

      double currentTotalAmount = _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      double paid = double.tryParse(_paidAmountController.text) ?? 0.0;
      double debt = (currentTotalAmount - _discount) - paid;
      double totalAmount = currentTotalAmount - _discount;

      Invoice invoice = Invoice(
        id: widget.existingInvoice?.id,
        customerName: _customerNameController.text,
        customerPhone: _customerPhoneController.text,
        customerAddress: _customerAddressController.text,
        installerName: _installerNameController.text.isEmpty ? null : _installerNameController.text,
        invoiceDate: _selectedDate,
        paymentType: _paymentType,
        totalAmount: totalAmount,
        discount: _discount,
        amountPaidOnInvoice: paid,
        createdAt: widget.existingInvoice?.createdAt ?? DateTime.now(),
        lastModifiedAt: DateTime.now(),
        customerId: customer?.id, // Assign the found or created customer's ID
      );

      // Check if installer exists and add if not
      if (invoice.installerName != null && invoice.installerName!.isNotEmpty) {
        final existingInstaller = await _db.getInstallerByName(invoice.installerName!);
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
        await _db.updateInvoice(invoice); // customerId is now included in the invoice object
      } else {
        invoiceId = await _db.insertInvoice(invoice); // customerId is now included in the invoice object
        // Update the invoice object with the new ID for potential use later if needed
        if (invoice.id == null) {
          invoice = invoice.copyWith(id: invoiceId);
        }
      }

      // إذا كانت الفاتورة بالدين، أضف المبلغ فورًا إلى حساب العميل (جديد أو موجود)
      if (_paymentType == 'دين' && customer != null && debt > 0) {
        final updatedCustomer = customer.copyWith(
          currentTotalDebt: (customer.currentTotalDebt) + debt,
          lastModifiedAt: DateTime.now(),
        );
        await _db.updateCustomer(updatedCustomer);
      }

      // Save invoice items (ensure they are linked to the correct invoice ID)
       for (var item in _invoiceItems) {
         item.invoiceId = invoiceId; // Assign the correct invoice ID
         if (item.id == null) {
           await _db.insertInvoiceItem(item); // Assuming you have insertInvoiceItem method
         } else {
            await _db.updateInvoiceItem(item); // Assuming you have updateInvoiceItem method
         }
       }
       // رسالة توضيحية للعميل عن الدين
       String extraMsg = '';
       if (_paymentType == 'دين') {
         extraMsg = '\nتمت إضافة ${debt.toStringAsFixed(2)} دينار كدين للعميل لأن الفاتورة ${currentTotalAmount.toStringAsFixed(2)} - خصم ${_discount.toStringAsFixed(2)} - مسدد ${paid.toStringAsFixed(2)}';
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
      String errorMessage = 'حدث خطأ عند حفظ الفاتورة: ${e.toString()}'; // رسالة افتراضية
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
      // Find or create customer BEFORE creating the invoice object
      Customer? customer;
      int? customerId;
      if (_customerNameController.text.trim().isNotEmpty) {
        customer = await _db.searchCustomers(_customerNameController.text.trim()).then((list) => list.isNotEmpty ? list.first : null);
        if (customer == null) {
          customer = Customer(
            id: null,
            name: _customerNameController.text.trim(),
            phone: _customerPhoneController.text.trim(),
            address: _customerAddressController.text.trim(),
            createdAt: DateTime.now(),
            lastModifiedAt: DateTime.now(),
            currentTotalDebt: 0.0,
          );
          final insertedId = await _db.insertCustomer(customer);
          customer = customer.copyWith(id: insertedId);
        }
        customerId = customer.id;
      }
      double currentTotalAmount = _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      double totalAmount = currentTotalAmount - _discount;
      double paid = double.tryParse(_paidAmountController.text.trim()) ?? 0.0;
      double debt = (currentTotalAmount - _discount) - paid;
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
      for (final item in _invoiceItems) {
        await _db.insertInvoiceItem(item.copyWith(invoiceId: invoiceId));
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تعليق الفاتورة بنجاح ويمكن تعديلها لاحقاً من القوائم المعلقة.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      String errorMessage = 'حدث خطأ عند تعليق الفاتورة: \\${e.toString()}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  // دالة توليد ملف PDF للفاتورة
  Future<pw.Document> _generateInvoicePdf() async {
    final pdf = pw.Document();
    final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    final currentTotalAmount = _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final discount = _discount;
    final afterDiscount = (currentTotalAmount - discount).clamp(0, double.infinity);
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
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('النــاصر', style: pw.TextStyle(font: font, fontSize: 32, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                        pw.Text('تجارة المواد الكهربائية والكابلات', style: pw.TextStyle(font: font, fontSize: 18)),
                        pw.Text('الموصل - الجامعة، مقابل البرج', style: pw.TextStyle(font: font, fontSize: 14)),
                        pw.Text('0773 284 5260  |  0770 304 0821', style: pw.TextStyle(font: font, fontSize: 14, color: PdfColors.orange)),
                      ],
                    ),
                    // يمكنك إضافة صورة الشعار هنا إذا أردت
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('التاريخ: ${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}', style: pw.TextStyle(font: font)),
                    pw.Text('حضرة السيد: ${_customerNameController.text}', style: pw.TextStyle(font: font)),
                  ],
                ),
                if (_customerAddressController.text.isNotEmpty)
                  pw.Text('العنوان: ${_customerAddressController.text}', style: pw.TextStyle(font: font)),
                if (_customerPhoneController.text.isNotEmpty)
                  pw.Text('الموبايل: ${_customerPhoneController.text}', style: pw.TextStyle(font: font)),
                pw.SizedBox(height: 12),
                // جدول الأصناف
                pw.Table.fromTextArray(
                  headers: ['م', 'التفاصيل', 'العدد', 'السعر', 'المبلغ'],
                  data: [
                    for (int i = 0; i < _invoiceItems.length; i++)
                      [
                        (i + 1).toString(),
                        _invoiceItems[i].productName,
                        (_invoiceItems[i].quantityIndividual ?? _invoiceItems[i].quantityLargeUnit ?? 0).toStringAsFixed(2),
                        _invoiceItems[i].appliedPrice.toStringAsFixed(2),
                        _invoiceItems[i].itemTotal.toStringAsFixed(2),
                      ]
                  ],
                  headerStyle: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold),
                  cellStyle: pw.TextStyle(font: font),
                  cellAlignment: pw.Alignment.center,
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  border: pw.TableBorder.all(),
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text('الإجمالي قبل الخصم: ', style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                    pw.Text(currentTotalAmount.toStringAsFixed(2), style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text('الخصم: ', style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                    pw.Text(discount.toStringAsFixed(2), style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Text('الإجمالي بعد الخصم: ', style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 18)),
                    pw.Text(afterDiscount.toStringAsFixed(2), style: pw.TextStyle(font: font, fontWeight: pw.FontWeight.bold, fontSize: 18)),
                  ],
                ),
                pw.SizedBox(height: 24),
                pw.Text('التوقيع: _______________', style: pw.TextStyle(font: font)),
                pw.SizedBox(height: 12),
                pw.Text('ملاحظة: البضاعة لا ترد ولا تستبدل بعد اسبوعين من تاريخ البيع', style: pw.TextStyle(font: font, fontSize: 12)),
              ],
            ),
          );
        },
      ),
    );
    return pdf;
  }

  Future<String> _saveInvoicePdf(pw.Document pdf, String customerName, DateTime invoiceDate) async {
    // تنظيف اسم العميل ليكون صالحًا كاسم ملف
    final safeCustomerName = customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
    final formattedDate = DateFormat('yyyy-MM-dd').format(invoiceDate);
    final fileName = '${safeCustomerName}_$formattedDate.pdf';
    final directory = Directory('${Platform.environment['USERPROFILE']}/Documents/invoices');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return filePath;
  }

  Future<void> _printInvoice() async {
    final pdf = await _generateInvoicePdf();
    if (Platform.isWindows) {
      final filePath = await _saveInvoicePdf(pdf, _customerNameController.text, _selectedDate);
      await Process.start('cmd', ['/c', 'start', '/min', '', filePath, '/p']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ الفاتورة وإرسالها للطابعة مباشرة!')),
        );
      }
      return;
    }
    if (Platform.isAndroid) {
      if (_selectedPrinter == null) {
        List<PrinterDevice> printers = [];
        final bluetoothPrinters = await _printingService.findBluetoothPrinters();
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
              SnackBar(content: Text('تم إرسال الفاتورة إلى الطابعة: ${_selectedPrinter!.name}')),
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
    final currentTotalAmount = _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final isViewOnly = widget.isViewOnly;
    final relatedDebtTransaction = widget.relatedDebtTransaction;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingInvoice != null && !widget.isViewOnly ? 'تعديل فاتورة' : (widget.isViewOnly ? 'عرض فاتورة' : 'إنشاء فاتورة')),
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
                      decoration: const InputDecoration(labelText: 'اسم العميل'),
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
                      decoration: const InputDecoration(labelText: 'رقم الجوال (اختياري)'),
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
                       decoration: const InputDecoration(labelText: 'العنوان (اختياري)'),
                       enabled: !isViewOnly,
                     ),
                   ),
                   const SizedBox(width: 8.0),
                   Expanded(
                     flex: 2,
                     child: TextFormField(
                       controller: _installerNameController,
                       decoration: const InputDecoration(labelText: 'اسم المؤسس/الفني (اختياري)'),
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
                      onPressed: () {
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
                  onChanged: _searchProducts,
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
                          onTap: () {
                            setState(() {
                              _selectedProduct = product;
                              _productSearchController.text = product.name;
                              _searchResults = [];
                              _selectedPriceLevel = product.price1 ?? product.unitPrice;
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
                  if (_selectedProduct!.unit == 'piece' && _selectedProduct!.piecesPerUnit != null ||
                      _selectedProduct!.unit == 'meter' && _selectedProduct!.lengthPerUnit != null)
                    SwitchListTile(
                      title: Text(
                        _selectedProduct!.unit == 'piece'
                            ? 'استخدام الكرتون/الباكيت'
                            : 'استخدام القطعة الكاملة',
                      ),
                      value: _useLargeUnit,
                      onChanged: (bool value) {
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
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'الرجاء إدخال الكمية';
                            }
                            if (double.tryParse(value) == null || double.parse(value) <= 0) {
                              return 'الرجاء إدخال رقم موجب صحيح';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<double?>(
                          decoration: const InputDecoration(labelText: 'مستوى السعر'),
                          value: _selectedPriceLevel,
                          items: () {
                            // بناء قائمة أسعار فريدة
                            final Set<double> priceSet = {};
                            final List<double> uniquePrices = [];

                            // Add all potential prices to the set
                            if (_selectedProduct!.price1 != null) priceSet.add(_selectedProduct!.price1);
                            if (_selectedProduct!.price2 != null) priceSet.add(_selectedProduct!.price2!);
                            if (_selectedProduct!.price3 != null) priceSet.add(_selectedProduct!.price3!);
                            if (_selectedProduct!.price4 != null) priceSet.add(_selectedProduct!.price4!);
                            if (_selectedProduct!.price5 != null) priceSet.add(_selectedProduct!.price5!);
                            if (_selectedProduct!.unitPrice != null) priceSet.add(_selectedProduct!.unitPrice);

                            // Add unique prices from the set to the list
                            uniquePrices.addAll(priceSet);
                            uniquePrices.sort(); // Optional: sort prices

                            final List<DropdownMenuItem<double?>> priceItems = [];

                            // Create DropdownMenuItems for unique prices
                            for (var price in uniquePrices) {
                              // Determine the text for the price based on which field it matches
                              String priceText = 'سعر غير معروف';
                              if (price == _selectedProduct!.price1) priceText = 'سعر 1';
                              else if (price == _selectedProduct!.price2) priceText = 'سعر 2';
                              else if (price == _selectedProduct!.price3) priceText = 'سعر 3';
                              else if (price == _selectedProduct!.price4) priceText = 'سعر 4';
                              else if (price == _selectedProduct!.price5) priceText = 'سعر 5';
                              else if (price == _selectedProduct!.unitPrice) priceText = 'سعر الوحدة الأصلي';

                              priceItems.add(DropdownMenuItem(value: price, child: Text(priceText)));
                            }

                            // إذا كان السعر المخصص غير null وغير موجود في القائمة، أضفه
                            // This case might occur if an existing invoice item has a custom price
                            if (_selectedPriceLevel != null && _selectedPriceLevel != -1 && !uniquePrices.contains(_selectedPriceLevel!)) {
                               priceItems.add(DropdownMenuItem(value: _selectedPriceLevel, child: const Text('سعر مخصص حالي')));
                             }

                            // أضف خيار سعر مخصص
                            priceItems.add(const DropdownMenuItem(value: -1, child: Text('سعر مخصص')));
                            return priceItems;
                          }(),
                          onChanged: isViewOnly ? null : (value) async {
                            if (value == -1) {
                              // فتح Dialog لإدخال السعر المخصص مع فاليديشن قوي
                              final customPrice = await showDialog<double>(
                                context: context,
                                builder: (context) {
                                  final controller = TextEditingController();
                                  String? errorText;
                                  return StatefulBuilder(
                                    builder: (context, setState) {
                                      return AlertDialog(
                                        title: const Text('إدخال سعر مخصص'),
                                        content: TextField(
                                          controller: controller,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          decoration: InputDecoration(hintText: 'أدخل السعر', errorText: errorText),
                                          onChanged: (val) {
                                            final v = double.tryParse(val.trim());
                                            setState(() {
                                              if (v == null || v <= 0) {
                                                errorText = 'أدخل رقمًا موجبًا';
                                              } else {
                                                errorText = null;
                                              }
                                            });
                                          },
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('إلغاء'),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              final val = double.tryParse(controller.text.trim());
                                              if (val != null && val > 0) {
                                                Navigator.pop(context, val);
                                              } else {
                                                setState(() {
                                                  errorText = 'أدخل رقمًا موجبًا';
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
                              if (customPrice != null && customPrice > 0) {
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
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),
                  ElevatedButton(
                    onPressed: _addInvoiceItem,
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
                    children: const [
                      Expanded(flex: 1, child: Text('ت', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('المبلغ', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 4, child: Text('التفاصيل', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 1, child: Text('العدد', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 1, child: Text('نوع البيع', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('السعر', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
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
                  final displayQuantity = item.quantityIndividual ?? item.quantityLargeUnit ?? 0;
                  String displayUnit;
                  if (item.unit == 'piece') {
                     displayUnit = item.quantityIndividual != null ? 'ق' : 'ك';
                  } else if (item.unit == 'meter') {
                     displayUnit = 'م'; // Always 'م' when sold by meter, regardless of large or small unit representation
                  } else {
                     displayUnit = '';
                  }

                  // Display quantity as integer if it's a whole number, otherwise keep decimals
                  final quantityText = displayQuantity == displayQuantity.toInt() ? displayQuantity.toInt().toString() : displayQuantity.toStringAsFixed(2);

                  // Item total is already calculated and stored correctly in item.itemTotal
                  final itemTotalAmount = item.itemTotal;

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0.0),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                      child: Row(
                        children: [
                          Expanded(flex: 1, child: Text((index + 1).toString(), textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text(itemTotalAmount.toStringAsFixed(2), textAlign: TextAlign.center)),
                          Expanded(flex: 4, child: Text(item.productName, textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text(quantityText, textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text(displayUnit, textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text(item.appliedPrice.toStringAsFixed(2), textAlign: TextAlign.center)),
                          if (!isViewOnly)
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
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
              Text(
                'إجمالي الفاتورة بعد الخصم: ${(currentTotalAmount - _discount).clamp(0, double.infinity).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24.0),
              if (isViewOnly)
                Column(
                   crossAxisAlignment: CrossAxisAlignment.center,
                   children: [
                     Text(
                        'نوع الدفع: ${widget.existingInvoice?.paymentType ?? 'غير محدد'}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                     ),
                     if (widget.existingInvoice?.paymentType == 'دين' && relatedDebtTransaction != null)
                       Padding(
                         padding: const EdgeInsets.only(top: 8.0),
                         child: Text(
                           'أصبح الدين: ${relatedDebtTransaction.amountChanged.abs().toStringAsFixed(2)} دينار',
                           style: const TextStyle(fontSize: 16),
                         ),
                       ),
                   ],
                )
              else
                ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Radio<String>(
                        value: 'نقد',
                        groupValue: _paymentType,
                        onChanged: (value) {
                          setState(() {
                            _paymentType = value!;
                          });
                        },
                      ),
                      const Text('نقد'),
                      const SizedBox(width: 24),
                      Radio<String>(
                        value: 'دين',
                        groupValue: _paymentType,
                        onChanged: (value) {
                          setState(() {
                            _paymentType = value!;
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
                      decoration: const InputDecoration(labelText: 'المبلغ المسدد (اختياري)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ],
                ],
              const SizedBox(height: 24.0),
              // حقل الخصم
              TextFormField(
                decoration: const InputDecoration(labelText: 'الخصم (مبلغ وليس نسبة)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (val) {
                  setState(() {
                    _discount = double.tryParse(val) ?? 0.0;
                  });
                },
                initialValue: _discount > 0 ? _discount.toString() : '',
                enabled: !isViewOnly,
              ),
              if (!isViewOnly)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                  onPressed: _saveInvoice,
                  child: const Text('حفظ الفاتورة'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _suspendInvoice,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        child: const Text('تعليق الفاتورة'),
                      ),
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