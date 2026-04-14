// services/ai_extraction_service.dart
// خدمة استخراج بيانات الفواتير باستخدام Gemini مع مطابقة المنتجات

import 'dart:io';
import 'multi_provider_ai_service.dart';
import 'database_service.dart';

/// خدمة استخراج البيانات من الصور باستخدام Gemini
class AIExtractionService {
  AIExtractionService({
    required this.geminiApiKey,
    this.geminiApiKey2,
    this.geminiApiKey3,
    this.geminiApiKey4,
    this.openRouterApiKey,
    this.groqApiKey,
    this.cloudflareApiToken,
    this.cloudflareAccountId,
    this.ocrSpaceApiKey,
    this.glmApiKey,
    this.mistralApiKey,  // ✅ Mistral Pixtral - مجاني سخي!
  });

  final String geminiApiKey;
  final String? geminiApiKey2;
  final String? geminiApiKey3;
  final String? geminiApiKey4;
  final String? openRouterApiKey;
  final String? groqApiKey;
  final String? cloudflareApiToken;
  final String? cloudflareAccountId;
  final String? ocrSpaceApiKey;
  final String? glmApiKey;
  final String? mistralApiKey;  // ✅ Mistral

  /// جلب قائمة المنتجات من قاعدة البيانات
  Future<List<Map<String, dynamic>>> _getProductsForMatching() async {
    try {
      final db = await DatabaseService().database;
      final rows = await db.query(
        'products',
        columns: ['id', 'name', 'cost_price', 'unit_price', 'unit'],
      );
      
      final products = rows.map((row) => {
        'id': row['id'],
        'name': row['name'],
        'cost_price': row['cost_price'] ?? 0,
        'unit': row['unit'],
      }).toList();
      
      print('📦 تم جلب ${products.length} منتج للمطابقة');
      return products;
    } catch (e) {
      print('⚠️ خطأ في جلب المنتجات: $e');
      return [];
    }
  }

  /// استخراج بيانات الفاتورة أو السند من الصورة
  Future<ExtractionResult> extractInvoiceOrReceiptStructured({
    required List<int> fileBytes,
    required String fileMimeType,
    required String extractType,
  }) async {
    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🤖 استخراج البيانات باستخدام AI');
    print('📄 نوع الملف: $fileMimeType');
    print('📋 نوع الاستخراج: $extractType');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    try {
      // جلب المنتجات للمطابقة (فقط للفواتير)
      List<Map<String, dynamic>>? products;
      if (extractType == 'invoice') {
        products = await _getProductsForMatching();
      }

      final aiService = MultiProviderAIService(
        geminiApiKey: geminiApiKey,
        geminiApiKey2: geminiApiKey2,
        geminiApiKey3: geminiApiKey3,
        geminiApiKey4: geminiApiKey4,
        openRouterApiKey: openRouterApiKey,
        groqApiKey: groqApiKey,
        cloudflareApiToken: cloudflareApiToken,
        cloudflareAccountId: cloudflareAccountId,
        ocrSpaceApiKey: ocrSpaceApiKey,
        glmApiKey: glmApiKey,
        mistralApiKey: mistralApiKey,  // ✅ Mistral Pixtral
      );

      final result = await aiService.extractInvoiceOrReceiptStructured(
        fileBytes: fileBytes,
        fileMimeType: fileMimeType,
        extractType: extractType,
        products: products ?? [],
      );

      if (result.isNotEmpty && !result.containsKey('error')) {
        final items = result['line_items'] as List? ?? [];
        final providerName = aiService.currentProvider == 'gemini' ? 'Gemini' : 'Scitely';
        print('✅ نجح $providerName! تم استخراج ${items.length} بند');
        
        // طباعة تفاصيل المطابقة
        for (final item in items) {
          if (item is Map) {
            final name = item['name'] ?? '';
            final originalName = item['original_name'] ?? '';
            final isNew = item['is_new_product'] == true;
            final oldCost = item['old_cost_price'];
            final newCost = item['price'];
            final confidence = item['confidence'];
            final reason = item['reason'] ?? '';
            
            if (isNew) {
              print('  🆕 منتج جديد: $name');
              if (reason.isNotEmpty) print('     📝 السبب: $reason');
            } else {
              final confPercent = confidence != null ? '${(confidence * 100).toStringAsFixed(0)}%' : '?';
              print('  ✅ تطابق ($confPercent): "$originalName" → "$name"');
              if (reason.isNotEmpty) print('     📝 السبب: $reason');
              if (oldCost != null && newCost != null && oldCost > 0) {
                final diff = ((newCost - oldCost) / oldCost * 100).toStringAsFixed(1);
                print('     💰 التكلفة: $oldCost → $newCost ($diff%)');
              }
            }
          }
        }
        
        return ExtractionResult(
          data: result,
          source: 'Gemini',
          success: true,
        );
      } else {
        final error = result['error']?.toString() ?? 'فشل الاستخراج';
        print('❌ فشل AI: $error');
        return ExtractionResult(
          data: {},
          source: 'AI',
          success: false,
          error: error,
        );
      }
    } on HttpException catch (e) {
      print('❌ خطأ HTTP من AI: ${e.message}');
      return ExtractionResult(
        data: {},
        source: 'AI',
        success: false,
        error: e.message,
      );
    } catch (e) {
      print('❌ خطأ من AI: $e');
      return ExtractionResult(
        data: {},
        source: 'AI',
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
