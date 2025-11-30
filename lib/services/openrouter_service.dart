// services/openrouter_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// خدمة OpenRouter - مجمّع أفضل النماذج المجانية!
/// 
/// المميزات:
/// - وصول لأفضل النماذج المجانية (Qwen, Llama, وغيرها)
/// - مجاني 100% مع النماذج المنتهية بـ :free
/// - سريع وموثوق
/// - API متوافق مع OpenAI
/// - ممتاز للدردشة والتحليل
class OpenRouterService {
  final String apiKey;
  
  static const String _endpoint = 'https://openrouter.ai/api/v1/chat/completions';
  
  // أفضل النماذج المجانية (مرتبة حسب الأفضلية)
  // تم اختيارها بعناية للدردشة والتحليل المحاسبي
  
  // الأولوية الأولى: Qwen 2.5 Coder 32B - الأفضل للمنطق والتحليل
  static const String _primaryModel = 'qwen/qwen-2.5-coder-32b-instruct:free';
  
  // الأولوية الثانية: Llama 3.2 11B Vision - سريع وممتاز
  static const String _secondaryModel = 'meta-llama/llama-3.2-11b-vision-instruct:free';
  
  // الأولوية الثالثة: Qwen 2.5 7B - خفيف وسريع
  static const String _tertiaryModel = 'qwen/qwen-2.5-7b-instruct:free';
  
  OpenRouterService({required this.apiKey});
  
  /// إرسال رسالة عادية للدردشة
  Future<String> sendMessage(
    String message, {
    List<String>? conversationHistory,
    double temperature = 0.7,
    int maxTokens = 2048,
  }) async {
    print('🌐 OpenRouter: إرسال رسالة...');
    
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
    
    // محاولة النماذج بالترتيب
    final models = [_primaryModel, _secondaryModel, _tertiaryModel];
    
    for (var model in models) {
      try {
        print('🌐 OpenRouter: محاولة $model...');
        
        final response = await http.post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
            // Headers مهمة للنسخ المجانية
            'HTTP-Referer': 'https://flutter-debt-book.app',
            'X-Title': 'Debt Book - Flutter App',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': temperature,
            'max_tokens': maxTokens,
          }),
        ).timeout(const Duration(seconds: 45));
        
        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded['choices'] != null && decoded['choices'].isNotEmpty) {
            final content = decoded['choices'][0]['message']['content'] as String;
            print('✅ OpenRouter: نجح مع $model');
            return content.trim();
          }
        } else {
          print('⚠️ OpenRouter ($model): خطأ ${response.statusCode}');
        }
      } catch (e) {
        print('⚠️ OpenRouter ($model): فشل - $e');
      }
    }
    
    throw Exception('جميع نماذج OpenRouter مشغولة حالياً');
  }
  
  /// تحليل البيانات المحاسبية
  Future<String> analyzeDatabaseData({
    required String systemContext,
    required String userQuery,
    required String dataJson,
  }) async {
    print('🌐 OpenRouter: تحليل بيانات محاسبية...');
    
    final prompt = '''$systemContext

السؤال: $userQuery

البيانات (JSON):
$dataJson

قدم تحليل مفصل ودقيق بالعربية.''';
    
    return await sendMessage(
      prompt,
      temperature: 0.1, // دقة عالية للتحليل المحاسبي
      maxTokens: 3000,  // مساحة كبيرة للتقارير
    );
  }
  
  /// تحليل أخطاء الفواتير بذكاء
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
  
  /// تحليل بيانات عميل محدد
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
  
  /// الحصول على معلومات النماذج المتاحة
  Future<List<String>> getAvailableModels() async {
    return [
      _primaryModel,
      _secondaryModel,
      _tertiaryModel,
    ];
  }
}
