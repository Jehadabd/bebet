// screens/create_invoice_screen.dart
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
import 'package:get_storage/get_storage.dart';

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
  int _unitSelection = 0; // 0 لـ "قطعة"، 1 لـ "كرتون/باكيت"

  String formatNumber(num value, {bool forceDecimal = false}) {
    if (forceDecimal) {
      return value % 1 == 0 ? value.toInt().toString() : value.toString();
    }
    return value.toInt().toString();
  }

  List<Product> _searchResults = [];
  Product? _selectedProduct;
  List<InvoiceItem> _invoiceItems = [];

  final DatabaseService _db = DatabaseService();
  PrinterDevice? _selectedPrinter;
  late final PrintingService _printingService;
  Invoice? _invoiceToManage;

  // إضافة متغيرات للحفظ التلقائي
  final _storage = GetStorage();
  bool _savedOrSuspended = false;
  Timer? _debounceTimer;

  // أضف متغير تحكم لحقل الراجع
  final TextEditingController _returnAmountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _printingService = getPlatformPrintingService();
    _invoiceToManage = widget.existingInvoice;

    // تحميل البيانات المؤقتة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAutoSavedData();
    });

    // إضافة استماع للتغيرات في الحقول
    _customerNameController.addListener(_onFieldChanged);
    _customerPhoneController.addListener(_onFieldChanged);
    _customerAddressController.addListener(_onFieldChanged);
    _installerNameController.addListener(_onFieldChanged);
    _paidAmountController.addListener(_onFieldChanged);
    _discountController.addListener(_onFieldChanged);

    if (_invoiceToManage != null) {
      print(
          'CreateInvoiceScreen: Init with existing invoice: ${_invoiceToManage!.id}');
      print('Invoice Status on Init: ${_invoiceToManage!.status}');
      print('Is View Only on Init: ${widget.isViewOnly}');
      _customerNameController.text = _invoiceToManage!.customerName;
      _customerPhoneController.text = _invoiceToManage!.customerPhone ?? '';
      _customerAddressController.text = _invoiceToManage!.customerAddress ?? '';
      _installerNameController.text = _invoiceToManage!.installerName ?? '';
      _selectedDate = _invoiceToManage!.invoiceDate;
      _paymentType = _invoiceToManage!.paymentType;
      _totalAmountController.text = _invoiceToManage!.totalAmount.toString();
      _paidAmountController.text =
          _invoiceToManage!.amountPaidOnInvoice.toString();
      _discount = _invoiceToManage!.discount;
      _discountController.text = _discount.toStringAsFixed(2);
      _returnAmountController.text = _invoiceToManage!.returnAmount.toString();

      _loadInvoiceItems();
    } else {
      print('CreateInvoiceScreen: Init with new invoice');
      _totalAmountController.text = '0';
    }
  }

  // تحميل البيانات المحفوظة تلقائياً
  void _loadAutoSavedData() {
    if (widget.isViewOnly || widget.existingInvoice != null) {
      return;
    }

    final data = _storage.read('temp_invoice_data');
    if (data == null) return;

    setState(() {
      _customerNameController.text = data['customerName'] ?? '';
      _customerPhoneController.text = data['customerPhone'] ?? '';
      _customerAddressController.text = data['customerAddress'] ?? '';
      _installerNameController.text = data['installerName'] ?? '';

      if (data['selectedDate'] != null) {
        _selectedDate = DateTime.parse(data['selectedDate']);
      }

      _paymentType = data['paymentType'] ?? 'نقد';
      _discount = data['discount'] ?? 0;
      _discountController.text = _discount.toStringAsFixed(2);
      _paidAmountController.text = data['paidAmount'] ?? '';

      _invoiceItems = (data['invoiceItems'] as List<dynamic>).map((item) {
        return InvoiceItem(
          invoiceId: 0,
          productName: item['productName'],
          unit: item['unit'],
          unitPrice: item['unitPrice'],
          costPrice: item['costPrice'] ?? 0,
          quantityIndividual: item['quantityIndividual'],
          quantityLargeUnit: item['quantityLargeUnit'],
          appliedPrice: item['appliedPrice'],
          itemTotal: item['itemTotal'],
          saleType: item['saleType'],
        );
      }).toList();

      _totalAmountController.text = _invoiceItems
          .fold(0.0, (sum, item) => sum + item.itemTotal)
          .toStringAsFixed(2);
    });
  }

  // حفظ البيانات تلقائياً
  void _autoSave() {
    if (_savedOrSuspended ||
        widget.isViewOnly ||
        widget.existingInvoice != null) {
      return;
    }

    final data = {
      'customerName': _customerNameController.text,
      'customerPhone': _customerPhoneController.text,
      'customerAddress': _customerAddressController.text,
      'installerName': _installerNameController.text,
      'selectedDate': _selectedDate.toIso8601String(),
      'paymentType': _paymentType,
      'discount': _discount,
      'paidAmount': _paidAmountController.text,
      'invoiceItems': _invoiceItems
          .map((item) => {
                'productName': item.productName,
                'unit': item.unit,
                'unitPrice': item.unitPrice,
                'costPrice': item.costPrice,
                'quantityIndividual': item.quantityIndividual,
                'quantityLargeUnit': item.quantityLargeUnit,
                'appliedPrice': item.appliedPrice,
                'itemTotal': item.itemTotal,
                'saleType': item.saleType,
              })
          .toList(),
    };

    _storage.write('temp_invoice_data', data);
  }

  // معالج تغيير الحقول مع تأخير
  void _onFieldChanged() {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
    }

    _debounceTimer = Timer(const Duration(seconds: 1), _autoSave);
  }

  Future<void> _loadInvoiceItems() async {
    if (_invoiceToManage != null && _invoiceToManage!.id != null) {
      try {
        final items = await _db.getInvoiceItems(_invoiceToManage!.id!);
        setState(() {
          _invoiceItems = items;
          _totalAmountController.text = _invoiceItems
              .fold(0.0, (sum, item) => sum + item.itemTotal)
              .toStringAsFixed(2);
        });
      } catch (e) {
        print('Error loading invoice items: $e');
      }
    }
  }

  @override
  void dispose() {
    // إزالة المستمعين
    _customerNameController.removeListener(_onFieldChanged);
    _customerPhoneController.removeListener(_onFieldChanged);
    _customerAddressController.removeListener(_onFieldChanged);
    _installerNameController.removeListener(_onFieldChanged);
    _paidAmountController.removeListener(_onFieldChanged);
    _discountController.removeListener(_onFieldChanged);

    // إلغاء المؤقت
    _debounceTimer?.cancel();

    // الحفظ النهائي عند إغلاق الشاشة
    if (!_savedOrSuspended &&
        widget.existingInvoice == null &&
        !widget.isViewOnly) {
      _autoSave();
    }

    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerAddressController.dispose();
    _installerNameController.dispose();
    _productSearchController.dispose();
    _quantityController.dispose();
    _paidAmountController.dispose();
    _discountController.dispose();
    _returnAmountController.dispose();
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
        _autoSave(); // حفظ تلقائي عند تغيير التاريخ
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

  // دالة لتحديث المبلغ المسدد تلقائيًا إذا كان الدفع نقد
  void _updatePaidAmountIfCash() {
    if (_paymentType == 'نقد') {
      _guardDiscount();
      final currentTotalAmount =
          _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final total = currentTotalAmount - _discount;
      _paidAmountController.text =
          total.clamp(0, double.infinity).toStringAsFixed(2);
    }
  }

  // دالة مركزية لحماية الخصم
  void _guardDiscount() {
    final currentTotalAmount =
        _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    if (_discount >= currentTotalAmount) {
      _discount = 0.0;
      _discountController.text = '0';
    }
  }

  void _addInvoiceItem() {
    if (_formKey.currentState!.validate() &&
        _selectedProduct != null &&
        _selectedPriceLevel != null) {
      final quantity = double.tryParse(_quantityController.text.trim()) ?? 0.0;
      if (quantity <= 0) return;
      double itemCostPriceForInvoiceItem;
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
      double appliedPricePerUnitSold;
      if (_useLargeUnit) {
        quantitySold = quantity;
        appliedPricePerUnitSold =
            (_selectedPriceLevel ?? _selectedProduct!.unitPrice ?? 0) *
                unitsInLargeUnit;
        final totalSmallUnits = quantity * unitsInLargeUnit;
        itemCostPriceForInvoiceItem =
            (_selectedProduct!.costPrice ?? 0) * totalSmallUnits;
      } else {
        quantitySold = quantity;
        appliedPricePerUnitSold =
            _selectedPriceLevel ?? _selectedProduct!.unitPrice ?? 0;
        itemCostPriceForInvoiceItem =
            (_selectedProduct!.costPrice ?? 0) * quantitySold;
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
        // البحث عن صنف مطابق (نفس الاسم، نفس نوع البيع، نفس الوحدة)
        final existingIndex = _invoiceItems.indexWhere((item) =>
            item.productName == newItem.productName &&
            item.saleType == newItem.saleType &&
            item.unit == newItem.unit);
        if (existingIndex != -1) {
          final existingItem = _invoiceItems[existingIndex];
          _invoiceItems[existingIndex] = existingItem.copyWith(
            quantityIndividual: (existingItem.quantityIndividual ?? 0) +
                (newItem.quantityIndividual ?? 0),
            quantityLargeUnit: (existingItem.quantityLargeUnit ?? 0) +
                (newItem.quantityLargeUnit ?? 0),
            itemTotal: (existingItem.itemTotal) + (newItem.itemTotal),
            costPrice: (existingItem.costPrice ?? 0) + (newItem.costPrice ?? 0),
          );
        } else {
          _invoiceItems.add(newItem);
        }
        _productSearchController.clear();
        _quantityController.clear();
        _selectedProduct = null;
        _selectedPriceLevel = null;
        _useLargeUnit = false;
        _searchResults = [];
        _guardDiscount();
        _updatePaidAmountIfCash();
        _autoSave();
      });
    }
  }

  void _removeInvoiceItem(int index) {
    setState(() {
      _invoiceItems.removeAt(index);
      _guardDiscount();
      _updatePaidAmountIfCash();
      _autoSave();
    });
  }

  Future<Invoice?> _saveInvoice({bool printAfterSave = false}) async {
    if (!_formKey.currentState!.validate()) return null;

    try {
      Customer? customer;
      if (_customerNameController.text.trim().isNotEmpty) {
        final customers = await _db.getAllCustomers();
        try {
          customer = customers.firstWhere(
            (c) =>
                c.name.trim() == _customerNameController.text.trim() &&
                (c.phone == null ||
                    c.phone!.isEmpty ||
                    _customerPhoneController.text.trim().isEmpty ||
                    c.phone == _customerPhoneController.text.trim()),
          );
        } catch (e) {
          customer = null;
        }

        if (customer == null) {
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

      // تحقق من نسبة الخصم
      if (_discount >= currentTotalAmount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('نسبة الخصم خاطئة!')),
          );
        }
        return null;
      }

      // تحقق من المبلغ المسدد في حالة الدين
      if (_paymentType == 'دين' && paid >= totalAmount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'لا يمكن أن يكون المبلغ المسدد مساوياً أو أكبر من إجمالي الفاتورة في حالة الدين!')),
          );
        }
        return null;
      }

      // حماية: إذا كان نوع الدفع دين والمبلغ المسدد أكبر من الإجمالي، صفّره
      if (_paymentType == 'دين' && paid > totalAmount) {
        paid = 0.0;
        _paidAmountController.text = '';
      }

      print('DEBUG: currentTotalAmount: $currentTotalAmount');
      print('DEBUG: _discount: $_discount');
      print('DEBUG: paid: $paid');
      print('DEBUG: calculated debt: $debt');

      Invoice invoice = Invoice(
        id: _invoiceToManage?.id,
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
        createdAt: _invoiceToManage?.createdAt ?? DateTime.now(),
        lastModifiedAt: DateTime.now(),
        customerId: customer?.id,
        status: 'محفوظة',
        returnAmount: _returnAmountController.text.isNotEmpty
            ? double.parse(_returnAmountController.text)
            : 0.0,
        isLocked: false,
      );

      if (invoice.installerName != null && invoice.installerName!.isNotEmpty) {
        final existingInstaller =
            await _db.getInstallerByName(invoice.installerName!);
        if (existingInstaller == null) {
          final newInstaller = Installer(
            id: null,
            name: invoice.installerName!,
            totalBilledAmount: 0.0,
          );
          await _db.insertInstaller(newInstaller);
        }
      }

      int invoiceId;
      if (_invoiceToManage != null) {
        invoiceId = _invoiceToManage!.id!;
        await context.read<AppProvider>().updateInvoice(invoice);
        print(
            'Updated existing invoice via AppProvider. Invoice ID: $invoiceId, New Status: ${invoice.status}');
      } else {
        invoiceId = await _db.insertInvoice(invoice);
        final savedInvoice = await _db.getInvoiceById(invoiceId);
        if (savedInvoice != null) {
          setState(() {
            _invoiceToManage = savedInvoice;
          });
          invoice = savedInvoice;
        }
        print(
            'Inserted new invoice. Invoice ID: $invoiceId, Status: ${invoice.status}');
      }

      if (_paymentType == 'دين' && customer != null && debt > 0) {
        final updatedCustomer = customer.copyWith(
          currentTotalDebt: (customer.currentTotalDebt) + debt,
          lastModifiedAt: DateTime.now(),
        );
        await _db.updateCustomer(updatedCustomer);

        final debtTransaction = DebtTransaction(
          id: null,
          customerId: customer.id!,
          amountChanged: debt,
          transactionType: 'invoice_debt',
          description: 'دين فاتورة رقم ${invoiceId ?? _invoiceToManage?.id}',
          newBalanceAfterTransaction: updatedCustomer.currentTotalDebt,
          invoiceId: invoiceId,
        );
        await _db.insertDebtTransaction(debtTransaction);
      }

      for (var item in _invoiceItems) {
        item.invoiceId = invoiceId;
        if (item.id == null) {
          await _db.insertInvoiceItem(item);
        } else {
          await _db.updateInvoiceItem(item);
        }
      }
      String extraMsg = '';
      if (_paymentType == 'دين') {
        extraMsg =
            '\nتمت إضافة ${debt.toStringAsFixed(2)} دينار كدين للعميل لأن الفاتورة ${currentTotalAmount.toStringAsFixed(2)} - خصم ${_discount.toStringAsFixed(2)} - مسدد ${paid.toStringAsFixed(2)}';
      }

      // حذف البيانات المؤقتة بعد الحفظ الناجح
      _storage.remove('temp_invoice_data');
      _savedOrSuspended = true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الفاتورة بنجاح$extraMsg'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
      return invoice;
    } catch (e) {
      String errorMessage = 'حدث خطأ عند حفظ الفاتورة: ${e.toString()}';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _suspendInvoice() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      Customer? customer;
      int? customerId;
      if (_customerNameController.text.trim().isNotEmpty) {
        final customers =
            await _db.searchCustomers(_customerNameController.text.trim());
        customer = customers.isNotEmpty ? customers.first : null;
        customerId = customer?.id;
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

      // حذف البيانات المؤقتة بعد التعليق الناجح
      _storage.remove('temp_invoice_data');
      _savedOrSuspended = true;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'تم تعليق الفاتورة بنجاح ويمكن تعديلها لاحقاً من القوائم المعلقة.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      String errorMessage = 'حدث خطأ عند تعليق الفاتورة: \${e.toString()}';
      print('Error suspending invoice: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  Future<pw.Document> _generateInvoicePdf() async {
    final pdf = pw.Document();
    final font =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));

    final currentTotalAmount =
        _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final discount = _discount;
    final afterDiscount =
        (currentTotalAmount - discount).clamp(0, double.infinity);

    // حساب الديون
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
    final paid = double.tryParse(_paidAmountController.text) ?? 0.0;
    final isCash = _paymentType == 'نقد';
    final remaining = isCash ? 0 : (afterDiscount - paid);
    if (isCash) {
      currentDebt = previousDebt;
    } else {
      currentDebt = previousDebt + remaining;
    }

    // --- منطق رقم الفاتورة ---
    int invoiceId;
    if (_invoiceToManage != null && _invoiceToManage!.id != null) {
      invoiceId = _invoiceToManage!.id!;
    } else {
      invoiceId = (await _db.getLastInvoiceId()) + 1;
    }

    // تقسيم العناصر إلى صفحات
    // const itemsPerPage = 33; // القيمة القديمة
    const itemsPerPage =
        22; //  <<<<----- تغيير هنا: القيمة الجديدة (جرب 25 أو 28)
    final totalPages = (_invoiceItems.length / itemsPerPage).ceil();

    for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final start = pageIndex * itemsPerPage;
      final end = (start + itemsPerPage) > _invoiceItems.length
          ? _invoiceItems.length
          : start + itemsPerPage;
      final pageItems = _invoiceItems.sublist(start, end);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.only(top: 10, bottom: 10, left: 10, right: 10),
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // --- الرأس الجديد مع معلومات المتجر ---
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      children: [
                        // اسم المتجر
                        pw.Center(
                          child: pw.Text('الــــــنــــــاصــــــر',
                              style: pw.TextStyle(
                                  font: font,
                                  fontSize: 28, //  <<<<----- تغيير هنا
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black)),
                        ),

                        // نوع النشاط
                        pw.Center(
                          child: pw.Text(
                              'لتجارة المواد الصحية والعدد اليدوية والانشائية',
                              // style: pw.TextStyle(font: font, fontSize: 16)), // قديم
                              style: pw.TextStyle(
                                  font: font,
                                  fontSize: 17)), //  <<<<----- تغيير هنا
                        ),

                        // العنوان مع رقم الفاتورة
                        pw.Center(
                          child: pw.Text(
                            'الموصل - الجدعة - مقابل البرج',
                            // style: pw.TextStyle(font: font, fontSize: 12), // قديم
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 13), //  <<<<----- تغيير هنا
                          ),
                        ),

                        // أرقام الهواتف
                        pw.Center(
                          child: pw.Text('0771 406 3064  |  0770 305 1353',
                              style: pw.TextStyle(
                                  font: font,
                                  // fontSize: 12, // قديم
                                  fontSize: 13, //  <<<<----- تغيير هنا
                                  color: PdfColors.black)),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 8),

                  // --- معلومات العميل والتاريخ ---
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('العميل: ${_customerNameController.text}',
                          // style: pw.TextStyle(font: font, fontSize: 9)), // قديم
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 12)), //  <<<<----- تغيير هنا
                      pw.Text(
                          'العنوان: ${_customerAddressController.text.isNotEmpty ? _customerAddressController.text : ' ______'}',
                          // style: pw.TextStyle(font: font, fontSize: 8)), // قديم
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 11)), //  <<<<----- تغيير هنا
                      pw.Text('رقم الفاتورة: ${invoiceId}',
                          // style: pw.TextStyle(font: font, fontSize: 9)), // قديم
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 10)), //  <<<<----- تغيير هنا
                      pw.Text(
                          'الوقت: ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                          // style: pw.TextStyle(font: font, fontSize: 8)), // قديم
                          style: pw.TextStyle(
                              font: font,
                              fontSize: 11)), //  <<<<----- تغيير هنا
                      pw.Text(
                        'التاريخ: ${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}',
                        // style: pw.TextStyle(font: font, fontSize: 9), // قديم
                        style: pw.TextStyle(
                            font: font, fontSize: 11), //  <<<<----- تغيير هنا
                      ),
                    ],
                  ),
                  pw.Divider(height: 6, thickness: 0.5),

                  // --- جدول العناصر ---
                  // ! ملاحظة هامة: يجب تعديل حجم الخط داخل دوال _headerCell و _dataCell أيضاً
                  // بما أن تعريف هذه الدوال غير موجود هنا، افترض أنك ستعدل حجم الخط فيها
                  // مثلاً، إذا كان _headerCell يستخدم fontSize: 8، غيره إلى fontSize: 9 أو 10
                  // وكذلك بالنسبة لـ _dataCell
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.5),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(90), // المبلغ
                      1: const pw.FixedColumnWidth(50), // العدد
                      2: const pw.FixedColumnWidth(65), // السعر
                      3: const pw.FlexColumnWidth(1.4), // اسم المنتج
                      4: const pw.FixedColumnWidth(20), // ت (التسلسل)
                    },
                    defaultVerticalAlignment:
                        pw.TableCellVerticalAlignment.middle,
                    children: [
                      // رأس الجدول
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(),
                        children: [
                          _headerCell(
                              'المبلغ', font), // عدّل fontSize داخل هذه الدالة
                          _headerCell(
                              'العدد', font), // عدّل fontSize داخل هذه الدالة
                          _headerCell(
                              'السعر', font), // عدّل fontSize داخل هذه الدالة
                          _headerCell('اسم المنتج',
                              font), // عدّل fontSize داخل هذه الدالة
                          _headerCell(
                              'ت', font), // عدّل fontSize داخل هذه الدالة
                        ],
                      ),

                      // عناصر الجدول للصفحة الحالية
                      ...pageItems.asMap().entries.map((entry) {
                        final index = entry.key + (pageIndex * itemsPerPage);
                        final item = entry.value;
                        final quantity = (item.quantityIndividual ??
                            item.quantityLargeUnit ??
                            0.0);

                        return pw.TableRow(
                          children: [
                            _dataCell(
                                // عدّل fontSize داخل هذه الدالة
                                formatNumber(item.itemTotal,
                                    forceDecimal: true),
                                font),
                            _dataCell(
                                // عدّل fontSize داخل هذه الدالة
                                '${formatNumber(quantity, forceDecimal: true)} ${item.saleType ?? ''}',
                                font),
                            _dataCell(
                                // عدّل fontSize داخل هذه الدالة
                                formatNumber(item.appliedPrice,
                                    forceDecimal: true),
                                font),
                            _dataCell(item.productName,
                                font, // عدّل fontSize داخل هذه الدالة
                                align: pw.TextAlign.right),
                            _dataCell('${index + 1}',
                                font), // عدّل fontSize داخل هذه الدالة
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                  pw.Divider(height: 6, thickness: 0.5),

                  // --- المجاميع في الصفحة الأخيرة فقط ---
                  if (pageIndex == totalPages - 1) ...[
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        // الصف العلوي
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            // ! ملاحظة: يجب تعديل حجم الخط داخل دالة _summaryRow أيضاً
                            _summaryRow(
                                'الاجمالي قبل الخصم:', // عدّل fontSize داخل هذه الدالة
                                currentTotalAmount,
                                font),
                            pw.SizedBox(width: 10),
                            _summaryRow('الخصم:', discount,
                                font), // عدّل fontSize داخل هذه الدالة
                            pw.SizedBox(width: 10),
                            _summaryRow(
                                // عدّل fontSize داخل هذه الدالة
                                'الاجمالي بعد الخصم:',
                                afterDiscount,
                                font),
                            pw.SizedBox(width: 10),
                            _summaryRow('المبلغ المدفوع:', paid,
                                font), // عدّل fontSize داخل هذه الدالة
                          ],
                        ),
                        pw.SizedBox(height: 6),

                        // الصف السفلي
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            _summaryRow('المبلغ المتبقي:', remaining,
                                font), // عدّل fontSize داخل هذه الدالة
                            pw.SizedBox(width: 10),
                            _summaryRow('الدين السابق:', previousDebt,
                                font), // عدّل fontSize داخل هذه الدالة
                            pw.SizedBox(width: 10),
                            _summaryRow('الدين الحالي:', currentDebt,
                                font), // عدّل fontSize داخل هذه الدالة
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 6),

                    // --- التذييل ---
                    pw.Center(
                        child: pw.Text('شكراً لتعاملكم معنا',
                            // style: pw.TextStyle(font: font, fontSize: 9))), // قديم
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 11))), //  <<<<----- تغيير هنا
                  ],

                  // --- ترقيم الصفحات ---
                  pw.Align(
                    // استخدم Align لتوسيط أفضل إذا كان هناك عناصر أخرى في نفس المستوى
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      'صفحة ${pageIndex + 1} من $totalPages',
                      // style: pw.TextStyle(font: font, fontSize: 8), // قديم
                      style: pw.TextStyle(
                          font: font, fontSize: 11), //  <<<<----- تغيير هنا
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
    return pdf;
  }

