// lib/services/smart_search/smart_search_service.dart
// خدمة البحث الذكي الرئيسية

import '../../models/product.dart';
import '../database_service.dart';
import 'smart_search_db.dart';
import 'smart_search_models.dart';
import 'smart_search_trainer.dart';

/// منتج مع نقاط الترتيب
class _ScoredProduct {
  final Product product;
  final double score;
  
  _ScoredProduct({required this.product, required this.score});
}

class SmartSearchService {
  static SmartSearchService? _instance;
  
  final DatabaseService _mainDb;
  final SmartSearchDatabase _smartDb;
  final SmartSearchTrainer _trainer;
  
  // سياق الجلسة الحالية
  final SessionContext _sessionContext = SessionContext();
  
  // تفعيل/تعطيل البحث الذكي
  bool _isEnabled = true;

  SmartSearchService._({
    DatabaseService? mainDb,
    SmartSearchDatabase? smartDb,
  })  : _mainDb = mainDb ?? DatabaseService(),
        _smartDb = smartDb ?? SmartSearchDatabase.instance,
        _trainer = SmartSearchTrainer(
          mainDb: mainDb ?? DatabaseService(),
          smartDb: smartDb ?? SmartSearchDatabase.instance,
        );

  static SmartSearchService get instance {
    _instance ??= SmartSearchService._();
    return _instance!;
  }

