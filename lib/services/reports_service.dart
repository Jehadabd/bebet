// services/reports_service.dart
// خدمة التقارير المتقدمة - منفصلة عن database_service لتخفيف الحمل
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database_service.dart';
import '../utils/money_calculator.dart';

class ReportsService {
  final DatabaseService _db = DatabaseService();
  
  /// 🔍 تشخيص مشكلة التكلفة - طباعة تفاصيل حساب التكلفة لكل بند
  /// يُستخدم لتحديد سبب التكلفة العالية
  double _calculateItemCostWithDebug(Map<String, dynamic> row, {bool enableDebug = false, String? productName}) {
    final double qi = (row['qi'] as num?)?.toDouble() ?? 0.0;
    final double ql = (row['ql'] as num?)?.toDouble() ?? 0.0;
    final double uilu = (row['uilu'] as num?)?.toDouble() ?? 0.0;
    final String saleType = (row['sale_type'] as String?) ?? '';
    final String productUnit = (row['product_unit'] as String?) ?? '';
    final double productCost = (row['product_cost_price'] as num?)?.toDouble() ?? 0.0;
    final double? lengthPerUnit = (row['length_per_unit'] as num?)?.toDouble();
    final double? actualCostPerUnit = (row['actual_cost_per_unit'] as num?)?.toDouble();
    final double sellingPrice = (row['selling_price'] as num?)?.toDouble() ?? 0.0;
    final double itemTotal = (row['item_total'] as num?)?.toDouble() ?? 0.0;
    final String? unitCostsJson = row['unit_costs'] as String?;
    final String? unitHierarchyJson = row['unit_hierarchy'] as String?;
    
    // تحليل unit_costs JSON
    Map<String, dynamic> unitCosts = const {};
    if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
      try { 
        unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; 
      } catch (e) { 
        // تجاهل خطأ التحليل
      }
    }

    final bool soldAsLargeUnit = ql > 0;
    final double soldUnitsCount = soldAsLargeUnit ? ql : qi;

    // حساب التكلفة لكل وحدة مباعة
    double costPerSoldUnit;
    String costSource = 'unknown';
    
    if (actualCostPerUnit != null && actualCostPerUnit > 0) {
      costPerSoldUnit = actualCostPerUnit;
      costSource = 'actualCostPerUnit';
    } else if (soldAsLargeUnit) {
      final dynamic stored = unitCosts[saleType];
      if (stored is num && stored > 0) {
        costPerSoldUnit = stored.toDouble();
        costSource = 'unitCosts[$saleType]';
      } else {
        final bool isMeterRoll = productUnit == 'meter' && lengthPerUnit != null && (saleType == 'لفة');
        if (isMeterRoll) {
          costPerSoldUnit = productCost * (lengthPerUnit ?? 1.0);
          costSource = 'meter_roll: $productCost * $lengthPerUnit';
        } else if (uilu > 0) {
          costPerSoldUnit = productCost * uilu;
          costSource = 'uilu: $productCost * $uilu';
        } else {
          costPerSoldUnit = _calculateCostFromHierarchy(
            productCost: productCost,
            saleType: saleType,
            unitHierarchyJson: unitHierarchyJson,
            productUnit: productUnit,
          );
          costSource = 'hierarchy: productCost=$productCost, saleType=$saleType';
        }
      }
    } else {
      costPerSoldUnit = productCost;
      costSource = 'productCost (base)';
    }

    // إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
    if (costPerSoldUnit <= 0 && sellingPrice > 0) {
      costPerSoldUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
      costSource = 'estimated_10%';
    }

    final totalCost = costPerSoldUnit * soldUnitsCount;
    final profit = itemTotal - totalCost;
    
    // طباعة تشخيصية إذا كان الربح سالب أو التكلفة أعلى من المبيعات
    if (enableDebug || profit < 0 || totalCost > itemTotal * 2) {
      print('═══════════════════════════════════════════════════════════');
      print('🔍 تشخيص بند: ${productName ?? row['product_name'] ?? 'غير معروف'}');
      print('   نوع البيع: $saleType | وحدة المنتج: $productUnit');
      print('   الكمية: qi=$qi, ql=$ql, uilu=$uilu');
      print('   سعر البيع: $sellingPrice | إجمالي البند: $itemTotal');
      print('   تكلفة المنتج الأساسية: $productCost');
      print('   actualCostPerUnit: $actualCostPerUnit');
      print('   unitCosts: $unitCosts');
      print('   unitHierarchy: $unitHierarchyJson');
      print('   ─────────────────────────────────────────────────────────');
      print('   📊 النتيجة:');
      print('   مصدر التكلفة: $costSource');
      print('   تكلفة الوحدة المحسوبة: $costPerSoldUnit');
      print('   عدد الوحدات المباعة: $soldUnitsCount');
      print('   إجمالي التكلفة: $totalCost');
      print('   الربح: $profit ${profit < 0 ? "⚠️ سالب!" : "✅"}');
      print('═══════════════════════════════════════════════════════════');
    }

