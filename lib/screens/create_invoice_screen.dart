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
import '../widgets/formatters.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/pdf_service.dart';
import 'package:alnaser/services/printing_service_platform_io.dart';
import 'package:get_storage/get_storage.dart';
import 'dart:convert';
import 'package:flutter/scheduler.dart';
import '../services/pdf_header.dart';
import '../models/invoice_adjustment.dart';

// Helper: format product ID - show raw value without zero-padding
String formatProductId5(int? id) {
  if (id == null) return '';
  return id.toString();
}

// تعريف EditableInvoiceItemRow موجود هنا (أو تأكد من وجوده قبل استخدامه في ListView)
// إذا كان التعريف موجود بالفعل، لا داعي لأي تعديل إضافي هنا.
// إذا لم يكن موجودًا، أضف الكود الذي تم إنشاؤه في الخطوة السابقة هنا.

class CreateInvoiceScreen extends StatefulWidget {
  final Invoice? existingInvoice;
  final bool isViewOnly;
  final DebtTransaction? relatedDebtTransaction;
  // إذا كانت غير null فهذا يعني فتح الشاشة بوضع تسوية لفاتورة محفوظة
  final Invoice? settlementForInvoice;

  const CreateInvoiceScreen({
    super.key,
    this.existingInvoice,
    this.isViewOnly = false,
    this.relatedDebtTransaction,
    this.settlementForInvoice,
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
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }

  // kept unused helper removed; global formatProductId5 is used instead

  List<Product> _searchResults = [];
  Product? _selectedProduct;
  List<InvoiceItem> _invoiceItems = [];

  final DatabaseService _db = DatabaseService();
  final TextEditingController _productIdController = TextEditingController();
  Product? _productIdSuggestion;
  PrinterDevice? _selectedPrinter;
  late final PrintingService _printingService;
  Invoice? _invoiceToManage;

  // إضافة متغيرات للحفظ التلقائي
  final _storage = GetStorage();
  bool _savedOrSuspended = false;
  Timer? _debounceTimer;

  

  bool _isViewOnly = false;

  // تسوية الفاتورة - حالة الواجهة
  bool _settlementPanelVisible = false; // عند اختيار "بند"
  bool _settlementIsDebit = true; // true = إضافة (debit), false = حذف (credit)
  final List<InvoiceItem> _settlementItems = [];
  String _settlementPaymentType = 'نقد';
  final TextEditingController _settleNameCtrl = TextEditingController();
  final TextEditingController _settleIdCtrl = TextEditingController();
  final TextEditingController _settleQtyCtrl = TextEditingController();
  final TextEditingController _settlePriceCtrl = TextEditingController();
  final TextEditingController _settleUnitCtrl = TextEditingController();
  Product? _settleSelectedProduct;
  String _settleSelectedSaleType = 'قطعة'; // نوع البيع المحدد في التسوية
  
  // Controllers للـ Autocomplete في لوحة التسوية
  TextEditingController? _settleIdController;
  TextEditingController? _settleNameController;
  
  // معلومات التسويات
  List<InvoiceAdjustment> _invoiceAdjustments = [];
  double _totalSettlementAmount = 0.0;
  
  // جلب معلومات التسويات
  Future<void> _loadSettlementInfo() async {
    if (_invoiceToManage?.id != null) {
      try {
        final adjustments = await _db.getInvoiceAdjustments(_invoiceToManage!.id!);
        setState(() {
          _invoiceAdjustments = adjustments;
          _totalSettlementAmount = adjustments.fold(0.0, (sum, adj) {
            return sum + (adj.type == 'debit' ? adj.amountDelta : -adj.amountDelta);
          });
        });
      } catch (e) {
        print('Error loading settlement info: $e');
      }
    }
  }

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

  void _handleChangeProductId(String value) {
    final v = value.trim();
    if (v.isEmpty) {
      setState(() {
        _productIdSuggestion = null;
      });
      return;
    }
    final id = int.tryParse(v);
    if (id == null) {
      setState(() {
        _productIdSuggestion = null;
      });
      return;
    }
    // بحث مباشر سريع
    _db.getProductById(id).then((p) {
      if (!mounted) return;
      setState(() {
        _productIdSuggestion = p;
      });
    });
  }

  Future<void> _handleSubmitProductId(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final id = int.tryParse(trimmed);
    if (id == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال ID صحيح')));
      return;
    }
    final product = await _db.getProductById(id);
    if (product == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لم يتم العثور على صنف بهذا المعرّف')));
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _productIdController.clear();

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
    newPriceLevel ??= product.unitPrice;

    // لا نضيف مباشرة. نختار المنتج ونظهر خيارات الوحدة والكمية
    setState(() {
      _selectedProduct = product;
      _selectedPriceLevel = newPriceLevel;
      _quantityController.clear();
      _productIdSuggestion = null;
      _quantityAutofocus = true;
    });
  }

  @override
  void initState() {
    super.initState();
    try {
      _printingService = getPlatformPrintingService();
      _invoiceToManage = widget.existingInvoice;
      _isViewOnly = widget.isViewOnly;
      // تفعيل وضع التسوية: افتح واجهة إدخال أصناف جديدة، لكن اربطها بالفاتورة الأساسية
      if (widget.settlementForInvoice != null) {
        // في وضع التسوية: اجعل الشاشة قابلة للإدخال، ولا تعدّل الأصناف الأصلية
        _isViewOnly = false;
        _invoiceToManage = widget.settlementForInvoice; // للربط ولأخذ العميل/التاريخ إن لزم
        // نظف أي بيانات إدخال قديمة وابدأ بقائمة فارغة لتسوية جديدة
        _invoiceItems.clear();
        _totalAmountController.text = '0';
        // أضف صف فارغ كبداية
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
      _loadingFeeController = TextEditingController();
      _loadAutoSavedData();
      _loadSettlementInfo(); // جلب معلومات التسويات
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
      _discountController.addListener(_onDiscountChanged);

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
        
        // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
        if (_invoiceToManage != null && _paymentType == 'نقد' && !_isViewOnly) {
          final newTotal = _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal) - _discount;
          _paidAmountController.text = formatNumber(newTotal);
        }
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

  // معالج تغيير الخصم
  void _onDiscountChanged() {
    try {
      final discountText = _discountController.text.replaceAll(',', '');
      final newDiscount = double.tryParse(discountText) ?? 0.0;
      _discount = newDiscount;
      
      // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
      if (_invoiceToManage != null && _paymentType == 'نقد' && !_isViewOnly) {
        final currentTotalAmount = _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final newTotal = currentTotalAmount - _discount;
        _paidAmountController.text = formatNumber(newTotal);
      }
    } catch (e) {
      print('Error in onDiscountChanged: $e');
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
      _discountController.removeListener(_onDiscountChanged);

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
      
      _quantityFocusNode.dispose(); // تنظيف FocusNode
      _searchFocusNode.dispose();
      _loadingFeeController.dispose();
      _productIdController.dispose();
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

  /// دالة البحث عن المنتجات - تستخدم خوارزمية البحث الذكية المتعددة الطبقات
  /// تدعم البحث عن "كوب فنار" لإيجاد "كوب واحد سيه فنار"، "كوب اثنين سيات فنار"، إلخ
  Future<void> _searchProducts(String query) async {
    try {
      if (query.isEmpty) {
        setState(() {
          _searchResults = [];
        });
        return;
      }
      // استخدام البحث الذكي المخصص لشاشة إنشاء الفاتورة
      // يدعم البحث عن الكلمات في ترتيب مختلف والكلمات الوسيطة
      final results = await _db.searchProductsSmart(query);
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
            formatNumber(total.clamp(0, double.infinity));
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
        _discountController.text = formatNumber(_discount);
      }
      if (_discount < 0) {
        _discount = 0.0;
        _discountController.text = formatNumber(0);
      }
      
      // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً عند تغيير الخصم
      if (_invoiceToManage != null && _paymentType == 'نقد' && !_isViewOnly) {
        final newTotal = currentTotalAmount - _discount;
        _paidAmountController.text = formatNumber(newTotal);
      }
    } catch (e) {
      print('Error in guardDiscount: $e');
    }
  }

  // --- دالة حساب التكلفة الفعلية بناءً على نوع الوحدة المباعة ---
  double _calculateActualCostPrice(Product product, String saleUnit, double quantity) {
    // إذا كانت الوحدة المباعة هي القطعة الواحدة، استخدم تكلفة القطعة
    if (saleUnit == 'قطعة' || saleUnit == 'متر') {
      return product.costPrice ?? 0.0;
    }
    
    // إذا كانت الوحدة المباعة أكبر، احسب التكلفة من النظام الهيراركي
    if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
      try {
        final hierarchy = jsonDecode(product.unitHierarchy!) as List;
        final unitCosts = product.getUnitCostsMap();
        
        // البحث عن الوحدة المباعة في النظام الهيراركي
        for (var unit in hierarchy) {
          if (unit['unit_name'] == saleUnit) {
            // إذا وجدت التكلفة محسوبة مسبقاً، استخدمها
            if (unitCosts.containsKey(saleUnit)) {
              return unitCosts[saleUnit]!;
            }
            
            // إذا لم تكن محسوبة، احسبها الآن
            double currentCost = product.costPrice ?? 0.0;
            for (var hUnit in hierarchy) {
              if (hUnit['unit_name'] == saleUnit) {
                break; // توقف عند الوحدة المطلوبة
              }
              currentCost = currentCost * (hUnit['quantity'] as num);
            }
            return currentCost;
          }
        }
      } catch (e) {
        print('خطأ في حساب التكلفة الهيراركية: $e');
      }
    }
    
    // إذا لم يتم العثور على تكلفة هيراركية، استخدم تكلفة القطعة
    return product.costPrice ?? 0.0;
  }

  void _addInvoiceItem() {
    try {
      if (_formKey.currentState!.validate() &&
          _selectedProduct != null &&
          _selectedPriceLevel != null) {
        final double inputQuantity =
            double.tryParse(_quantityController.text.trim().replaceAll(',', '')) ?? 0.0;
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
        
        // حساب التكلفة الفعلية بناءً على نوع الوحدة المباعة
        final actualCostPrice = _calculateActualCostPrice(_selectedProduct!, _selectedUnitForItem, inputQuantity);
        
        final newItem = InvoiceItem(
          invoiceId: 0,
          productName: _selectedProduct!.name,
          unit: _selectedProduct!.unit,
          unitPrice: _selectedProduct!.unitPrice,
          costPrice: finalItemCostPrice,
          actualCostPrice: actualCostPrice, // التكلفة الفعلية المحسوبة
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
          
          // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
          if (_invoiceToManage != null && _paymentType == 'نقد' && !_isViewOnly) {
            final newTotal = _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal) - _discount;
            _paidAmountController.text = formatNumber(newTotal);
          }
          
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
        
        // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
        if (_invoiceToManage != null && _paymentType == 'نقد' && !_isViewOnly) {
          final newTotal = _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal) - _discount;
          _paidAmountController.text = formatNumber(newTotal);
        }
        
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
    
    // حفظ حالة "فاتورة جديدة" قبل أي عمليات أخرى
    final bool isNewInvoice = _invoiceToManage == null;
    
    print('=== بداية حفظ الفاتورة ===');
    print('هل فاتورة جديدة: $isNewInvoice');
    print('معرف الفاتورة الحالية: ${_invoiceToManage?.id}');
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
      double totalAmount = currentTotalAmount - _discount;
      
      // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
      double paid = double.tryParse(_paidAmountController.text.replaceAll(',', '')) ?? 0.0;
      if (_invoiceToManage != null && _paymentType == 'نقد') {
        paid = totalAmount; // للفواتير النقدية المعدلة، المبلغ المدفوع = الإجمالي الجديد
        _paidAmountController.text = formatNumber(paid);
      }
      
      double debt = totalAmount - paid;
      
      print('=== معلومات الفاتورة ===');
      print('نوع الدفع: $_paymentType');
      print('إجمالي الفاتورة: $totalAmount');
      print('المبلغ المدفوع: $paid');
      print('المبلغ المتبقي (الدين): $debt');
      print('اسم العميل: ${customer?.name}');
      print('معرف العميل: ${customer?.id}');
      print('الدين الحالي للعميل: ${customer?.currentTotalDebt}');
      print('=== نهاية معلومات الفاتورة ===');

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
              false;
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
          if (_isInvoiceItemComplete(item)) {
            // البحث عن المنتج لجلب التكلفة الفعلية
            final products = await _db.getAllProducts();
            final matchedProduct = products.firstWhere(
              (p) => p.name == item.productName,
              orElse: () => Product(
                name: '',
                unit: '',
                unitPrice: 0.0,
                price1: 0.0,
                createdAt: DateTime.now(),
                lastModifiedAt: DateTime.now(),
              ),
            );
            
            // حساب التكلفة الفعلية بناءً على نوع الوحدة المباعة
            final actualCostPrice = _calculateActualCostPrice(matchedProduct, item.saleType ?? 'قطعة', item.quantityIndividual ?? item.quantityLargeUnit ?? 0);
            
            // إنشاء عنصر فاتورة مع التكلفة الفعلية المحسوبة
            final invoiceItem = item.copyWith(
              invoiceId: invoiceId,
              actualCostPrice: actualCostPrice, // التكلفة الفعلية المحسوبة
            );
            
            await _db.insertInvoiceItem(invoiceItem);
          }
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
          if (_isInvoiceItemComplete(item)) {
            // البحث عن المنتج لجلب التكلفة الفعلية
            final products = await _db.getAllProducts();
            final matchedProduct = products.firstWhere(
              (p) => p.name == item.productName,
              orElse: () => Product(
                name: '',
                unit: '',
                unitPrice: 0.0,
                price1: 0.0,
                createdAt: DateTime.now(),
                lastModifiedAt: DateTime.now(),
              ),
            );
            
            // حساب التكلفة الفعلية بناءً على نوع الوحدة المباعة
            final actualCostPrice = _calculateActualCostPrice(matchedProduct, item.saleType ?? 'قطعة', item.quantityIndividual ?? item.quantityLargeUnit ?? 0);
            
            // إنشاء عنصر فاتورة مع التكلفة الفعلية المحسوبة
            final invoiceItem = item.copyWith(
              invoiceId: invoiceId,
              actualCostPrice: actualCostPrice, // التكلفة الفعلية المحسوبة
            );
            
            await _db.insertInvoiceItem(invoiceItem);
          }
        }
        print(
            'Inserted new invoice. Invoice ID: $invoiceId, Status: ${invoice.status}');
      }

      // تحديث الديون بناءً على نوع العملية
      if (customer != null) {
        
        print('=== بداية منطق تحديث الديون ===');
        print('نوع الدفع: $_paymentType');
        print('هل فاتورة جديدة: $isNewInvoice');
        print('المبلغ المتبقي (debt): $debt');
        
        double debtChange = 0.0;
        String transactionDescription = '';
        
        if (!isNewInvoice) {
          // تعديل فاتورة موجودة - حساب الفرق
          final oldTotal = _invoiceToManage!.totalAmount;
          final newTotal = totalAmount;
          final oldPaid = _invoiceToManage!.amountPaidOnInvoice;
          final newPaid = paid;
          
          if (_paymentType == 'نقد') {
            // للفواتير النقدية: المبلغ المدفوع يجب أن يساوي الإجمالي الجديد
            debtChange = newTotal - oldTotal;
            if (debtChange != 0) {
              transactionDescription = debtChange > 0 
                  ? 'تعديل فاتورة نقدية رقم $invoiceId - إضافة ${debtChange.abs().toStringAsFixed(2)} دينار'
                  : 'تعديل فاتورة نقدية رقم $invoiceId - خصم ${debtChange.abs().toStringAsFixed(2)} دينار';
            }
          } else {
            // للفواتير بالدين: حساب الفرق في المبلغ المتبقي
            final oldRemaining = oldTotal - oldPaid;
            final newRemaining = newTotal - newPaid;
            debtChange = newRemaining - oldRemaining;
            
            if (debtChange != 0) {
              transactionDescription = debtChange > 0 
                  ? 'تعديل فاتورة رقم $invoiceId - إضافة ${debtChange.abs().toStringAsFixed(2)} دينار'
                  : 'تعديل فاتورة رقم $invoiceId - خصم ${debtChange.abs().toStringAsFixed(2)} دينار';
            }
          }
        } else {
          // فاتورة جديدة
          print('=== فاتورة جديدة ===');
          print('نوع الدفع: $_paymentType');
          print('المبلغ المتبقي (debt): $debt');
          
          if (_paymentType == 'دين') {
            print('دخول منطق الفاتورة الجديدة بالدين');
            debtChange = debt; // احفظ الدين حتى لو كان صفر أو سالب
            transactionDescription = debt > 0 
                ? 'دين فاتورة رقم $invoiceId'
                : debt < 0 
                    ? 'دفعة زائدة لفاتورة رقم $invoiceId'
                    : 'فاتورة رقم $invoiceId - مدفوعة بالكامل';
            
            print('=== فاتورة جديدة بالدين ===');
            print('المبلغ المتبقي (debt): $debt');
            print('تغيير الدين (debtChange): $debtChange');
            print('وصف المعاملة: $transactionDescription');
            print('=== نهاية فاتورة جديدة بالدين ===');
          } else {
            print('فاتورة جديدة نقدية - لا يتم حفظ دين');
          }
          print('=== نهاية فاتورة جديدة ===');
        }
        
        print('=== فحص شرط حفظ الدين ===');
        print('نوع الدفع: $_paymentType');
        print('هل العميل موجود: ${customer != null}');
        print('معرف العميل: ${customer?.id}');
        print('تغيير الدين: $debtChange');
        print('هل فاتورة جديدة: $isNewInvoice');
        print('هل سيتم حفظ معاملة الدين: ${_paymentType == 'دين' && customer != null && debtChange != 0}');
        print('=== نهاية فحص شرط حفظ الدين ===');
        
        // للفواتير بالدين: احفظ معاملة الدين فقط إذا كان هناك تغيير
        if (_paymentType == 'دين' && customer != null && debtChange != 0) {
          print('=== حفظ معاملة الدين ===');
          print('نوع الدفع: $_paymentType');
          print('تغيير الدين: $debtChange');
          print('وصف المعاملة: $transactionDescription');
          print('الدين السابق: ${customer.currentTotalDebt}');
          print('الدين الجديد: ${customer.currentTotalDebt + debtChange}');
          print('معرف العميل: ${customer.id}');
          print('معرف الفاتورة: $invoiceId');
          
          final updatedCustomer = customer.copyWith(
            currentTotalDebt: (customer.currentTotalDebt) + debtChange,
            lastModifiedAt: DateTime.now(),
          );
          await _db.updateCustomer(updatedCustomer);

          final debtTransaction = DebtTransaction(
            id: null,
            customerId: customer.id!,
            amountChanged: debtChange,
            transactionType: _invoiceToManage != null ? 'invoice_edit' : 'invoice_debt',
            description: transactionDescription,
            newBalanceAfterTransaction: updatedCustomer.currentTotalDebt,
            invoiceId: invoiceId,
          );
          await _db.insertDebtTransaction(debtTransaction);
          print('تم حفظ معاملة الدين بنجاح');
          print('تم تحديث دين العميل إلى: ${updatedCustomer.currentTotalDebt}');
          print('=== نهاية حفظ معاملة الدين ===');
        } else {
          print('=== لم يتم حفظ معاملة الدين ===');
          print('السبب: ${_paymentType != 'دين' ? 'نوع الدفع ليس دين' : customer == null ? 'العميل غير موجود' : 'تغيير الدين = 0'}');
          print('=== نهاية عدم حفظ معاملة الدين ===');
        }
      }

      String extraMsg = '';
      if (_invoiceToManage != null) {
        // تعديل فاتورة موجودة - رسالة فقط (لا نحفظ معاملة هنا)
        if (customer != null) {
          final oldTotal = _invoiceToManage!.totalAmount;
          final newTotal = totalAmount;
          final oldPaid = _invoiceToManage!.amountPaidOnInvoice;
          final newPaid = paid;
          
          if (_paymentType == 'نقد') {
            // للفواتير النقدية
            final debtChange = newTotal - oldTotal;
            if (debtChange != 0) {
              extraMsg = debtChange > 0 
                  ? '\nتم إضافة ${debtChange.abs().toStringAsFixed(2)} دينار إلى حساب العميل (فاتورة نقدية)'
                  : '\nتم خصم ${debtChange.abs().toStringAsFixed(2)} دينار من حساب العميل (فاتورة نقدية)';
            } else {
              extraMsg = '\nلم يتغير المبلغ (فاتورة نقدية)';
            }
          } else {
            // للفواتير بالدين - رسالة فقط (المعاملة تم حفظها أعلاه)
            final oldRemaining = oldTotal - oldPaid;
            final newRemaining = newTotal - newPaid;
            final debtChange = newRemaining - oldRemaining;
            
            if (debtChange != 0) {
              extraMsg = debtChange > 0 
                  ? '\nتم إضافة ${debtChange.abs().toStringAsFixed(2)} دينار إلى حساب العميل'
                  : '\nتم خصم ${debtChange.abs().toStringAsFixed(2)} دينار من حساب العميل';
            } else {
              extraMsg = '\nلم يتغير المبلغ المتبقي';
            }
          }
        }
      } else if (_paymentType == 'دين') {
        // فاتورة جديدة - رسالة فقط (المعاملة تم حفظها أعلاه)
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
        final actionText = _invoiceToManage != null ? 'تم تعديل الفاتورة بنجاح' : 'تم حفظ الفاتورة بنجاح';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$actionText$extraMsg'),
            backgroundColor: Colors.green,
          ),
        );
        
        if (_invoiceToManage == null) {
          // العودة للصفحة الرئيسية فقط للفواتير الجديدة
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          // للفواتير المعدلة، البقاء في نفس الصفحة مع تفعيل وضع العرض
          setState(() {
            _isViewOnly = true;
          });
        }
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
          await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));

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

      // تصفية العناصر لإزالة الصفوف الفارغة قبل الطباعة
      final filteredItems = _invoiceItems.where((item) => _isInvoiceItemComplete(item)).toList();

      final itemsTotal =
          filteredItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final discount = _discount;
      // جلب تسويات الفاتورة (إن وجدت) وحساب إجماليها
      List<InvoiceAdjustment> adjs = [];
      double settlementsTotal = 0.0;
      if (_invoiceToManage != null && _invoiceToManage!.id != null) {
        try {
          adjs = await _db.getInvoiceAdjustments(_invoiceToManage!.id!);
          settlementsTotal = adjs.fold(0.0, (sum, a) => sum + a.amountDelta);
        } catch (_) {}
      }
      final bool hasAdjustments = adjs.isNotEmpty;
      // تحديد تسويات البنود المضافة في نفس يوم الفاتورة لعرضها ضمن القائمة
      final DateTime invoiceDateOnly = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final List<InvoiceAdjustment> sameDayAddedItemAdjs = adjs.where((a) {
        if (a.productId == null) return false;
        if (a.type != 'debit') return false;
        final d = DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day);
        return d == invoiceDateOnly;
      }).toList();
      final List<InvoiceAdjustment> itemAdditionsForSection = adjs.where((a) => a.productId != null && a.type == 'debit' && !sameDayAddedItemAdjs.contains(a)).toList();
      final List<InvoiceAdjustment> itemCreditsForSection = adjs.where((a) => a.productId != null && a.type == 'credit').toList();
      final List<InvoiceAdjustment> amountOnlyAdjs = adjs.where((a) => a.productId == null).toList();
      final bool showSettlementSections = itemAdditionsForSection.isNotEmpty || itemCreditsForSection.isNotEmpty || amountOnlyAdjs.isNotEmpty || sameDayAddedItemAdjs.isNotEmpty;
      
