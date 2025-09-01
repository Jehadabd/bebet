// models/product.dart
import 'dart:convert';

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
  final String? unitCosts; // JSON string representing costs for each unit level
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
    this.unitCosts,
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
      'unit_costs': unitCosts,
      'created_at': createdAt.toIso8601String(),
      'last_modified_at': lastModifiedAt.toIso8601String(),
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      name: map['name'] as String,
      unit: map['unit'] as String,
      unitPrice: (map['unit_price'] as num).toDouble(), // More robust parsing
      costPrice: (map['cost_price'] as num?)?.toDouble(),
      piecesPerUnit: (map['pieces_per_unit'] as num?)?.toInt(), // Fix: Convert num to int safely
      lengthPerUnit: (map['length_per_unit'] as num?)?.toDouble(),
      price1: (map['price1'] as num).toDouble(),
      price2: (map['price2'] as num?)?.toDouble(),
      price3: (map['price3'] as num?)?.toDouble(),
      price4: (map['price4'] as num?)?.toDouble(),
      price5: (map['price5'] as num?)?.toDouble(),
      unitHierarchy: map['unit_hierarchy'] as String?,
      unitCosts: map['unit_costs'] as String?,
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
    String? unitCosts,
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
      unitCosts: unitCosts ?? this.unitCosts,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
    );
  }

  // Helper methods for unit hierarchy and costs
  List<Map<String, dynamic>> getUnitHierarchyList() {
    if (unitHierarchy == null || unitHierarchy!.isEmpty) return [];
    try {
      return List<Map<String, dynamic>>.from(
        jsonDecode(unitHierarchy!) as List,
      );
    } catch (e) {
      print('Error parsing unit hierarchy: $e');
      return [];
    }
  }

  Map<String, double> getUnitCostsMap() {
    if (unitCosts == null || unitCosts!.isEmpty) return {};
    try {
      // jsonDecode يرجع Map<String, dynamic>، لذا نحتاج إلى تحويل القيم إلى double
      final decodedMap = jsonDecode(unitCosts!) as Map<String, dynamic>;
      return decodedMap.map((key, value) => MapEntry(key, (value as num).toDouble()));
    } catch (e) {
      print('Error parsing unit costs: $e');
      return {};
    }
  }

  // Calculate cost for a specific unit level
  double? getCostForUnit(String unitName) {
    final costs = getUnitCostsMap();
    return costs[unitName];
  }

  // Get all available unit levels including base unit
  List<String> getAllUnitLevels() {
    final levels = [unit]; // Start with base unit
    final hierarchy = getUnitHierarchyList();
    for (var item in hierarchy) {
      if (item['unit_name'] != null) {
        levels.add(item['unit_name'] as String);
      }
    }
    return levels;
  }

  // دالة جديدة لحساب التكلفة للمنتجات المباعة بالمتر
  double? getMeterProductCost(String saleUnit) {
    if (unit != 'meter') return null;
    
    if (saleUnit == 'متر') {
      return costPrice;
    } else if (saleUnit == 'لفة' && lengthPerUnit != null) {
      // تكلفة اللفة = تكلفة المتر × عدد الأمتار في اللفة
      return (costPrice ?? 0.0) * lengthPerUnit!;
    }
    
    return null;
  }

  // دالة جديدة لبناء التسلسل الهرمي التلقائي للمنتجات المباعة بالمتر
  String? buildMeterUnitHierarchy() {
    if (unit != 'meter' || lengthPerUnit == null || lengthPerUnit! <= 0) {
      return null;
    }
    
    final hierarchy = [
      {
        'unit_name': 'لفة',
        'quantity': lengthPerUnit,
      }
    ];
    
    return jsonEncode(hierarchy);
  }

  // دالة جديدة لبناء تكلفة الوحدات التلقائية للمنتجات المباعة بالمتر
  String? buildMeterUnitCosts() {
    if (unit != 'meter' || costPrice == null || lengthPerUnit == null) {
      return null;
    }
    
    final costs = {
      'متر': costPrice,
      'لفة': costPrice! * lengthPerUnit!,
    };
    
    return jsonEncode(costs);
  }
}