    return totalCost;
  }

  /// حساب تكلفة بند فاتورة بنفس منطق getMonthlySalesSummary
  /// يتعامل مع جميع أنواع الوحدات (قطعة، كرتون، متر، لفة)
  /// 🔧 إصلاح: عند عدم توفر actualCostPrice و uilu = 0، نحسب من unit_hierarchy
  double _calculateItemCost(Map<String, dynamic> row) {
    final double qi = (row['qi'] as num?)?.toDouble() ?? 0.0;
    final double ql = (row['ql'] as num?)?.toDouble() ?? 0.0;
    final double uilu = (row['uilu'] as num?)?.toDouble() ?? 0.0;
    final String saleType = (row['sale_type'] as String?) ?? '';
    final String productUnit = (row['product_unit'] as String?) ?? '';
    final double productCost = (row['product_cost_price'] as num?)?.toDouble() ?? 0.0;
    final double? lengthPerUnit = (row['length_per_unit'] as num?)?.toDouble();
    final double? actualCostPerUnit = (row['actual_cost_per_unit'] as num?)?.toDouble();
    final double sellingPrice = (row['selling_price'] as num?)?.toDouble() ?? 0.0;
    final String? unitCostsJson = row['unit_costs'] as String?;
    final String? unitHierarchyJson = row['unit_hierarchy'] as String?;
    
    // تحليل unit_costs JSON
    Map<String, dynamic> unitCosts = const {};
    if (unitCostsJson != null && unitCostsJson.trim().isNotEmpty) {
      try { 
        unitCosts = jsonDecode(unitCostsJson) as Map<String, dynamic>; 
      } catch (e) { 
        // تجاهل خطأ التحليل
      }
    }

    final bool soldAsLargeUnit = ql > 0;
    final double soldUnitsCount = soldAsLargeUnit ? ql : qi;

    // حساب التكلفة لكل وحدة مباعة - نفس منطق getDailyReport في ai_chat_service
    double costPerSoldUnit;
    if (actualCostPerUnit != null && actualCostPerUnit > 0) {
      // التكلفة الفعلية المخزنة في بند الفاتورة (الأولوية الأولى)
      costPerSoldUnit = actualCostPerUnit;
    } else if (soldAsLargeUnit) {
      // بيع بوحدة كبيرة (كرتون، لفة، إلخ)
      // أولاً: إن كانت تكلفة الوحدة الكبيرة مخزنة في unit_costs استخدمها
      final dynamic stored = unitCosts[saleType];
      if (stored is num && stored > 0) {
        costPerSoldUnit = stored.toDouble();
      } else {
        // حساب تكلفة الوحدة الكبيرة
        final bool isMeterRoll = productUnit == 'meter' && lengthPerUnit != null && (saleType == 'لفة');
        if (isMeterRoll) {
          costPerSoldUnit = productCost * (lengthPerUnit ?? 1.0);  // لفة = تكلفة المتر × طول اللفة
        } else if (uilu > 0) {
          costPerSoldUnit = productCost * uilu; // كرتون/باكية = تكلفة القطعة × عدد القطع
        } else {
          // 🔧 إصلاح: إذا كان uilu = 0، نحاول حساب المضاعف من unit_hierarchy
          costPerSoldUnit = _calculateCostFromHierarchy(
            productCost: productCost,
            saleType: saleType,
            unitHierarchyJson: unitHierarchyJson,
            productUnit: productUnit,
          );
        }
      }
    } else {
      // بيع بوحدة صغيرة (قطعة أو متر)
      costPerSoldUnit = productCost;
    }

    // إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
    if (costPerSoldUnit <= 0 && sellingPrice > 0) {
      costPerSoldUnit = MoneyCalculator.getEffectiveCost(0, sellingPrice);
    }

    return costPerSoldUnit * soldUnitsCount;
  }
  
  /// 🔧 حساب التكلفة من unit_hierarchy عندما لا تتوفر بيانات أخرى
  /// نفس منطق _calculateActualCostPrice في create_invoice_screen.dart
  double _calculateCostFromHierarchy({
    required double productCost,
    required String saleType,
    required String? unitHierarchyJson,
    required String productUnit,
  }) {
    // إذا لم يكن هناك تسلسل هرمي، نرجع التكلفة الأساسية
    if (unitHierarchyJson == null || unitHierarchyJson.trim().isEmpty) {
      return productCost;
    }
    
    try {
      final List<dynamic> hierarchy = jsonDecode(unitHierarchyJson) as List<dynamic>;
      double multiplier = 1.0;
      
      for (final level in hierarchy) {
        final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
        final double qty = (level['quantity'] is num)
            ? (level['quantity'] as num).toDouble()
            : double.tryParse(level['quantity'].toString()) ?? 1.0;
        multiplier *= qty;
        
        // إذا وصلنا لوحدة البيع المطلوبة، نرجع التكلفة المحسوبة
        if (unitName == saleType) {
          return productCost * multiplier;
        }
      }
      
      // إذا لم نجد الوحدة في التسلسل، نرجع التكلفة الأساسية
      return productCost;
    } catch (e) {
      // في حالة خطأ التحليل، نرجع التكلفة الأساسية
      return productCost;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // أفضل المنتجات في فترة معينة
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// أفضل المنتجات مبيعاً في فترة معينة
  Future<List<Map<String, dynamic>>> getTopProductsInPeriod({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    final results = await db.rawQuery('''
      SELECT 
        ii.product_name,
        SUM(ii.item_total) as total_sales,
        SUM(COALESCE(ii.quantity_individual, 0) + COALESCE(ii.quantity_large_unit, 0)) as total_quantity,
        COUNT(DISTINCT ii.invoice_id) as invoice_count
      FROM invoice_items ii
      INNER JOIN invoices i ON ii.invoice_id = i.id
      WHERE DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?
        AND i.status = 'محفوظة'
      GROUP BY ii.product_name
      ORDER BY total_sales DESC
      LIMIT ?
    ''', [startStr, endStr, limit]);
    
    return results;
  }

  /// أفضل المنتجات ربحاً في فترة معينة
  /// يستخدم نفس منطق حساب الربح من database_service.getMonthlySalesSummary
  Future<List<Map<String, dynamic>>> getTopProductsByProfitInPeriod({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    // جلب بنود الفواتير مع بيانات المنتج الكاملة (JOIN وليس LEFT JOIN لضمان وجود بيانات المنتج)
    final items = await db.rawQuery('''
      SELECT 
        ii.product_name,
        ii.quantity_individual AS qi,
        ii.quantity_large_unit AS ql,
        ii.units_in_large_unit AS uilu,
        ii.actual_cost_price AS actual_cost_per_unit,
        ii.applied_price AS selling_price,
        ii.sale_type AS sale_type,
        ii.item_total,
        p.unit AS product_unit,
        p.cost_price AS product_cost_price,
        p.length_per_unit AS length_per_unit,
        p.unit_costs AS unit_costs,
        p.unit_hierarchy AS unit_hierarchy
      FROM invoice_items ii
      INNER JOIN invoices i ON ii.invoice_id = i.id
      JOIN products p ON p.name = ii.product_name
      WHERE DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?
        AND i.status = 'محفوظة'
    ''', [startStr, endStr]);
    
    // حساب الربح لكل منتج بنفس منطق getMonthlySalesSummary
    Map<String, Map<String, dynamic>> productProfits = {};
    
    for (final item in items) {
      final productName = item['product_name'] as String;
      final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0;
      final ql = (item['ql'] as num?)?.toDouble() ?? 0;
      final qi = (item['qi'] as num?)?.toDouble() ?? 0;
      
      // حساب التكلفة باستخدام الدالة المشتركة
      final totalCost = _calculateItemCost(item);
      
      // حساب الربح
      final profit = MoneyCalculator.subtract(itemTotal, totalCost);
      final soldUnits = ql > 0 ? ql : qi;
      
      if (!productProfits.containsKey(productName)) {
        productProfits[productName] = {
          'product_name': productName,
          'total_sales': 0.0,
          'total_profit': 0.0,
          'total_quantity': 0.0,
        };
      }
      productProfits[productName]!['total_profit'] =
          (productProfits[productName]!['total_profit'] as double) + profit;
      productProfits[productName]!['total_sales'] =
          (productProfits[productName]!['total_sales'] as double) + itemTotal;
      productProfits[productName]!['total_quantity'] =
          (productProfits[productName]!['total_quantity'] as double) + soldUnits;
    }
    
    // ترتيب حسب الربح
    final sortedProducts = productProfits.values.toList()
      ..sort((a, b) => (b['total_profit'] as double).compareTo(a['total_profit'] as double));
    
    return sortedProducts.take(limit).toList();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // أفضل العملاء في فترة معينة
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// أفضل العملاء شراءً في فترة معينة
  Future<List<Map<String, dynamic>>> getTopCustomersInPeriod({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 5,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    final results = await db.rawQuery('''
      SELECT 
        i.customer_name,
        c.phone as customer_phone,
        SUM(i.total_amount) as total_purchases,
        COUNT(i.id) as invoice_count
      FROM invoices i
      LEFT JOIN customers c ON i.customer_id = c.id
      WHERE DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?
        AND i.status = 'محفوظة'
      GROUP BY i.customer_name
      ORDER BY total_purchases DESC
      LIMIT ?
    ''', [startStr, endStr, limit]);
    
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // مقارنة الفترات
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// الحصول على بيانات فترة معينة للمقارنة
  /// يستخدم نفس منطق getMonthlySalesSummary بالضبط
  Future<Map<String, dynamic>> getPeriodSummary({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    // بيانات الفواتير الأساسية - فقط الفواتير المحفوظة (نفس منطق getMonthlySalesSummary)
    final invoiceData = await db.rawQuery('''
      SELECT 
        COUNT(*) as invoice_count,
        COALESCE(SUM(total_amount), 0) as total_sales,
        COALESCE(SUM(return_amount), 0) as total_returns,
        COALESCE(SUM(CASE WHEN payment_type = 'نقد' THEN total_amount ELSE 0 END), 0) as cash_sales,
        COALESCE(SUM(CASE WHEN payment_type = 'دين' THEN total_amount ELSE 0 END), 0) as credit_sales
      FROM invoices
      WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
        AND status = 'محفوظة'
    ''', [startStr, endStr]);
    
    // جلب الفواتير المحفوظة لحساب التكلفة والربح لكل فاتورة
    final invoices = await db.rawQuery('''
      SELECT id, total_amount, return_amount
      FROM invoices
      WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
        AND status = 'محفوظة'
    ''', [startStr, endStr]);
    
    // حساب التكلفة والربح لكل فاتورة بنفس منطق getMonthlySalesSummary
    double totalCostCalculated = 0.0;
    double totalProfitCalculated = 0.0;
    
    for (final invoice in invoices) {
      final invoiceId = invoice['id'] as int;
      final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
      final returnAmount = (invoice['return_amount'] as num?)?.toDouble() ?? 0.0;
      
      // جلب بنود الفاتورة مع بيانات المنتج (JOIN وليس LEFT JOIN لضمان وجود بيانات المنتج)
      final items = await db.rawQuery('''
        SELECT 
          ii.quantity_individual AS qi,
          ii.quantity_large_unit AS ql,
          ii.units_in_large_unit AS uilu,
          ii.actual_cost_price AS actual_cost_per_unit,
          ii.applied_price AS selling_price,
          ii.sale_type AS sale_type,
          ii.item_total,
          p.unit AS product_unit,
          p.cost_price AS product_cost_price,
          p.length_per_unit AS length_per_unit,
          p.unit_costs AS unit_costs,
          p.unit_hierarchy AS unit_hierarchy
        FROM invoice_items ii
        JOIN products p ON p.name = ii.product_name
        WHERE ii.invoice_id = ?
      ''', [invoiceId]);
      
      // حساب تكلفة الفاتورة
      double invoiceCost = 0.0;
      for (final item in items) {
        invoiceCost += _calculateItemCost(item);
      }
      
      totalCostCalculated += invoiceCost;
      
      // صافي المبيعات بعد الراجع مطروحاً منه التكلفة (نفس منطق getMonthlySalesSummary)
      final netSaleAmount = MoneyCalculator.subtract(totalAmount, returnAmount);
      final profit = MoneyCalculator.subtract(netSaleAmount, invoiceCost);
      totalProfitCalculated += profit;
    }
    
    // المعاملات اليدوية (جدول transactions)
    final manualDebt = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        COALESCE(SUM(amount_changed), 0) as total
      FROM transactions
      WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
        AND transaction_type IN ('manual_debt', 'opening_balance')
    ''', [startStr, endStr]);
    
    final manualPayment = await db.rawQuery('''
      SELECT 
        COUNT(*) as count,
        COALESCE(SUM(ABS(amount_changed)), 0) as total
      FROM transactions
      WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
        AND transaction_type = 'manual_payment'
    ''', [startStr, endStr]);
    
    final inv = invoiceData.first;
    final debt = manualDebt.first;
    final payment = manualPayment.first;
    
    final totalSales = (inv['total_sales'] as num?)?.toDouble() ?? 0.0;
    final totalReturns = (inv['total_returns'] as num?)?.toDouble() ?? 0.0;
    
    return {
      'invoiceCount': inv['invoice_count'] ?? 0,
      'totalSales': totalSales,
      'netProfit': totalProfitCalculated,
      'totalCost': totalCostCalculated,
      'cashSales': (inv['cash_sales'] as num?)?.toDouble() ?? 0.0,
      'creditSales': (inv['credit_sales'] as num?)?.toDouble() ?? 0.0,
      'totalReturns': totalReturns,
      'manualDebtCount': debt['count'] ?? 0,
      'totalManualDebt': (debt['total'] as num?)?.toDouble() ?? 0.0,
      'manualPaymentCount': payment['count'] ?? 0,
      'totalManualPayment': (payment['total'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// مقارنة فترتين
  Future<Map<String, dynamic>> comparePeriods({
    required DateTime currentStart,
    required DateTime currentEnd,
    required DateTime previousStart,
    required DateTime previousEnd,
  }) async {
    final current = await getPeriodSummary(startDate: currentStart, endDate: currentEnd);
    final previous = await getPeriodSummary(startDate: previousStart, endDate: previousEnd);
    
    // حساب نسب التغيير
    double calcChange(double curr, double prev) {
      if (prev == 0) return curr > 0 ? 100.0 : 0.0;
      return ((curr - prev) / prev) * 100;
    }
    
    return {
      'current': current,
      'previous': previous,
      'changes': {
        'salesChange': calcChange(current['totalSales'], previous['totalSales']),
        'profitChange': calcChange(current['netProfit'], previous['netProfit']),
        'invoiceCountChange': calcChange(
          (current['invoiceCount'] as int).toDouble(), 
          (previous['invoiceCount'] as int).toDouble()
        ),
        'cashSalesChange': calcChange(current['cashSales'], previous['cashSales']),
        'creditSalesChange': calcChange(current['creditSales'], previous['creditSales']),
      },
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // العملاء الجدد
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// العملاء الجدد في فترة معينة
  Future<List<Map<String, dynamic>>> getNewCustomersInPeriod({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    final results = await db.rawQuery('''
      SELECT 
        c.id,
        c.name,
        c.phone,
        c.created_at,
        COALESCE(SUM(i.total_amount), 0) as total_purchases,
        COUNT(i.id) as invoice_count
      FROM customers c
      LEFT JOIN invoices i ON c.id = i.customer_id AND i.status = 'محفوظة'
      WHERE DATE(c.created_at) >= ? AND DATE(c.created_at) <= ?
      GROUP BY c.id
      ORDER BY c.created_at DESC
    ''', [startStr, endStr]);
    
    return results;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الديون المتأخرة
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// العملاء الذين لديهم ديون ولم يسددوا منذ فترة
  Future<List<Map<String, dynamic>>> getOverdueDebts({
    int daysSinceLastPayment = 30,
    double minimumDebt = 0,
  }) async {
    final db = await _db.database;
    final cutoffDate = DateTime.now().subtract(Duration(days: daysSinceLastPayment));
    final cutoffStr = cutoffDate.toIso8601String().split('T')[0];
    
    final results = await db.rawQuery('''
      SELECT 
        c.id,
        c.name,
        c.phone,
        c.current_total_debt,
        (
          SELECT MAX(transaction_date)
          FROM transactions t
          WHERE t.customer_id = c.id AND t.transaction_type = 'manual_payment'
        ) as last_payment_date,
        (
          SELECT MAX(transaction_date)
          FROM transactions t
          WHERE t.customer_id = c.id
        ) as last_transaction_date
      FROM customers c
      WHERE c.current_total_debt > ?
      ORDER BY c.current_total_debt DESC
    ''', [minimumDebt]);
    
    // تصفية العملاء الذين لم يسددوا منذ الفترة المحددة
    final filtered = results.where((customer) {
      final lastPayment = customer['last_payment_date'] as String?;
      if (lastPayment == null) return true; // لم يسدد أبداً
      
      try {
        final paymentDate = DateTime.parse(lastPayment);
        return paymentDate.isBefore(cutoffDate);
      } catch (e) {
        return true;
      }
    }).toList();
    
    return filtered;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تحليل الاتجاه (Trend Analysis)
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// المبيعات اليومية خلال فترة (للرسم البياني)
  Future<List<Map<String, dynamic>>> getDailySalesInPeriod({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final db = await _db.database;
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    final results = await db.rawQuery('''
      SELECT 
        DATE(invoice_date) as date,
        COUNT(*) as invoice_count,
        COALESCE(SUM(total_amount), 0) as total_sales,
        COALESCE(SUM(CASE WHEN payment_type = 'نقد' THEN total_amount ELSE 0 END), 0) as cash_sales,
        COALESCE(SUM(CASE WHEN payment_type = 'دين' THEN total_amount ELSE 0 END), 0) as credit_sales
      FROM invoices
      WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
        AND status = 'محفوظة'
      GROUP BY DATE(invoice_date)
      ORDER BY date ASC
    ''', [startStr, endStr]);
    
    return results;
  }

  /// تحليل اتجاه المبيعات (صاعد/هابط/مستقر)
  Future<Map<String, dynamic>> analyzeSalesTrend({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final dailySales = await getDailySalesInPeriod(startDate: startDate, endDate: endDate);
    
    if (dailySales.length < 2) {
      return {
        'trend': 'insufficient_data',
        'trendArabic': 'بيانات غير كافية',
        'averageDailySales': 0.0,
        'totalDays': dailySales.length,
      };
    }
    
    // حساب المتوسط
    double totalSales = 0;
    for (var day in dailySales) {
      totalSales += (day['total_sales'] as num?)?.toDouble() ?? 0;
    }
    final avgDailySales = totalSales / dailySales.length;
    
    // تقسيم الفترة إلى نصفين ومقارنتهما
    final midPoint = dailySales.length ~/ 2;
    double firstHalfTotal = 0;
    double secondHalfTotal = 0;
    
    for (int i = 0; i < dailySales.length; i++) {
      final sales = (dailySales[i]['total_sales'] as num?)?.toDouble() ?? 0;
      if (i < midPoint) {
        firstHalfTotal += sales;
      } else {
        secondHalfTotal += sales;
      }
    }
    
    final firstHalfAvg = firstHalfTotal / midPoint;
    final secondHalfAvg = secondHalfTotal / (dailySales.length - midPoint);
    
    String trend;
    String trendArabic;
    double changePercent = 0;
    
    if (firstHalfAvg > 0) {
      changePercent = ((secondHalfAvg - firstHalfAvg) / firstHalfAvg) * 100;
    }
    
    if (changePercent > 10) {
      trend = 'increasing';
      trendArabic = 'صاعد ↑';
    } else if (changePercent < -10) {
      trend = 'decreasing';
      trendArabic = 'هابط ↓';
    } else {
      trend = 'stable';
      trendArabic = 'مستقر →';
    }
    
    return {
      'trend': trend,
      'trendArabic': trendArabic,
      'changePercent': changePercent,
      'averageDailySales': avgDailySales,
      'totalDays': dailySales.length,
      'firstHalfAvg': firstHalfAvg,
      'secondHalfAvg': secondHalfAvg,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // نسبة الربح
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// حساب نسبة الربح لفترة معينة
  Future<double> getProfitPercentage({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final summary = await getPeriodSummary(startDate: startDate, endDate: endDate);
    final totalSales = summary['totalSales'] as double;
    final netProfit = summary['netProfit'] as double;
    
    if (totalSales <= 0) return 0.0;
    return (netProfit / totalSales) * 100;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تقرير شهري مفصل
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// تقرير شهري شامل
  Future<Map<String, dynamic>> getMonthlyDetailedReport({
    required int year,
    required int month,
  }) async {
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0); // آخر يوم في الشهر
    
    // الشهر السابق للمقارنة
    final prevMonth = month == 1 ? 12 : month - 1;
    final prevYear = month == 1 ? year - 1 : year;
    final prevStartDate = DateTime(prevYear, prevMonth, 1);
    final prevEndDate = DateTime(prevYear, prevMonth + 1, 0);
    
    final summary = await getPeriodSummary(startDate: startDate, endDate: endDate);
    final comparison = await comparePeriods(
      currentStart: startDate,
      currentEnd: endDate,
      previousStart: prevStartDate,
      previousEnd: prevEndDate,
    );
    final topProducts = await getTopProductsInPeriod(startDate: startDate, endDate: endDate, limit: 10);
    final topCustomers = await getTopCustomersInPeriod(startDate: startDate, endDate: endDate, limit: 10);
    final newCustomers = await getNewCustomersInPeriod(startDate: startDate, endDate: endDate);
    final trend = await analyzeSalesTrend(startDate: startDate, endDate: endDate);
    final dailySales = await getDailySalesInPeriod(startDate: startDate, endDate: endDate);
    final profitPercent = await getProfitPercentage(startDate: startDate, endDate: endDate);
    
    return {
      'year': year,
      'month': month,
      'summary': summary,
      'comparison': comparison,
      'topProducts': topProducts,
      'topCustomers': topCustomers,
      'newCustomers': newCustomers,
      'newCustomersCount': newCustomers.length,
      'trend': trend,
      'dailySales': dailySales,
      'profitPercent': profitPercent,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // تقرير سنوي
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// تقرير سنوي شامل
  Future<Map<String, dynamic>> getYearlyReport({required int year}) async {
    final startDate = DateTime(year, 1, 1);
    final endDate = DateTime(year, 12, 31);
    
    // السنة السابقة للمقارنة
    final prevStartDate = DateTime(year - 1, 1, 1);
    final prevEndDate = DateTime(year - 1, 12, 31);
    
    final summary = await getPeriodSummary(startDate: startDate, endDate: endDate);
    final comparison = await comparePeriods(
      currentStart: startDate,
      currentEnd: endDate,
      previousStart: prevStartDate,
      previousEnd: prevEndDate,
    );
    final topProducts = await getTopProductsInPeriod(startDate: startDate, endDate: endDate, limit: 20);
    final topCustomers = await getTopCustomersInPeriod(startDate: startDate, endDate: endDate, limit: 20);
    final newCustomers = await getNewCustomersInPeriod(startDate: startDate, endDate: endDate);
    final profitPercent = await getProfitPercentage(startDate: startDate, endDate: endDate);
    
    // المبيعات الشهرية للسنة
    final monthlySales = <Map<String, dynamic>>[];
    for (int m = 1; m <= 12; m++) {
      final mStart = DateTime(year, m, 1);
      final mEnd = DateTime(year, m + 1, 0);
      final mSummary = await getPeriodSummary(startDate: mStart, endDate: mEnd);
      monthlySales.add({
        'month': m,
        'monthName': _getArabicMonthName(m),
        ...mSummary,
      });
    }
    
    return {
      'year': year,
      'summary': summary,
      'comparison': comparison,
      'topProducts': topProducts,
      'topCustomers': topCustomers,
      'newCustomersCount': newCustomers.length,
      'profitPercent': profitPercent,
      'monthlySales': monthlySales,
    };
  }

  String _getArabicMonthName(int month) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return months[month - 1];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔍 تشخيص مشكلة التكلفة
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// تشخيص مشكلة التكلفة العالية - يطبع تفاصيل كل فاتورة وبنودها
  /// استخدم هذه الدالة لفهم سبب التكلفة العالية
  Future<Map<String, dynamic>> diagnoseCostProblem({
    required int year,
    required int month,
    int? limitInvoices,
  }) async {
    final db = await _db.database;
    final startDate = DateTime(year, month, 1);
    final endDate = DateTime(year, month + 1, 0);
    final startStr = startDate.toIso8601String().split('T')[0];
    final endStr = endDate.toIso8601String().split('T')[0];
    
    print('');
    print('╔═══════════════════════════════════════════════════════════════════╗');
    print('║  🔍 تشخيص مشكلة التكلفة - ${_getArabicMonthName(month)} $year');
    print('╚═══════════════════════════════════════════════════════════════════╝');
    print('');
    
    // جلب الفواتير المحفوظة
    final invoices = await db.rawQuery('''
      SELECT id, total_amount, return_amount, customer_name, invoice_date
      FROM invoices
      WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
        AND status = 'محفوظة'
      ORDER BY id DESC
      ${limitInvoices != null ? 'LIMIT $limitInvoices' : ''}
    ''', [startStr, endStr]);
    
    double grandTotalSales = 0.0;
    double grandTotalCost = 0.0;
    int problemItems = 0;
    int totalItems = 0;
    final problemProducts = <String, int>{};
    
    for (final invoice in invoices) {
      final invoiceId = invoice['id'] as int;
      final totalAmount = (invoice['total_amount'] as num?)?.toDouble() ?? 0.0;
      final returnAmount = (invoice['return_amount'] as num?)?.toDouble() ?? 0.0;
      final customerName = invoice['customer_name'] as String? ?? 'غير معروف';
      
      grandTotalSales += totalAmount;
      
      // جلب بنود الفاتورة
      final items = await db.rawQuery('''
        SELECT 
          ii.product_name,
          ii.quantity_individual AS qi,
          ii.quantity_large_unit AS ql,
          ii.units_in_large_unit AS uilu,
          ii.actual_cost_price AS actual_cost_per_unit,
          ii.applied_price AS selling_price,
          ii.sale_type AS sale_type,
          ii.item_total,
          p.unit AS product_unit,
          p.cost_price AS product_cost_price,
          p.length_per_unit AS length_per_unit,
          p.unit_costs AS unit_costs,
          p.unit_hierarchy AS unit_hierarchy
        FROM invoice_items ii
        JOIN products p ON p.name = ii.product_name
        WHERE ii.invoice_id = ?
      ''', [invoiceId]);
      
      double invoiceCost = 0.0;
      bool hasProblems = false;
      
      for (final item in items) {
        totalItems++;
        final productName = item['product_name'] as String? ?? 'غير معروف';
        final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
        
        // حساب التكلفة مع التشخيص
        final itemCost = _calculateItemCostWithDebug(item, enableDebug: false, productName: productName);
        invoiceCost += itemCost;
        
        // تحقق من وجود مشكلة
        if (itemCost > itemTotal * 1.5) { // التكلفة أعلى من 150% من المبيعات
          problemItems++;
          hasProblems = true;
          problemProducts[productName] = (problemProducts[productName] ?? 0) + 1;
          
          // طباعة تفاصيل البند المشكل
          _calculateItemCostWithDebug(item, enableDebug: true, productName: productName);
        }
      }
      
      grandTotalCost += invoiceCost;
      
      // طباعة ملخص الفاتورة إذا كانت بها مشاكل
      if (hasProblems) {
        final profit = (totalAmount - returnAmount) - invoiceCost;
        print('');
        print('📄 فاتورة #$invoiceId - $customerName');
        print('   المبيعات: $totalAmount | التكلفة: $invoiceCost | الربح: $profit');
        print('');
      }
    }
    
    // ملخص التشخيص
    final grandProfit = grandTotalSales - grandTotalCost;
    final profitPercent = grandTotalSales > 0 ? (grandProfit / grandTotalSales) * 100 : 0.0;
    
    print('');
    print('╔═══════════════════════════════════════════════════════════════════╗');
    print('║  📊 ملخص التشخيص');
    print('╠═══════════════════════════════════════════════════════════════════╣');
    print('║  عدد الفواتير: ${invoices.length}');
    print('║  عدد البنود الإجمالي: $totalItems');
    print('║  عدد البنود المشكلة: $problemItems');
    print('║  ─────────────────────────────────────────────────────────────────');
    print('║  إجمالي المبيعات: $grandTotalSales');
    print('║  إجمالي التكلفة: $grandTotalCost');
    print('║  صافي الربح: $grandProfit');
    print('║  نسبة الربح: ${profitPercent.toStringAsFixed(1)}%');
    print('╠═══════════════════════════════════════════════════════════════════╣');
    
    if (problemProducts.isNotEmpty) {
      print('║  🚨 المنتجات الأكثر مشاكل:');
      final sorted = problemProducts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (var i = 0; i < sorted.length && i < 10; i++) {
        print('║     ${i + 1}. ${sorted[i].key}: ${sorted[i].value} مرة');
      }
    }
    
    print('╚═══════════════════════════════════════════════════════════════════╝');
    print('');
    
    return {
      'invoiceCount': invoices.length,
      'totalItems': totalItems,
      'problemItems': problemItems,
      'grandTotalSales': grandTotalSales,
      'grandTotalCost': grandTotalCost,
      'grandProfit': grandProfit,
      'profitPercent': profitPercent,
      'problemProducts': problemProducts,
    };
  }

  /// تشخيص منتج محدد - يطبع كل الفواتير التي تحتوي على هذا المنتج
  Future<void> diagnoseProduct({
    required String productName,
    int? year,
    int? month,
  }) async {
    final db = await _db.database;
    
    print('');
    print('╔═══════════════════════════════════════════════════════════════════╗');
    print('║  🔍 تشخيص منتج: $productName');
    print('╚═══════════════════════════════════════════════════════════════════╝');
    
    // جلب بيانات المنتج
    final products = await db.query('products', where: 'name = ?', whereArgs: [productName]);
    if (products.isEmpty) {
      print('❌ المنتج غير موجود في قاعدة البيانات!');
      return;
    }
    
    final product = products.first;
    print('');
    print('📦 بيانات المنتج:');
    print('   الوحدة: ${product['unit']}');
    print('   تكلفة الوحدة: ${product['cost_price']}');
    print('   unit_costs: ${product['unit_costs']}');
    print('   unit_hierarchy: ${product['unit_hierarchy']}');
    print('');
    
    // جلب بنود الفواتير لهذا المنتج
    String whereClause = 'ii.product_name = ?';
    List<dynamic> whereArgs = [productName];
    
    if (year != null && month != null) {
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0);
      whereClause += ' AND DATE(i.invoice_date) >= ? AND DATE(i.invoice_date) <= ?';
      whereArgs.addAll([startDate.toIso8601String().split('T')[0], endDate.toIso8601String().split('T')[0]]);
    }
    
    final items = await db.rawQuery('''
      SELECT 
        i.id as invoice_id,
        i.invoice_date,
        i.customer_name,
        ii.quantity_individual AS qi,
        ii.quantity_large_unit AS ql,
        ii.units_in_large_unit AS uilu,
        ii.actual_cost_price AS actual_cost_per_unit,
        ii.applied_price AS selling_price,
        ii.sale_type AS sale_type,
        ii.item_total,
        p.unit AS product_unit,
        p.cost_price AS product_cost_price,
        p.length_per_unit AS length_per_unit,
        p.unit_costs AS unit_costs,
        p.unit_hierarchy AS unit_hierarchy
      FROM invoice_items ii
      JOIN invoices i ON ii.invoice_id = i.id
      JOIN products p ON p.name = ii.product_name
      WHERE $whereClause AND i.status = 'محفوظة'
      ORDER BY i.invoice_date DESC
      LIMIT 20
    ''', whereArgs);
    
    print('📋 آخر ${items.length} فاتورة تحتوي على هذا المنتج:');
    print('');
    
    for (final item in items) {
      _calculateItemCostWithDebug(item, enableDebug: true, productName: productName);
    }
  }
}
