// services/gemini_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// خدمة Gemini مع دعم 4 مفاتيح API والفحص المتوازي
class GeminiService {
  GeminiService({
    required this.apiKey,
    this.apiKey2,
    this.apiKey3,
    this.apiKey4,
  }) {
    // بناء قائمة المفاتيح المتاحة
    _apiKeys = [apiKey];
    if (apiKey2 != null && apiKey2!.isNotEmpty) _apiKeys.add(apiKey2!);
    if (apiKey3 != null && apiKey3!.isNotEmpty) _apiKeys.add(apiKey3!);
    if (apiKey4 != null && apiKey4!.isNotEmpty) _apiKeys.add(apiKey4!);
    print('🔑 Gemini: تم تحميل ${_apiKeys.length} مفتاح/مفاتيح API');
  }

  final String apiKey;
  final String? apiKey2;
  final String? apiKey3;
  final String? apiKey4;
  
  // قائمة المفاتيح المتاحة
  late final List<String> _apiKeys;
  
  // ✅ فهرس المفتاح الناجح (لإعطائه أولوية)
  int? _lastSuccessfulKeyIndex;
  
  // فهرس المفتاح الحالي (للتوافق مع الكود القديم)
  int _currentKeyIndex = 0;
  
  String get _currentApiKey => _apiKeys[_currentKeyIndex];
  
  // ✅ ترتيب المفاتيح حسب الأولوية (الناجح أولاً)
  List<int> get _keyPriorityOrder {
    final indices = List<int>.generate(_apiKeys.length, (i) => i);
    
    // إذا كان هناك مفتاح ناجح سابقاً، ضعه في المقدمة
    if (_lastSuccessfulKeyIndex != null && _lastSuccessfulKeyIndex! < _apiKeys.length) {
      indices.remove(_lastSuccessfulKeyIndex);
      indices.insert(0, _lastSuccessfulKeyIndex!);
    }
    
    return indices;
  }
  
  /// التبديل للمفتاح التالي
  bool _switchToNextKey() {
    if (_currentKeyIndex < _apiKeys.length - 1) {
      _currentKeyIndex++;
      print('🔄 Gemini: التبديل للمفتاح ${_currentKeyIndex + 1} من ${_apiKeys.length}');
      return true;
    }
    print('❌ Gemini: لا توجد مفاتيح إضافية للتبديل');
    return false;
  }

  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent';

  /// ✅ فحص مفتاح واحد (للفحص المتوازي)
  Future<_KeyResult> _checkSingleKey({
    required int keyIndex,
    required Map<String, dynamic> body,
  }) async {
    final apiKey = _apiKeys[keyIndex];
    final uri = Uri.parse(_endpoint);
    
    try {
      print('🔍 Gemini: فحص المفتاح ${keyIndex + 1}/${_apiKeys.length}...');
      
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'X-goog-api-key': apiKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60)); // ✅ مهلة 60 ثانية لدعم الإنترنت الضعيف

      // نجاح
      if (response.statusCode == 200) {
        print('✅ Gemini: المفتاح ${keyIndex + 1} ناجح!');
        return _KeyResult(keyIndex: keyIndex, response: response, success: true);
      }
      
