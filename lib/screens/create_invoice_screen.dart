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
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';
import 'package:path_provider/path_provider.dart' as pp;
import '../services/invoice_pdf_service.dart';
import '../widgets/formatters.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/pdf_service.dart';
import 'package:alnaser/services/printing_service_platform_io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:flutter/scheduler.dart';
import '../services/pdf_header.dart';
import '../models/invoice_adjustment.dart';
// removed duplicate imports
import '../services/drive_service.dart';
import 'invoice_actions.dart';
import '../services/password_service.dart'; // Added for password protection

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

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> with InvoiceActionsMixin {
  final formKey = GlobalKey<FormState>();
  final customerNameController = TextEditingController();
  final customerPhoneController = TextEditingController();
  final customerAddressController = TextEditingController();
  final installerNameController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _quantityController = TextEditingController();
  final FocusNode _quantityFocusNode = FocusNode(); // FocusNode لحقل الكمية
  final _itemsController = TextEditingController();
  final _totalAmountController = TextEditingController();
  double? _selectedPriceLevel;
  DateTime selectedDate = DateTime.now();
  bool _useLargeUnit = false;
  String paymentType = 'نقد';
  final paidAmountController = TextEditingController();
  double discount = 0.0;
  final discountController = TextEditingController();
  int _unitSelection = 0; // 0 لـ "قطعة"، 1 لـ "كرتون/باكيت"

  String formatNumber(num value, {bool forceDecimal = false}) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }

  // kept unused helper removed; global formatProductId5 is used instead

  List<Product> _searchResults = [];
  Product? _selectedProduct;
  List<InvoiceItem> invoiceItems = [];

  final DatabaseService db = DatabaseService();
  final TextEditingController _productIdController = TextEditingController();
  Product? _productIdSuggestion;
  PrinterDevice? selectedPrinter;
  late final PrintingService printingService;
  Invoice? invoiceToManage;

  // إضافة متغيرات للحفظ التلقائي
  final storage = const FlutterSecureStorage();
  bool savedOrSuspended = false;
  Timer? debounceTimer;
  Timer? liveDebtTimer;
  
  // متغير لتتبع التغييرات غير المحفوظة
  bool hasUnsavedChanges = false;
  
  // متغير لمنع الحفظ المزدوج
  bool isSaving = false;

  // Profit Display State
  bool _isProfitVisible = false;
  double _currentInvoiceProfit = 0.0;

  void _calculateProfit() {
    double totalProfit = 0.0;
    
    // Create a map of products for faster lookup
    final Map<String, Product> productMap = {
      for (var p in (_allProductsForUnits ?? [])) p.name: p
    };

    for (var item in invoiceItems) {
      if (!_isInvoiceItemComplete(item)) continue;
      
      final double sellingPrice = item.appliedPrice;
      // Priority 1: Actual Cost Price (if specific batch/item cost is set)
      final double? acp = item.actualCostPrice;
      // Priority 4 (Fallback): Base Cost Price
      final double itemBaseCost = item.costPrice ?? 0.0;
      
      final String saleType = item.saleType ?? '';
      final double qi = item.quantityIndividual ?? 0.0;
      final double ql = item.quantityLargeUnit ?? 0.0;
      final double uilu = item.unitsInLargeUnit ?? 0.0;
      
      // Resolve product data
      final Product? product = productMap[item.productName];
      final String productUnit = product?.unit ?? '';
      final double lengthPerUnit = product?.lengthPerUnit ?? 1.0;
      final double productBaseCost = product?.costPrice ?? 0.0;
      final Map<String, double> unitCosts = product?.getUnitCostsMap() ?? {};

      final bool soldAsLargeUnit = ql > 0;
      final double saleUnitsCount = soldAsLargeUnit ? ql : qi;

      double costPerSaleUnit;
      
      if (acp != null && acp > 0) {
        // Priority 1: Use actual cost price if available
        costPerSaleUnit = acp;
      } else if (soldAsLargeUnit) {
        // Priority 2 & 3: Handle large units (Carton, Roll, etc.)
        
        // Check if specific cost exists for this sale type (e.g. cost of 'Carton')
        if (unitCosts.containsKey(saleType)) {
           costPerSaleUnit = unitCosts[saleType]!;
        } else if (productUnit == 'meter' && saleType == 'لفة') {
           // Special case for Rolls: Cost = Base Cost * Length
           costPerSaleUnit = productBaseCost * lengthPerUnit;
        } else {
           // Default: Cost = Base Cost * Units in Large Unit
           costPerSaleUnit = productBaseCost * (uilu > 0 ? uilu : 1.0);
        }
      } else {
        // Priority 4: Selling in base units (Piece, Meter)
        // Use item's stored cost if available, otherwise product's base cost
        costPerSaleUnit = itemBaseCost > 0 ? itemBaseCost : productBaseCost;
      }

      final double lineAmount = sellingPrice * saleUnitsCount;
      final double lineCostTotal = costPerSaleUnit * saleUnitsCount;
      
      totalProfit += (lineAmount - lineCostTotal);
    }
    
    // Subtract discount from profit
    _currentInvoiceProfit = totalProfit - discount;
  }

  Future<void> _toggleProfitVisibility() async {
    if (_isProfitVisible) {
      setState(() {
        _isProfitVisible = false;
      });
    } else {
      // Show password dialog
      final controller = TextEditingController();
      final shouldShow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('أدخل رمز المرور'),
          content: TextField(
            controller: controller,
            obscureText: true,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(hintText: '****'),
            onSubmitted: (value) async {
              if (await PasswordService().verifyPassword(value)) {
                Navigator.pop(context, true);
              } else {
                Navigator.pop(context, false);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                if (await PasswordService().verifyPassword(controller.text)) {
                  Navigator.pop(context, true);
                } else {
                  Navigator.pop(context, false);
                }
              },
              child: const Text('تأكيد'),
            ),
          ],
        ),
      );

      if (shouldShow == true) {
        _calculateProfit();
        setState(() {
          _isProfitVisible = true;
        });
      } else if (shouldShow == false) { // Explicit check for false (wrong password or cancel)
         ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رمز المرور غير صحيح')),
        );
      }
    }
  }
  
  // دالة لإظهار Dialog الحفظ عند الرجوع
  Future<bool> _showSaveDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('تعديلات غير محفوظة'),
          content: const Text('هل تريد حفظ التعديلات قبل الخروج؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false), // تجاهل
              child: const Text('تجاهل'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true), // حفظ
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
    return result ?? false; // إذا أغلقت Dialog، نعتبرها تجاهل
  }
  
  // دالة لاعتراض زر الرجوع
  Future<bool> _onWillPop() async {
    // إذا لم تكن في وضع تعديل أو لا توجد تغييرات غير محفوظة، اخرج مباشرة
    if (invoiceToManage == null || isViewOnly || !hasUnsavedChanges) {
      return true;
    }
    
    // إظهار Dialog الحفظ
    final shouldSave = await _showSaveDialog();
    
    if (shouldSave) {
      // حفظ الفاتورة
      final savedInvoice = await saveInvoice();
      if (savedInvoice != null) {
        // تم الحفظ بنجاح، hasUnsavedChanges تم إعادة تعيينه في _saveInvoice
        return true; // اخرج
      } else {
        return false; // فشل الحفظ، ابق في الشاشة
      }
    } else {
      // تجاهل التعديلات - إعادة تحميل البيانات الأصلية
      await _loadInvoiceItems();
      hasUnsavedChanges = false;
      return true; // اخرج
    }
  }

  bool isViewOnly = false;

  // تسوية الفاتورة - حالة الواجهة
  bool settlementPanelVisible = false; // عند اختيار "بند"
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
    if (invoiceToManage?.id != null) {
      try {
        final adjustments = await db.getInvoiceAdjustments(invoiceToManage!.id!);
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
  bool suppressSearch = false; // لمنع البحث التلقائي عند اختيار منتج
  bool quantityAutofocus = false; // للتحكم في autofocus لحقل الكمية

  // أضف متغير نوع القائمة (يظل موجوداً ولكن بدون واجهة مستخدم لتغييره)
  String _selectedListType = 'مفرد';
  final List<String> _listTypes = ['مفرد', 'جملة', 'جملة بيوت', 'بيوت', 'أخرى'];

  // 1. أضف المتغيرات أعلى الكلاس:
  List<Map<String, dynamic>> _currentUnitHierarchy = [];
  List<String> currentUnitOptions = ['قطعة'];
  String selectedUnitForItem = 'قطعة';
  
  // متغير للتحكم في السعر المخصص
  bool isCustomPrice = false;

  List<Product>? _allProductsForUnits;

  late TextEditingController loadingFeeController;

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
    db.getProductById(id).then((p) {
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
    final product = await db.getProductById(id);
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
    // توحيد مسار التهيئة مع البحث الذكي لضمان إعداد الوحدات وأنواع البيع والأسعار بشكل صحيح
    _onProductSelected(product);
    setState(() {
      _selectedPriceLevel = newPriceLevel;
      _productIdSuggestion = null;
    });
  }

  @override
  void initState() {
    super.initState();
    try {
      printingService = getPlatformPrintingService();
      invoiceToManage = widget.existingInvoice;
      isViewOnly = widget.isViewOnly;
      // تفعيل وضع التسوية: افتح واجهة إدخال أصناف جديدة، لكن اربطها بالفاتورة الأساسية
      if (widget.settlementForInvoice != null) {
        // في وضع التسوية: اجعل الشاشة قابلة للإدخال، ولا تعدّل الأصناف الأصلية
        isViewOnly = false;
        invoiceToManage = widget.settlementForInvoice; // للربط ولأخذ العميل/التاريخ إن لزم
        // نظف أي بيانات إدخال قديمة وابدأ بقائمة فارغة لتسوية جديدة
        invoiceItems.clear();
        _totalAmountController.text = '0';
        // أضف صف فارغ كبداية
        invoiceItems.add(InvoiceItem(
          invoiceId: 0,
          productName: '',
          unit: '',
          unitPrice: 0.0,
          appliedPrice: 0.0,
          itemTotal: 0.0,
          uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
        ));
      }
      loadingFeeController = TextEditingController();
      _loadAutoSavedData();
      _loadSettlementInfo(); // جلب معلومات التسويات
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          _allProductsForUnits = await db.getAllProducts();
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
      customerNameController.addListener(_onFieldChanged);
      customerPhoneController.addListener(_onFieldChanged);
      customerAddressController.addListener(_onFieldChanged);
      installerNameController.addListener(_onFieldChanged);
      paidAmountController.addListener(_onFieldChanged);
      discountController.addListener(_onFieldChanged);
      discountController.addListener(_onDiscountChanged);

      if (invoiceToManage != null) {
        customerNameController.text = invoiceToManage!.customerName;
        customerPhoneController.text = invoiceToManage!.customerPhone ?? '';
        customerAddressController.text =
            invoiceToManage!.customerAddress ?? '';
        installerNameController.text = invoiceToManage!.installerName ?? '';
        selectedDate = invoiceToManage!.invoiceDate;
        paymentType = invoiceToManage!.paymentType;
        _totalAmountController.text = invoiceToManage!.totalAmount.toString();
        paidAmountController.text =
            invoiceToManage!.amountPaidOnInvoice.toString();
        discount = invoiceToManage!.discount;
        discountController.text = discount.toStringAsFixed(2);
        // تهيئة قيمة أجور التحميل من الفاتورة الحالية
        try {
          loadingFeeController.text = formatNumber(invoiceToManage!.loadingFee);
        } catch (_) {
          loadingFeeController.text = invoiceToManage!.loadingFee.toString();
        }
        

        _loadInvoiceItems();
      } else {
        _totalAmountController.text = '0';
      }
      // تهيئة FocusNode
      _quantityFocusNode.addListener(_onFieldChanged);
      // إضافة مستمع لحقل البحث
      _productSearchController.addListener(() {
        if (suppressSearch) {
          suppressSearch = false;
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
    if (invoiceItems.isEmpty) {
      invoiceItems.add(InvoiceItem(
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
  Future<void> _loadAutoSavedData() async {
    try {
      if (isViewOnly || widget.existingInvoice != null) {
        return;
      }

      final tempData = await storage.read(key: 'temp_invoice_data');
      if (tempData == null) return;

      final data = jsonDecode(tempData);
      setState(() {
        customerNameController.text = data['customerName'] ?? '';
        customerPhoneController.text = data['customerPhone'] ?? '';
        customerAddressController.text = data['customerAddress'] ?? '';
        installerNameController.text = data['installerName'] ?? '';

        if (data['selectedDate'] != null) {
          selectedDate = DateTime.parse(data['selectedDate']);
        }

        paymentType = data['paymentType'] ?? 'نقد';
        discount = data['discount'] ?? 0;
        discountController.text = discount.toStringAsFixed(2);
        paidAmountController.text = data['paidAmount'] ?? '';

        invoiceItems = (data['invoiceItems'] as List<dynamic>).map((item) {
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

        double itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
        _totalAmountController.text = (itemsTotal + loadingFee).toStringAsFixed(2);
        
        // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
        if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
          final newTotal = (itemsTotal + loadingFee) - discount;
          paidAmountController.text = formatNumber(newTotal);
        }
      });
    } catch (e) {
      print('Error loading auto-saved data: $e');
    }
  }

  // حفظ البيانات تلقائياً
  Future<void> _autoSave() async {
    try {
      if (savedOrSuspended || isViewOnly || widget.existingInvoice != null) {
        return;
      }

      final data = {
        'customerName': customerNameController.text,
        'customerPhone': customerPhoneController.text,
        'customerAddress': customerAddressController.text,
        'installerName': installerNameController.text,
        'selectedDate': selectedDate.toIso8601String(),
        'paymentType': paymentType,
        'discount': discount,
        'paidAmount': paidAmountController.text,
        'invoiceItems': invoiceItems
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

      await storage.write(key: 'temp_invoice_data', value: jsonEncode(data));
    } catch (e) {
      print('Error in autoSave: $e');
    }
  }

  // معالج تغيير الحقول مع تأخير
  void _onFieldChanged() {
    try {
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      if (debounceTimer?.isActive ?? false) {
        debounceTimer!.cancel();
      }

      debounceTimer = Timer(const Duration(seconds: 1), _autoSave);
    } catch (e) {
      print('Error in onFieldChanged: $e');
    }
  }

  // معالج تغيير الخصم
  void _onDiscountChanged() {
    try {
      final discountText = discountController.text.replaceAll(',', '');
      final newDiscount = double.tryParse(discountText) ?? 0.0;
      discount = newDiscount;
      
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
      if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
        final currentTotalAmount = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final newTotal = currentTotalAmount - discount;
        paidAmountController.text = formatNumber(newTotal);
      }
      _calculateProfit(); // Update profit on discount change
      _scheduleLiveDebtSync();
    } catch (e) {
      print('Error in onDiscountChanged: $e');
    }
  }

  Future<void> _loadInvoiceItems() async {
    try {
      if (invoiceToManage != null && invoiceToManage!.id != null) {
        final items = await db.getInvoiceItems(invoiceToManage!.id!);
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
          invoiceItems = items;
          double itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
          final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
          _totalAmountController.text = (itemsTotal + loadingFee).toStringAsFixed(2);
        });
        _scheduleLiveDebtSync();
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
      customerNameController.removeListener(_onFieldChanged);
      customerPhoneController.removeListener(_onFieldChanged);
      customerAddressController.removeListener(_onFieldChanged);
      installerNameController.removeListener(_onFieldChanged);
      paidAmountController.removeListener(_onFieldChanged);
      discountController.removeListener(_onFieldChanged);
      discountController.removeListener(_onDiscountChanged);

      // إلغاء المؤقت
      debounceTimer?.cancel();

      // الحفظ النهائي عند إغلاق الشاشة
      if (!savedOrSuspended &&
          widget.existingInvoice == null &&
          !isViewOnly) {
        _autoSave();
      }

      customerNameController.dispose();
      customerPhoneController.dispose();
      customerAddressController.dispose();
      installerNameController.dispose();
      _productSearchController.dispose();
      _quantityController.dispose();
      _itemsController.dispose();
      _totalAmountController.dispose();
      paidAmountController.dispose();
      discountController.dispose();
      
      _quantityFocusNode.dispose(); // تنظيف FocusNode
      _searchFocusNode.dispose();
      loadingFeeController.dispose();
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
        initialDate: selectedDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        locale: const Locale('ar', 'SA'),
      );
      if (picked != null && picked != selectedDate) {
        // تحديد أن هناك تغييرات غير محفوظة
        if (invoiceToManage != null && !isViewOnly) {
          hasUnsavedChanges = true;
        }
        
        setState(() {
          selectedDate = picked;
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
      final results = await db.searchProductsSmart(query);
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
      if (paymentType == 'نقد') {
        _guardDiscount();
        final itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
        final currentTotalAmount = itemsTotal + loadingFee;
        final total = currentTotalAmount - discount;
        paidAmountController.text =
            formatNumber(total.clamp(0, double.infinity));
      }
    } catch (e) {
      print('Error in updatePaidAmountIfCash: $e');
    }
  }

  // دالة مركزية لحماية الخصم
  void _guardDiscount() {
    try {
      final itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
      final currentTotalAmount = itemsTotal + loadingFee;
      // الحد الأعلى للخصم هو أقل من نصف الإجمالي
      final maxDiscount = (currentTotalAmount / 2) - 1;
      if (discount > maxDiscount) {
        discount = maxDiscount > 0 ? maxDiscount : 0.0;
        discountController.text = formatNumber(discount);
      }
      if (discount < 0) {
        discount = 0.0;
        discountController.text = formatNumber(0);
      }
      
      // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً عند تغيير الخصم
      if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
        final newTotal = currentTotalAmount - discount;
        paidAmountController.text = formatNumber(newTotal);
      }
    } catch (e) {
      print('Error in guardDiscount: $e');
    }
  }

  // --- دالة حساب التكلفة الفعلية بناءً على نوع وحدة البيع (تعامل مع غياب/صفر unit_costs) ---
  double _calculateActualCostPrice(Product product, String saleUnit, double quantity) {
    final double baseCost = product.costPrice ?? 0.0;
    // بيع بالوحدة الأساسية
    if ((product.unit == 'piece' && saleUnit == 'قطعة') ||
        (product.unit == 'meter' && saleUnit == 'متر')) {
      return baseCost;
    }

    // جرّب قراءة تكلفة الوحدة المباعة من unit_costs; اعتبر الصفر كأنه غير متوفر
    Map<String, double> unitCosts = const {};
    try { unitCosts = product.getUnitCostsMap(); } catch (_) {}
    final double? stored = unitCosts[saleUnit];
    if (stored != null && stored > 0) {
      return stored;
    }

    // للمتر و"لفة": استخدم طول اللفة عند عدم توفر تكلفة مخزنة
    if (product.unit == 'meter' && saleUnit == 'لفة') {
      final double lengthPerUnit = product.lengthPerUnit ?? 1.0;
      return baseCost * lengthPerUnit;
    }

    // للقطعة مع هرمية: احسب المضاعف التراكمي حتى وحدة البيع المطلوبة
    if (product.unit == 'piece' && product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
      try {
        final List<dynamic> hierarchy = jsonDecode(product.unitHierarchy!) as List<dynamic>;
        double multiplier = 1.0;
        for (final level in hierarchy) {
          final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
          final double qty = (level['quantity'] is num)
              ? (level['quantity'] as num).toDouble()
              : double.tryParse(level['quantity'].toString()) ?? 1.0;
          multiplier *= qty;
          if (unitName == saleUnit) {
            return baseCost * multiplier;
          }
        }
      } catch (e) {
        print('خطأ في حساب التكلفة الهيراركية: $e');
      }
    }

    // رجوع آمن
    return baseCost;
  }

  void _addInvoiceItem() {
    try {
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      if (formKey.currentState!.validate() &&
          _selectedProduct != null &&
          _selectedPriceLevel != null) {
        final double inputQuantity =
            double.tryParse(_quantityController.text.trim().replaceAll(',', '')) ?? 0.0;
        if (inputQuantity <= 0) return;
        double finalAppliedPrice = _selectedPriceLevel!;
        double baseUnitsPerSelectedUnit = 1.0;
        // --- تعديل منطق التسعير التراكمي ---
        if (_selectedProduct!.unit == 'piece' &&
            selectedUnitForItem != 'قطعة') {
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
                if (unitName == selectedUnitForItem) {
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
                    selectedUnitForItem,
                orElse: () => {},
              );
              if (selectedHierarchyUnit.isNotEmpty) {
                baseUnitsPerSelectedUnit = double.tryParse(
                        selectedHierarchyUnit['quantity'].toString()) ??
                    1.0;
                if (isCustomPrice) {
                  finalAppliedPrice = _selectedPriceLevel!;
                } else {
                  finalAppliedPrice =
                      _selectedPriceLevel! * baseUnitsPerSelectedUnit;
                }
              }
            }
          }
        } else if (_selectedProduct!.unit == 'meter' &&
            selectedUnitForItem == 'لفة') {
          baseUnitsPerSelectedUnit = _selectedProduct!.lengthPerUnit ?? 1.0;
          if (isCustomPrice) {
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
                selectedUnitForItem == 'قطعة') ||
            (_selectedProduct!.unit == 'meter' &&
                selectedUnitForItem == 'متر')) {
          quantityIndividual = inputQuantity;
        } else {
          quantityLargeUnit = inputQuantity;
        }
        
        // حساب التكلفة الفعلية بناءً على نوع الوحدة المباعة
        final actualCostPrice = _calculateActualCostPrice(_selectedProduct!, selectedUnitForItem, inputQuantity);
        
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
          saleType: selectedUnitForItem,
          unitsInLargeUnit:
              baseUnitsPerSelectedUnit != 1.0 ? baseUnitsPerSelectedUnit : null,
        );
        setState(() {
          final existingIndex = invoiceItems.indexWhere((item) =>
              item.productName == newItem.productName &&
              item.saleType == newItem.saleType &&
              item.unit == newItem.unit);
          if (existingIndex != -1) {
            final existingItem = invoiceItems[existingIndex];
            invoiceItems[existingIndex] = existingItem.copyWith(
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
            invoiceItems.add(newItem);
          }
          _productSearchController.clear();
          _quantityController.clear();
          _selectedProduct = null;
          _selectedPriceLevel = null;
          _searchResults = [];
          selectedUnitForItem = 'قطعة';
          currentUnitOptions = ['قطعة'];
          _currentUnitHierarchy = [];
          _guardDiscount();
          _updatePaidAmountIfCash();
          _calculateProfit(); // Update profit on item addition
          
          // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
          if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
            final newTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal) - discount;
            paidAmountController.text = formatNumber(newTotal);
          }
          
          _autoSave();
          if (invoiceToManage != null &&
              invoiceToManage!.status == 'معلقة' &&
              (invoiceToManage?.isLocked ?? false)) {
            autoSaveSuspendedInvoice();
          }
          // --- معالجة الصفوف الفارغة ---
          // احذف جميع الصفوف الفارغة (غير المكتملة)
          invoiceItems.removeWhere((item) => !_isInvoiceItemComplete(item));
          // ثم أضف صف فارغ جديد إذا كان آخر صف مكتمل أو القائمة فارغة
          if (invoiceItems.isEmpty ||
              _isInvoiceItemComplete(invoiceItems.last)) {
            invoiceItems.add(InvoiceItem(
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
      if (index < 0 || index >= invoiceItems.length) return;
      _removeInvoiceItemByUid(invoiceItems[index].uniqueId);
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
      // تحديد أن هناك تغييرات غير محفوظة
      if (invoiceToManage != null && !isViewOnly) {
        hasUnsavedChanges = true;
      }
      
      setState(() {
        final index = invoiceItems.indexWhere((it) => it.uniqueId == uid);
        if (index == -1) return;
        if (index < focusNodesList.length) {
          focusNodesList[index].dispose();
          focusNodesList.removeAt(index);
        }
        invoiceItems.removeAt(index);
        _guardDiscount();
        _updatePaidAmountIfCash();
        
        // للفواتير النقدية المعدلة: تحديث المبلغ المدفوع تلقائياً
        if (invoiceToManage != null && paymentType == 'نقد' && !isViewOnly) {
          final newTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal) - discount;
          paidAmountController.text = formatNumber(newTotal);
        }
        
        _recalculateTotals();
        _calculateProfit(); // Update profit on item removal
        _autoSave();
        if (invoiceToManage != null &&
            invoiceToManage!.status == 'معلقة' &&
            (invoiceToManage?.isLocked ?? false)) {
          autoSaveSuspendedInvoice();
        }
      });
      _scheduleLiveDebtSync();
    } catch (e) {
      print('Error removing invoice item by uid: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حذف الصنف: $e')),
        );
      }
    }
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

  // حفظ في مجلد مؤقت مناسب للمشاركة (Android/Windows/macOS)
  Future<String> _saveInvoicePdfToTemp(
      pw.Document pdf, String customerName, DateTime invoiceDate) async {
    final safeCustomerName =
        customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
    final formattedDate = DateFormat('yyyy-MM-dd').format(invoiceDate);
    final fileName = '${safeCustomerName}_$formattedDate.pdf';
    final dir = await pp.getTemporaryDirectory();
    final folder = Directory(p.join(dir.path, 'invoices_share_cache'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final filePath = p.join(folder.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save(), flush: true);
    return filePath;
  }

  Future<void> _printPickingList() async {
    try {
      // تحميل الخطوط والشعار كما في خدمة PDF
      final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
      final alnaserFontData = await rootBundle.load('assets/fonts/PTBLDHAD.TTF');
      final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
      final font = pw.Font.ttf(fontData);
      final alnaserFont = pw.Font.ttf(alnaserFontData);
      final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

      // تحميل الإعدادات العامة
      final appSettings = await SettingsManager.getAppSettings();

      final doc = await InvoicePdfService.generatePickingListPdf(
        invoiceItems: invoiceItems,
        allProducts: await db.getAllProducts(),
        customerName: customerNameController.text,
        invoiceId: invoiceToManage?.id ?? 0,
        selectedDate: selectedDate,
        font: font,
        alnaserFont: alnaserFont,
        logoImage: logoImage,
        appSettings: appSettings,
      );

      // احفظ ثم افتح للطباعة على ويندوز
      final filePath = await _saveInvoicePdfToTemp(doc, customerNameController.text, selectedDate);
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '/min', '', filePath, '/p']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال قائمة التجهيز للطابعة')),
          );
        }
        return;
      }
      // على أندرويد/منصات أخرى: مشاركة/فتح الملف ليطبعه المستخدم
      final fileName = p.basename(filePath);
      await Share.shareXFiles([
        XFile(
          filePath,
          mimeType: 'application/pdf',
          name: fileName,
        )
      ], text: 'قائمة تجهيز ${customerNameController.text}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل طباعة التجهيز: $e')),
        );
      }
    }
  }

  // حوار خطوات التسوية: اختيار (إضافة/حذف) ثم (بند/مبلغ)
  Future<void> _openSettlementChoice() async {
    if (invoiceToManage == null) return;
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
      settlementPanelVisible = true;
      _settlementItems.clear();
      _settleSelectedProduct = null;
      _settleSelectedSaleType = 'قطعة';
      _settleNameCtrl.clear();
      _settleIdCtrl.clear();
      _settleQtyCtrl.clear();
      _settlePriceCtrl.clear();
      _settleUnitCtrl.clear();
      _settlementPaymentType = (invoiceToManage?.paymentType == 'دين') ? 'دين' : 'نقد';
    });
  }

  // دالة تفعيل وضع التعديل
  void _enableEditMode() {
    setState(() {
      isViewOnly = false;
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
      isViewOnly = true;
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
    if (invoiceToManage == null) return false;
    
    // حساب المبلغ المتبقي الحالي
    final remainingAmount = await _calculateRemainingAmount();
    
    // إضافة التسوية الجديدة
    final totalRefunds = remainingAmount + newRefundAmount.abs();
    
    // فحص إذا تجاوزت المبلغ المتبقي (أصبحت سالبة)
    return totalRefunds < 0;
  }

  // حساب المبلغ المتبقي بعد التسويات
  Future<double> _calculateRemainingAmount() async {
    if (invoiceToManage == null) return 0.0;
    
    // حساب إجمالي الفاتورة - totalAmount يحتوي على الخصم مسبقاً
    final afterDiscount = invoiceToManage!.totalAmount;
    
    // حساب التسويات
    final adjustments = await db.getInvoiceAdjustments(invoiceToManage!.id!);
    final cashSettlements = adjustments
        .where((adj) => adj.settlementPaymentType == 'نقد')
        .fold<double>(0.0, (sum, adj) => sum + adj.amountDelta);
    final debtSettlements = adjustments
        .where((adj) => adj.settlementPaymentType == 'دين')
        .fold<double>(0.0, (sum, adj) => sum + adj.amountDelta);
    
    // حساب المبلغ المدفوع المعروض
    final double displayedPaid;
    if (invoiceToManage!.paymentType == 'نقد' && adjustments.isNotEmpty) {
      // للفواتير النقدية مع تسويات: المبلغ المدفوع = المبلغ الأصلي + التسويات النقدية فقط
      displayedPaid = invoiceToManage!.amountPaidOnInvoice + cashSettlements;
    } else {
      // للفواتير بالدين أو الفواتير النقدية بدون تسويات
      displayedPaid = invoiceToManage!.amountPaidOnInvoice + cashSettlements;
    }
    
    // حساب المبلغ المتبقي
    return afterDiscount - displayedPaid;
  }

  Future<void> _openSettlementAmountDialog() async {
    final TextEditingController amountCtrl = TextEditingController();
    final TextEditingController noteCtrl = TextEditingController();
    // الإرجاع/الحذف لا يملك خيار (دين/نقد) ويجب أن يؤثر على الدين تلقائياً
    String paymentKind = _settlementIsDebit
        ? ((invoiceToManage?.paymentType == 'دين') ? 'دين' : 'نقد')
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
    if (ok != true || invoiceToManage == null) return;
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
    
    await db.insertInvoiceAdjustment(InvoiceAdjustment(
      invoiceId: invoiceToManage!.id!,
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
                  onPressed: () => setState(() => settlementPanelVisible = false),
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
                                  final p = await db.getProductById(id);
                                  if (p != null) {
                                    _applySettlementProductSelection(p);
                                  }
                                },
                              );
                            },
                            onSelected: (String selection) {
                              try {
                                // البحث عن المنتج المحدد وتطبيق التعبئة التلقائية
                                db.searchProductsSmart(selection).then((products) {
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
                                db.searchProductsSmart(selection).then((products) {
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
                  onPressed: isSaving ? null : _saveSettlementItems,
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
    if (invoiceToManage == null || _settlementItems.isEmpty) return;
    
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
      
      await db.insertInvoiceAdjustment(InvoiceAdjustment(
        invoiceId: invoiceToManage!.id!,
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
        settlementPanelVisible = false;
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
      final settlementItems = invoiceItems.where((it) => _isInvoiceItemComplete(it)).toList();
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
          final all = await db.getAllProducts();
          prod = all.firstWhere((p) => p.name == item.productName);
        } catch (_) {}
        await db.insertInvoiceAdjustment(
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

  Future<void> _performReset() async {
    try {
      setState(() {
        customerNameController.clear();
        customerPhoneController.clear();
        customerAddressController.clear();
        installerNameController.clear();
        _productSearchController.clear();
        _quantityController.clear();
        paidAmountController.clear();
        discountController.clear();
        discount = 0.0;
        _selectedPriceLevel = null;
        _selectedProduct = null;
        _useLargeUnit = false;
        paymentType = 'نقد';
        selectedDate = DateTime.now();
        invoiceItems.clear(); // حذف جميع الأصناف فورًا
        for (final node in focusNodesList) {
          node.dispose();
        }
        focusNodesList.clear();
        _searchResults.clear();
        _totalAmountController.text = '0';
        savedOrSuspended = false;
      });
      
      await storage.delete(key: 'temp_invoice_data');

      // بعد ثانية واحدة أضف عنصر فارغ جديد
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            invoiceItems.add(InvoiceItem(
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
      if (invoiceToManage == null || invoiceToManage!.isLocked) return;
      // تحديث الفاتورة في قاعدة البيانات
      final updatedInvoice =
          invoiceToManage!.copyWith(isLocked: true);
      await db.updateInvoice(updatedInvoice);

      // إزالة منطق خصم الراجع من رصيد المؤسس
      if (updatedInvoice.installerName != null &&
          updatedInvoice.installerName!.isNotEmpty) {
        final installer =
            await db.getInstallerByName(updatedInvoice.installerName!);
        if (installer != null) {
          final newTotal =
              (installer.totalBilledAmount - value).clamp(0.0, double.infinity);
          final updatedInstaller =
              installer.copyWith(totalBilledAmount: newTotal);
          await db.updateInstaller(updatedInstaller);
        }
      }

      // إزالة منطق دين العميل المرتبط بالراجع

      // جلب أحدث نسخة من الفاتورة بعد الحفظ
      final updatedInvoiceFromDb =
          await db.getInvoiceById(invoiceToManage!.id!);
      setState(() {
        invoiceToManage = updatedInvoiceFromDb;
        isViewOnly = true; // تفعيل وضع العرض فقط
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
      if (invoiceToManage == null ||
          invoiceToManage!.status != 'معلقة' ||
          (invoiceToManage?.isLocked ?? false)) return;
      Customer? customer;
      if (customerNameController.text.trim().isNotEmpty) {
        final customers = await db.getAllCustomers();
        try {
          customer = customers.firstWhere(
            (c) =>
                c.name.trim() == customerNameController.text.trim() &&
                (c.phone == null ||
                    c.phone!.isEmpty ||
                    customerPhoneController.text.trim().isEmpty ||
                    c.phone == customerPhoneController.text.trim()),
          );
        } catch (e) {
          customer = null;
        }
        // لا تنشئ عميل جديد هنا، فقط استخدم الموجود إن وجد
      }
      double currentTotalAmount =
          invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      // تضمين أجور التحميل في الإجمالي الفعلي عند الحفظ/التعديل
      final double loadingFee =
          double.tryParse(loadingFeeController.text.replaceAll(',', '')) ??
              0.0;
      double paid =
          double.tryParse(paidAmountController.text.replaceAll(',', '')) ??
              0.0;
      double totalAmount = (currentTotalAmount + loadingFee) - discount;
      Invoice invoice = invoiceToManage!.copyWith(
        customerName: customerNameController.text,
        customerPhone: customerPhoneController.text,
        customerAddress: customerAddressController.text,
        installerName: installerNameController.text.isEmpty
            ? null
            : installerNameController.text,
        invoiceDate: selectedDate,
        paymentType: paymentType,
        totalAmount: totalAmount,
        discount: discount,
        amountPaidOnInvoice: paid,
        loadingFee: loadingFee,
        lastModifiedAt: DateTime.now(),
        customerId: customer?.id,
        // status: 'معلقة',
        isLocked: false,
      );
      int invoiceId = invoiceToManage!.id!;
      // حذف جميع أصناف الفاتورة القديمة وإضافة الجديدة
      final oldItems = await db.getInvoiceItems(invoiceId);
      for (var oldItem in oldItems) {
        await db.deleteInvoiceItem(oldItem.id!);
      }
      for (var item in invoiceItems) {
        item.invoiceId = invoiceId;
        await db.insertInvoiceItem(item);
      }
      await context.read<AppProvider>().updateInvoice(invoice);
      setState(() {
        invoiceToManage = invoice;
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
        currentUnitOptions = [];
        if (product.unit == 'piece') {
          currentUnitOptions.add('قطعة');
          selectedUnitForItem = 'قطعة';
          if (product.unitHierarchy != null &&
              product.unitHierarchy!.isNotEmpty) {
            try {
              final List<dynamic> parsed =
                  json.decode(product.unitHierarchy!.replaceAll("'", '"'));
              _currentUnitHierarchy =
                  parsed.map((e) => Map<String, dynamic>.from(e)).toList();
              currentUnitOptions.addAll(_currentUnitHierarchy
                  .map((e) => (e['unit_name'] ?? e['name'] ?? '').toString()));
              print(
                  'DEBUG: product.unitHierarchy = \u001b[32m${product.unitHierarchy}\u001b[0m');
              print(
                  'DEBUG: currentUnitOptions = \u001b[36m$currentUnitOptions\u001b[0m');
              print(
                  'DEBUG: _currentUnitHierarchy = \u001b[35m$_currentUnitHierarchy\u001b[0m');
            } catch (e) {
              print('Error parsing unit hierarchy for ${product.name}: $e');
            }
          }
        } else if (product.unit == 'meter') {
          currentUnitOptions = ['متر'];
          selectedUnitForItem = 'متر';
          if (product.lengthPerUnit != null && product.lengthPerUnit! > 0) {
            currentUnitOptions.add('لفة');
          }
        } else {
          currentUnitOptions.add(product.unit);
          selectedUnitForItem = product.unit;
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
        suppressSearch = true;
        _productSearchController.text = product.name;
        _searchResults = [];
        quantityAutofocus = true;
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
    double itemsTotal = invoiceItems.fold(0, (sum, item) => sum + item.itemTotal);
    // إضافة رسوم التحميل إلى الإجمالي المعروض
    final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
    double total = itemsTotal + loadingFee;
    _totalAmountController.text = formatNumber(total);
    if (paymentType == 'نقد') {
      paidAmountController.text = formatNumber(total - discount);
    }
    setState(() {});
    _scheduleLiveDebtSync();
  }

  Future<void> _syncLiveDebt() async {
    try {
      // متاح فقط للفواتير الموجودة ولها عميل
      if (invoiceToManage == null || invoiceToManage!.id == null) return;
      final int invoiceId = invoiceToManage!.id!;
      int? customerId = invoiceToManage!.customerId;
      if (customerId == null) {
        // حاول إيجاد العميل بالاسم/الهاتف إذا لم يكن مرتبطاً
        if (customerNameController.text.trim().isEmpty) return;
        final customer = await db.findCustomerByNormalizedName(
          customerNameController.text.trim(),
          phone: customerPhoneController.text.trim().isEmpty
              ? null
              : customerPhoneController.text.trim(),
        );
        if (customer == null || customer.id == null) return;
        customerId = customer.id;
      }
      final int resolvedCustomerId = customerId!;

      // تحقق مما إذا كانت هناك معاملة دين موجودة بالفعل لهذه الفاتورة
      // لتجنب إنشاء معاملات مكررة
      final existingDebtTransaction = await db.getInvoiceDebtTransaction(invoiceId);
      if (existingDebtTransaction != null) {
        // تم بالفعل إنشاء معاملة دين لهذه الفاتورة، لا تقم بإنشاء أخرى
        return;
      }

      double newContribution = 0.0;
      if (paymentType == 'دين') {
        // استخدم دالة المتبقي الحالية التي تأخذ بعين الاعتبار التسويات النقدية
        final remaining = await _calculateRemainingAmount();
        newContribution = remaining.clamp(0.0, double.infinity);
      } else {
        newContribution = 0.0;
      }

      await db.setInvoiceDebtContribution(
        invoiceId: invoiceId,
        customerId: resolvedCustomerId,
        newContribution: newContribution,
        note: 'تعديل حي لمساهمة فاتورة #$invoiceId',
      );
    } catch (e) {
      // لا تُظهر خطأ للمستخدم أثناء التعديل الحي؛ فقط سجّل
      print('live debt sync error: $e');
    }
  }

  void _scheduleLiveDebtSync() {
    try {
      liveDebtTimer?.cancel();
      liveDebtTimer = Timer(const Duration(milliseconds: 500), _syncLiveDebt);
    } catch (e) {
      print('schedule live sync error: $e');
    }
  }

  Future<void> _persistPaymentTypeLightweight() async {
    try {
      if (invoiceToManage == null || invoiceToManage!.id == null) return;
      final paid = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0;
      // لا نعدّل البنود هنا؛ فقط نحفظ نوع الدفع والمبلغ المسدد والتاريخ
      final updated = invoiceToManage!.copyWith(
        paymentType: paymentType,
        amountPaidOnInvoice: paid,
        lastModifiedAt: DateTime.now(),
      );
      await db.updateInvoice(updated);
    } catch (e) {
      print('light persist payment type error: $e');
    }
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
    final displayedItems = invoiceItems;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Theme(
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
          title: Text(invoiceToManage != null 
              ? (isViewOnly ? 'عرض فاتورة' : 'تعديل فاتورة')
              : 'إنشاء فاتورة'),
          centerTitle: true,
          actions: [
            // زر جديد لإعادة التعيين
            IconButton(
              icon: const Icon(Icons.receipt),
              tooltip: 'فاتورة جديدة',
              onPressed: invoiceItems.isNotEmpty ||
                      customerNameController.text.isNotEmpty
                  ? _resetInvoice
                  : null,
            ),
            // زر الطباعة الموجود
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'طباعة الفاتورة',
              onPressed: (invoiceItems.isEmpty || isSaving) ? null : printInvoice,
            ),
            IconButton(
              icon: const Icon(Icons.print_disabled),
              tooltip: 'طباعة تجهيز (بدون أسعار)',
              onPressed: (invoiceItems.isEmpty || isSaving) ? null : _printPickingList,
            ),
            // زر المشاركة الجديد
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'مشاركة الفاتورة PDF',
              onPressed: (invoiceItems.isEmpty || isSaving) ? null : shareInvoice,
            ),
            if (invoiceToManage != null && isViewOnly) ...[
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'تعديل الفاتورة',
                onPressed: isSaving ? null : _enableEditMode,
              ),
              IconButton(
                icon: const Icon(Icons.playlist_add),
                tooltip: 'تسوية الفاتورة - تحت التطوير',
                onPressed: isSaving ? null : () {
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
            if (invoiceToManage != null && !isViewOnly) ...[
              IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'حفظ التعديلات',
                onPressed: isSaving ? null : saveInvoice,
              ),
              IconButton(
                icon: const Icon(Icons.cancel),
                tooltip: 'إلغاء التعديل',
                onPressed: isSaving ? null : _cancelEdit,
              ),
            ],
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: formKey,
            child: ListView(
              children: <Widget>[
                ListTile(
                  title: const Text('تاريخ الفاتورة'),
                  subtitle: Text(
                    '${selectedDate.year}/${selectedDate.month}/${selectedDate.day}',
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
                      child: isViewOnly
                          ? TextFormField(
                              controller: customerNameController,
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
                                final customers = await db
                                    .searchCustomers(textEditingValue.text);
                                return customers.map((c) => c.name).toSet();
                              },
                              fieldViewBuilder: (context, controller, focusNode,
                                  onFieldSubmitted) {
                                // مزامنة النص بين المتحكمين بعد انتهاء عملية البناء
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (controller.text !=
                                      customerNameController.text) {
                                    controller.text =
                                        customerNameController.text;
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
                                    customerNameController.text = val;
                                    _onFieldChanged();
                                    if (invoiceToManage != null &&
                                        invoiceToManage!.status == 'معلقة' &&
                                        (invoiceToManage?.isLocked ?? false)) {
                                      autoSaveSuspendedInvoice();
                                    }
                                  },
                                );
                              },
                              onSelected: (String selection) {
                                customerNameController.text = selection;
                                _onFieldChanged();
                              },
                            ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: customerPhoneController,
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
                        controller: customerAddressController,
                        decoration: const InputDecoration(
                            labelText: 'العنوان (اختياري)'),
                        enabled: !isViewOnly,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      flex: 2,
                      child: isViewOnly
                          ? TextFormField(
                              controller: installerNameController,
                              decoration: const InputDecoration(
                                  labelText: 'اسم المؤسس/الفني (اختياري)'),
                              enabled: false,
                            )
                          : Autocomplete<String>(
                              optionsBuilder:
                                  (TextEditingValue textEditingValue) async {
                                if (textEditingValue.text == '') {
                                  return const Iterable<String>.empty();
                                }
                                final installers = await db
                                    .searchInstallers(textEditingValue.text);
                                return installers.map((i) => i.name).toSet();
                              },
                              fieldViewBuilder: (context, controller, focusNode,
                                  onFieldSubmitted) {
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (controller.text !=
                                      installerNameController.text) {
                                    controller.text =
                                        installerNameController.text;
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
                                      labelText: 'اسم المؤسس/الفني (اختياري)'),
                                  onChanged: (val) {
                                    installerNameController.text = val;
                                    _onFieldChanged();
                                  },
                                );
                              },
                              onSelected: (String selection) {
                                installerNameController.text = selection;
                                _onFieldChanged();
                              },
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
                              enabled: !isViewOnly,
                              onFieldSubmitted: isViewOnly ? null : _handleSubmitProductId,
                              onChanged: isViewOnly ? null : _handleChangeProductId,
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
                            currentUnitOptions.length > 1) ||
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
                                children: currentUnitOptions.map((unitName) {
                                  return ChoiceChip(
                                    label: Text(
                                      unitName,
                                      style: TextStyle(
                                        color: selectedUnitForItem == unitName
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                    ),
                                    selected: selectedUnitForItem == unitName,
                                    onSelected: isViewOnly
                                        ? null
                                        : (selected) {
                                            if (selected) {
                                              setState(() {
                                                selectedUnitForItem = unitName;
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
                            autofocus: quantityAutofocus, // ربط autofocus
                            decoration: InputDecoration(
                              labelText: 'الكمية (${selectedUnitForItem})',
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
                            enabled: !isViewOnly,
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
                            onChanged: isViewOnly
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
                if (settlementPanelVisible) _buildSettlementPanel(),
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
                  itemCount: invoiceItems.length,
                  itemBuilder: (context, index) {
                    final item = invoiceItems[index];
                    while (focusNodesList.length <= index) {
                      focusNodesList.add(LineItemFocusNodes());
                    }
                    return EditableInvoiceItemRow(
                      key: ValueKey(item.uniqueId),
                      item: item,
                      index: index,
                      allProducts: _allProductsForUnits ?? [],
                      isViewOnly: isViewOnly,
                      isPlaceholder: item.productName.isEmpty,
                      databaseService: db, // إضافة DatabaseService للبحث الذكي
                    currentCustomerName: customerNameController.text.trim(),
                    currentCustomerPhone: customerPhoneController.text.trim().isEmpty ? null : customerPhoneController.text.trim(),
                      onItemUpdated: (updatedItem) {
                        // تحديد أن هناك تغييرات غير محفوظة
                        if (invoiceToManage != null && !isViewOnly) {
                          hasUnsavedChanges = true;
                        }
                        
                        setState(() {
                          final i = invoiceItems.indexWhere(
                              (it) => it.uniqueId == updatedItem.uniqueId);
                          if (i != -1) {
                            invoiceItems[i] = updatedItem;
                          }
                          _recalculateTotals();
                          _calculateProfit(); // Update profit on item update
                          final lastIndex = invoiceItems.length - 1;
                          if (i == lastIndex &&
                              _isInvoiceItemComplete(updatedItem)) {
                            invoiceItems.add(InvoiceItem(
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
        _scheduleLiveDebtSync();
                      },
                      onItemRemovedByUid: _removeInvoiceItemByUid,
                    );
                  },
                ),
                const SizedBox(height: 24.0),
                Builder(
                  builder: (context) {
                    final totalBeforeDiscount = invoiceItems.fold(
                        0.0, (sum, item) => sum + item.itemTotal);
                    final total = totalBeforeDiscount - discount;
                    double enteredPaidAmount =
                        double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0;
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

                    if (paymentType == 'نقد') {
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
                            if (paymentType == 'دين' || debtSettlements != 0)
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
                if (isViewOnly)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'نوع الدفع: ${invoiceToManage?.paymentType ?? 'غير محدد'}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (invoiceToManage?.paymentType == 'دين' &&
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
                        groupValue: paymentType,
                        onChanged: isViewOnly
                            ? null
                            : (value) {
                                // تحديد أن هناك تغييرات غير محفوظة
                                if (invoiceToManage != null && !isViewOnly) {
                                  hasUnsavedChanges = true;
                                }
                                
                                setState(() {
                                  paymentType = value!;
                                  _guardDiscount();
                                  _updatePaidAmountIfCash();
                                  _autoSave();
                                });
                _scheduleLiveDebtSync();
                _persistPaymentTypeLightweight();
                                if (invoiceToManage != null &&
                                    invoiceToManage!.status == 'معلقة' &&
                                    (invoiceToManage?.isLocked ?? false)) {
                                  autoSaveSuspendedInvoice();
                                }
                              },
                      ),
                      const Text('نقد'),
                      const SizedBox(width: 24),
                      Radio<String>(
                        value: 'دين',
                        groupValue: paymentType,
                        onChanged: isViewOnly
                            ? null
                            : (value) {
                                // تحديد أن هناك تغييرات غير محفوظة
                                if (invoiceToManage != null && !isViewOnly) {
                                  hasUnsavedChanges = true;
                                }
                                
                                setState(() {
                                  paymentType = value!;
                                  paidAmountController.text = formatNumber(0);
                                  _autoSave();
                                });
                _scheduleLiveDebtSync();
                _persistPaymentTypeLightweight();
                                if (invoiceToManage != null &&
                                    invoiceToManage!.status == 'معلقة' &&
                                    (invoiceToManage?.isLocked ?? false)) {
                                  autoSaveSuspendedInvoice();
                                }
                              },
                      ),
                      const Text('دين'),
                    ],
                  ),
                  if (paymentType == 'دين') ...[
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: paidAmountController,
                      decoration: const InputDecoration(
                          labelText: 'المبلغ المسدد (اختياري)'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        ThousandSeparatorDecimalInputFormatter(),
                      ],
                      enabled: !isViewOnly && paymentType == 'دين',
                      onChanged: (value) {
                        setState(() {
                          double enteredPaid = double.tryParse(value.replaceAll(',', '')) ?? 0.0;
                          final total = invoiceItems.fold(
                                  0.0, (sum, item) => sum + item.itemTotal) -
                              discount;
                          if (enteredPaid >= total) {
                            paidAmountController.text = formatNumber(0);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'المبلغ المسدد يجب أن يكون أقل من مبلغ الفاتورة في حالة الدين!')),
                            );
                          }
                        });
                        if (invoiceToManage != null &&
                            invoiceToManage!.status == 'معلقة' &&
                            (invoiceToManage?.isLocked ?? false)) {
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
                  onChanged: isViewOnly
                      ? null
                      : (val) {
                          setState(() {
                            double enteredDiscount =
                                double.tryParse(val.replaceAll(',', '')) ?? 0.0;
                            discount = enteredDiscount;
                            _guardDiscount();
                            _updatePaidAmountIfCash();
                          });
                          if (invoiceToManage != null &&
                              invoiceToManage!.status == 'معلقة' &&
                              (invoiceToManage?.isLocked ?? false)) {
                            autoSaveSuspendedInvoice();
                          }
                        },
                  initialValue: discount > 0 ? formatNumber(discount) : '',
                  enabled: !isViewOnly,
                ),
                const SizedBox(height: 24.0),
                // في وضع التسوية أيضاً نحتاج زر حفظ لكن يختلف المنطق
                if (!isViewOnly)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      if (widget.settlementForInvoice == null)
                        ElevatedButton.icon(
                          onPressed: isSaving ? null : saveInvoice,
                          icon: const Icon(Icons.save),
                          label: const Text('حفظ الفاتورة'),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: isSaving ? null : _saveSettlement,
                          icon: const Icon(Icons.save_as),
                          label: const Text('حفظ التسوية'),
                        ),
                    ],
                  ),

                // إضافة حقل أجور التحميل فقط إذا لم يكن العرض فقط أو الفاتورة مقفلة
                if (!isViewOnly && !(invoiceToManage?.isLocked ?? false)) ...[
                  const SizedBox(height: 16.0),
                  TextFormField(
                    controller: loadingFeeController,
                    decoration: const InputDecoration(
                      labelText: 'أجور التحميل (اختياري)',
                      hintText: 'أدخل مبلغ أجور التحميل إذا وجد',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      ThousandSeparatorDecimalInputFormatter(),
                    ],
                    onChanged: (val) {
                       // Recalculate totals when loading fee changes
                       setState(() {
                         final itemsTotal = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
                         final double loadingFee = double.tryParse(val.replaceAll(',', '')) ?? 0.0;
                         _totalAmountController.text = (itemsTotal + loadingFee).toStringAsFixed(2);
                         _guardDiscount();
                         _updatePaidAmountIfCash();
                         _calculateProfit(); // Update profit on loading fee change
                       });
                    },
                  ),
                ],
                const SizedBox(height: 24.0),
                // Protected Profit Display
                Center(
                  child: InkWell(
                    onTap: _toggleProfitVisibility,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                      decoration: BoxDecoration(
                        color: _isProfitVisible ? Colors.green.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(color: _isProfitVisible ? Colors.green : Colors.grey),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isProfitVisible ? Icons.visibility : Icons.lock,
                            color: _isProfitVisible ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isProfitVisible
                                ? 'إجمالي الربح: ${formatNumber(_currentInvoiceProfit)}'
                                : 'إجمالي الربح: ***',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isProfitVisible ? Colors.green.shade800 : Colors.grey.shade700,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24.0),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Future<bool> _showAddAdjustmentDialog() async {
    if (invoiceToManage == null) return false;
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
          : (await db.searchProductsSmart(q.trim())).take(10).toList();
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

                  await db.insertInvoiceAdjustment(
                    InvoiceAdjustment(
                      invoiceId: invoiceToManage!.id!,
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
  final String currentCustomerName; // اسم العميل الحالي لقراءة سجل أسعاره
  final String? currentCustomerPhone; // هاتف العميل لتحسين المطابقة

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
    required this.currentCustomerName,
    this.currentCustomerPhone,
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
  bool _hasShownLowPriceWarning = false;
  double? _lowestRecentPrice; // أدنى سعر خلال آخر 3 فواتير
  String? _lowestRecentInfo; // وصف مختصر: التاريخ ونوع البيع

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
    // احضر أدنى سعر تاريخي بمجرد تهيئة الصف
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLowestRecentPrice();
    });
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
    // تحديث أقل سعر تاريخي عند تغيير نوع البيع
    _fetchLowestRecentPrice();
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
      // احسب تكلفة الوحدة الفعلية من بيانات العنصر نفسه لمقارنة دقيقة
      double? effectiveCostPerUnit;
      if (_currentItem.actualCostPrice != null) {
        effectiveCostPerUnit = _currentItem.actualCostPrice;
      } else if (_currentItem.costPrice != null && quantity > 0) {
        // إذا كانت costPrice هي تكلفة إجمالية للسطر، حوّلها إلى تكلفة للوحدة
        effectiveCostPerUnit = _currentItem.costPrice! / quantity;
      }
      const double eps = 1e-6;
      // تحذير فقط إذا كان السعر المدخل أقل من تكلفة الوحدة الفعلية (بدون مقارنته بسعر الوحدة البيعية)
      if (effectiveCostPerUnit != null && (newPrice + eps) < effectiveCostPerUnit) {
        if (!_hasShownLowPriceWarning) {
          _hasShownLowPriceWarning = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('⚠️ السعر المدخل أقل من سعر التكلفة!'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        });
          // إعادة تعيين السماح بعرض التحذير مرة أخرى بعد التعديل التالي إذا لزم
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) setState(() => _hasShownLowPriceWarning = false);
        });
        }
      }
      // الحساب: المبلغ = السعر * العدد مباشرة بغض النظر عن نوع الوحدة
      _currentItem = _currentItem.copyWith(
        appliedPrice: newPrice,
        itemTotal: quantity * newPrice,
      );
      // اترك المُدخل كما يكتبه المستخدم؛ المُنسق سيضيف الفواصل تلقائياً
    });
    widget.onItemUpdated(_currentItem);
    // تحديث الأيقونة حسب السعر الحالي
    _fetchLowestRecentPrice();
  }

  Future<void> _fetchLowestRecentPrice() async {
    try {
      final db = widget.databaseService;
      if (db == null) return;
      final String customer = widget.currentCustomerName.trim();
      if (customer.isEmpty) return;
      final String productName = _currentItem.productName.trim();
      if (productName.isEmpty) return;
      final results = await db.getLastNPricesForCustomerProduct(
        customerName: customer,
        customerPhone: widget.currentCustomerPhone,
        productName: productName,
        limit: 3,
        saleType: _currentItem.saleType,
      );
      if (results.isEmpty) {
        setState(() {
          _lowestRecentPrice = null;
          _lowestRecentInfo = null;
        });
        return;
      }
      double minPrice = results
          .map((r) => (r['applied_price'] as num).toDouble())
          .reduce((a, b) => a < b ? a : b);
      final minRow = results.firstWhere(
          (r) => (r['applied_price'] as num).toDouble() == minPrice,
          orElse: () => results.first);
      final String dateStr = (minRow['invoice_date'] as String?) ?? '';
      final int? invoiceId = (minRow['invoice_id'] as int?);
      final String saleType = (minRow['sale_type'] as String?) ?? (_currentItem.saleType ?? '');
      setState(() {
        _lowestRecentPrice = minPrice;
        final String d = dateStr.isNotEmpty ? dateStr : '';
        final String idText = invoiceId != null ? 'فاتورة #$invoiceId' : '';
        _lowestRecentInfo = [idText, d, saleType].where((s) => s != null && s.toString().trim().isNotEmpty).join(' — ');
      });
    } catch (_) {
      // ignore أخطاء الاستعلام البسيطة
    }
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
    // بعد اختيار المنتج، حدّث أقل سعر تاريخي لعرض الأيقونة إن لزم
    _fetchLowestRecentPrice();
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
            // أيقونة التنبيه في أقصى اليمين
            SizedBox(
              width: 40,
              child: Builder(builder: (context) {
                final bool showIcon = _lowestRecentPrice != null &&
                    !widget.isViewOnly &&
                    _currentItem.appliedPrice > (_lowestRecentPrice ?? 0);
                if (!showIcon) return const SizedBox.shrink();
                return Tooltip(
                  message:
                      'سعر أقل سابقاً: ${formatCurrency(_lowestRecentPrice!)}\n${_lowestRecentInfo ?? ''}',
                  preferBelow: false,
                  child: Icon(Icons.error_outline,
                      color: Colors.orange.shade700, size: 22),
                );
              }),
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
