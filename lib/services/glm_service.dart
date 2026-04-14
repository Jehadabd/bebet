// services/glm_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// خدمة GLM (智谱AI) - مجانية غير محدودة!
/// أفضل النماذج: GLM-4.6V (Vision), GLM-4V-Plus
class GlmService {
  GlmService({required this.apiKey});

  final String apiKey;

  // النماذج المتاحة - من الموقع الرسمي
  static const String visionModel = 'glm-4v';  // مجاني - 10 concurrent
  static const String visionModelPlus = 'glm-4v-plus';  // أفضل جودة
  static const String textModel = 'glm-4-flash';  // للنصوص فقط

  /// استخراج بيانات الفاتورة من الصورة
  Future<Map<String, dynamic>> extractInvoiceFromImage({
    required Uint8List imageBytes,
    required String mimeType,
    required List<Map<String, dynamic>> products,
  }) async {
    print('\n🚀 GLM: بدء استخراج بيانات الفاتورة...');
    print('📷 حجم الصورة: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');

    final base64Image = base64Encode(imageBytes);
    final dataUrl = 'data:$mimeType;base64,$base64Image';

    final prompt = _buildInvoiceExtractionPrompt(products);

    // قائمة النماذج للتجربة بالترتيب - GLM-4.6V أولاً (الأفضل والمجاني)
    final models = [
      'GLM-4.6V',        // ⭐ الأفضل - مجاني 10 concurrent
      'glm-4.6v',        // نفسه بأحرف صغيرة
      'glm-4v',          // الإصدار القديم
      'glm-4v-plus',     // Plus
    ];

    for (final model in models) {
      try {
        print('🔑 GLM: تجربة النموذج $model...');

        final requestBody = {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': dataUrl}
                },
                {
                  'type': 'text',
                  'text': prompt
                }
              ]
            }
          ],
          'max_tokens': 4096,
          'temperature': 0.1,
        };

        final response = await http.post(
          Uri.parse('https://open.bigmodel.cn/api/paas/v4/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 120));

        print('📡 GLM: Status ${response.statusCode}');

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final content = decoded['choices']?[0]?['message']?['content'] as String?;

          if (content != null && content.isNotEmpty) {
            print('✅ GLM ($model): تم استلام الرد (${content.length} حرف)');
            print('📄 الرد: ${content.substring(0, content.length > 500 ? 500 : content.length)}...');
            return _parseJsonFromResponse(content);
          }
        } else {
          print('⚠️ GLM: النموذج $model غير متاح (${response.statusCode})');
          print('📄 Response: ${response.body}');
        }
      } catch (e) {
        print('⚠️ GLM: فشل مع النموذج $model: $e');
        continue;
      }
    }

    throw Exception('GLM: فشلت جميع النماذج');
  }

  /// بناء برومبت استخراج الفاتورة
  String _buildInvoiceExtractionPrompt(List<Map<String, dynamic>> products) {
    final productsList = products.map((p) {
      return '- ${p['name']} (الباركود: ${p['barcode'] ?? 'غير محدد'})';
    }).join('\n');

    return '''
أنت خبير في استخراج البيانات من الفواتير. قم بتحليل هذه الفاتورة واستخراج البيانات التالية بتنسيق JSON:

**قائمة المنتجات المتوفرة في النظام:**
$productsList

**المطلوب:**
استخرج البيانات وأرجعها بهذا التنسيق JSON فقط (بدون نص إضافي):
{
  "supplier_name": "اسم المورد",
  "supplier_phone": "رقم الهاتف",
  "invoice_date": "YYYY-MM-DD",
  "invoice_number": "رقم الفاتورة",
  "total_amount": 0.0,
  "items": [
    {
      "product_name": "اسم المنتج",
      "quantity": 1,
      "unit_price": 0.0,
      "total_price": 0.0,
      "matched_product_barcode": "الباركود إذا وجد تطابق",
      "confidence": 0.95
    }
  ]
}

**تعليمات مهمة:**
1. قارن المنتجات في الفاتورة مع قائمة المنتجات المتوفرة
2. إذا وجدت تطابق (تشابه في الاسم)، ضع الباركود في matched_product_barcode
3. confidence = نسبة التأكد من التطابق (0-1)
4. أرجع JSON فقط بدون أي نص إضافي
5. الأرقام يجب أن تكون أرقام حقيقية من الفاتورة

الآن قم بتحليل الفاتورة وأرجع JSON:
''';
  }

  /// استخراج JSON من الرد
  Map<String, dynamic> _parseJsonFromResponse(String response) {
    try {
      // البحث عن JSON في الرد
      final jsonMatch = RegExp(r'\{[\s\S]*\}', multiLine: true).firstMatch(response);
      
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        return decoded;
      }
      
      throw Exception('لم يتم العثور على JSON في الرد');
    } catch (e) {
      print('❌ خطأ في تحليل JSON: $e');
      return {
        'error': 'فشل تحليل الرد',
        'raw_response': response,
      };
    }
  }

  /// اختبار الاتصال
  Future<bool> testConnection() async {
    try {
      print('🔑 اختبار اتصال GLM...');
      
      final response = await http.post(
        Uri.parse('https://open.bigmodel.cn/api/paas/v4/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'glm-4-flash',
          'messages': [
            {'role': 'user', 'content': 'مرحبا'}
          ],
          'max_tokens': 10,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        print('✅ اتصال GLM ناجح!');
        return true;
      }
      
      print('❌ فشل الاتصال: ${response.statusCode}');
      return false;
    } catch (e) {
      print('❌ خطأ في الاتصال: $e');
      return false;
    }
  }
}
