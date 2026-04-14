// services/google_vision_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// خدمة Google Cloud Vision API لاستخراج النص من الصور
class GoogleVisionService {
  GoogleVisionService({required this.apiKey});

  final String apiKey;

  /// استخراج النص من صورة باستخدام Google Cloud Vision
  Future<String> extractTextFromImage(Uint8List imageBytes) async {
    final base64Image = base64Encode(imageBytes);

    final requestBody = {
      'requests': [
        {
          'image': {
            'content': base64Image,
          },
          'features': [
            {
              'type': 'TEXT_DETECTION',
              'maxResults': 1,
            },
            {
              'type': 'DOCUMENT_TEXT_DETECTION',
              'maxResults': 1,
            },
          ],
          'imageContext': {
            'languageHints': ['ar', 'en'], // دعم العربية والإنجليزية
          },
        },
      ],
    };

    try {
      print('🔍 Google Vision: بدء استخراج النص من الصورة...');

      final response = await http.post(
        Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('❌ Google Vision خطأ: ${response.statusCode}');
        throw Exception('Google Vision error: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final responses = decoded['responses'] as List?;

      if (responses == null || responses.isEmpty) {
        print('⚠️ Google Vision: لا توجد استجابة');
        return '';
      }

      // استخراج النص الكامل
      final fullTextAnnotation = responses[0]['fullTextAnnotation'] as Map<String, dynamic>?;
      final text = fullTextAnnotation?['text'] as String? ?? '';

      if (text.isEmpty) {
        // محاولة استخراج من textAnnotations
        final textAnnotations = responses[0]['textAnnotations'] as List?;
        if (textAnnotations != null && textAnnotations.isNotEmpty) {
          final firstText = textAnnotations[0] as Map<String, dynamic>?;
          return firstText?['description'] as String? ?? '';
        }
      }

      print('✅ Google Vision: تم استخراج ${text.length} حرف');
      return text;
    } catch (e) {
      print('❌ Google Vision فشل: $e');
      return '';
    }
  }

  /// استخراج النص مع معلومات الموقع (للجداول)
  Future<List<Map<String, dynamic>>> extractTextWithBlocks(Uint8List imageBytes) async {
    final base64Image = base64Encode(imageBytes);

    final requestBody = {
      'requests': [
        {
          'image': {
            'content': base64Image,
          },
          'features': [
            {
              'type': 'DOCUMENT_TEXT_DETECTION',
              'maxResults': 1,
            },
          ],
          'imageContext': {
            'languageHints': ['ar', 'en'],
          },
        },
      ],
    };

    try {
      final response = await http.post(
        Uri.parse('https://vision.googleapis.com/v1/images:annotate?key=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw Exception('Google Vision error: ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final responses = decoded['responses'] as List?;

      if (responses == null || responses.isEmpty) {
        return [];
      }

      final fullTextAnnotation = responses[0]['fullTextAnnotation'] as Map<String, dynamic>?;
      if (fullTextAnnotation == null) return [];

      final pages = fullTextAnnotation['pages'] as List?;
      if (pages == null || pages.isEmpty) return [];

      final blocks = <Map<String, dynamic>>[];

      for (final page in pages) {
        final pageBlocks = page['blocks'] as List?;
        if (pageBlocks == null) continue;

        for (final block in pageBlocks) {
          final paragraphs = block['paragraphs'] as List?;
          if (paragraphs == null) continue;

          final blockText = StringBuffer();
          for (final paragraph in paragraphs) {
            final words = paragraph['words'] as List?;
            if (words == null) continue;

            for (final word in words) {
              final symbols = word['symbols'] as List?;
              if (symbols == null) continue;

              for (final symbol in symbols) {
                blockText.write(symbol['text'] ?? '');
              }
              blockText.write(' ');
            }
          }

          // استخراج إحداثيات الكتلة
          final boundingBox = block['boundingBox'] as Map<String, dynamic>?;
          final vertices = boundingBox?['normalizedVertices'] as List?;

          blocks.add({
            'text': blockText.toString().trim(),
            'position': vertices,
          });
        }
      }

      return blocks;
    } catch (e) {
      print('❌ Google Vision فشل في استخراج الكتل: $e');
      return [];
    }
  }
}
