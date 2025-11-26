// models/supplier.dart
class Supplier {
  int? id;
  String companyName;
  String? taxNumber;
  String? phoneNumber;
  String? emailAddress;
  String? address;
  double openingBalance;
  double currentBalance;
  double totalPurchases;
  DateTime createdAt;
  DateTime lastModifiedAt;
  String? notes;

  Supplier({
    this.id,
    required this.companyName,
    this.taxNumber,
    this.phoneNumber,
    this.emailAddress,
    this.address,
    this.openingBalance = 0.0,
    double? currentBalance,
    this.totalPurchases = 0.0,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    this.notes,
  })  : currentBalance = currentBalance ?? openingBalance,
        createdAt = createdAt ?? DateTime.now(),
        lastModifiedAt = lastModifiedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_name': companyName,
      'tax_number': taxNumber,
      'phone_number': phoneNumber,
      'email_address': emailAddress,
      'address': address,
      'opening_balance': openingBalance,
      'current_balance': currentBalance,
      'total_purchases': totalPurchases,
      'created_at': createdAt.toIso8601String(),
      'last_modified_at': lastModifiedAt.toIso8601String(),
      'notes': notes,
    };
  }

  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'] as int?,
      companyName: map['company_name'] ?? '',
      taxNumber: map['tax_number'] as String?,
      phoneNumber: map['phone_number'] as String?,
      emailAddress: map['email_address'] as String?,
      address: map['address'] as String?,
      openingBalance: (map['opening_balance'] as num?)?.toDouble() ?? 0.0,
      currentBalance: (map['current_balance'] as num?)?.toDouble() ?? 0.0,
      totalPurchases: (map['total_purchases'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastModifiedAt: DateTime.parse(map['last_modified_at'] as String),
      notes: map['notes'] as String?,
    );
  }

  Supplier copyWith({
    int? id,
    String? companyName,
    String? taxNumber,
    String? phoneNumber,
    String? emailAddress,
    String? address,
    double? openingBalance,
    double? currentBalance,
    double? totalPurchases,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
    String? notes,
  }) {
    return Supplier(
      id: id ?? this.id,
      companyName: companyName ?? this.companyName,
      taxNumber: taxNumber ?? this.taxNumber,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      emailAddress: emailAddress ?? this.emailAddress,
      address: address ?? this.address,
      openingBalance: openingBalance ?? this.openingBalance,
      currentBalance: currentBalance ?? this.currentBalance,
      totalPurchases: totalPurchases ?? this.totalPurchases,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      notes: notes ?? this.notes,
    );
  }
}

class SupplierInvoice {
  int? id;
  int supplierId;
  String? invoiceNumber;
  DateTime invoiceDate;
  double totalAmount;
  double discount;
  double amountPaid;
  String currency;
  String status; // آجل/جزئي/مسدد
  String paymentType; // نقد / دين
  DateTime createdAt;
  DateTime lastModifiedAt;

  SupplierInvoice({
    this.id,
    required this.supplierId,
    this.invoiceNumber,
    required this.invoiceDate,
    required this.totalAmount,
    this.discount = 0.0,
    this.amountPaid = 0.0,
    this.currency = 'IQD',
    this.status = 'آجل',
    this.paymentType = 'دين',
    DateTime? createdAt,
    DateTime? lastModifiedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastModifiedAt = lastModifiedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier_id': supplierId,
      'invoice_number': invoiceNumber,
      'invoice_date': invoiceDate.toIso8601String(),
      'total_amount': totalAmount,
      'discount': discount,
      'amount_paid': amountPaid,
      'currency': currency,
      'status': status,
      'payment_type': paymentType,
      'created_at': createdAt.toIso8601String(),
      'last_modified_at': lastModifiedAt.toIso8601String(),
    };
  }