      print('=== DEBUG SETTLEMENT SECTIONS ===');
      print('DEBUG: itemAdditionsForSection.length = ${itemAdditionsForSection.length}');
      print('DEBUG: itemCreditsForSection.length = ${itemCreditsForSection.length}');
      print('DEBUG: amountOnlyAdjs.length = ${amountOnlyAdjs.length}');
      print('DEBUG: sameDayAddedItemAdjs.length = ${sameDayAddedItemAdjs.length}');
      print('DEBUG: showSettlementSections = $showSettlementSections');
      print('=== END DEBUG SETTLEMENT SECTIONS ===');
      final bool includeSameDayOnlyCase = sameDayAddedItemAdjs.isNotEmpty && !showSettlementSections;

      // حساب الإجماليات المعروضة بحسب الحالة الخاصة
      final double sameDayAddsTotal = sameDayAddedItemAdjs.fold(0.0, (sum, a) {
        // للتسويات البنود: احسب من price * quantity
        final double price = a.price ?? 0.0;
        final double quantity = a.quantity ?? 0.0;
        return sum + (price * quantity);
      });
      final double itemsTotalForDisplay = includeSameDayOnlyCase ? (itemsTotal + sameDayAddsTotal) : itemsTotal;
      final double settlementsTotalForDisplay = includeSameDayOnlyCase ? 0.0 : settlementsTotal;
      final double preDiscountTotal = (itemsTotalForDisplay + settlementsTotalForDisplay);
      final double afterDiscount = ((preDiscountTotal - discount).clamp(0.0, double.infinity)).toDouble();
      