      // فشل
      print('❌ Gemini: المفتاح ${keyIndex + 1} فشل (${response.statusCode})');
      return _KeyResult(keyIndex: keyIndex, response: response, success: false);
      
    } on TimeoutException catch (_) {
      print('⏱️ Gemini: المفتاح ${keyIndex + 1} انتهت المهلة');
      return _KeyResult(keyIndex: keyIndex, response: null, success: false, error: 'timeout');
    } on SocketException catch (_) {
      print('🌐 Gemini: المفتاح ${keyIndex + 1} خطأ اتصال');
      return _KeyResult(keyIndex: keyIndex, response: null, success: false, error: 'socket');
    } catch (e) {
      print('💥 Gemini: المفتاح ${keyIndex + 1} خطأ: $e');
      return _KeyResult(keyIndex: keyIndex, response: null, success: false, error: e.toString());
    }
  }

  /// ✅ الفحص المتوازي لجميع المفاتيح مع أولوية للمفتاح الناجح
  Future<http.Response> _postWithParallelCheck({
    required Map<String, dynamic> body,
  }) async {
    // إذا كان هناك مفتاح ناجح سابقاً، جربه أولاً بسرعة
    if (_lastSuccessfulKeyIndex != null) {
      print('🚀 Gemini: محاولة المفتاح الناجح سابقاً (${_lastSuccessfulKeyIndex! + 1})...');
      final result = await _checkSingleKey(keyIndex: _lastSuccessfulKeyIndex!, body: body);
      if (result.success) {
        return result.response!;
      }
      // إذا فشل، نسيته وننتقل للفحص المتوازي
      print('⚠️ Gemini: المفتاح الناجح سابقاً فشل، فحص متوازي...');
      _lastSuccessfulKeyIndex = null;
    }
    
    // ✅ الفحص المتوازي لجميع المفاتيح
    print('🔥 Gemini: فحص متوازي لـ ${_apiKeys.length} مفاتيح...');
    
    final futures = _apiKeys.asMap().entries.map((entry) {
      return _checkSingleKey(keyIndex: entry.key, body: body);
    }).toList();
    
    // انتظر أول نجاح
    final results = await Future.wait(futures);
    
    // ابحث عن أول نجاح
    for (final result in results) {
      if (result.success && result.response != null) {
        // ✅ تذكر المفتاح الناجح
        _lastSuccessfulKeyIndex = result.keyIndex;
        print('🎯 Gemini: استخدام المفتاح ${result.keyIndex + 1} (تم تسجيله كمفتاح ناجح)');
        return result.response!;
      }
    }
    
    // جميع المفاتيح فشلت
    throw HttpException('جميع مفاتيح Gemini فشلت');
  }

  /// تنفيذ الطلب مع التبديل التلقائي بين المفاتيح
  Future<http.Response> _postWithRetry({
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(_endpoint);
    const int maxAttemptsPerKey = 1; // محاولة واحدة فقط لكل مفتاح
    
    // المحاولة مع كل مفتاح
    while (true) {
      int attempt = 0;
      
      while (attempt < maxAttemptsPerKey) {
        attempt++;
        try {
          print('🔑 Gemini: استخدام المفتاح ${_currentKeyIndex + 1}/${_apiKeys.length} (محاولة $attempt)');
          
          final response = await http
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'X-goog-api-key': _currentApiKey,
                },
                body: jsonEncode(body),
              )
              .timeout(const Duration(seconds: 60)); // مهلة 60 ثانية لتحميل الملفات الكبيرة

          // خطأ 429 (تجاوز الحصة) - تبديل فوري للمفتاح التالي
          if (response.statusCode == 429) {
            print('⚠️ Gemini: تجاوز الحصة (429) للمفتاح ${_currentKeyIndex + 1}');
            if (_switchToNextKey()) {
              attempt = 0; // إعادة تعيين المحاولات للمفتاح الجديد
              continue;
            }
            return response; // لا توجد مفاتيح إضافية
          }
          
          // خطأ في المفتاح - تبديل فوري
          if (response.statusCode == 401 || response.statusCode == 403) {
            print('🔑 Gemini: مفتاح غير صالح (${response.statusCode}) للمفتاح ${_currentKeyIndex + 1}');
            if (_switchToNextKey()) {
              attempt = 0;
              continue;
            }
            return response;
          }
          
          // أخطاء الخادم - إعادة المحاولة
          if (response.statusCode == 500 ||
              response.statusCode == 502 ||
              response.statusCode == 503 ||
              response.statusCode == 504) {
            if (attempt >= maxAttemptsPerKey) {
              if (_switchToNextKey()) {
                attempt = 0;
                continue;
              }
              return response;
            }
          } else if (response.statusCode == 200) {
            return response; // نجاح
          } else {
            // أي خطأ آخر (400, 404, etc) - تبديل فوري
            print('⚠️ Gemini: خطأ عام (${response.statusCode}) للمفتاح ${_currentKeyIndex + 1}');
            if (_switchToNextKey()) {
              attempt = 0;
              continue;
            }
            return response;
          }
        } on TimeoutException catch (_) {
          print('⏱️ Gemini: انتهت المهلة للمفتاح ${_currentKeyIndex + 1}');
          if (attempt >= maxAttemptsPerKey) {
            if (!_switchToNextKey()) {
              // لا مفاتيح أخرى متاحة - ارمي استثناء يسمح للمزود الاحتياطي بالعمل
              throw HttpException('جميع مفاتيح Gemini انتهت مهلة الاتصال');
            }
            attempt = 0;
          }
        } on SocketException catch (_) {
          print('🌐 Gemini: خطأ في الاتصال');
          if (attempt >= maxAttemptsPerKey) {
            if (!_switchToNextKey()) {
              throw HttpException('جميع مفاتيح Gemini فشلت في الاتصال');
            }
            attempt = 0;
          }
        }

        // تراجع أسي
        final delayMs = (math.pow(2, attempt) as num).toInt() * 300;
        final jitter = math.Random().nextInt(200);
        await Future.delayed(Duration(milliseconds: delayMs + jitter));
      }
      
      // إذا وصلنا هنا، فشلت كل المحاولات مع المفتاح الحالي
      if (!_switchToNextKey()) {
        throw HttpException('فشلت جميع مفاتيح Gemini API');
      }
    }
  }
  
  /// إعادة تعيين لاستخدام المفتاح الأول
  void resetToFirstKey() {
    _currentKeyIndex = 0;
  }
  
  /// الحصول على فهرس المفتاح الحالي
  int get currentKeyIndex => _currentKeyIndex;
  
  /// عدد المفاتيح المتاحة
  int get totalKeys => _apiKeys.length;

  /// إرسال رسالة نصية إلى Gemini والحصول على رد
  Future<String> sendMessage(String message, {List<String>? conversationHistory}) async {
    print('🤖 Gemini: إرسال رسالة...');
    
    final contents = <Map<String, dynamic>>[];
    
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      for (var i = 0; i < conversationHistory.length; i++) {
        contents.add({
          'role': i % 2 == 0 ? 'user' : 'model',
          'parts': [{'text': conversationHistory[i]}]
        });
      }
    }
    
    contents.add({
      'role': 'user',
      'parts': [{'text': message}]
    });
    
    final requestBody = {
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'topK': 40,
        'topP': 0.95,
        'maxOutputTokens': 1024,
      },
    };

    // ✅ استخدام الفحص المتوازي للمفاتيح
    final response = await _postWithParallelCheck(body: requestBody);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      print('❌ Gemini: لا توجد نتائج');
      return '';
    }
    final content = candidates.first['content'] as Map<String, dynamic>? ?? const {};
    final parts = content['parts'] as List? ?? [];
    if (parts.isEmpty) {
      print('❌ Gemini: رد فارغ');
      return '';
    }
    final text = parts.first['text'] as String? ?? '';
    
    print('✅ Gemini: تم استلام الرد (${text.length} حرف)');
    return text;
  }

  Future<String> extractTextFromPrompt(String prompt) async {
    final requestBody = {
      'contents': [
        {
          'parts': [{'text': prompt}]
        }
      ],
      'generationConfig': {
        'response_mime_type': 'application/json'
      }
    };

    // ✅ استخدام الفحص المتوازي للمفاتيح
    final response = await _postWithParallelCheck(body: requestBody);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return '';
    final content = candidates.first['content'] as Map<String, dynamic>? ?? const {};
    final parts = content['parts'] as List? ?? [];
    if (parts.isEmpty) return '';
    return parts.first['text'] as String? ?? '';
  }

  String _buildInvoiceExtractionPrompt({List<Map<String, dynamic>>? products}) {
    final productsJson = products != null && products.isNotEmpty
        ? jsonEncode(products)
        : '[]';
    
    return '''أنت محاسب ذكي خبير في تحليل الفواتير التجارية العراقية. تعمل كإنسان يقرأ الفاتورة ويبحث عن المنتجات في قاعدة البيانات.

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

### sale_unit (وحدة البيع من الفاتورة):
- استخرج الوحدة من عمود "الوحدة" في الفاتورة
- أمثلة: "كرتون"، "باكيت"، "لفة"، "كيس"، "قطعة"، "متر"
- إذا كانت الوحدة "كارتون" في الفاتورة → sale_unit: "كرتون" (تصحيح التاء المربوطة)
- إذا كانت الوحدة "باكت" في الفاتورة → sale_unit: "باكيت" (تصحيح التاء المربوطة)

## شرح أعمدة جدول المراجعة في التطبيق:

### الأعمدة التي سيتم عرضها للمستخدم:
1. **المنتج**: اسم المنتج المطابق أو المُنظف
2. **الإجمالي**: المبلغ الإجمالي من الفاتورة
3. **سعر الوحدة**: السعر كما في الفاتورة (سعر اللفة/الكرتون/الباكيت)
4. **التعبئة**: 
   - للمنتجات بالمتر: عدد الأمتار في اللفة (units_count)
   - للمنتجات بالقطعة: عدد القطع في الكرتون/الباكيت إذا وُجد
5. **التكلفة**: سعر الوحدة الأساسية (سعر المتر الواحد أو القطعة الواحدة)
   - يُحسب تلقائياً: السعر ÷ التعبئة
6. **سعر البيع**: التكلفة + نسبة الربح

### مثال عملي:
فاتورة تحتوي على: "كيبل 4×16 Berly 250M" بسعر 2000 دينار للفة

JSON المطلوب:
{
  "name": "كيبل 4×16 Berly 250M",
  "original_name": "كيبل 4*16 Berly 250M مكذول",
  "qty": 1,
  "price": 2000,
  "amount": 2000,
  "unit_type": "meter",
  "units_count": 250,
  "matched_product_id": 720,
  "is_new_product": false,
  "confidence": 0.98
}

العرض في التطبيق:
- المنتج: كيبل 4×16 Berly 250M
- الإجمالي: 2,000
- سعر الوحدة: 2,000
- التعبئة: 250 (متر)
- التكلفة: 8 (2000 ÷ 250)
- سعر البيع: 9.2 (مع ربح 15%)

## تنبيهات:
- أرجع JSON object فقط (ليس مصفوفة!) بدون أي نص إضافي
- اقرأ الأرقام بدقة (الكمية، السعر، المبلغ)
- إذا السعر غير واضح: احسبه من المبلغ ÷ الكمية
- استخرج العملة من الفاتورة (IQD أو USD أو \$)
- **لا تنسَ استخراج عدد الأمتار من اسم المنتج!**''';
  }


  Future<Map<String, dynamic>> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType,
    List<Map<String, dynamic>>? products,
  }) async {
    final base64Data = base64Encode(fileBytes);

    final prompt = extractType == 'invoice'
        ? _buildInvoiceExtractionPrompt(products: products)
        : 'حلل هذا السند وأعد JSON فقط بالمفاتيح: {"receipt_date":"YYYY-MM-DD","receipt_number":"","amount":0,"payment_method":"نقد","currency":"IQD","notes":""}. لا تُدرج أي نص آخر غير JSON.';

    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': fileMimeType,
                'data': base64Data,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'response_mime_type': 'application/json'
      }
    };

    // ✅ استخدام الفحص المتوازي للمفاتيح
    final response = await _postWithParallelCheck(body: requestBody);

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return {};
    
    final content = candidates.first['content'] as Map<String, dynamic>? ?? const {};
    final parts = content['parts'] as List? ?? [];
    if (parts.isEmpty) return {};
    
    final text = parts.first['text'] as String? ?? '{}';
    
    print('📄 Gemini Raw Response:');
    print(text);
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    try {
      final parsed = jsonDecode(text);
      
      // Gemini قد يرجع مصفوفة بدلاً من كائن - نأخذ العنصر الأول
      Map<String, dynamic> extracted;
      if (parsed is List) {
        if (parsed.isEmpty) return {};
        extracted = Map<String, dynamic>.from(parsed.first as Map);
        print('📦 Gemini أرجع مصفوفة - تم أخذ العنصر الأول');
      } else if (parsed is Map) {
        extracted = Map<String, dynamic>.from(parsed);
      } else {
        print('⚠️ نوع غير متوقع من Gemini: ${parsed.runtimeType}');
        return {'raw': text};
      }
      
      if (extractType == 'invoice') {
        final items = extracted['line_items'] ?? extracted['items'] ?? [];
        print('📦 عدد العناصر المستخرجة: ${items is List ? items.length : 0}');
      }
      return extracted;
    } catch (e) {
      print('⚠️ فشل تحليل JSON من Gemini: $e');
      return {'raw': text};
    }
  }
}

/// ✅ نتيجة فحص مفتاح واحد (للفحص المتوازي)
class _KeyResult {
  final int keyIndex;
  final http.Response? response;
  final bool success;
  final String? error;

  _KeyResult({
    required this.keyIndex,
    this.response,
    required this.success,
    this.error,
  });
}
