// services/ai_extraction_service.dart
import 'dart:io';
import 'groq_service.dart';
import 'gemini_service.dart';
import 'huggingface_service.dart';

/// خدمة موحدة لاستخراج البيانات من الصور باستخدام AI
/// تحاول Groq أولاً، ثم Gemini كخطة احتياطية
class AIExtractionService {
  AIExtractionService({
    required this.groqApiKey,
    required this.geminiApiKey,
    required this.huggingfaceApiKey,
  });

  final String groqApiKey;
  final String geminiApiKey;
  final String huggingfaceApiKey;

  /// استخراج بيانات الفاتورة أو السند من الصورة
  /// يحاول Gemini أولاً (الأولوية)، ثم Groq، ثم HuggingFace
  Future<ExtractionResult> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType, // 'invoice' | 'receipt'
  }) async {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🤖 بدء استخراج البيانات من الصورة');
    print('📄 نوع الملف: $fileMimeType');
    print('📋 نوع الاستخراج: $extractType');
    print('🎯 الأولوية: Gemini → Groq → HuggingFace');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    // المحاولة 1: Gemini (الأولوية الأولى) ⭐
    if (geminiApiKey.isNotEmpty) {
      print('⭐ المحاولة 1: استخدام Gemini (الأولوية الأولى)...');
      try {
        final geminiService = GeminiService(apiKey: geminiApiKey);
        final result = await geminiService.extractInvoiceOrReceiptStructured(
          fileBytes: fileBytes,
          fileMimeType: fileMimeType,
          extractType: extractType,
        );

        if (result.isNotEmpty && !result.containsKey('error')) {
          print('✅ نجح Gemini! تم استخراج البيانات بنجاح');
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
          return ExtractionResult(
            data: result,
            source: 'Gemini',
            success: true,
          );
        } else {
          print('⚠️ Gemini أرجع نتيجة فارغة أو خطأ');
        }
      } on HttpException catch (e) {
        print('❌ خطأ HTTP من Gemini: ${e.message}');
        if (e.message.contains('429')) {
          print('   السبب: تجاوز الحصة (Rate Limit)');
        } else if (e.message.contains('503')) {
          print('   السبب: الخدمة غير متاحة مؤقتاً');
        }
      } catch (e) {
        print('❌ خطأ عام من Gemini: $e');
      }
      print('🔄 الانتقال إلى Groq...\n');
    } else {
      print('⏭️ تخطي Gemini (API Key غير متوفر)\n');
    }

    // المحاولة 2: Groq API (Llama 3.2 Vision)
    if (groqApiKey.isNotEmpty) {
      print('🔵 المحاولة 2: استخدام Groq API...');
      try {
        final groqService = GroqService(apiKey: groqApiKey);
        final result = await groqService.extractInvoiceOrReceiptStructured(
          fileBytes: fileBytes,
          fileMimeType: fileMimeType,
          extractType: extractType,
        );

        if (result.isNotEmpty && !result.containsKey('error')) {
          print('✅ نجح Groq! تم استخراج البيانات بنجاح');
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
          return ExtractionResult(
            data: result,
            source: 'Groq',
            success: true,
          );
        } else {
          print('⚠️ Groq أرجع نتيجة فارغة أو خطأ');
        }
      } on HttpException catch (e) {
        print('❌ خطأ HTTP من Groq: ${e.message}');
        if (e.message.contains('429')) {
          print('   السبب: تجاوز الحصة (Rate Limit)');
        } else if (e.message.contains('401') || e.message.contains('403')) {
          print('   السبب: مشكلة في المصادقة');
        } else if (e.message.contains('400')) {
          print('   السبب: طلب غير صالح (قد يكون نوع الملف غير مدعوم)');
        }
      } catch (e) {
        print('❌ خطأ عام من Groq: $e');
      }
      print('🔄 الانتقال إلى HuggingFace...\n');
    } else {
      print('⏭️ تخطي Groq (API Key غير متوفر)\n');
    }

    // المحاولة 3: Hugging Face API (Qwen2-VL - الخيار الأخير)
    if (huggingfaceApiKey.isNotEmpty) {
      print('🟠 المحاولة 3: استخدام Hugging Face API (Qwen2-VL)...');
      try {
        final hfService = HuggingFaceService(apiKey: huggingfaceApiKey);
        final result = await hfService.extractInvoiceOrReceiptStructured(
          fileBytes: fileBytes,
          fileMimeType: fileMimeType,
          extractType: extractType,
        );

        if (result.isNotEmpty && !result.containsKey('error')) {
          print('✅ نجح Hugging Face! تم استخراج البيانات بنجاح');
          print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
          return ExtractionResult(
            data: result,
            source: 'HuggingFace',
            success: true,
          );
        } else {
          print('⚠️ Hugging Face أرجع نتيجة فارغة أو خطأ');
        }
      } on HttpException catch (e) {
        print('❌ خطأ HTTP من Hugging Face: ${e.message}');
        if (e.message.contains('503')) {
          print('   السبب: النموذج يتم تحميله، حاول مرة أخرى');
        }
      } catch (e) {
        print('❌ خطأ عام من Hugging Face: $e');
      }
    } else {
      print('⏭️ تخطي Hugging Face (API Key غير متوفر)\n');
    }

    // فشلت جميع المحاولات
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('❌ فشلت جميع محاولات الاستخراج');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
    
    return ExtractionResult(
      data: {},
      source: 'None',
      success: false,
      error: 'فشل استخراج البيانات من جميع الخدمات المتاحة',
    );
  }
}

/// نتيجة عملية الاستخراج
class ExtractionResult {
  final Map<String, dynamic> data;
  final String source; // 'Groq' | 'Gemini' | 'None'
  final bool success;
  final String? error;

  ExtractionResult({
    required this.data,
    required this.source,
    required this.success,
    this.error,
  });
}
