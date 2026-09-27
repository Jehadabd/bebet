// models/invoice_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class InvoiceItem {
  // دالة تنسيق الأرقام مع فواصل كل ثلاث خانات
  static String _formatNumber(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }
  int? id;
  int invoiceId; // Foreign key to Invoice
  int? productId; // Foreign key to Product
  String? productSyncUuid; // 🔄 معرّف مزامنة المنتج (لمطابقته عبر الأجهزة)
  String productName;
  String unit;
  double unitPrice; // This is the *selling* unit price from the product
  double? costPrice; // Added: The cost price of the item at the time of sale (made nullable)
  double? actualCostPrice; // التكلفة الفعلية للمنتج في وقت البيع - للحسابات الدقيقة
  // الكميات - حقل واحد فقط يُستخدم في كل مرة
  double? quantityIndividual; // Quantity in pieces or meters
  double? quantityLargeUnit; // Quantity in cartons/packets or full meters
  // الأسعار - السعر المطبق لهذا البند المحدد
  double appliedPrice;
  double itemTotal;
  String? saleType; // نوع البيع بالحرف العربي: ق/ك/م/ل
  double? unitsInLargeUnit; // عدد القطع في الكرتون أو الأمتار في اللفة (للوحدة الكبيرة)
  double? suggestedPrice; // ⚡ السعر الذي اقترحه محرك التسعير قبل أي تعديل يدوي

  // --- أضف هذا الحقل ---
  final String uniqueId;

  // Controllers for UI binding
  late TextEditingController productNameController;
  late TextEditingController quantityIndividualController;
  late TextEditingController quantityLargeUnitController;
  late TextEditingController appliedPriceController;
  late TextEditingController itemTotalController;
  late TextEditingController saleTypeController;

  InvoiceItem({
    this.id,
    required this.invoiceId,
    this.productId,
    this.productSyncUuid,
    required this.productName,
    required this.unit,
    required this.unitPrice,
    this.quantityIndividual,
    this.quantityLargeUnit,
    required this.appliedPrice,
    required this.itemTotal,
    this.costPrice, // Made optional
    this.actualCostPrice, // التكلفة الفعلية للمنتج في وقت البيع
    this.saleType, // أضف هذا
    this.unitsInLargeUnit,
    this.suggestedPrice, // ⚡ السعر المقترح من المحرك
    String? uniqueId, // أضف هذا
  }) : this.uniqueId =
            uniqueId ?? 'item_${DateTime.now().microsecondsSinceEpoch}' {
    // Initialize controllers with initial values - مع تنسيق الأرقام بفواصل
    productNameController = TextEditingController(text: productName);
    quantityIndividualController =
        TextEditingController(text: quantityIndividual != null ? _formatNumber(quantityIndividual!) : '');
    quantityLargeUnitController =
        TextEditingController(text: quantityLargeUnit != null ? _formatNumber(quantityLargeUnit!) : '');
    appliedPriceController =
        TextEditingController(text: _formatNumber(appliedPrice));
    itemTotalController = TextEditingController(text: _formatNumber(itemTotal));
    saleTypeController = TextEditingController(text: saleType ?? '');
  }

  void initializeControllers() {
    productNameController.text = productName;
    quantityIndividualController.text = quantityIndividual != null ? _formatNumber(quantityIndividual!) : '';
    quantityLargeUnitController.text = quantityLargeUnit != null ? _formatNumber(quantityLargeUnit!) : '';
    appliedPriceController.text = _formatNumber(appliedPrice);
    itemTotalController.text = _formatNumber(itemTotal);
    saleTypeController.text = saleType ?? '';
  }

  void disposeControllers() {
    productNameController.dispose();
    quantityIndividualController.dispose();
    quantityLargeUnitController.dispose();
    appliedPriceController.dispose();
    itemTotalController.dispose();
    saleTypeController.dispose();
  }

  // Convert an InvoiceItem object into a Map object
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'product_sync_uuid': productSyncUuid,
      'product_name': productName,
      'unit': unit,
      'unit_price': unitPrice, // Selling unit price
      'cost_price': costPrice, // Can now be null
      'actual_cost_price': actualCostPrice, // التكلفة الفعلية للمنتج في وقت البيع
      'quantity_individual': quantityIndividual,
      'quantity_large_unit': quantityLargeUnit,
      'applied_price': appliedPrice,
      'suggested_price': suggestedPrice, // ⚡ السعر المقترح
      'item_total': itemTotal,
      'sale_type': saleType, // أضف هذا
      'units_in_large_unit': unitsInLargeUnit,
      'unique_id': uniqueId, // أضف هذا
    };
  }

  // Extract an InvoiceItem object from a Map object
  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح: تنظيف البيانات - استخدام الكمية الصحيحة بناءً على نوع البيع
    // يدعم الآن: قطعة/متر القياسية + أي وحدة مخصصة
    //
    // المبدأ: نستخدم مؤشرات متعددة لتحديد الوحدة الأساسية vs الكبيرة:
    //   1. unitsInLargeUnit > 1 + saleType غير أساسي معروف → وحدة كبيرة
    //   2. quantityIndividual != null → عادةً وحدة أساسية
    //   3. مقارنة saleType مع baseUnit (piece→قطعة, meter→متر)
    // ═══════════════════════════════════════════════════════════════════════════
    final String? saleType = map['sale_type'] as String?;
    double? quantityIndividual = map['quantity_individual'] as double?;
    double? quantityLargeUnit = map['quantity_large_unit'] as double?;
    final double? unitsInLargeUnit = map['units_in_large_unit'] as double?;

    // تحديد الوحدة الأساسية من حقل unit (piece→قطعة, meter→متر)
    final String rawUnit = map['unit'] as String? ?? '';
    String baseUnit = rawUnit;
    if (baseUnit == 'piece') baseUnit = 'قطعة';
    if (baseUnit == 'meter') baseUnit = 'متر';

    // 🔑 المنطق المحسّن للكشف عن الوحدة الأساسية
    // الأولوية: نثق بقيمة quantity_individual إذا كانت محددة (_updateSaleType يضبطها)
    
    // المؤشر الأقوى: قيمة محددة في quantityIndividual ← وحدة أساسية بغض النظر عن أي شيء
    final bool qtyIndExplicitlySet = (quantityIndividual != null && quantityIndividual! > 0);
    
    bool isBaseSaleType;
    
    final bool hasValidUnitsInLargeUnit = (unitsInLargeUnit != null && unitsInLargeUnit! > 1);
    final bool saleTypeMatchesBase = (saleType == baseUnit);
    final bool isKnownBaseUnit = (saleType == 'قطعة' || saleType == 'متر' || saleType == 'piece');
    
    if (qtyIndExplicitlySet) {
      // 🔑 quantityIndividual له قيمة ← وحدة أساسية (المؤشر الأكثر موثوقية)
      isBaseSaleType = true;
    } else if (!hasValidUnitsInLargeUnit) {
      // بدون تحويل وحدات → دائماً وحدة أساسية
      isBaseSaleType = true;
    } else if (isKnownBaseUnit) {
      // saleType هو قطعة أو متر → وحدة أساسية
      isBaseSaleType = true;
    } else if (saleTypeMatchesBase) {
      // saleType يطابق baseUnit (أياً كانا) → وحدة أساسية
      isBaseSaleType = true;
    } else if (saleType == null || saleType!.isEmpty) {
      // saleType فارغ → اعتبره وحدة أساسية
      isBaseSaleType = true;
    } else {
      // باقي الحالات: unitsInLargeUnit > 1 و saleType ≠ baseUnit ولا qtyIndividual → وحدة كبيرة
      isBaseSaleType = false;
    }

    if (isBaseSaleType) {
      // للوحدات الأساسية: استخدم quantityIndividual
      if (quantityIndividual == null && quantityLargeUnit != null) {
        quantityIndividual = quantityLargeUnit;
      }
      quantityLargeUnit = null; // مسح القيمة الأخرى
    } else {
      // للوحدات الكبيرة (لفة، كرتون، Q، jjj، إلخ): استخدم quantityLargeUnit
      if (quantityLargeUnit == null && quantityIndividual != null) {
        quantityLargeUnit = quantityIndividual;
      }
      quantityIndividual = null; // مسح القيمة الأخرى
    }

    return InvoiceItem(
      id: map['id'] as int?,
      invoiceId: map['invoice_id'] ?? 0,
      productId: map['product_id'] as int?,
      productSyncUuid: map['product_sync_uuid'] as String?,
      productName: map['product_name'] ?? '',
      unit: map['unit'] ?? '',
      unitPrice: (map['unit_price'] as num).toDouble(),
      costPrice: (map['cost_price'] as num?)?.toDouble(),
      actualCostPrice: (map['actual_cost_price'] as num?)?.toDouble(),
      quantityIndividual: quantityIndividual,
      quantityLargeUnit: quantityLargeUnit,
      appliedPrice: (map['applied_price'] as num?)?.toDouble() ?? 0.0,
      suggestedPrice: (map['suggested_price'] as num?)?.toDouble(),
      itemTotal: (map['item_total'] as num?)?.toDouble() ?? 0.0,
      saleType: saleType,
      unitsInLargeUnit: unitsInLargeUnit,
      uniqueId: map['unique_id'] ?? 'item_${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 إصلاح: استخدام Object? sentinel pattern للسماح بتمرير null بشكل صريح
  // ═══════════════════════════════════════════════════════════════════════════
  static const _sentinel = Object();
  
  InvoiceItem copyWith({
    int? id,
    int? invoiceId,
    int? productId,
    String? productSyncUuid,
    String? productName,
    String? unit,
    double? unitPrice,
    double? costPrice,
    double? actualCostPrice,
    Object? quantityIndividual = _sentinel, // استخدام Object? للسماح بـ null
    Object? quantityLargeUnit = _sentinel,  // استخدام Object? للسماح بـ null
    double? appliedPrice,
    double? suggestedPrice,
    double? itemTotal,
    String? saleType,
    double? unitsInLargeUnit,
    String? uniqueId,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      productSyncUuid: productSyncUuid ?? this.productSyncUuid,
      productName: productName ?? this.productName,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      costPrice: costPrice ?? this.costPrice,
      actualCostPrice: actualCostPrice ?? this.actualCostPrice,
      // 🔧 إصلاح: السماح بتمرير null لمسح القيمة القديمة
      quantityIndividual: quantityIndividual == _sentinel 
          ? this.quantityIndividual 
          : quantityIndividual as double?,
      quantityLargeUnit: quantityLargeUnit == _sentinel 
          ? this.quantityLargeUnit 
          : quantityLargeUnit as double?,
      appliedPrice: appliedPrice ?? this.appliedPrice,
      suggestedPrice: suggestedPrice ?? this.suggestedPrice,
      itemTotal: itemTotal ?? this.itemTotal,
      saleType: saleType ?? this.saleType,
      unitsInLargeUnit: unitsInLargeUnit ?? this.unitsInLargeUnit,
      uniqueId: uniqueId ?? this.uniqueId,
    );
  }
}
