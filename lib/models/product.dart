// models/product.dart
class Product {
  final int? id;
  final String name;
  final String unit; // 'piece' or 'meter'
  final double unitPrice;
  final double? costPrice;
  final int? piecesPerUnit;
  final double? lengthPerUnit;
  final double price1;
  final double? price2;
  final double? price3;
  final double? price4;
  final double? price5;
  final String? unitHierarchy; // JSON string representing the unit hierarchy
  final DateTime createdAt;
  final DateTime lastModifiedAt;

  Product({
    this.id,
    required this.name,
    required this.unit,
    required this.unitPrice,
    this.costPrice,
    this.piecesPerUnit,
    this.lengthPerUnit,
    required this.price1,
    this.price2,
    this.price3,
    this.price4,
    this.price5,
    this.unitHierarchy,
    required this.createdAt,
    required this.lastModifiedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'unit': unit,
      'unit_price': unitPrice,
      'cost_price': costPrice,
      'pieces_per_unit': piecesPerUnit,
      'length_per_unit': lengthPerUnit,
      'price1': price1,
      'price2': price2,
      'price3': price3,
      'price4': price4,
      'price5': price5,
      'unit_hierarchy': unitHierarchy,
      'created_at': createdAt.toIso8601String(),
      'last_modified_at': lastModifiedAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      name: map['name'] as String,
      unit: map['unit'] as String,
      unitPrice: map['unit_price'] as double,
      costPrice: map['cost_price'] as double?,
      piecesPerUnit: map['pieces_per_unit'] as int?,
      lengthPerUnit: map['length_per_unit'] as double?,
      price1: map['price1'] as double,
      price2: map['price2'] as double?,
      price3: map['price3'] as double?,
      price4: map['price4'] as double?,
      price5: map['price5'] as double?,
      unitHierarchy: map['unit_hierarchy'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastModifiedAt: DateTime.parse(map['last_modified_at'] as String),
    );
  }

  // Optional: Implement copyWith for easy updates
  Product copyWith({
    int? id,
    String? name,
    String? unit,
    double? unitPrice,
    double? costPrice,
    int? piecesPerUnit,
    double? lengthPerUnit,
    double? price1,
    double? price2,
    double? price3,
    double? price4,
    double? price5,
    String? unitHierarchy,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      costPrice: costPrice ?? this.costPrice,
      piecesPerUnit: piecesPerUnit ?? this.piecesPerUnit,
      lengthPerUnit: lengthPerUnit ?? this.lengthPerUnit,
      price1: price1 ?? this.price1,
      price2: price2 ?? this.price2,
      price3: price3 ?? this.price3,
      price4: price4 ?? this.price4,
      price5: price5 ?? this.price5,
      unitHierarchy: unitHierarchy ?? this.unitHierarchy,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
    );
  }
}