  /// تفعيل/تعطيل البحث الذكي
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    print('🔧 Smart Search ${enabled ? "enabled" : "disabled"}');
  }

  bool get isEnabled => _isEnabled;

  /// الحصول على سياق الجلسة
  SessionContext get sessionContext => _sessionContext;

  /// الحصول على المدرب
  SmartSearchTrainer get trainer => _trainer;

  // ═══════════════════════════════════════════════════════════════════════════
  // إدارة سياق الجلسة
  // ═══════════════════════════════════════════════════════════════════════════

  /// بدء جلسة جديدة (فاتورة جديدة)
  /// إذا كانت الجلسة تحتوي على منتجات مضافة، لا يتم مسحها (الفاتورة قيد الإنشاء)
  void startNewSession({
    String? customerName,
    int? customerId,
    String? installerName,
    bool forceNew = false, // إجبار بدء جلسة جديدة حتى لو كانت هناك منتجات
  }) {
    // 🆕 لا تمسح الجلسة إذا كانت الفاتورة قيد الإنشاء (يوجد منتجات مضافة)
    // إلا إذا تم طلب ذلك صراحة بـ forceNew
    if (!forceNew && _sessionContext.addedProductIds.isNotEmpty) {
      print('📌 Session preserved: ${_sessionContext.addedProductIds.length} products in progress');
      // تحديث معلومات العميل/المُركّب فقط إذا تم تمريرها
      if (customerName != null) _sessionContext.customerName = customerName;
      if (customerId != null) _sessionContext.customerId = customerId;
      if (installerName != null) _sessionContext.installerName = installerName;
      return;
    }
    
    _sessionContext.clear();
    _sessionContext.customerName = customerName;
    _sessionContext.customerId = customerId;
    _sessionContext.installerName = installerName;
    print('🆕 Started new session: customer=$customerName, installer=$installerName');
  }
  
  /// بدء جلسة جديدة بالقوة (يمسح كل شيء)
  void forceNewSession({
    String? customerName,
    int? customerId,
    String? installerName,
  }) {
    startNewSession(
      customerName: customerName,
      customerId: customerId,
      installerName: installerName,
      forceNew: true,
    );
  }

  /// تحديث معلومات العميل في الجلسة
  void updateSessionCustomer({
    String? customerName,
    int? customerId,
  }) {
    _sessionContext.customerName = customerName;
    _sessionContext.customerId = customerId;
  }

  /// تحديث معلومات المُركّب في الجلسة
  void updateSessionInstaller(String? installerName) {
    _sessionContext.installerName = installerName;
  }

  /// إضافة منتج للجلسة
  void addProductToSession(int? productId, String productName) {
    _sessionContext.addProduct(productId, productName);
    print('➕ Added to session: $productName');
    print('   🏷️ Brands: ${_sessionContext.detectedBrands}');
    print('   📝 Last words: ${_sessionContext.detectedLastWords}');
  }

  /// إزالة منتج من الجلسة
  void removeProductFromSession(int? productId, String productName) {
    if (productId != null) {
      _sessionContext.addedProductIds.remove(productId);
    }
    _sessionContext.addedProductNames.remove(productName);
    
    // إعادة حساب العلامات التجارية والكلمات الأخيرة
    _sessionContext.detectedBrands.clear();
    _sessionContext.detectedLastWords.clear();
    for (final name in _sessionContext.addedProductNames) {
      final brand = SessionContext.extractBrand(name);
      if (brand != null && !_sessionContext.detectedBrands.contains(brand)) {
        _sessionContext.detectedBrands.add(brand);
      }
      final lastWord = SessionContext.extractLastWord(name);
      if (lastWord != null && !_sessionContext.detectedLastWords.contains(lastWord)) {
        _sessionContext.detectedLastWords.add(lastWord);
      }
    }
  }

  /// مسح الجلسة
  void clearSession() {
    _sessionContext.clear();
    print('🗑️ Session cleared');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // البحث الذكي
  // ═══════════════════════════════════════════════════════════════════════════

  /// البحث الذكي عن المنتجات - نظام النقاط المتقدم
  /// [currentInvoiceProductNames] - قائمة أسماء المنتجات الموجودة حالياً في الفاتورة
  /// إذا تم تمريرها، يتم استخدامها للتحقق من المنتجات المضافة بدلاً من الاعتماد على الجلسة
  Future<List<Product>> smartSearch(
    String query, {
    List<String>? currentInvoiceProductNames,
  }) async {
    // إذا البحث الذكي معطل، استخدم البحث العادي
    if (!_isEnabled) {
      return await _mainDb.searchProductsSmart(query);
    }

    try {
      // 1. البحث الأساسي بـ FTS5 - يُرجع 300 نتيجة للترتيب الذكي
      final baseResults = await _mainDb.searchProductsSmart(query);
      if (baseResults.isEmpty) return [];
      
      // إذا لا يوجد سياق (لم يُختر أي منتج بعد)، أرجع النتائج كما هي
      if (_sessionContext.detectedBrands.isEmpty && 
          _sessionContext.detectedLastWords.isEmpty &&
          _sessionContext.addedProductIds.isEmpty &&
          _sessionContext.addedProductNames.isEmpty &&
          (currentInvoiceProductNames == null || currentInvoiceProductNames.isEmpty)) {
        return baseResults;
      }

      // 🆕 2. إضافة منتجات الماركة المكتشفة (خاصة للبحث القصير)
      // هذا يضمن ظهور منتجات الماركة حتى لو لم تظهر في نتائج FTS5
      List<Product> combinedResults = List.from(baseResults);
      final existingIds = baseResults.map((p) => p.id).toSet();
      
      // البحث عن منتجات الماركة + كلمة البحث
      for (final brand in _sessionContext.detectedBrands) {
        final brandResults = await _mainDb.searchProductsSmart('$brand $query');
        for (final product in brandResults) {
          if (!existingIds.contains(product.id)) {
            combinedResults.add(product);
            existingIds.add(product.id);
          }
        }
      }

      // 3. جلب المنتجات المرتبطة (Associations)
      Map<int, int> associations = {};
      if (_sessionContext.addedProductIds.isNotEmpty) {
        associations = await _smartDb.getAssociatedProductsForList(
          _sessionContext.addedProductIds,
        );
      }

      // 4. حساب النقاط لكل منتج وإعادة الترتيب
      final scoredResults = _calculateScoresAndSort(
        combinedResults, 
        query, 
        associations,
        currentInvoiceProductNames: currentInvoiceProductNames,
      );

      return scoredResults;
    } catch (e) {
      print('⚠️ Smart search error, falling back to basic search: $e');
      return await _mainDb.searchProductsSmart(query);
    }
  }

  /// حساب النقاط لكل منتج وترتيبها
  /// نظام النقاط الموحد (الكل يُجمع معاً):
  /// - تطابق الأحرف: 10,000,000 نقطة لكل حرف متطابق (الأولوية القصوى!)
  /// - تطابق الماركة الكامل: 100 نقطة
  /// - العلاقة التراكمية: 3 نقاط لكل علاقة
  /// - تطابق الماركة الجزئي: 20 نقطة
  /// - العائلة: 15 نقطة
  /// - الكلمة الأخيرة: 5 نقاط
  /// - عقوبة المنتج المضاف: -100,000,000 نقطة
  /// 
  /// المجموع = تطابق الأحرف + الماركة + العلاقات + ...
  /// 
  /// [currentInvoiceProductNames] - قائمة أسماء المنتجات الموجودة حالياً في الفاتورة
  /// إذا تم تمريرها، يتم استخدامها للتحقق من المنتجات المضافة (أكثر دقة)
  List<Product> _calculateScoresAndSort(
    List<Product> products, 
    String query,
    Map<int, int> associations, {
    List<String>? currentInvoiceProductNames,
  }) {
    // استخراج "عائلة" المنتجات المضافة (الكلمات الأولى)
    final addedProductFamilies = _extractProductFamilies(_sessionContext.addedProductNames);
    
    // 🆕 تحضير قائمة المنتجات الموجودة في الفاتورة للتحقق الدقيق
    // إذا تم تمرير currentInvoiceProductNames، نستخدمها (أكثر دقة)
    // وإلا نستخدم addedProductNames من الجلسة (للتوافق مع الكود القديم)
    final Set<String> invoiceProductNamesLower;
    if (currentInvoiceProductNames != null) {
      invoiceProductNamesLower = currentInvoiceProductNames
          .map((n) => n.toLowerCase().trim())
          .where((n) => n.isNotEmpty)
          .toSet();
    } else {
      invoiceProductNamesLower = _sessionContext.addedProductNames
          .map((n) => n.toLowerCase().trim())
          .toSet();
    }
    
    // تحضير كلمات البحث للمقارنة
    final queryLower = query.toLowerCase().trim();
    final queryWords = queryLower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    
    // حساب النقاط لكل منتج
    final List<_ScoredProduct> scoredProducts = [];
    
    for (int i = 0; i < products.length; i++) {
      final product = products[i];
      double score = 0;
      
      // 🆕 التحقق إذا كان المنتج موجوداً حالياً في الفاتورة
      // نستخدم القائمة الممررة (الأكثر دقة) أو الجلسة
      final productNameLower = product.name.toLowerCase().trim();
      final isInCurrentInvoice = invoiceProductNamesLower.contains(productNameLower);
      
      // تقسيم اسم المنتج إلى كلمات للبحث الدقيق
      final productWords = productNameLower.split(RegExp(r'\s+'));
      
      // ═══════════════════════════════════════════════════════════════════
      // 1. 🆕 نقاط تطابق الأحرف (10,000,000 نقطة لكل حرف) - الأولوية القصوى!
      // ═══════════════════════════════════════════════════════════════════
      // البحث عن كلمات تبدأ بكلمة البحث (وليس تحتوي عليها في أي مكان)
      // مثال: "سويج ن" → يبحث عن كلمة تبدأ بـ "ن" (مثل "نيو")
      // "سويج اثنين" لا يطابق لأن "ن" في منتصف كلمة "اثنين"
      // 10,000,000 نقطة لكل حرف = الأولوية المطلقة لتطابق الأحرف!
      int matchedChars = 0;
      for (final queryWord in queryWords) {
        // البحث عن كلمة في اسم المنتج تبدأ بكلمة البحث
        final hasWordStartingWith = productWords.any((productWord) => 
          productWord.startsWith(queryWord)
        );
        if (hasWordStartingWith) {
          matchedChars += queryWord.length;
        }
      }
      score += matchedChars * 10000000; // 10,000,000 نقطة لكل حرف متطابق
      
      // ═══════════════════════════════════════════════════════════════════
      // 2. نقاط الماركة الكاملة (100 نقطة)
      // ═══════════════════════════════════════════════════════════════════
      final productNameNormalized = _normalizeForBrandMatch(product.name);
      bool fullBrandMatch = false;
      bool partialBrandMatch = false;
      
      for (final detectedBrand in _sessionContext.detectedBrands) {
        final brandNormalized = _normalizeForBrandMatch(detectedBrand);
        
        // التطابق الكامل: اسم المنتج يحتوي على نص الماركة بالكامل
        if (productNameNormalized.contains(brandNormalized)) {
          score += 100;
          fullBrandMatch = true;
          break;
        }
      }
      
      // ═══════════════════════════════════════════════════════════════════
      // 3. نقاط العلاقة التراكمية (3 نقاط لكل علاقة)
      // ═══════════════════════════════════════════════════════════════════
      if (product.id != null && associations.containsKey(product.id)) {
        final associationCount = associations[product.id]!;
        score += associationCount * 3;
      }
      
      // ═══════════════════════════════════════════════════════════════════
      // 4. نقاط الماركة الجزئية (20 نقطة)
      // ═══════════════════════════════════════════════════════════════════
      if (!fullBrandMatch) {
        final productBrand = SessionContext.extractBrand(product.name);
        if (productBrand != null) {
          final productBrandNormalized = _normalizeForBrandMatch(productBrand);
          
          for (final detectedBrand in _sessionContext.detectedBrands) {
            final brandNormalized = _normalizeForBrandMatch(detectedBrand);
            
            if (productBrandNormalized.contains(brandNormalized) ||
                brandNormalized.contains(productBrandNormalized)) {
              score += 20;
              partialBrandMatch = true;
              break;
            }
            
            final detectedWords = detectedBrand.toLowerCase().split(RegExp(r'\s+'));
            final productBrandWords = productBrand.toLowerCase().split(RegExp(r'\s+'));
            final commonWords = detectedWords.where((w) => productBrandWords.contains(w)).length;
            
            if (commonWords >= 1 && !partialBrandMatch) {
              score += 5 + (commonWords * 5).clamp(0, 10);
              partialBrandMatch = true;
              break;
            }
          }
        }
      }
      
      // ═══════════════════════════════════════════════════════════════════
      // 5. نقاط العائلة (15 نقطة)
      // ═══════════════════════════════════════════════════════════════════
      final productFamily = _extractProductFamily(product.name);
      if (productFamily != null && addedProductFamilies.contains(productFamily)) {
        score += 15;
      }
      
      // ═══════════════════════════════════════════════════════════════════
      // 6. نقاط الكلمة الأخيرة (5 نقاط)
      // ═══════════════════════════════════════════════════════════════════
      final productLastWord = SessionContext.extractLastWord(product.name);
      if (productLastWord != null && _sessionContext.detectedLastWords.contains(productLastWord)) {
        score += 5;
      }
      
      // ═══════════════════════════════════════════════════════════════════
      // 7. bonus صغير للحفاظ على ترتيب FTS5 الأصلي
      // ═══════════════════════════════════════════════════════════════════
      score += (products.length - i) * 0.01;
      
      // ═══════════════════════════════════════════════════════════════════
      // 8. 🆕 عقوبة المنتج الموجود في الفاتورة (-100,000,000 نقطة)
      // ═══════════════════════════════════════════════════════════════════
      // نتحقق من القائمة الفعلية للمنتجات في الفاتورة (أكثر دقة)
      if (isInCurrentInvoice) {
        score -= 100000000; // -100 مليون نقطة للمنتج الموجود في الفاتورة
      }
      
      scoredProducts.add(_ScoredProduct(product: product, score: score));
    }
    
    // ترتيب حسب النقاط (الأعلى أولاً)
    scoredProducts.sort((a, b) => b.score.compareTo(a.score));
    
    // طباعة للتصحيح (أول 5 نتائج)
    if (scoredProducts.isNotEmpty) {
      print('🔍 Smart Search Results (top 5):');
      for (int i = 0; i < scoredProducts.take(5).length; i++) {
        final sp = scoredProducts[i];
        final isAdded = sp.score < -50000 ? ' [مضاف]' : '';
        print('   ${i + 1}. ${sp.product.name} (score: ${sp.score.toStringAsFixed(2)})$isAdded');
      }
    }
    
    return scoredProducts.map((sp) => sp.product).toList();
  }
  
  /// 🆕 تطبيع النص لمطابقة الماركات (إزالة الفراغات وتوحيد الأحرف)
  /// مثال: "نيو فنار ابيض" -> "نيوفنارابيض"
  /// هذا يسمح بمطابقة "نيو فنار ابيض" مع "نيوفنار ابيض" أو "نيو فنارابيض"
  String _normalizeForBrandMatch(String text) {
    return text
        .toLowerCase()
        .replaceAll(' ', '')      // إزالة الفراغات
        .replaceAll('\u00A0', '') // إزالة non-breaking space
        .replaceAll('-', '')      // إزالة الشرطات
        .replaceAll('_', '')      // إزالة الشرطات السفلية
        .trim();
  }
  
  /// استخراج "عائلة" المنتج (الكلمات الأولى بدون الأرقام والمواصفات)
  /// مثال: "سويتش فنار 1 خط" -> "سويتش فنار"
  String? _extractProductFamily(String productName) {
    final words = productName.trim().split(RegExp(r'\s+'));
    if (words.length < 2) return null;
    
    // أخذ أول كلمتين أو ثلاث (حسب طول الاسم)
    final familyWords = <String>[];
    for (final word in words) {
      // توقف عند الأرقام أو الكلمات الوصفية
      if (RegExp(r'^\d').hasMatch(word)) break;
      if (_isDescriptiveWord(word)) break;
      familyWords.add(word.toLowerCase());
      if (familyWords.length >= 3) break;
    }
    
    if (familyWords.isEmpty) return null;
    return familyWords.join(' ');
  }
  
  /// استخراج عائلات المنتجات المضافة
  Set<String> _extractProductFamilies(List<String> productNames) {
    final families = <String>{};
    for (final name in productNames) {
      final family = _extractProductFamily(name);
      if (family != null) {
        families.add(family);
      }
    }
    return families;
  }
  
  /// التحقق إذا كانت الكلمة وصفية (رقم، قياس، إلخ)
  /// 🆕 تم إزالة الألوان والأوصاف المهمة (عميق، ثقيل، رصاصي) لأنها تميز المنتجات
  bool _isDescriptiveWord(String word) {
    final descriptiveWords = [
      // أرقام وقياسات فقط - هذه لا تميز المنتجات
      'خط', 'خطين', 'امبير', 'فولت', 'واط', 'ملم', 'سم', 'متر', 'انش',
      // أحجام عامة جداً
      'كبير', 'صغير', 'متوسط',
      // كلمات تقنية
      'سنجل', 'دبل',
    ];
    return descriptiveWords.contains(word.toLowerCase());
  }

  /// إعادة ترتيب النتائج بناءً على السياق (Re-ranking) - الطريقة القديمة للتوافق
  /// الترتيب:
  /// 1. المنتجات التي تطابق البحث + السياق (الأفضل)
  /// 2. المنتجات التي تطابق البحث فقط (FTS5)
  /// 3. المنتجات التي تطابق السياق فقط
  /// 4. باقي المنتجات
  /// 
  /// داخل كل مجموعة: الأكثر ارتباطاً (من Associations) يظهر أولاً
  List<Product> _rerankResults(
    List<Product> products, 
    String query,
    Map<int, int> associations,
  ) {
    // تقسيم المنتجات إلى 4 مجموعات
    final List<Product> matchesBothSearchAndContext = [];
    final List<Product> matchesSearchOnly = [];
    final List<Product> matchesContextOnly = [];
    final List<Product> matchesNeither = [];
    
    // استخراج كلمات البحث
    final queryWords = query.toLowerCase().trim().split(RegExp(r'\s+'));
    
    for (final product in products) {
      final productName = product.name.toLowerCase();
      final matchesContext = _sessionContext.matchesSessionContext(product.name);
      
      // التحقق من تطابق جميع كلمات البحث
      final matchesAllQueryWords = queryWords.every((word) => productName.contains(word));
      
      if (matchesAllQueryWords && matchesContext) {
        // يطابق البحث + السياق
        matchesBothSearchAndContext.add(product);
      } else if (matchesAllQueryWords) {
        // يطابق البحث فقط
        matchesSearchOnly.add(product);
      } else if (matchesContext) {
        // يطابق السياق فقط
        matchesContextOnly.add(product);
      } else {
        // لا يطابق شيء (نتائج FTS5 الجزئية)
        matchesNeither.add(product);
      }
    }
    
    // ترتيب كل مجموعة حسب قوة الارتباط (الأكثر ارتباطاً أولاً)
    if (associations.isNotEmpty) {
      _sortByAssociation(matchesBothSearchAndContext, associations);
      _sortByAssociation(matchesSearchOnly, associations);
      _sortByAssociation(matchesContextOnly, associations);
      _sortByAssociation(matchesNeither, associations);
    }
    
    // دمج المجموعات بالترتيب الصحيح
    return [
      ...matchesBothSearchAndContext,
      ...matchesSearchOnly,
      ...matchesContextOnly,
      ...matchesNeither,
    ];
  }
  
  /// ترتيب المنتجات حسب قوة الارتباط (الأكثر ارتباطاً أولاً)
  /// المنتجات غير المرتبطة تبقى في نهاية القائمة بترتيب FTS5
  void _sortByAssociation(List<Product> products, Map<int, int> associations) {
    if (products.length <= 1) return;
    
    products.sort((a, b) {
      final aScore = associations[a.id] ?? 0;
      final bScore = associations[b.id] ?? 0;
      
      // إذا كلاهما لهما ارتباط، رتب حسب القوة
      if (aScore > 0 && bScore > 0) {
        return bScore.compareTo(aScore); // الأعلى أولاً
      }
      
      // إذا أحدهما فقط له ارتباط، ضعه أولاً
      if (aScore > 0) return -1;
      if (bScore > 0) return 1;
      
      // إذا كلاهما بدون ارتباط، حافظ على ترتيب FTS5
      return 0;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // اقتراحات ذكية
  // ═══════════════════════════════════════════════════════════════════════════

  /// اقتراح المنتجات التالية بناءً على السياق
  Future<List<Product>> suggestNextProducts({int limit = 10}) async {
    if (!_isEnabled || _sessionContext.addedProductIds.isEmpty) {
      return [];
    }

    try {
      // جلب المنتجات المرتبطة
      final associations = await _smartDb.getAssociatedProductsForList(
        _sessionContext.addedProductIds,
      );

      if (associations.isEmpty) return [];

      // ترتيب حسب قوة الارتباط
      final sortedIds = associations.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // جلب المنتجات
      final List<Product> suggestions = [];
      for (final entry in sortedIds.take(limit)) {
        final product = await _mainDb.getProductById(entry.key);
        if (product != null && !_sessionContext.addedProductIds.contains(product.id)) {
          suggestions.add(product);
        }
      }

      return suggestions;
    } catch (e) {
      print('⚠️ Error getting suggestions: $e');
      return [];
    }
  }

  /// اقتراح العلامة التجارية المتوقعة للعميل الجديد بناءً على المُركّب
  Future<String?> suggestBrandForNewCustomer() async {
    if (!_isEnabled) return null;

    // أولاً: من سياق الجلسة
    if (_sessionContext.detectedBrands.isNotEmpty) {
      return _sessionContext.detectedBrands.first;
    }

    // ثانياً: من تاريخ المُركّب
    if (_sessionContext.installerName != null && _sessionContext.installerName!.isNotEmpty) {
      return await _smartDb.getInstallerTopBrand(_sessionContext.installerName!);
    }

    return null;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // التدريب
  // ═══════════════════════════════════════════════════════════════════════════

  /// التدريب على جميع الفواتير
  Future<TrainingStats> trainOnAllInvoices({
    Function(int current, int total, String message)? onProgress,
  }) async {
    return await _trainer.trainOnAllInvoices(onProgress: onProgress);
  }

  /// التدريب على فاتورة جديدة (يُستدعى بعد حفظ الفاتورة)
  Future<void> trainOnNewInvoice(int invoiceId) async {
    if (!_isEnabled) return;
    await _trainer.trainOnSingleInvoice(invoiceId);
  }

  /// التحقق من وجود بيانات تدريب
  Future<bool> hasTrainingData() async {
    return await _trainer.hasTrainingData();
  }

  /// جلب إحصائيات التدريب
  Future<TrainingStats?> getTrainingStats() async {
    return await _trainer.getLastTrainingStats();
  }
  
  /// 🆕 تحميل الماركات المكتشفة تلقائياً
  Future<void> loadAutoDiscoveredBrands() async {
    try {
      // جلب الماركات التي تظهر في 5+ منتجات
      final brands = await _smartDb.getAutoDiscoveredBrands(minOccurrence: 5);
      SessionContext.setAutoDiscoveredBrands(brands.toSet());
      print('✅ Loaded ${brands.length} auto-discovered brands');
    } catch (e) {
      print('⚠️ Error loading auto-discovered brands: $e');
    }
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // إدارة الماركات
  // ═══════════════════════════════════════════════════════════════════════════
  
  /// 🆕 جلب جميع الماركات مع عدد التكرار
  Future<List<Map<String, dynamic>>> getAllBrandsWithCount() async {
    return await _smartDb.getDiscoveredBrandsWithCount();
  }
  
  /// 🆕 حذف ماركة
  Future<bool> deleteBrand(String brand) async {
    final result = await _smartDb.deleteBrand(brand);
    if (result) {
      // تحديث الماركات في الذاكرة
      await loadAutoDiscoveredBrands();
    }
    return result;
  }
  
  /// 🆕 إضافة ماركة يدوياً
  Future<void> addManualBrand(String brand) async {
    await _smartDb.addManualBrand(brand);
    // تحديث الماركات في الذاكرة
    await loadAutoDiscoveredBrands();
  }
  
  /// 🆕 التحقق من وجود ماركة
  Future<bool> brandExists(String brand) async {
    return await _smartDb.brandExists(brand);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // معلومات التصحيح
  // ═══════════════════════════════════════════════════════════════════════════

  /// طباعة معلومات السياق الحالي
  void debugPrintContext() {
    print('''
╔══════════════════════════════════════════════════════════════╗
║                    Smart Search Context                       ║
╠══════════════════════════════════════════════════════════════╣
║ Enabled: $_isEnabled
║ Customer: ${_sessionContext.customerName} (ID: ${_sessionContext.customerId})
║ Installer: ${_sessionContext.installerName}
║ Detected Brands: ${_sessionContext.detectedBrands}
║ Detected Last Words: ${_sessionContext.detectedLastWords}
║ Added Products: ${_sessionContext.addedProductIds.length}
║ Auto-discovered Brands: ${SessionContext.autoDiscoveredBrands.length}
╚══════════════════════════════════════════════════════════════╝
''');
  }
}
