// خدمة إرسال النسخ الاحتياطية إلى Telegram
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_manager.dart';

class TelegramBackupService {
  static final TelegramBackupService _instance = TelegramBackupService._internal();
  factory TelegramBackupService() => _instance;
  TelegramBackupService._internal();

  // مفاتيح التخزين
  static const String _lastUploadTimeKey = 'telegram_last_upload_time';

  // القيم الثابتة (للاستخدام إذا فشل تحميل .env)
  static const String _fallbackBotToken = '8500250915:AAFl4ITzMuvEeC7hsSv0zk8UFZY6XsEysI8';
  static const String _fallbackChannelIdElectric = '-1003625352513'; // كهربائيات
  static const String _fallbackChannelIdHealth = '-1003392606317'; // صحيات

  // الحصول على البيانات من .env مع fallback
  String get _botToken {
    final envToken = dotenv.env['TELEGRAM_BOT_TOKEN'] ?? '';
    return envToken.isNotEmpty ? envToken : _fallbackBotToken;
  }
  
  String get _channelIdElectric {
    final envChannelId = dotenv.env['TELEGRAM_CHANNEL_ID'] ?? '';
    return envChannelId.isNotEmpty ? envChannelId : _fallbackChannelIdElectric;
  }
  
  String get _channelIdHealth {
    final envChannelId = dotenv.env['TELEGRAM_CHANNEL_ID_HEALTH'] ?? '';
    return envChannelId.isNotEmpty ? envChannelId : _fallbackChannelIdHealth;
  }

  /// الحصول على Channel ID بناءً على قسم المحل المحدد في الإعدادات
  Future<String> _getChannelId() async {
    final settings = await SettingsManager.getAppSettings();
    if (settings.storeSection == 'صحيات') {
      return _channelIdHealth;
    }
    return _channelIdElectric;
  }

  // للتشخيص
  bool get botTokenExists => _botToken.isNotEmpty;
  bool get channelIdExists => _channelIdElectric.isNotEmpty;

  // التحقق من صحة الإعدادات
  bool get isConfigured => _botToken.isNotEmpty && _channelIdElectric.isNotEmpty;

  /// إرسال ملف إلى قناة Telegram
  Future<bool> sendDocument({
    required File file,
    String? caption,
  }) async {
    if (!isConfigured) {
      return false;
    }

    try {
      final channelId = await _getChannelId();
      final uri = Uri.parse('https://api.telegram.org/bot$_botToken/sendDocument');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['chat_id'] = channelId;
      if (caption != null && caption.isNotEmpty) {
        request.fields['caption'] = caption;
      }
      
      request.files.add(await http.MultipartFile.fromPath(
        'document',
        file.path,
        filename: file.uri.pathSegments.last,
      ));

      final response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// إرسال رسالة نصية إلى القناة
  Future<bool> sendMessage(String text) async {
    if (!isConfigured) return false;

    try {
      final channelId = await _getChannelId();
      final uri = Uri.parse('https://api.telegram.org/bot$_botToken/sendMessage');
      final response = await http.post(uri, body: {
        'chat_id': channelId,
        'text': text,
        'parse_mode': 'HTML',
      });

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// إرسال مجموعة ملفات PDF
  Future<int> sendMultipleDocuments({
    required List<File> files,
    Function(int current, int total)? onProgress,
  }) async {
    int successCount = 0;
    
    for (int i = 0; i < files.length; i++) {
      onProgress?.call(i + 1, files.length);
      
      final success = await sendDocument(file: files[i]);
      if (success) successCount++;
      
      // تأخير بسيط لتجنب rate limiting
      if (i < files.length - 1) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    
    return successCount;
  }

  /// حفظ وقت آخر رفع
  Future<void> saveLastUploadTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUploadTimeKey, DateTime.now().toIso8601String());
  }

  /// الحصول على وقت آخر رفع
  Future<DateTime?> getLastUploadTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_lastUploadTimeKey);
    if (timeStr == null) return null;
    return DateTime.tryParse(timeStr);
  }

  /// مسح وقت آخر رفع (للاختبار)
  Future<void> clearLastUploadTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastUploadTimeKey);
  }
}
