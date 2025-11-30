// services/huggingface_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// خدمة Hugging Face مع نموذج Qwen 2.5 - الوحش الكاسر في المنطق الرياضي والمحاسبي
/// 
/// نموذج Qwen 2.5 72B Instruct (من Alibaba) يتفوق على Llama 3 في:
/// - المنطق الرياضي والمحاسبي
/// - البرمجة وقراءة ملفات JSON
/// - دعم اللغة العربية بشكل ممتاز
/// 
/// الاستخدام الموصى به:
/// - Groq: لتحليل صور الفواتير بسرعة البرق
/// - Qwen (Hugging Face): للتفكير العميق، التدقيق المحاسبي، والإجابة على الأسئلة المعقدة
class HuggingFaceService {
  final String apiKey;
  
  // نموذج Qwen2-VL للصور
  static const String _visionModel = 'Qwen/Qwen2-VL-7B-Instruct';
  // ⚠️ تحديث: Hugging Face غيّر الـ endpoint من api-inference إلى router
  static const String _visionEndpoint = 'https://router.huggingface.co/models/$_visionModel?wait_for_model=true';
  
  // نموذج Qwen 2.5 72B للتحليل النصي والبيانات - الأقوى في المنطق الرياضي
  static const String _textModel = 'Qwen/Qwen2.5-72B-Instruct';
  // ⚠️ تحديث: Hugging Face غيّر الـ endpoint من api-inference إلى router
  static const String _textEndpoint = 'https://router.huggingface.co/models/$_textModel';
  
  HuggingFaceService({required this.apiKey});
  
  /// تنفيذ الطلب مع آلية إعادة المحاولة (Retry Logic) المحسّنة
  /// مهمة جداً مع Hugging Face لأن السيرفرات المجانية قد تكون مشغولة أحياناً
  /// النماذج الضخمة مثل Qwen 2.5-72B تحتاج وقت تحميل (Cold Boot) من 60-120 ثانية
  Future<http.Response> _postWithRetry({
    required String endpoint,
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(endpoint);
    const int maxAttempts = 3; // مع الانتظار الطويل، لا نحتاج لمحاولات كثيرة
    int attempt = 0;
    
    while (true) {
      attempt++;
      print('⏳ محاولة الاتصال بـ Qwen (المحاولة $attempt)...');
      
      try {
        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
            // هذا الهيدر سحري! يخبر السيرفر: "لا تفصل الخط، أنا سأنتظر تحميل الموديل"
            'x-wait-for-model': 'true',
            'x-use-cache': 'false',
          },
          body: jsonEncode(body),
        ).timeout(
          // ⚠️ نزيد الوقت هنا إلى 5 دقائق (300 ثانية)
          // الموديل قد يستغرق 60-90 ثانية للتحميل فقط
          const Duration(seconds: 300),
        );
        
        // الحالة 503 تعني Model Loading (جاري تحميل الموديل)
        if (response.statusCode == 503) {
          final errorBody = jsonDecode(response.body);
          // أحياناً يعطيك الوقت المقدر للانتظار
          final estimatedTime = errorBody['estimated_time'] as num?;
          
          if (attempt >= maxAttempts) {
            throw HttpException('فشل تحميل الموديل بعد عدة محاولات.');
          }
          
          double waitSeconds = estimatedTime?.toDouble() ?? 20.0;
          print('⚠️ الموديل قيد التحميل. انتظار متوقع: $waitSeconds ثانية...');
          
          // ننتظر المدة المطلوبة + قليل من الوقت الإضافي
          await Future.delayed(Duration(seconds: waitSeconds.toInt()));
          continue; // إعادة المحاولة
        }
        
        if (response.statusCode == 200) {
          return response;
        } else {
          throw HttpException('Status: ${response.statusCode}, Body: ${response.body}');
        }
      } on TimeoutException {
        print('⏰ انتهى وقت الانتظار (Timeout).');
        if (attempt >= maxAttempts) rethrow;
        // إذا حدث timeout، ننتظر قليلاً ثم نحاول مرة أخرى (ربما الموديل أصبح جاهزاً الآن)
        await Future.delayed(const Duration(seconds: 5));
      } catch (e) {
        if (attempt >= maxAttempts) rethrow;
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }
  
  /// إرسال رسالة عادية للنموذج النصي (Qwen 2.5 72B)
  Future<String> sendMessage(String message, {List<String>? conversationHistory}) async {
    // تنسيق ChatML الخاص بـ Qwen للحصول على أفضل أداء
    final prompt = '''<|im_start|>system
أنت مساعد ذكي متخصص في إدارة المتاجر والمحاسبة. يجب أن تجيب باللغة العربية وتكون إجاباتك دقيقة ومفيدة.
<|im_end|>
<|im_start|>user
$message
<|im_end|>
<|im_start|>assistant
''';
    
    final requestBody = {
      'inputs': prompt,
      'parameters': {
        'max_new_tokens': 2048,
        'temperature': 0.7,
        'top_p': 0.9,
        'return_full_text': false,
      }
    };
    
    try {
      final response = await _postWithRetry(
        endpoint: _textEndpoint,
        body: requestBody,
      );
      
      if (response.statusCode != 200) {
        if (response.statusCode == 503) {
          return 'النموذج قيد التحميل، يرجى المحاولة مرة أخرى بعد قليل (عادة 20-30 ثانية)';
        }
        throw HttpException('Hugging Face Error: ${response.statusCode} - ${response.body}');
      }
      
      // تحليل الرد (هيكل الرد يختلف قليلاً عن OpenAI)
      final List<dynamic> decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded.isEmpty) return 'لا توجد إجابة';
      
      String generatedText = decoded[0]['generated_text'] ?? '';
      return generatedText.trim();
      
    } catch (e) {
      print('❌ خطأ في خدمة Qwen (Hugging Face): $e');
      rethrow;
    }
  }
  
