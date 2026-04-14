// services/multi_provider_ai_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'gemini_service.dart';
import 'file_preprocessor_service.dart';
import 'ocr_space_service.dart';
import 'glm_service.dart';
import 'mistral_service.dart';  // ✅ Mistral Pixtral - مجاني سخي!

/// خدمة AI متعددة المزودين
/// الترتيب: Mistral -> Gemini -> Groq -> OpenRouter
class MultiProviderAIService {
  MultiProviderAIService({
    required this.geminiApiKey,
    this.geminiApiKey2,
    this.geminiApiKey3,
    this.geminiApiKey4,
    this.openRouterApiKey,
    this.groqApiKey,
    this.cloudflareApiToken,
    this.cloudflareAccountId,
    this.ocrSpaceApiKey,
    this.glmApiKey,
    this.mistralApiKey,  // ✅ Mistral Pixtral
  });

  final String geminiApiKey;
  final String? geminiApiKey2;
  final String? geminiApiKey3;
  final String? geminiApiKey4;
  final String? openRouterApiKey;
  final String? groqApiKey;
  final String? cloudflareApiToken;
  final String? cloudflareAccountId;
  final String? ocrSpaceApiKey;
  final String? glmApiKey;
  final String? mistralApiKey;  // ✅ Mistral

  // حالة المزود الحالي
  String _currentProvider = 'mistral';
  
  // ✅ مثيل Gemini مشترك للحفاظ على المفتاح الناجح
  static GeminiService? _sharedGeminiService;
  
  /// الحصول على مثيل Gemini مشترك
  GeminiService _getGeminiService() {
    _sharedGeminiService ??= GeminiService(
      apiKey: geminiApiKey,
      apiKey2: geminiApiKey2,
      apiKey3: geminiApiKey3,
      apiKey4: geminiApiKey4,
    );
    return _sharedGeminiService!;
  }

  // ⚙️ إعدادات التحكم في المزودين
  static const bool _mistralEnabled = false;  // ❌ Rate limit - معطّل مؤقتاً
  static const bool _glmEnabled = false;  // ❌ يحتاج رصيد
  static const bool _geminiEnabled = true;  // ✅ الأولوية الأولى
  static const bool _openRouterEnabled = true;  // ✅ مفعّل
  static const bool _groqEnabled = true;  // ✅ مفعّل

