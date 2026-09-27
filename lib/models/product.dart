// models/product.dart
import 'dart:convert';

class Product {
  final int? id;
  final String name;
  final String unit; // وحدة البيع الأساسية (نص حر: قطعة، متر، كيلو، علبة، إلخ)
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
  final DateTime? costPriceLastModifiedAt;
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
    this.costPriceLastModifiedAt,
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
      'cost_price_last_modified_at': costPriceLastModifiedAt?.toIso8601String(),
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
      costPriceLastModifiedAt: map['cost_price_last_modified_at'] != null 
          ? DateTime.parse(map['cost_price_last_modified_at'] as String) 
          : null,
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
    DateTime? costPriceLastModifiedAt,
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
      costPriceLastModifiedAt: costPriceLastModifiedAt ?? this.costPriceLastModifiedAt,
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

  // دالة عامة لحساب التكلفة لأي وحدة بيع
  double? getProductCostForUnit(String saleUnit) {
    String baseUnit = unit;
    if (baseUnit == 'piece') baseUnit = 'قطعة';
    if (baseUnit == 'meter') baseUnit = 'متر';
    String normSaleUnit = saleUnit;
    if (normSaleUnit == 'piece') normSaleUnit = 'قطعة';
    if (normSaleUnit == 'meter') normSaleUnit = 'متر';

    // إذا كان نوع البيع هو الوحدة الأساسية
    if (saleUnit == unit || normSaleUnit == baseUnit) {
      return costPrice;
    }

    final costs = getUnitCostsMap();

    // البحث في تكاليف الوحدات المحفوظة
    if (costs.containsKey(saleUnit)) {
      return costs[saleUnit];
    }
    if (costs.containsKey(normSaleUnit)) {
      return costs[normSaleUnit];
    }

    // البحث في التسلسل الهرمي
    final hierarchy = getUnitHierarchyList();
    double? multiplier;
    for (var item in hierarchy) {
      if (item['unit_name'] == saleUnit || item['unit_name'] == normSaleUnit) {
        multiplier = (item['quantity'] as num?)?.toDouble();
        break;
      }
    }

    if (multiplier != null && costPrice != null) {
      return costPrice! * multiplier;
    }

    // إذا كان هناك lengthPerUnit (مثل المتر واللفة أو القطعة والكرتون)
    if (lengthPerUnit != null && lengthPerUnit! > 0 && costPrice != null) {
      final unitLower = unit.toLowerCase();
      String expectedLarge = 'علبة';
      if (unitLower.contains('متر') || unit == 'meter') expectedLarge = 'لفة';
      else if (unitLower.contains('قطع') || unit == 'piece') expectedLarge = 'كرتون';

      if (saleUnit == expectedLarge || normSaleUnit == expectedLarge) {
        return costPrice! * lengthPerUnit!;
      }
    }

    return costPrice;
  }

  /// 📦 الحصول على معامل التحويل لوحدة معينة بالنسبة للوحدة الأساسية (مثلاً: باكية = 10، كرتون = 100)
  double getConversionFactorForUnit(String saleUnit) {
    String baseUnit = unit;
    if (baseUnit == 'piece') baseUnit = 'قطعة';
    if (baseUnit == 'meter') baseUnit = 'متر';
    String normSaleUnit = saleUnit;
    if (normSaleUnit == 'piece') normSaleUnit = 'قطعة';
    if (normSaleUnit == 'meter') normSaleUnit = 'متر';

    if (saleUnit == unit || normSaleUnit == baseUnit) {
      return 1.0;
    }

    final hierarchy = getUnitHierarchyList();
    for (var item in hierarchy) {
      if (item['unit_name'] == saleUnit || item['unit_name'] == normSaleUnit) {
        final qty = (item['quantity'] as num?)?.toDouble();
        if (qty != null && qty > 0) return qty;
      }
    }

    if (lengthPerUnit != null && lengthPerUnit! > 0) {
      final unitLower = unit.toLowerCase();
      String expectedLarge = 'علبة';
      if (unitLower.contains('متر') || unit == 'meter') expectedLarge = 'لفة';
      else if (unitLower.contains('قطع') || unit == 'piece') expectedLarge = 'كرتون';

      if (saleUnit == expectedLarge || normSaleUnit == expectedLarge) {
        return lengthPerUnit!;
      }
    }

    return 1.0;
  }

  // دالة عامة لبناء التسلسل الهرمي التلقائي للوحدات
  String? buildAutoUnitHierarchy() {
    if (lengthPerUnit == null || lengthPerUnit! <= 0) {
      // إذا كان هناك تسلسل هرمي محدد مسبقاً من المستخدم، استخدمه
      if (unitHierarchy != null && unitHierarchy!.isNotEmpty) {
        return unitHierarchy;
      }
      return null;
    }
    
    // بناء هرمية تلقائية بناءً على طول الوحدة (للمتر/لفة)
    final hierarchy = [
      {
        'unit_name': _getLargeUnitName(),
        'quantity': lengthPerUnit,
      }
    ];
    
    return jsonEncode(hierarchy);
  }

  // دالة لتحديد اسم الوحدة الكبيرة التلقائية
  String _getLargeUnitName() {
    // تحديد اسم الوحدة الكبيرة بناءً على الوحدة الأساسية
    final unitLower = unit.toLowerCase();
    if (unitLower.contains('متر') || unitLower == 'meter') return 'لفة';
    if (unitLower.contains('قطع') || unitLower == 'piece') return 'كرتون';
    if (unitLower.contains('كيلو')) return 'صندوق';
    if (unitLower.contains('غرام')) return 'كيس';
    // افتراضي: "وحدة كبيرة"
    return 'علبة';
  }

  // دالة عامة لبناء تكلفة الوحدات التلقائية
  String? buildAutoUnitCosts() {
    if (costPrice == null) return null;
    
    final costs = <String, dynamic>{};
    
    // إضافة تكلفة الوحدة الأساسية
    costs[unit] = costPrice;
    
    // إذا كان هناك طول وحدة (مثل المتر/لفة)
    if (lengthPerUnit != null && lengthPerUnit! > 0) {
      costs[_getLargeUnitName()] = costPrice! * lengthPerUnit!;
    }
    
    // إذا كان هناك تسلسلهرمي، احسب التكاليف تراكمياً
    if (unitHierarchy != null && unitHierarchy!.isNotEmpty) {
      try {
        final hierarchy = getUnitHierarchyList();
        double currentCost = costPrice!;
        for (final item in hierarchy) {
          final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
          currentCost = currentCost * qty;
          final unitName = (item['unit_name'] ?? '').toString();
          if (unitName.isNotEmpty) {
            costs[unitName] = currentCost;
          }
        }
      } catch (_) {}
    }
    
    return costs.isEmpty ? null : jsonEncode(costs);
  }
}