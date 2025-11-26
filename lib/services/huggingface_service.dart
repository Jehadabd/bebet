// services/huggingface_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class HuggingFaceService {
  HuggingFaceService({required this.apiKey});

  final String apiKey;

  // استخدام Qwen2-VL - نموذج قوي جداً في تحليل الصور
  static const String _model = 'Qwen/Qwen2-VL-7B-Instruct';
  // إضافة wait_for_model=true لتجنب مشاكل الاتصال
  static const String _endpoint = 'https://api-inference.huggingface.co/models/$_model?wait_for_model=true';

  /// استخراج بيانات الفاتورة أو السند من الصورة
  Future<Map<String, dynamic>> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType, // 'invoice' | 'receipt'
  }) async {
    print('🟠 استخدام Hugging Face (Qwen2-VL)...');

    // تحويل الصورة إلى base64
    final base64Image = base64Encode(fileBytes);
    final imageDataUrl = 'data:$fileMimeType;base64,$base64Image';

    // بناء الـ prompt حسب نوع الاستخراج
    final String prompt = extractType == 'invoice'
        ? _buildInvoicePrompt()
        : _buildReceiptPrompt();

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
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
