// widgets/editable_invoice_item_row.dart
// widgets/editable_invoice_item_row.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/invoice_item.dart';
import 'formatters.dart';
import '../models/product.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'safe_autocomplete.dart';
import '../services/database_service.dart';
import '../services/personal_pricing_service.dart'; // 👤 محرك التسعير الشخصي المستقل
import '../services/settings_manager.dart';

class EditableInvoiceItemRow extends StatefulWidget {
  final InvoiceItem item;
  final int index;
  final Function(InvoiceItem) onItemUpdated;
  final Function(String) onItemRemovedByUid;
  final List<Product> allProducts;
  final bool isViewOnly;
  final bool isPlaceholder;
  final FocusNode? detailsFocusNode;
  final FocusNode? quantityFocusNode;
  final FocusNode? priceFocusNode;
  final VoidCallback? onPriceSubmitted;
  final DatabaseService? databaseService;
  final String? currentCustomerName;
  final String? currentCustomerPhone;
  final String paymentType; // 💳 نوع الفاتورة: 'نقد' أو 'دين'

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
    this.onPriceSubmitted,
    this.databaseService,
    this.currentCustomerName,
    this.currentCustomerPhone,
    this.paymentType = 'نقد', // 💳 نوع الفاتورة الافتراضي نقد
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
  bool _isSaleTypeDropdownOpen = false;
  int _selectedSaleTypeIndex = 0;
  final GlobalKey _saleTypeDropdownKey = GlobalKey();
  OverlayEntry? _saleTypeOverlayEntry;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح: تحديد الكمية الصحيحة بناءً على نوع البيع
    // ═══════════════════════════════════════════════════════════════════════════
    final quantity = _getCorrectQuantity(widget.item);
    final price = widget.item.appliedPrice;
    
    _quantityController = TextEditingController(
      text: quantity > 0 ? NumberFormat('#,##0.##', 'en_US').format(quantity) : ''
    );
    _priceController = TextEditingController(
      text: price > 0 ? NumberFormat('#,##0.##', 'en_US').format(price) : ''
    );
    
    _detailsFocusNode = widget.detailsFocusNode ?? FocusNode();
    _quantityFocusNode = widget.quantityFocusNode ?? FocusNode();
    _priceFocusNode = widget.priceFocusNode ?? FocusNode();
    _saleTypeFocusNode = FocusNode();
    
