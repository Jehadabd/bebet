// services/gemini_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

class GeminiService {
  GeminiService({required this.apiKey});

  final String apiKey;

  static const String _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  // تنفيذ الطلب مع محاولات إعادة المحاولة والتراجع الأسي عند أخطاء التحميل/الازدحام
  Future<http.Response> _postWithRetry({
    required Map<String, dynamic> body,
  }) async {
    final uri = Uri.parse(_endpoint);
    const int maxAttempts = 4; // إجمالي المحاولات
    int attempt = 0;
    while (true) {
      attempt += 1;
      try {
        final response = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'X-goog-api-key': apiKey,
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
          if (attempt >= maxAttempts) return response; // أعدها ليتعامل معها النداء الأعلى
        } else {
          return response; // نجاح أو خطأ غير قابل لإعادة المحاولة
        }
      } on TimeoutException catch (_) {
        if (attempt >= maxAttempts) rethrow;
      } on SocketException catch (_) {
        if (attempt >= maxAttempts) rethrow;
      }

      // تراجع أسي مع عشوائية بسيطة
      final delayMs = (math.pow(2, attempt) as num).toInt() * 400;
      final jitter = math.Random().nextInt(250);
      await Future.delayed(Duration(milliseconds: delayMs + jitter));
    }
  }

  Future<String> extractTextFromPrompt(String prompt) async {
    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
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
    if (candidates == null || candidates.isEmpty) {
      return '';
    }
    final content = candidates.first['content'] as Map<String, dynamic>?
        ?? const {};
    final parts = content['parts'] as List? ?? [];
    if (parts.isEmpty) return '';
    final text = parts.first['text'] as String? ?? '';
    return text;
  }

  Future<Map<String, dynamic>> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType, // 'invoice' | 'receipt'
  }) async {
    // Base64 encode file for inline content
    final base64Data = base64Encode(fileBytes);

    final prompt = extractType == 'invoice'
        ? 'حلل الفاتورة وأعد JSON فقط دون أي نص زائد. استخدم البنية: {"invoice_date":"YYYY-MM-DD","invoice_number":"","currency":"IQD","line_items":[{"name":"","qty":0,"price":0,"amount":0}],"totals":{"subtotal":0,"tax":0,"discount":0,"grand_total":0},"amount_paid":0,"remaining":0,"status":"آجل","explanation":""}. قواعد مهمة: 1) اعثر على المدفوع من صيغ مثل: المبلغ المسدد، المبلغ المدفوع، Paid, Amount Paid, Received. 2) إن لم يُذكر المدفوع ولكن يوجد: المتبقي/باقي/الدين المتبقي/Balance Due/Remaining/Due؛ فاحسب amount_paid = grand_total - remaining. 3) إن ذُكر كلاهما وتعارضا، اعتبر النص الأوضح واذكر سببك في explanation (جملة قصيرة). 4) حدّد status: "نقد" إن remaining<=0، وإلا "دين". 5) احرص أن تكون line_items أرقامها رقمية. 6) أرجع JSON فقط.'
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
    if (candidates == null || candidates.isEmpty) {
      return {};
    }
    final content = candidates.first['content'] as Map<String, dynamic>?
        ?? const {};
    final parts = content['parts'] as List? ?? [];
    if (parts.isEmpty) return {};
    final text = parts.first['text'] as String? ?? '{}';
    try {
      final extracted = jsonDecode(text) as Map<String, dynamic>;
      return extracted;
    } catch (_) {
      return {'raw': text};
    }
  }
}


