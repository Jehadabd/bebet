// services/discord_backup_service.dart
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as path;

/// خدمة النسخ الاحتياطي إلى Discord عبر Webhook
/// أسهل من Telegram و TamTam - Webhook واحد فقط!
class DiscordBackupService {
  static final DiscordBackupService _instance = DiscordBackupService._internal();
  factory DiscordBackupService() => _instance;
  DiscordBackupService._internal();

  // إعدادات Discord
  String? _webhookUrl;
  bool _isEnabled = false;

  // Getters
  bool get isEnabled => _isEnabled;
  String? get webhookUrl => _webhookUrl;

  /// تحميل الإعدادات من dotenv
  void loadSettings() {
    _webhookUrl = dotenv.env['DISCORD_WEBHOOK_URL']?.trim();
    _isEnabled = dotenv.env['DISCORD_ENABLED'] == 'true';
    
    print('📱 Discord Settings Loaded:');
    print('   Webhook: ${_webhookUrl == null || _webhookUrl!.isEmpty ? "غير موجود" : "موجود (${_webhookUrl!.length} حرف)"}');
    print('   Enabled: $_isEnabled');
  }

  /// حفظ الإعدادات
  Future<void> saveSettings({
    required String webhookUrl,
    required bool enabled,
  }) async {
    _webhookUrl = webhookUrl.trim();
    _isEnabled = enabled;

    print('💾 Discord: حفظ الإعدادات...');
    print('   Webhook: ${webhookUrl.isEmpty ? "فارغ" : "موجود (${webhookUrl.length} حرف)"}');
    print('   Enabled: $enabled');

    // تحديث ملف .env
    try {
      final envFile = File('.env');
      if (await envFile.exists()) {
        String content = await envFile.readAsString();
        
        // تحديث أو إضافة القيم
        content = _updateEnvLine(content, 'DISCORD_WEBHOOK_URL', webhookUrl);
        content = _updateEnvLine(content, 'DISCORD_ENABLED', enabled.toString());
        
        await envFile.writeAsString(content);
        print('✅ Discord: تم حفظ الإعدادات في .env');
      }
    } catch (e) {
      print('⚠️ Discord: خطأ في الحفظ - $e');
    }
    
    // ✅ القيم محفوظة في الـ instance مباشرة
    // لا نحتاج لإعادة تحميل dotenv
  }

