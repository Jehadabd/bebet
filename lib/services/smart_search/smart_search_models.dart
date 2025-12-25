// lib/services/smart_search/smart_search_models.dart
// نماذج البيانات لنظام البحث الذكي

/// علاقة بين منتجين (يُشتريان معاً)
class ProductAssociation {
  final int productIdA;
  final int productIdB;
  final String productNameA;
  final String productNameB;
  final int coOccurrenceCount; // عدد مرات الظهور معاً
  final double strength; // قوة العلاقة (0-1)

  ProductAssociation({
    required this.productIdA,
    required this.productIdB,
    required this.productNameA,
    required this.productNameB,
    required this.coOccurrenceCount,
    required this.strength,
  });

  Map<String, dynamic> toMap() => {
    'product_id_a': productIdA,
    'product_id_b': productIdB,
    'product_name_a': productNameA,
    'product_name_b': productNameB,
    'co_occurrence_count': coOccurrenceCount,
    'strength': strength,
  };

  factory ProductAssociation.fromMap(Map<String, dynamic> map) => ProductAssociation(
    productIdA: map['product_id_a'] as int,
    productIdB: map['product_id_b'] as int,
    productNameA: map['product_name_a'] as String,
    productNameB: map['product_name_b'] as String,
    coOccurrenceCount: map['co_occurrence_count'] as int,
    strength: (map['strength'] as num).toDouble(),
  );
}

/// تفضيلات العميل للعلامات التجارية
class CustomerBrandPreference {
  final int? customerId; // قد يكون null
  final String customerName;
  final String brand;
  final int purchaseCount; // عدد مرات الشراء
  final double percentage; // نسبة من إجمالي مشترياته
  final DateTime lastPurchase;

  CustomerBrandPreference({
    this.customerId,
    required this.customerName,
    required this.brand,
    required this.purchaseCount,
    required this.percentage,
    required this.lastPurchase,
  });

  Map<String, dynamic> toMap() => {
    'customer_id': customerId,
    'customer_name': customerName,
    'brand': brand,
    'purchase_count': purchaseCount,
    'percentage': percentage,
    'last_purchase': lastPurchase.toIso8601String(),
  };

  factory CustomerBrandPreference.fromMap(Map<String, dynamic> map) => CustomerBrandPreference(
    customerId: map['customer_id'] as int?, // nullable
    customerName: map['customer_name'] as String,
    brand: map['brand'] as String,
    purchaseCount: map['purchase_count'] as int,
    percentage: (map['percentage'] as num?)?.toDouble() ?? 0.0,
    lastPurchase: DateTime.parse(map['last_purchase'] as String),
  );
}

/// تفضيلات المُركّب/المؤسس للعلامات التجارية
class InstallerBrandPreference {
  final String installerName;
  final String brand;
  final int purchaseCount;
  final double percentage;
  final DateTime lastPurchase;

  InstallerBrandPreference({
    required this.installerName,
    required this.brand,
    required this.purchaseCount,
    required this.percentage,
    required this.lastPurchase,
  });

  Map<String, dynamic> toMap() => {
    'installer_name': installerName,
    'brand': brand,
    'purchase_count': purchaseCount,
    'percentage': percentage,
    'last_purchase': lastPurchase.toIso8601String(),
  };

  factory InstallerBrandPreference.fromMap(Map<String, dynamic> map) => InstallerBrandPreference(
    installerName: map['installer_name'] as String,
    brand: map['brand'] as String,
    purchaseCount: map['purchase_count'] as int,
    percentage: (map['percentage'] as num).toDouble(),
    lastPurchase: DateTime.parse(map['last_purchase'] as String),
  );
}

/// سياق الجلسة الحالية (الفاتورة قيد الإنشاء)
class SessionContext {
  String? customerName;
  int? customerId;
  String? installerName;
  List<String> detectedBrands = [];
  List<String> detectedLastWords = [];
  List<int> addedProductIds = [];
  List<String> addedProductNames = [];
  
  // الماركات المكتشفة تلقائياً (من التدريب)
  static Set<String> _autoDiscoveredBrands = {};
  
  // الحد الأدنى لاعتبار كلمة كماركة
  static const int minBrandOccurrence = 5;

  SessionContext();

