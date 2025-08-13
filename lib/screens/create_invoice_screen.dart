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
import 'package:flutter/scheduler.dart';
import '../services/pdf_header.dart';

// تعريف EditableInvoiceItemRow موجود هنا (أو تأكد من وجوده قبل استخدامه في ListView)
// إذا كان التعريف موجود بالفعل، لا داعي لأي تعديل إضافي هنا.
// إذا لم يكن موجودًا، أضف الكود الذي تم إنشاؤه في الخطوة السابقة هنا.

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
  
  // متغير للتحكم في السعر المخصص
  bool _isCustomPrice = false;

  List<Product>? _allProductsForUnits;

  late TextEditingController _loadingFeeController;

  List<LineItemFocusNodes> focusNodesList = [];

  @override
  void initState() {
    super.initState();
    try {
      _printingService = getPlatformPrintingService();
      _invoiceToManage = widget.existingInvoice;
      _isViewOnly = widget.isViewOnly;
      _loadingFeeController = TextEditingController();
      _loadAutoSavedData();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          _allProductsForUnits = await _db.getAllProducts();
          setState(() {});
        } catch (e) {
          print('Error loading products: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('حدث خطأ أثناء تحميل المنتجات: $e')),
            );
          }
        }
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
        _customerAddressController.text =
            _invoiceToManage!.customerAddress ?? '';
        _installerNameController.text = _invoiceToManage!.installerName ?? '';
        _selectedDate = _invoiceToManage!.invoiceDate;
        _paymentType = _invoiceToManage!.paymentType;
        _totalAmountController.text = _invoiceToManage!.totalAmount.toString();
        _paidAmountController.text =
            _invoiceToManage!.amountPaidOnInvoice.toString();
        _discount = _invoiceToManage!.discount;
        _discountController.text = _discount.toStringAsFixed(2);
        _returnAmountController.text =
            _invoiceToManage!.returnAmount.toString();

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
    } catch (e) {
      print('Error in initState: $e');
    }
    if (_invoiceItems.isEmpty) {
      _invoiceItems.add(InvoiceItem(
        invoiceId: 0,
        productName: '',
        unit: '',
        unitPrice: 0.0,
        appliedPrice: 0.0,
        itemTotal: 0.0,
        uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
      ));
    }
  }

  // تحميل البيانات المحفوظة تلقائياً
  void _loadAutoSavedData() {
    try {
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
            uniqueId: item['uniqueId'] ?? 'item_${DateTime.now().microsecondsSinceEpoch}',
          );
        }).toList();

        _totalAmountController.text = _invoiceItems
            .fold(0.0, (sum, item) => sum + item.itemTotal)
            .toStringAsFixed(2);
      });
    } catch (e) {
      print('Error loading auto-saved data: $e');
    }
  }

  // حفظ البيانات تلقائياً
  void _autoSave() {
    try {
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
                  'uniqueId': item.uniqueId,
                })
            .toList(),
      };

      _storage.write('temp_invoice_data', data);
    } catch (e) {
      print('Error in autoSave: $e');
    }
  }

  // معالج تغيير الحقول مع تأخير
  void _onFieldChanged() {
    try {
      if (_debounceTimer?.isActive ?? false) {
        _debounceTimer!.cancel();
      }

      _debounceTimer = Timer(const Duration(seconds: 1), _autoSave);
    } catch (e) {
      print('Error in onFieldChanged: $e');
    }
  }

  Future<void> _loadInvoiceItems() async {
    try {
      if (_invoiceToManage != null && _invoiceToManage!.id != null) {
        final items = await _db.getInvoiceItems(_invoiceToManage!.id!);
        // تهيئة الـ controllers لكل صنف
        for (var item in items) {
          item.initializeControllers();
        }
        // تهيئة FocusNodes لكل صنف
        focusNodesList.clear();
        for (var _ in items) {
          focusNodesList.add(LineItemFocusNodes());
        }
        setState(() {
          _invoiceItems = items;
          _totalAmountController.text = _invoiceItems
              .fold(0.0, (sum, item) => sum + item.itemTotal)
              .toStringAsFixed(2);
        });
      }
    } catch (e) {
      print('Error loading invoice items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل أصناف الفاتورة: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    try {
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
          !_isViewOnly) {
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
      // --- تخلص من جميع FocusNodes الخاصة بالصفوف ---
      for (final node in focusNodesList) {
        node.dispose();
      }
      focusNodesList.clear();
      // --- نهاية التخصيص ---
      super.dispose();
    } catch (e) {
      print('Error in dispose: $e');
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    try {
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
    } catch (e) {
      print('Error selecting date: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء اختيار التاريخ: $e')),
        );
      }
    }
  }

  Future<void> _searchProducts(String query) async {
    try {
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
    } catch (e) {
      print('Error searching products: $e');
      setState(() {
        _searchResults = [];
      });
    }
  }

  // دالة لتحديث المبلغ المسدد تلقائيًا إذا كان الدفع نقد
  void _updatePaidAmountIfCash() {
    try {
      if (_paymentType == 'نقد') {
        _guardDiscount();
        final currentTotalAmount =
            _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final total = currentTotalAmount - _discount;
        _paidAmountController.text =
            total.clamp(0, double.infinity).toStringAsFixed(2);
      }
    } catch (e) {
      print('Error in updatePaidAmountIfCash: $e');
    }
  }

  // دالة مركزية لحماية الخصم
  void _guardDiscount() {
    try {
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
    } catch (e) {
      print('Error in guardDiscount: $e');
    }
  }

  void _addInvoiceItem() {
    try {
      if (_formKey.currentState!.validate() &&
          _selectedProduct != null &&
          _selectedPriceLevel != null) {
        final double inputQuantity =
            double.tryParse(_quantityController.text.trim()) ?? 0.0;
        if (inputQuantity <= 0) return;
        double finalAppliedPrice = _selectedPriceLevel!;
        double baseUnitsPerSelectedUnit = 1.0;
        // --- تعديل منطق التسعير التراكمي ---
        if (_selectedProduct!.unit == 'piece' &&
            _selectedUnitForItem != 'قطعة') {
          // إذا كان هناك تسلسل هرمي للوحدات
          if (_selectedProduct!.unitHierarchy != null &&
              _selectedProduct!.unitHierarchy!.isNotEmpty) {
            try {
              final List<dynamic> hierarchy = json.decode(
                  _selectedProduct!.unitHierarchy!.replaceAll("'", '"'));
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
              finalAppliedPrice =
                  _selectedPriceLevel! * baseUnitsPerSelectedUnit;
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
                if (_isCustomPrice) {
                  finalAppliedPrice = _selectedPriceLevel!;
                } else {
                  finalAppliedPrice =
                      _selectedPriceLevel! * baseUnitsPerSelectedUnit;
                }
              }
            }
          }
        } else if (_selectedProduct!.unit == 'meter' &&
            _selectedUnitForItem == 'لفة') {
          baseUnitsPerSelectedUnit = _selectedProduct!.lengthPerUnit ?? 1.0;
          if (_isCustomPrice) {
            finalAppliedPrice = _selectedPriceLevel!;
          } else {
            finalAppliedPrice = _selectedPriceLevel! * baseUnitsPerSelectedUnit;
          }
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
              costPrice:
                  (existingItem.costPrice ?? 0) + (newItem.costPrice ?? 0),
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
              (_invoiceToManage?.isLocked ?? false)) {
            autoSaveSuspendedInvoice();
          }
          // --- معالجة الصفوف الفارغة ---
          // احذف جميع الصفوف الفارغة (غير المكتملة)
          _invoiceItems.removeWhere((item) => !_isInvoiceItemComplete(item));
          // ثم أضف صف فارغ جديد إذا كان آخر صف مكتمل أو القائمة فارغة
          if (_invoiceItems.isEmpty ||
              _isInvoiceItemComplete(_invoiceItems.last)) {
            _invoiceItems.add(InvoiceItem(
              invoiceId: 0,
              productName: '',
              unit: '',
              unitPrice: 0.0,
              appliedPrice: 0.0,
              itemTotal: 0.0,
              uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
            ));
          }
        });
      }
    } catch (e) {
      print('Error adding invoice item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء إضافة الصنف: $e')),
        );
      }
    }
  }

  void _removeInvoiceItem(int index) {
    try {
      if (index < 0 || index >= _invoiceItems.length) return;
      _removeInvoiceItemByUid(_invoiceItems[index].uniqueId);
    } catch (e) {
      print('Error removing invoice item: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حذف الصنف: $e')),
        );
      }
    }
  }

  void _removeInvoiceItemByUid(String uid) {
    try {
      setState(() {
        final index = _invoiceItems.indexWhere((it) => it.uniqueId == uid);
        if (index == -1) return;
        if (index < focusNodesList.length) {
          focusNodesList[index].dispose();
          focusNodesList.removeAt(index);
        }
        _invoiceItems.removeAt(index);
        _guardDiscount();
        _updatePaidAmountIfCash();
        _recalculateTotals();
        _autoSave();
        if (_invoiceToManage != null &&
            _invoiceToManage!.status == 'معلقة' &&
            (_invoiceToManage?.isLocked ?? false)) {
          autoSaveSuspendedInvoice();
        }
      });
    } catch (e) {
      print('Error removing invoice item by uid: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حذف الصنف: $e')),
        );
      }
    }
  }

  Future<Invoice?> _saveInvoice({bool printAfterSave = false}) async {
    if (!_formKey.currentState!.validate()) return null;
    print('--- بيانات الفاتورة عند الحفظ ---');
    print('اسم العميل: ${_customerNameController.text}');
    print('رقم الهاتف: ${_customerPhoneController.text}');
    print('العنوان: ${_customerAddressController.text}');
    print('اسم المؤسس/الفني: ${_installerNameController.text}');
    print('تاريخ الفاتورة: ${_selectedDate.toIso8601String()}');
    print('نوع الدفع: ${_paymentType}');
    print('الخصم: ${_discount}');
    print('المبلغ المسدد: ${_paidAmountController.text}');
    print('--- أصناف الفاتورة ---');
    for (var item in _invoiceItems) {
      print('--- صنف ---');
      print('المنتج:  ${item.productName}');
      print(
          'الكمية:  ${(item.quantityIndividual ?? item.quantityLargeUnit ?? 0)}');
      print('نوع البيع:  ${item.saleType}');
      print('السعر:  ${item.appliedPrice}');
      print('المبلغ:  ${item.itemTotal}');
      print('التفاصيل:  ${item.productName != null ? item.productName : ''}');
    }
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
      final totalAmountForDiscount =
          _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      if (_discount >= totalAmountForDiscount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'نسبة الخصم خاطئة! (الخصم: ${_discount.toStringAsFixed(2)} الإجمالي: ${totalAmountForDiscount.toStringAsFixed(2)})')),
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
      // احذف جميع الأصناف غير المكتملة قبل التعليق
      _invoiceItems.removeWhere((item) => !_isInvoiceItemComplete(item));
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
    try {
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
      String buildUnitConversionStringForPdf(
          InvoiceItem item, Product? product) {
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
                    buildPdfHeader(font, alnaserFont, logoImage),
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
                          if ((_invoiceToManage?.status == 'محفوظة') &&
                              !(_invoiceToManage?.isLocked ?? false)) ...[
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.end,
                              children: [
                                _summaryRow('المبلغ المتبقي:', remaining, font),
                                pw.SizedBox(width: 10),
                                _summaryRow(
                                    'الدين السابق:', previousDebt, font),
                                pw.SizedBox(width: 10),
                                _summaryRow('الدين الحالي:', currentDebt, font),
                              ],
                            ),
                          ],
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
    } catch (e) {
      print('Error generating PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء إنشاء ملف PDF: $e')),
        );
      }
      rethrow;
    }
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
    try {
      final safeCustomerName =
          customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
      final formattedDate = DateFormat('yyyy-MM-dd').format(invoiceDate);
      final fileName = '${safeCustomerName}_$formattedDate.pdf';
      final directory = Directory(
          '${Platform.environment['USERPROFILE']}/Documents/invoices');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      return filePath;
    } catch (e) {
      print('Error saving PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حفظ ملف PDF: $e')),
        );
      }
      rethrow;
    }
  }

  Future<void> _printInvoice() async {
    try {
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
                SnackBar(
                    content: Text('حدث خطأ أثناء الطباعة: ${e.toString()}')),
              );
            }
          }
        }
        return;
      }
    } catch (e) {
      print('Error printing invoice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الطباعة: $e')),
        );
      }
    }
  }

  void _resetInvoice() {
    try {
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
    } catch (e) {
      print('Error resetting invoice: $e');
    }
  }

  void _performReset() {
    try {
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
        _invoiceItems.clear(); // حذف جميع الأصناف فورًا
        for (final node in focusNodesList) {
          node.dispose();
        }
        focusNodesList.clear();
        _searchResults.clear();
        _totalAmountController.text = '0';
        _savedOrSuspended = false;
        _storage.remove('temp_invoice_data');
      });

      // بعد ثانية واحدة أضف عنصر فارغ جديد
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _invoiceItems.add(InvoiceItem(
              invoiceId: 0,
              productName: '',
              unit: '',
              unitPrice: 0.0,
              appliedPrice: 0.0,
              itemTotal: 0.0,
              uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
            ));
            focusNodesList.add(LineItemFocusNodes());
          });
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم بدء فاتورة جديدة')),
      );
    } catch (e) {
      print('Error performing reset: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء بدء فاتورة جديدة: $e')),
        );
      }
    }
  }

  Future<void> _saveReturnAmount(double value) async {
    try {
      if (_invoiceToManage == null || _invoiceToManage!.isLocked) return;
      // تحديث الفاتورة في قاعدة البيانات
      final updatedInvoice =
          _invoiceToManage!.copyWith(returnAmount: value, isLocked: true);
      await _db.updateInvoice(updatedInvoice);

      // خصم الراجع من رصيد المؤسس
      if (updatedInvoice.installerName != null &&
          updatedInvoice.installerName!.isNotEmpty) {
        final installer =
            await _db.getInstallerByName(updatedInvoice.installerName!);
        if (installer != null) {
          final newTotal =
              (installer.totalBilledAmount - value).clamp(0.0, double.infinity);
          final updatedInstaller =
              installer.copyWith(totalBilledAmount: newTotal);
          await _db.updateInstaller(updatedInstaller);
        }
      }

      // إذا كانت الفاتورة دين، خصم الراجع من دين العميل وتسجيل معاملة تسديد راجع
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
              transactionNote:
                  'تسديد راجع على الفاتورة رقم ${updatedInvoice.id}',
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
    } catch (e) {
      print('Error saving return amount: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حفظ الراجع: $e')),
        );
      }
    }
  }

  // دالة الحفظ التلقائي للفواتير المعلقة
  Future<void> autoSaveSuspendedInvoice() async {
    try {
      if (_invoiceToManage == null ||
          _invoiceToManage!.status != 'معلقة' ||
          (_invoiceToManage?.isLocked ?? false)) return;
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
    try {
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
          _selectedPriceLevel = null;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('المنتج المحدد لا يملك سعر "$_selectedListType".'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          // تحقق أن السعر موجود في قائمة الأسعار
          final validPrices = [
            product.price1,
            product.price2,
            product.price3,
            product.price4,
            product.price5
          ].where((p) => p != null && p > 0).toList();
          if (validPrices.contains(newPriceLevel)) {
            _selectedPriceLevel = newPriceLevel;
          } else {
            _selectedPriceLevel = null;
          }
        }
        _suppressSearch = true;
        _productSearchController.text = product.name;
        _searchResults = [];
        _quantityAutofocus = true;
      });
    } catch (e) {
      print('Error selecting product: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء اختيار المنتج: $e')),
        );
      }
    }
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

  void _recalculateTotals() {
    double total = _invoiceItems.fold(0, (sum, item) => sum + item.itemTotal);
    _totalAmountController.text = total.toStringAsFixed(2);
    if (_paymentType == 'نقد') {
      _paidAmountController.text = (total - _discount).toStringAsFixed(2);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // تعريف الألوان والثيم العصري
    final Color primaryColor = const Color(0xFF3F51B5); // Indigo
    final Color accentColor = const Color(0xFF8C9EFF); // Light Indigo Accent
    final Color textColor = const Color(0xFF212121);
    final Color lightBackgroundColor = const Color(0xFFF8F8F8);
    final Color successColor = Colors.green[600]!;
    final Color errorColor = Colors.red[700]!;

    // استخدم القائمة الكاملة دائمًا لعرض جميع الصفوف بما في ذلك الصف الفارغ الجديد
    final displayedItems = _invoiceItems;

    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white,
          secondary: accentColor,
          onSecondary: Colors.black,
          surface: Colors.white,
          onSurface: textColor,
          background: Colors.white,
          onBackground: textColor,
          error: errorColor,
          onError: Colors.white,
          tertiary: successColor,
        ),
        fontFamily: 'Roboto',
        textTheme: TextTheme(
          titleLarge: TextStyle(
              fontSize: 22.0, fontWeight: FontWeight.bold, color: Colors.white),
          titleMedium: TextStyle(
              fontSize: 18.0, fontWeight: FontWeight.w600, color: textColor),
          bodyLarge: TextStyle(fontSize: 16.0, color: textColor),
          bodyMedium: TextStyle(fontSize: 14.0, color: textColor),
          labelLarge: TextStyle(
              fontSize: 16.0, color: Colors.white, fontWeight: FontWeight.w600),
          labelMedium: TextStyle(fontSize: 14.0, color: Colors.grey[600]),
          bodySmall: TextStyle(fontSize: 12.0, color: Colors.grey[700]),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: primaryColor, width: 2.0),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          labelStyle: TextStyle(color: Colors.grey[700], fontSize: 15.0),
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14.0),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
          filled: true,
          fillColor: lightBackgroundColor,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0)),
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            elevation: 4,
            textStyle: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
        cardTheme: CardThemeData(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          margin: EdgeInsets.zero,
        ),
        listTileTheme: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          tileColor: lightBackgroundColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 4,
          titleTextStyle: TextStyle(
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
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
                                // مزامنة النص بين المتحكمين بعد انتهاء عملية البناء
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
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
                                });
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
                                        (_invoiceToManage?.isLocked ?? false)) {
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
                        enabled: !_isViewOnly,
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
                        enabled: !_isViewOnly,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _installerNameController,
                        decoration: const InputDecoration(
                            labelText: 'اسم المؤسس/الفني (اختياري)'),
                        enabled: !_isViewOnly,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24.0),
                if (!_isViewOnly) ...[
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
                        onPressed: _isViewOnly
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
                    onChanged: _isViewOnly ? null : _searchProducts,
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
                            onTap: _isViewOnly
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
                                    onSelected: _isViewOnly
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
                            focusNode: focusNodesList.length > 0
                                ? focusNodesList[0].quantity
                                : null,
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
                            enabled: !_isViewOnly,
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          flex: 1,
                          child: Builder(
                            builder: (context) {
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
                              ];
                              final List<DropdownMenuItem<double?>> priceItems =
                                  [];
                              final Set<double?> seenValues = {};
                              for (var option in priceOptions) {
                                final val = option['value'];
                                if ((val != null &&
                                        val > 0 &&
                                        !seenValues.contains(val)) ||
                                    option['alwaysShow'] == true) {
                                  String text = option['label'] + ': ${val}';
                                  priceItems.add(DropdownMenuItem(
                                    value: val,
                                    child: Text(text),
                                  ));
                                  seenValues.add(val);
                                }
                              }
                              // إذا كانت قيمة _selectedPriceLevel غير موجودة في القائمة وأكبر من 0 (أي سعر مخصص)، أضفها مؤقتًا
                              if (_selectedPriceLevel != null &&
                                  _selectedPriceLevel! > 0 &&
                                  !seenValues.contains(_selectedPriceLevel)) {
                                priceItems.add(
                                  DropdownMenuItem(
                                    value: _selectedPriceLevel,
                                    child: Text(
                                        'سعر مخصص: ${_selectedPriceLevel!.toStringAsFixed(2)}'),
                                  ),
                                );
                                seenValues.add(_selectedPriceLevel);
                              }
                              priceItems.add(const DropdownMenuItem(
                                  value: -1, child: Text('سعر مخصص')));
                              // تحقق أن القيمة المختارة تظهر مرة واحدة فقط، وإلا اجعلها null
                              final validValues =
                                  priceItems.map((item) => item.value).toList();
                              final dropdownValue = validValues
                                          .where(
                                              (v) => v == _selectedPriceLevel)
                                          .length ==
                                      1
                                  ? _selectedPriceLevel
                                  : null;
                              return DropdownButtonFormField<double?>(
                                decoration: const InputDecoration(
                                    labelText: 'مستوى السعر'),
                                value: dropdownValue,
                                items: priceItems,
                                onChanged: _isViewOnly
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
                                                      decoration:
                                                          InputDecoration(
                                                              hintText:
                                                                  'أدخل السعر',
                                                              errorText:
                                                                  errorText),
                                                      onChanged: (val) {
                                                        final v =
                                                            double.tryParse(
                                                                val.trim());
                                                        setState(() {
                                                          if (v == null ||
                                                              v <= 0) {
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
                                                            Navigator.pop(
                                                                context),
                                                        child:
                                                            const Text('إلغاء'),
                                                      ),
                                                      TextButton(
                                                        onPressed: () {
                                                          final v =
                                                              double.tryParse(
                                                                  controller
                                                                      .text
                                                                      .trim());
                                                          if (v != null &&
                                                              v > 0) {
                                                            Navigator.pop(
                                                                context, v);
                                                          }
                                                        },
                                                        child:
                                                            const Text('موافق'),
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
                                isDense: _isViewOnly,
                                menuMaxHeight: _isViewOnly ? 0 : 200,
                              );
                            },
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
                            onChanged: _isViewOnly
                                ? null
                                : (value) async {
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
                                      // بعد تحديث القائمة أو جلب الأصناف من قاعدة البيانات
                                      print(
                                          '--- العناصر الحالية بعد اختيار نوع القائمة ---');
                                      for (var item in _invoiceItems) {
                                        print('--- صنف ---');
                                        print('المنتج:  ${item.productName}');
                                        print(
                                            'الكمية:  ${(item.quantityIndividual ?? item.quantityLargeUnit ?? 0)}');
                                        print('نوع البيع:  ${item.saleType}');
                                        print('السعر:  ${item.appliedPrice}');
                                        print('المبلغ:  ${item.itemTotal}');
                                        print(
                                            'التفاصيل:  ${item.productName != null ? item.productName : ''}');
                                      }
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0),
                    ElevatedButton(
                      onPressed: _isViewOnly ? null : _addInvoiceItem,
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
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                            flex: 1,
                            child: Center(
                                child: Text('ت',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)))),
                        Expanded(
                            flex: 2,
                            child: Center(
                                child: Text('المبلغ',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)))),
                        Expanded(
                            flex: 3,
                            child: Center(
                                child: Text('التفاصيل',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)))),
                        Expanded(
                            flex: 2,
                            child: Center(
                                child: Text('العدد',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)))),
                        Expanded(
                            flex: 2,
                            child: Center(
                                child: Text('نوع البيع',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)))),
                        Expanded(
                            flex: 2,
                            child: Center(
                                child: Text('السعر',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)))),
                        Expanded(
                            flex: 2,
                            child: Center(
                                child: Text('عدد الوحدات',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold)))),
                        SizedBox(width: 40),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // هنا يأتي ListView.builder كما هو مع نفس توزيع flex للأعمدة
                    // ... existing ListView.builder code ...
                  ],
                ),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _invoiceItems.length,
                  itemBuilder: (context, index) {
                    final item = _invoiceItems[index];
                    while (focusNodesList.length <= index) {
                      focusNodesList.add(LineItemFocusNodes());
                    }
                    return EditableInvoiceItemRow(
                      key: ValueKey(item.uniqueId),
                      item: item,
                      index: index,
                      allProducts: _allProductsForUnits ?? [],
                      isViewOnly: _isViewOnly,
                      isPlaceholder: item.productName.isEmpty,
                      onItemUpdated: (updatedItem) {
                        setState(() {
                          final i = _invoiceItems.indexWhere(
                              (it) => it.uniqueId == updatedItem.uniqueId);
                          if (i != -1) {
                            _invoiceItems[i] = updatedItem;
                          }
                          _recalculateTotals();
                          final lastIndex = _invoiceItems.length - 1;
                          if (i == lastIndex &&
                              _isInvoiceItemComplete(updatedItem)) {
                            _invoiceItems.add(InvoiceItem(
                                invoiceId: 0,
                                productName: '',
                                unit: '',
                                unitPrice: 0.0,
                                appliedPrice: 0.0,
                                itemTotal: 0.0,
                                uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}'));
                            focusNodesList.add(LineItemFocusNodes());
                            SchedulerBinding.instance.addPostFrameCallback((_) {
                              if (mounted && focusNodesList.isNotEmpty) {
                                focusNodesList.last.details.requestFocus();
                              }
                            });
                          }
                        });
                      },
                      onItemRemovedByUid: _removeInvoiceItemByUid,
                    );
                  },
                ),
                const SizedBox(height: 24.0),
                Builder(
                  builder: (context) {
                    final totalBeforeDiscount = _invoiceItems.fold(
                        0.0, (sum, item) => sum + item.itemTotal);
                    final total = totalBeforeDiscount - _discount;
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
                if (_isViewOnly)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'نوع الدفع: ${_invoiceToManage?.paymentType ?? 'غير محدد'}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (_invoiceToManage?.paymentType == 'دين' &&
                          widget.relatedDebtTransaction != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'أصبح الدين: ${widget.relatedDebtTransaction!.amountChanged.abs().toStringAsFixed(2)} دينار',
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
                        onChanged: _isViewOnly
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
                                    (_invoiceToManage?.isLocked ?? false)) {
                                  autoSaveSuspendedInvoice();
                                }
                              },
                      ),
                      const Text('نقد'),
                      const SizedBox(width: 24),
                      Radio<String>(
                        value: 'دين',
                        groupValue: _paymentType,
                        onChanged: _isViewOnly
                            ? null
                            : (value) {
                                setState(() {
                                  _paymentType = value!;
                                  _paidAmountController.text = '0';
                                  _autoSave();
                                });
                                if (_invoiceToManage != null &&
                                    _invoiceToManage!.status == 'معلقة' &&
                                    (_invoiceToManage?.isLocked ?? false)) {
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
                      enabled: !_isViewOnly && _paymentType == 'دين',
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
                            (_invoiceToManage?.isLocked ?? false)) {
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
                  onChanged: _isViewOnly
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
                              (_invoiceToManage?.isLocked ?? false)) {
                            autoSaveSuspendedInvoice();
                          }
                        },
                  initialValue: _discount > 0 ? _discount.toString() : '',
                  enabled: !_isViewOnly,
                ),
                const SizedBox(height: 24.0),
                if (!_isViewOnly)
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
                if (!_isViewOnly && !(_invoiceToManage?.isLocked ?? false)) ...[
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

class EditableInvoiceItemRow extends StatefulWidget {
  final InvoiceItem item;
  final int index;
  final Function(InvoiceItem) onItemUpdated;
  final Function(String) onItemRemovedByUid;
  final List<Product> allProducts;
  final bool isViewOnly;
  final bool isPlaceholder;
  final FocusNode? detailsFocusNode; // جديد: لقبول FocusNode لحقل التفاصيل
  final FocusNode? quantityFocusNode; // جديد: لطلب التركيز على العدد من الخارج
  final FocusNode? priceFocusNode; // جديد: لطلب التركيز على السعر من الخارج

  const EditableInvoiceItemRow({
    Key? key,
    required this.item,
    required this.index,
    required this.onItemUpdated,
    required this.onItemRemovedByUid,
    required this.allProducts,
    required this.isViewOnly,
    required this.isPlaceholder,
    this.detailsFocusNode,
    this.quantityFocusNode,
    this.priceFocusNode,
  }) : super(key: key);

  @override
  State<EditableInvoiceItemRow> createState() => _EditableInvoiceItemRowState();
}

class _EditableInvoiceItemRowState extends State<EditableInvoiceItemRow> {
  late InvoiceItem _currentItem;
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  late FocusNode _quantityFocusNode;
  late FocusNode _priceFocusNode;
  late FocusNode _detailsFocusNode;
  late FocusNode _saleTypeFocusNode;
  bool _openSaleTypeDropdown = false;
  bool _openPriceDropdown = false;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    // استخدم المتحكمات الجاهزة من كائن الصنف مباشرة
    _quantityController = TextEditingController(
      text: (widget.item.quantityIndividual ??
              widget.item.quantityLargeUnit ??
              '')
          .toString(),
    );
    _priceController = widget.item.appliedPriceController;
    _detailsFocusNode = widget.detailsFocusNode ?? FocusNode();
    _quantityFocusNode = widget.quantityFocusNode ?? FocusNode();
    _priceFocusNode = widget.priceFocusNode ?? FocusNode();
    _saleTypeFocusNode = FocusNode();
  }

  @override
  void dispose() {
    if (widget.detailsFocusNode == null) {
      _detailsFocusNode.dispose();
    }
    if (widget.quantityFocusNode == null) {
      _quantityFocusNode.dispose();
    }
    if (widget.priceFocusNode == null) {
      _priceFocusNode.dispose();
    }
    _saleTypeFocusNode.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String>> _getUnitOptions() {
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    List<String> options = ['قطعة'];
    if (product.unit == 'piece' &&
        product.unitHierarchy != null &&
        product.unitHierarchy!.isNotEmpty) {
      try {
        List<dynamic> hierarchy =
            json.decode(product.unitHierarchy!.replaceAll("'", '"'));
        options.addAll(
            hierarchy.map((e) => (e['unit_name'] ?? e['name']).toString()));
      } catch (e) {}
    } else if (product.unit == 'meter' && product.lengthPerUnit != null) {
      options = ['متر'];
      options.add('لفة');
    } else if (product.unit != 'piece' && product.unit != 'meter') {
      options = [product.unit];
    }
    // إزالة التكرار والقيم الفارغة
    options = options.where((e) => e != null && e.isNotEmpty).toSet().toList();
    // إذا كانت قيمة saleType غير موجودة أضفها
    if (_currentItem.saleType != null &&
        _currentItem.saleType!.isNotEmpty &&
        !options.contains(_currentItem.saleType)) {
      options.add(_currentItem.saleType!);
    }
    return options
        .map((unit) => DropdownMenuItem(
              value: unit,
              child: Text(unit, textAlign: TextAlign.center),
            ))
        .toList();
  }

  void _updateQuantity(String value) {
    double? newQuantity = double.tryParse(value);
    if (newQuantity == null || newQuantity <= 0) return;
    setState(() {
      // منطق موحد: دائماً المبلغ = السعر الحالي × العدد الحالي مباشرة
      _currentItem = _currentItem.copyWith(
        quantityIndividual:
            (_currentItem.saleType == 'قطعة' || _currentItem.saleType == 'متر')
                ? newQuantity
                : null,
        quantityLargeUnit:
            (_currentItem.saleType != 'قطعة' && _currentItem.saleType != 'متر')
                ? newQuantity
                : null,
        itemTotal: newQuantity * _currentItem.appliedPrice,
      );
      _priceController.text = _currentItem.appliedPrice.toStringAsFixed(2);
    });
    widget.onItemUpdated(_currentItem);
  }

  void _updateSaleType(String newType) {
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    double conversionFactor = 1.0;
    if (product != null) {
      if (product.unit == 'piece' && newType != 'قطعة') {
        if (product.unitHierarchy != null &&
            product.unitHierarchy!.isNotEmpty) {
          try {
            List<dynamic> hierarchy =
                json.decode(product.unitHierarchy!.replaceAll("'", '"'));
            for (var unit in hierarchy) {
              if ((unit['unit_name'] ?? unit['name']) == newType) {
                conversionFactor = unit['quantity'] is int
                    ? (unit['quantity'] as int).toDouble()
                    : double.tryParse(unit['quantity'].toString()) ?? 1.0;
                break;
              }
            }
          } catch (e) {}
        }
      } else if (product.unit == 'meter' && newType == 'لفة') {
        conversionFactor = product.lengthPerUnit ?? 1.0;
      }
    }
    setState(() {
      double newAppliedPrice;
      if ((product?.unit == 'piece' && newType != 'قطعة') ||
          (product?.unit == 'meter' && newType == 'لفة')) {
        // عند التحويل من قطعة إلى باكيت أو من متر إلى لفة: السعر للوحدة الكبيرة = السعر الحالي × عامل التحويل
        newAppliedPrice = _currentItem.appliedPrice * conversionFactor;
      } else if ((product?.unit == 'piece' &&
              _currentItem.saleType != 'قطعة' &&
              newType == 'قطعة') ||
          (product?.unit == 'meter' &&
              _currentItem.saleType == 'لفة' &&
              newType == 'متر')) {
        // عند التحويل من باكيت إلى قطعة أو من لفة إلى متر: السعر للوحدة الصغيرة = السعر الحالي ÷ عامل التحويل
        newAppliedPrice = _currentItem.appliedPrice / conversionFactor;
      } else {
        newAppliedPrice = _currentItem.appliedPrice;
      }
      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ??
          1;
      _currentItem = _currentItem.copyWith(
        saleType: newType,
        appliedPrice: newAppliedPrice,
        unitsInLargeUnit: conversionFactor != 1.0 ? conversionFactor : null,
        itemTotal: quantity * newAppliedPrice,
        quantityIndividual:
            (newType == 'قطعة' || newType == 'متر') ? quantity : null,
        quantityLargeUnit:
            (newType != 'قطعة' && newType != 'متر') ? quantity : null,
      );
      _quantityController.text = quantity.toString();
      _priceController.text =
          (newAppliedPrice > 0) ? newAppliedPrice.toString() : '';
      widget.onItemUpdated(_currentItem);
      // بعد اختيار نوع البيع، انتقل تلقائياً إلى السعر وافتح قائمة الأسعار
      FocusScope.of(context).requestFocus(_priceFocusNode);
      setState(() {
        _openPriceDropdown = true;
      });
    });
  }

  void _updatePrice(String value) {
    double? newPrice = double.tryParse(value);
    if (newPrice == null || newPrice < 0) return;
    setState(() {
      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ??
          1;
      // منطق السعر المخصص: إذا كان المستخدم أدخل سعراً يدوياً (غير مطابق لسعر الوحدة أو سعر التكلفة)
      bool isCustomPrice = true;
      double? costPrice = _currentItem.costPrice;
      double unitPrice = _currentItem.unitPrice;

      // تحقق من السعر المنخفض
      if ((costPrice != null && newPrice < costPrice) || newPrice < unitPrice) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('⚠️ السعر المدخل أقل من سعر التكلفة أو سعر الوحدة!'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        });
      }
      // الحساب: المبلغ = السعر * العدد مباشرة بغض النظر عن نوع الوحدة
      _currentItem = _currentItem.copyWith(
        appliedPrice: newPrice,
        itemTotal: quantity * newPrice,
      );
    });
    widget.onItemUpdated(_currentItem);
  }

  String formatCurrency(num value) {
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Row(
          children: [
            // رقم الصف
            Expanded(
                flex: 1,
                child: Text((widget.index + 1).toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium)),
            // المبلغ
            Expanded(
                flex: 2,
                child: widget.isViewOnly
                    ? Text(
                        widget.item.itemTotal.toStringAsFixed(2),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary),
                      )
                    : Text(formatCurrency(_currentItem.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary))),
            // التفاصيل (اسم المنتج)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(widget.item.productName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium)
                    : Autocomplete<String>(
                        initialValue:
                            TextEditingValue(text: widget.item.productName),
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<String>.empty();
                          }
                          return widget.allProducts.map((p) => p.name).where(
                              (option) =>
                                  option.contains(textEditingValue.text));
                        },
                        onSelected: (String selection) {
                          _currentItem =
                              _currentItem.copyWith(productName: selection);
                          widget.onItemUpdated(_currentItem);
                          FocusScope.of(context)
                              .requestFocus(_quantityFocusNode);
                        },
                        fieldViewBuilder: (context, textEditingController,
                            focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            enabled: !widget.isViewOnly,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 0, vertical: 8),
                              isDense: true,
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                            onChanged: (val) {
                              _currentItem =
                                  _currentItem.copyWith(productName: val);
                            },
                            onSubmitted: (val) {
                              onFieldSubmitted();
                              widget.onItemUpdated(_currentItem);
                              FocusScope.of(context)
                                  .requestFocus(_quantityFocusNode);
                            },
                          );
                        },
                      ),
              ),
            ),
            // العدد
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(
                        ((widget.item.quantityIndividual ??
                                    widget.item.quantityLargeUnit) ??
                                '')
                            .toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : TextFormField(
                        controller: _quantityController,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        enabled: !widget.isViewOnly,
                        onChanged: _updateQuantity, // الآن أصبح آمناً
                        focusNode: _quantityFocusNode,
                        onFieldSubmitted: (val) {
                          widget.onItemUpdated(_currentItem);
                          _saleTypeFocusNode.requestFocus();
                          setState(() {
                            _openSaleTypeDropdown = true;
                          });
                        },
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                          isDense: true,
                        ),
                      ),
              ),
            ),
            // نوع البيع
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(
                        widget.item.saleType ?? '',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _currentItem.saleType,
                          items: _getUnitOptions(),
                          onChanged: widget.isViewOnly
                              ? null
                              : (value) => _updateSaleType(value!),
                          isExpanded: true,
                          alignment: AlignmentDirectional.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                          itemHeight: 48,
                          autofocus: _openSaleTypeDropdown,
                          focusNode: _saleTypeFocusNode,
                          onTap: () {
                            setState(() {
                              _openSaleTypeDropdown = false;
                            });
                          },
                        ),
                      ),
              ),
            ),
            // السعر
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(
                        widget.item.appliedPrice.toStringAsFixed(2),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : TextFormField(
                        controller: _priceController,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        enabled: !widget.isViewOnly,
                        onChanged: _updatePrice, // الآن أصبح آمناً
                        focusNode: _priceFocusNode,
                        onFieldSubmitted: (val) {
                          widget.onItemUpdated(_currentItem);
                        },
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                          isDense: true,
                        ),
                      ),
              ),
            ),
            // عدد الوحدات
            Expanded(
              flex: 2,
              child: widget.isViewOnly
                  ? ((widget.item.saleType == 'قطعة' ||
                          widget.item.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          widget.item.unitsInLargeUnit?.toStringAsFixed(0) ??
                              '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium))
                  : (_currentItem.saleType == 'قطعة' ||
                          _currentItem.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          _currentItem.unitsInLargeUnit?.toStringAsFixed(0) ??
                              '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium),
            ),
            if (!widget.isViewOnly && !widget.isPlaceholder)
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 24),
                  onPressed: () =>
                      widget.onItemRemovedByUid(widget.item.uniqueId),
                  tooltip: 'حذف الصنف',
                ),
              )
            else
              const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}

// أضف دالة مساعدة للتحقق من اكتمال الصف
bool _isInvoiceItemComplete(InvoiceItem item) {
  return (item.productName.isNotEmpty &&
      (item.quantityIndividual != null || item.quantityLargeUnit != null) &&
      item.appliedPrice > 0 &&
      item.itemTotal > 0 &&
      (item.saleType != null && item.saleType!.isNotEmpty));
}

// إدارة FocusNode لكل صف
class LineItemFocusNodes {
  FocusNode details = FocusNode();
  FocusNode quantity = FocusNode();
  FocusNode price = FocusNode();
  void dispose() {
    details.dispose();
    quantity.dispose();
    price.dispose();
  }
}