// دالة لخلايا الرأس
  pw.Widget _headerCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center),
    );
  }

// دالة لخلايا البيانات
  pw.Widget _dataCell(String text, pw.Font font,
      {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(font: font, fontSize: 13), textAlign: align),
    );
  }

// دالة لصفوف المجاميع
  pw.Widget _summaryRow(String label, num value, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 11)),
          pw.SizedBox(width: 5),
          pw.Text(formatNumber(value, forceDecimal: true),
              style: pw.TextStyle(
                  font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  Future<String> _saveInvoicePdf(
      pw.Document pdf, String customerName, DateTime invoiceDate) async {
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
    final pdf = await _generateInvoicePdf();
    if (Platform.isWindows) {
      final filePath = await _saveInvoicePdf(
          pdf, _customerNameController.text, _selectedDate);
      await Process.start('cmd', ['/c', 'start', '/min', '', filePath, '/p']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الفاتورة للطابعة مباشرة!')),
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
  }

  void _resetInvoice() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فاتورة جديدة'),
        content: const Text(
            'هل تريد بدء فاتورة جديدة؟ سيتم مسح جميع البيانات الحالية.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performReset();
            },
            child: const Text('نعم'),
          ),
        ],
      ),
    );
  }

  void _performReset() {
    setState(() {
      _customerNameController.clear();
      _customerPhoneController.clear();
      _customerAddressController.clear();
      _installerNameController.clear();
      _productSearchController.clear();
      _quantityController.clear();
      _paidAmountController.clear();
      _discountController.clear();
      _discount = 0.0;
      _selectedPriceLevel = null;
      _selectedProduct = null;
      _useLargeUnit = false;
      _paymentType = 'نقد';
      _selectedDate = DateTime.now();
      _invoiceItems.clear();
      _searchResults.clear();
      _totalAmountController.text = '0';
      _savedOrSuspended = false;
      // حذف البيانات المؤقتة
      _storage.remove('temp_invoice_data');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم بدء فاتورة جديدة')),
    );
  }

  Future<void> _saveReturnAmount(double value) async {
    if (_invoiceToManage == null || _invoiceToManage!.isLocked) return;
    // تحديث الفاتورة في قاعدة البيانات
    final updatedInvoice =
        _invoiceToManage!.copyWith(returnAmount: value, isLocked: true);
    await _db.updateInvoice(updatedInvoice);
    // إذا كان هناك مؤسس، اطرح الراجع من رصيده
    if (updatedInvoice.installerName != null &&
        updatedInvoice.installerName!.isNotEmpty) {
      final installer =
          await _db.getInstallerByName(updatedInvoice.installerName!);
      if (installer != null) {
        final newTotal = (installer.totalBilledAmount - value.toDouble())
            .clamp(0.0, double.infinity);
        final updatedInstaller =
            installer.copyWith(totalBilledAmount: newTotal as double?);
        await _db.updateInstaller(updatedInstaller);
      }
    }
    setState(() {
      _invoiceToManage = updatedInvoice;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حفظ الراجع وقفل الفاتورة!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    print(
        'CreateInvoiceScreen: Building with isViewOnly: ${widget.isViewOnly}');
    final currentTotalAmount =
        _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final isViewOnly = widget.isViewOnly;
    final relatedDebtTransaction = widget.relatedDebtTransaction;

    return WillPopScope(
      onWillPop: () async {
        _autoSave();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_invoiceToManage != null && !widget.isViewOnly
              ? 'تعديل فاتورة'
              : (widget.isViewOnly ? 'عرض فاتورة' : 'إنشاء فاتورة')),
          centerTitle: true,
          actions: [
            // زر جديد لإعادة التعيين
            IconButton(
              icon: const Icon(Icons.receipt),
              tooltip: 'فاتورة جديدة',
              onPressed: _invoiceItems.isNotEmpty ||
                      _customerNameController.text.isNotEmpty
                  ? _resetInvoice
                  : null,
            ),
            // زر الطباعة الموجود
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: widget.isViewOnly
                          ? TextFormField(
                              controller: _customerNameController,
                              decoration: const InputDecoration(
                                  labelText: 'اسم العميل'),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'الرجاء إدخال اسم العميل';
                                }
                                return null;
                              },
                              enabled: false,
                            )
                          : Autocomplete<String>(
                              optionsBuilder:
                                  (TextEditingValue textEditingValue) async {
                                if (textEditingValue.text == '') {
                                  return const Iterable<String>.empty();
                                }
                                final customers = await _db
                                    .searchCustomers(textEditingValue.text);
                                return customers.map((c) => c.name).toSet();
                              },
                              fieldViewBuilder: (context, controller, focusNode,
                                  onFieldSubmitted) {
                                controller.text = _customerNameController.text;
                                controller.selection =
                                    TextSelection.fromPosition(TextPosition(
                                        offset: controller.text.length));
                                return TextFormField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  decoration: const InputDecoration(
                                      labelText: 'اسم العميل'),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'الرجاء إدخال اسم العميل';
                                    }
                                    return null;
                                  },
                                  onChanged: (val) {
                                    _customerNameController.text = val;
                                    _onFieldChanged();
                                  },
                                );
                              },
                              onSelected: (String selection) {
                                _customerNameController.text = selection;
                                _onFieldChanged();
                              },
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
                        decoration: const InputDecoration(
                            labelText: 'العنوان (اختياري)'),
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
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('نوع الوحدة:',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ChoiceChip(
                                      label: Text(
                                        _selectedProduct!.unit == 'piece'
                                            ? 'قطعة'
                                            : 'متر',
                                        style: TextStyle(
                                          color: _unitSelection == 0
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                      selected: _unitSelection == 0,
                                      onSelected: (selected) {
                                        setState(() {
                                          _unitSelection = 0;
                                          _useLargeUnit = false;
                                          _quantityController.clear();
                                        });
                                      },
                                      selectedColor:
                                          Theme.of(context).primaryColor,
                                      backgroundColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                  Expanded(
                                    child: ChoiceChip(
                                      label: Text(
                                        _selectedProduct!.unit == 'piece'
                                            ? 'كرتون/باكيت'
                                            : 'لفة كاملة',
                                        style: TextStyle(
                                          color: _unitSelection == 1
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
                                      selected: _unitSelection == 1,
                                      onSelected: (selected) {
                                        setState(() {
                                          _unitSelection = 1;
                                          _useLargeUnit = true;
                                          _quantityController.clear();
                                        });
                                      },
                                      selectedColor:
                                          Theme.of(context).primaryColor,
                                      backgroundColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding:
                                          EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _quantityController,
                            decoration: InputDecoration(
                              labelText: _unitSelection == 1
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
                              final Set<double> priceSet = {};
                              final List<double> uniquePrices = [];

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

                              uniquePrices.addAll(priceSet);
                              uniquePrices.sort();

                              final List<DropdownMenuItem<double?>> priceItems =
                                  [];

                              for (var price in uniquePrices) {
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

                              priceItems.add(const DropdownMenuItem(
                                  value: -1, child: Text('سعر مخصص')));
                              return priceItems;
                            }(),
                            onChanged: isViewOnly
                                ? null
                                : (value) async {
                                    if (value == -1) {
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
                                                title: const Text(
                                                    'إدخال سعر مخصص'),
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
                                                      final val =
                                                          double.tryParse(
                                                              controller.text
                                                                  .trim());
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
                        if (!isViewOnly) SizedBox(width: 40),
                      ],
                    ),
                  ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _invoiceItems.length,
                  itemBuilder: (context, index) {
                    final item = _invoiceItems[index];
                    final displayQuantity =
                        item.quantityIndividual ?? item.quantityLargeUnit ?? 0;
                    String displayUnit;
                    if (item.unit == 'piece') {
                      displayUnit = item.quantityIndividual != null ? 'ق' : 'ك';
                    } else if (item.unit == 'meter') {
                      displayUnit = 'م';
                    } else {
                      displayUnit = '';
                    }

                    final quantityText =
                        displayQuantity == displayQuantity.toInt()
                            ? displayQuantity.toInt().toString()
                            : displayQuantity.toStringAsFixed(2);

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
                                child: Text(
                                    formatNumber(itemTotalAmount,
                                        forceDecimal: true),
                                    textAlign: TextAlign.center)),
                            Expanded(
                                flex: 4,
                                child: Text(item.productName,
                                    textAlign: TextAlign.center)),
                            Expanded(
                                flex: 1,
                                child: Text(
                                    formatNumber(displayQuantity,
                                        forceDecimal: true),
                                    textAlign: TextAlign.center)),
                            Expanded(
                                flex: 1,
                                child: Text(item.saleType ?? '',
                                    textAlign: TextAlign.center)),
                            Expanded(
                                flex: 2,
                                child: Text(
                                    formatNumber(item.appliedPrice,
                                        forceDecimal: true),
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
                Builder(
                  builder: (context) {
                    final totalBeforeDiscount = currentTotalAmount;
                    final total = currentTotalAmount - _discount;
                    double enteredPaidAmount =
                        double.tryParse(_paidAmountController.text) ?? 0;
                    double displayedPaidAmount = enteredPaidAmount;
                    double displayedRemainingAmount = total - enteredPaidAmount;

                    if (_paymentType == 'نقد') {
                      displayedPaidAmount = total;
                      displayedRemainingAmount = 0;
                    } else {}

                    return Card(
                      color: Colors.grey[100],
                      margin: const EdgeInsets.only(bottom: 16.0),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                'المبلغ الإجمالي قبل الخصم:  ${formatNumber(totalBeforeDiscount, forceDecimal: true)} دينار',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                                'المبلغ الإجمالي:  ${formatNumber(total, forceDecimal: true)} دينار',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                                'المبلغ المسدد:    ${formatNumber(displayedPaidAmount, forceDecimal: true)} دينار',
                                style: const TextStyle(color: Colors.green)),
                            const SizedBox(height: 4),
                            Text(
                                'المتبقي:         ${formatNumber(displayedRemainingAmount, forceDecimal: true)} دينار',
                                style: const TextStyle(color: Colors.red)),
                            if (_paymentType == 'دين')
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                    'أصبح الدين: ${formatNumber(displayedRemainingAmount, forceDecimal: true)} دينار',
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
                        'نوع الدفع: ${_invoiceToManage?.paymentType ?? 'غير محدد'}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (_invoiceToManage?.paymentType == 'دين' &&
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
                                  _guardDiscount();
                                  _updatePaidAmountIfCash();
                                  _autoSave();
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
                                  _paidAmountController.text = '0';
                                  _autoSave(); // حفظ تلقائي عند تغيير نوع الدفع
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
                      enabled: !isViewOnly && _paymentType == 'دين',
                      onChanged: (value) {
                        setState(() {
                          double enteredPaid = double.tryParse(value) ?? 0.0;
                          final total = _invoiceItems.fold(
                                  0.0, (sum, item) => sum + item.itemTotal) -
                              _discount;
                          if (enteredPaid >= total) {
                            _paidAmountController.text = '0';
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'المبلغ المسدد يجب أن يكون أقل من مبلغ الفاتورة في حالة الدين!')),
                            );
                          }
                        });
                      },
                    ),
                  ],
                ],
                const SizedBox(height: 24.0),
                TextFormField(
                  decoration: const InputDecoration(
                      labelText: 'الخصم (مبلغ وليس نسبة)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: isViewOnly
                      ? null
                      : (val) {
                          setState(() {
                            double enteredDiscount =
                                double.tryParse(val) ?? 0.0;
                            _discount = enteredDiscount;
                            _guardDiscount();
                            _updatePaidAmountIfCash();
                          });
                        },
                  initialValue: _discount > 0 ? _discount.toString() : '',
                  enabled: !isViewOnly,
                ),
                const SizedBox(height: 24.0),
                if (!isViewOnly)
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
                if (_invoiceToManage != null &&
                    _invoiceToManage!.status == 'محفوظة') ...[
                  if (!_invoiceToManage!.isLocked) ...[
                    SizedBox(height: 24),
                    TextFormField(
                      controller: _returnAmountController,
                      decoration:
                          InputDecoration(labelText: 'الراجع (مبلغ الإرجاع)'),
                      keyboardType: TextInputType.number,
                      enabled: !_invoiceToManage!.isLocked,
                    ),
                    SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: Icon(Icons.assignment_turned_in),
                      label: Text('حفظ الراجع'),
                      onPressed: () async {
                        final value =
                            double.tryParse(_returnAmountController.text) ??
                                0.0;
                        await _saveReturnAmount(value);
                      },
                    ),
                  ] else ...[
                    SizedBox(height: 24),
                    Text('الراجع: ${_invoiceToManage!.returnAmount} دينار',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.red)),
                    SizedBox(height: 8),
                    Text('الفاتورة مقفلة ولا يمكن تعديلها بعد حفظ الراجع.',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