  /// تحديث الماركات المكتشفة تلقائياً
  static void setAutoDiscoveredBrands(Set<String> brands) {
    _autoDiscoveredBrands = brands;
    print('🏷️ Auto-discovered brands updated: ${brands.length} brands');
  }
  
  /// الحصول على الماركات المكتشفة
  static Set<String> get autoDiscoveredBrands => _autoDiscoveredBrands;

  /// إضافة منتج للسياق واستخراج العلامة التجارية
  void addProduct(int? productId, String productName) {
    if (productId != null) {
      addedProductIds.add(productId);
    }
    addedProductNames.add(productName);
    
    // استخراج الكلمة الأخيرة (للنظام الهجين)
    final lastWord = extractLastWord(productName);
    if (lastWord != null && !detectedLastWords.contains(lastWord)) {
      detectedLastWords.add(lastWord);
    }
    
    // استخراج العلامة التجارية من اسم المنتج
    final brand = extractBrand(productName);
    if (brand != null && !detectedBrands.contains(brand)) {
      detectedBrands.add(brand);
    }
  }

  /// مسح السياق
  void clear() {
    customerName = null;
    customerId = null;
    installerName = null;
    detectedBrands.clear();
    detectedLastWords.clear();
    addedProductIds.clear();
    addedProductNames.clear();
  }


  /// 🆕 قائمة الكلمات العامة/الوصفية التي لا تُعتبر ماركات (موسعة)
  static const List<String> _excludedWords = [
    // الأحجام والأوصاف
    'عميق', 'ثقيل', 'خفيف', 'كبير', 'صغير', 'متوسط', 'عادي',
    'جديد', 'قديم', 'أصلي', 'اصلي', 'تقليد', 'درجة', 'ممتاز',
    'سميك', 'رفيع', 'طويل', 'قصير', 'عريض', 'ضيق', 'عالي', 'منخفض',
    // الألوان
    'ابيض', 'اسود', 'رصاصي', 'احمر', 'ازرق', 'اخضر', 'اصفر',
    'بني', 'برتقالي', 'وردي', 'بنفسجي', 'ذهبي', 'فضي', 'شفاف',
    'white', 'black', 'red', 'blue', 'green', 'yellow', 'gold', 'silver',
    // الأشكال
    'مربع', 'دائري', 'مستطيل', 'بيضاوي', 'مسطح', 'منحني',
    // الوحدات والقياسات
    'ملم', 'سم', 'متر', 'انج', 'انش', 'قدم', 'بوصة',
    'mm', 'cm', 'm', 'inch', 'ft',
    'امبير', 'فولت', 'واط', 'كيلو', 'جرام', 'لتر',
    'amp', 'volt', 'watt', 'kg', 'gram', 'liter',
    // التوصيفات الكهربائية
    'خط', 'خطين', 'ثلاثي', 'رباعي', 'احادي', 'ثنائي', 'دبل', 'سنجل',
    'فاز', 'فيز', 'ارضي', 'نيوترال', 'حي',
    'single', 'double', 'triple', 'phase',
    // الرموز والاختصارات الشائعة
    'a', 'w', 'v', 'mm', 'cm', 'ac', 'dc', 'led', 'lcd',
    // كلمات عامة
    'نوع', 'موديل', 'طراز', 'شكل', 'لون', 'حجم', 'مقاس',
    'عدد', 'قطعة', 'حبة', 'علبة', 'كرتون', 'ربطة',
    'مع', 'بدون', 'فقط', 'كامل', 'نصف', 'زوج',
    // المواد
    'حديد', 'نحاس', 'المنيوم', 'بلاستيك', 'خشب', 'زجاج', 'معدن',
    'iron', 'copper', 'aluminum', 'plastic', 'wood', 'glass', 'metal',
    // كلمات الجودة
    'ممتاز', 'جيد', 'عادي', 'اقتصادي', 'فاخر', 'درجة', 'اولى', 'ثانية',
  ];

  /// استخراج الكلمة الأخيرة من اسم المنتج
  static String? extractLastWord(String productName) {
    final words = productName.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return null;
    
    final lastWord = words.last.toLowerCase().trim();
    
    // تجاهل الكلمات القصيرة جداً (أقل من 2 حرف)
    if (lastWord.length < 2) return null;
    
    // تجاهل الأرقام فقط
    if (RegExp(r'^\d+$').hasMatch(lastWord)) return null;
    
    // تجاهل الكلمات العامة/الوصفية
    if (_excludedWords.contains(lastWord)) return null;
    
    return lastWord;
  }

