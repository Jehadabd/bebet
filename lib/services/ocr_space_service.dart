// services/ocr_space_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// خدمة OCR.space API لاستخراج النص من الصور و PDF
/// مجانية مع 25,000 طلب/شهر
class OcrSpaceService {
  OcrSpaceService({required this.apiKey});

  final String apiKey;

  /// استخراج النص من صورة أو PDF باستخدام OCR.space
  /// engine: 1=ABBYY, 2=Amazon, 3=Google Tesseract
  /// language: 'ara' للعربية (Auto-detect إذا فارغ)
  Future<String> extractText(
    Uint8List fileBytes, {
    int engine = 3,
    String? language, // null = auto-detect
    bool isPdf = false,
  }) async {
    try {
      print('🔍 OCR.space: بدء استخراج النص (Engine $engine, ${isPdf ? "PDF" : "Image"}, Lang: ${language ?? "auto"})...');

      final String base64Data = base64Encode(fileBytes);
      final String mimeType = isPdf ? 'application/pdf' : 'image/jpeg';

      // بناء body بدون language لاستخدام auto-detect
      final Map<String, String> body = {
        'base64Image': 'data:$mimeType;base64,$base64Data',
        'isOverlayRequired': 'false',
        'detectOrientation': 'true',
        'scale': 'true',
        'OCREngine': engine.toString(),
        if (isPdf) 'filetype': 'PDF',
      };

      // إضافة language فقط إذا تم تحديدها
      // ملاحظة: OCR.space يدعم 'arabic' كاسم كامل للغة العربية
      if (language != null && language.isNotEmpty) {
        body['language'] = language;
      }

      final response = await http.post(
        Uri.parse('https://api.ocr.space/parse/image'),
        headers: {
          'apikey': apiKey,
        },
        body: body,
      ).timeout(const Duration(seconds: 90));

      print('📡 OCR.space: Status ${response.statusCode}');

      if (response.statusCode != 200) {
        print('❌ OCR.space خطأ: ${response.statusCode}');
        print('📄 Response: ${response.body}');
        throw Exception('OCR.space error: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      
      // التحقق من وجود خطأ
      if (decoded.containsKey('ErrorMessage')) {
        final errorMsg = decoded['ErrorMessage'];
        print('❌ OCR.space خطأ: $errorMsg');
        throw Exception('OCR.space error: $errorMsg');
      }

      // استخراج النص
      final parsedResults = decoded['ParsedResults'] as List?;
      if (parsedResults == null || parsedResults.isEmpty) {
        print('⚠️ OCR.space: لا توجد نتائج');
        return '';
      }

      final text = parsedResults[0]['ParsedText'] as String? ?? '';
      
      print('✅ OCR.space: تم استخراج ${text.length} حرف');
      
      // طباعة النص المستخرج
      if (text.isNotEmpty) {
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print('📄 النص المستخرج من OCR.space:');
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        print(text);
        print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      }

      return text;
    } catch (e) {
      print('❌ OCR.space فشل: $e');
      return '';
    }
  }

  /// استخراج النص من صورة (للتوافق مع الكود القديم)
  Future<String> extractTextFromImage(
    Uint8List imageBytes, {
    int engine = 3,
    String? language,
  }) async {
    return extractText(imageBytes, engine: engine, language: language, isPdf: false);
  }

  /// استخراج النص من PDF
  Future<String> extractTextFromPdf(
    Uint8List pdfBytes, {
    int engine = 3,
    String? language,
  }) async {
    return extractText(pdfBytes, engine: engine, language: language, isPdf: true);
  }

  /// اختبار API Key
  Future<bool> testApiKey() async {
    try {
      print('🔑 اختبار API Key...');
      
      // صورة اختبار صغيرة (1x1 pixel)
      final testImage = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
      
      final response = await http.post(
        Uri.parse('https://api.ocr.space/parse/image'),
        headers: {
          'apikey': apiKey,
        },
        body: {
          'base64Image': 'data:image/png;base64,${base64Encode(testImage)}',
          'language': 'eng',
          'engine': '1',
        },
      ).timeout(const Duration(seconds: 30));

      print('📡 Test Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && !decoded.containsKey('ErrorMessage')) {
          print('✅ API Key صالح!');
          return true;
        }
      }
      
      print('❌ API Key غير صالح');
      return false;
    } catch (e) {
      print('❌ خطأ في اختبار API Key: $e');
      return false;
    }
  }
}
