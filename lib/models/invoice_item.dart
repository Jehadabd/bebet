class InvoiceItem {
  int? id;
  int invoiceId; // Foreign key to Invoice
  String productName;
  String unit;
  double unitPrice; // This is the *selling* unit price from the product
  double? costPrice; // Added: The cost price of the item at the time of sale (made nullable)
  // الكميات - حقل واحد فقط يُستخدم في كل مرة
  double? quantityIndividual; // Quantity in pieces or meters
  double? quantityLargeUnit; // Quantity in cartons/packets or full meters
  // الأسعار - السعر المطبق لهذا البند المحدد
  double appliedPrice; // The price used for calculation (price1, price2, etc.)
  double itemTotal;

  InvoiceItem({
    this.id,
    required this.invoiceId,
    required this.productName,
    required this.unit,
    required this.unitPrice,
    this.quantityIndividual,
    this.quantityLargeUnit,
    required this.appliedPrice,
    required this.itemTotal,
    this.costPrice, // Made optional
  });

  // Convert an InvoiceItem object into a Map object
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_name': productName,
      'unit': unit,
      'unit_price': unitPrice, // Selling unit price
      'cost_price': costPrice, // Can now be null
      'quantity_individual': quantityIndividual,
      'quantity_large_unit': quantityLargeUnit,
      'applied_price': appliedPrice,
      'item_total': itemTotal,
    };
  }

  // Extract an InvoiceItem object from a Map object
  factory InvoiceItem.fromMap(Map<String, dynamic> map) {
    return InvoiceItem(
      id: map['id'] as int?,
      invoiceId: map['invoice_id'] ?? 0,
      productName: map['product_name'] ?? '',
      unit: map['unit'] ?? '',
      unitPrice: map['unit_price'] as double,
      costPrice: map['cost_price'] as double?, // Retrieve as double?, defaults to null if not present
      quantityIndividual: map['quantity_individual'] as double?,
      quantityLargeUnit: map['quantity_large_unit'] as double?,
      appliedPrice: map['applied_price'] ?? 0.0,
      itemTotal: map['item_total'] ?? 0.0,
    );
  }

  InvoiceItem copyWith({
    int? id,
    int? invoiceId,
    String? productName,
    String? unit,
    double? unitPrice,
    double? costPrice, // Made nullable in copyWith
    double? quantityIndividual,
    double? quantityLargeUnit,
    double? appliedPrice,
    double? itemTotal,
  }) {
    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productName: productName ?? this.productName,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      costPrice: costPrice ?? this.costPrice,
      quantityIndividual: quantityIndividual ?? this.quantityIndividual,
      quantityLargeUnit: quantityLargeUnit ?? this.quantityLargeUnit,
      appliedPrice: appliedPrice ?? this.appliedPrice,
      itemTotal: itemTotal ?? this.itemTotal,
    );
  }
} 