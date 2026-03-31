// lib/services/invoice_prediction_service.dart
// خدمة التوقعات الذكية للفواتير - نظام النقاط المتقدم

import '../models/invoice_prediction.dart';
import '../models/product.dart';
import '../models/invoice_item.dart';
import 'database_service.dart';

class InvoicePredictionService {
  static InvoicePredictionService? _instance;
  final DatabaseService _db;

  InvoicePredictionService._() : _db = DatabaseService();

  static InvoicePredictionService get instance {
    _instance ??= InvoicePredictionService._();
    return _instance!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // نظام النقاط مع التلاشي الزمني
  // ═══════════════════════════════════════════════════════════════════════════

  /// حساب معامل التلاشي الزمني (نفس البحث الذكي)
  /// يتناقص بمقدار 10% كل شهر
  double _calculateTimeDecay(DateTime invoiceDate) {
    final now = DateTime.now();
    final differenceInDays = now.difference(invoiceDate).inDays;
    final monthsPassed = differenceInDays / 30;
    double decay = 1.0 - (monthsPassed * 0.1);
    return decay.clamp(0.0, 1.0);
  }

  /// حساب نقاط منتج واحد
  /// النقاط = عدد_الظهور × 10 × معامل_التلاشي × وزن_الشخص
  double _calculateProductScore({
    required int occurrenceCount,
    required DateTime lastOccurrence,
    required bool isInstaller,
  }) {
    const basePoints = 10.0;
    final timeDecay = _calculateTimeDecay(lastOccurrence);
    final personWeight = isInstaller ? 1.5 : 1.0;
    
    return occurrenceCount * basePoints * timeDecay * personWeight;
  }

  /// الحصول على التوقعات بنظام النقاط المتقدم
  Future<List<InvoicePrediction>> getPredictions({
    String? customerName,
    int? customerId,
    String? installerName,
  }) async {
    try {
      // 1. حساب حجم السلة المستهدف (متوسط عدد الأصناف المعتاد)
      final targetSize = await _calculateTargetBasketSize(
        installerName: installerName,
        customerName: customerName,
      );

      // 2. جمع معلومات المنتجات والارتباطات (Co-occurrence)
      final personData = await _collectPersonAndClusterData(
        installerName: installerName,
        customerName: customerName,
      );

      if (personData.productData.isEmpty) {
        return [];
      }

      // 3. توليد 5 سيناريوهات متنوعة (Diverse Scenarios)
      return await _generateDiverseScenarios(
        personData,
        targetSize: targetSize,
        installerName: installerName,
        customerName: customerName,
      );
    } catch (e) {
      print('❌ Error getting predictions: $e');
      return [];
    }
  }

  /// حساب حجم السلة المستهدف (متوسط عدد الأصناف التي يطلبها الشخص عادة)
  Future<int> _calculateTargetBasketSize({
    String? installerName,
    String? customerName,
  }) async {
    try {
      final db = await _db.database;
      final personField = (installerName != null && installerName.isNotEmpty)
          ? 'installer_name'
          : 'customer_name';
      final personValue = (installerName != null && installerName.isNotEmpty)
          ? installerName
          : customerName;

      final results = await db.rawQuery('''
        SELECT COUNT(ii.id) as item_count
        FROM invoice_items ii
        JOIN invoices i ON ii.invoice_id = i.id
        WHERE i.$personField = ?
          AND i.status != 'معلقة'
        GROUP BY i.id
        ORDER BY i.invoice_date DESC
        LIMIT 20
      ''', [personValue]);

      if (results.isEmpty) return 7; // قيمة افتراضية منطقية

      final counts = results.map((r) => r['item_count'] as int).toList();
      final avg = counts.reduce((a, b) => a + b) / counts.length;
      
      // نختار القيمة الأكثر تكراراً (Mode) أو المتوسط لقرب الصواب
      return avg.round().clamp(5, 25);
    } catch (e) {
      return 10;
    }
  }

  /// جمع بيانات شخص (فني أو عميل) مع بناء مصفوفة الارتباط
  Future<_PersonClusterData> _collectPersonAndClusterData({
    String? installerName,
    String? customerName,
  }) async {
    final db = await _db.database;
    final useInstaller = installerName != null && installerName.isNotEmpty;
    final personName = useInstaller ? installerName : customerName;

    // جلب آخر 2000 فاتورة للشخص (لتحليل شامل مع أداء جيد)
    final invoices = await db.rawQuery('''
      SELECT id, invoice_date
      FROM invoices
      WHERE ${useInstaller ? 'installer_name' : 'customer_name'} = ?
        AND status != 'معلقة'
      ORDER BY invoice_date DESC
      LIMIT 2000
    ''', [personName]);

    final Map<String, _ProductData> productDataMap = {};
    final Map<String, Map<String, int>> coOccurrence = {};

    // معالجة كل فاتورة
    for (final invoice in invoices) {
      final invoiceId = invoice['id'] as int;
      final invoiceDate = DateTime.parse(invoice['invoice_date'] as String);
      
      final items = await db.query(
        'invoice_items',
        where: 'invoice_id = ?',
        whereArgs: [invoiceId],
        orderBy: 'id ASC',
      );

      final invoiceProducts = <String>{};

      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final productName = item['product_name'] as String;
        invoiceProducts.add(productName);

        if (!productDataMap.containsKey(productName)) {
          productDataMap[productName] = _ProductData(
            productId: item['product_id'] as int?,
            productName: productName,
          );
        }

        final data = productDataMap[productName]!;
        data.occurrences.add(_ProductOccurrence(
          invoiceDate: invoiceDate,
          quantity: ((item['quantity_individual'] ?? item['quantity_large_unit'] ?? 0) as num).toDouble(),
          price: (item['applied_price'] as num).toDouble(),
          saleType: item['sale_type'] as String? ?? 'قطعة',
          position: i,
        ));
      }

      // بناء مصفوفة الارتباط (Co-occurrence)
      final List<String> pList = invoiceProducts.toList();
      for (int i = 0; i < pList.length; i++) {
        for (int j = i + 1; j < pList.length; j++) {
          final pA = pList[i];
          final pB = pList[j];
          
          coOccurrence[pA] ??= {};
          coOccurrence[pA]![pB] = (coOccurrence[pA]![pB] ?? 0) + 1;
          
          coOccurrence[pB] ??= {};
          coOccurrence[pB]![pA] = (coOccurrence[pB]![pA] ?? 0) + 1;
        }
      }
    }

    // حساب النقاط الكلية لكل منتج
    final Map<String, _ScoredProduct> productScores = {};
    for (final entry in productDataMap.entries) {
      final data = entry.value;
      final score = _calculateProductScore(
        occurrenceCount: data.occurrences.length,
        lastOccurrence: data.occurrences.first.invoiceDate,
        isInstaller: useInstaller,
      );
      
      productScores[entry.key] = _ScoredProduct(
        productId: data.productId,
        productName: entry.key,
        score: score,
        occurrences: data.occurrences,
      );
    }

    return _PersonClusterData(
      productData: productScores,
      coOccurrence: coOccurrence,
    );
  }

