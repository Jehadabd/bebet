/// 🔮 محرك التسعير الذكي - Smart Pricing Engine v2.0
///
/// نظام تسعير احترافي يعتمد على:
/// 1. تاريخ الزبون مع المنتج (إذا وُجد) - عامل يزيد الدقة
/// 2. آخر 20 عملية بيع للمنتج (بغض النظر عن الزبون)
/// 3. تحليل اتجاه السعر (آخر العمليات أهم)
/// 4. نظام النقاط لكل سعر مرشح
///
/// المبادئ:
/// - الزبون ليس شرطاً للعمل، بل عامل يزيد الدقة
/// - الفاتورة النقدية = تحليل المنتج فقط
/// - الزبون الجديد = تحليل المنتج فقط
/// - الزبون المعروف = تاريخه + تحليل المنتج
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'database_service.dart';
import 'smart_search/smart_search_db.dart';
import 'settings_manager.dart';

/// نتيجة التسعير الذكي
class SmartPricingResult {
  final double price;
  final int confidence; // 0-100
  final String source;
  final String reason;
  final Map<double, int> candidateScores; // الأسعار المرشحة ونقاطها

  SmartPricingResult({
    required this.price,
    required this.confidence,
    required this.source,
    required this.reason,
    this.candidateScores = const {},
  });

  @override
  String toString() {
    return 'SmartPricingResult(price: $price, confidence: $confidence%, source: $source)';
  }
}

/// سعر مرشح مع نقاطه
class PriceCandidate {
  final double price;
  int score;
  final List<String> reasons;

  PriceCandidate({
    required this.price,
    this.score = 0,
    List<String>? reasons,
  }) : reasons = reasons ?? [];

  void addPoints(int points, String reason) {
    score += points;
    reasons.add('$reason (+$points)');
  }
}

/// إحصائيات سعر المنتج
class ProductPriceStats {
  final int productId;
  final double lastPrice;
  final double mostFrequentPrice;
  final double medianPrice;
  final int saleCount;
  final DateTime? lastSaleDate;
  final int confidence;
  final String? priceTrend; // ارتفاع، انخفاض، مستقر
  final int? trendSinceOperations;

  ProductPriceStats({
    required this.productId,
    required this.lastPrice,
    required this.mostFrequentPrice,
    required this.medianPrice,
    required this.saleCount,
    this.lastSaleDate,
    required this.confidence,
    this.priceTrend,
    this.trendSinceOperations,
  });

  factory ProductPriceStats.fromMap(Map<String, dynamic> map) {
    return ProductPriceStats(
      productId: map['product_id'] as int,
      lastPrice: (map['last_price'] as num?)?.toDouble() ?? 0,
      mostFrequentPrice: (map['most_frequent_price'] as num?)?.toDouble() ?? 0,
      medianPrice: (map['median_price'] as num?)?.toDouble() ?? 0,
      saleCount: (map['sale_count'] as int?) ?? 0,
      lastSaleDate: map['last_sale_date'] != null 
          ? DateTime.tryParse(map['last_sale_date']) 
          : null,
      confidence: (map['confidence'] as int?) ?? 0,
      priceTrend: map['price_trend'] as String?,
      trendSinceOperations: map['trend_since_ops'] as int?,
    );
  }
}

/// إحصائيات سعر الزبون مع المنتج
class CustomerProductStats {
  final int customerId;
  final int productId;
  final double lastPrice;
  final double mostFrequentPrice;
  final int purchaseCount;
  final DateTime? lastPurchaseDate;
  final int confidence;

  CustomerProductStats({
    required this.customerId,
    required this.productId,
    required this.lastPrice,
    required this.mostFrequentPrice,
    required this.purchaseCount,
    this.lastPurchaseDate,
    required this.confidence,
  });

  factory CustomerProductStats.fromMap(Map<String, dynamic> map) {
    return CustomerProductStats(
      customerId: map['customer_id'] as int,
      productId: map['product_id'] as int,
      lastPrice: (map['last_price'] as num?)?.toDouble() ?? 0,
      mostFrequentPrice: (map['most_frequent_price'] as num?)?.toDouble() ?? 0,
      purchaseCount: (map['purchase_count'] as int?) ?? 0,
      lastPurchaseDate: map['last_purchase_date'] != null 
          ? DateTime.tryParse(map['last_purchase_date']) 
          : null,
      confidence: (map['confidence'] as int?) ?? 0,
    );
  }
}