      // المبلغ المدفوع من الحقل
      final double paid = double.tryParse(_paidAmountController.text.replaceAll(',', '')) ?? 0.0;
      final isCash = _paymentType == 'نقد';
      

      // تحديد مبالغ التسويات النقدية/الدين لحساب المبلغ المدفوع المعروض
      final double cashSettlements = showSettlementSections
          ? [...adjs, ...sameDayAddedItemAdjs].where((a) => a.settlementPaymentType == 'نقد').fold(0.0, (sum, a) {
              // للتسويات البنود: احسب من price * quantity
              if (a.productId != null) {
                final double price = a.price ?? 0.0;
                final double quantity = a.quantity ?? 0.0;
                return sum + (price * quantity);
              } else {
                // للتسويات المبلغ: استخدم amountDelta
                return sum + a.amountDelta;
              }
            })
          : 0.0;
      final double debtSettlements = showSettlementSections
          ? [...adjs, ...sameDayAddedItemAdjs].where((a) => a.settlementPaymentType == 'دين').fold(0.0, (sum, a) {
              // للتسويات البنود: احسب من price * quantity
              if (a.productId != null) {
                final double price = a.price ?? 0.0;
                final double quantity = a.quantity ?? 0.0;
                return sum + (price * quantity);
              } else {
                // للتسويات المبلغ: استخدم amountDelta
                return sum + a.amountDelta;
              }
            })
          : 0.0;
      
      // تشخيص للمشكلة
      print('=== DEBUG PDF SETTLEMENTS ===');
      print('DEBUG PDF: paid = $paid');
      print('DEBUG PDF: cashSettlements = $cashSettlements');
      print('DEBUG PDF: debtSettlements = $debtSettlements');
      print('DEBUG PDF: showSettlementSections = $showSettlementSections');
      print('DEBUG PDF: adjs.length = ${adjs.length}');
      for (int i = 0; i < adjs.length; i++) {
        final adj = adjs[i];
        print('DEBUG PDF: adj[$i] = {');
        print('  productId: ${adj.productId}');
        print('  productName: ${adj.productName}');
        print('  type: ${adj.type}');
        print('  amountDelta: ${adj.amountDelta}');
        print('  settlementPaymentType: ${adj.settlementPaymentType}');
        print('  price: ${adj.price}');
        print('  quantity: ${adj.quantity}');
        print('  createdAt: ${adj.createdAt}');
        print('}');
      }
      print('=== END DEBUG PDF SETTLEMENTS ===');
      
      double displayedPaidForSettlementsCase;
      if (isCash && !showSettlementSections) {
        // للفواتير النقدية بدون تسويات: المبلغ المدفوع يجب أن يساوي الإجمالي دائماً
        displayedPaidForSettlementsCase = afterDiscount;
      } else {
        // للفواتير بالدين أو الفواتير النقدية مع تسويات: إضافة التسويات النقدية إلى المبلغ المدفوع الأصلي
        displayedPaidForSettlementsCase = paid + cashSettlements;
      }

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
      
      // حساب المبلغ المتبقي والدين الحالي
      final double remainingForPdf;
      if (isCash && !showSettlementSections) {
        // للفواتير النقدية بدون تسويات: المبلغ المتبقي دائماً صفر
        remainingForPdf = 0;
      } else {
        // للفواتير بالدين أو الفواتير النقدية مع تسويات: احسب المتبقي من الإجمالي ناقص المبلغ المدفوع (بما في ذلك التسويات النقدية)
        remainingForPdf = afterDiscount - displayedPaidForSettlementsCase;
      }
      
      // حساب الدين الحالي بناءً على التسويات
      if (showSettlementSections) {
        // إذا كانت هناك تسويات، احسب الدين بناءً على التسويات الدينية
        currentDebt = previousDebt + debtSettlements;
      } else {
        // إذا لم تكن هناك تسويات، احسب الدين بناءً على نوع الدفع الأصلي
      if (isCash) {
        currentDebt = previousDebt;
      } else {
          currentDebt = previousDebt + remainingForPdf;
        }
      }

      // للفواتير المحفوظة: إزالة "الدين السابق" من العرض
      final bool isSavedInvoice = _invoiceToManage?.id != null;
      final double previousDebtForPdf = 0.0; // إزالة عرض الدين السابق
      final double currentDebtForPdf = currentDebt;

      int invoiceId;
      if (_invoiceToManage != null && _invoiceToManage!.id != null) {
        invoiceId = _invoiceToManage!.id!;
      } else {
        invoiceId = (await _db.getLastInvoiceId()) + 1;
      }
      
      // دمج بنود التسوية المضافة بنفس اليوم داخل جدول العناصر الرئيسي عند كونها الحالة الوحيدة
      final List<Map<String, dynamic>> combinedRows = [
        // صفوف الفاتورة الأصلية
        ...filteredItems.map((it) => {
              'type': 'item',
              'item': it,
            }),
        // صفوف التسوية المضافة بنفس اليوم (إن كانت الحالة الوحيدة)
        if (includeSameDayOnlyCase)
          ...sameDayAddedItemAdjs.map((a) => {
                'type': 'adj',
                'adj': a,
              }),
      ];
      
      const itemsPerPage = 20;
      final totalPages = (combinedRows.length / itemsPerPage).ceil().clamp(1, double.infinity).toInt();
      bool printedSummaryInLastPage = false;

      for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
        final start = pageIndex * itemsPerPage;
        final end = (start + itemsPerPage) > combinedRows.length
            ? combinedRows.length
            : start + itemsPerPage;
        final pageRows = combinedRows.sublist(start, end);