  /// توليد 5 سيناريوهات متنوعة (Diverse Scenarios) باستخدام خوارزمية العناقيد
  Future<List<InvoicePrediction>> _generateDiverseScenarios(
    _PersonClusterData data, {
    required int targetSize,
    String? installerName,
    String? customerName,
  }) async {
    final List<InvoicePrediction> scenarios = [];
    final List<Set<String>> previousClusters = [];
    
    // عناوين السيناريوهات لتعكس مراحل العمل أو الأنماط
    final List<String> scenarioTitles = [
      'النمط الأساسي (Master Cluster)',
      'النمط البديل 1 (Variation 1)',
      'النمط البديل 2 (Variation 2)',
      'سيناريو عمل مختلف 1',
      'سيناريو عمل مختلف 2',
    ];

    // توليد 5 سيناريوهات
    for (int i = 0; i < 5; i++) {
      // 1. حساب "عقوبة التشابه" للمنتجات التي ظهرت في العناقيد السابقة لضمان التنوع
      final adjustedScores = <String, double>{};
      
      for (final entry in data.productData.entries) {
        final productName = entry.key;
        double score = entry.value.score;
        
        // تطبيق العقوبة: كلما زاد ظهور المنتج في العناقيد السابقة، قلت فرصة ظهوره مجدداً
        double penalty = 1.0;
        for (final cluster in previousClusters) {
          if (cluster.contains(productName)) {
            penalty *= 0.2; // عقوبة قاسية لضمان التنوع الحقيقي
          }
        }
        
        adjustedScores[productName] = score * penalty;
      }

      // 2. بناء العنقود الجديد (Greedy Expansion)
      final cluster = await _buildCluster(
        data: data,
        adjustedScores: adjustedScores,
        targetSize: targetSize,
      );

      if (cluster.isEmpty) continue;

      // 3. تحويل العنقود إلى كائن InvoicePrediction
      final items = <PredictedItem>[];
      for (final productName in cluster) {
        final pData = data.productData[productName]!;
        items.add(await _buildPredictedItem(pData));
      }

      scenarios.add(InvoicePrediction(
        type: 'cluster_$i',
        title: scenarioTitles[i],
        items: items,
        totalAmount: items.fold(0, (sum, item) => sum + (item.price * item.quantity)),
        score: (100 - (i * 10)).toDouble(), // نقاط تنازلية لترتيب العرض
      ));

      // إضافة العنقود الحالي لقائمة السابقين لتجنبه في المرة القادمة
      previousClusters.add(Set.from(cluster));
    }

    return scenarios;
  }