  /// استخراج العلامة التجارية من اسم المنتج (نظام هجين محسّن)
  /// الأولوية الجديدة:
  /// 1. 🆕 استخراج آخر كلمات اسم المنتج كماركة أولاً (مثل "نيو فنار ابيض")
  /// 2. البحث في الماركات المكتشفة (للتحقق والتطابق)
  /// 3. البحث في الماركات المعروفة الثابتة (كـ fallback)
  static String? extractBrand(String productName) {
    final normalizedName = productName.toLowerCase();
    
    // 🆕 أولاً: استخراج آخر كلمات اسم المنتج كماركة
    // هذا يعطي الأولوية للماركة الكاملة مثل "نيو فنار ابيض" بدلاً من "فنار" فقط
    // مثال: "سويتش واحد خط نيو فنار ابيض" -> "نيو فنار ابيض"
    // مثال: "سويتش واحد خط فنار رصاصي" -> "فنار رصاصي"
    // مثال: "سويتش واحد خط فنار" -> "فنار"
    final extractedBrand = _extractBrandFromEnd(productName);
    if (extractedBrand != null) {
      // التحقق إذا كانت الماركة المستخرجة موجودة في الماركات المكتشفة
      // إذا وجدت، نستخدمها مباشرة
      final extractedNormalized = extractedBrand.toLowerCase();
      for (final discoveredBrand in _autoDiscoveredBrands) {
        if (discoveredBrand.toLowerCase() == extractedNormalized) {
          return discoveredBrand; // إرجاع الماركة بالتنسيق الصحيح
        }
      }
      // إذا لم توجد في المكتشفة، نرجعها كما هي
      return extractedBrand;
    }
    
    // ثانياً: البحث في الماركات المكتشفة تلقائياً (الأطول أولاً)
    // هذا يضمن أن "نيو فنار ابيض" يُطابق قبل "نيو فنار" أو "فنار"
    final sortedBrands = _autoDiscoveredBrands.toList()
      ..sort((a, b) => b.length.compareTo(a.length)); // الأطول أولاً
    
    for (final brand in sortedBrands) {
      if (normalizedName.contains(brand.toLowerCase())) {
        return brand;
      }
    }
    
    // ثالثاً: البحث في القائمة الثابتة (للماركات المعروفة)
    // مرتبة من الأطول للأقصر لضمان التطابق الأدق
    final knownBrands = [
      // فنار ومشتقاتها (الأطول أولاً)
      'نيو فنار', 'نيوفنار', 'فنار',
      // سيمنز/سيمنس
      'سيمنز', 'سيمنس', 'siemens',
      // باناسونيك/ناشونال
      'باناسونيك', 'panasonic', 'ناشونال', 'national',
      // شنايدر
      'شنايدر', 'schneider',
      // ليجراند
      'ليجراند', 'legrand',
      // ABB
      'abb',
      // علامات أخرى
      'الترا', 'ultra', 'تبييك', 'توشيبا', 'toshiba',
      'فيليبس', 'philips', 'اوسرام', 'osram',
      'جنرال', 'general', 'lg', 'سامسونج', 'samsung',
      // علامات محلية/إقليمية
      'كورلن', 'بيرلي', 'perylli', 'ريفال',
      'أسيا', 'اسيا', 'asia', 'ايجا',
      'اردني', 'ايطاليانو', 'هولندي', 'الماني',
      'بي جي', 'bg', 'otg', 'es', 'جام', 'رامكو', 'ramco', 'dvr',
    ];
    
    for (final brand in knownBrands) {
      if (normalizedName.contains(brand.toLowerCase())) {
        // توحيد الأسماء المتشابهة
        if (brand == 'سيمنس' || brand == 'siemens') return 'سيمنز';
        // 🆕 لا نوحد "نيو فنار" إلى "فنار" - نتركها كما هي
        // هذا يسمح بالتمييز بين "فنار" و "نيو فنار" و "نيو فنار ابيض"
        if (brand == 'نيوفنار') return 'نيو فنار';
        if (brand == 'panasonic') return 'باناسونيك';
        if (brand == 'national') return 'ناشونال';
        if (brand == 'schneider') return 'شنايدر';
        if (brand == 'legrand') return 'ليجراند';
        if (brand == 'ultra') return 'الترا';
        if (brand == 'toshiba') return 'توشيبا';
        if (brand == 'philips') return 'فيليبس';
        if (brand == 'osram') return 'اوسرام';
        if (brand == 'general') return 'جنرال';
        if (brand == 'samsung') return 'سامسونج';
        if (brand == 'perylli') return 'بيرلي';
        if (brand == 'أسيا' || brand == 'asia') return 'اسيا';
        if (brand == 'ramco') return 'رامكو';
        return brand;
      }
    }
    
    return null;
  }
  