  factory SupplierInvoice.fromMap(Map<String, dynamic> map) {
    return SupplierInvoice(
      id: map['id'] as int?,
      supplierId: map['supplier_id'] as int,
      invoiceNumber: map['invoice_number'] as String?,
      invoiceDate: DateTime.parse(map['invoice_date'] as String),
      totalAmount: (map['total_amount'] as num).toDouble(),
      discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
      amountPaid: (map['amount_paid'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] as String? ?? 'IQD',
      status: map['status'] as String? ?? 'آجل',
      paymentType: map['payment_type'] as String? ?? 'دين',
      createdAt: DateTime.parse(map['created_at'] as String),
      lastModifiedAt: DateTime.parse(map['last_modified_at'] as String),
    );
  }
}

class SupplierReceipt {
  int? id;
  int supplierId;
  String? receiptNumber;
  DateTime receiptDate;
  double amount;
  String paymentMethod; // نقد/تحويل/شيك
  String? notes;
  DateTime createdAt;

  SupplierReceipt({
    this.id,
    required this.supplierId,
    this.receiptNumber,
    required this.receiptDate,
    required this.amount,
    this.paymentMethod = 'نقد',
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'supplier_id': supplierId,
      'receipt_number': receiptNumber,
      'receipt_date': receiptDate.toIso8601String(),
      'amount': amount,
      'payment_method': paymentMethod,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SupplierReceipt.fromMap(Map<String, dynamic> map) {
    return SupplierReceipt(
      id: map['id'] as int?,
      supplierId: map['supplier_id'] as int,
      receiptNumber: map['receipt_number'] as String?,
      receiptDate: DateTime.parse(map['receipt_date'] as String),
      amount: (map['amount'] as num).toDouble(),
      paymentMethod: map['payment_method'] as String? ?? 'نقد',
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class Attachment {
  int? id;
  String ownerType; // SupplierInvoice / SupplierReceipt / Supplier
  int ownerId;
  String filePath;
  String fileType; // pdf / image
  String? extractedText;
  double? extractionConfidence;
  DateTime uploadedAt;

  Attachment({
    this.id,
    required this.ownerType,
    required this.ownerId,
    required this.filePath,
    required this.fileType,
    this.extractedText,
    this.extractionConfidence,
    DateTime? uploadedAt,
  }) : uploadedAt = uploadedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_type': ownerType,
      'owner_id': ownerId,
      'file_path': filePath,
      'file_type': fileType,
      'extracted_text': extractedText,
      'extraction_confidence': extractionConfidence,
      'uploaded_at': uploadedAt.toIso8601String(),
    };
  }

  factory Attachment.fromMap(Map<String, dynamic> map) {
    return Attachment(
      id: map['id'] as int?,
      ownerType: map['owner_type'] as String,
      ownerId: map['owner_id'] as int,
      filePath: map['file_path'] as String,
      fileType: map['file_type'] as String,
      extractedText: map['extracted_text'] as String?,
      extractionConfidence: (map['extraction_confidence'] as num?)?.toDouble(),
      uploadedAt: DateTime.parse(map['uploaded_at'] as String),
    );
  }
}


class SupplierInvoiceItem {
  int? id;
  int invoiceId;
  int? productId; // NULL إذا كان منتج غير موجود في المخزون
  String productName;
  double quantity;
  double unitPrice; // السعر للوحدة الواحدة (التكلفة)
  double totalPrice; // الكمية × السعر
  String? unit; // الوحدة (قطعة، متر، لفة، إلخ)
  String? notes;
  DateTime createdAt;

  SupplierInvoiceItem({
    this.id,
    required this.invoiceId,
    this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.unit,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'invoice_id': invoiceId,
      'product_id': productId,
      'product_name': productName,
      'quantity': quantity,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'unit': unit,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SupplierInvoiceItem.fromMap(Map<String, dynamic> map) {
    return SupplierInvoiceItem(
      id: map['id'] as int?,
      invoiceId: map['invoice_id'] as int,
      productId: map['product_id'] as int?,
      productName: map['product_name'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      unitPrice: (map['unit_price'] as num).toDouble(),
      totalPrice: (map['total_price'] as num).toDouble(),
      unit: map['unit'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  SupplierInvoiceItem copyWith({
    int? id,
    int? invoiceId,
    int? productId,
    String? productName,
    double? quantity,
    double? unitPrice,
    double? totalPrice,
    String? unit,
    String? notes,
    DateTime? createdAt,
  }) {
    return SupplierInvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      unit: unit ?? this.unit,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}