  /// خوارزمية التوسع الجشع (Greedy Expansion) لبناء عنقود مترابط
  Future<List<String>> _buildCluster({
    required _PersonClusterData data,
    required Map<String, double> adjustedScores,
    required int targetSize,
  }) async {
    final List<String> cluster = [];
    final Set<String> candidates = Set.from(adjustedScores.keys);

    if (candidates.isEmpty) return [];

    // 1. اختيار المنتج الأساسي (أعلى سكور معدل)
    final coreProduct = candidates.toList()
      ..sort((a, b) => adjustedScores[b]!.compareTo(adjustedScores[a]!));
    
    final firstProduct = coreProduct.first;
    cluster.add(firstProduct);
    candidates.remove(firstProduct);

    // 2. التوسع تدريجياً بإضافة المنتجات الأكثر ارتباطاً بالمجموعة الحالية
    while (cluster.length < targetSize && candidates.isNotEmpty) {
      String? bestCandidate;
      double bestStrength = -1.0;

      for (final candidate in candidates) {
        // حساب قوة ارتباط المرشح بكامل العنقود الحالي (متوسط الارتباط)
        double totalAssociation = 0;
        int links = 0;

        for (final clusteredProduct in cluster) {
          final count = data.coOccurrence[clusteredProduct]?[candidate] ?? 0;
          if (count > 0) {
            totalAssociation += count;
            links++;
          }
        }

        if (links == 0) continue; // لا يستحق الإضافة إذا لم يكن مرتبطاً بأي عنصر

        // معادلة القوة: (متوسط الارتباط بالداخل) × (سكور المنتج الأصلي)
        // هذا يحقق التوازن بين "انتماء المنتج للمجموعة" و "أهمية المنتج الفردية"
        final strength = (totalAssociation / cluster.length) * (adjustedScores[candidate] ?? 1.0);

        if (strength > bestStrength) {
          bestStrength = strength;
          bestCandidate = candidate;
        }
      }

      if (bestCandidate == null) break; // توقف إذا لم تعد هناك منتجات مرتبطة

      cluster.add(bestCandidate);
      candidates.remove(bestCandidate);
    }

    return cluster;
  }

