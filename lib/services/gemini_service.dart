// services/gemini_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// خدمة Gemini مع دعم 3 مفاتيح API للتبديل التلقائي
class GeminiService {
  GeminiService({
    required this.apiKey,
    this.apiKey2,
    this.apiKey3,
  }) {
    // بناء قائمة المفاتيح المتاحة
    _apiKeys = [apiKey];
    if (apiKey2 != null && apiKey2!.isNotEmpty) _apiKeys.add(apiKey2!);
    if (apiKey3 != null && apiKey3!.isNotEmpty) _apiKeys.add(apiKey3!);
    print('🔑 Gemini: تم تحميل ${_apiKeys.length} مفتاح/مفاتيح API');
  }

  final String apiKey;
  final String? apiKey2;
  final String? apiKey3;
  
  // قائمة المفاتيح المتاحة
  late final List<String> _apiKeys;
  
  // فهرس المفتاح الحالي
  int _currentKeyIndex = 0;
  
  String get _currentApiKey => _apiKeys[_currentKeyIndex];
  
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

  /// تنفيذ الطلب مع التبديل التلقائي بين المفاتيح
  Future<http.Response> _postWithRetry({
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(_endpoint);
    const int maxAttemptsPerKey = 2;
    
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
              .timeout(const Duration(seconds: 30));

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
            if (!_switchToNextKey()) rethrow;
            attempt = 0;
          }
        } on SocketException catch (_) {
          print('🌐 Gemini: خطأ في الاتصال');
          if (attempt >= maxAttemptsPerKey) {
            if (!_switchToNextKey()) rethrow;
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

    final response = await _postWithRetry(body: requestBody);

    if (response.statusCode != 200) {
      print('❌ Gemini: خطأ ${response.statusCode}');
      throw HttpException('Gemini error: ${response.statusCode} ${response.body}');
    }

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

    final response = await _postWithRetry(body: requestBody);

    if (response.statusCode != 200) {
      throw HttpException('Gemini error: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return '';
    final content = candidates.first['content'] as Map<String, dynamic>? ?? const {};
    final parts = content['parts'] as List? ?? [];
    if (parts.isEmpty) return '';
    return parts.first['text'] as String? ?? '';
  }

  String _buildInvoiceExtractionPrompt() {
    return '''أنت خبير في تحليل الفواتير التجارية العراقية. حلل الفاتورة واستخرج البيانات بدقة عالية.

## معرفة السوق العراقي:
- لفة/بكرة (Roll): عادة تعني طول بالأمتار (مثل 80م، 100م)
- تعبئة: عدد القطع داخل الكرتون/العلبة
- درزن: يعني 12 قطعة بالضبط
- شدة: مجموعة من العناصر، ابحث عن الرقم المرتبط

## خوارزمية التحليل:
1. افحص اسم المنتج للكلمات المفتاحية (M، م، متر، تعبئة، شدة، لفة، درزن)
2. إذا وجدت رقم قبل/بعد وحدة الطول (مثل "80م")، هذا هو unit_length
3. إذا وجدت "تعبئة" أو "درزن"، استخرج pack_size
4. احسب: price_per_meter = price / unit_length أو price_per_piece = price / pack_size

## البنية المطلوبة (JSON فقط):
{
  "invoice_date": "YYYY-MM-DD",
  "invoice_number": "",
  "currency": "IQD",
  "line_items": [
    {
      "name": "الاسم الأصلي من الفاتورة",
      "qty": 0,
      "price": 0,
      "amount": 0,
      "analysis": {
        "category": "cable|accessory|switchgear|other",
        "unit_type": "meter|piece|pack|roll|dozen|bundle|none",
        "unit_value": 0,
        "calculated_unit_price": 0,
        "unit_label": "سعر المتر|سعر القطعة|سعر الوحدة",
        "reasoning": "شرح قصير بالعربي"
      }
    }
  ],
  "totals": {"subtotal": 0, "tax": 0, "discount": 0, "grand_total": 0},
  "amount_paid": 0,
  "remaining": 0,
  "status": "نقد|دين",
  "explanation": ""
}

## قواعد مهمة:
1. اعثر على المدفوع من: المبلغ المسدد، المبلغ المدفوع، Paid, Amount Paid, Received
2. إن لم يُذكر المدفوع لكن يوجد المتبقي: amount_paid = grand_total - remaining
3. status = "نقد" إذا remaining <= 0، وإلا "دين"
4. جميع الأرقام يجب أن تكون رقمية (ليست نصية)
5. أرجع JSON فقط بدون أي نص إضافي''';
  }


  Future<Map<String, dynamic>> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType,
  }) async {
    final base64Data = base64Encode(fileBytes);

    final prompt = extractType == 'invoice'
        ? _buildInvoiceExtractionPrompt()
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

    final response = await _postWithRetry(body: requestBody);

    if (response.statusCode != 200) {
      throw HttpException('Gemini error: ${response.statusCode} ${response.body}');
    }

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
      final extracted = jsonDecode(text) as Map<String, dynamic>;
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