  /// دالة خاصة لتحليل البيانات واستخراج المعلومات
  /// ممتازة لتدقيق الحسابات وقراءة الـ JSON
  Future<String> analyzeDatabaseData({
    required String systemContext,
    required String userQuery,
    required String dataJson,
  }) async {
    // تنسيق ChatML الخاص بـ Qwen للحصول على أفضل أداء
    // هذا التنسيق يجعل الموديل يفهم بدقة الفرق بين التعليمات والبيانات
    final prompt = '''<|im_start|>system
$systemContext
أنت مساعد محاسبي خبير ومدقق بيانات. يجب أن تجيب باللغة العربية وتكون إجاباتك دقيقة جداً رياضياً.
<|im_end|>
<|im_start|>user
السؤال: $userQuery

البيانات (JSON):
$dataJson
<|im_end|>
<|im_start|>assistant
''';
    
    final requestBody = {
      'inputs': prompt,
      'parameters': {
        'max_new_tokens': 2048, // مساحة كافية للتقارير الطويلة
        'temperature': 0.1,     // دقة عالية جداً (تقليل الإبداع للأرقام)
        'top_p': 0.9,
        'return_full_text': false, // إرجاع الرد فقط بدون السؤال
      }
    };
    
    try {
      final response = await _postWithRetry(
        endpoint: _textEndpoint,
        body: requestBody,
      );
      
      if (response.statusCode != 200) {
        if (response.statusCode == 503) {
          return 'النموذج قيد التحميل، يرجى المحاولة مرة أخرى بعد قليل (عادة 20-30 ثانية)';
        }
        throw HttpException('Hugging Face Error: ${response.statusCode} - ${response.body}');
      }
      
      // تحليل الرد (Qwen via HF returns a list with generated_text)
      final List<dynamic> decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded.isEmpty) return 'لا توجد إجابة';
      
      String generatedText = decoded[0]['generated_text'] ?? '';
      return generatedText.trim();
      
    } catch (e) {
      print('❌ خطأ في خدمة Qwen (Hugging Face): $e');
      rethrow;
    }
  }
  
  /// دالة متقدمة لكشف الأخطاء المحاسبية
  /// تستخدم قوة Qwen في المنطق الرياضي
  Future<String> detectAccountingAnomalies({
    required Map<String, dynamic> financialData,
  }) async {
    final dataJson = jsonEncode(financialData);
    
    return await analyzeDatabaseData(
      systemContext: '''أنت مدقق مالي خبير متخصص في كشف الأخطاء المحاسبية.
مهمتك:
1. تحليل البيانات المالية بدقة
2. كشف أي تناقضات في الأرصدة
3. اكتشاف الديون التي لم تُحصل منذ فترة طويلة
4. التحقق من صحة الحسابات الرياضية
5. تقديم توصيات واضحة للإصلاح''',
      userQuery: 'قم بتحليل هذه البيانات المالية وكشف أي أخطاء أو مخاطر محتملة',
      dataJson: dataJson,
    );
  }
  
  /// دالة لتحليل الأرباح بدقة عالية
  Future<String> analyzeProfitAccuracy({
    required Map<String, dynamic> profitData,
  }) async {
    final dataJson = jsonEncode(profitData);
    
    return await analyzeDatabaseData(
      systemContext: '''أنت محلل مالي خبير متخصص في حساب الأرباح.
مهمتك:
1. التحقق من دقة حسابات الأرباح
2. مقارنة التكلفة مع المبيعات
3. كشف أي أخطاء في الأسعار (Clash Detection)
4. التأكد من منطقية نسب الربح
5. تقديم تقرير مفصل عن أي مشاكل''',
      userQuery: 'تحقق من دقة حسابات الأرباح وكشف أي أخطاء في الأسعار أو التكلفة',
      dataJson: dataJson,
    );
  }
  
  // ============================================
  // دوال تحليل الصور (Qwen2-VL)
  // ============================================
  
  /// استخراج بيانات الفاتورة أو السند من الصورة
  Future<Map<String, dynamic>> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType, // 'invoice' | 'receipt'
  }) async {
    print('🟠 استخدام Hugging Face (Qwen2-VL) لتحليل الصورة...');

    // تحويل الصورة إلى base64
    final base64Image = base64Encode(fileBytes);
    final imageDataUrl = 'data:$fileMimeType;base64,$base64Image';

    // بناء الـ prompt حسب نوع الاستخراج
    final String prompt = extractType == 'invoice'
        ? _buildInvoicePrompt()
        : _buildReceiptPrompt();

    try {
      final response = await http.post(
        Uri.parse(_visionEndpoint),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'inputs': {
            'image': imageDataUrl,
            'text': prompt,
          },
          'parameters': {
            'max_new_tokens': 2000,
            'temperature': 0.1,
          },
        }),
      ).timeout(const Duration(seconds: 120)); // timeout أطول مع wait_for_model

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        // استخراج النص من الاستجابة
        String extractedText = '';
        if (result is List && result.isNotEmpty) {
          extractedText = result[0]['generated_text'] ?? '';
        } else if (result is Map && result.containsKey('generated_text')) {
          extractedText = result['generated_text'] ?? '';
        }

        // تحليل JSON من النص
        return _parseJsonFromText(extractedText);
      } else if (response.statusCode == 503) {
        // النموذج يتم تحميله - wait_for_model سيتعامل مع هذا
        print('⏳ HuggingFace: النموذج يتم تحميله، الانتظار...');
        throw HttpException('Hugging Face: النموذج يتم تحميله');
      } else {
        throw HttpException('Hugging Face error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('❌ خطأ من Hugging Face: $e');
      rethrow;
    }
  }

  String _buildInvoicePrompt() {
    return '''أنت خبير في استخراج البيانات من الفواتير. قم بتحليل هذه الصورة واستخرج البيانات التالية بصيغة JSON فقط:

{
  "invoice_number": "رقم الفاتورة",
  "invoice_date": "تاريخ الفاتورة بصيغة YYYY-MM-DD",
  "supplier_name": "اسم المورد",
  "total": المبلغ الإجمالي كرقم,
  "currency": "العملة (IQD أو USD)",
  "items": [
    {
      "name": "اسم المنتج",
      "qty": الكمية كرقم,
      "price": السعر كرقم,
      "amount": الإجمالي كرقم
    }
  ]
}

قواعد مهمة:
- أرجع JSON فقط، بدون أي نص إضافي
- إذا لم تجد قيمة، استخدم null
- الأرقام يجب أن تكون أرقام وليس نصوص
- التاريخ بصيغة YYYY-MM-DD''';
  }

  String _buildReceiptPrompt() {
    return '''أنت خبير في استخراج البيانات من سندات القبض. قم بتحليل هذه الصورة واستخرج البيانات التالية بصيغة JSON فقط:

{
  "receipt_number": "رقم السند",
  "receipt_date": "تاريخ السند بصيغة YYYY-MM-DD",
  "amount": المبلغ كرقم,
  "currency": "العملة (IQD أو USD)",
  "payment_method": "طريقة الدفع (نقد/شيك/تحويل)",
  "notes": "ملاحظات إضافية"
}

قواعد مهمة:
- أرجع JSON فقط، بدون أي نص إضافي
- إذا لم تجد قيمة، استخدم null
- الأرقام يجب أن تكون أرقام وليس نصوص
- التاريخ بصيغة YYYY-MM-DD''';
  }

  Map<String, dynamic> _parseJsonFromText(String text) {
    try {
      // محاولة استخراج JSON من النص
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        return jsonDecode(jsonStr);
      }
      
      // إذا لم نجد JSON، نرجع خطأ
      throw FormatException('لم يتم العثور على JSON في الاستجابة');
    } catch (e) {
      print('❌ خطأ في تحليل JSON: $e');
      print('النص المستلم: $text');
      return {};
    }
  }
}