  /// بناء صنف متوقع واحد مع حساب المتوسطات بدقة
  Future<PredictedItem> _buildPredictedItem(_ScoredProduct p) async {
    // حساب نوع البيع الأكثر تكراراً
    final saleTypeCounts = <String, int>{};
    for (final occ in p.occurrences) {
      saleTypeCounts[occ.saleType] = (saleTypeCounts[occ.saleType] ?? 0) + 1;
    }
    
    final favoriteSaleType = saleTypeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final saleType = favoriteSaleType.first.key;

    // تصفية الظهورات لتشمل فقط نوع البيع المفضل لضمان دقة السعر والكمية
    final relevantOccurrences = p.occurrences
        .where((o) => o.saleType == saleType)
        .toList();

    // حساب متوسط السعر والكمية من آخر 3 مرات بهذا النوع
    final last3 = relevantOccurrences.take(3).toList();
    
    double avgPrice = last3.map((o) => o.price).reduce((a, b) => a + b) / last3.length;
    double avgQty = last3.map((o) => o.quantity).reduce((a, b) => a + b) / last3.length;

    return PredictedItem(
      productId: p.productId,
      productName: p.productName,
      quantity: avgQty,
      price: avgPrice,
      saleType: saleType,
    );
  }
  }

  /// التدريب على فاتورة جديدة (للتوافق مع الكود القديم)
  Future<void> trainOnInvoice(int invoiceId) async {
    // لا حاجة للتدريب في نظام النقاط - البيانات تُجمع مباشرة
    print('✅ Invoice $invoiceId processed (no training needed in scoring system)');
  }
  
  /// اختبار النظام والتحقق من البيانات
  /// يقوم بتحليل عينة من الفواتير والتحقق من جودة التوقعات
  Future<PredictionTestStats> testPredictionSystem({
    Function(int current, int total, String message)? onProgress,
  }) async {
    final startTime = DateTime.now();
    print('🧪 بدء اختبار نظام التوقعات...');
    
    final stats = PredictionTestStats();
    
    try {
      // 1. جلب عينة من الفواتير (آخر 100 فاتورة)
      onProgress?.call(0, 0, 'جاري جلب الفواتير...');
      final db = await _db.database;
      final invoices = await db.rawQuery('''
        SELECT id, customer_name, installer_name, invoice_date
        FROM invoices
        WHERE status != 'معلقة'
        ORDER BY invoice_date DESC
        LIMIT 100
      ''');
      
      stats.totalInvoices = invoices.length;
      print('📊 عدد الفواتير للاختبار: ${invoices.length}');
      
      if (invoices.isEmpty) {
        print('⚠️ لا توجد فواتير للاختبار');
        return stats;
      }
      
      // 2. اختبار عينة من الفواتير
      int tested = 0;
      for (final invoice in invoices.take(20)) {
        tested++;
        onProgress?.call(tested, 20, 'اختبار الفاتورة $tested من 20...');
        
        final customerName = invoice['customer_name'] as String?;
        final installerName = invoice['installer_name'] as String?;
        
        if ((customerName == null || customerName.isEmpty) &&
            (installerName == null || installerName.isEmpty)) {
          continue;
        }
        
        try {
          // محاولة الحصول على توقعات
          final predictions = await getPredictions(
            customerName: customerName,
            installerName: installerName,
          );
          
          if (predictions.isNotEmpty) {
            stats.successfulPredictions++;
            stats.totalPredictions += predictions.length;
            
            // حساب متوسط عدد المنتجات في التوقعات
            for (final pred in predictions) {
              stats.totalProducts += pred.items.length;
            }
          }
        } catch (e) {
          print('⚠️ خطأ في اختبار الفاتورة: $e');
          stats.failedPredictions++;
        }
      }
      
      // 3. حساب الإحصائيات
      stats.duration = DateTime.now().difference(startTime);
      if (stats.totalPredictions > 0) {
        stats.avgProductsPerPrediction = stats.totalProducts / stats.totalPredictions;
      }
      
      print('✅ انتهى الاختبار');
      print('   - فواتير تم اختبارها: $tested');
      print('   - توقعات ناجحة: ${stats.successfulPredictions}');
      print('   - توقعات فاشلة: ${stats.failedPredictions}');
      print('   - إجمالي التوقعات: ${stats.totalPredictions}');
      print('   - متوسط المنتجات: ${stats.avgProductsPerPrediction.toStringAsFixed(1)}');
      print('   - المدة: ${stats.duration.inSeconds} ثانية');
      
    } catch (e) {
      print('❌ خطأ في اختبار النظام: $e');
    }
    
    return stats;
  }
  
  /// التحقق من وجود بيانات كافية للتوقعات
  Future<bool> hasEnoughData() async {
    try {
      final db = await _db.database;
      final result = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM invoices
        WHERE status != 'معلقة'
      ''');
      
      final count = result.first['count'] as int;
      return count >= 10; // على الأقل 10 فواتير
    } catch (e) {
      print('❌ خطأ في التحقق من البيانات: $e');
      return false;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// النماذج الداخلية
// ═══════════════════════════════════════════════════════════════════════════

/// هيكل بيانات عنقود الشخص
class _PersonClusterData {
  final Map<String, _ScoredProduct> productData;
  final Map<String, Map<String, int>> coOccurrence;

  _PersonClusterData({
    required this.productData,
    required this.coOccurrence,
  });
}

/// بيانات منتج واحد
class _ProductData {
  final int? productId;
  final String productName;
  final List<_ProductOccurrence> occurrences = [];

  _ProductData({
    required this.productId,
    required this.productName,
  });
}

/// ظهور منتج في فاتورة
class _ProductOccurrence {
  final DateTime invoiceDate;
  final double quantity;
  final double price;
  final String saleType;
  final int position; // موقع المنتج في الفاتورة

  _ProductOccurrence({
    required this.invoiceDate,
    required this.quantity,
    required this.price,
    required this.saleType,
    required this.position,
  });
}

/// منتج مع نقاطه
class _ScoredProduct {
  final int? productId;
  final String productName;
  double score;
  final List<_ProductOccurrence> occurrences;

  _ScoredProduct({
    required this.productId,
    required this.productName,
    required this.score,
    required this.occurrences,
  });
}

/// منتج مع نقاط الترتيب
class _ProductWithOrderScore {
  final _ScoredProduct scoredProduct;
  final double orderScore;
  final double avgPosition;

  _ProductWithOrderScore({
    required this.scoredProduct,
    required this.orderScore,
    required this.avgPosition,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// إحصائيات اختبار النظام
// ═══════════════════════════════════════════════════════════════════════════

/// إحصائيات اختبار نظام التوقعات
class PredictionTestStats {
  int totalInvoices = 0;
  int successfulPredictions = 0;
  int failedPredictions = 0;
  int totalPredictions = 0;
  int totalProducts = 0;
  double avgProductsPerPrediction = 0.0;
  Duration duration = Duration.zero;
  
  PredictionTestStats();
  
  @override
  String toString() {
    return '''
إحصائيات اختبار نظام التوقعات:
  - إجمالي الفواتير: $totalInvoices
  - توقعات ناجحة: $successfulPredictions
  - توقعات فاشلة: $failedPredictions
  - إجمالي التوقعات: $totalPredictions
  - إجمالي المنتجات: $totalProducts
  - متوسط المنتجات لكل توقع: ${avgProductsPerPrediction.toStringAsFixed(1)}
  - المدة: ${duration.inSeconds} ثانية
''';
  }
}
