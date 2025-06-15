class Invoice {
  int? id;
  String customerName;
  String? customerPhone;
  String? customerAddress;
  String? installerName;
  DateTime invoiceDate;
  String paymentType;
  // Relationship with Invoice Items will be handled separately
  double totalAmount;
  double amountPaidOnInvoice;
  DateTime createdAt;
  DateTime lastModifiedAt;
  int? customerId;
  String status;
  double discount;

  Invoice({
    this.id,
    required this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.installerName,
    required this.invoiceDate,
    required this.paymentType,
    required this.totalAmount,
    this.amountPaidOnInvoice = 0.0,
    required this.createdAt,
    required this.lastModifiedAt,
    this.customerId,
    this.status = 'محفوظة',
    this.discount = 0.0,
  });

  // Convert an Invoice object into a Map object
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_address': customerAddress,
      'installer_name': installerName,
      'invoice_date': invoiceDate.toIso8601String(),
      'payment_type': paymentType,
      'total_amount': totalAmount,
      'amount_paid_on_invoice': amountPaidOnInvoice,
      'created_at': createdAt.toIso8601String(),
      'last_modified_at': lastModifiedAt.toIso8601String(),
      'customer_id': customerId,
      'status': status,
      'discount': discount,
    };
  }

  // Extract an Invoice object from a Map object
  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      id: map['id'],
      customerName: map['customer_name'] ?? '',
      customerPhone: map['customer_phone'],
      customerAddress: map['customer_address'],
      installerName: map['installer_name'],
      invoiceDate: DateTime.parse(map['invoice_date']),
      paymentType: map['payment_type'] ?? 'نقد',
      totalAmount: map['total_amount'] ?? 0.0,
      amountPaidOnInvoice: map['amount_paid_on_invoice'] ?? 0.0,
      createdAt: DateTime.parse(map['created_at']),
      lastModifiedAt: DateTime.parse(map['last_modified_at']),
      customerId: map['customer_id'] as int?,
      status: map['status'] ?? 'محفوظة',
      discount: map['discount'] ?? 0.0,
    );
  }

  // Optional: Implement copyWith
  Invoice copyWith({
    int? id,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? installerName,
    DateTime? invoiceDate,
    String? paymentType,
    double? totalAmount,
    double? amountPaidOnInvoice,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    int? customerId,
    String? status,
    double? discount,
  }) {
    return Invoice(
      id: id ?? this.id,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      installerName: installerName ?? this.installerName,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      paymentType: paymentType ?? this.paymentType,
      totalAmount: totalAmount ?? this.totalAmount,
      amountPaidOnInvoice: amountPaidOnInvoice ?? this.amountPaidOnInvoice,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      customerId: customerId ?? this.customerId,
      status: status ?? this.status,
      discount: discount ?? this.discount,
    );
  }
} 