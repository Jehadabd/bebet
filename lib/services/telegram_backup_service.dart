// خدمة إرسال النسخ الاحتياطية إلى Telegram
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'settings_manager.dart';
import 'database_service.dart';
import 'reports_service.dart';

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
      
      // تأخير 3.5 ثواني لتجنب rate limiting (حد Telegram: 20 رسالة/دقيقة)
      if (i < files.length - 1) {
        await Future.delayed(const Duration(milliseconds: 3500));
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

  /// إرسال ملخص شهري إلى Telegram
  /// يحسب البيانات من أول الشهر الحالي إلى تاريخ اليوم
  Future<bool> sendMonthlySummary() async {
    if (!isConfigured) return false;

    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final startStr = startOfMonth.toIso8601String().split('T')[0];
      final endStr = now.toIso8601String().split('T')[0];
      
      final db = DatabaseService();
      final database = await db.database;
      final reportsService = ReportsService();
      final nf = NumberFormat('#,##0', 'en_US');
      
      // 1) بيانات الفواتير
      final invoiceData = await database.rawQuery('''
        SELECT 
          COUNT(*) as invoice_count,
          COALESCE(SUM(total_amount), 0) as total_sales
        FROM invoices
        WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
          AND status = 'محفوظة'
      ''', [startStr, endStr]);
      
      final invoiceCount = invoiceData.first['invoice_count'] as int? ?? 0;
      final totalSales = (invoiceData.first['total_sales'] as num?)?.toDouble() ?? 0.0;
      
      // 2) حساب أرباح الفواتير باستخدام ReportsService
      final periodSummary = await reportsService.getPeriodSummary(
        startDate: startOfMonth,
        endDate: now,
      );
      final invoiceProfit = periodSummary['netProfit'] as double? ?? 0.0;
      
      // 3) معاملات إضافة الدين اليدوية (من هذا الجهاز فقط، غير مرتبطة بفاتورة)
      final manualDebtData = await database.rawQuery('''
        SELECT 
          COUNT(*) as count,
          COALESCE(SUM(amount_changed), 0) as total
        FROM transactions
        WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
          AND transaction_type IN ('manual_debt', 'opening_balance')
          AND is_created_by_me = 1
          AND invoice_id IS NULL
      ''', [startStr, endStr]);
      
      final manualDebtCount = manualDebtData.first['count'] as int? ?? 0;
      final manualDebtTotal = (manualDebtData.first['total'] as num?)?.toDouble() ?? 0.0;
      final manualDebtProfit = manualDebtTotal * 0.15; // 15% أرباح
      
      // 4) معاملات تسديد الدين اليدوية (من هذا الجهاز فقط، غير مرتبطة بفاتورة)
      final manualPaymentData = await database.rawQuery('''
        SELECT 
          COUNT(*) as count,
          COALESCE(SUM(ABS(amount_changed)), 0) as total
        FROM transactions
        WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
          AND transaction_type = 'manual_payment'
          AND is_created_by_me = 1
          AND invoice_id IS NULL
      ''', [startStr, endStr]);
      
      final manualPaymentCount = manualPaymentData.first['count'] as int? ?? 0;
      final manualPaymentTotal = (manualPaymentData.first['total'] as num?)?.toDouble() ?? 0.0;
      
      // 5) جلب اسم الفرع من الإعدادات
      final settings = await SettingsManager.getAppSettings();
      final branchName = settings.branchName;
      
      // 6) بناء الرسالة
      final monthNames = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
      ];
      final monthName = monthNames[now.month - 1];
      
      final message = '''
📊 <b>ملخص شهر $monthName ${now.year}</b>
🏪 <b>$branchName</b>
📅 من ${startOfMonth.day}/${startOfMonth.month}/${startOfMonth.year} إلى ${now.day}/${now.month}/${now.year}

🧾 <b>الفواتير:</b>
   • العدد: $invoiceCount فاتورة
   • المبالغ: ${nf.format(totalSales)} د.ع
   • الأرباح: ${nf.format(invoiceProfit)} د.ع

💰 <b>معاملات إضافة الدين (يدوية):</b>
   • العدد: $manualDebtCount معاملة
   • المبلغ: ${nf.format(manualDebtTotal)} د.ع
   • الأرباح (15%): ${nf.format(manualDebtProfit)} د.ع

💵 <b>معاملات تسديد الدين (يدوية):</b>
   • العدد: $manualPaymentCount معاملة
   • المبلغ: ${nf.format(manualPaymentTotal)} د.ع

📈 <b>إجمالي الأرباح:</b> ${nf.format(invoiceProfit + manualDebtProfit)} د.ع
''';
      
      return await sendMessage(message);
    } catch (e) {
      return false;
    }
  }
}