        final bool isLast = pageIndex == totalPages - 1;
        final bool deferSummary = isLast && (pageRows.length >= 18) && showSettlementSections;

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
                        5: const pw.FixedColumnWidth(45), // ID (خمسة محارف)
                        6: const pw.FixedColumnWidth(20), // ت
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
                            _headerCell('ID', font),
                            _headerCell('ت', font),
                          ],
                        ),
                        ...pageRows.asMap().entries.map((entry) {
                          final index = entry.key + (pageIndex * itemsPerPage);
                          final row = entry.value;
                          if (row['type'] == 'item') {
                            final item = row['item'] as InvoiceItem;
                            final quantity = (item.quantityIndividual ?? item.quantityLargeUnit ?? 0.0);
                          Product? product;
                          try {
                              product = allProducts.firstWhere((p) => p.name == item.productName);
                          } catch (e) {
                            product = null;
                          }
                          final idText = formatProductId5(product?.id);
                          return pw.TableRow(
                            children: [
                                _dataCell(formatNumber(item.itemTotal, forceDecimal: true), font),
                                _dataCell(formatNumber(item.appliedPrice, forceDecimal: true), font),
                              _dataCell(
                                buildUnitConversionStringForPdf(item, product),
                                font,
                              ),
                                _dataCell('${formatNumber(quantity, forceDecimal: true)} ${item.saleType ?? ''}', font),
                                _dataCell(item.productName, font, align: pw.TextAlign.right),
                              _dataCell(idText, font),
                              _dataCell('${index + 1}', font),
                            ],
                          );
                          } else {
                            final a = row['adj'] as InvoiceAdjustment;
                            final double price = a.price ?? 0.0;
                            final double qty = a.quantity ?? 0.0;
                            final double total = a.amountDelta != 0.0 ? a.amountDelta : (price * qty);
                            Product? product;
                            try {
                              product = allProducts.firstWhere((p) => p.id == a.productId);
                            } catch (e) {
                              product = null;
                            }
                            final idText = formatProductId5(product?.id);
                            final unitConv = () {
                              // بناء سلسلة التحويل للوحدة للتسوية
                              try {
                                if (product == null || product.unitHierarchy == null || product.unitHierarchy!.isEmpty) {
                                  return (a.unitsInLargeUnit?.toString() ?? '');
                                }
                                final List<dynamic> hierarchy = json.decode(product.unitHierarchy!.replaceAll("'", '"'));
                                List<String> factors = [];
                                for (int i = 0; i < hierarchy.length; i++) {
                                  final unitName = hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
                                  final quantity = hierarchy[i]['quantity'];
                                  factors.add(quantity.toString());
                                  if (unitName == a.saleType) {
                                    break;
                                  }
                                }
                                if (factors.isEmpty) {
                                  return a.unitsInLargeUnit?.toString() ?? '';
                                }
                                return factors.join(' × ');
                              } catch (_) {
                                return a.unitsInLargeUnit?.toString() ?? '';
                              }
                            }();
                            return pw.TableRow(
                              children: [
                                _dataCell(formatNumber(total, forceDecimal: true), font),
                                _dataCell(formatNumber(price, forceDecimal: true), font),
                                _dataCell(unitConv, font),
                                _dataCell('${formatNumber(qty, forceDecimal: true)} ${a.saleType ?? ''}', font),
                                _dataCell(a.productName ?? '-', font, align: pw.TextAlign.right),
                                _dataCell(idText, font),
                                _dataCell('${index + 1}', font),
                              ],
                            );
                          }
                        }).toList(),
                      ],
                    ),
                    pw.Divider(height: 4, thickness: 0.4),

                    // --- بنود تسوية مضافة في نفس اليوم (تظهر ضمن القائمة) ---
                    if (sameDayAddedItemAdjs.isNotEmpty && !includeSameDayOnlyCase) ...[
                      pw.SizedBox(height: 4),
                      pw.Table(
                        border: pw.TableBorder.all(width: 0.2),
                        columnWidths: {
                          0: const pw.FixedColumnWidth(90), // المبلغ
                          1: const pw.FixedColumnWidth(70), // السعر
                          2: const pw.FixedColumnWidth(65), // عدد الوحدات
                          3: const pw.FixedColumnWidth(90), // العدد
                          4: const pw.FlexColumnWidth(0.8), // التفاصيل
                          5: const pw.FixedColumnWidth(45), // ID
                          6: const pw.FixedColumnWidth(20), // ت
                        },
                        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                        children: [
                          pw.TableRow(children: [
                            _headerCell('المبلغ', font),
                            _headerCell('السعر', font),
                            _headerCell('عدد الوحدات', font),
                            _headerCell('العدد', font),
                            _headerCell('التفاصيل', font),
                            _headerCell('ID', font),
                            _headerCell('ت', font),
                          ]),
                          ...sameDayAddedItemAdjs.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final a = entry.value;
                            final qty = a.quantity ?? 0;
                            final price = a.price ?? 0;
                            final amount = price * qty;
                            final idText = formatProductId5(a.productId);
                            return pw.TableRow(children: [
                              _dataCell(formatNumber(amount, forceDecimal: true), font),
                              _dataCell(formatNumber(price, forceDecimal: true), font),
                              _dataCell((a.unitsInLargeUnit != null && a.unitsInLargeUnit! > 0) ? a.unitsInLargeUnit!.toStringAsFixed(2) : '-', font),
                              _dataCell(qty.toStringAsFixed(2), font),
                              _dataCell(a.productName ?? '', font, align: pw.TextAlign.right),
                              _dataCell(idText, font),
                              _dataCell('${idx + 1}', font),
                            ]);
                          })
                        ],
                      ),
                      pw.SizedBox(height: 6),
                    ],

                    // --- المجاميع والتسويات في الصفحة الأخيرة فقط (إلا إذا أُجّلت) ---
                    if (isLast && !deferSummary) ...[
                      // --- طباعة التسويات ---
                      if (_invoiceToManage != null && _invoiceToManage!.id != null && (itemAdditionsForSection.isNotEmpty || itemCreditsForSection.isNotEmpty || amountOnlyAdjs.isNotEmpty)) ...[
                        pw.SizedBox(height: 6),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('التعديلات', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                            pw.Text('التاريخ والوقت: ${DateTime.now().year}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().day.toString().padLeft(2, '0')} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}', style: pw.TextStyle(font: font, fontSize: 10)),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        // تسويات البنود (إضافة)
                        if (itemAdditionsForSection.isNotEmpty) ...[
                          pw.Text('تسوية البنود - إضافة', style: pw.TextStyle(font: font, fontSize: 12)),
                          pw.SizedBox(height: 2),
                          pw.Table(
                            border: pw.TableBorder.all(width: 0.2),
                            columnWidths: {
                              0: const pw.FixedColumnWidth(90), // المبلغ
                              1: const pw.FixedColumnWidth(70), // السعر
                              2: const pw.FixedColumnWidth(65), // عدد الوحدات
                              3: const pw.FixedColumnWidth(90), // العدد
                              4: const pw.FlexColumnWidth(0.8), // التفاصيل
                              5: const pw.FixedColumnWidth(45), // ID
                              6: const pw.FixedColumnWidth(20), // ت
                            },
                            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                            children: [
                              pw.TableRow(children: [
                                _headerCell('المبلغ', font),
                                _headerCell('السعر', font),
                                _headerCell('عدد الوحدات', font),
                                _headerCell('العدد', font),
                                _headerCell('التفاصيل', font),
                                _headerCell('ID', font),
                                _headerCell('ت', font),
                              ]),
                              ...itemAdditionsForSection.toList().asMap().entries.map((entry) {
                                final idx = entry.key;
                                final a = entry.value;
                                final qty = a.quantity ?? 0;
                                final price = a.price ?? 0;
                                final amount = price * qty;
                                final idText = formatProductId5(a.productId);
                                return pw.TableRow(children: [
                                  _dataCell(formatNumber(amount, forceDecimal: true), font),
                                  _dataCell(formatNumber(price, forceDecimal: true), font),
                                  _dataCell((a.unitsInLargeUnit != null && a.unitsInLargeUnit! > 0) ? a.unitsInLargeUnit!.toStringAsFixed(2) : '-', font),
                                  _dataCell(qty.toStringAsFixed(2), font),
                                  _dataCell(a.productName ?? '', font, align: pw.TextAlign.right),
                                  _dataCell(idText, font),
                                  _dataCell('${idx + 1}', font),
                                ]);
                              })
                            ],
                          ),
                          pw.SizedBox(height: 6),
                        ],
                        // تسويات البنود (إرجاع)
                        if (itemCreditsForSection.isNotEmpty) ...[
                          pw.Text('تسوية البنود - إرجاع', style: pw.TextStyle(font: font, fontSize: 12)),
                          pw.SizedBox(height: 2),
                          pw.Table(
                            border: pw.TableBorder.all(width: 0.2),
                            columnWidths: {
                              0: const pw.FixedColumnWidth(90),
                              1: const pw.FixedColumnWidth(70),
                              2: const pw.FixedColumnWidth(65),
                              3: const pw.FixedColumnWidth(90),
                              4: const pw.FlexColumnWidth(0.8),
                              5: const pw.FixedColumnWidth(45),
                              6: const pw.FixedColumnWidth(20),
                            },
                            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                            children: [
                              pw.TableRow(children: [
                                _headerCell('المبلغ', font),
                                _headerCell('السعر', font),
                                _headerCell('عدد الوحدات', font),
                                _headerCell('العدد', font),
                                _headerCell('التفاصيل', font),
                                _headerCell('ID', font),
                                _headerCell('ت', font),
                              ]),
                              ...itemCreditsForSection.toList().asMap().entries.map((entry) {
                                final idx = entry.key;
                                final a = entry.value;
                                final qty = a.quantity ?? 0;
                                final price = a.price ?? 0;
                                final amount = price * qty;
                                final idText = formatProductId5(a.productId);
                                return pw.TableRow(children: [
                                  _dataCell(formatNumber(-amount, forceDecimal: true), font),
                                  _dataCell(formatNumber(price, forceDecimal: true), font),
                                  _dataCell((a.unitsInLargeUnit != null && a.unitsInLargeUnit! > 0) ? a.unitsInLargeUnit!.toStringAsFixed(2) : '-', font),
                                  _dataCell(qty.toStringAsFixed(2), font),
                                  _dataCell(a.productName ?? '', font, align: pw.TextAlign.right),
                                  _dataCell(idText, font),
                                  _dataCell('-', font),
                                ]);
                              })
                            ],
                          ),
                          pw.SizedBox(height: 6),
                        ],
                        // تسويات مبلغ فقط (معكوسة الأعمدة لتناسب اتجاه العربية)
                        if (amountOnlyAdjs.isNotEmpty) ...[
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('تعديل مبالغ', style: pw.TextStyle(font: font, fontSize: 12)),
                              pw.Text('التاريخ والوقت: ${DateTime.now().year}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().day.toString().padLeft(2, '0')} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}', style: pw.TextStyle(font: font, fontSize: 10)),
                            ],
                          ),
                          pw.SizedBox(height: 2),
                          pw.Table(
                            border: pw.TableBorder.all(width: 0.2),
                            columnWidths: {
                              0: const pw.FlexColumnWidth(), // ملاحظة
                              1: const pw.FixedColumnWidth(120), // النوع
                              2: const pw.FixedColumnWidth(90), // المبلغ
                            },
                            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                            children: [
                              pw.TableRow(children: [
                                _headerCell('ملاحظة', font),
                                _headerCell('النوع', font),
                                _headerCell('المبلغ', font),
                              ]),
                              ...amountOnlyAdjs.map((a) {
                                final kind = a.type == 'debit' ? 'تسوية إضافة' : 'تسوية إرجاع';
                                return pw.TableRow(children: [
                                  _dataCell(a.note ?? '-', font, align: pw.TextAlign.right),
                                  _dataCell(kind, font),
                                  _dataCell(formatNumber(a.amountDelta, forceDecimal: true), font),
                                ]);
                              })
                            ],
                          ),
                          pw.SizedBox(height: 10),
                        ],
                      ],
                      // --- ملخص المجاميع ---
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          if (hasAdjustments && !includeSameDayOnlyCase) ...[
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                                _summaryRow('الإجمالي قبل التعديل:', itemsTotalForDisplay, font),
                                pw.SizedBox(width: 10),
                                _summaryRow('إجمالي التسويات:', settlementsTotalForDisplay, font),
                                pw.SizedBox(width: 10),
                                _summaryRow('الإجمالي قبل الخصم:', preDiscountTotal, font),
                              pw.SizedBox(width: 10),
                              _summaryRow('الخصم:', discount, font),
                              ],
                            ),
                            pw.SizedBox(height: 4),
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.end,
                              children: [
                                _summaryRow('الإجمالي بعد الخصم:', afterDiscount, font),
                              pw.SizedBox(width: 10),
                                _summaryRow('المبلغ المدفوع:', displayedPaidForSettlementsCase, font),
                              ],
                            ),
                          ],
                          if (!hasAdjustments || includeSameDayOnlyCase) pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              _summaryRow('الإجمالي قبل الخصم:', itemsTotalForDisplay, font),
                              pw.SizedBox(width: 10),
                              _summaryRow('الخصم:', discount, font),
                              pw.SizedBox(width: 10),
                              _summaryRow('الإجمالي بعد الخصم:', afterDiscount, font),
                              pw.SizedBox(width: 10),
                              _summaryRow('المبلغ المدفوع:', displayedPaidForSettlementsCase, font),
                            ],
                          ),
                          pw.SizedBox(height: 4),
                          // عند وجود تسويات عرضنا "إجمالي القائمة" في السطر الثاني أعلاه
                          pw.SizedBox(height: 6),
                          // إضافة المبلغ المتبقي والدين السابق والدين الحالي وأجور التحميل
                          // عرض المتبقي دائماً في الملخص النهائي،
                          // خصوصاً عند وجود تسويات بالدين حتى لو كانت الفاتورة نقد.
                          if (true) ...[
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.end,
                              children: [
                                _summaryRow('المبلغ المتبقي:', remainingForPdf, font),
                                pw.SizedBox(width: 10),
                                _summaryRow('المبلغ المطلوب الحالي:', currentDebtForPdf, font),
                                pw.SizedBox(width: 10),
                                _summaryRow('اجور التحميل:', 
                                    double.tryParse(_loadingFeeController.text) ?? 0.0, font),
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
        if (isLast && !deferSummary) { printedSummaryInLastPage = true; }
      }

      // إذا تم تأجيل الملخص بسبب ضيق الصفحة الأخيرة، اطبعه في صفحة مستقلة لضمان ظهوره
      if (!printedSummaryInLastPage) {
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.only(top: 10, bottom: 10, left: 10, right: 10),
            build: (pw.Context context) {
              return pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    if (_invoiceToManage != null && _invoiceToManage!.id != null && (itemAdditionsForSection.isNotEmpty || itemCreditsForSection.isNotEmpty || amountOnlyAdjs.isNotEmpty)) ...[
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('التعديلات', style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                          pw.Text('التاريخ والوقت: ${DateTime.now().year}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().day.toString().padLeft(2, '0')} ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}', style: pw.TextStyle(font: font, fontSize: 10)),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      if (itemAdditionsForSection.isNotEmpty) ...[
                        pw.Text('تسوية البنود - إضافة', style: pw.TextStyle(font: font, fontSize: 12)),
                        pw.SizedBox(height: 2),
                        // لإيجاز الكود: إعادة استخدام نفس جداول البنود كما في الصفحة الأخيرة
                        // نطبع فقط مبالغ وخانات أساسية لضمان المساحة
                        pw.Table(
                          border: pw.TableBorder.all(width: 0.2),
                          columnWidths: { 0: const pw.FixedColumnWidth(90), 1: const pw.FixedColumnWidth(70), 2: const pw.FlexColumnWidth(1) },
                          children: [
                            pw.TableRow(children: [ _headerCell('المبلغ', font), _headerCell('السعر', font), _headerCell('التفاصيل', font) ]),
                            ...itemAdditionsForSection.map((a) {
                              final qty = a.quantity ?? 0; final price = a.price ?? 0; final amount = price * qty;
                              return pw.TableRow(children: [ _dataCell(formatNumber(amount, forceDecimal: true), font), _dataCell(formatNumber(price, forceDecimal: true), font), _dataCell(a.productName ?? '', font, align: pw.TextAlign.right) ]);
                            })
                          ],
                        ),
                        pw.SizedBox(height: 6),
                      ],
                      if (itemCreditsForSection.isNotEmpty) ...[
                        pw.Text('تسوية البنود - إرجاع', style: pw.TextStyle(font: font, fontSize: 12)),
                        pw.SizedBox(height: 2),
                        pw.Table(
                          border: pw.TableBorder.all(width: 0.2),
                          columnWidths: { 0: const pw.FixedColumnWidth(90), 1: const pw.FixedColumnWidth(70), 2: const pw.FlexColumnWidth(1) },
                          children: [
                            pw.TableRow(children: [ _headerCell('المبلغ', font), _headerCell('السعر', font), _headerCell('التفاصيل', font) ]),
                            ...itemCreditsForSection.map((a) {
                              final qty = a.quantity ?? 0; final price = a.price ?? 0; final amount = price * qty;
                              return pw.TableRow(children: [ _dataCell(formatNumber(amount, forceDecimal: true), font), _dataCell(formatNumber(price, forceDecimal: true), font), _dataCell(a.productName ?? '', font, align: pw.TextAlign.right) ]);
                            })
                          ],
                        ),
                        pw.SizedBox(height: 6),
                      ],
                      if (amountOnlyAdjs.isNotEmpty) ...[
                        pw.Table(
                          border: pw.TableBorder.all(width: 0.2),
                          columnWidths: { 0: const pw.FlexColumnWidth(1), 1: const pw.FixedColumnWidth(70), 2: const pw.FixedColumnWidth(90) },
                          children: [
                            pw.TableRow(children: [ _headerCell('ملاحظة', font), _headerCell('النوع', font), _headerCell('المبلغ', font) ]),
                            ...amountOnlyAdjs.map((a) { final kind = a.type == 'debit' ? 'تسوية إضافة' : 'تسوية إرجاع'; return pw.TableRow(children: [ _dataCell(a.note ?? '-', font, align: pw.TextAlign.right), _dataCell(kind, font), _dataCell(formatNumber(a.amountDelta, forceDecimal: true), font) ]); })
                          ],
                        ),
                      ],
                      pw.SizedBox(height: 10),
                    ],
                    // الملخص النهائي
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        if (hasAdjustments && !includeSameDayOnlyCase) ...[
                          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                            _summaryRow('الإجمالي قبل التعديل:', itemsTotalForDisplay, font), pw.SizedBox(width: 10), _summaryRow('إجمالي التسويات:', settlementsTotalForDisplay, font), pw.SizedBox(width: 10), _summaryRow('الإجمالي قبل الخصم:', preDiscountTotal, font), pw.SizedBox(width: 10), _summaryRow('الخصم:', discount, font),
                          ]),
                          pw.SizedBox(height: 4),
                          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                            _summaryRow('الإجمالي بعد الخصم:', afterDiscount, font), pw.SizedBox(width: 10), _summaryRow('المبلغ المدفوع:', displayedPaidForSettlementsCase, font),
                          ]),
                        ] else ...[
                          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                            _summaryRow('الإجمالي قبل الخصم:', itemsTotalForDisplay, font), pw.SizedBox(width: 10), _summaryRow('الخصم:', discount, font), pw.SizedBox(width: 10), _summaryRow('الإجمالي بعد الخصم:', afterDiscount, font), pw.SizedBox(width: 10), _summaryRow('المبلغ المدفوع:', displayedPaidForSettlementsCase, font),
                          ]),
                        ],
                        pw.SizedBox(height: 6),
                        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                          _summaryRow('المبلغ المتبقي:', remainingForPdf, font), pw.SizedBox(width: 10), _summaryRow('المبلغ المطلوب الحالي:', currentDebtForPdf, font), pw.SizedBox(width: 10), _summaryRow('اجور التحميل:', double.tryParse(_loadingFeeController.text) ?? 0.0, font),
                        ]),
                      ],
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

  // حوار خطوات التسوية: اختيار (إضافة/حذف) ثم (بند/مبلغ)
  Future<void> _openSettlementChoice() async {
    if (_invoiceToManage == null) return;
    // Dialog 1: إضافة / حذف
    String? op = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسوية الفاتورة'),
        content: const Text('اختر نوع العملية'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'credit'), child: const Text('حذف (راجع)')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'debit'), child: const Text('إضافة')),
        ],
      ),
    );
    if (op == null) return;
    _settlementIsDebit = (op == 'debit');

    // Dialog 2: بند / مبلغ + ملاحظة
    String? mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('طريقة التسوية'),
        content: const Text('اختر تسوية ببند أم مبلغ مباشر؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'amount'), child: const Text('مبلغ + ملاحظة')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'item'), child: const Text('بند (أصناف)')),
        ],
      ),
    );
    if (mode == null) return;
    if (mode == 'amount') {
      await _openSettlementAmountDialog();
      return;
    }
    // mode == item ⇒ افتح لوحة الأصناف أسفل الجدول
    setState(() {
      _settlementPanelVisible = true;
      _settlementItems.clear();
      _settleSelectedProduct = null;
      _settleSelectedSaleType = 'قطعة';
      _settleNameCtrl.clear();
      _settleIdCtrl.clear();
      _settleQtyCtrl.clear();
      _settlePriceCtrl.clear();
      _settleUnitCtrl.clear();
      _settlementPaymentType = (_invoiceToManage?.paymentType == 'دين') ? 'دين' : 'نقد';
    });
  }

  // دالة تفعيل وضع التعديل
  void _enableEditMode() {
    setState(() {
      _isViewOnly = false;
    });
    
    // إظهار رسالة تأكيد
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تفعيل وضع التعديل - يمكنك الآن إضافة أو حذف أصناف'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // دالة إلغاء التعديل
  void _cancelEdit() {
    setState(() {
      _isViewOnly = true;
    });
    
    // إعادة تحميل البيانات الأصلية
    _loadInvoiceItems();
    
    // إظهار رسالة تأكيد
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إلغاء التعديل - تم استعادة البيانات الأصلية'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // فحص إذا كانت التسويات الراجعة تتجاوز المبلغ المتبقي الفعلي
  Future<bool> _isRefundExceedingRemaining(double newRefundAmount) async {
    if (_invoiceToManage == null) return false;
    
    // حساب المبلغ المتبقي الحالي
    final remainingAmount = await _calculateRemainingAmount();
    
    // إضافة التسوية الجديدة
    final totalRefunds = remainingAmount + newRefundAmount.abs();
    
    // فحص إذا تجاوزت المبلغ المتبقي (أصبحت سالبة)
    return totalRefunds < 0;
  }

  // حساب المبلغ المتبقي بعد التسويات
  Future<double> _calculateRemainingAmount() async {
    if (_invoiceToManage == null) return 0.0;
    
    // حساب إجمالي الفاتورة
    final itemsTotal = _invoiceToManage!.totalAmount;
    final discount = _invoiceToManage!.discount;
    final afterDiscount = itemsTotal - discount;
    
    // حساب التسويات
    final adjustments = await _db.getInvoiceAdjustments(_invoiceToManage!.id!);
    final cashSettlements = adjustments
        .where((adj) => adj.settlementPaymentType == 'نقد')
        .fold<double>(0.0, (sum, adj) => sum + adj.amountDelta);
    final debtSettlements = adjustments
        .where((adj) => adj.settlementPaymentType == 'دين')
        .fold<double>(0.0, (sum, adj) => sum + adj.amountDelta);
    
    // حساب المبلغ المدفوع المعروض
    final double displayedPaid;
    if (_invoiceToManage!.paymentType == 'نقد' && adjustments.isNotEmpty) {
      // للفواتير النقدية مع تسويات: المبلغ المدفوع = المبلغ الأصلي + التسويات النقدية فقط
      displayedPaid = _invoiceToManage!.amountPaidOnInvoice + cashSettlements;
    } else {
      // للفواتير بالدين أو الفواتير النقدية بدون تسويات
      displayedPaid = _invoiceToManage!.amountPaidOnInvoice + cashSettlements;
    }
    
    // حساب المبلغ المتبقي
    return afterDiscount - displayedPaid;
  }

  Future<void> _openSettlementAmountDialog() async {
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    // الإرجاع/الحذف لا يملك خيار (دين/نقد) ويجب أن يؤثر على الدين تلقائياً
    String paymentKind = _settlementIsDebit
        ? ((_invoiceToManage?.paymentType == 'دين') ? 'دين' : 'نقد')
        : 'دين';
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_settlementIsDebit ? 'إضافة مبلغ' : 'حذف (راجع) مبلغ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'المبلغ'),
            ),
            if (_settlementIsDebit) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: paymentKind,
                onChanged: (v) { if (v != null) paymentKind = v; },
                items: const [
                  DropdownMenuItem(value: 'دين', child: Text('دين')),
                  DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                ],
                decoration: const InputDecoration(labelText: 'طريقة دفع التسوية'),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true || _invoiceToManage == null) return;
    final v = double.tryParse(amountCtrl.text.trim());
    if (v == null || v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل مبلغاً صحيحاً')));
      return;
    }
    final delta = _settlementIsDebit ? v.abs() : -v.abs();
    
    // فحص إذا كانت التسوية راجعة وتتجاوز المبلغ المتبقي الفعلي
    if (!_settlementIsDebit) {
      final isExceeding = await _isRefundExceedingRemaining(v.abs());
      if (isExceeding) {
        final remainingAmount = await _calculateRemainingAmount();
        final maxAllowedRefund = remainingAmount.abs();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('التسوية الراجعة تتجاوز المبلغ المتبقي. الحد الأقصى المسموح: ${formatNumber(maxAllowedRefund, forceDecimal: true)} دينار'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    
    await _db.insertInvoiceAdjustment(InvoiceAdjustment(
      invoiceId: _invoiceToManage!.id!,
      type: _settlementIsDebit ? 'debit' : 'credit',
      amountDelta: delta,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      settlementPaymentType: paymentKind,
    ));
    await _loadSettlementInfo();
    
    // فحص إذا كان المبلغ المتبقي أصبح سالباً (يحتاج كاش)
    if (mounted) {
      final remainingAmount = await _calculateRemainingAmount();
      if (remainingAmount < 0) {
        final cashToGive = (-remainingAmount).abs();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تنبيه'),
            content: Text('يجب أن تعطيه ${formatNumber(cashToGive, forceDecimal: true)} دينار كاش'),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('موافق'),
              ),
            ],
          ),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تسوية المبلغ')));
    }
  }

  Widget _buildSettlementPanel() {
    final Color gridBorderColor = Colors.grey.shade300;
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_settlementIsDebit ? 'تسوية: إضافة بنود' : 'تسوية: حذف (راجع) بنود', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => setState(() => _settlementPanelVisible = false),
                  icon: const Icon(Icons.close),
                  label: const Text('إخفاء'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _settlementPaymentType,
                    onChanged: (v) {
                      if (v != null) setState(() => _settlementPaymentType = v);
                    },
                    items: const [
                      DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                      DropdownMenuItem(value: 'دين', child: Text('دين')),
                    ],
                    decoration: const InputDecoration(labelText: 'طريقة دفع التسوية'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // جدول تسوية بنفس تصميم جدول الفاتورة
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: gridBorderColor),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  // رأس الجدول
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(bottom: BorderSide(color: gridBorderColor)),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 1, child: Text('ت', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('المبلغ', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('ID', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text('التفاصيل', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('العدد', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('نوع البيع', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('السعر', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('عدد الوحدات', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Expanded(flex: 1, child: Text('حذف', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  // صف إدخال جديد
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: gridBorderColor)),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 1, child: Text('${_settlementItems.length + 1}', textAlign: TextAlign.center)),
                        Expanded(flex: 1, child: Text('', textAlign: TextAlign.center)), // المبلغ سيحسب تلقائياً
                        Expanded(
                          flex: 1,
                          child: Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) async {
                              if (textEditingValue.text.isEmpty) {
                                return const Iterable<String>.empty();
                              }
                              final v = textEditingValue.text.trim();
                              final id = int.tryParse(v);
                              if (id == null) return const Iterable<String>.empty();
                              final db = DatabaseService();
                              final suggestions = await db.searchProductsByIdPrefix(v, limit: 8);
                              return suggestions.map((p) => p.name);
                            },
                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                              // ربط controller مع _settleIdController
                              _settleIdController = controller;
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  hintText: 'ID',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                  isDense: true,
                                ),
                                onSubmitted: (val) async {
                                  final id = int.tryParse(val.trim());
                                  if (id == null) return;
                                  final p = await _db.getProductById(id);
                                  if (p != null) {
                                    _applySettlementProductSelection(p);
                                  }
                                },
                              );
                            },
                            onSelected: (String selection) {
                              try {
                                // البحث عن المنتج المحدد وتطبيق التعبئة التلقائية
                                _db.searchProductsSmart(selection).then((products) {
                                  if (products.isNotEmpty) {
                                    _applySettlementProductSelection(products.first);
                                  }
                                });
                              } catch (e) {}
                            },
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) async {
                              if (textEditingValue.text.isEmpty) {
                                return const Iterable<String>.empty();
                              }
                              final db = DatabaseService();
                              final results = await db.searchProductsSmart(textEditingValue.text);
                              return results.map((p) => p.name);
                            },
                            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                              // ربط controller مع _settleNameController
                              _settleNameController = controller;
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  hintText: 'التفاصيل',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                                  isDense: true,
                                ),
                                // عند الكتابة لا نقوم باختيار أول نتيجة تلقائياً؛ نعرض الاقتراحات فقط،
                                // ويتم تطبيق الاختيار عند تحديد عنصر من القائمة أو تأكيد الإدخال.
                              );
                            },
                            onSelected: (String selection) {
                              try {
                                // البحث عن المنتج المحدد وتطبيق التعبئة التلقائية
                                _db.searchProductsSmart(selection).then((products) {
                                  if (products.isNotEmpty) {
                                    _applySettlementProductSelection(products.first);
                                  }
                                });
                              } catch (e) {}
                            },
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _settleQtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              hintText: 'العدد',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              isDense: true,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _settleSelectedSaleType,
                              items: _getSettlementUnitOptions(),
                              onChanged: (value) {
                                setState(() {
                                  _settleSelectedSaleType = value!;
                                });
                              },
                              isExpanded: true,
                              alignment: AlignmentDirectional.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _settlePriceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              hintText: 'السعر',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              isDense: true,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey),
                              borderRadius: BorderRadius.circular(4),
                              color: Colors.grey[100],
                            ),
                            child: Text(
                              _settleSelectedProduct?.piecesPerUnit?.toStringAsFixed(0) ?? '1',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: ElevatedButton(
                            onPressed: _addSettlementRow,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                              minimumSize: Size.zero,
                            ),
                            child: const Text('إضافة', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // الأصناف المضافة
                  for (int i = 0; i < _settlementItems.length; i++)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: gridBorderColor)),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 1, child: Text('${i + 1}', textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text(_settlementItems[i].itemTotal.toStringAsFixed(2), textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text(_settlementItems[i].productId?.toString() ?? '', textAlign: TextAlign.center)),
                          Expanded(flex: 2, child: Text(_settlementItems[i].productName, textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text((_settlementItems[i].quantityIndividual ?? _settlementItems[i].quantityLargeUnit ?? 0).toString(), textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text(_settlementItems[i].unit, textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text(_settlementItems[i].appliedPrice.toStringAsFixed(2), textAlign: TextAlign.center)),
                          Expanded(flex: 1, child: Text('', textAlign: TextAlign.center)), // عدد الوحدات
                          Expanded(
                            flex: 1,
                            child: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                              onPressed: () => setState(() => _settlementItems.removeAt(i)),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _saveSettlementItems,
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ بنود التسوية'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  void _addSettlementRow() {
    final name = _settleNameCtrl.text.trim();
    final qty = double.tryParse(_settleQtyCtrl.text.trim());
    final price = double.tryParse(_settlePriceCtrl.text.trim());
    // احسب عدد الوحدات الأساسية داخل وحدة البيع المختارة باستخدام الهرمية
    double unitsCount = 1.0;
    if (_settleSelectedProduct != null) {
      final prod = _settleSelectedProduct!;
      if (_settleSelectedSaleType == 'قطعة' || _settleSelectedSaleType == 'متر') {
        unitsCount = 1.0;
      } else if (prod.unit == 'meter' && _settleSelectedSaleType == 'لفة') {
        unitsCount = prod.lengthPerUnit?.toDouble() ?? 1.0;
      } else {
        // للمنتجات بالقطعة: احسب الضرب التراكمي حتى تصل للوحدة المطلوبة
        try {
          final List<Map<String, dynamic>> hierarchy = prod.getUnitHierarchyList();
          double cumulative = 1.0;
          for (final level in hierarchy) {
            final String levelName = (level['unit_name'] ?? level['name'] ?? '').toString();
            final double q = (level['quantity'] is num)
                ? (level['quantity'] as num).toDouble()
                : double.tryParse(level['quantity']?.toString() ?? '') ?? 1.0;
            cumulative = cumulative * (q > 0 ? q : 1.0);
            if (levelName == _settleSelectedSaleType) {
              unitsCount = cumulative;
              break;
            }
          }
        } catch (_) {
          unitsCount = 1.0;
        }
      }
    }
    
    if (name.isEmpty || qty == null || qty <= 0 || price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل التفاصيل والعدد والسعر بشكل صحيح')));
      return;
    }
    
    final item = InvoiceItem(
      invoiceId: 0,
      productId: _settleSelectedProduct?.id,
      productName: name,
      unit: _settleSelectedProduct?.unit ?? 'piece',
      unitPrice: _settleSelectedProduct?.unitPrice ?? price,
      appliedPrice: price,
      itemTotal: price * qty,
      quantityIndividual: (_settleSelectedSaleType == 'قطعة' || _settleSelectedSaleType == 'متر') ? qty : null,
      quantityLargeUnit: (_settleSelectedSaleType != 'قطعة' && _settleSelectedSaleType != 'متر') ? qty : null,
      saleType: _settleSelectedSaleType,
      unitsInLargeUnit: unitsCount,
      uniqueId: 'settle_${DateTime.now().microsecondsSinceEpoch}',
    );
    
    setState(() {
      _settlementItems.add(item);
      _settleQtyCtrl.clear();
      _settlePriceCtrl.clear();
    });
  }

  void _applySettlementProductSelection(Product prod) {
    setState(() {
      _settleSelectedProduct = prod;
      // ملء حقل ID بالمعرف
      _settleIdCtrl.text = prod.id?.toString() ?? '';
      // ملء حقل التفاصيل بالاسم
      _settleNameCtrl.text = prod.name;
      // ملء حقل السعر
      _settlePriceCtrl.text = (prod.price1 ?? prod.unitPrice).toString();
      
      // تحديد نوع البيع المناسب بناءً على الخيارات المتاحة
      List<String> availableOptions = _getAvailableUnitOptions(prod);
      if (availableOptions.isNotEmpty) {
        _settleSelectedSaleType = availableOptions.first;
      } else {
        _settleSelectedSaleType = 'قطعة';
      }
    });
    
    // تحديث controller في Autocomplete مباشرة
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // تحديث حقل ID
        _settleIdController?.text = prod.id?.toString() ?? '';
        // تحديث حقل التفاصيل
        _settleNameController?.text = prod.name;
      }
    });
  }

  List<String> _getAvailableUnitOptions(Product prod) {
    List<String> options = ['قطعة'];
    if (prod.unit == 'piece' && 
        prod.unitHierarchy != null && 
        prod.unitHierarchy!.isNotEmpty) {
      try {
        List<dynamic> hierarchy = json.decode(prod.unitHierarchy!.replaceAll("'", '"'));
        options.addAll(hierarchy.map((e) => (e['unit_name'] ?? e['name']).toString()));
      } catch (e) {}
    } else if (prod.unit == 'meter' && prod.lengthPerUnit != null) {
      options = ['متر'];
      options.add('لفة');
    } else if (prod.unit != 'piece' && prod.unit != 'meter') {
      options = [prod.unit];
    }
    
    // إزالة التكرار والقيم الفارغة
    return options.where((e) => e.isNotEmpty).toSet().toList();
  }

  List<DropdownMenuItem<String>> _getSettlementUnitOptions() {
    if (_settleSelectedProduct == null) {
      return [const DropdownMenuItem(value: 'قطعة', child: Text('قطعة', textAlign: TextAlign.center))];
    }
    
    List<String> options = _getAvailableUnitOptions(_settleSelectedProduct!);
    
    // التأكد من أن القيمة المحددة موجودة في القائمة
    if (!options.contains(_settleSelectedSaleType)) {
      _settleSelectedSaleType = options.first;
    }
    
    return options.map((unit) => DropdownMenuItem(
      value: unit,
      child: Text(unit, textAlign: TextAlign.center),
    )).toList();
  }

  Future<void> _saveSettlementItems() async {
    if (_invoiceToManage == null || _settlementItems.isEmpty) return;
    
    // فحص إذا كانت التسويات الراجعة تتجاوز المبلغ المتبقي الفعلي
    if (!_settlementIsDebit) {
      final totalRefundAmount = _settlementItems.fold<double>(0.0, (sum, item) => sum + item.itemTotal);
      final isExceeding = await _isRefundExceedingRemaining(totalRefundAmount);
      if (isExceeding) {
        final remainingAmount = await _calculateRemainingAmount();
        final maxAllowedRefund = remainingAmount.abs();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('التسويات الراجعة تتجاوز المبلغ المتبقي. الحد الأقصى المسموح: ${formatNumber(maxAllowedRefund, forceDecimal: true)} دينار'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }
    
    for (final it in _settlementItems) {
      final delta = (_settlementIsDebit ? 1 : -1) * (it.itemTotal);
      final paymentType = _settlementIsDebit ? _settlementPaymentType : 'دين';
      
      print('=== DEBUG SAVING SETTLEMENT ITEM ===');
      print('DEBUG: _settlementIsDebit = $_settlementIsDebit');
      print('DEBUG: _settlementPaymentType = $_settlementPaymentType');
      print('DEBUG: final paymentType = $paymentType');
      print('DEBUG: productName = ${it.productName}');
      print('DEBUG: itemTotal = ${it.itemTotal}');
      print('=== END DEBUG SAVING SETTLEMENT ITEM ===');
      
      await _db.insertInvoiceAdjustment(InvoiceAdjustment(
        invoiceId: _invoiceToManage!.id!,
        type: _settlementIsDebit ? 'debit' : 'credit',
        amountDelta: delta,
        productId: it.productId,
        productName: it.productName,
        quantity: (it.quantityIndividual ?? it.quantityLargeUnit ?? 0).toDouble(),
        price: it.appliedPrice,
        unit: it.unit,
        saleType: it.saleType,
        unitsInLargeUnit: it.unitsInLargeUnit,
        settlementPaymentType: paymentType,
        note: 'تسوية بند',
      ));
    }
    if (mounted) {
      setState(() {
        _settlementPanelVisible = false;
        _settlementItems.clear();
        _settleSelectedProduct = null;
        _settleSelectedSaleType = 'قطعة';
        _settleNameCtrl.clear();
        _settleIdCtrl.clear();
        _settleQtyCtrl.clear();
        _settlePriceCtrl.clear();
        _settleUnitCtrl.clear();
      });
      
      // فحص إذا كان المبلغ المتبقي أصبح سالباً (يحتاج كاش)
      final remainingAmount = await _calculateRemainingAmount();
      if (remainingAmount < 0) {
        final cashToGive = (-remainingAmount).abs();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تنبيه'),
            content: Text('يجب أن تعطيه ${formatNumber(cashToGive, forceDecimal: true)} دينار كاش'),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('موافق'),
              ),
            ],
          ),
        );
      }
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ بنود التسوية')));
    }
  }

  // حفظ التسوية كأصناف جديدة مرتبطة بالفاتورة الأساسية عبر invoice_adjustments
  Future<void> _saveSettlement() async {
    try {
      if (widget.settlementForInvoice == null) return;
      final baseInvoice = widget.settlementForInvoice!;
      // صفّ البيانات الفارغة وأحسب الإجمالي
      final settlementItems = _invoiceItems.where((it) => _isInvoiceItemComplete(it)).toList();
      if (settlementItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف بنوداً للتسوية أولاً')));
        return;
      }
      for (final item in settlementItems) {
        // المبلغ للبند
        final double qty = (item.quantityIndividual ?? item.quantityLargeUnit ?? 0).toDouble();
        final double price = item.appliedPrice;
        final double delta = qty * price;
        // البحث عن المنتج لتعويض productId
        Product? prod;
        try {
          final all = await _db.getAllProducts();
          prod = all.firstWhere((p) => p.name == item.productName);
        } catch (_) {}
        await _db.insertInvoiceAdjustment(
          InvoiceAdjustment(
            invoiceId: baseInvoice.id!,
            type: 'debit',
            amountDelta: delta,
            productId: prod?.id,
            productName: item.productName,
            quantity: qty,
            price: price,
            note: 'تسوية بند',
          ),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التسوية وربطها بالفاتورة')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل حفظ التسوية: $e')));
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
          _invoiceToManage!.copyWith(isLocked: true);
      await _db.updateInvoice(updatedInvoice);

      // إزالة منطق خصم الراجع من رصيد المؤسس
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

      // إزالة منطق دين العميل المرتبط بالراجع

      // جلب أحدث نسخة من الفاتورة بعد الحفظ
      final updatedInvoiceFromDb =
          await _db.getInvoiceById(_invoiceToManage!.id!);
      setState(() {
        _invoiceToManage = updatedInvoiceFromDb;
        _isViewOnly = true; // تفعيل وضع العرض فقط
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم قفل الفاتورة!')), 
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
      double paid = double.tryParse(_paidAmountController.text.replaceAll(',', '')) ?? 0.0;
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
    _totalAmountController.text = formatNumber(total);
    if (_paymentType == 'نقد') {
      _paidAmountController.text = formatNumber(total - _discount);
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
          title: Text(_invoiceToManage != null 
              ? (_isViewOnly ? 'عرض فاتورة' : 'تعديل فاتورة')
              : 'إنشاء فاتورة'),
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
            if (_invoiceToManage != null && _isViewOnly) ...[
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'تعديل الفاتورة',
                onPressed: _enableEditMode,
              ),
              IconButton(
                icon: const Icon(Icons.playlist_add),
                tooltip: 'تسوية الفاتورة - تحت التطوير',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('هذه الميزة تحت التطوير حالياً'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
            if (_invoiceToManage != null && !_isViewOnly) ...[
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'حفظ التعديلات',
                onPressed: _saveInvoice,
              ),
              IconButton(
                icon: const Icon(Icons.cancel),
                tooltip: 'إلغاء التعديل',
                onPressed: _cancelEdit,
              ),
            ],
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
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _productIdController,
                              keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                              decoration: const InputDecoration(
                                labelText: 'ID الصنف (إضافة مباشرة بالمعرّف)',
                                hintText: 'اكتب ID المنتج ثم Enter',
                              ),
                              enabled: !_isViewOnly,
                              onFieldSubmitted: _isViewOnly ? null : _handleSubmitProductId,
                              onChanged: _isViewOnly ? null : _handleChangeProductId,
                            ),
                            if (_productIdSuggestion != null)
                              Container(
                                margin: const EdgeInsets.only(top: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x22000000),
                                      blurRadius: 6,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                constraints: const BoxConstraints(maxHeight: 160),
                                child: ListView(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  children: [
                                    ListTile(
                                      dense: true,
                                      title: Text(_productIdSuggestion!.name),
                                      subtitle: Text('ID: ${_productIdSuggestion!.id}'),
                                      onTap: () => _handleSubmitProductId(_productIdSuggestion!.id!.toString()),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: TextFormField(
                          controller: _productSearchController,
                          focusNode: _searchFocusNode, // ربط FocusNode
                          decoration: InputDecoration(
                            labelText: 'البحث عن صنف (بحث ذكي يدعم الكلمات المتعددة)',
                            hintText: 'مثال: اكتب "كوب فنار" لإيجاد "كوب واحد سيه فنار"',
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
                      ),
                    ],
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
                            inputFormatters: [
                              ThousandSeparatorDecimalInputFormatter(),
                            ],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'الرجاء إدخال الكمية';
                              }
                              final v = double.tryParse(value.replaceAll(',', ''));
                              if (v == null || v <= 0) {
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
                                  labelText: 'مستوى السعر',
                                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                ),
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
                                isDense: true,
                                menuMaxHeight: 240,
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
                if (_settlementPanelVisible) _buildSettlementPanel(),
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
                            flex: 2,
                            child: Center(
                                child: Text('ID',
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
                      databaseService: _db, // إضافة DatabaseService للبحث الذكي
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
                        double.tryParse(_paidAmountController.text.replaceAll(',', '')) ?? 0;
                    double displayedPaidAmount = enteredPaidAmount;
                    double displayedRemainingAmount = total - enteredPaidAmount;
                    final double totalAfterAdjustments =
                        total + (_invoiceAdjustments.isNotEmpty ? _totalSettlementAmount : 0.0);

                    // حساب التسويات النقدية والدينية
                    final double cashSettlements = _invoiceAdjustments
                        .where((a) => (a.settlementPaymentType ?? 'نقد') == 'نقد')
                        .fold(0.0, (sum, a) {
                          // للتسويات البنود: احسب من price * quantity
                          if (a.productId != null) {
                            final double price = a.price ?? 0.0;
                            final double quantity = a.quantity ?? 0.0;
                            return sum + (price * quantity);
                          } else {
                            // للتسويات المبلغ: استخدم amountDelta
                            return sum + a.amountDelta;
                          }
                        });
                    final double debtSettlements = _invoiceAdjustments
                        .where((a) => a.settlementPaymentType == 'دين')
                        .fold(0.0, (sum, a) {
                          // للتسويات البنود: احسب من price * quantity
                          if (a.productId != null) {
                            final double price = a.price ?? 0.0;
                            final double quantity = a.quantity ?? 0.0;
                            return sum + (price * quantity);
                          } else {
                            // للتسويات المبلغ: استخدم amountDelta
                            return sum + a.amountDelta;
                          }
                        });

                    if (_paymentType == 'نقد') {
                      // للفواتير النقدية: المبلغ المدفوع يجب أن يساوي الإجمالي كاملاً
                      displayedPaidAmount = totalAfterAdjustments;
                      displayedRemainingAmount = 0;
                    } else {
                      // للفواتير بالدين: إضافة التسويات النقدية إلى المبلغ المدفوع المعروض
                      displayedPaidAmount = enteredPaidAmount + cashSettlements;
                      displayedRemainingAmount = totalAfterAdjustments - displayedPaidAmount;
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
                                'المبلغ الإجمالي قبل الخصم:  ${formatNumber(totalBeforeDiscount, forceDecimal: true)} دينار',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(
                                'المبلغ الإجمالي:  ${formatNumber(total, forceDecimal: true)} دينار',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            if (_invoiceAdjustments.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                  'المبلغ الإجمالي بعد التعديلات:  ${formatNumber(totalAfterAdjustments, forceDecimal: true)} دينار',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                            const SizedBox(height: 4),
                            Text(
                                'المبلغ المسدد:    ${formatNumber(displayedPaidAmount, forceDecimal: true)} دينار',
                                style: const TextStyle(color: Colors.green)),
                            const SizedBox(height: 4),
                            Text(
                                'المتبقي:         ${formatNumber(displayedRemainingAmount, forceDecimal: true)} دينار',
                                style: const TextStyle(color: Colors.red)),
                            if (_paymentType == 'دين' || debtSettlements != 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                    'أصبح الدين: ${formatNumber(displayedRemainingAmount + debtSettlements, forceDecimal: true)} دينار',
                                    style:
                                        const TextStyle(color: Colors.black87)),
                              ),
                            // عرض معلومات التسويات
                            if (_invoiceAdjustments.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blue[200]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.edit, color: Colors.blue[700], size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          'معلومات التسويات (${_invoiceAdjustments.length} تعديل)',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue[700],
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'إجمالي التسويات: ${_totalSettlementAmount > 0 ? '+' : ''}${formatNumber(_totalSettlementAmount, forceDecimal: true)} دينار',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _totalSettlementAmount > 0 ? Colors.green[700] : Colors.red[700],
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Builder(
                                      builder: (context) {
                                        final List<InvoiceAdjustment> itemAdjustments = _invoiceAdjustments
                                            .where((a) => (a.productId != null || (a.productName ?? '').isNotEmpty))
                                            .toList();
                                        final List<InvoiceAdjustment> amountOnlyAdjustments = _invoiceAdjustments
                                            .where((a) => (a.productId == null && (a.productName == null || a.productName!.isEmpty)))
                                            .toList();

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                            if (itemAdjustments.isNotEmpty) ...[
                                              SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                child: DataTable(
                                                  headingRowHeight: 32,
                                                  dataRowMinHeight: 32,
                                                  dataRowMaxHeight: 40,
                                                  columns: const [
                                                    DataColumn(label: Text('ت')),
                                                    DataColumn(label: Text('المبلغ')),
                                                    DataColumn(label: Text('ID')),
                                                    DataColumn(label: Text('التفاصيل')),
                                                    DataColumn(label: Text('العدد')),
                                                    DataColumn(label: Text('نوع البيع')),
                                                    DataColumn(label: Text('السعر')),
                                                    DataColumn(label: Text('عدد الوحدات')),
                                                    DataColumn(label: Text('التاريخ/الوقت')),
                                                  ],
                                                  rows: List<DataRow>.generate(
                                                    itemAdjustments.length,
                                                    (index) {
                                                      final adj = itemAdjustments[index];
                                                      final double quantity = adj.quantity ?? 0.0;
                                                      final double price = adj.price ?? 0.0;
                                                      final double rowAmount = (quantity * price);
                                                      final String sign = adj.type == 'debit' ? '+' : '−';
                                                      final String dt = '${adj.createdAt.year}/${adj.createdAt.month.toString().padLeft(2,'0')}/${adj.createdAt.day.toString().padLeft(2,'0')} ${adj.createdAt.hour.toString().padLeft(2,'0')}:${adj.createdAt.minute.toString().padLeft(2,'0')}';
                                                      return DataRow(cells: [
                                                        DataCell(Text('${index + 1}')),
                                                        DataCell(Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text(sign, style: TextStyle(color: adj.type == 'debit' ? Colors.green[700] : Colors.red[700], fontWeight: FontWeight.bold)),
                                                            const SizedBox(width: 4),
                                                            Text(formatNumber(rowAmount, forceDecimal: true)),
                                                          ],
                                                        )),
                                                        DataCell(Text(adj.productId?.toString() ?? '')),
                                                        DataCell(Text(adj.productName ?? '')),
                                                        DataCell(Text(quantity.toStringAsFixed(2))),
                                                        DataCell(Text(adj.saleType ?? '')),
                                                        DataCell(Text(price.toStringAsFixed(2))),
                                                        DataCell(Text((adj.unitsInLargeUnit ?? 0).toString())),
                                                        DataCell(Text(dt)),
                                                      ]);
                                                    },
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                            ],

                                            if (amountOnlyAdjustments.isNotEmpty) ...[
                                              DataTable(
                                                headingRowHeight: 32,
                                                dataRowMinHeight: 32,
                                                dataRowMaxHeight: 40,
                                                columns: const [
                                                  DataColumn(label: Text('ملاحظة')),
                                                  DataColumn(label: Text('النوع')),
                                                  DataColumn(label: Text('المبلغ')),
                                                  DataColumn(label: Text('التاريخ/الوقت')),
                                                ],
                                                rows: amountOnlyAdjustments.map((adj) {
                                                  final String dt = '${adj.createdAt.year}/${adj.createdAt.month.toString().padLeft(2,'0')}/${adj.createdAt.day.toString().padLeft(2,'0')} ${adj.createdAt.hour.toString().padLeft(2,'0')}:${adj.createdAt.minute.toString().padLeft(2,'0')}';
                                                  return DataRow(cells: [
                                                    DataCell(Text(adj.note ?? '')),
                                                    DataCell(Text(adj.type == 'debit' ? 'إضافة' : 'حذف')),
                                                    DataCell(Text(formatNumber(adj.amountDelta, forceDecimal: true))),
                                                    DataCell(Text(dt)),
                                                  ]);
                                                }).toList(),
                                              ),
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                                  _paidAmountController.text = formatNumber(0);
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        ThousandSeparatorDecimalInputFormatter(),
                      ],
                      enabled: !_isViewOnly && _paymentType == 'دين',
                      onChanged: (value) {
                        setState(() {
                          double enteredPaid = double.tryParse(value.replaceAll(',', '')) ?? 0.0;
                          final total = _invoiceItems.fold(
                                  0.0, (sum, item) => sum + item.itemTotal) -
                              _discount;
                          if (enteredPaid >= total) {
                            _paidAmountController.text = formatNumber(0);
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
                  inputFormatters: [
                    ThousandSeparatorDecimalInputFormatter(),
                  ],
                  onChanged: _isViewOnly
                      ? null
                      : (val) {
                          setState(() {
                            double enteredDiscount =
                                double.tryParse(val.replaceAll(',', '')) ?? 0.0;
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
                  initialValue: _discount > 0 ? formatNumber(_discount) : '',
                  enabled: !_isViewOnly,
                ),
                const SizedBox(height: 24.0),
                // في وضع التسوية أيضاً نحتاج زر حفظ لكن يختلف المنطق
                if (!_isViewOnly)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      if (widget.settlementForInvoice == null)
                        ElevatedButton.icon(
                          onPressed: _saveInvoice,
                          icon: const Icon(Icons.save),
                          label: const Text('حفظ الفاتورة'),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: _saveSettlement,
                          icon: const Icon(Icons.save_as),
                          label: const Text('حفظ التسوية'),
                        ),
                    ],
                  ),
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
                    inputFormatters: [
                      ThousandSeparatorDecimalInputFormatter(),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _showAddAdjustmentDialog() async {
    if (_invoiceToManage == null) return false;
    String type = 'debit';
    bool byItem = true;
    final TextEditingController productCtrl = TextEditingController();
    final TextEditingController qtyCtrl = TextEditingController();
    final TextEditingController priceCtrl = TextEditingController();
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    Product? selectedProduct;
    List<Product> productSuggestions = [];

    Future<void> fetchSuggestions(String q) async {
      productSuggestions = q.trim().isEmpty
          ? []
          : (await _db.searchProductsSmart(q.trim())).take(10).toList();
      if (mounted) setState(() {});
    }

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final double _maxH = MediaQuery.of(ctx).size.height * 0.7;
        return AlertDialog(
          title: const Text('إضافة تسوية على الفاتورة'),
          content: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: _maxH, minWidth: 320),
            child: SingleChildScrollView(
              child: StatefulBuilder(builder: (context, setLocal) {
                return Column(
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
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('بند'),
                            selected: byItem,
                            onSelected: (s) => setLocal(() => byItem = true),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('مبلغ مباشر'),
                            selected: !byItem,
                            onSelected: (s) => setLocal(() => byItem = false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (byItem) ...[
                      TextField(
                        controller: productCtrl,
                        decoration: const InputDecoration(
                          labelText: 'المنتج',
                          hintText: 'اكتب اسم المنتج للبحث',
                        ),
                        onChanged: (v) async {
                          selectedProduct = null;
                          await fetchSuggestions(v);
                          setLocal(() {});
                        },
                      ),
                      if (productSuggestions.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            itemCount: productSuggestions.length,
                            itemBuilder: (c, i) {
                              final p = productSuggestions[i];
                              return ListTile(
                                dense: true,
                                title: Text(p.name),
                                subtitle: Text('ID: ${p.id ?? ''}')
                                    ,
                                onTap: () {
                                  selectedProduct = p;
                                  productCtrl.text = p.name;
                                  productSuggestions = [];
                                  setLocal(() {});
                                },
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'الكمية'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'السعر'),
                          ),
                        ),
                      ]),
                    ] else ...[
                      TextField(
                        controller: amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'مبلغ التسوية'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
                    ),
                  ],
                );
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  double delta = 0;
                  int? productId;
                  String? productName;
                  double? qty;
                  double? price;
                  if (byItem) {
                    if (selectedProduct == null) {
                      throw 'اختر منتجاً';
                    }
                    qty = double.tryParse(qtyCtrl.text.trim());
                    price = double.tryParse(priceCtrl.text.trim());
                    if (qty == null || price == null) {
                      throw 'أدخل الكمية والسعر بشكل صحيح';
                    }
                    delta = (qty * price).toDouble();
                    productId = selectedProduct!.id;
                    productName = selectedProduct!.name;
                  } else {
                    final v = double.tryParse(amountCtrl.text.trim());
                    if (v == null) throw 'أدخل مبلغاً صحيحاً';
                    delta = v;
                  }
                  if (type == 'credit') delta = -delta.abs(); else delta = delta.abs();

                  await _db.insertInvoiceAdjustment(
                    InvoiceAdjustment(
                      invoiceId: _invoiceToManage!.id!,
                      type: type,
                      amountDelta: delta,
                      productId: productId,
                      productName: productName,
                      quantity: qty,
                      price: price,
                      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                    ),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تمت إضافة التسوية')),
                    );
                  }
                  Navigator.pop(ctx, true);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
    return result ?? false;
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
  final DatabaseService? databaseService; // جديد: للبحث الذكي

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
    this.databaseService, // جديد: للبحث الذكي
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
  late TextEditingController _idController;
  Product? _rowIdSuggestion;
  Timer? _rowIdDebounce;
  List<Product> _rowIdOptions = [];
  TextEditingController? _detailsController; // reference to details field controller

  String _formatNumber(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }

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
    // Initialize ID controller from current product if resolvable
    final prod = widget.allProducts.firstWhere(
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
    _idController = TextEditingController(text: prod.id?.toString() ?? '');
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
    _rowIdDebounce?.cancel();
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
      // لا تفرض ".00" عند الكتابة؛ استخدم تنسيق أرقام بدون كسور ثابتة
      _priceController.text = _formatNumber(_currentItem.appliedPrice);
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
                conversionFactor = (unit['quantity'] as num).toDouble();
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
      // لا تفرض ".00" أثناء التحرير؛ اظهر فواصل فقط
      _priceController.text =
          (newAppliedPrice > 0) ? _formatNumber(newAppliedPrice) : '';
      widget.onItemUpdated(_currentItem);
      // بعد اختيار نوع البيع، انتقل تلقائياً إلى السعر وافتح قائمة الأسعار
      FocusScope.of(context).requestFocus(_priceFocusNode);
      setState(() {
        _openPriceDropdown = true;
      });
    });
  }

  void _updatePrice(String value) {
    double? newPrice = double.tryParse(value.replaceAll(',', ''));
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
      // اترك المُدخل كما يكتبه المستخدم؛ المُنسق سيضيف الفواصل تلقائياً
    });
    widget.onItemUpdated(_currentItem);
  }

  void _applyProductSelection(Product prod) {
    setState(() {
      _idController.text = prod.id?.toString() ?? '';
      _rowIdSuggestion = null;
      _currentItem = _currentItem.copyWith(
        productName: prod.name,
        unit: prod.unit,
        unitPrice: prod.unitPrice,
      );
      // مزامنة خانة التفاصيل فوراً
      _detailsController?.text = prod.name;
      if (prod.unit == 'piece') {
        _currentItem = _currentItem.copyWith(saleType: 'قطعة');
      } else if (prod.unit == 'meter') {
        _currentItem = _currentItem.copyWith(saleType: 'متر');
      } else {
        _currentItem = _currentItem.copyWith(saleType: prod.unit);
      }
    });
    widget.onItemUpdated(_currentItem);
    // نقل المؤشر مباشرة إلى حقل العدد
    FocusScope.of(context).requestFocus(_quantityFocusNode);
  }

  String formatCurrency(num value) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return formatter.format(value);
  }

  @override
  Widget build(BuildContext context) {
    final Color gridBorderColor = Colors.grey.shade300;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: gridBorderColor, width: 1),
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // رقم الصف
            Expanded(
              flex: 1,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                child: Text((widget.index + 1).toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
            ),
            // المبلغ
            Expanded(
              flex: 2,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                child: widget.isViewOnly
                    ? Text(
                        formatCurrency(widget.item.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary),
                      )
                    : Text(
                        formatCurrency(_currentItem.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary),
                      ),
              ),
            ),
            // ID المادة
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                child: Builder(builder: (context) {
                if (widget.isViewOnly) {
                  final product = widget.allProducts.firstWhere(
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
                  return Text(
                    formatProductId5(product.id),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  );
                }
                return Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) async {
                    final v = textEditingValue.text.trim();
                    if (v.isEmpty) {
                      _rowIdOptions = [];
                      return const Iterable<String>.empty();
                    }
                    final db = widget.databaseService;
                    if (db == null) return const Iterable<String>.empty();
                    final suggestions = await db.searchProductsByIdPrefix(v, limit: 8);
                    _rowIdOptions = suggestions;
                    return suggestions.map((p) => p.name);
                  },
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    _idController = controller;
                    // تعبئة أولية لقيمة ID بناءً على اسم المنتج المخزن في الصف عند العودة للشاشة
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      try {
                        if (!mounted) return;
                        if ((controller.text).trim().isEmpty && _currentItem.productName.isNotEmpty) {
                          final p = widget.allProducts.firstWhere((pr) => pr.name == _currentItem.productName);
                          if ((controller.text).trim() != (p.id?.toString() ?? '')) {
                            controller.text = p.id?.toString() ?? '';
                          }
                        }
                      } catch (e) {}
                    });
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(signed: false, decimal: false),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        filled: true,
                        fillColor: Color(0xFFF3F3F3),
                        contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      ),
                      onFieldSubmitted: (val) async {
                        final id = int.tryParse(val.trim());
                        if (id == null) return onFieldSubmitted();
                        final db = widget.databaseService;
                        if (db == null) return onFieldSubmitted();
                        final prod = await db.getProductById(id);
                        if (prod != null) {
                          _applyProductSelection(prod);
                        }
                        onFieldSubmitted();
                      },
                    );
                  },
                  onSelected: (String selection) {
                    try {
                      final prod = _rowIdOptions.firstWhere((p) => p.name == selection);
                      _applyProductSelection(prod);
                      _idController.text = prod.id?.toString() ?? '';
                    } catch (e) {}
                  },
                );
              }),
              ),
            ),
            // التفاصيل (اسم المنتج)
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(widget.item.productName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium)
                    : Builder(
                        builder: (context) {
                          TextEditingController detailsController = TextEditingController(text: widget.item.productName);
                          // استخدام البحث الذكي إذا كان DatabaseService متوفر
                          if (widget.databaseService != null) {
                            return Autocomplete<String>(
                              initialValue: TextEditingValue(text: widget.item.productName),
                              optionsBuilder: (TextEditingValue textEditingValue) async {
                                if (textEditingValue.text.isEmpty) {
                                  return const Iterable<String>.empty();
                                }
                                try {
                                  // استخدام البحث الذكي
                                  final products = await widget.databaseService!.searchProductsSmart(textEditingValue.text);
                                  return products.map((p) => p.name);
                                } catch (e) {
                                  print('Error in smart search: $e');
                                  // Fallback إلى البحث العادي
                                  return widget.allProducts
                                      .map((p) => p.name)
                                      .where((option) =>
                                          option.contains(textEditingValue.text));
                                }
                              },
                              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                detailsController = controller;
                                _detailsController = controller; // keep reference to update on ID selection
                                return TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  enabled: !widget.isViewOnly,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                    isDense: true,
                                    filled: true,
                                    fillColor: Color(0xFFF3F3F3),
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
                              onSelected: (String selection) {
                                setState(() {
                                  _currentItem = _currentItem.copyWith(
                                      productName: selection);
                                  widget.onItemUpdated(_currentItem);
                                });
                                detailsController.text = selection;
                                try {
                                  final p = widget.allProducts.firstWhere(
                                      (pr) => pr.name == selection);
                                  _idController.text = p.id?.toString() ?? '';
                                } catch (e) {}
                                FocusScope.of(context)
                                    .requestFocus(_quantityFocusNode);
                              },
                            );
                          } else {
                            // Fallback إلى البحث العادي إذا لم يكن DatabaseService متوفر
                            return Autocomplete<String>(
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
                                try {
                                  final p = widget.allProducts
                                      .firstWhere((pr) => pr.name == selection);
                                  _idController.text = p.id?.toString() ?? '';
                                } catch (e) {}
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
                                    contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                    isDense: true,
                                    filled: true,
                                    fillColor: Color(0xFFF3F3F3),
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  onChanged: (val) {
                                    _currentItem =
                                        _currentItem.copyWith(productName: val);
                                  },
                                  onSubmitted: (val) {
                                    onFieldSubmitted();
                                    widget.onItemUpdated(_currentItem);
                                    try {
                                      final p = widget.allProducts
                                          .firstWhere((pr) => pr.name == val);
                                      _idController.text = p.id?.toString() ?? '';
                                    } catch (e) {}
                                    FocusScope.of(context)
                                        .requestFocus(_quantityFocusNode);
                                  },
                                );
                              },
                            );
                          }
                        },
                      ),
              ),
            ),
            // العدد
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                alignment: Alignment.center,
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
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          isDense: true,
                          filled: true,
                          fillColor: Color(0xFFF3F3F3),
                        ),
                      ),
              ),
            ),
            // نوع البيع
            Expanded(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
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
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: gridBorderColor, width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(
                        formatCurrency(widget.item.appliedPrice),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : TextFormField(
                        controller: _priceController,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        enabled: !widget.isViewOnly,
                        inputFormatters: [
                          ThousandSeparatorDecimalInputFormatter(),
                        ],
                        onChanged: _updatePrice, // الآن أصبح آمناً
                        focusNode: _priceFocusNode,
                        onFieldSubmitted: (val) {
                          widget.onItemUpdated(_currentItem);
                        },
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          isDense: true,
                          filled: true,
                          fillColor: Color(0xFFF3F3F3),
                        ),
                      ),
              ),
            ),
            // عدد الوحدات
            Expanded(
              flex: 2,
              child: Container(
                alignment: Alignment.center,
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