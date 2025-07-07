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
import 'dart:convert';

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
  final FocusNode _quantityFocusNode = FocusNode(); // FocusNode لحقل الكمية
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

  bool _isViewOnly = false;

  final FocusNode _searchFocusNode = FocusNode(); // FocusNode جديد لحقل البحث
  bool _suppressSearch = false; // لمنع البحث التلقائي عند اختيار منتج
  bool _quantityAutofocus = false; // للتحكم في autofocus لحقل الكمية

  // أضف متغير نوع القائمة (يظل موجوداً ولكن بدون واجهة مستخدم لتغييره)
  String _selectedListType = 'مفرد';
  final List<String> _listTypes = ['مفرد', 'جملة', 'جملة بيوت', 'بيوت', 'أخرى'];

  // 1. أضف المتغيرات أعلى الكلاس:
  List<Map<String, dynamic>> _currentUnitHierarchy = [];
  List<String> _currentUnitOptions = ['قطعة'];
  String _selectedUnitForItem = 'قطعة';

  List<Product>? _allProductsForUnits;

  late TextEditingController _loadingFeeController;

  @override
  void initState() {
    super.initState();
    _printingService = getPlatformPrintingService();
    _invoiceToManage = widget.existingInvoice;
    _isViewOnly = widget.isViewOnly;
    _loadingFeeController = TextEditingController();
    _loadAutoSavedData();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _allProductsForUnits = await _db.getAllProducts();
      setState(() {});
      // تمت إزالة استدعاء _loadAutoSavedData من هنا
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
    // تهيئة FocusNode
    _quantityFocusNode.addListener(_onFieldChanged);
    // إضافة مستمع لحقل البحث
    _productSearchController.addListener(() {
      if (_suppressSearch) {
        _suppressSearch = false;
        return;
      }
      if (_productSearchController.text.isNotEmpty) {
        _searchProducts(_productSearchController.text);
      }
      if (_productSearchController.text.isEmpty) {
        setState(() {
          _searchResults = [];
          _selectedProduct = null;
        });
      }
    });
  }

  // تحميل البيانات المحفوظة تلقائياً
  void _loadAutoSavedData() {
    if (_isViewOnly || widget.existingInvoice != null) {
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
          unitsInLargeUnit: item['unitsInLargeUnit'],
        );
      }).toList();

      _totalAmountController.text = _invoiceItems
          .fold(0.0, (sum, item) => sum + item.itemTotal)
          .toStringAsFixed(2);
    });
  }

  // حفظ البيانات تلقائياً
  void _autoSave() {
    if (_savedOrSuspended || _isViewOnly || widget.existingInvoice != null) {
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
                'unitsInLargeUnit': item.unitsInLargeUnit,
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
    if (!_savedOrSuspended && widget.existingInvoice == null && !_isViewOnly) {
      _autoSave();
    }

    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerAddressController.dispose();
    _installerNameController.dispose();
    _productSearchController.dispose();
    _quantityController.dispose();
    _itemsController.dispose();
    _totalAmountController.dispose();
    _paidAmountController.dispose();
    _discountController.dispose();
    _returnAmountController.dispose();
    _quantityFocusNode.dispose(); // تنظيف FocusNode
    _searchFocusNode.dispose();
    _loadingFeeController.dispose();
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
    // الحد الأعلى للخصم هو أقل من نصف الإجمالي
    final maxDiscount = (currentTotalAmount / 2) - 1;
    if (_discount > maxDiscount) {
      _discount = maxDiscount > 0 ? maxDiscount : 0.0;
      _discountController.text = _discount.toStringAsFixed(2);
    }
    if (_discount < 0) {
      _discount = 0.0;
      _discountController.text = '0';
    }
  }

  void _addInvoiceItem() {
    if (_formKey.currentState!.validate() &&
        _selectedProduct != null &&
        _selectedPriceLevel != null) {
      final double inputQuantity =
          double.tryParse(_quantityController.text.trim()) ?? 0.0;
      if (inputQuantity <= 0) return;
      double finalAppliedPrice = _selectedPriceLevel!;
      double baseUnitsPerSelectedUnit = 1.0;
      // --- تعديل منطق التسعير التراكمي ---
      if (_selectedProduct!.unit == 'piece' && _selectedUnitForItem != 'قطعة') {
        // إذا كان هناك تسلسل هرمي للوحدات
        if (_selectedProduct!.unitHierarchy != null &&
            _selectedProduct!.unitHierarchy!.isNotEmpty) {
          try {
            final List<dynamic> hierarchy = json
                .decode(_selectedProduct!.unitHierarchy!.replaceAll("'", '"'));
            List<num> factors = [];
            for (int i = 0; i < hierarchy.length; i++) {
              final unitName =
                  hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
              final quantity =
                  num.tryParse(hierarchy[i]['quantity'].toString()) ?? 1;
              factors.add(quantity);
              if (unitName == _selectedUnitForItem) {
                break;
              }
            }
            baseUnitsPerSelectedUnit = factors.fold(1, (a, b) => a * b);
            finalAppliedPrice = _selectedPriceLevel! * baseUnitsPerSelectedUnit;
          } catch (e) {
            // fallback: منطق قديم
            final selectedHierarchyUnit = _currentUnitHierarchy.firstWhere(
              (element) =>
                  (element['unit_name'] ?? element['name']) ==
                  _selectedUnitForItem,
              orElse: () => {},
            );
            if (selectedHierarchyUnit.isNotEmpty) {
              baseUnitsPerSelectedUnit = double.tryParse(
                      selectedHierarchyUnit['quantity'].toString()) ??
                  1.0;
              finalAppliedPrice =
                  _selectedPriceLevel! * baseUnitsPerSelectedUnit;
            }
          }
        }
      } else if (_selectedProduct!.unit == 'meter' &&
          _selectedUnitForItem == 'لفة') {
        baseUnitsPerSelectedUnit = _selectedProduct!.lengthPerUnit ?? 1.0;
        finalAppliedPrice = _selectedPriceLevel! * baseUnitsPerSelectedUnit;
      }
      final double totalBaseUnitsSold =
          inputQuantity * baseUnitsPerSelectedUnit;
      final double finalItemCostPrice =
          (_selectedProduct!.costPrice ?? 0) * totalBaseUnitsSold;
      final double finalItemTotal = inputQuantity * finalAppliedPrice;
      double? quantityIndividual;
      double? quantityLargeUnit;
      if ((_selectedProduct!.unit == 'piece' &&
              _selectedUnitForItem == 'قطعة') ||
          (_selectedProduct!.unit == 'meter' &&
              _selectedUnitForItem == 'متر')) {
        quantityIndividual = inputQuantity;
      } else {
        quantityLargeUnit = inputQuantity;
      }
      final newItem = InvoiceItem(
        invoiceId: 0,
        productName: _selectedProduct!.name,
        unit: _selectedProduct!.unit,
        unitPrice: _selectedProduct!.unitPrice,
        costPrice: finalItemCostPrice,
        quantityIndividual: quantityIndividual,
        quantityLargeUnit: quantityLargeUnit,
        appliedPrice: finalAppliedPrice,
        itemTotal: finalItemTotal,
        saleType: _selectedUnitForItem,
        unitsInLargeUnit:
            baseUnitsPerSelectedUnit != 1.0 ? baseUnitsPerSelectedUnit : null,
      );
      setState(() {
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
            unitsInLargeUnit: newItem.unitsInLargeUnit,
          );
        } else {
          _invoiceItems.add(newItem);
        }
        _productSearchController.clear();
        _quantityController.clear();
        _selectedProduct = null;
        _selectedPriceLevel = null;
        _searchResults = [];
        _selectedUnitForItem = 'قطعة';
        _currentUnitOptions = ['قطعة'];
        _currentUnitHierarchy = [];
        _guardDiscount();
        _updatePaidAmountIfCash();
        _autoSave();
        if (_invoiceToManage != null &&
            _invoiceToManage!.status == 'معلقة' &&
            !_invoiceToManage!.isLocked) {
          autoSaveSuspendedInvoice();
        }
      });
    }
  }

  void _removeInvoiceItem(int index) {
    setState(() {
      _invoiceItems.removeAt(index);
      _guardDiscount();
      _updatePaidAmountIfCash();
      _autoSave();
      if (_invoiceToManage != null &&
          _invoiceToManage!.status == 'معلقة' &&
          !_invoiceToManage!.isLocked) {
        autoSaveSuspendedInvoice();
      }
    });
  }

  Future<Invoice?> _saveInvoice({bool printAfterSave = false}) async {
    if (!_formKey.currentState!.validate()) return null;

    try {
      Customer? customer;
      if (_customerNameController.text.trim().isNotEmpty) {
        // التطبيع: إزالة المسافات من الاسم والبحث عبر الدالة الجديدة
        customer = await _db.findCustomerByNormalizedName(
          _customerNameController.text.trim(),
          phone: _customerPhoneController.text.trim().isEmpty
              ? null
              : _customerPhoneController.text.trim(),
        );
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

      // تحديد الحالة الجديدة
      String newStatus = 'محفوظة';
      bool newIsLocked =
          _invoiceToManage?.isLocked ?? false; // الحفاظ على حالة القفل الحالية

      if (_invoiceToManage != null) {
        if (_invoiceToManage!.status == 'معلقة') {
          newStatus = 'محفوظة';
          newIsLocked =
              false; // فواتير معلقة محولة تبقى قابلة للتعديل حتى إدخال الراجع
        }
      } else {
        // فواتير جديدة
        newIsLocked = false;
      }

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
        status: newStatus,
        returnAmount: _returnAmountController.text.isNotEmpty
            ? double.parse(_returnAmountController.text)
            : 0.0,
        isLocked: false, // دائماً غير مقفلة بعد الحفظ العادي
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
        // حذف جميع أصناف الفاتورة القديمة وإضافة الجديدة
        final oldItems = await _db.getInvoiceItems(invoiceId);
        for (var oldItem in oldItems) {
          await _db.deleteInvoiceItem(oldItem.id!);
        }
        for (var item in _invoiceItems) {
          item.invoiceId = invoiceId;
          await _db.insertInvoiceItem(item);
        }
        // تحديث الفاتورة بالحالة الجديدة
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
        // إضافة أصناف الفاتورة الجديدة
        for (var item in _invoiceItems) {
          item.invoiceId = invoiceId;
          await _db.insertInvoiceItem(item);
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

      String extraMsg = '';
      if (_paymentType == 'دين') {
        extraMsg =
            '\nتمت إضافة ${debt.toStringAsFixed(2)} دينار كدين للعميل لأن الفاتورة ${currentTotalAmount.toStringAsFixed(2)} - خصم ${_discount.toStringAsFixed(2)} - مسدد ${paid.toStringAsFixed(2)}';
      }

      // حذف البيانات المؤقتة بعد الحفظ الناجح
      _storage.remove('temp_invoice_data');
      _savedOrSuspended = true;

      // تحديث حالة الفاتورة في الذاكرة مباشرة بعد الحفظ
      final updatedInvoice = await _db.getInvoiceById(invoiceId);
      setState(() {
        _invoiceToManage = updatedInvoice;
        if (_invoiceToManage != null &&
            _invoiceToManage!.status == 'محفوظة' &&
            _invoiceToManage!.isLocked) {
          _isViewOnly = true;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الفاتورة بنجاح$extraMsg'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context)
            .popUntil((route) => route.isFirst); // العودة للصفحة الرئيسية
      }
      return updatedInvoice;
    } catch (e) {
      String errorMessage = 'حدث خطأ عند حفظ الفاتورة: ￼[${e.toString()}';

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
        id: _invoiceToManage?.id,
        customerName: _customerNameController.text.trim(),
        customerPhone: _customerPhoneController.text.trim(),
        customerAddress: _customerAddressController.text.trim(),
        installerName: _installerNameController.text.trim(),
        invoiceDate: _selectedDate,
        paymentType: _paymentType,
        totalAmount: totalAmount,
        discount: _discount,
        amountPaidOnInvoice: paid,
        createdAt: _invoiceToManage?.createdAt ?? DateTime.now(),
        lastModifiedAt: DateTime.now(),
        customerId: customerId,
        status: 'معلقة',
        isLocked: false,
        returnAmount: _returnAmountController.text.isNotEmpty
            ? double.tryParse(_returnAmountController.text) ?? 0.0
            : 0.0,
      );
      int invoiceId;
      if (_invoiceToManage != null) {
        invoiceId = _invoiceToManage!.id!;
        // حذف جميع أصناف الفاتورة القديمة وإضافة الجديدة
        final oldItems = await _db.getInvoiceItems(invoiceId);
        for (var oldItem in oldItems) {
          await _db.deleteInvoiceItem(oldItem.id!);
        }
        for (final item in _invoiceItems) {
          await _db.insertInvoiceItem(item.copyWith(invoiceId: invoiceId));
        }
        await context.read<AppProvider>().updateInvoice(invoice);
        print(
            'Suspended invoice. Invoice ID: $invoiceId, Status: ${invoice.status}');
      } else {
        invoiceId = await _db.insertInvoice(invoice);
        print(
            'Suspended invoice. Invoice ID: $invoiceId, Status: ${invoice.status}');
        for (final item in _invoiceItems) {
          await _db.insertInvoiceItem(item.copyWith(invoiceId: invoiceId));
        }
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
      String errorMessage = 'حدث خطأ عند تعليق الفاتورة: \\${e.toString()}';
      print('Error suspending invoice: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  Future<pw.Document> _generateInvoicePdf() async {
    final pdf = pw.Document();
    // تحميل صورة اللوجو الجديدة من الأصول
    final logoBytes = await rootBundle
        .load('assets/icon/AL_NASSER_logo_transparent_medium.png');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    final font =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
    final alnaserFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Old Antic Outline Shaded.ttf'));

    // دالة مساعدة لبناء سلسلة التحويل من InvoiceItem
    String buildUnitConversionStringForPdf(InvoiceItem item, Product? product) {
      if (item.unit == 'meter') {
        if (item.saleType == 'لفة' && item.unitsInLargeUnit != null) {
          return item.unitsInLargeUnit!.toString();
        } else {
          return '';
        }
      }
      if (item.saleType == 'قطعة' || item.saleType == 'متر') {
        return '';
      }
      if (product == null ||
          product.unitHierarchy == null ||
          product.unitHierarchy!.isEmpty) {
        return item.unitsInLargeUnit?.toString() ?? '';
      }
      try {
        final List<dynamic> hierarchy =
            json.decode(product.unitHierarchy!.replaceAll("'", '"'));
        List<String> factors = [];
        for (int i = 0; i < hierarchy.length; i++) {
          final unitName = hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
          final quantity = hierarchy[i]['quantity'];
          factors.add(quantity.toString());
          if (unitName == item.saleType) {
            break;
          }
        }
        if (factors.isEmpty) {
          return item.unitsInLargeUnit?.toString() ?? '';
        }
        return factors.join(' × ');
      } catch (e) {
        return item.unitsInLargeUnit?.toString() ?? '';
      }
    }

    // جلب جميع المنتجات لمطابقة الهيكل الهرمي
    final allProducts = await _db.getAllProducts();

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

    int invoiceId;
    if (_invoiceToManage != null && _invoiceToManage!.id != null) {
      invoiceId = _invoiceToManage!.id!;
    } else {
      invoiceId = (await _db.getLastInvoiceId()) + 1;
    }

    const itemsPerPage = 20;
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
          margin: pw.EdgeInsets.only(top: 0, bottom: 2, left: 10, right: 10),
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // --- رأس الفاتورة مع اللوجو الجديد في الجهة اليمنى ---
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // بقية رأس الفاتورة (العنوان والمعلومات)
                      pw.Expanded(
                        child: pw.Column(
                          children: [
                            pw.SizedBox(height: 0),
                            pw.Center(
                              child: pw.Text(
                                'الــــــنــــــاصــــــر',
                                style: pw.TextStyle(
                                  font: alnaserFont,
                                  fontSize: 45,
                                  height: 0,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.black,
                                ),
                              ),
                            ),
                            pw.Center(
                              child: pw.Text(
                                  'لتجارة المواد الصحية والعدد اليدوية والانشائية',
                                  style:
                                      pw.TextStyle(font: font, fontSize: 17)),
                            ),
                            pw.Center(
                              child: pw.Text(
                                'الموصل - الجدعة - مقابل البرج',
                                style: pw.TextStyle(font: font, fontSize: 13),
                              ),
                            ),
                            pw.Center(
                              child: pw.Text('0771 406 3064  |  0770 305 1353',
                                  style: pw.TextStyle(
                                      font: font,
                                      fontSize: 13,
                                      color: PdfColors.black)),
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Container(
                        width: 150,
                        height: 150,
                        // تم حذف border
                        child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  // --- معلومات العميل والتاريخ ---
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('السيد: ${_customerNameController.text}',
                          style: pw.TextStyle(font: font, fontSize: 12)),
                      pw.Text(
                          'العنوان: ${_customerAddressController.text.isNotEmpty ? _customerAddressController.text : ' ______'}',
                          style: pw.TextStyle(font: font, fontSize: 11)),
                      pw.Text('رقم الفاتورة: ${invoiceId}',
                          style: pw.TextStyle(font: font, fontSize: 10)),
                      pw.Text(
                          'الوقت: ${_invoiceToManage?.createdAt?.hour.toString().padLeft(2, '0') ?? DateTime.now().hour.toString().padLeft(2, '0')}:${_invoiceToManage?.createdAt?.minute.toString().padLeft(2, '0') ?? DateTime.now().minute.toString().padLeft(2, '0')}',
                          style: pw.TextStyle(font: font, fontSize: 11)),
                      pw.Text(
                        'التاريخ: ${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}',
                        style: pw.TextStyle(font: font, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Divider(height: 5, thickness: 0.5),

                  // --- جدول العناصر ---
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.2),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(90), // المبلغ
                      1: const pw.FixedColumnWidth(70), // السعر
                      2: const pw.FixedColumnWidth(65), // عدد الوحدات (جديد)
                      3: const pw.FixedColumnWidth(90), // العدد
                      4: const pw.FlexColumnWidth(0.8), // التفاصيل
                      5: const pw.FixedColumnWidth(20), // ت
                    },
                    defaultVerticalAlignment:
                        pw.TableCellVerticalAlignment.middle,
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(),
                        children: [
                          _headerCell('المبلغ', font),
                          _headerCell('السعر', font),
                          _headerCell('عدد الوحدات', font),
                          _headerCell('العدد', font),
                          _headerCell('التفاصيل ', font),
                          _headerCell('ت', font),
                        ],
                      ),
                      ...pageItems.asMap().entries.map((entry) {
                        final index = entry.key + (pageIndex * itemsPerPage);
                        final item = entry.value;
                        final quantity = (item.quantityIndividual ??
                            item.quantityLargeUnit ??
                            0.0);
                        Product? product;
                        try {
                          product = allProducts
                              .firstWhere((p) => p.name == item.productName);
                        } catch (e) {
                          product = null;
                        }
                        return pw.TableRow(
                          children: [
                            _dataCell(
                                formatNumber(item.itemTotal,
                                    forceDecimal: true),
                                font),
                            _dataCell(
                                formatNumber(item.appliedPrice,
                                    forceDecimal: true),
                                font),
                            // عدد الوحدات (منطق جديد)
                            _dataCell(
                              buildUnitConversionStringForPdf(item, product),
                              font,
                            ),
                            _dataCell(
                              '${formatNumber(quantity, forceDecimal: true)} ${item.saleType ?? ''}',
                              font,
                            ),
                            _dataCell(item.productName, font,
                                align: pw.TextAlign.right),
                            _dataCell('${index + 1}', font),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                  pw.Divider(height: 4, thickness: 0.4),

                  // --- المجاميع في الصفحة الأخيرة فقط ---
                  if (pageIndex == totalPages - 1) ...[
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            _summaryRow('الاجمالي قبل الخصم:',
                                currentTotalAmount, font),
                            pw.SizedBox(width: 10),
                            _summaryRow('الخصم:', discount, font),
                            pw.SizedBox(width: 10),
                            _summaryRow(
                                'الاجمالي بعد الخصم:', afterDiscount, font),
                            pw.SizedBox(width: 10),
                            _summaryRow('المبلغ المدفوع:', paid, font),
                          ],
                        ),
                        pw.SizedBox(height: 6),
                        if (!(_invoiceToManage != null &&
                            _invoiceToManage!.status == 'محفوظة'))
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              _summaryRow('المبلغ المتبقي:', remaining, font),
                              pw.SizedBox(width: 10),
                              _summaryRow('الدين السابق:', previousDebt, font),
                              pw.SizedBox(width: 10),
                              _summaryRow('الدين الحالي:', currentDebt, font),
                            ],
                          ),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Center(
                        child: pw.Text('شكراً لتعاملكم معنا',
                            style: pw.TextStyle(font: font, fontSize: 11))),
                  ],

                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text(
                      'صفحة ${pageIndex + 1} من $totalPages',
                      style: pw.TextStyle(font: font, fontSize: 11),
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
          style: pw.TextStyle(
              font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
          textAlign: align),
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
    // تحديث دين العميل وتسجيل معاملة تسديد راجع
    if (updatedInvoice.paymentType == 'دين' &&
        updatedInvoice.customerId != null &&
        value > 0) {
      final customer = await _db.getCustomerById(updatedInvoice.customerId!);
      if (customer != null) {
        final newDebt =
            (customer.currentTotalDebt - value).clamp(0.0, double.infinity);
        final updatedCustomer = customer.copyWith(
          currentTotalDebt: newDebt,
          lastModifiedAt: DateTime.now(),
        );
        await _db.updateCustomer(updatedCustomer);
        // سجل معاملة تسديد راجع
        await _db.insertTransaction(
          DebtTransaction(
            id: null,
            customerId: customer.id!,
            invoiceId: updatedInvoice.id!,
            amountChanged: -value, // سالبة لأنها تسديد
            transactionDate: DateTime.now(),
            newBalanceAfterTransaction: newDebt,
            transactionNote: 'تسديد راجع على الفاتورة رقم ${updatedInvoice.id}',
            transactionType: 'return_payment',
            createdAt: DateTime.now(),
          ),
        );
      }
    }
    // جلب أحدث نسخة من الفاتورة بعد الحفظ
    final updatedInvoiceFromDb =
        await _db.getInvoiceById(_invoiceToManage!.id!);
    setState(() {
      _invoiceToManage = updatedInvoiceFromDb;
    });
    setState(() {
      _isViewOnly = true; // تفعيل وضع العرض فقط
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ الراجع وقفل الفاتورة!'),
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context)
          .popUntil((route) => route.isFirst); // العودة للصفحة الرئيسية
    }
  }

  // دالة الحفظ التلقائي للفواتير المعلقة
  Future<void> autoSaveSuspendedInvoice() async {
    if (_invoiceToManage == null ||
        _invoiceToManage!.status != 'معلقة' ||
        _invoiceToManage!.isLocked) return;
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
        // لا تنشئ عميل جديد هنا، فقط استخدم الموجود إن وجد
      }
      double currentTotalAmount =
          _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      double paid = double.tryParse(_paidAmountController.text) ?? 0.0;
      double totalAmount = currentTotalAmount - _discount;
      Invoice invoice = _invoiceToManage!.copyWith(
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
        lastModifiedAt: DateTime.now(),
        customerId: customer?.id,
        // status: 'معلقة',
        returnAmount: _returnAmountController.text.isNotEmpty
            ? double.parse(_returnAmountController.text)
            : 0.0,
        isLocked: false,
      );
      int invoiceId = _invoiceToManage!.id!;
      // حذف جميع أصناف الفاتورة القديمة وإضافة الجديدة
      final oldItems = await _db.getInvoiceItems(invoiceId);
      for (var oldItem in oldItems) {
        await _db.deleteInvoiceItem(oldItem.id!);
      }
      for (var item in _invoiceItems) {
        item.invoiceId = invoiceId;
        await _db.insertInvoiceItem(item);
      }
      await context.read<AppProvider>().updateInvoice(invoice);
      setState(() {
        _invoiceToManage = invoice;
      });
    } catch (e) {
      print('Auto-save suspended invoice error: $e');
    }
  }

  // 2. أضف دالة توليد الوحدات:
  void _onProductSelected(Product product) {
    setState(() {
      _selectedProduct = product;
      _quantityController.clear();
      _currentUnitHierarchy = [];
      _currentUnitOptions = [];
      if (product.unit == 'piece') {
        _currentUnitOptions.add('قطعة');
        _selectedUnitForItem = 'قطعة';
        if (product.unitHierarchy != null &&
            product.unitHierarchy!.isNotEmpty) {
          try {
            final List<dynamic> parsed =
                json.decode(product.unitHierarchy!.replaceAll("'", '"'));
            _currentUnitHierarchy =
                parsed.map((e) => Map<String, dynamic>.from(e)).toList();
            _currentUnitOptions.addAll(_currentUnitHierarchy
                .map((e) => (e['unit_name'] ?? e['name'] ?? '').toString()));
            print(
                'DEBUG: product.unitHierarchy = \u001b[32m${product.unitHierarchy}\u001b[0m');
            print(
                'DEBUG: _currentUnitOptions = \u001b[36m$_currentUnitOptions\u001b[0m');
            print(
                'DEBUG: _currentUnitHierarchy = \u001b[35m$_currentUnitHierarchy\u001b[0m');
          } catch (e) {
            print('Error parsing unit hierarchy for ${product.name}: $e');
          }
        }
      } else if (product.unit == 'meter') {
        _currentUnitOptions = ['متر'];
        _selectedUnitForItem = 'متر';
        if (product.lengthPerUnit != null && product.lengthPerUnit! > 0) {
          _currentUnitOptions.add('لفة');
        }
      } else {
        _currentUnitOptions.add(product.unit);
        _selectedUnitForItem = product.unit;
      }
      double? newPriceLevel;
      switch (_selectedListType) {
        case 'مفرد':
          newPriceLevel = product.price1;
          break;
        case 'جملة':
          newPriceLevel = product.price2;
          break;
        case 'جملة بيوت':
          newPriceLevel = product.price3;
          break;
        case 'بيوت':
          newPriceLevel = product.price4;
          break;
        case 'أخرى':
          newPriceLevel = product.price5;
          break;
        default:
          newPriceLevel = product.price1;
      }
      if (newPriceLevel == null || newPriceLevel == 0) {
        newPriceLevel = product.unitPrice;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'المنتج "${product.name}" لا يملك سعر "$_selectedListType". تم اختيار سعر الوحدة الأصلي.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      _selectedPriceLevel = newPriceLevel;
      _suppressSearch = true;
      _productSearchController.text = product.name;
      _searchResults = [];
      _quantityAutofocus = true;
    });
  }

  // دالة مساعدة لبناء سلسلة التحويل للوحدة المختارة
  String buildUnitConversionString(
      InvoiceItem item, List<Product> allProducts) {
    // المنتجات التي تباع بالامتار
    if (item.unit == 'meter') {
      if (item.saleType == 'لفة' && item.unitsInLargeUnit != null) {
        return item.unitsInLargeUnit!.toString();
      } else {
        return '';
      }
    }
    // المنتجات التي تباع بالقطعة ولها تسلسل هرمي
    final product = allProducts.firstWhere(
      (p) => p.name == item.productName,
      orElse: () => Product(
        id: null,
        name: item.productName,
        unit: item.unit,
        unitPrice: item.unitPrice,
        costPrice: null,
        piecesPerUnit: null,
        lengthPerUnit: null,
        price1: item.unitPrice,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    if (product.unitHierarchy == null || product.unitHierarchy!.isEmpty) {
      return item.unitsInLargeUnit?.toString() ?? '';
    }
    try {
      final List<dynamic> hierarchy =
          json.decode(product.unitHierarchy!.replaceAll("'", '"'));
      // ابحث عن تسلسل التحويل للوحدة المختارة
      List<String> factors = [];
      for (int i = 0; i < hierarchy.length; i++) {
        final unitName = hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
        final quantity = hierarchy[i]['quantity'];
        factors.add(quantity.toString());
        if (unitName == item.saleType) {
          break;
        }
      }
      if (factors.isEmpty) {
        return item.unitsInLargeUnit?.toString() ?? '';
      }
      return factors.join(' × ');
    } catch (e) {
      return item.unitsInLargeUnit?.toString() ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    print('CreateInvoiceScreen: Building with isViewOnly: ${_isViewOnly}');
    final currentTotalAmount =
        _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final isViewOnly = _isViewOnly;
    final relatedDebtTransaction = widget.relatedDebtTransaction;
    final isLocked = _invoiceToManage?.isLocked ?? false;
    final isEnabled = !isViewOnly && !isLocked;
    bool canEditReturn = _invoiceToManage != null &&
        _invoiceToManage!.status == 'محفوظة' &&
        !_invoiceToManage!.isLocked &&
        (_invoiceToManage!.returnAmount == 0.0 ||
            _invoiceToManage!.returnAmount == null);

    return WillPopScope(
      onWillPop: () async {
        _autoSave();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_invoiceToManage != null && !_isViewOnly
              ? 'تعديل فاتورة'
              : (_isViewOnly ? 'عرض فاتورة' : 'إنشاء فاتورة')),
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
                      child: _isViewOnly
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
                                // مزامنة النص بين المتحكمين
                                if (controller.text !=
                                    _customerNameController.text) {
                                  controller.text =
                                      _customerNameController.text;
                                  controller.selection =
                                      TextSelection.fromPosition(
                                    TextPosition(
                                        offset: controller.text.length),
                                  );
                                }
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
                                    if (_invoiceToManage != null &&
                                        _invoiceToManage!.status == 'معلقة' &&
                                        !_invoiceToManage!.isLocked) {
                                      autoSaveSuspendedInvoice();
                                    }
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
                  // --- START: THE SECTION YOU WANTED TO REMOVE ---
                  // The Dropdown and SizedBox have been removed from here.
                  // --- END: THE SECTION YOU WANTED TO REMOVE ---
                  TextFormField(
                    controller: _productSearchController,
                    focusNode: _searchFocusNode, // ربط FocusNode
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
                                  _unitSelection = 0;
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
                                    FocusScope.of(context).unfocus();
                                    double? newPriceLevel;
                                    switch (_selectedListType) {
                                      case 'مفرد':
                                        newPriceLevel = product.price1;
                                        break;
                                      case 'جملة':
                                        newPriceLevel = product.price2;
                                        break;
                                      case 'جملة بيوت':
                                        newPriceLevel = product.price3;
                                        break;
                                      case 'بيوت':
                                        newPriceLevel = product.price4;
                                        break;
                                      case 'أخرى':
                                        newPriceLevel = product.price5;
                                        break;
                                      default:
                                        newPriceLevel = product.price1;
                                    }
                                    if (newPriceLevel == null ||
                                        newPriceLevel == 0) {
                                      newPriceLevel = product.unitPrice;
                                    }
                                    setState(() {
                                      _selectedProduct = product;
                                      _selectedPriceLevel = newPriceLevel;
                                      _quantityController.clear();
                                    });
                                    _onProductSelected(
                                        product); // استدعاء الدالة بعد setState
                                  },
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16.0),
                  if (_selectedProduct != null) ...[
                    Text('الصنف المحدد: ${_selectedProduct!.name}'),
                    const SizedBox(height: 8.0),
                    if ((_selectedProduct != null &&
                            _currentUnitOptions.length > 1) ||
                        (_selectedProduct!.unit == 'meter' &&
                            _selectedProduct!.lengthPerUnit != null))
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: _currentUnitOptions.map((unitName) {
                                  return ChoiceChip(
                                    label: Text(
                                      unitName,
                                      style: TextStyle(
                                        color: _selectedUnitForItem == unitName
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    selected: _selectedUnitForItem == unitName,
                                    onSelected: isViewOnly
                                        ? null
                                        : (selected) {
                                            if (selected) {
                                              setState(() {
                                                _selectedUnitForItem = unitName;
                                                _quantityController.clear();
                                              });
                                            }
                                          },
                                    selectedColor:
                                        Theme.of(context).primaryColor,
                                    backgroundColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                  );
                                }).toList(),
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
                            focusNode: _quantityFocusNode, // ربط FocusNode
                            autofocus: _quantityAutofocus, // ربط autofocus
                            decoration: InputDecoration(
                              labelText: 'الكمية (${_selectedUnitForItem})',
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
                          flex: 1,
                          child: DropdownButtonFormField<double?>(
                            decoration:
                                const InputDecoration(labelText: 'مستوى السعر'),
                            value: _selectedPriceLevel,
                            items: () {
                              final List<DropdownMenuItem<double?>> priceItems =
                                  [];
                              final product = _selectedProduct!;
                              final List<Map<String, dynamic>> priceOptions = [
                                {
                                  'value': product.price1,
                                  'label': 'سعر المفرد (سعر 1)',
                                  'number': 1,
                                },
                                {
                                  'value': product.price2,
                                  'label': 'سعر الجملة (سعر 2)',
                                  'number': 2,
                                },
                                {
                                  'value': product.price3,
                                  'label': 'سعر الجملة بيوت (سعر 3)',
                                  'number': 3,
                                },
                                {
                                  'value': product.price4,
                                  'label': 'سعر البيوت (سعر 4)',
                                  'number': 4,
                                },
                                {
                                  'value': product.price5,
                                  'label': 'سعر أخرى (سعر 5)',
                                  'number': 5,
                                },
                                {
                                  'value': product.unitPrice ?? 0.0,
                                  'label': 'سعر الوحدة الأصلي',
                                  'number': null,
                                  'alwaysShow': true,
                                },
                              ];
                              for (var option in priceOptions) {
                                if ((option['value'] != null &&
                                        option['value'] > 0) ||
                                    option['alwaysShow'] == true) {
                                  String text =
                                      option['label'] + ': ${option['value']}';
                                  priceItems.add(DropdownMenuItem(
                                    value: option['value'],
                                    child: Text(text),
                                  ));
                                }
                              }
                              // إضافة خيار سعر التكلفة (غير قابل للاختيار)
                              if (product.costPrice != null &&
                                  product.costPrice! > 0) {
                                priceItems.add(DropdownMenuItem(
                                  value: null,
                                  enabled: false,
                                  child: Text(
                                      'سعر التكلفة: ${product.costPrice}',
                                      style: TextStyle(color: Colors.grey)),
                                ));
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
                                                      final v = double.tryParse(
                                                          controller.text
                                                              .trim());
                                                      if (v != null && v > 0) {
                                                        Navigator.pop(
                                                            context, v);
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
                        const SizedBox(width: 8.0),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<String>(
                            value: _selectedListType,
                            decoration:
                                const InputDecoration(labelText: 'نوع القائمة'),
                            items: _listTypes
                                .map((type) => DropdownMenuItem(
                                    value: type, child: Text(type)))
                                .toList(),
                            onChanged: isViewOnly
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() {
                                        _selectedListType = value;
                                        if (_selectedProduct != null) {
                                          double? newPriceLevel;
                                          switch (value) {
                                            case 'مفرد':
                                              newPriceLevel =
                                                  _selectedProduct!.price1;
                                              break;
                                            case 'جملة':
                                              newPriceLevel =
                                                  _selectedProduct!.price2;
                                              break;
                                            case 'جملة بيوت':
                                              newPriceLevel =
                                                  _selectedProduct!.price3;
                                              break;
                                            case 'بيوت':
                                              newPriceLevel =
                                                  _selectedProduct!.price4;
                                              break;
                                            case 'أخرى':
                                              newPriceLevel =
                                                  _selectedProduct!.price5;
                                              break;
                                          }
                                          if (newPriceLevel != null &&
                                              newPriceLevel > 0) {
                                            _selectedPriceLevel = newPriceLevel;
                                          } else {
                                            _selectedPriceLevel = null;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'المنتج المحدد لا يملك سعر "$value".'),
                                                backgroundColor: Colors.orange,
                                              ),
                                            );
                                          }
                                        }
                                      });
                                    }
                                  },
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
                            flex: 3,
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
                        Expanded(
                            flex: 1,
                            child: Text('عدد الوحدات',
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
                      displayUnit = item.quantityIndividual != null ? 'م' : 'ل';
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
                                flex: 3,
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
                            Expanded(
                              flex: 1,
                              child: (item.saleType == 'قطعة' ||
                                      item.saleType == 'متر')
                                  ? const SizedBox()
                                  : Text(
                                      buildUnitConversionString(
                                          item, _allProductsForUnits ?? []),
                                      textAlign: TextAlign.center),
                            ),
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
                                if (_invoiceToManage != null &&
                                    _invoiceToManage!.status == 'معلقة' &&
                                    !_invoiceToManage!.isLocked) {
                                  autoSaveSuspendedInvoice();
                                }
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
                                  _autoSave();
                                });
                                if (_invoiceToManage != null &&
                                    _invoiceToManage!.status == 'معلقة' &&
                                    !_invoiceToManage!.isLocked) {
                                  autoSaveSuspendedInvoice();
                                }
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
                        if (_invoiceToManage != null &&
                            _invoiceToManage!.status == 'معلقة' &&
                            !_invoiceToManage!.isLocked) {
                          autoSaveSuspendedInvoice();
                        }
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
                          if (_invoiceToManage != null &&
                              _invoiceToManage!.status == 'معلقة' &&
                              !_invoiceToManage!.isLocked) {
                            autoSaveSuspendedInvoice();
                          }
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
                      if (!(_invoiceToManage != null &&
                          _invoiceToManage!.status == 'معلقة'))
                        ElevatedButton.icon(
                          onPressed: _suspendInvoice,
                          icon: const Icon(Icons.pause),
                          label: const Text('تعليق الفاتورة'),
                        ),
                    ],
                  ),
                // إظهار قسم الراجع بعد الحفظ مباشرة
                if (_invoiceToManage != null &&
                    _invoiceToManage!.status == 'محفوظة' &&
                    !_invoiceToManage!.isLocked) ...[
                  SizedBox(height: 24),
                  TextFormField(
                    controller: _returnAmountController,
                    decoration:
                        InputDecoration(labelText: 'الراجع (مبلغ الإرجاع)'),
                    keyboardType: TextInputType.number,
                    enabled: true, // نشط دائماً في هذه الحالة
                  ),
                  SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: Icon(Icons.assignment_turned_in),
                    label: Text('حفظ الراجع'),
                    onPressed: () async {
                      final value =
                          double.tryParse(_returnAmountController.text) ?? 0.0;
                      await _saveReturnAmount(value);
                    }, // نشط دائماً في هذه الحالة
                  ),
                ],
                // عرض حالة الراجع للفواتير المقفلة أو إذا تم إدخال الراجع بالفعل
                if (_invoiceToManage != null &&
                    (_invoiceToManage!.isLocked ||
                        (_invoiceToManage!.returnAmount != 0.0 &&
                            _invoiceToManage!.returnAmount != null))) ...[
                  SizedBox(height: 24),
                  Text('الراجع: ${_invoiceToManage!.returnAmount} دينار',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.red)),
                  SizedBox(height: 8),
                  Text('الفاتورة مقفلة ولا يمكن تعديلها',
                      style: TextStyle(color: Colors.grey)),
                ],
                // إضافة حقل أجور التحميل فقط إذا لم يكن العرض فقط أو الفاتورة مقفلة
                if (!isViewOnly && !isLocked) ...[
                  const SizedBox(height: 16.0),
                  TextFormField(
                    controller: _loadingFeeController,
                    decoration: const InputDecoration(
                      labelText: 'أجور التحميل (اختياري)',
                      hintText: 'أدخل مبلغ أجور التحميل إذا وجد',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
