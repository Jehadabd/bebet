// services/sambanova_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// خدمة SambaNova - أقوى منصة مجانية حالياً!
/// 
/// المميزات:
/// - 200k-500k توكن شهرياً مجاناً
/// - نموذج Llama 3.1 405B (أقوى من GPT-4!)
/// - سريع جداً
/// - API متوافق مع OpenAI
/// - ممتاز للتحليل المحاسبي والمالي
class SambaNovaService {
  final String apiKey;
  
  // Endpoint الرسمي من SambaNova
  static const String _endpoint = 'https://api.sambanova.ai/v1/chat/completions';
  
  // النماذج المتاحة (اختر الأنسب لك)
  // ملاحظة: 405B لم يعد متاحاً (410)، نستخدم 70B بدلاً منه
  static const String _model70B = 'Meta-Llama-3.1-70B-Instruct';   // الأقوى المتاح
  static const String _model8B = 'Meta-Llama-3.1-8B-Instruct';     // الأسرع
  
  // النموذج الافتراضي (70B بدلاً من 405B)
  String _currentModel = _model70B;
  
  SambaNovaService({required this.apiKey});
  
  /// تغيير النموذج المستخدم
  void setModel(String model) {
    _currentModel = model;
  }
  
  /// تنفيذ الطلب مع محاولات إعادة المحاولة
  Future<http.Response> _postWithRetry({
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(_endpoint);
    const int maxAttempts = 3;
    int attempt = 0;
    
    while (true) {
      attempt++;
      
      try {
        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 60)); // SambaNova سريع جداً
        
        // أخطاء قابلة لإعادة المحاولة
        if (response.statusCode == 429 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504) {
          if (attempt >= maxAttempts) return response;
        } else {
          return response;
        }
      } on TimeoutException catch (_) {
        if (attempt >= maxAttempts) rethrow;
      } on SocketException catch (_) {
        if (attempt >= maxAttempts) rethrow;
      }
      
      // تراجع أسي مع jitter
      final delayMs = (math.pow(2, attempt) as num).toInt() * 400;
      final jitter = math.Random().nextInt(250);
      await Future.delayed(Duration(milliseconds: delayMs + jitter));
    }
  }
  
  /// إرسال رسالة نصية عادية
  Future<String> sendMessage(
    String message, {
    List<String>? conversationHistory,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    print('🚀 SambaNova: إرسال رسالة...');
    
    // بناء المحادثة
    final messages = <Map<String, dynamic>>[];
    
    // إضافة السياق من المحادثة السابقة
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      for (var i = 0; i < conversationHistory.length; i++) {
        messages.add({
          'role': i % 2 == 0 ? 'user' : 'assistant',
          'content': conversationHistory[i],
        });
      }
    }
    
    // إضافة الرسالة الحالية
    messages.add({
      'role': 'user',
      'content': message,
    });
    
    final requestBody = {
      'model': _currentModel,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'top_p': 0.9,
      'stream': false,
    };
    
    try {
      final response = await _postWithRetry(body: requestBody);
      
      if (response.statusCode != 200) {
        print('❌ SambaNova: خطأ ${response.statusCode}');
        throw HttpException('SambaNova error: ${response.statusCode} ${response.body}');
      }
      
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final content = decoded['choices'][0]['message']['content'] as String;
      
      print('✅ SambaNova: تم الرد بنجاح');
      return content.trim();
      
    } catch (e) {
      print('❌ خطأ في خدمة SambaNova: $e');
      rethrow;
    }
  }
  
  /// تحليل البيانات المحاسبية (متخصص)
  Future<String> analyzeDatabaseData({
    required String systemContext,
    required String userQuery,
    required String dataJson,
  }) async {
    print('🚀 SambaNova: تحليل بيانات محاسبية...');
    
    final prompt = '''$systemContext

السؤال: $userQuery

البيانات (JSON):
$dataJson

قدم تحليل مفصل ودقيق بالعربية.''';
    
    return await sendMessage(
      prompt,
      temperature: 0.1, // دقة عالية للتحليل المحاسبي
      maxTokens: 4096,  // مساحة كبيرة للتقارير المفصلة
    );
  }
  
  /// كشف الأخطاء المحاسبية
  Future<String> detectAccountingAnomalies({
    required Map<String, dynamic> financialData,
  }) async {
    final dataJson = jsonEncode(financialData);
    
    return await analyzeDatabaseData(
      systemContext: '''أنت مدقق مالي خبير ومحاسب محترف متخصص في:
- كشف الأخطاء المحاسبية
- تحليل التناقضات في الأرصدة
- اكتشاف الديون المتأخرة
- التحقق من صحة الحسابات الرياضية
- تقديم توصيات واضحة للإصلاح

يجب أن تكون إجاباتك:
✓ دقيقة رياضياً
✓ واضحة ومنظمة
✓ بالعربية الفصحى
✓ مع أمثلة عملية''',
      userQuery: 'قم بتحليل هذه البيانات المالية وكشف أي أخطاء أو مخاطر محتملة',
      dataJson: dataJson,
    );
  }
  
  /// تحليل دقة الأرباح
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
5. تقديم تقرير مفصل عن أي مشاكل

استخدم تحليل رياضي دقيق وقدم أمثلة واضحة.''',
      userQuery: 'تحقق من دقة حسابات الأرباح وكشف أي أخطاء في الأسعار أو التكلفة',
      dataJson: dataJson,
    );
  }
  
  /// تحليل أخطاء الفواتير بذكاء عالي
  Future<String> analyzeInvoiceErrors({
    required Map<String, dynamic> errorsData,
  }) async {
    final dataJson = jsonEncode(errorsData);
    
    return await analyzeDatabaseData(
      systemContext: '''أنت محاسب خبير ومدقق مالي محترف.
تم اكتشاف أخطاء محاسبية في الفواتير.

مهمتك تحليل كل خطأ وتقديم:
1. تفسير واضح لكل خطأ
2. السبب المحتمل للخطأ
3. التأثير المالي (بالأرقام)
4. الحل المقترح (خطوات عملية)
5. الأولوية (عالية/متوسطة/منخفضة)

يجب أن يكون تقريرك:
✓ مفصل ومنظم
✓ دقيق رياضياً
✓ عملي وقابل للتطبيق
✓ بالعربية الفصحى''',
      userQuery: 'قم بتحليل هذه الأخطاء المحاسبية وقدم تقرير مفصل مع توصيات للإصلاح',
      dataJson: dataJson,
    );
  }
  
  /// البحث والتحليل الشامل لعميل
  Future<String> analyzeCustomerData({
    required Map<String, dynamic> customerData,
  }) async {
    final dataJson = jsonEncode(customerData);
    
    return await analyzeDatabaseData(
      systemContext: '''أنت محلل مالي متخصص في تحليل بيانات العملاء.
قدم تحليل شامل يتضمن:
- الملخص المالي
- تقييم الأداء
- المخاطر المحتملة
- التوصيات
- التوقعات المستقبلية

استخدم لغة واضحة ومهنية.''',
      userQuery: 'قم بتحليل شامل لبيانات هذا العميل وقدم تقرير مفصل',
      dataJson: dataJson,
    );
  }
  
  /// الحصول على معلومات الاستخدام (Usage)
  Future<Map<String, dynamic>?> getUsageInfo() async {
    // SambaNova لا يوفر endpoint لمعلومات الاستخدام حالياً
    // لكن يمكنك تتبعه محلياً
    return null;
  }
}