/// محرك التسعير الذكي v2.0
class SmartPricingService {
  static final SmartPricingService _instance = SmartPricingService._internal();
  factory SmartPricingService() => _instance;
  SmartPricingService._internal();

  DatabaseService? _dbService;
  
  /// حجم النافذة الدائرية (آخر N عملية)
  static const int RECENT_SALES_LIMIT = 20;
  
  /// عوامل النقاط (قابلة للتعديل - تم التركيز بشكل كبير على آخر 5 عمليات)
  static const int POINTS_LAST_PRICE = 50;
  static const int POINTS_IN_LAST_5 = 100; // وزن ضخم جداً للعمليات الحديثة
  static const int POINTS_IN_LAST_10 = 10;
  static const int POINTS_FREQUENCY_BONUS = 15;
  static const int POINTS_CUSTOMER_HISTORY = 75;
  static const int POINTS_TREND_MATCH = 15;
  static const int POINTS_DOMINANT_PRICE = 30;
  static const int POINTS_CONTEXT_MATCH = 80; // تطابق سياق الفاتورة

  /// تهيئة الخدمة
  Future<void> initialize(DatabaseService dbService) async {
    _dbService = dbService;
    await _ensureTablesExist();
    await _runInitialTrainingIfNeeded();
  }

  /// التأكد من وجود الجداول
  Future<void> _ensureTablesExist() async {
    final db = await _dbService!.database;
    
    // جدول إحصائيات المنتج (محدث ليشمل الاتجاه)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_price_stats (
        product_id INTEGER PRIMARY KEY,
        last_price REAL,
        most_frequent_price REAL,
        median_price REAL,
        sale_count INTEGER DEFAULT 0,
        last_sale_date TEXT,
        confidence INTEGER DEFAULT 0,
        price_trend TEXT,
        trend_since_ops INTEGER,
        updated_at TEXT
      )
    ''');

    // جدول إحصائيات الزبون مع المنتج
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_product_stats (
        customer_id INTEGER,
        product_id INTEGER,
        last_price REAL,
        most_frequent_price REAL,
        purchase_count INTEGER DEFAULT 0,
        last_purchase_date TEXT,
        confidence INTEGER DEFAULT 0,
        updated_at TEXT,
        PRIMARY KEY (customer_id, product_id)
      )
    ''');

    // جدول آخر العمليات (Circular Buffer)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS recent_sales_buffer (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        customer_id INTEGER,
        price REAL,
        sale_type TEXT,
        invoice_date TEXT,
        created_at TEXT
      )
    ''');

    // إنشاء فهارس للسرعة
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recent_sales_product 
      ON recent_sales_buffer(product_id, invoice_date DESC)
    ''');
    
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recent_sales_customer_product 
      ON recent_sales_buffer(product_id, customer_id)
    ''');
  }

  /// التدريب الأولي - قراءة جميع الفواتير وبناء الإحصائيات
  Future<void> _runInitialTrainingIfNeeded() async {
    final db = await _dbService!.database;
    
    // التحقق إذا كانت الجداول فارغة
    final productStatsCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM product_price_stats')
    ) ?? 0;
    
    if (productStatsCount == 0) {
      print('🔮 Smart Pricing: Starting initial training...');
      await rebuildAllStats();
      print('✅ Smart Pricing: Initial training completed!');
    } else {
      print('✅ Smart Pricing: Stats already exist, skipping training.');
    }
  }

  /// إعادة بناء جميع الإحصائيات من الصفر
  Future<void> rebuildAllStats() async {
    final db = await _dbService!.database;
    
    // 1. مسح الجداول القديمة
    await db.delete('product_price_stats');
    await db.delete('customer_product_stats');
    await db.delete('recent_sales_buffer');

    // 2. جلب جميع عناصر الفواتير المحفوظة
    final invoiceItems = await db.rawQuery('''
      SELECT 
        ii.product_id,
        ii.product_name,
        ii.applied_price,
        ii.sale_type,
        i.customer_id,
        i.invoice_date
      FROM invoice_items ii
      JOIN invoices i ON i.id = ii.invoice_id
      WHERE i.status = 'محفوظة' AND ii.applied_price > 0
      ORDER BY i.invoice_date ASC
    ''');

    print('📊 Processing ${invoiceItems.length} invoice items...');

    // 3. تجميع البيانات
    final Map<int, List<Map<String, dynamic>>> productSales = {};
    final Map<String, List<Map<String, dynamic>>> customerProductSales = {};

    int skippedNoCustomerId = 0;
    int skippedNoProductId = 0;

    for (var item in invoiceItems) {
      final productId = item['product_id'] as int?;
      final customerId = item['customer_id'] as int?;
      final price = (item['applied_price'] as num).toDouble();
      final saleType = item['sale_type'] as String? ?? '';
      final invoiceDate = item['invoice_date'] as String;

      if (productId == null) {
        skippedNoProductId++;
        continue;
      }

      // تجميع حسب المنتج (بغض النظر عن الزبون)
      productSales.putIfAbsent(productId, () => []);
      productSales[productId]!.add({
        'price': price,
        'sale_type': saleType,
        'invoice_date': invoiceDate,
        'customer_id': customerId,
      });

      // تجميع حسب الزبون+المنتج (إذا كان الزبون موجوداً)
      if (customerId != null) {
        final key = '${customerId}_$productId';
        customerProductSales.putIfAbsent(key, () => []);
        customerProductSales[key]!.add({
          'price': price,
          'sale_type': saleType,
          'invoice_date': invoiceDate,
        });
      } else {
        skippedNoCustomerId++;
      }
    }

    print('📊 Skipped $skippedNoProductId items without product_id');
    print('📊 Skipped $skippedNoCustomerId items without customer_id');
    print('📊 Processing ${productSales.length} products...');

    // 4. بناء إحصائيات المنتجات
    int processedProducts = 0;
    for (var entry in productSales.entries) {
      final productId = entry.key;
      final sales = entry.value;
      
      if (sales.isEmpty) continue;

      final prices = sales.map((s) => s['price'] as double).toList();
      final lastPrice = prices.last;
      final mostFrequent = _findMostFrequent(prices);
      final median = _calculateMedian(prices);
      final saleCount = sales.length;
      final lastSaleDate = sales.last['invoice_date'] as String;
      final confidence = _calculateConfidence(prices);
      
      // تحليل الاتجاه
      final trendAnalysis = _analyzeTrend(prices);
      final priceTrend = trendAnalysis['trend'] as String;
      final trendSinceOps = trendAnalysis['since'] as int;

      await db.insert('product_price_stats', {
        'product_id': productId,
        'last_price': lastPrice,
        'most_frequent_price': mostFrequent,
        'median_price': median,
        'sale_count': saleCount,
        'last_sale_date': lastSaleDate,
        'confidence': confidence,
        'price_trend': priceTrend,
        'trend_since_ops': trendSinceOps,
        'updated_at': DateTime.now().toIso8601String(),
      });

      // إضافة آخر 20 عملية للـ buffer
      final recentSales = sales.reversed.take(RECENT_SALES_LIMIT).toList();
      for (var sale in recentSales) {
        await db.insert('recent_sales_buffer', {
          'product_id': productId,
          'customer_id': sale['customer_id'],
          'price': sale['price'],
          'sale_type': sale['sale_type'],
          'invoice_date': sale['invoice_date'],
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      processedProducts++;
      if (processedProducts % 100 == 0) {
        print('📊 Processed $processedProducts products...');
      }
    }

    // 5. بناء إحصائيات الزبون+المنتج
    for (var entry in customerProductSales.entries) {
      final parts = entry.key.split('_');
      final customerId = int.parse(parts[0]);
      final productId = int.parse(parts[1]);
      final sales = entry.value;

      if (sales.isEmpty) continue;

      final prices = sales.map((s) => s['price'] as double).toList();
      final lastPrice = prices.last;
      final mostFrequent = _findMostFrequent(prices);
      final purchaseCount = sales.length;
      final lastPurchaseDate = sales.last['invoice_date'] as String;
      final confidence = _calculateConfidence(prices);

      await db.insert('customer_product_stats', {
        'customer_id': customerId,
        'product_id': productId,
        'last_price': lastPrice,
        'most_frequent_price': mostFrequent,
        'purchase_count': purchaseCount,
        'last_purchase_date': lastPurchaseDate,
        'confidence': confidence,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }

    print('✅ Smart Pricing: Trained ${productSales.length} products, ${customerProductSales.length} customer-product pairs');
  }

  /// 🎯 الحصول على السعر الذكي للمنتج (الخوارزمية الجديدة)
  Future<SmartPricingResult?> getSmartPriceEnhanced({
    required int productId,
    int? customerId,
    String? saleType,
    List<Map<String, dynamic>>? invoiceItemsContext, // [{ 'product_id': 1, 'applied_price': 100.0 }]
  }) async {
    final db = await _dbService!.database;

    // 📋 تحليل سياق الفاتورة (Invoice Context Analyzer)
    String? expectedLevel;
    double? productMedianPrice;
    
    // جلب متوسط سعر المنتج الحالي
    final statsMap = await db.query('product_price_stats', where: 'product_id = ?', whereArgs: [productId]);
    if (statsMap.isNotEmpty) {
      productMedianPrice = (statsMap.first['median_price'] as num).toDouble();
    }

    if (invoiceItemsContext != null && invoiceItemsContext.isNotEmpty) {
      List<Map<String, dynamic>> contextProducts = [];
      for(var item in invoiceItemsContext) {
         int pid = item['product_id'] as int;
         double price = (item['applied_price'] as num).toDouble();
         
         String level = 'average';
         final cStatsMap = await db.query('product_price_stats', where: 'product_id = ?', whereArgs: [pid]);
         if (cStatsMap.isNotEmpty) {
           double cMedian = (cStatsMap.first['median_price'] as num).toDouble();
           if (price <= cMedian * 0.95) {
             level = 'wholesale';
           } else if (price >= cMedian * 1.05) {
             level = 'retail';
           }
         }
         contextProducts.add({'id': pid, 'level': level});
      }
      
      // سؤال قاعدة بيانات البحث الذكي عن العلاقة السعرية
      expectedLevel = await SmartSearchDatabase.instance.getExpectedPriceLevel(
         queryProductId: productId,
         contextProducts: contextProducts,
      );
      
      // إذا لم يكن هناك تاريخ للعلاقة السعرية، نعتمد على الأغلبية في الفاتورة
      if (expectedLevel == null) {
         int w = contextProducts.where((p) => p['level'] == 'wholesale').length;
         int r = contextProducts.where((p) => p['level'] == 'retail').length;
         if (w > r) expectedLevel = 'wholesale';
         else if (r > w) expectedLevel = 'retail';
      }
    }

    // 🌟 تصنيف العميل التلقائي بناءً على المسحوبات (يتفوق على سياق الفاتورة)
    try {
      final appSettings = await SettingsManager.getAppSettings();
      final double wholesaleLimit = appSettings.wholesaleCustomerLimit;
      if (customerId != null && customerId > 0 && wholesaleLimit > 0) {
        final totalPurchases = await _dbService!.getCustomerTotalPurchases(customerId);
        if (totalPurchases >= wholesaleLimit) {
          expectedLevel = 'wholesale';
          print('🏆 Auto Segment: Customer $customerId is wholesale (Total: $totalPurchases)');
        }
      }
    } catch (e) {
      print('⚠️ Error checking wholesale limit: $e');
    }

    // 📋 الخطوة 1: جلب آخر 20 عملية للمنتج
    final recentSales = await db.rawQuery('''
      SELECT price, invoice_date FROM recent_sales_buffer
      WHERE product_id = ?
      ORDER BY invoice_date DESC
      LIMIT ?
    ''', [productId, RECENT_SALES_LIMIT]);

    // إذا لم توجد بيانات للمنتج، ارجع null
    if (recentSales.isEmpty) {
      print('⚠️ Smart Pricing: No data for product $productId');
      return null;
    }

    final recentPrices = recentSales.map((s) => (s['price'] as num).toDouble()).toList();

    // 📋 الخطوة 2: استخراج الأسعار المرشحة (الفريدة)
    final candidatePrices = <double, PriceCandidate>{};
    for (var price in recentPrices) {
      candidatePrices.putIfAbsent(price, () => PriceCandidate(price: price));
    }

    // 📋 الخطوة 3: حساب نقاط كل سعر مرشح
    for (var candidate in candidatePrices.values) {
      _calculatePriceScore(
        candidate: candidate,
        recentPrices: recentPrices,
        customerId: customerId,
        expectedLevel: expectedLevel,
        productMedianPrice: productMedianPrice,
      );
    }

    // 📋 الخطوة 4: إذا وُجد زبون، أضف نقاط تاريخه
    if (customerId != null && customerId > 0) {
      final customerStats = await _getCustomerProductStats(customerId, productId);
      if (customerStats != null && customerStats.purchaseCount >= 2) {
        final customerPrice = customerStats.mostFrequentPrice;
        if (candidatePrices.containsKey(customerPrice)) {
          candidatePrices[customerPrice]!.addPoints(
            POINTS_CUSTOMER_HISTORY,
            'سعر الزبون المعتاد (${customerStats.purchaseCount} عملية)',
          );
        } else {
          // أضف سعر الزبون كمرشح جديد
          candidatePrices[customerPrice] = PriceCandidate(price: customerPrice);
          candidatePrices[customerPrice]!.addPoints(
            POINTS_CUSTOMER_HISTORY,
            'سعر الزبون المعتاد (${customerStats.purchaseCount} عملية)',
          );
        }
      }
    }

    // 📋 الخطوة 5: اختر السعر الأعلى نقاطاً
    final sortedCandidates = candidatePrices.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final winner = sortedCandidates.first;
    final winnerScore = winner.score;
    
    // حساب نسبة الثقة بناءً على الفرق بين المرشحين
    int confidence = 50;
    if (sortedCandidates.length > 1) {
      final secondScore = sortedCandidates[1].score;
      final gap = winnerScore - secondScore;
      confidence = 50 + (gap * 2).clamp(0, 45);
    } else {
      confidence = 85;
    }

    // تحديد المصدر
    String source = 'تحليل السوق';
    if (winner.reasons.any((r) => r.contains('سياق الفاتورة'))) {
      source = 'سياق الفاتورة';
    } else if (winner.reasons.any((r) => r.contains('الزبون'))) {
      source = 'سجل الزبون';
    } else if (winner.reasons.any((r) => r.contains('المهيمن'))) {
      source = 'السعر المهيمن';
    } else if (winner.reasons.any((r) => r.contains('آخر 5'))) {
      source = 'عمليات حديثة';
    } else if (winner.reasons.any((r) => r.contains('الأخير'))) {
      source = 'آخر سعر';
    }

    // بناء خريطة النقاط للنتيجة
    final scoresMap = <double, int>{};
    for (var c in sortedCandidates.take(5)) {
      scoresMap[c.price] = c.score;
    }

    print('🔮 Smart Price for product $productId: ${winner.price} (score: $winnerScore, confidence: $confidence%)');
    print('   Candidates: ${scoresMap.entries.map((e) => "${e.key}=${e.value}").join(", ")}');

    // 🛡️ صمام الأمان: منع التوقع الأقل من سعر التكلفة
    try {
      final product = await _dbService!.getProductById(productId);
      if (product != null) {
        final cost = product.getProductCostForUnit(saleType ?? product.unit);
        if (cost != null && cost > 0 && winner.price < cost) {
          print('🛡️ Safety Guard: AI suggested ${winner.price} but cost is $cost. Rejecting suggestion.');
          return null; // رفض مقترح الذكاء الاصطناعي
        }
      }
    } catch (e) {
      print('⚠️ Error in safety guard: $e');
    }

    return SmartPricingResult(
      price: winner.price,
      confidence: confidence,
      source: source,
      reason: winner.reasons.join(' | '),
      candidateScores: scoresMap,
    );
  }

  /// حساب نقاط سعر مرشح
  void _calculatePriceScore({
    required PriceCandidate candidate,
    required List<double> recentPrices,
    int? customerId,
    String? expectedLevel,
    double? productMedianPrice,
  }) {
    final price = candidate.price;
    final totalSales = recentPrices.length;

    // 🏆 نقاط كونه آخر سعر
    if (recentPrices.first == price) {
      candidate.addPoints(POINTS_LAST_PRICE, 'آخر سعر');
    }

    // 🏆 نقاط الوجود في آخر 5 عمليات
    final last5 = recentPrices.take(5).toList();
    final countInLast5 = last5.where((p) => p == price).length;
    if (countInLast5 > 0) {
      candidate.addPoints(POINTS_IN_LAST_5 * countInLast5, 'في آخر 5 عمليات ($countInLast5 مرات)');
    }

    // 🏆 نقاط الوجود في آخر 10 عمليات
    final last10 = recentPrices.take(10).toList();
    final countInLast10 = last10.where((p) => p == price).length;
    if (countInLast10 > countInLast5) {
      candidate.addPoints(POINTS_IN_LAST_10 * (countInLast10 - countInLast5), 'في العمليات 6-10');
    }

    // 🏆 نقاط التكرار الكلي
    final totalOccurrences = recentPrices.where((p) => p == price).length;
    final frequencyPercent = totalOccurrences / totalSales;
    candidate.addPoints((POINTS_FREQUENCY_BONUS * frequencyPercent).round(), 'تكرار ${(frequencyPercent * 100).toStringAsFixed(0)}%');

    // 🏆 نقاط السعر المهيمن (> 60%)
    if (frequencyPercent >= 0.60) {
      candidate.addPoints(POINTS_DOMINANT_PRICE, 'سعر مهيمن (${(frequencyPercent * 100).toStringAsFixed(0)}%)');
    }

    // 🏆 نقاط اتجاه السعر
    if (recentPrices.length >= 5) {
      final last5Avg = last5.reduce((a, b) => a + b) / 5;
      final first5Avg = recentPrices.reversed.take(5).toList().reduce((a, b) => a + b) / 5;
      
      // إذا كان السعر قريباً من متوسط آخر 5 (اتجاه حديث)
      if ((price - last5Avg).abs() < last5Avg * 0.05) {
        candidate.addPoints(POINTS_TREND_MATCH, 'يتوافق مع اتجاه السعر الحالي');
      }
    }

    // 🏆 نقاط سياق الفاتورة (جملة / مفرق)
    if (expectedLevel != null && productMedianPrice != null) {
      if (expectedLevel == 'wholesale' && price <= productMedianPrice * 0.95) {
        candidate.addPoints(POINTS_CONTEXT_MATCH, 'يتوافق مع أسعار الجملة لسياق الفاتورة الحالية');
      } else if (expectedLevel == 'retail' && price >= productMedianPrice * 1.05) {
        candidate.addPoints(POINTS_CONTEXT_MATCH, 'يتوافق مع أسعار المفرق لسياق الفاتورة الحالية');
      }
    }
  }

  /// تحديث الإحصائيات عند حفظ فاتورة جديدة
  Future<void> updateOnInvoiceSave({
    required int productId,
    int? customerId,
    required double price,
    String? saleType,
    required String invoiceDate,
  }) async {
    final db = await _dbService!.database;

    // 1. تحديث إحصائيات المنتج
    await _updateProductStats(productId, price, invoiceDate);

    // 2. تحديث إحصائيات الزبون+المنتج (إذا وُجد زبون)
    if (customerId != null && customerId > 0) {
      await _updateCustomerProductStats(customerId, productId, price, invoiceDate);
    }

    // 3. إضافة للـ buffer مع الحفاظ على آخر 20 فقط
    await _addToRecentSalesBuffer(productId, customerId, price, saleType, invoiceDate);
  }

  /// تحديث إحصائيات المنتج
  Future<void> _updateProductStats(int productId, double price, String invoiceDate) async {
    final db = await _dbService!.database;

    // جلب الأسعار الحديثة
    final recentPrices = await _getRecentPrices(productId, limit: RECENT_SALES_LIMIT);
    recentPrices.add(price);

    final mostFrequent = _findMostFrequent(recentPrices);
    final median = _calculateMedian(recentPrices);
    final confidence = _calculateConfidence(recentPrices);
    
    // تحليل الاتجاه
    final trendAnalysis = _analyzeTrend(recentPrices);

    await db.insert(
      'product_price_stats',
      {
        'product_id': productId,
        'last_price': price,
        'most_frequent_price': mostFrequent,
        'median_price': median,
        'sale_count': Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM recent_sales_buffer WHERE product_id = ?',
                [productId],
              ),
            ) ?? 0 + 1,
        'last_sale_date': invoiceDate,
        'confidence': confidence,
        'price_trend': trendAnalysis['trend'],
        'trend_since_ops': trendAnalysis['since'],
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// تحديث إحصائيات الزبون+المنتج
  Future<void> _updateCustomerProductStats(
    int customerId,
    int productId,
    double price,
    String invoiceDate,
  ) async {
    final db = await _dbService!.database;

    // جلب الأسعار السابقة للزبون مع المنتج
    final existingStats = await db.query(
      'customer_product_stats',
      where: 'customer_id = ? AND product_id = ?',
      whereArgs: [customerId, productId],
    );

    List<double> prices = [];
    if (existingStats.isNotEmpty) {
      // جلب الأسعار من recent_sales_buffer لهذا الزبون والمنتج
      final customerSales = await db.rawQuery('''
        SELECT price FROM recent_sales_buffer
        WHERE product_id = ? AND customer_id = ?
        ORDER BY invoice_date DESC
        LIMIT ?
      ''', [productId, customerId, RECENT_SALES_LIMIT]);
      
      prices = customerSales.map((s) => (s['price'] as num).toDouble()).toList();
    }
    prices.add(price);

    final mostFrequent = _findMostFrequent(prices);
    final confidence = _calculateConfidence(prices);

    await db.insert(
      'customer_product_stats',
      {
        'customer_id': customerId,
        'product_id': productId,
        'last_price': price,
        'most_frequent_price': mostFrequent,
        'purchase_count': prices.length,
        'last_purchase_date': invoiceDate,
        'confidence': confidence,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// إضافة للـ buffer مع الحفاظ على آخر N فقط
  Future<void> _addToRecentSalesBuffer(
    int productId,
    int? customerId,
    double price,
    String? saleType,
    String invoiceDate,
  ) async {
    final db = await _dbService!.database;

    // إضافة السجل الجديد
    await db.insert('recent_sales_buffer', {
      'product_id': productId,
      'customer_id': customerId,
      'price': price,
      'sale_type': saleType ?? '',
      'invoice_date': invoiceDate,
      'created_at': DateTime.now().toIso8601String(),
    });

    // حذف الأسعار القديمة (أبعد من آخر 20)
    await db.rawDelete('''
      DELETE FROM recent_sales_buffer
      WHERE product_id = ? AND id NOT IN (
        SELECT id FROM recent_sales_buffer
        WHERE product_id = ?
        ORDER BY invoice_date DESC
        LIMIT ?
      )
    ''', [productId, productId, RECENT_SALES_LIMIT]);
  }

  /// جلب إحصائيات الزبون مع المنتج
  Future<CustomerProductStats?> _getCustomerProductStats(int customerId, int productId) async {
    final db = await _dbService!.database;
    
    final results = await db.query(
      'customer_product_stats',
      where: 'customer_id = ? AND product_id = ?',
      whereArgs: [customerId, productId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return CustomerProductStats.fromMap(results.first);
  }

  /// جلب آخر N سعر للمنتج
  Future<List<double>> _getRecentPrices(int productId, {int limit = 20}) async {
    final db = await _dbService!.database;
    
    final results = await db.rawQuery('''
      SELECT price FROM recent_sales_buffer
      WHERE product_id = ?
      ORDER BY invoice_date DESC
      LIMIT ?
    ''', [productId, limit]);

    return results.map((r) => (r['price'] as num).toDouble()).toList();
  }

  /// إيجاد السعر الأكثر تكراراً
  double _findMostFrequent(List<double> prices) {
    if (prices.isEmpty) return 0;
    
    final frequencyMap = <double, int>{};
    for (var price in prices) {
      frequencyMap[price] = (frequencyMap[price] ?? 0) + 1;
    }

    double mostFrequent = prices.first;
    int maxCount = 0;
    frequencyMap.forEach((price, count) {
      if (count > maxCount) {
        maxCount = count;
        mostFrequent = price;
      }
    });

    return mostFrequent;
  }

  /// حساب الوسيط (Median)
  double _calculateMedian(List<double> prices) {
    if (prices.isEmpty) return 0;
    
    final sorted = List<double>.from(prices)..sort();
    final length = sorted.length;
    
    if (length % 2 == 0) {
      return (sorted[length ~/ 2 - 1] + sorted[length ~/ 2]) / 2;
    } else {
      return sorted[length ~/ 2];
    }
  }

  /// تحليل اتجاه السعر
  Map<String, dynamic> _analyzeTrend(List<double> prices) {
    if (prices.length < 5) {
      return {'trend': 'غير محدد', 'since': 0};
    }

    // نبحث عن نقطة التغيير
    final reversed = prices.reversed.toList();
    double? currentTrend;
    int trendSince = 0;

    for (int i = 0; i < reversed.length - 1; i++) {
      if (reversed[i] == reversed[i + 1]) {
        continue;
      }
      
      if (currentTrend == null) {
        currentTrend = reversed[i];
        trendSince = i + 1;
      } else if (reversed[i] != currentTrend) {
        break;
      }
      trendSince++;
    }

    // تحديد نوع الاتجاه
    final last5 = reversed.take(5).toList();
    final first5 = reversed.skip(reversed.length - 5).take(5).toList();
    
    final last5Avg = last5.reduce((a, b) => a + b) / 5;
    final first5Avg = first5.reduce((a, b) => a + b) / 5;

    String trend;
    if (last5Avg > first5Avg * 1.05) {
      trend = 'ارتفاع';
    } else if (last5Avg < first5Avg * 0.95) {
      trend = 'انخفاض';
    } else {
      trend = 'مستقر';
    }

    return {
      'trend': trend,
      'since': trendSince,
    };
  }

  /// حساب نسبة الثقة (0-100)
  int _calculateConfidence(List<double> prices) {
    if (prices.isEmpty) return 0;
    if (prices.length < 3) return 30; // بيانات قليلة

    // حساب معامل الاختلاف (Coefficient of Variation)
    final mean = prices.reduce((a, b) => a + b) / prices.length;
    if (mean == 0) return 0;

    final variance = prices.map((p) => pow(p - mean, 2)).reduce((a, b) => a + b) / prices.length;
    final stdDev = sqrt(variance);
    final cv = stdDev / mean;

    // تحويل إلى ثقة
    // كلما كان التشتت أقل، كانت الثقة أعلى
    if (cv < 0.05) return 98; // أسعار متقاربة جداً
    if (cv < 0.10) return 90;
    if (cv < 0.15) return 80;
    if (cv < 0.20) return 70;
    if (cv < 0.30) return 60;
    if (cv < 0.50) return 50;
    return 40; // تشتت عالي
  }

  /// الحصول على إحصائيات المنتج
  Future<ProductPriceStats?> getProductStats(int productId) async {
    final db = await _dbService!.database;
    
    final results = await db.query(
      'product_price_stats',
      where: 'product_id = ?',
      whereArgs: [productId],
      limit: 1,
    );

    if (results.isEmpty) return null;
    return ProductPriceStats.fromMap(results.first);
  }

  /// جلب آخر العمليات للمنتج
  Future<List<Map<String, dynamic>>> getRecentSales(int productId, {int limit = 20}) async {
    final db = await _dbService!.database;
    
    return await db.rawQuery('''
      SELECT rsb.*, c.name as customer_name
      FROM recent_sales_buffer rsb
      LEFT JOIN customers c ON c.id = rsb.customer_id
      WHERE rsb.product_id = ?
      ORDER BY rsb.invoice_date DESC
      LIMIT ?
    ''', [productId, limit]);
  }
}
