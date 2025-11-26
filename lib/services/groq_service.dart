// services/groq_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class GroqService {
  GroqService({required this.apiKey});

  final String apiKey;

  static const String _endpoint = 'https://api.groq.com/openai/v1/chat/completions';

  // تنفيذ الطلب مع محاولات إعادة المحاولة
  Future<http.Response> _postWithRetry({
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(_endpoint);
    const int maxAttempts = 3;
    int attempt = 0;
    
    while (true) {
      attempt += 1;
      try {
        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));

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

      // تراجع أسي
      final delayMs = (math.pow(2, attempt) as num).toInt() * 400;
      final jitter = math.Random().nextInt(250);
      await Future.delayed(Duration(milliseconds: delayMs + jitter));
    }
  }

  Future<Map<String, dynamic>> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType, // 'invoice' | 'receipt'
  }) async {
    // Groq يدعم llama-3.2-90b-vision-preview للصور
    // لكن يجب تحويل الصورة إلى base64 وإرسالها كـ image_url
    
    final base64Data = base64Encode(fileBytes);
    final dataUrl = 'data:$fileMimeType;base64,$base64Data';

    final prompt = extractType == 'invoice'
        ? '''حلل الفاتورة وأعد JSON فقط دون أي نص زائد. استخدم البنية التالية:
{
  "invoice_date": "YYYY-MM-DD",
  "invoice_number": "",
  "currency": "IQD",
  "line_items": [
    {
      "name": "",
      "qty": 0,
      "price": 0,
      "amount": 0
    }
  ],
  "totals": {
    "subtotal": 0,
    "tax": 0,
    "discount": 0,
    "grand_total": 0
  },
  "amount_paid": 0,
  "remaining": 0,
  "status": "آجل",
  "explanation": ""
}

قواعد مهمة:
1) اعثر على المدفوع من صيغ مثل: المبلغ المسدد، المبلغ المدفوع، Paid, Amount Paid, Received
2) إن لم يُذكر المدفوع ولكن يوجد: المتبقي/باقي/الدين المتبقي/Balance Due/Remaining/Due؛ فاحسب amount_paid = grand_total - remaining
3) إن ذُكر كلاهما وتعارضا، اعتبر النص الأوضح واذكر سببك في explanation
4) حدّد status: "نقد" إن remaining<=0، وإلا "دين"
5) احرص أن تكون line_items أرقامها رقمية
6) أرجع JSON فقط بدون أي نص إضافي'''
        : '''حلل هذا السند وأعد JSON فقط بالمفاتيح التالية:
{
  "receipt_date": "YYYY-MM-DD",
  "receipt_number": "",
  "amount": 0,
  "payment_method": "نقد",
  "currency": "IQD",
  "notes": ""
}

لا تُدرج أي نص آخر غير JSON.''';

    final requestBody = {
      'model': 'llama-3.2-11b-vision-preview',
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text': prompt,
            },
            {
              'type': 'image_url',
              'image_url': {
                'url': dataUrl,
              },
            },
          ],
        },
      ],
      'temperature': 0.1,
      'max_tokens': 2000,
      'response_format': {'type': 'json_object'},
    };

    final response = await _postWithRetry(body: requestBody);

    if (response.statusCode != 200) {
      throw HttpException('Groq error: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      return {};
    }
    
    final message = choices.first['message'] as Map<String, dynamic>?;
    if (message == null) return {};
    
    final content = message['content'] as String? ?? '{}';
    
    try {
      final extracted = jsonDecode(content) as Map<String, dynamic>;
      return extracted;
    } catch (_) {
      return {'raw': content};
    }
  }
}