  /// 🔧 فصل الأرقام الملتصقة بالكلمات العربية
  /// مثال: "13Aفنار" -> "13A فنار"
  /// مثال: "بلك32Aسيمنز" -> "بلك 32A سيمنز"
  static String _separateNumbersFromWords(String text) {
    // نمط 1: رقم + حروف إنجليزية + حروف عربية (مثل "13Aفنار")
    // نضيف فراغ بين الحروف الإنجليزية والعربية
    String result = text.replaceAllMapped(
      RegExp(r'(\d+[a-zA-Z]+)([\u0600-\u06FF])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    
    // نمط 2: حروف عربية + رقم (مثل "بلك32")
    // نضيف فراغ بين الحروف العربية والأرقام
    result = result.replaceAllMapped(
      RegExp(r'([\u0600-\u06FF])(\d)'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    
    // نمط 3: رقم + حروف عربية مباشرة (مثل "13فنار")
    result = result.replaceAllMapped(
      RegExp(r'(\d)([\u0600-\u06FF])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    
    return result;
  }
  
  /// 🆕 استخراج الماركة من آخر كلمات اسم المنتج
  /// يبحث عن آخر 1-3 كلمات غير وصفية (ليست أرقام أو قياسات)
  static String? _extractBrandFromEnd(String productName) {
    // 🔧 فصل الأرقام الملتصقة بالكلمات أولاً
    // مثال: "13Aفنار" -> "13A فنار"
    // مثال: "32Aسيمنز" -> "32A سيمنز"
    final separatedName = _separateNumbersFromWords(productName);
    
    final words = separatedName.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return null;
    
    // نبدأ من آخر كلمة ونجمع الكلمات غير الوصفية
    final brandWords = <String>[];
    
    for (int i = words.length - 1; i >= 0 && brandWords.length < 3; i--) {
      final word = words[i].toLowerCase().trim();
      
      // تجاهل الكلمات القصيرة جداً
      if (word.length < 2) continue;
      
      // تجاهل الأرقام فقط
      if (RegExp(r'^\d+$').hasMatch(word)) break;
      
      // تجاهل الأرقام مع وحدات (مثل 13A, 16A, 32A)
      if (RegExp(r'^\d+[a-zA-Z]+$').hasMatch(word)) break;
      
      // تجاهل كلمات القياسات والأرقام
      if (_isMeasurementWord(word)) break;
      
      // أضف الكلمة للماركة
      brandWords.insert(0, word);
    }
    
    if (brandWords.isEmpty) return null;
    
    // إرجاع الماركة المستخرجة
    return brandWords.join(' ');
  }
  
  /// 🆕 التحقق إذا كانت الكلمة قياس أو رقم
  static bool _isMeasurementWord(String word) {
    final measurementWords = [
      // أرقام وقياسات
      'خط', 'خطين', 'ثلاث', 'اربع', 'اربعة', 'خمس', 'ست', 'سبع', 'ثمان', 'تسع', 'عشر',
      'واحد', 'اثنين', 'ثلاثة',
      'امبير', 'فولت', 'واط', 'ملم', 'سم', 'متر', 'انش', 'انج',
      // كلمات تقنية تدل على نهاية اسم المنتج الأساسي
      'دبل', 'سنجل', 'فاز',
    ];
    return measurementWords.contains(word);
  }
  
  /// 🆕 تطبيع النص لمطابقة الماركات (إزالة الفراغات وتوحيد الأحرف)
  static String _normalizeForBrandMatch(String text) {
    return text
        .toLowerCase()
        .replaceAll(' ', '')
        .replaceAll('\u00A0', '')
        .replaceAll('-', '')
        .replaceAll('_', '')
        .trim();
  }

  /// التحقق إذا كانت نتيجة البحث تطابق سياق الجلسة
  bool matchesSessionContext(String productName) {
    // 🆕 البحث المباشر: اسم المنتج يحتوي على نص الماركة المكتشفة
    final productNameNormalized = _normalizeForBrandMatch(productName);
    for (final detectedBrand in detectedBrands) {
      final brandNormalized = _normalizeForBrandMatch(detectedBrand);
      if (productNameNormalized.contains(brandNormalized)) {
        return true;
      }
    }
    
    // التحقق من الماركة المستخرجة (للتوافق مع النظام القديم)
    final productBrand = extractBrand(productName);
    if (productBrand != null) {
      final productBrandNormalized = _normalizeForBrandMatch(productBrand);
      for (final detectedBrand in detectedBrands) {
        final brandNormalized = _normalizeForBrandMatch(detectedBrand);
        if (productBrandNormalized.contains(brandNormalized) ||
            brandNormalized.contains(productBrandNormalized)) {
          return true;
        }
      }
    }
    
    // التحقق من الكلمة الأخيرة
    final productLastWord = extractLastWord(productName);
    if (productLastWord != null && detectedLastWords.contains(productLastWord)) {
      return true;
    }
    
    return false;
  }
}


/// نتيجة بحث مع درجة الترجيح
class ScoredSearchResult {
  final int productId;
  final String productName;
  final double baseScore; // من FTS5
  final double brandBonus; // من العلامة التجارية
  final double customerBonus; // من تاريخ العميل
  final double installerBonus; // من تاريخ المُركّب
  final double associationBonus; // من المنتجات المرتبطة
  final double totalScore;

  ScoredSearchResult({
    required this.productId,
    required this.productName,
    this.baseScore = 0,
    this.brandBonus = 0,
    this.customerBonus = 0,
    this.installerBonus = 0,
    this.associationBonus = 0,
  }) : totalScore = baseScore + brandBonus + customerBonus + installerBonus + associationBonus;

  @override
  String toString() => 'ScoredSearchResult($productName, total: $totalScore)';
}

/// إحصائيات التدريب
class TrainingStats {
  final int totalInvoices;
  final int totalItems;
  final int totalAssociations;
  final int totalCustomerPreferences;
  final int totalInstallerPreferences;
  final int uniqueBrands;
  final DateTime trainedAt;
  final Duration trainingDuration;

  TrainingStats({
    required this.totalInvoices,
    required this.totalItems,
    required this.totalAssociations,
    required this.totalCustomerPreferences,
    required this.totalInstallerPreferences,
    required this.uniqueBrands,
    required this.trainedAt,
    required this.trainingDuration,
  });

  Map<String, dynamic> toMap() => {
    'total_invoices': totalInvoices,
    'total_items': totalItems,
    'total_associations': totalAssociations,
    'total_customer_preferences': totalCustomerPreferences,
    'total_installer_preferences': totalInstallerPreferences,
    'unique_brands': uniqueBrands,
    'trained_at': trainedAt.toIso8601String(),
    'training_duration_ms': trainingDuration.inMilliseconds,
  };

  factory TrainingStats.fromMap(Map<String, dynamic> map) => TrainingStats(
    totalInvoices: map['total_invoices'] as int,
    totalItems: map['total_items'] as int,
    totalAssociations: map['total_associations'] as int,
    totalCustomerPreferences: map['total_customer_preferences'] as int,
    totalInstallerPreferences: map['total_installer_preferences'] as int,
    uniqueBrands: map['unique_brands'] as int,
    trainedAt: DateTime.parse(map['trained_at'] as String),
    trainingDuration: Duration(milliseconds: map['training_duration_ms'] as int),
  );

  @override
  String toString() => '''
📊 إحصائيات التدريب:
   - الفواتير: $totalInvoices
   - الأصناف: $totalItems
   - العلاقات: $totalAssociations
   - تفضيلات العملاء: $totalCustomerPreferences
   - تفضيلات المُركّبين: $totalInstallerPreferences
   - العلامات التجارية: $uniqueBrands
   - وقت التدريب: ${trainingDuration.inSeconds} ثانية
''';
}
