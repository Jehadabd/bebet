// services/file_preprocessor_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart'; // بديل ممتاز على ويندوز
import 'dart:ui' show ImageByteFormat;

/// خدمة تحضير الملفات للمزودين الذين لا يدعمون PDF (مثل Groq)
class FilePreprocessorService {
  
  /// تحويل PDF إلى صورة (أول صفحة فقط)
  static Future<Uint8List> convertPdfToImage(List<int> pdfBytes) async {
    try {
      print('📄 PDF -> تحويل إلى صورة...');
      
      // هنا نستخدم Printing بدلا من pdf_render للويندوز
      await for (final page in Printing.raster(Uint8List.fromList(pdfBytes), pages: [0], dpi: 150)) {
        final image = await page.toImage();
        final byteData = await image.toByteData(format: ImageByteFormat.png);
        final bytes = byteData!.buffer.asUint8List();
        print('✅ تم تحويل PDF إلى صورة: ${bytes.length} بايت');
        return bytes; 
      }
      
      throw Exception('ملف الـ PDF فارغ ولا يحتوي على صفحات.');
    } catch (e) {
      print('❌ فشل تحويل PDF إلى صورة: $e');
      rethrow;
    }
  }
  
  /// ضغط الصورة (تقليل الأبعاد والجودة)
  static Future<Uint8List> compressImage(
    Uint8List imageBytes, {
    int maxWidth = 1024,
    int quality = 70,
    int maxSizeBytes = 3 * 1024 * 1024, // 3 ميجابايت كحد أقصى
  }) async {
    try {
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        print('⚠️ لا يمكن فك تشفير الصورة');
        return imageBytes;
      }
      
      print('📐 أبعاد الصورة الأصلية: ${image.width}x${image.height}');
      
      // تغيير الحجم إذا كان العرض أكبر من maxWidth
      if (image.width > maxWidth) {
        final newHeight = (image.height * maxWidth / image.width).round();
        image = img.copyResize(image, width: maxWidth, height: newHeight);
        print('📐 تم تغيير الحجم إلى: ${image.width}x${image.height}');
      }
      
      // ضغط الجودة
      Uint8List compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      print('📦 ضغط الصورة: ${imageBytes.length} → ${compressed.length} بايت (${(compressed.length / imageBytes.length * 100).toStringAsFixed(1)}%)');
      
      // إذا كان الحجم لا يزال كبيراً، قلل الجودة أكثر
      while (compressed.length > maxSizeBytes && quality > 30) {
        quality -= 10;
        compressed = Uint8List.fromList(img.encodeJpg(image, quality: quality));
        print('📦 إعادة الضغط (جودة $quality%): ${compressed.length} بايت');
      }
      
      if (compressed.length > maxSizeBytes) {
        throw Exception('الصورة كبيرة جداً حتى بعد الضغط. الحد الأقصى 3 ميجابايت.');
      }
      
      return compressed;
    } catch (e) {
      print('⚠️ فشل ضغط الصورة: $e');
      return imageBytes;
    }
  }

  /// التحضير لإرسال الملف إلى Groq أو Cloudflare
  /// - إذا كان PDF: يحول إلى صورة ثم يضغطها
  /// - إذا كان صورة: يضغطها
  static Future<ProcessedFile> prepareForNonGeminiProvider(
    List<int> fileBytes,
    String mimeType,
  ) async {
    Uint8List bytes = Uint8List.fromList(fileBytes);
    
    if (mimeType == 'application/pdf') {
      print('📄 PDF -> تحويل إلى صورة ثم ضغط...');
      // تحويل PDF إلى صورة
      bytes = await convertPdfToImage(bytes);
      // ضغط الصورة الناتجة
      bytes = await compressImage(bytes);
      return ProcessedFile(
        bytes: bytes,
        mimeType: 'image/jpeg', // بعد الضغط تصبح JPG
      );
    } else if (mimeType.startsWith('image/')) {
      print('🖼️ صورة -> ضغط للحصول على حجم أقل من 3 ميجابايت');
      bytes = await compressImage(bytes);
      return ProcessedFile(
        bytes: bytes,
        mimeType: 'image/jpeg', // بعد الضغط تصبح JPG
      );
    } else {
      throw Exception('نوع ملف غير مدعوم: $mimeType');
    }
  }
}

/// صف يمثل الملف المعالج
class ProcessedFile {
  final Uint8List bytes;
  final String mimeType;
  
  ProcessedFile({
    required this.bytes,
    required this.mimeType,
  });
}
