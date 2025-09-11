// models/invoice_item.dart
import 'package:flutter/material.dart';

class InvoiceItem {
  int? id;
  int invoiceId; // Foreign key to Invoice
  int? productId; // Foreign key to Product
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
    String? uniqueId, // أضف هذا
  }) : this.uniqueId =
            uniqueId ?? 'item_${DateTime.now().microsecondsSinceEpoch}' {
    // Initialize controllers with initial values
    productNameController = TextEditingController(text: productName);
    quantityIndividualController =
        TextEditingController(text: (quantityIndividual ?? '').toString());
    quantityLargeUnitController =
        TextEditingController(text: (quantityLargeUnit ?? '').toString());
    appliedPriceController =
        TextEditingController(text: appliedPrice.toString());
    itemTotalController = TextEditingController(text: itemTotal.toString());
    saleTypeController = TextEditingController(text: saleType ?? '');
  }

  void initializeControllers() {
    productNameController.text = productName;
    quantityIndividualController.text = (quantityIndividual ?? '').toString();
    quantityLargeUnitController.text = (quantityLargeUnit ?? '').toString();
    appliedPriceController.text = appliedPrice.toString();
    itemTotalController.text = itemTotal.toString();
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
      'product_name': productName,
      'unit': unit,
      'unit_price': unitPrice, // Selling unit price
      'cost_price': costPrice, // Can now be null
      'actual_cost_price': actualCostPrice, // التكلفة الفعلية للمنتج في وقت البيع
      'quantity_individual': quantityIndividual,
      'quantity_large_unit': quantityLargeUnit,
      'applied_price': appliedPrice,
      'item_total': itemTotal,
      'sale_type': saleType, // أضف هذا
      'units_in_large_unit': unitsInLargeUnit,
      'unique_id': uniqueId, // أضف هذا
    };
  }

  // Extract an InvoiceItem object from a Map object
  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      id: map['id'] as int?,
      invoiceId: map['invoice_id'] ?? 0,
      productId: map['product_id'] as int?,
      productName: map['product_name'] ?? '',
      unit: map['unit'] ?? '',
      unitPrice: map['unit_price'] as double,
      costPrice: map['cost_price'] as double?,
      actualCostPrice: map['actual_cost_price'] as double?, // التكلفة الفعلية للمنتج في وقت البيع
      quantityIndividual: map['quantity_individual'] as double?,
      quantityLargeUnit: map['quantity_large_unit'] as double?,
      appliedPrice: map['applied_price'] ?? 0.0,
      itemTotal: map['item_total'] ?? 0.0,
      saleType: map['sale_type'] as String?,
      unitsInLargeUnit: map['units_in_large_unit'] as double?,
      uniqueId: map['unique_id'] ?? 'item_${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  InvoiceItem copyWith({
    int? id,
    int? invoiceId,
    int? productId,
    String? productName,
    String? unit,
    double? unitPrice,
    double? costPrice, // Made nullable in copyWith
    double? actualCostPrice, // التكلفة الفعلية للمنتج في وقت البيع
    double? quantityIndividual,
    double? quantityLargeUnit,
    double? appliedPrice,
    double? itemTotal,
    String? saleType, // أضف هذا
    double? unitsInLargeUnit,
    String? uniqueId, // أضف هذا
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      costPrice: costPrice ?? this.costPrice,
      actualCostPrice: actualCostPrice ?? this.actualCostPrice, // التكلفة الفعلية للمنتج في وقت البيع
      quantityIndividual: quantityIndividual ?? this.quantityIndividual,
      quantityLargeUnit: quantityLargeUnit ?? this.quantityLargeUnit,
      appliedPrice: appliedPrice ?? this.appliedPrice,
      itemTotal: itemTotal ?? this.itemTotal,
      saleType: saleType ?? this.saleType, // أضف هذا
      unitsInLargeUnit: unitsInLargeUnit ?? this.unitsInLargeUnit,
      uniqueId: uniqueId ?? this.uniqueId, // أضف هذا
    );
  }
}