    // 💡 تحديد النص بالكامل عند الدخول إلى حقل السعر ليسهل مسحه مباشرةً
    _priceFocusNode.addListener(_onPriceFocusChange);
  }

  void _onPriceFocusChange() {
    if (_priceFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_priceController.text.isNotEmpty) {
          _priceController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _priceController.text.length,
          );
        }
      });
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 دالة مساعدة: الحصول على الكمية الصحيحة بناءً على نوع البيع
  // ═══════════════════════════════════════════════════════════════════════════
  double _getCorrectQuantity(InvoiceItem item) {
    if (item.saleType == 'قطعة' || item.saleType == 'متر') {
      return item.quantityIndividual ?? item.quantityLargeUnit ?? 0;
    } else {
      return item.quantityLargeUnit ?? item.quantityIndividual ?? 0;
    }
  }

  // 🔧 دالة مساعدة: التحقق إذا كان نوع البيع هو الوحدة الأساسية للمنتج
  bool _isBaseUnit(String? saleType, String productName) {
    if (saleType == null || saleType.isEmpty) return true;
    
    final product = widget.allProducts.firstWhere(
      (p) => p.name == productName,
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
    
    String baseUnit = product.unit;
    if (baseUnit == 'piece') baseUnit = 'قطعة';
    if (baseUnit == 'meter') baseUnit = 'متر';
    
    return saleType == baseUnit;
  }

  // 🔧 دالة مساعدة: الحصول على قيمة unitsInLargeUnit من الـ item
  double unitsInLargeUnitValue(InvoiceItem item) {
    return item.unitsInLargeUnit ?? 1.0;
  }

  @override
  void didUpdateWidget(covariant EditableInvoiceItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح مشكلة عدم تزامن البيانات عند التعديلات المتكررة
    // ═══════════════════════════════════════════════════════════════════════════
    // إذا تغير الـ item من الخارج (مثلاً بعد إعادة جلب البيانات من قاعدة البيانات)
    // يجب تحديث الـ _currentItem والمتحكمات
    if (widget.item.uniqueId != oldWidget.item.uniqueId ||
        widget.item.quantityIndividual != oldWidget.item.quantityIndividual ||
        widget.item.quantityLargeUnit != oldWidget.item.quantityLargeUnit ||
        widget.item.appliedPrice != oldWidget.item.appliedPrice ||
        widget.item.saleType != oldWidget.item.saleType ||
        widget.item.productName != oldWidget.item.productName) {
      
      _currentItem = widget.item;
      
      // 🔧 إصلاح: استخدام الدالة المساعدة للحصول على الكمية الصحيحة
      final newQuantity = _getCorrectQuantity(widget.item);
      final newPrice = widget.item.appliedPrice;
      
      // تحديث الكمية
      if (!_quantityFocusNode.hasFocus) {
        final newQuantityText = newQuantity > 0 ? NumberFormat('#,##0.##', 'en_US').format(newQuantity) : '';
        if (_quantityController.text != newQuantityText) {
          _quantityController.text = newQuantityText;
        }
      }
      
      // تحديث السعر
      if (!_priceFocusNode.hasFocus) {
        final newPriceText = newPrice > 0 ? NumberFormat('#,##0.##', 'en_US').format(newPrice) : '';
        if (_priceController.text != newPriceText) {
          _priceController.text = newPriceText;
        }
      }
    }
  }

  @override
  void dispose() {
    _closeSaleTypeDropdown();
    _priceFocusNode.removeListener(_onPriceFocusChange); // إزالة المستمع
    _quantityController.dispose();
    _priceController.dispose();
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

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 قائمة منسدلة مخصصة لنوع البيع مع دعم لوحة المفاتيح
  // ═══════════════════════════════════════════════════════════════════════════
  void _openSaleTypeDropdownMenu() {
    if (_isSaleTypeDropdownOpen) return;
    
    final options = _getUnitValues();
    if (options.isEmpty) return;
    
    // تحديد الفهرس الحالي (أصغر وحدة = الأول)
    _selectedSaleTypeIndex = options.indexOf(_currentItem.saleType ?? options.first);
    if (_selectedSaleTypeIndex < 0) _selectedSaleTypeIndex = 0;
    
    final RenderBox? renderBox = _saleTypeDropdownKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    
    _saleTypeOverlayEntry = OverlayEntry(
      builder: (context) => _SaleTypeDropdownOverlay(
        options: options,
        selectedIndex: _selectedSaleTypeIndex,
        position: position,
        size: size,
        onSelect: (value) {
          _closeSaleTypeDropdown();
          _updateSaleType(value);
          // الانتقال للسعر بعد الاختيار
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _priceFocusNode.requestFocus();
          });
        },
        onClose: () {
          _closeSaleTypeDropdown();
        },
        onIndexChanged: (index) {
          _selectedSaleTypeIndex = index;
        },
      ),
    );
    
    Overlay.of(context).insert(_saleTypeOverlayEntry!);
    setState(() {
      _isSaleTypeDropdownOpen = true;
    });
  }
  
  void _closeSaleTypeDropdown() {
    _saleTypeOverlayEntry?.remove();
    _saleTypeOverlayEntry = null;
    if (mounted) {
      setState(() {
        _isSaleTypeDropdownOpen = false;
      });
    }
  }

  List<String> _getUnitValues() {
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

    // تحويل الوحدات القديمة
    String baseUnit = product.unit;
    if (baseUnit == 'piece') baseUnit = 'قطعة';
    if (baseUnit == 'meter') baseUnit = 'متر';

    List<String> options = [baseUnit];

    // إضافة الوحدات من التسلسل الهرمي لأي منتج (وليس فقط piece)
    if (product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
      try {
        List<dynamic> hierarchy =
            json.decode(product.unitHierarchy!.replaceAll("'", '"'));
        options.addAll(hierarchy
            .map((e) => (e['unit_name'] ?? e['name'] ?? '').toString()));
      } catch (e) {}
    }

    // إضافة الوحدة الكبيرة إذا كان هناك lengthPerUnit وبدون هرمية
    if ((product.lengthPerUnit ?? 0) > 0 && 
        !(product.unitHierarchy?.isNotEmpty ?? false)) {
      String largeUnitName;
      final unitLower = baseUnit.toLowerCase();
      if (unitLower.contains('متر') || product.unit == 'meter') largeUnitName = 'لفة';
      else if (unitLower.contains('قطع') || product.unit == 'piece') largeUnitName = 'كرتون';
      else largeUnitName = 'علبة'; // افتراضي لأي وحدة أخرى
      
      if (!options.contains(largeUnitName)) {
        options.add(largeUnitName);
      }
    }
    options = options.where((e) => e != null && e.isNotEmpty).toSet().toList();
    if (_currentItem.saleType != null &&
        _currentItem.saleType!.isNotEmpty &&
        !options.contains(_currentItem.saleType)) {
      options.add(_currentItem.saleType!);
    }
    return options;
  }

  List<DropdownMenuItem<String>> _getUnitOptions() {
    return _getUnitValues()
        .map((unit) => DropdownMenuItem(
              value: unit,
              child: Text(unit, textAlign: TextAlign.center),
            ))
        .toList();
  }

  // 🤖 دالة جلب السعر التلقائي بناءً على إعدادات التطبيق
  Future<void> _applyAutoPriceIfEnabled(String productName, String saleType) async {
    if (widget.databaseService == null || productName.isEmpty || saleType.isEmpty) return;
    
    try {
      final settings = await SettingsManager.getAppSettings();
      final mode = settings.autoPriceMode; // 0 = off, 1 = last, 3 = avg 3, 5 = avg 5, 99 = smart AI
      
      print('🔍 Auto Price: product="$productName", saleType="$saleType", mode=$mode');
      
      double? finalPrice;

      // 1. حساب السعر الافتراضي من بيانات المنتج نفسه كثابت إذا لم يتوفر تاريخ
      Product? product = widget.allProducts.firstWhere(
        (p) => p.name == productName,
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

      double defaultPrice = 0;
      if (product.id != null) {
        double basePrice = product.price1 ?? product.unitPrice;
        if (basePrice > 0) {
          // تحديد الوحدة الأساسية الفعلية
          String baseUnit = product.unit;
          if (baseUnit == 'piece') baseUnit = 'قطعة';
          if (baseUnit == 'meter') baseUnit = 'متر';
          
          bool isBaseSaleType = (saleType == baseUnit);
          double conversionFactor = 1.0;

          // البحث عن معامل التحويل في الهرمية لأي وحدة (ليس فقط piece/meter)
          if (!isBaseSaleType && product.unitHierarchy != null && product.unitHierarchy!.isNotEmpty) {
            try {
              List<dynamic> hierarchy = json.decode(product.unitHierarchy!.replaceAll("'", '"'));
              for (var unit in hierarchy) {
                if ((unit['unit_name'] ?? unit['name']) == saleType) {
                  conversionFactor = (unit['quantity'] as num).toDouble();
                  break;
                }
              }
            } catch (e) {}
          }

          // إذا لم نجد في الهرمية، جرب lengthPerUnit
          if (conversionFactor == 1.0 && !isBaseSaleType && (product.lengthPerUnit ?? 0) > 0) {
            final unitLower = baseUnit.toLowerCase();
            String expectedLarge;
            if (unitLower.contains('متر') || product.unit == 'meter') expectedLarge = 'لفة';
            else if (unitLower.contains('قطع') || product.unit == 'piece') expectedLarge = 'كرتون';
            else expectedLarge = 'علبة';

            if (saleType == expectedLarge) {
              conversionFactor = product.lengthPerUnit ?? 1.0;
            }
          }
          
          if (!isBaseSaleType && conversionFactor > 1.0) {
            defaultPrice = basePrice * conversionFactor;
          } else {
            defaultPrice = basePrice;
          }
        }
      }

      // 2. البحث في السجل التاريخي إذا كان الخيار مُفعلاً
      if (mode > 0) {
        // 🧾 حل معرّف العميل من الاسم/الهاتف (الودجت لا يحمل الـ id مباشرة)
        int? customerId;
        final custName = widget.currentCustomerName?.trim() ?? '';
        if (custName.isNotEmpty && widget.databaseService != null) {
          try {
            final custPhone = widget.currentCustomerPhone?.trim() ?? '';
            customerId = await widget.databaseService!.findCustomerIdByNameAndPhone(
              custName,
              custPhone.isNotEmpty ? custPhone : null,
            );
          } catch (_) {}
        }
        if (mode == 101 || mode == 102 || mode == 103) {
          // 👤 وضع التسعير الشخصي (101: بالتكلفة / 102: بالنسبة / 103: هايبرد)
          final personalizedPrice = await PersonalPricingService().getPersonalizedPriceForProduct(
            productName,
            saleType,
            customerId,
            mode: mode,
            paymentType: widget.paymentType,
            preloadedProduct: product.id != null ? product : null, // ⚡ تمرير المنتج من الذاكرة
          );
          if (personalizedPrice != null && personalizedPrice > 0) {
            finalPrice = personalizedPrice;
            widget.item.suggestedPrice = personalizedPrice;
            print('👤 Personalized Price: $finalPrice for "$productName" - $saleType (${widget.paymentType}, mode=$mode)');
          } else {
            print('⚠️ No personalized price found for "$productName" - $saleType, using default: $defaultPrice');
            if (defaultPrice > 0) finalPrice = defaultPrice;
          }
        } else if (mode == 99 && product.id != null && (customerId ?? 0) > 0) {
          // 🔮 وضع التسعير الذكي
          print('🔮 Using Smart Pricing for product_id=${product.id}, customer_id=$customerId');
          final smartResult = await widget.databaseService!.getSmartPriceForProduct(
            productId: product.id!,
            customerId: customerId ?? 0,
            saleType: saleType,
          );
          
          if (smartResult != null) {
            finalPrice = smartResult.price;
            print('🔮 Smart Price: ${smartResult.price} (ثقة: ${smartResult.confidence}%, المصدر: ${smartResult.source})');
          } else {
            print('⚠️ No smart price found, using default: $defaultPrice');
            if (defaultPrice > 0) finalPrice = defaultPrice;
          }
        } else if (mode == 99) {
          // التسعير الذكي غير متاح (لا يوجد product.id أو customerId)
          print('⚠️ Smart Pricing unavailable (product.id=${product.id}, customerId=$customerId), using default: $defaultPrice');
          if (defaultPrice > 0) finalPrice = defaultPrice;
        } else {
          // الأوضاع التقليدية
          final double? historicalPrice = await widget.databaseService!.getHistoricalPriceForProduct(productName, saleType, mode);
          
          print('📊 Historical Price: $historicalPrice');
          
          if (historicalPrice != null && historicalPrice > 0) {
            finalPrice = historicalPrice;
          } else {
            print('⚠️ No historical price found for "$productName" - $saleType, using default price: $defaultPrice');
            if (defaultPrice > 0) finalPrice = defaultPrice;
          }
        }
      } else {
        print('🔕 Auto Price is disabled (mode=0), using default price: $defaultPrice');
        if (defaultPrice > 0) finalPrice = defaultPrice;
      }

      // 3. تطبيق السعر النهائي
      if (finalPrice != null && finalPrice > 0) {
        if (mounted) {
          setState(() {
            _currentItem = _currentItem.copyWith(
              appliedPrice: finalPrice,
              itemTotal: _getCorrectQuantity(_currentItem) * (finalPrice ?? 0),
            );
            _priceController.text = NumberFormat('#,##0.##', 'en_US').format(finalPrice);
            widget.onItemUpdated(_currentItem);
          });
          
          // ⚡ تحديد السعر بالكامل ليسهل مسحه
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              if (_priceController.text.isNotEmpty) {
                 _priceController.selection = TextSelection(
                   baseOffset: 0,
                   extentOffset: _priceController.text.length,
                 );
              }
            }
          });
        }
      } else {
        print('⚠️ Could not resolve any price for "$productName" - $saleType');
      }
    } catch (e) {
      print('❌ Auto Price Error: $e');
    }
  }

  void _updateQuantity(String value) {
    double? newQuantity = double.tryParse(value.replaceAll(',', ''));
    if (newQuantity == null || newQuantity <= 0) return;
    
    bool isBase = _isBaseUnit(_currentItem.saleType, _currentItem.productName);
    
    setState(() {
      if (isBase) {
        _currentItem = _currentItem.copyWith(
          quantityIndividual: newQuantity,
          quantityLargeUnit: null,
          itemTotal: newQuantity * _currentItem.appliedPrice,
        );
      } else {
        _currentItem = _currentItem.copyWith(
          quantityLargeUnit: newQuantity,
          quantityIndividual: null,
          itemTotal: newQuantity * _currentItem.appliedPrice,
        );
      }
      _quantityController.text = NumberFormat('#,##0.##', 'en_US').format(newQuantity);
      _priceController.text = NumberFormat('#,##0.##', 'en_US').format(_currentItem.appliedPrice);
      widget.onItemUpdated(_currentItem);
    });
    
    // 💡 تطبيق التسعير التلقائي عند إدخال الكمية (إذا لم يكن هناك سعر)
    if (_currentItem.appliedPrice <= 0 && _currentItem.productName.isNotEmpty && _currentItem.saleType != null) {
      _applyAutoPriceIfEnabled(_currentItem.productName, _currentItem.saleType!);
    }
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

    // تحديد الوحدة الأساسية الفعلية للمنتج
    String baseUnit = product.unit;
    if (baseUnit == 'piece') baseUnit = 'قطعة';
    if (baseUnit == 'meter') baseUnit = 'متر';

    bool isNewTypeBaseUnit = (newType == baseUnit);
    double conversionFactor = 1.0;

    // البحث عن معامل التحويل في التسلسل الهرمي لأي وحدة
    if (!isNewTypeBaseUnit && product.unitHierarchy != null &&
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

    // إذا لم نجد في الهرمية، جرب lengthPerUnit
    if (conversionFactor == 1.0 && !isNewTypeBaseUnit &&
        (product.lengthPerUnit ?? 0) > 0) {
      final unitLower = baseUnit.toLowerCase();
      String expectedLarge;
      if (unitLower.contains('متر') || product.unit == 'meter') expectedLarge = 'لفة';
      else if (unitLower.contains('قطع') || product.unit == 'piece') expectedLarge = 'كرتون';
      else expectedLarge = 'علبة';

      if (newType == expectedLarge) {
        conversionFactor = product.lengthPerUnit ?? 1.0;
      }
    }

    setState(() {
      double newAppliedPrice;
      bool wasLargeUnit = (_currentItem.saleType != null &&
          !_isBaseUnit(_currentItem.saleType, _currentItem.productName));

      if (!isNewTypeBaseUnit && wasLargeUnit) {
        // التحويل بين وحدتين كبيرتين (نادر)
        newAppliedPrice = _currentItem.appliedPrice / (unitsInLargeUnitValue(_currentItem) > 0 ? unitsInLargeUnitValue(_currentItem) : 1.0) * conversionFactor;
      } else if (isNewTypeBaseUnit && wasLargeUnit) {
        // الانتقال من كبيرة → أساسية: قسم السعر على معامل التحويل
        double oldFactor = unitsInLargeUnitValue(_currentItem);
        newAppliedPrice = oldFactor > 0 ? _currentItem.appliedPrice / oldFactor : _currentItem.appliedPrice;
      } else if (!isNewTypeBaseUnit) {
        // الانتقال من أساسية → كبيرة: اضرب في معامل التحويل
        newAppliedPrice = _currentItem.appliedPrice * conversionFactor;
      } else {
        newAppliedPrice = _currentItem.appliedPrice;
      }

      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ?? 1;

      _currentItem = _currentItem.copyWith(
        saleType: newType,
        appliedPrice: newAppliedPrice,
        unitsInLargeUnit: (!isNewTypeBaseUnit && conversionFactor > 1.0) ? conversionFactor : null,
        itemTotal: quantity * newAppliedPrice,
        quantityIndividual: isNewTypeBaseUnit ? quantity : null,
        quantityLargeUnit: !isNewTypeBaseUnit ? quantity : null,
      );
      _quantityController.text = NumberFormat('#,##0.##', 'en_US').format(quantity);
      _priceController.text =
          (newAppliedPrice > 0) ? NumberFormat('#,##0.##', 'en_US').format(newAppliedPrice) : '';
      widget.onItemUpdated(_currentItem);
      // FocusScope.of(context).requestFocus(_priceFocusNode); // <-- Removed auto focus to price here to allow user to confirm with Enter
      setState(() {
        _openPriceDropdown = true;
      });
      
      // 💡 تطبيق التسعير التلقائي عند تغيير نوع البيع
      _applyAutoPriceIfEnabled(_currentItem.productName, newType).then((_) {
        // ⚡ تحديد السعر بالكامل بعد تطبيق التسعير التلقائي
        if (mounted && _priceController.text.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) {
              _priceController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _priceController.text.length,
              );
            }
          });
        }
      });
      
      // ⚡ نقل التركيز إلى حقل السعر
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _priceFocusNode.requestFocus();
        }
      });
    });
  }

  void _updatePrice(String value) {
    double? newPrice = double.tryParse(value.replaceAll(',', ''));
    if (newPrice == null || newPrice <= 0) return;
    setState(() {
      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ??
          1;
      _currentItem = _currentItem.copyWith(
        appliedPrice: newPrice,
        itemTotal: quantity * newPrice,
      );
      _priceController.text = NumberFormat('#,##0.##', 'en_US').format(newPrice);
      widget.onItemUpdated(_currentItem);
    });
  }

  String formatCurrency(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }

  // الحصول على ID المنتج من قائمة المنتجات
  int? _getProductId() {
    if (_currentItem.productName.isEmpty) return null;
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
    return product.id;
  }

  // بناء حقل إدخال بحدود مربعة
  Widget _buildSquareInputField({
    required Widget child,
    bool showBorder = true,
  }) {
    return Container(
      decoration: showBorder
          ? BoxDecoration(
              border: Border.all(color: Colors.grey.shade400, width: 1),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح: استخدام _currentItem دائماً لضمان عرض البيانات المحدثة
    // ═══════════════════════════════════════════════════════════════════════════
    final displayItem = _currentItem;
    final productId = _getProductId();
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 0.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Row(
          children: [
            // عمود التسلسل (ت)
            Expanded(
                flex: 1,
                child: Text((widget.index + 1).toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium)),
            // عمود المبلغ
            Expanded(
                flex: 2,
                child: widget.isViewOnly
                    ? Text(
                        NumberFormat('#,##0.##', 'en_US').format(displayItem.itemTotal),
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
            // عمود ID
            Expanded(
              flex: 2,
              child: _buildSquareInputField(
                child: Text(
                  productId?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            // عمود التفاصيل (اسم المنتج)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(displayItem.productName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium)
                      : Builder(
                          builder: (context) {
                            TextEditingController? detailsController;
                            return SafeAutocomplete<String>(
                              initialValue:
                                  TextEditingValue(text: widget.item.productName),
                              optionsBuilder:
                                  (TextEditingValue textEditingValue) {
                                if (textEditingValue.text == '') {
                                  return const Iterable<String>.empty();
                                }
                                return widget.allProducts
                                    .map((p) => p.name)
                                    .where((option) =>
                                        option.contains(textEditingValue.text));
                              },
                              fieldViewBuilder: (context, controller, focusNode,
                                  onFieldSubmitted) {
                                detailsController = controller;
                                return TextField(
                                  controller: controller,
                                  focusNode: _detailsFocusNode,
                                  enabled: !widget.isViewOnly,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 8),
                                    isDense: true,
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  onChanged: (val) {
                                    _currentItem =
                                        _currentItem.copyWith(productName: val);
                                  },
                                  onSubmitted: (val) {
                                    if (val.isNotEmpty && _currentItem.saleType != null) {
                                      _applyAutoPriceIfEnabled(val, _currentItem.saleType!);
                                    }
                                    onFieldSubmitted();
                                  },
                                );
                              },
                              onSelected: (String selection) {
                                // الحصول على المنتج المحدد لتعيين نوع البيع الافتراضي
                                final selectedProduct = widget.allProducts.firstWhere(
                                  (p) => p.name == selection,
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
                                
                                // تحديد نوع البيع الافتراضي (أصغر وحدة)
                                String defaultSaleType = 'قطعة';
                                if (selectedProduct.unit == 'meter') {
                                  defaultSaleType = 'متر';
                                }
                                
                                setState(() {
                                  _currentItem = _currentItem.copyWith(
                                    productName: selection,
                                    saleType: defaultSaleType,
                                    appliedPrice: selectedProduct.price1 ?? selectedProduct.unitPrice,
                                    costPrice: selectedProduct.costPrice,
                                  );
                                  widget.onItemUpdated(_currentItem);
                                });
                                detailsController?.text = selection;
                                // 💡 تطبيق التسعير التلقائي بعد اختيار المنتج مباشرةً
                                _applyAutoPriceIfEnabled(selection, defaultSaleType);
                                
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _quantityFocusNode.requestFocus();
                                });
                              },
                            );
                          },
                        ),
                ),
              ),
            ),
            // عمود العدد
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(
                          // 🔧 إصلاح: استخدام الدالة المساعدة للحصول على الكمية الصحيحة
                          NumberFormat('#,##0.##', 'en_US').format(_getCorrectQuantity(displayItem)),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : TextFormField(
                          controller: _quantityController,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            ThousandSeparatorDecimalInputFormatter(),
                          ],
                          enabled: !widget.isViewOnly,
                          onChanged: _updateQuantity,
                          focusNode: _quantityFocusNode,
                          onFieldSubmitted: (val) {
                            // عند الضغط على Enter في حقل العدد
                            // انتقل إلى حقل الوحدة وافتح القائمة المنسدلة
                            _saleTypeFocusNode.requestFocus();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _openSaleTypeDropdownMenu();
                            });
                          },
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            isDense: true,
                          ),
                        ),
                ),
              ),
            ),
            // عمود نوع البيع
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(
                          displayItem.saleType ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : Focus(
                          focusNode: _saleTypeFocusNode,
                          onFocusChange: (hasFocus) {
                            if (!hasFocus && _isSaleTypeDropdownOpen) {
                              _closeSaleTypeDropdown();
                            }
                          },
                          onKeyEvent: (node, event) {
                            if (event is! KeyDownEvent) return KeyEventResult.ignored;

                            if (event.logicalKey.keyLabel == 'Enter') {
                                // إذا القائمة مفتوحة، أغلقها وانتقل للسعر
                                if (_isSaleTypeDropdownOpen) {
                                  _closeSaleTypeDropdown();
                                }
                                _priceFocusNode.requestFocus();
                                return KeyEventResult.handled;
                            } else if (event.logicalKey.keyLabel == 'Arrow Down') {
                                // الوحدة التالية
                                final options = _getUnitValues();
                                if (options.isNotEmpty) {
                                    int currentIndex = options.indexOf(_currentItem.saleType ?? '');
                                    int nextIndex = (currentIndex + 1) % options.length;
                                    _updateSaleType(options[nextIndex]);
                                }
                                return KeyEventResult.handled;
                            } else if (event.logicalKey.keyLabel == 'Arrow Up') {
                                // الوحدة السابقة
                                final options = _getUnitValues();
                                if (options.isNotEmpty) {
                                    int currentIndex = options.indexOf(_currentItem.saleType ?? '');
                                    int prevIndex = (currentIndex - 1 + options.length) % options.length;
                                    _updateSaleType(options[prevIndex]);
                                }
                                return KeyEventResult.handled;
                            } else if (event.logicalKey.keyLabel == ' ') {
                                // فتح القائمة بالمسافة
                                _openSaleTypeDropdownMenu();
                                return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: GestureDetector(
                            key: _saleTypeDropdownKey,
                            onTap: () {
                              _saleTypeFocusNode.requestFocus();
                              _openSaleTypeDropdownMenu();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                              decoration: BoxDecoration(
                                border: _saleTypeFocusNode.hasFocus
                                    ? Border.all(color: Colors.red, width: 2)
                                    : null,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _currentItem.saleType ?? '',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: _saleTypeFocusNode.hasFocus ? Colors.red : null,
                                        fontWeight: _saleTypeFocusNode.hasFocus ? FontWeight.bold : null,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_drop_down,
                                    size: 20,
                                    color: _saleTypeFocusNode.hasFocus ? Colors.red : Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            // عمود السعر
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(
                          NumberFormat('#,##0.##', 'en_US').format(displayItem.appliedPrice),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : TextFormField(
                          controller: _priceController,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            ThousandSeparatorDecimalInputFormatter(),
                          ],
                          enabled: !widget.isViewOnly,
                          onChanged: _updatePrice,
                          focusNode: _priceFocusNode,
                          onFieldSubmitted: (val) {
                            // عند الضغط على Enter في حقل السعر، انتقل للصف التالي
                            widget.onPriceSubmitted?.call();
                            // العودة للتركيز على حقل العدد للصف الجديد أو الحالي إذا تطلب الأمر
                            // (يتم التعامل مع إنشاء صف جديد في create_invoice_screen)
                          },
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            isDense: true,
                          ),
                        ),
                ),
              ),
            ),
            // عمود عدد الوحدات - يظهر فقط إذا كان نوع البيع ليس الوحدة الأساسية
            Expanded(
              flex: 2,
              child: widget.isViewOnly
                  ? (_isBaseUnit(displayItem.saleType, displayItem.productName)
                      ? const SizedBox.shrink()
                      : Text(
                          displayItem.unitsInLargeUnit?.toStringAsFixed(0) ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium))
                  : (_isBaseUnit(_currentItem.saleType, _currentItem.productName)
                      ? const SizedBox.shrink()
                      : Text(
                          _currentItem.unitsInLargeUnit?.toStringAsFixed(0) ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium)),
            ),
            // زر الحذف
            if (!widget.isViewOnly && !widget.isPlaceholder)
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 24),
                  onPressed: () => widget.onItemRemovedByUid(widget.item.uniqueId),
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

  // دالة لاختيار نوع البيع الافتراضي (أصغر وحدة) والانتقال للسعر (لم تعد مستخدمة في onFieldSubmitted للكمية)
  void _selectDefaultSaleTypeAndMoveToPrice() {
     // ... logic kept or removed as needed, currently not called by Quantity Enter anymore ...
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 🔧 Widget مخصص للقائمة المنسدلة مع دعم لوحة المفاتيح
// ═══════════════════════════════════════════════════════════════════════════
class _SaleTypeDropdownOverlay extends StatefulWidget {
  final List<String> options;
  final int selectedIndex;
  final Offset position;
  final Size size;
  final Function(String) onSelect;
  final VoidCallback onClose;
  final Function(int) onIndexChanged;

  const _SaleTypeDropdownOverlay({
    required this.options,
    required this.selectedIndex,
    required this.position,
    required this.size,
    required this.onSelect,
    required this.onClose,
    required this.onIndexChanged,
  });

  @override
  State<_SaleTypeDropdownOverlay> createState() => _SaleTypeDropdownOverlayState();
}

class _SaleTypeDropdownOverlayState extends State<_SaleTypeDropdownOverlay> {
  late int _currentIndex;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.selectedIndex;
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // خلفية شفافة للإغلاق عند النقر خارج القائمة
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(color: Colors.transparent),
          ),
        ),
        // القائمة المنسدلة
        Positioned(
          left: widget.position.dx,
          top: widget.position.dy + widget.size.height,
          width: widget.size.width,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(4),
            child: Focus(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;

                if (event.logicalKey.keyLabel == 'Arrow Down') {
                  setState(() {
                    _currentIndex = (_currentIndex + 1) % widget.options.length;
                    widget.onIndexChanged(_currentIndex);
                  });
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Arrow Up') {
                  setState(() {
                    _currentIndex = (_currentIndex - 1 + widget.options.length) % widget.options.length;
                    widget.onIndexChanged(_currentIndex);
                  });
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Enter') {
                  widget.onSelect(widget.options[_currentIndex]);
                  return KeyEventResult.handled;
                } else if (event.logicalKey.keyLabel == 'Escape') {
                  widget.onClose();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: widget.options.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _currentIndex;
                    return InkWell(
                      onTap: () => widget.onSelect(widget.options[index]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.red.shade50 : Colors.white,
                          border: isSelected
                              ? Border.all(color: Colors.red, width: 2)
                              : null,
                        ),
                        child: Text(
                          widget.options[index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected ? Colors.red : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