  String _updateEnvLine(String content, String key, String value) {
    final lines = content.split('\n');
    bool found = false;
    
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('$key=')) {
        lines[i] = '$key=$value';
        found = true;
        break;
      }
    }
    
    if (!found) {
      lines.add('$key=$value');
    }
    
    return lines.join('\n');
  }

  /// اختبار الاتصال مع Discord
  Future<bool> testConnection() async {
    if (_webhookUrl == null || _webhookUrl!.isEmpty) {
      print('❌ Discord: Webhook URL غير موجود');
      return false;
    }

    // التحقق من صحة الرابط
    if (!_webhookUrl!.startsWith('https://discord.com/api/webhooks/') &&
        !_webhookUrl!.startsWith('https://discordapp.com/api/webhooks/')) {
      print('❌ Discord: رابط Webhook غير صالح');
      print('   يجب أن يبدأ بـ: https://discord.com/api/webhooks/');
      return false;
    }

    try {
      print('🔍 Discord: اختبار الاتصال...');
      print('   URL: ${_webhookUrl!.substring(0, 60)}...');
      
      final response = await http.post(
        Uri.parse(_webhookUrl!),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': '🔍 اختبار الاتصال من تطبيق دبس كريدي',
        }),
      ).timeout(const Duration(seconds: 30));

      print('📡 Discord: Status ${response.statusCode}');
      
      // Discord يعيد 204 أو 200 عند النجاح
      if (response.statusCode == 204 || response.statusCode == 200 || response.statusCode == 201) {
        print('✅ Discord: متصل بنجاح!');
        return true;
      }
      
      print('❌ Discord: فشل الاتصال - ${response.statusCode}');
      print('📄 Response: ${response.body}');
      return false;
    } catch (e) {
      print('❌ Discord: خطأ في الاتصال - $e');
      return false;
    }
  }

  /// إرسال رسالة ترحيبية
  Future<bool> sendWelcomeMessage() async {
    if (!_isEnabled || _webhookUrl == null) {
      print('⚠️ Discord: غير مفعّل أو إعدادات ناقصة');
      return false;
    }

    try {
      final response = await http.post(
        Uri.parse(_webhookUrl!),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'content': '''
🎉 تم ربط التطبيق بنجاح!

📱 التطبيق: دبس كريدي
📅 التاريخ: ${DateTime.now().toString().split('.')[0]}

✅ سيتم إرسال النسخ الاحتياطية هنا تلقائياً.
''',
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 204 || response.statusCode == 200) {
        print('✅ Discord: تم إرسال الرسالة الترحيبية');
        return true;
      }
      
      print('❌ Discord: فشل إرسال الرسالة الترحيبية');
      return false;
    } catch (e) {
      print('❌ Discord: خطأ - $e');
      return false;
    }
  }

  /// إرسال ملف النسخة الاحتياطية (Webhook بسيط!)
  Future<bool> sendBackupFile(File file, {String? caption}) async {
    if (!_isEnabled || _webhookUrl == null) {
      print('⚠️ Discord: تخطي الإرسال (غير مفعّل)');
      return false;
    }

    try {
      print('📤 Discord: إرسال النسخة الاحتياطية...');
      
      final fileName = path.basename(file.path);
      final fileBytes = await file.readAsBytes();
      
      // إنشاء multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_webhookUrl!));
      
      // إضافة الملف
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ),
      );
      
      // إضافة محتوى الرسالة (اختياري)
      if (caption != null && caption.isNotEmpty) {
        request.fields['content'] = caption;
      } else {
        request.fields['content'] = '📦 نسخة احتياطية - ${DateTime.now().toString().split('.')[0]}';
      }
      
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
      );
      
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 204 || response.statusCode == 200) {
        print('✅ Discord: تم إرسال الملف بنجاح');
        return true;
      }
      
      print('❌ Discord: فشل إرسال الملف - ${response.statusCode}');
      print('📄 Response: ${response.body}');
      return false;
    } catch (e) {
      print('❌ Discord: خطأ في إرسال الملف - $e');
      return false;
    }
  }

  String _normalizeMessageForDiscord(String text) {
    return text
        .replaceAll('<b>', '**')
        .replaceAll('</b>', '**')
        .replaceAll('<strong>', '**')
        .replaceAll('</strong>', '**')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('═══════════════════', '━━━━━━━━━━━━━━━━━━━')
        .replaceAll('══════════════════', '━━━━━━━━━━━━━━━━━━')
        .replaceAll('═════════════════', '━━━━━━━━━━━━━━━━━')
        .replaceAll('════════════════', '━━━━━━━━━━━━━━━━')
        .replaceAll('═══════════════', '━━━━━━━━━━━━━━━')
        .trim();
  }

  List<String> _splitMessageForDiscord(String text, {int maxLength = 1800}) {
    final normalized = _normalizeMessageForDiscord(text);
    if (normalized.length <= maxLength) return [normalized];

    final lines = normalized.split('\n');
    final parts = <String>[];
    final buffer = StringBuffer();

    for (final line in lines) {
      final candidate = buffer.isEmpty ? line : '${buffer.toString()}\n$line';
      if (candidate.length <= maxLength) {
        if (!buffer.isEmpty) buffer.write('\n');
        buffer.write(line);
        continue;
      }

      if (!buffer.isEmpty) {
        parts.add(buffer.toString().trim());
        buffer.clear();
      }

      if (line.length <= maxLength) {
        buffer.write(line);
      } else {
        for (int i = 0; i < line.length; i += maxLength) {
          final end = (i + maxLength < line.length) ? i + maxLength : line.length;
          parts.add(line.substring(i, end));
        }
      }
    }

    if (!buffer.isEmpty) {
      parts.add(buffer.toString().trim());
    }

    return parts.where((part) => part.trim().isNotEmpty).toList();
  }

  /// إرسال رسالة نصية
  Future<bool> sendMessage(String text) async {
    if (!_isEnabled || _webhookUrl == null || _webhookUrl!.isEmpty) {
      return false;
    }

    try {
      final parts = _splitMessageForDiscord(text);
      bool allSent = true;

      for (int i = 0; i < parts.length; i++) {
        final response = await http.post(
          Uri.parse(_webhookUrl!),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'content': parts[i],
          }),
        ).timeout(const Duration(seconds: 30));

        final success = response.statusCode == 204 || response.statusCode == 200;
        if (!success) {
          print('❌ Discord: فشل إرسال جزء من الرسالة - ${response.statusCode}');
          print('📄 Response: ${response.body}');
          allSent = false;
          break;
        }

        if (i < parts.length - 1) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }

      return allSent;
    } catch (e) {
      print('❌ Discord: خطأ في إرسال الرسالة - $e');
      return false;
    }
  }

  /// تفعيل/إيقاف الخدمة
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    saveSettings(
      webhookUrl: _webhookUrl ?? '',
      enabled: enabled,
    );
  }
}
