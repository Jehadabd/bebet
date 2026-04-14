// services/mistral_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// خدمة Mistral (Pixtral) - مجاني سخي!
/// يتجدد شهرياً - 1 طلب/ثانية = ~86,400 طلب/يوم
class MistralService {
  MistralService({required this.apiKey});

  final String apiKey;

  // النماذج المتاحة
  static const String visionModel = 'pixtral-12b-2409';  // مجاني - Vision
  static const String textModel = 'mistral-small-latest';  // للنصوص

  /// استخراج بيانات الفاتورة من الصورة
  Future<Map<String, dynamic>> extractInvoiceFromImage({
    required Uint8List imageBytes,
    required String mimeType,
    required List<Map<String, dynamic>> products,
  }) async {
    print('\n🚀 Mistral Pixtral: بدء استخراج بيانات الفاتورة...');
    print('📷 حجم الصورة: ${(imageBytes.length / 1024).toStringAsFixed(1)} KB');

    final base64Image = base64Encode(imageBytes);
    final dataUrl = 'data:$mimeType;base64,$base64Image';

    final prompt = _buildInvoiceExtractionPrompt(products);

    final requestBody = {
      'model': visionModel,
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

    try {
      print('🔑 Mistral: إرسال الطلب إلى $visionModel...');
      
      final response = await http.post(
        Uri.parse('https://api.mistral.ai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 120));

      print('📡 Mistral: Status ${response.statusCode}');

      if (response.statusCode != 200) {
        print('❌ Mistral خطأ: ${response.statusCode}');
        print('📄 Response: ${response.body}');
        throw Exception('Mistral error: ${response.statusCode} - ${response.body}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final content = decoded['choices']?[0]?['message']?['content'] as String?;

      if (content == null || content.isEmpty) {
        throw Exception('Mistral: لم يتم استخراج محتوى');
      }

      print('✅ Mistral: تم استلام الرد (${content.length} حرف)');
      print('📄 الرد: ${content.substring(0, content.length > 500 ? 500 : content.length)}...');

      // استخراج JSON من الرد
      return _parseJsonFromResponse(content);
    } catch (e) {
      print('❌ Mistral فشل: $e');
      rethrow;
    }
  }

  /// بناء برومبت استخراج الفاتورة
  String _buildInvoiceExtractionPrompt(List<Map<String, dynamic>> products) {
    final productsList = products.map((p) {
      return '- ${p['name']} (الباركود: ${p['barcode'] ?? 'غير محدد'})';
    }).join('\n');

    return '''
أنت خبير في استخراج البيانات من الفواتير العربية والعراقية. قم بتحليل هذه الفاتورة واستخراج البيانات التالية بتنسيق JSON:

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
6. العملة العراقية (دينار) - الأرقام قد تكون كبيرة

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
      print('🔑 اختبار اتصال Mistral...');
      
      final response = await http.post(
        Uri.parse('https://api.mistral.ai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'mistral-small-latest',
          'messages': [
            {'role': 'user', 'content': 'مرحبا'}
          ],
          'max_tokens': 10,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        print('✅ اتصال Mistral ناجح!');
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