  /// استخراج بيانات الفاتورة/الإيصال من الصورة
  /// الترتيب: Mistral -> Gemini -> Groq -> OpenRouter
  Future<Map<String, dynamic>> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType,
    required List<Map<String, dynamic>> products,
  }) async {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🚀 بدء استخراج البيانات');
    print('📋 المزودين المفعّلين:');
    if (_mistralEnabled) print('   ✅ Mistral Pixtral (الأولوية - مجاني سخي!)');
    else print('   ❌ Mistral (معطّل)');
    if (_glmEnabled) print('   ✅ GLM');
    else print('   ❌ GLM (معطّل)');
    if (_geminiEnabled) print('   ✅ Gemini');
    else print('   ❌ Gemini (معطّل)');
    if (_openRouterEnabled) print('   ✅ OpenRouter');
    else print('   ❌ OpenRouter (معطّل)');
    if (_groqEnabled) print('   ✅ Groq');
    else print('   ❌ Groq (معطّل)');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    // =====================================================
    // المرحلة 1: Mistral Pixtral (أولوية قصوى - مجاني سخي!)
    // =====================================================
    if (_mistralEnabled && mistralApiKey != null && mistralApiKey!.isNotEmpty) {
      try {
        print('🤖 المرحلة 1: محاولة Mistral Pixtral (مجاني سخي!)...');
        _currentProvider = 'mistral';
        
        final mistralService = MistralService(apiKey: mistralApiKey!);
        final result = await mistralService.extractInvoiceFromImage(
          imageBytes: Uint8List.fromList(fileBytes),
          mimeType: fileMimeType,
          products: products,
        );

        print('✅ نجح Mistral Pixtral!');
        return result;
      } catch (e) {
        print('❌ فشل Mistral: $e');
      }
    }

    // =====================================================
    // المرحلة 2: GLM (معطّل - يحتاج رصيد)
    // =====================================================
    if (_glmEnabled && glmApiKey != null && glmApiKey!.isNotEmpty) {
      try {
        print('🤖 المرحلة 2: محاولة GLM...');
        _currentProvider = 'glm';
        
        final glmService = GlmService(apiKey: glmApiKey!);
        final result = await glmService.extractInvoiceFromImage(
          imageBytes: Uint8List.fromList(fileBytes),
          mimeType: fileMimeType,
          products: products,
        );

        print('✅ نجح GLM!');
        return result;
      } catch (e) {
        print('❌ فشل GLM: $e');
      }
    }

    // =====================================================
    // المرحلة 3: Gemini
    // =====================================================
    int stageNum = 3;
    if (!_mistralEnabled) stageNum--;
    if (!_glmEnabled) stageNum--;
    
    if (_geminiEnabled) {
      try {
        print('🤖 المرحلة $stageNum: محاولة Gemini مع جميع المفاتيح بالتوازي...');
        
        final gemini = _getGeminiService();
        final result = await gemini.extractInvoiceOrReceiptStructured(
          fileBytes: fileBytes,
          fileMimeType: fileMimeType,
          extractType: extractType,
          products: products,
        );

        _currentProvider = 'gemini';
        print('✅ نجح Gemini!');
        return result;
      } catch (e) {
        print('❌ فشل Gemini بعد تجربة جميع المفاتيح: $e');
      }
    }

    // =====================================================
    // المرحلة 4: Groq
    // =====================================================
    if (!_geminiEnabled) stageNum--;
    
    if (_groqEnabled && groqApiKey != null && groqApiKey!.isNotEmpty) {
      try {
        print('🤖 المرحلة $stageNum: محاولة Groq...');
        _currentProvider = 'groq';
        final result = await _extractWithGroq(
          fileBytes: fileBytes,
          fileMimeType: fileMimeType,
          extractType: extractType,
          products: products,
        );
        print('✅ نجح Groq!');
        return result;
      } catch (e) {
        print('❌ فشل Groq: $e');
      }
    }

    // =====================================================
    // المرحلة 3: OpenRouter (احتياطي)
    // =====================================================
    if (_openRouterEnabled && openRouterApiKey != null && openRouterApiKey!.isNotEmpty) {
      try {
        print('🤖 المرحلة ${(_geminiEnabled ? 2 : 1) + (_groqEnabled ? 1 : 0)}: محاولة OpenRouter...');
        _currentProvider = 'openrouter';
        final result = await _extractWithOpenRouter(
          fileBytes: fileBytes,
          fileMimeType: fileMimeType,
          extractType: extractType,
          products: products,
        );
        print('✅ نجح OpenRouter!');
        return result;
      } catch (e) {
        print('❌ فشل OpenRouter: $e');
      }
    }

    // =====================================================
    // المرحلة 4: Cloudflare (احتياطي نهائي)
    // =====================================================
    if (cloudflareApiToken != null && cloudflareApiToken!.isNotEmpty &&
        cloudflareAccountId != null && cloudflareAccountId!.isNotEmpty) {
      try {
        print('🤖 المرحلة الأخيرة: محاولة Cloudflare...');
        _currentProvider = 'cloudflare';
        final result = await _extractWithCloudflare(
          fileBytes: fileBytes,
          fileMimeType: fileMimeType,
          extractType: extractType,
          products: products,
        );
        print('✅ نجح Cloudflare!');
        return result;
      } catch (e) {
        print('❌ فشل Cloudflare: $e');
      }
    }

    throw Exception('❌ فشلت جميع المزودين في استخراج البيانات');
  }

  /// استخراج باستخدام Groq API
  Future<Map<String, dynamic>> _extractWithGroq({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType,
    required List<Map<String, dynamic>> products,
  }) async {
    if (groqApiKey == null || groqApiKey!.isEmpty) {
      throw Exception('مفتاح Groq غير متوفر');
    }

    _currentProvider = 'groq';
    print('🤖 Groq: بدء استخراج $extractType...');

    // ✅ تحضير الملف (ضغط الصور، رفض PDF)
    late final Uint8List processedBytes;
    late final String processedMimeType;
    try {
      final processed = await FilePreprocessorService.prepareForNonGeminiProvider(
        fileBytes,
        fileMimeType,
      );
      processedBytes = processed.bytes;
      processedMimeType = processed.mimeType;
      print('✅ تم تحضير الملف: ${processedBytes.length} بايت، النوع: $processedMimeType');
    } catch (prepError) {
      print('❌ فشل تحضير الملف: $prepError');
      rethrow;
    }

    // ✅ استخراج النص من الملف الأصلي (صورة أو PDF) باستخدام OCR.space (Engine 3)
    String extractedText = '';
    if (ocrSpaceApiKey != null && ocrSpaceApiKey!.isNotEmpty) {
      try {
        final ocrService = OcrSpaceService(apiKey: ocrSpaceApiKey!);
        final isPdf = fileMimeType == 'application/pdf';
        
        print('🔍 Groq: استخراج النص باستخدام OCR.space (Engine 3, ${isPdf ? "PDF" : "صورة"})...');
        
        extractedText = await ocrService.extractText(
          Uint8List.fromList(fileBytes),  // الملف الأصلي
          engine: 3,  // Google Tesseract - الأفضل
          // language: null = auto-detect
          isPdf: isPdf,
        );
        
        if (extractedText.isNotEmpty) {
          print('✅ Groq: تم استخراج ${extractedText.length} حرف من ${isPdf ? "PDF" : "الصورة"}');
        }
      } catch (e) {
        print('⚠️ Groq: فشل OCR.space، المتابعة بدون نص مستخرج: $e');
      }
    }

    // تحويل الصورة إلى base64
    final base64Image = base64Encode(processedBytes);
    
    // التحقق من حجم Base64
    final base64Size = base64Image.length;
    print('📏 حجم Base64: ${(base64Size / 1024).toStringAsFixed(1)} كيلوبايت');
    if (base64Size > 4 * 1024 * 1024) {
      throw Exception('الملف كبير جداً حتى بعد الضغط. الحد الأقصى 4 ميجابايت Base64 لـ Groq.');
    }

    // ✅ استخدام برومبت محسّن مع النص المستخرج
    final prompt = _buildGroqInvoiceExtractionPrompt(
      products: products,
      extractedText: extractedText,
    );

    // قائمة النماذج المُحدّثة (Groq Vision Models - 2025)
    final models = [
      'meta-llama/llama-4-scout-17b-16e-instruct',  // الأحدث
      'llama-3.2-90b-vision-preview',  // بديل قوي
    ];

    for (int i = 0; i < models.length; i++) {
      final model = models[i];
      print('🔄 Groq: تجربة النموذج ${i + 1}/${models.length} - $model');

      final requestBody = {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:$processedMimeType;base64,$base64Image'}
              }
            ]
          }
        ],
        'temperature': 0.3,
        'max_tokens': 4096,
      };

      try {
        print('🔑 Groq: المفتاح المستخدم: ${groqApiKey?.substring(0, 10)}... (الطول: ${groqApiKey?.length})');
        
        final response = await http.post(
          Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $groqApiKey',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': 'application/json',
            'Connection': 'keep-alive',
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 120));

        if (response.statusCode != 200) {
          throw Exception('Groq error: ${response.statusCode} ${response.body}');
        }

        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final content = decoded['choices']?[0]?['message']?['content'] as String?;

        if (content == null || content.isEmpty) {
          throw Exception('Groq: لا يوجد محتوى في الرد');
        }

        // استخراج JSON من الرد
        final jsonStr = _extractJsonFromContent(content);
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;

        print('✅ تم الاستخراج بنجاح باستخدام Groq (نموذج: $model)');
        return result;
      } catch (e) {
        print('❌ Groq فشل مع النموذج $model: $e');
        if (i == models.length - 1) {
          rethrow;
        }
        print('🔄 Groq: الانتقال للنموذج الاحتياطي...');
      }
    }
    
    throw Exception('جميع نماذج Groq فشلت');
  }

  /// استخراج JSON من نص الرد
  String _extractJsonFromContent(String content) {
    String text = content.trim();
    
    // مسح علامات الماركدوان المشهورة في البداية والنهاية
    if (text.toLowerCase().startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    
    // الأسلوب المتقدم: البحث عن أول قوس فتح وآخر قوس غلق
    final startObj = text.indexOf('{');
    final endObj = text.lastIndexOf('}');
    final startArr = text.indexOf('[');
    final endArr = text.lastIndexOf(']');
    
    int start = -1;
    int end = -1;
    
    // تحديد ما هو غلاف الـ JSON (هل هو مصفوفة أم كائن)
    if (startObj != -1 && endObj != -1) {
      if (startArr != -1 && startArr < startObj && endArr > endObj) {
        start = startArr;
        end = endArr;
      } else {
        start = startObj;
        end = endObj;
      }
    } else if (startArr != -1 && endArr != -1) {
      start = startArr;
      end = endArr;
    }
    
    if (start != -1 && end != -1) {
      return text.substring(start, end + 1).trim();
    }
    
    return text.trim();
  }

  /// الحصول على المزود الحالي
  String get currentProvider => _currentProvider;

  String _buildInvoiceExtractionPrompt({List<Map<String, dynamic>>? products}) {
    final productsJson = products != null && products.isNotEmpty
        ? jsonEncode(products)
        : '[]';
    
    return '''أنت محاسب ذكي خبير في تحليل الفواتير التجارية العراقية. تعمل كإنسان يقرأ الفاتورة ويبحث عن المنتجات في قاعدة البيانات.

## مهمتك الأساسية:
1. اقرأ صورة الفاتورة واستخرج كل المنتجات والفاتورة.
2. لكل منتج، ابحث عن أقرب تطابق في قاعدة البيانات المرفقة.
3. **مهم جداً**: اكتشف "وحدة البيع" (sale_unit) هل هي كرتون أم باكيت أم قطعة أم متر، وما هو معامل الضرب (units_multiplier) بناءً على حقل `unit_hierarchy` المأخوذ من قاعدة البيانات.

## قائمة المنتجات الموجودة في قاعدة البيانات (مع الهيكلية unit_hierarchy):
$productsJson

## كيف تُطابق المنتجات (تعلم من البيانات):

### الخطوة 1: حلل أسماء المنتجات في القاعدة
انظر للأسماء الموجودة وافهم التنسيق المستخدم. مثلاً إذا رأيت:
- "سيمنس 2×1.5 بيرلي" → التنسيق هو: [نوع] [عدد×مقاس] [ماركة]
- "فلكس 3×2.5 ناشيونال" → نفس التنسيق

### الخطوة 2: استخرج العناصر من اسم المنتج في الفاتورة
مثال: "Berly 80M 1.5*2 سيمس" يحتوي على:
- ماركة: Berly (بالإنجليزي)
- طول اللفة: 80M (يُحذف من الاسم لكن يُحفظ في units_count!)
- مقاس: 1.5*2
- نوع: سيمس

### الخطوة 3: طابق مع القاعدة
ابحث عن منتج يحتوي على نفس العناصر (ماركة + نوع + مقاس)

## قواعد أساسية ثابتة:

### 1. استخراج عدد الوحدات (مهم جداً!):
- إذا وجدت رقم متبوع بـ M أو متر في اسم المنتج → unit_type = "meter" و units_count = ذلك الرقم
  - مثال: "80M" → units_count: 80, unit_type: "meter"
  - مثال: "M 91.4" → units_count: 91.4, unit_type: "meter"  
  - مثال: "250M" → units_count: 250, unit_type: "meter"
  - مثال: "90 متر" → units_count: 90, unit_type: "meter"
- إذا لم يوجد أمتار → unit_type = "piece" و units_count = 1
- طول اللفة يُحذف من الاسم لكن يُحفظ في units_count

### 2. ترتيب المقاس قد يكون معكوساً:
- في الفاتورة: 1.5*2 (مقاس×عدد)
- في القاعدة: 2×1.5 (عدد×مقاس)
- المهم: نفس الأرقام = نفس المنتج

### 3. التعبئة والكميات تُحذف:
- "كوب ماء تعبئة 20" → "كوب ماء" (التعبئة = عدد القطع في الكرتون، ليست جزء من الاسم)
- "صابون تعبئة 12" → "صابون"
- "درزن", "شدة", "كرتون", "باكيت" → تُحذف من الاسم عند المطابقة

### 4. الترجمة بين الإنجليزي والعربي:
ابحث عن الكلمات المتشابهة صوتياً:
- Berly/BERLY ≈ بيرلي
- Flex/FLEX ≈ فلكس  
- National ≈ ناشيونال
- Pioneer ≈ بايونير
- SIMS/Siemens/سيمس ≈ سيمنس

### 5. الرموز المختصرة:
- B = بيرلي (Berly)
- XW/W = سيمنس
- F = فلكس
- مثال: B2-4-80XW = بيرلي 2×4 سيمنس 80 متر

## البنية المطلوبة (JSON object فقط، ليس مصفوفة):
{
  "invoice_date": "YYYY-MM-DD",
  "invoice_number": "",
  "currency": "IQD أو USD (حسب ما مكتوب في الفاتورة)",
  "line_items": [
    {
      "name": "اسم المنتج من قاعدة البيانات (إذا وُجد تطابق) أو الاسم المُنظف",
      "original_name": "الاسم الأصلي كما في الفاتورة بالضبط",
      "qty": 0,
      "price": 0,
      "amount": 0,
      "unit_type": "meter أو piece",
      "units_count": 0,
      "sale_unit": "الوحدة المقروءة (مثل: كرتون، باكيت، قطعة، متر، لفة)",
      "units_multiplier": 1,
      "matched_product_id": null,
      "old_cost_price": null,
      "is_new_product": false,
      "confidence": 0.0,
      "reason": "شرح المطابقة"
    }
  ],
  "totals": {"subtotal": 0, "discount": 0, "grand_total": 0},
  "amount_paid": 0,
  "remaining": 0,
  "status": "نقد|دين"
}

## قواعد الحقول:

### sale_unit و units_multiplier (مهم جداً للتسلسل الهرمي):
- اكتشف "وحدة البيع" (sale_unit) المذكورة في الفاتورة (مثل كرتون، باكيت، درزن).
- استعن بحقل `unit_hierarchy` المرفق مع كل منتج في قاعدة البيانات لمعرفة المضاعف الفعلي (`units_multiplier`).
- مثال: إذا اشتريت "كوب ماء (كرتون)" ووجدت في هيراركية المنتج أن الكرتون يعادل 100 قطعة، أرجع `sale_unit`="كرتون" و `units_multiplier`= 100.
- إذا لم تُذكر وحدة صريحة وتأكدت أنها مفرد، اجعل `sale_unit`="قطعة" و `units_multiplier`= 1.

### unit_type و units_count (مهم جداً):
- unit_type: "meter" إذا المنتج يُباع بالمتر (كابلات، أسلاك، سيمس، فلكس) أو "piece" للقطع العادية
- units_count: عدد الأمتار في اللفة الواحدة (مثلاً 80 أو 91.4) أو 1 للقطع
- مثال: "Berly 80M 1.5*2 سيمس" بكمية 100 لفة → qty: 100, units_count: 80, unit_type: "meter"
- مثال: "بسمار 16mm" بكمية 1 → qty: 1, units_count: 1, unit_type: "piece"

### confidence (0.0 - 1.0):
- 0.90-1.0: تطابق مؤكد (كل العناصر متطابقة)
- 0.70-0.89: تطابق جيد (معظم العناصر متطابقة)
- 0.50-0.69: تطابق محتمل (بعض العناصر متطابقة)
- أقل من 0.50: منتج جديد

### reason (مهم جداً):
اشرح بالعربي كيف طابقت المنتج:
- "تطابق: Berly=بيرلي، سيمس=سيمنس، 1.5*2=2×1.5"
- "منتج جديد: لم أجد ماركة X في القاعدة"

### is_new_product:
- true: إذا confidence < 0.50 أو لم تجد تطابق
- false: إذا وجدت تطابق في القاعدة

### matched_product_id و old_cost_price:
- إذا وجدت تطابق: استخدم id و cost_price من القاعدة
- إذا منتج جديد: اتركهم null

## تنبيهات:
- أرجع JSON object فقط (ليس مصفوفة!) بدون أي نص إضافي
- اقرأ الأرقام بدقة (الكمية، السعر، المبلغ)
- إذا السعر غير واضح: احسبه من المبلغ ÷ الكمية
- استخرج العملة من الفاتورة (IQD أو USD أو \$)
- **لا تنسَ استخراج عدد الأمتار من اسم المنتج!''';
  }

  /// برومقت الأصلي مع إضافة قاعدة أولوية التعبئة
  String _buildGroqInvoiceExtractionPrompt({
    List<Map<String, dynamic>>? products,
    String extractedText = '',
  }) {
    final productsJson = products != null && products.isNotEmpty
        ? jsonEncode(products)
        : '[]';

    // ✅ إضافة النص المستخرج من Google Vision إذا وُجد
    final extractedTextSection = extractedText.isNotEmpty 
        ? '''

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## 📄 النص المستخرج من الصورة (Google Vision OCR)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

**هذا النص مستخرج من صورة الفاتورة باستخدام Google Cloud Vision API:**

```
$extractedText
```

⚠️ **تعليمات مهمة:**
- هذا النص مرجع أساسي لك - استخدمه لتأكيد المعلومات
- قد يحتوي على أخطاء بسيطة في القراءة
- إذا كانت الصورة غير واضحة، اعتمد على هذا النص
- قارن بين الصورة والنص للحصول على أفضل نتيجة

''' 
        : '';
    
    return '''أنت محاسب ذكي خبير في تحليل الفواتير التجارية العراقية. تعمل كإنسان يقرأ الفاتورة ويبحث عن المنتجات في قاعدة البيانات.
$extractedTextSection
## مهمتك الأساسية:
1. اقرأ صورة الفاتورة واستخرج كل المنتجات بدقة
2. لكل منتج في الفاتورة، ابحث عن أقرب تطابق في قائمة المنتجات أدناه
3. استخدم اسم المنتج من القاعدة (وليس من الفاتورة) إذا وجدت تطابق
4. **مهم جداً**: استخرج عدد الأمتار أو القطع لكل منتج من الاسم أو من الفاتورة

## قائمة المنتجات الموجودة في قاعدة البيانات:
$productsJson

## كيف تُطابق المنتجات (تعلم من البيانات):

### الخطوة 1: حلل أسماء المنتجات في القاعدة
انظر للأسماء الموجودة وافهم التنسيق المستخدم. مثلاً إذا رأيت:
- "سيمنس 2×1.5 بيرلي" → التنسيق هو: [نوع] [عدد×مقاس] [ماركة]
- "فلكس 3×2.5 ناشيونال" → نفس التنسيق

### الخطوة 2: استخرج العناصر من اسم المنتج في الفاتورة
مثال: "Berly 80M 1.5*2 سيمس" يحتوي على:
- ماركة: Berly (بالإنجليزي)
- طول اللفة: 80M (يُحذف من الاسم لكن يُحفظ في units_count!)
- مقاس: 1.5*2
- نوع: سيمس

### الخطوة 3: طابق مع القاعدة
ابحث عن منتج يحتوي على نفس العناصر (ماركة + نوع + مقاس)

## قواعد أساسية ثابتة:

### 1. استخراج عدد الوحدات (مهم جداً!):
- إذا وجدت رقم متبوع بـ M أو متر في اسم المنتج → unit_type = "meter" و units_count = ذلك الرقم
  - مثال: "80M" → units_count: 80, unit_type: "meter"
  - مثال: "M 91.4" → units_count: 91.4, unit_type: "meter"  
  - مثال: "250M" → units_count: 250, unit_type: "meter"
  - مثال: "90 متر" → units_count: 90, unit_type: "meter"
- ✅ **قاعدة جديدة مهمة**: إذا كان المنتج بالمتر (كيبل، سلك) و**لا يوجد رقم متبوع بـ M** في الاسم، ولكن **الكمية كبيرة (أكثر من 10)** → استخدم **الكمية كـ units_count**
  - مثال: "كيبل 4*4 بيرلي" مع كمية 500 متر → unit_type: "meter", units_count: 500
  - مثال: "واير كاميرا" مع كمية 250 متر → unit_type: "meter", units_count: 250
- إذا لم يوجد أمتار → unit_type = "piece" و units_count = 1
- طول اللفة يُحذف من الاسم لكن يُحفظ في units_count

### 2. ترتيب المقاس قد يكون معكوساً:
- في الفاتورة: 1.5*2 (مقاس×عدد)
- في القاعدة: 2×1.5 (عدد×مقاس)
- المهم: نفس الأرقام = نفس المنتج

### 3. التعبئة والكميات تُحذف:
- "كوب ماء تعبئة 20" → "كوب ماء" (التعبئة = عدد القطع في الكرتون، ليست جزء من الاسم)
- "صابون تعبئة 12" → "صابون"
- "درزن", "شدة", "كرتون", "باكيت" → تُحذف من الاسم عند المطابقة

### 4. الترجمة بين الإنجليزي والعربي:
ابحث عن الكلمات المتشابهة صوتياً:
- Berly/BERLY ≈ بيرلي
- Flex/FLEX ≈ فلكس  
- National ≈ ناشيونال
- Pioneer ≈ بايونير
- SIMS/Siemens/سيمس ≈ سيمنس

### 5. الرموز المختصرة:
- B = بيرلي (Berly)
- XW/W = سيمنس
- F = فلكس
- مثال: B2-4-80XW = بيرلي 2×4 سيمنس 80 متر

### 6. ✅ استخراج وحدة البيع من الفاتورة (مهم جداً!):
- انظر لعمود "الوحدة" في جدول الفاتورة (قد يكون: لفة، كارتون، باكيت، قطعة، كيس...)
- استخرج الوحدة في حقل "sale_unit"
- أمثلة على الوحدات في الفواتير:
  - "لفة" → sale_unit: "لفة"
  - "كارتون" أو "كرتون" → sale_unit: "كرتون"
  - "باكيت" أو "باكت" → sale_unit: "باكيت"
  - "كيس" → sale_unit: "كيس"
  - "قطعة" → sale_unit: "قطعة"
  - "متر" → sale_unit: "متر"

### 7. ✅ استخراج الوحدة والتعبئة من عمود واحد (مهم جداً!):
- في بعض الفواتير، يكون هناك عمود واحد يحتوي على **التعبئة + الوحدة** معاً
- أمثلة على هذا العمود:
  - "100 قطعة" → التعبئة: 100، الوحدة: "قطعة"
  - "10 باكيت" → التعبئة: 10، الوحدة: "باكيت"
  - "لفة" → الوحدة: "لفة" (بدون رقم = التعبئة = 1)
  - "كارتون" → الوحدة: "كرتون" (بدون رقم = التعبئة = 1)
- إذا وجدت رقم + وحدة → استخرج الرقم في units_count والوحدة في sale_unit
- إذا وجدت وحدة فقط بدون رقم → sale_unit = الوحدة، units_count = 1

### 8. ⚠️ قاعدة أولوية التعبئة (مهم جداً!):
في الفواتير العراقية قد توجد التعبئة في مكانين:
1. **في اسم المنتج** → مثال: "سويج 45 أمبير أسيا رصاصي سلم تعبئة 100"
2. **في جدول الفاتورة** → عمود منفصل يسمى "تعبئة" أو "عدد"

**🔴 الأولوية دائماً للتعبئة المذكورة في اسم المنتج!**

| الحالة | مثال | units_count | السبب |
|--------|------|-------------|-------|
| التعبئة في الاسم | "...تعبئة 100" | 100 | الأولوية للاسم |
| التعبئة في الاسم | "...2 عينه" | 2 | الأولوية للاسم |
| لا تعبئة في الاسم | "سويج 45 أمبير" | من الجدول | نأخذ من الجدول |
| لا تعبئة نهائياً | أي اسم | 1 | قيمة افتراضية |

**❌ خطأ شائع:**
```
الاسم: "سويج 45 أمبير أسيا رصاصي سلم تعبئة 100"
العدد في الجدول: 2

خطأ: units_count: 2 ← هذا عدد الكراتين!
صحيح: units_count: 100 ← من "تعبئة 100" في الاسم
       qty: 2 ← عدد الكراتين من الجدول
```

## البنية المطلوبة (JSON object فقط، ليس مصفوفة):
{
  "invoice_date": "YYYY-MM-DD",
  "invoice_number": "",
  "currency": "IQD أو USD (حسب ما مكتوب في الفاتورة)",
  "line_items": [
    {
      "name": "اسم المنتج من قاعدة البيانات (إذا وُجد تطابق) أو الاسم المُنظف",
      "original_name": "الاسم الأصلي كما في الفاتورة بالضبط",
      "qty": 0,
      "price": 0,
      "amount": 0,
      "unit_type": "meter أو piece",
      "units_count": 0,
      "sale_unit": "وحدة البيع من الفاتورة (كرتون، باكيت، لفة، كيس...)",
      "matched_product_id": null,
      "old_cost_price": null,
      "is_new_product": false,
      "confidence": 0.0,
      "reason": "شرح المطابقة"
    }
  ],
  "totals": {"subtotal": 0, "discount": 0, "grand_total": 0},
  "amount_paid": 0,
  "remaining": 0,
  "status": "نقد|دين"
}

## قواعد الحقول:

### unit_type و units_count (مهم جداً):
- unit_type: "meter" إذا المنتج يُباع بالمتر (كابلات، أسلاك، سيمس، فلكس) أو "piece" للقطع العادية
- units_count: عدد الأمتار في اللفة الواحدة (مثلاً 80 أو 91.4) أو عدد القطع في الكرتون (من التعبئة)
- مثال: "Berly 80M 1.5*2 سيمس" بكمية 100 لفة → qty: 100, units_count: 80, unit_type: "meter"
- مثال: "سويج 45 أمبير تعبئة 100" بكمية 2 كرتون → qty: 2, units_count: 100, unit_type: "piece"

### confidence (0.0 - 1.0):
- 0.90-1.0: تطابق مؤكد (كل العناصر متطابقة)
- 0.70-0.89: تطابق جيد (معظم العناصر متطابقة)
- 0.50-0.69: تطابق محتمل (بعض العناصر متطابقة)
- أقل من 0.50: منتج جديد

### reason (مهم جداً):
اشرح بالعربي كيف طابقت المنتج:
- "تطابق: Berly=بيرلي، سيمس=سيمنس، 1.5*2=2×1.5"
- "منتج جديد: لم أجد ماركة X في القاعدة"

### is_new_product:
- true: إذا confidence < 0.50 أو لم تجد تطابق
- false: إذا وجدت تطابق في القاعدة

### matched_product_id و old_cost_price:
- إذا وجدت تطابق: استخدم id و cost_price من القاعدة
- إذا منتج جديد: اتركهم null

### sale_unit (وحدة البيع من الفاتورة):
- استخرج الوحدة من عمود "الوحدة" في الفاتورة
- أمثلة: "كرتون"، "باكيت"، "لفة"، "كيس"، "قطعة"، "متر"
- إذا كانت الوحدة "كارتون" في الفاتورة → sale_unit: "كرتون" (تصحيح التاء المربوطة)
- إذا كانت الوحدة "باكت" في الفاتورة → sale_unit: "باكيت" (تصحيح التاء المربوطة)

## تنبيهات:
- أرجع JSON object فقط (ليس مصفوفة!) بدون أي نص إضافي
- اقرأ الأرقام بدقة (الكمية، السعر، المبلغ)
- إذا السعر غير واضح: احسبه من المبلغ ÷ الكمية
- استخرج العملة من الفاتورة (IQD أو USD أو \$)
- **التعبئة في الاسم أهم من التعبئة في الجدول**
- **لا تنسَ استخراج عدد الأمتار من اسم المنتج!**

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## تحسينات إضافية للدقة والإنتاج
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### 9. ✅ خطوة 0: تنظيف النص (مهم جداً قبل التحليل)
قبل أي معالجة، قم بتنظيف النص المستخرج من الصورة:
- حوّل كل النص إلى lowercase للمقارنة
- استبدل أخطاء OCR الشائعة:
  - O → 0 إذا كانت بين أرقام (8OM → 80M)
  - I أو l → 1 إذا كانت في سياق أرقام
  - S → 5 في بعض السياقات (1.S → 1.5)
- احذف الرموز غير المهمة: -, _, /, |
- وحّد الفواصل: (*, x, ×, X → ×)
- أمثلة:
  - "8OM" ← "80M"
  - "1.S" ← "1.5"
  - "2,S" ← "2.5"
  - "S1MS" ← "SIMS" ← "سيمس"

### 10. ✅ قاعدة مطابقة ذكية (مرونة + دقة)
**مستويات المطابقة:**

| المستوى | الشروط | confidence |
|---------|--------|------------|
| مؤكد | تطابق الأرقام + الماركة/النوع متشابه | 0.95 |
| جيد | تطابق الأرقام + تشابه صوتي | 0.80 |
| مقبول | تطابق الأرقام فقط أو تشابه كبير | 0.60 |
| جديد | لا تطابق | 0.0 |

**قواعد التشابه الصوتي:**
- "اي فنار" ≈ "اي فناء" ← نفس الكلمة
- "سويج" ≈ "سويتش" ← نفس المعنى
- "اسيا" ≈ "آسيا" ← نفس الكلمة

**قاعدة مهمة:** إذا تطابقت الأرقام (المقاس) ← على الأقل 60% ثقة، لا تجعله منتج جديد!

### 11. ✅ نظام التقييم الداخلي (Scoring System)
احسب confidence كالتالي:
- تطابق المقاس = +0.4
- تطابق الماركة = +0.3
- تطابق النوع = +0.2
- تشابه الاسم العام = +0.1

| المجموع | النتيجة |
|---------|---------|
| ≥ 0.9 | تطابق مؤكد (confidence: 0.95) |
| 0.7-0.89 | تطابق جيد (confidence: 0.80) |
| 0.5-0.69 | تطابق محتمل (confidence: 0.60) |
| < 0.5 | منتج جديد (confidence: 0.0) |

### 12. ✅ Fallback ذكي للأسماء
إذا لم يوجد تطابق، أعد بناء اسم نظيف بالترتيب:
```
[النوع] [عدد×مقاس] [الماركة]
```
مثال: من "Berly 80M 1.5*2 سيمس" → name: "سيمنس 2×1.5 بيرلي"

### 13. ✅ قاعدة إلزامية لـ unit_hierarchy
- إذا وُجد unit_hierarchy للمنتج المطابق:
  - استخرج units_multiplier منه حسب sale_unit
  - لا تستخدم القيمة الافتراضية 1 إذا كان hierarchy موجود
- مثال: إذا sale_unit = "كرتون" و unit_hierarchy يحتوي {"كرتون": 100}:
  - units_multiplier = 100

### 14. ✅ منتجات المتر بدون M
إذا:
- المنتج يبدو كيبل/سلك/واير
- ولا يوجد M أو متر في الاسم
- والكمية > 20

→ اعتبرها meter واجعل units_count = الكمية

### 15. ✅ قاعدة منع التكرار
- إذا نفس المنتج مكرر في الفاتورة (نفس الاسم والمقاس):
  - اجمع الكمية في سطر واحد
  - اجمع المبلغ الإجمالي
- لا تكرر نفس المنتج في line_items

### 16. ✅ تحقق نهائي (Validation)
**تحقق من:**
- amount = qty × price
- إذا لم يتحقق ← احسب price = amount ÷ qty

**تحقق من التسلسل:**
- grand_total = subtotal - discount
- remaining = grand_total - amount_paid

### 17. ✅ معالجة النصوص غير المفهومة
إذا:
- الاسم غير مفهوم
- أو النص مشوش جداً (أكثر من 50% رموز غير مقروءة)

→
```json
{
  "name": "UNKNOWN",
  "original_name": "[النص المشوش]",
  "is_new_product": true,
  "confidence": 0.0,
  "reason": "نص غير مقروء أو مشوش"
}
```

### 18. ✅ أخطاء OCR شائعة - جدول مرجعي
| الخطأ | الصحيح |
|-------|--------|
| 8OM | 80M |
| 1.S | 1.5 |
| 2,S | 2.5 |
| O (في أرقام) | 0 |
| I/l (في أرقام) | 1 |
| B3rly | Berly |
| S1MS | SIMS |
| FLEX | فلكس |
| Nat1onal | National |

### 19. ✅ قواعد إضافية للمطابقة
- **تجاهل المسافات الزائدة**: "بيرلي 2×1.5" = "بيرلي 2 × 1.5"
- **تجاهل التشكيل**: "سيمَنس" = "سيمنس"
- **تجاهل الألف الممدودة**: "كابل" = "كيبل"
- **الترادفات**: "سلك" = "واير" = "كيبل"''';
  }

  /// استخراج باستخدام OpenRouter (النموذج الثاني في الترتيب)
  Future<Map<String, dynamic>> _extractWithOpenRouter({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType,
    required List<Map<String, dynamic>> products,
  }) async {
    if (openRouterApiKey == null || openRouterApiKey!.isEmpty) {
      throw Exception('مفتاح OpenRouter غير متوفر');
    }

    _currentProvider = 'openrouter';
    print('🤖 OpenRouter: بدء استخراج $extractType...');

    // ✅ تحضير الملف (ضغط الصور، تحويل PDF إلى صورة)
    late final Uint8List processedBytes;
    late final String processedMimeType;
    try {
      final processed = await FilePreprocessorService.prepareForNonGeminiProvider(
        fileBytes,
        fileMimeType,
      );
      processedBytes = processed.bytes;
      processedMimeType = processed.mimeType;
      print('✅ تم تحضير الملف لـ OpenRouter: ${processedBytes.length} بايت، النوع: $processedMimeType');
    } catch (prepError) {
      print('❌ فشل تحضير الملف: $prepError');
      rethrow;
    }

    // ✅ استخراج النص من الملف الأصلي (صورة أو PDF) باستخدام OCR.space (Engine 3)
    String extractedText = '';
    if (ocrSpaceApiKey != null && ocrSpaceApiKey!.isNotEmpty) {
      try {
        final ocrService = OcrSpaceService(apiKey: ocrSpaceApiKey!);
        final isPdf = fileMimeType == 'application/pdf';
        
        print('🔍 OpenRouter: استخراج النص باستخدام OCR.space (Engine 3, ${isPdf ? "PDF" : "صورة"})...');
        
        extractedText = await ocrService.extractText(
          Uint8List.fromList(fileBytes),  // الملف الأصلي
          engine: 3,  // Google Tesseract - الأفضل
          // language: null = auto-detect
          isPdf: isPdf,
        );
        
        if (extractedText.isNotEmpty) {
          print('✅ OpenRouter: تم استخراج ${extractedText.length} حرف من ${isPdf ? "PDF" : "الصورة"}');
        }
      } catch (e) {
        print('⚠️ OpenRouter: فشل OCR.space، المتابعة بدون نص مستخرج: $e');
      }
    }

    // ✅ استخدام برومبت محسّن مع النص المستخرج
    final prompt = _buildGroqInvoiceExtractionPrompt(
      products: products,
      extractedText: extractedText,
    );

    // تحويل الصورة إلى base64
    final base64Image = base64Encode(processedBytes);

    // نموذج ممتاز وسريع يدعم الرؤية ومناسب جداً للغة العربية
    // قائمة نماذج للتجربة (الأفضل أولاً) - نماذج مجانية متاحة
    final models = [
      'meta-llama/llama-3.2-11b-vision-instruct:free',  // مجاني - الأفضل للرؤية
      'qwen/qwen-2-vl-7b-instruct:free',  // مجاني - جيد للعربية
      'google/gemma-3-4b-it:free',  // مجاني - سريع
    ];

    for (int i = 0; i < models.length; i++) {
      final model = models[i];
      print('🔄 OpenRouter: تجربة النموذج ${i + 1}/${models.length} - $model');

      final requestBody = {
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': prompt
          },
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$processedMimeType;base64,$base64Image'
                }
              }
            ]
          }
        ],
        'temperature': 0.1,
        'max_tokens': 4096,
      };

      try {
        final response = await http.post(
          Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $openRouterApiKey',
            'HTTP-Referer': 'http://localhost', 
            'X-Title': 'Debt Book',
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 120));

        if (response.statusCode != 200) {
          print('❌ OpenRouter خطأ ${response.statusCode} مع $model');
          if (i == models.length - 1) {
            throw Exception('OpenRouter error: ${response.statusCode} ${response.body}');
          }
          continue;
        }

        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = decoded['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) {
          print('❌ OpenRouter: لا توجد choices مع $model');
          if (i == models.length - 1) {
            throw Exception('OpenRouter: استجابة غير صالحة');
          }
          continue;
        }

        final content = choices[0]['message']?['content'] as String?;
        if (content == null || content.isEmpty) {
          print('❌ OpenRouter: محتوى فارغ مع $model');
          if (i == models.length - 1) {
            throw Exception('OpenRouter: المحتوى فارغ');
          }
          continue;
        }

        // استخراج JSON من الرد
        final jsonStr = _extractJsonFromContent(content);
        final extractedData = jsonDecode(jsonStr) as Map<String, dynamic>;

        print('✅ تم الاستخراج بنجاح باستخدام OpenRouter (نموذج: $model)');
        return extractedData;
      } catch (e) {
        print('❌ OpenRouter فشل مع $model: $e');
        if (i == models.length - 1) {
          rethrow;
        }
      }
    }

    throw Exception('جميع نماذج OpenRouter فشلت');
  }

  /// استخراج باستخدام Cloudflare AI API
  Future<Map<String, dynamic>> _extractWithCloudflare({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType,
    required List<Map<String, dynamic>> products,
  }) async {
    if (cloudflareApiToken == null || cloudflareApiToken!.isEmpty ||
        cloudflareAccountId == null || cloudflareAccountId!.isEmpty) {
      throw Exception('مفتاح Cloudflare غير متوفر');
    }

    _currentProvider = 'cloudflare';
    print('🤖 Cloudflare: بدء استخراج $extractType...');

    // ✅ تحضير الملف (ضغط الصور، رفض PDF)
    late final Uint8List processedBytes;
    late final String processedMimeType;
    try {
      final processed = await FilePreprocessorService.prepareForNonGeminiProvider(
        fileBytes,
        fileMimeType,
      );
      processedBytes = processed.bytes;
      processedMimeType = processed.mimeType;
      print('✅ تم تحضير الملف: ${processedBytes.length} بايت، النوع: $processedMimeType');
    } catch (prepError) {
      print('❌ فشل تحضير الملف: $prepError');
      rethrow;
    }

    // استخدام نموذج Llama 3.2 Vision للصور
    final model = '@cf/meta/llama-3.2-11b-vision-instruct';
    final url = 'https://api.cloudflare.com/client/v4/accounts/$cloudflareAccountId/ai/run/$model';

    // بناء البرومبت
    final prompt = _buildInvoiceExtractionPrompt(products: products);

    // تحويل الصورة إلى base64
    final base64Image = base64Encode(processedBytes);
    
    // التحقق من حجم Base64
    final base64Size = base64Image.length;
    print('📏 حجم Base64: ${(base64Size / 1024).toStringAsFixed(1)} كيلوبايت');

    final requestBody = {
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$processedMimeType;base64,$base64Image'}
            }
          ]
        }
      ],
      'temperature': 0.3,
      'max_tokens': 4096,
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $cloudflareApiToken',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode != 200) {
        throw Exception('Cloudflare error: ${response.statusCode} ${response.body}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      
      // Cloudflare يرجع النتيجة في result.response
      final result = decoded['result'] as Map<String, dynamic>?;
      if (result == null) {
        throw Exception('Cloudflare: لا يوجد نتيجة في الرد');
      }

      final content = result['response'] as String?;
      if (content == null || content.isEmpty) {
        throw Exception('Cloudflare: لا يوجد محتوى في الرد');
      }

      // استخراج JSON من الرد
      final jsonStr = _extractJsonFromContent(content);
      final extractedData = jsonDecode(jsonStr) as Map<String, dynamic>;

      print('✅ تم الاستخراج بنجاح باستخدام Cloudflare');
      return extractedData;
    } catch (e) {
      print('❌ Cloudflare فشل: $e');
      rethrow;
    }
  }
}
