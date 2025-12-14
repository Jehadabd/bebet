// services/ai_extraction_service.dart
// خدمة استخراج بيانات الفواتير باستخدام Gemini فقط

import 'dart:io';
import 'gemini_service.dart';

/// خدمة استخراج البيانات من الصور باستخدام Gemini
class AIExtractionService {
  AIExtractionService({
    required this.geminiApiKey,
    this.geminiApiKey2,
    this.geminiApiKey3,
  });

  final String geminiApiKey;
  final String? geminiApiKey2;
  final String? geminiApiKey3;

  /// استخراج بيانات الفاتورة أو السند من الصورة
  Future<ExtractionResult> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType,
  }) async {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🤖 استخراج البيانات باستخدام Gemini');
    print('📄 نوع الملف: $fileMimeType');
    print('📋 نوع الاستخراج: $extractType');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    try {
      final geminiService = GeminiService(
        apiKey: geminiApiKey,
        apiKey2: geminiApiKey2,
        apiKey3: geminiApiKey3,
      );

      final result = await geminiService.extractInvoiceOrReceiptStructured(
        fileBytes: fileBytes,
        fileMimeType: fileMimeType,
        extractType: extractType,
      );

      if (result.isNotEmpty && !result.containsKey('error')) {
        final items = result['line_items'] as List? ?? [];
        print('✅ نجح Gemini! تم استخراج ${items.length} بند');
        
        return ExtractionResult(
          data: result,
          source: 'Gemini',
          success: true,
        );
      } else {
        final error = result['error']?.toString() ?? 'فشل الاستخراج';
        print('❌ فشل Gemini: $error');
        return ExtractionResult(
          data: {},
          source: 'Gemini',
          success: false,
          error: error,
        );
      }
    } on HttpException catch (e) {
      print('❌ خطأ HTTP من Gemini: ${e.message}');
      return ExtractionResult(
        data: {},
        source: 'Gemini',
        success: false,
        error: e.message,
      );
    } catch (e) {
      print('❌ خطأ من Gemini: $e');
      return ExtractionResult(
        data: {},
        source: 'Gemini',
        success: false,
        error: e.toString(),
      );
    }
  }
}

/// نتيجة عملية الاستخراج
class ExtractionResult {
  final Map<String, dynamic> data;
  final String source;
  final bool success;
  final String? error;

  ExtractionResult({
    required this.data,
    required this.source,
    required this.success,
    this.error,
  });
}
