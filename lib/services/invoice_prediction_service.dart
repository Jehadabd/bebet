// lib/services/invoice_prediction_service.dart
// خدمة التوقعات الذكية للفواتير - نظام الخبير (Expert Thinking System)
// يعتمد على Confidence, Lift, Negative Filtering, و Diverse Scenarios

import '../models/invoice_prediction.dart';
import '../models/product.dart';
import '../models/invoice_item.dart';
import 'database_service.dart';
import 'expert_training_service.dart'; // 🧠 محرك التدريب المستقل
import 'dart:math';

class InvoicePredictionService {
  static InvoicePredictionService? _instance;
  final DatabaseService _db;

  InvoicePredictionService._() : _db = DatabaseService();

  static InvoicePredictionService get instance {
    _instance ??= InvoicePredictionService._();
    return _instance!;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // نظام التفكير الخبير (المقاييس الإحصائية: Support, Confidence, Lift)
  // ═══════════════════════════════════════════════════════════════════════════

  /// الحصول على التوقعات بنظام التفكير الخبير المتقدم
  Future<List<InvoicePrediction>> getPredictions({
    String? customerName,
    int? customerId,
    String? installerName,
  }) async {
    try {
      // 1. حساب حجم السلة المستهدف (العدد الأكثر تكراراً "المنوال" وليس المتوسط)
      final targetSize = await _calculateTargetBasketSize(
        installerName: installerName,
        customerName: customerName,
      );

      // 2. جمع معلومات المنتجات وارتباطاتها وتعداد الفواتير الكلي N
      final personData = await _collectPersonAndClusterData(
        installerName: installerName,
        customerName: customerName,
      );

      if (personData.productData.isEmpty || personData.totalInvoices == 0) {
        return [];
      }

      // 3. جلب القوانين العالمية الجاهزة من محرك التدريب الشامل والمستقل
      final globalLifts = await ExpertTrainingService.instance.getGlobalLiftsForNames(
        personData.productData.keys.toList()
      );
      final globalSequences = await ExpertTrainingService.instance.getGlobalSequences();
      
      // نحقن القوانين العالمية داخل العنقود الخاص بالشخص
      personData.globalLifts = globalLifts;
      personData.globalSequences = globalSequences;

      // 4. توليد 5 سيناريوهات ذكية ومختلفة (Top-K Diverse Scenarios)
      return await _generateDiverseScenarios(
        personData,
        targetSize: targetSize,
        installerName: installerName,
        customerName: customerName,
      );
    } catch (e) {
      print('❌ Error getting expert predictions: $e');
      return [];
    }
  }

  /// التحقق السريع مما إذا كان للعميل أو الفني سجل فواتير للقيام بالتوقع
  Future<bool> hasHistory({String? installerName, String? customerName}) async {
    try {
      final db = await _db.database;
      final useInstaller = installerName != null && installerName.isNotEmpty;
      
      // نبدأ بالبحث عن الفني إذا كان موجوداً
      if (useInstaller) {
        final results = await db.rawQuery('''
          SELECT id FROM invoices 
          WHERE installer_name = ? AND status != 'معلقة' 
          LIMIT 1
        ''', [installerName]);
        if (results.isNotEmpty) return true;
      }

      // إذا لم يكن هنالك فني أو لم نجد له تاريخ، نبحث عن العميل كملاذ بديل
      if (customerName != null && customerName.isNotEmpty) {
        final results = await db.rawQuery('''
          SELECT id FROM invoices 
          WHERE customer_name = ? AND status != 'معلقة' 
          LIMIT 1
        ''', [customerName]);
        if (results.isNotEmpty) return true;
      }

      return false;
    } catch (e) {
      print('Error checking prediction history: $e');
      return false;
    }
  }

  /// حساب حجم السلة باستخدام الـ منوال (Mode - الأكثر تكراراً) لمنع الإضافة العشوائية
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
      
      // إيجاد المنوال (العدد الأكثر تكراراً)
      final frequencyMap = <int, int>{};
      int mode = counts.first;
      int maxFreq = 0;
      
      for (final count in counts) {
        frequencyMap[count] = (frequencyMap[count] ?? 0) + 1;
        if (frequencyMap[count]! > maxFreq) {
          maxFreq = frequencyMap[count]!;
          mode = count;
        }
      }
      
      return mode.clamp(3, 25);
    } catch (e) {
      return 10;
    }
  }

  /// جمع بيانات الشخص الإحصائية وتشكيل مصفوفة الارتباط (Co-occurrence)
  Future<_PersonClusterData> _collectPersonAndClusterData({
    String? installerName,
    String? customerName,
  }) async {
    final db = await _db.database;
    final useInstaller = installerName != null && installerName.isNotEmpty;
    final personName = useInstaller ? installerName : customerName;

    // جلب آخر 2000 فاتورة كعينة عريضة (لتكوين قواعد الموثوقية بوضوح)
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
    int totalInvoicesAnalysed = 0;

    for (final invoice in invoices) {
      totalInvoicesAnalysed++;
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
        // تسجيل الظهور (Support)
        data.occurrences.add(_ProductOccurrence(
          invoiceDate: invoiceDate,
          quantity: ((item['quantity_individual'] ?? item['quantity_large_unit'] ?? 0) as num).toDouble(),
          price: (item['applied_price'] as num).toDouble(),
          saleType: item['sale_type'] as String? ?? 'قطعة',
          position: i,
        ));
      }

      // بناء مصفوفة الارتباط (Co-occurrence) - تستخدم كـ Support لزوج من المنتجات
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

    final Map<String, _ScoredProduct> productScores = {};
    for (final entry in productDataMap.entries) {
      final data = entry.value;
      
      // النقاط المبدئية هي وتيرة التكرار بالإضافة لوزن الشخص
      final baseScore = data.occurrences.length * (useInstaller ? 1.5 : 1.0);
      
      productScores[entry.key] = _ScoredProduct(
        productId: data.productId,
        productName: entry.key,
        score: baseScore, // Base Support Score
        occurrences: data.occurrences,
      );
    }

    return _PersonClusterData(
      productData: productScores,
      coOccurrence: coOccurrence,
      totalInvoices: totalInvoicesAnalysed,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // محرك التوليد الذكي والعلاقات السلبية (Negative Rules & Lift)
  // ═══════════════════════════════════════════════════════════════════════════

  /// الحصول على الـ Support الفردي P(A) المرجح
  double _getSupport(String p, _PersonClusterData data) {
    return data.productData[p]?.occurrences.length.toDouble() ?? 0.0;
  }

  /// الحصول على الجداء الثنائي المشترك P(A&B) 
  double _getSharedSupport(String p1, String p2, _PersonClusterData data) {
    return data.coOccurrence[p1]?[p2]?.toDouble() ?? 0.0;
  }

  /// حساب الثقة Confidence P(B|A)
  double _getConfidence(String pA, String pB, _PersonClusterData data) {
    final supportA = _getSupport(pA, data);
    if (supportA == 0) return 0.0;
    return _getSharedSupport(pA, pB, data) / supportA;
  }

  /// حساب قوة الترابط الحقيقية (Lift) 🔥 لاكتشاف العلاقات السلبية 
  double _getLift(String p1, String p2, _PersonClusterData data) {
    // 1️⃣ الأولوية العظمى لقوانين الرفع العالمية (Global Lift) إذا كانت مدربة
    if (data.globalLifts.containsKey(p1) && data.globalLifts[p1]!.containsKey(p2)) {
      return data.globalLifts[p1]![p2]!;
    }

    // 2️⃣ الحساب المحلي في حال عدم وجود تدريب مسبق
    final support1 = _getSupport(p1, data);
    final support2 = _getSupport(p2, data);
    final shared = _getSharedSupport(p1, p2, data);
    final n = data.totalInvoices.toDouble();

    if (support1 == 0 || support2 == 0 || n == 0) return 0.0;

    // Lift = P(A & B) / (P(A) * P(B)) = (Shared / N) / ((S1 / N) * (S2 / N))
    return (shared * n) / (support1 * support2);
  }

  /// ترتيب العناصر ذكياً بناءً على سلسلة التتابع العالمية (A -> B) بشكل صارم
  void _sequenceSort(List<String> cluster, Map<String, List<String>> sequences) {
    final result = <String>[];
    final remaining = Set<String>.from(cluster);

    while (remaining.isNotEmpty) {
      // إيجاد عنصر بداية (عنصر ليس لديه عنصر آخر "داخل" إليه من ضمن العناصر المتبقية)
      String? startNode;
      for (final node in remaining) {
        bool hasIncoming = false;
        for (final other in remaining) {
          final followers = sequences[other];
          if (followers != null && followers.contains(node)) {
            hasIncoming = true;
            break;
          }
        }
        if (!hasIncoming) {
          startNode = node;
          break;
        }
      }

      // في حال وجود حلقة دائرية (نادر جداً)، نأخذ أول عنصر
      startNode ??= remaining.first;

      // سحب السلسلة بالكامل ابتداءً من هذا العنصر
      String current = startNode;
      while (remaining.contains(current)) {
        result.add(current);
        remaining.remove(current);
        
        // التوجه إلى أقوى تابع متاح من القائمة ويجب أن يكون متواجداً في السلة
        String? nextNode;
        final potentialNexts = sequences[current] ?? [];
        for (final candidate in potentialNexts) {
          if (remaining.contains(candidate)) {
            nextNode = candidate;
            break;
          }
        }

        if (nextNode != null) {
          current = nextNode; // التوجه فوراً للعنصر التابع لإضافته تحته مباشرة
        } else {
          break; // نهاية السلسلة
        }
      }
    }

    cluster.clear();
    cluster.addAll(result);
  }

  /// توليد 5 سيناريوهات متنوعة الذكاء (Top-K Diverse Recommendations)
  Future<List<InvoicePrediction>> _generateDiverseScenarios(
    _PersonClusterData data, {
    required int targetSize,
    String? installerName,
    String? customerName,
  }) async {
    final List<InvoicePrediction> scenarios = [];
    final List<Set<String>> previousClusters = [];
    
    // الأوزان لفرض تقليل التشابه لكل مرحلة (Diversity Penalty Weights)
    final List<double> diversityPenalties = [
      0.0,   // الفاتورة 1: الأقوى (بدون تعديل) - Master
      0.10,  // الفاتورة 2: اختلاف 10% - استبدال الضعيف
      0.30,  // الفاتورة 3: اختلاف 30% - تغيير نمط جزئي
      0.50,  // الفاتورة 4: اختلاف 50% - تغيير نمط رئيسي
      0.80,  // الفاتورة 5: الأوسع - مرحلة متباعدة جداً (تأسيس vs تشطيب)
    ];

    final List<String> scenarioTitles = [
      'النمط الأساسي (توقعات مؤكدة)',
      'النمط البديل (تغيير طفيف)',
      'تغيير مرحلة العمل (خيار أوسط)',
      'تغيير جذري للسياق',
      'سيناريو متباعد كلياً',
    ];

    for (int i = 0; i < 5; i++) {
      // 1. البناء الجشع الموجه (Context-Aware Greedy Expansion + Negative Filtering)
      final cluster = _buildExpertCluster(
        data: data,
        diversityWeight: diversityPenalties[i],
        previousClusters: previousClusters,
        targetSize: targetSize,
      );

      if (cluster.isEmpty) continue; // فشل في إيجاد مسار منطقي جديد، نتجاهل

      // تطبيق الفرز التسلسلي الذكي (Sequence Sorting) لترتيب الفاتورة كترتيب الفني المعتاد
      if (data.globalSequences.isNotEmpty) {
        _sequenceSort(cluster, data.globalSequences);
      }

      // 2. تحويل العنقود إلى الفاتورة النهائية
      final items = <PredictedItem>[];
      for (final productName in cluster) {
        final pData = data.productData[productName]!;
        items.add(await _buildPredictedItem(pData));
      }

      scenarios.add(InvoicePrediction(
        type: 'smart_expert_$i',
        title: scenarioTitles[i],
        items: items,
        totalAmount: items.fold(0, (sum, item) => sum + (item.price * item.quantity)),
        score: (100 - (i * 10)).toDouble(), 
        description: i == 0 ? 'أفضل فاتورة مبنية على سياق العمل' : 'احتمال رياضي معدّل بنسبة ${diversityPenalties[i]*100}%',
      ));

      // 3. إضافة للذاكرة لمعاقبة التشابه في الدورة القادمة
      previousClusters.add(Set.from(cluster));
    }

    return scenarios;
  }

  /// خوارزمية البناء الخبير باستخدام قوانين المنع (Negative Rules) وتخفيض التشابه
  List<String> _buildExpertCluster({
    required _PersonClusterData data,
    required double diversityWeight,
    required List<Set<String>> previousClusters,
    required int targetSize,
  }) {
    final List<String> cluster = [];
    final Set<String> candidates = Set.from(data.productData.keys);

    if (candidates.isEmpty) return [];

    // --- المرحلة الأولى: اختيار المنتج الأساسي (Core Product) ---
    String? coreProduct;
    double bestCoreScore = -1.0;

    for (final p in candidates) {
      double baseScore = data.productData[p]!.score;
      
      // عقوبة التشابه (Diversity Penalty)
      double penalty = 0.0;
      for (final prev in previousClusters) {
        if (prev.contains(p)) {
          penalty = max(penalty, diversityWeight);
        }
      }
      
      double finalScore = baseScore * (1.0 - penalty);
      if (finalScore > bestCoreScore) {
        bestCoreScore = finalScore;
        coreProduct = p;
      }
    }

    if (coreProduct == null) return [];
    
    cluster.add(coreProduct);
    candidates.remove(coreProduct);

    // --- المرحلة الثانية: التوسع التدريجي باكتشاف المنع (Greedy Expansion + Lift Check) ---
    while (cluster.length < targetSize && candidates.isNotEmpty) {
      String? bestCandidate;
      double bestCandScore = -100.0;

      for (final c in candidates) {
        double avgAssociation = 0.0;
        bool isNegativeAssociation = false;

        // اختبار المُشرح مع [كل] منتج في السلة الحالية لمنع خلط الأنماط (تأسيس x تشطيب)
        for (final existing in cluster) {
          final lift = _getLift(existing, c, data);
          
          // 🛑 تفعيل علاقات المنع الذكية: 
          // إذا كان الظهور الفعلي أقل من المتوقع بشكل واضح (Lift < 0.7)
          // يُمنع إضافة سويتش (تشطيب) إلى سلة فيها سيمنس (تأسيس) حتى لو كان شائعاً.
          if (lift < 0.7 && data.totalInvoices > 3) {
            isNegativeAssociation = true;
            break; 
          }

          final conf = _getConfidence(existing, c, data);
          
          // دمج قوة الثقة بقوة الرفع لوزن حقيقي
          avgAssociation += (conf * lift);
        }

        // إذا كان يمتلك علاقة سلبية قوية، تجنبه نهائياً
        if (isNegativeAssociation) continue;

        avgAssociation /= cluster.length;

        // تخصيص عقوبة إضافية للتنوع (Diversity Penalty)
        double penalty = 0.0;
        for (final prev in previousClusters) {
          if (prev.contains(c)) {
            penalty = max(penalty, diversityWeight);
          }
        }

        double pScore = data.productData[c]!.score;
        // الوزن النهائي: مدى التوافق سياقياً × القوة الأصلية × عقوبة التكرار
        double finalScore = (avgAssociation > 0 ? avgAssociation : 0.001) * pScore * (1.0 - penalty);

        if (finalScore > bestCandScore) {
          bestCandScore = finalScore;
          bestCandidate = c;
        }
      }

      if (bestCandidate == null) {
        break; // توقفنا لأنه لم يتبقَ مرشح صامد أمام فلتر "علاقات المنع" (يحمي منطق الفاتورة)
      }

      cluster.add(bestCandidate);
      candidates.remove(bestCandidate);
    }

    return cluster;
  }

  /// بناء بيانات الصنف المتوقع مع الاعتماد على البيع النموذجي
  Future<PredictedItem> _buildPredictedItem(_ScoredProduct p) async {
    final saleTypeCounts = <String, int>{};
    for (final occ in p.occurrences) {
      saleTypeCounts[occ.saleType] = (saleTypeCounts[occ.saleType] ?? 0) + 1;
    }
    
    final favoriteSaleType = saleTypeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final saleType = favoriteSaleType.first.key;

    final relevantOccurrences = p.occurrences
        .where((o) => o.saleType == saleType)
        .toList();

    final last3 = relevantOccurrences.take(3).toList();
    
    double avgPrice = (last3.map((o) => o.price).reduce((a, b) => a + b) / last3.length).roundToDouble();
    double avgQty = (last3.map((o) => o.quantity).reduce((a, b) => a + b) / last3.length).roundToDouble();

    // تأكد من عدم وجود صفر (خاصة في الكمية)
    if (avgQty == 0) avgQty = 1.0;

    return PredictedItem(
      productId: p.productId,
      productName: p.productName,
      quantity: avgQty,
      price: avgPrice,
      saleType: saleType,
      confidence: 1.0, // يمكن ربطه بقيمة Lift لاحقاً أو تركه كإشارة كمال
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الإشعارات والعمليات السطحية
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> trainOnInvoice(int invoiceId) async {
    // تم إلغاء التدريب التقليدي لعمل النظام كمحرك خبير يراجع التاريخ مباشرةً عند الطلب.
    print('✅ Invoice $invoiceId processed (Expert Thinking dynamically analyzes)');
  }
  
  Future<bool> hasEnoughData() async {
    try {
      final db = await _db.database;
      final result = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM invoices
        WHERE status != 'معلقة'
      ''');
      
      final count = result.first['count'] as int;
      return count >= 10;
    } catch (e) {
      return false;
    }
  }

  // 🧪 الاختبار الروتيني
  Future<PredictionTestStats> testPredictionSystem({
    Function(int current, int total, String message)? onProgress,
  }) async {
    final stats = PredictionTestStats();
    stats.totalPredictions = 0;
    return stats; // Stub function for compiler compliance if tested
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// النماذج الداخلية المحورية للخبير
// ═══════════════════════════════════════════════════════════════════════════

class _PersonClusterData {
  final Map<String, _ScoredProduct> productData;
  final Map<String, Map<String, int>> coOccurrence;
  final int totalInvoices;
  
  // المخزون العالمي الذي تم جلبه من التدريب 
  Map<String, Map<String, double>> globalLifts = {};
  Map<String, List<String>> globalSequences = {};

  _PersonClusterData({
    required this.productData,
    required this.coOccurrence,
    required this.totalInvoices,
  });
}

class _ProductData {
  final int? productId;
  final String productName;
  final List<_ProductOccurrence> occurrences = [];

  _ProductData({
    required this.productId,
    required this.productName,
  });
}

class _ProductOccurrence {
  final DateTime invoiceDate;
  final double quantity;
  final double price;
  final String saleType;
  final int position; 

  _ProductOccurrence({
    required this.invoiceDate,
    required this.quantity,
    required this.price,
    required this.saleType,
    required this.position,
  });
}

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

class PredictionTestStats {
  int totalInvoices = 0;
  int successfulPredictions = 0;
  int failedPredictions = 0;
  int totalPredictions = 0;
  int totalProducts = 0;
  double avgProductsPerPrediction = 0.0;
  Duration duration = Duration.zero;
}
