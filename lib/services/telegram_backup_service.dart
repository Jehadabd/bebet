// خدمة إرسال النسخ الاحتياطية إلى Telegram
import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'settings_manager.dart';
import 'database_service.dart';
import 'discord_backup_service.dart'; // ✅ Discord Webhook - إرسال بالتوازي

/// نتيجة عملية الإرسال مع تفاصيل الخطأ
class TelegramSendResult {
  final bool success;
  final String? errorMessage;
  final String? errorDetails;
  final int? statusCode;
  
  TelegramSendResult({
    required this.success,
    this.errorMessage,
    this.errorDetails,
    this.statusCode,
  });
  
  factory TelegramSendResult.ok() => TelegramSendResult(success: true);
  
  factory TelegramSendResult.error(String message, {String? details, int? statusCode}) {
    return TelegramSendResult(
      success: false,
      errorMessage: message,
      errorDetails: details,
      statusCode: statusCode,
    );
  }
  
  @override
  String toString() {
    if (success) return 'نجح الإرسال';
    return 'فشل: $errorMessage${errorDetails != null ? '\nالتفاصيل: $errorDetails' : ''}${statusCode != null ? '\nكود الحالة: $statusCode' : ''}';
  }
}

class TelegramBackupService {
  static final TelegramBackupService _instance = TelegramBackupService._internal();
  factory TelegramBackupService() => _instance;
  TelegramBackupService._internal();

  // مفاتيح التخزين
  static const String _lastUploadTimeKey = 'telegram_last_upload_time';
  static const String _customBotTokenKey = 'telegram_custom_bot_token';
  static const String _customChannelIdKey = 'telegram_custom_channel_id';

  String? customBotToken;
  String? customChannelId;
  
  // آخر خطأ حدث (للتشخيص)
  String? _lastError;
  String? get lastError => _lastError;

  // القيم الثابتة (للاستخدام إذا فشل تحميل .env)
  // ⚠️ هذه القيم مُضمنة في الكود لضمان عمل التطبيق حتى بدون ملف .env
  static const String _fallbackBotToken = '8500250915:AAFl4ITzMuvEeC7hsSv0zk8UFZY6XsEysI8';
  static const String _fallbackChannelIdElectric = '-1003625352513'; // كهربائيات
  static const String _fallbackChannelIdHealth = '-1003392606317'; // صحيات

  // الحصول على البيانات من .env مع fallback آمن (تُستخدم فقط إذا لم يتم ضبط إعدادات مخصصة)
  String get _botToken {
    if (customBotToken != null && customBotToken!.isNotEmpty) return customBotToken!;
    try {
      final envToken = dotenv.env['TELEGRAM_BOT_TOKEN'];
      if (envToken != null && envToken.trim().isNotEmpty) {
        return envToken.trim();
      }
    } catch (e) {
      print('⚠️ خطأ في قراءة TELEGRAM_BOT_TOKEN من .env: $e');
    }
    return _fallbackBotToken;
  }
  
  String get _channelIdElectric {
    try {
      final envChannelId = dotenv.env['TELEGRAM_CHANNEL_ID'];
      if (envChannelId != null && envChannelId.trim().isNotEmpty) {
        return envChannelId.trim();
      }
    } catch (e) {
      print('⚠️ خطأ في قراءة TELEGRAM_CHANNEL_ID من .env: $e');
    }
    return _fallbackChannelIdElectric;
  }
  
  String get _channelIdHealth {
    try {
      final envChannelId = dotenv.env['TELEGRAM_CHANNEL_ID_HEALTH'];
      if (envChannelId != null && envChannelId.trim().isNotEmpty) {
        return envChannelId.trim();
      }
    } catch (e) {
      print('⚠️ خطأ في قراءة TELEGRAM_CHANNEL_ID_HEALTH من .env: $e');
    }
    return _fallbackChannelIdHealth;
  }

  /// الحصول على Channel ID (الأولوية للقناة المخصصة الموحدة، ثم حسب القسم)
  Future<String> _getChannelId() async {
    if (customChannelId != null && customChannelId!.isNotEmpty) {
      return customChannelId!;
    }
    
    final settings = await SettingsManager.getAppSettings();
    final section = settings.storeSection;
    print('📡 القسم المحدد: $section');
    
    if (section == 'صحيات') {
      final channelId = _channelIdHealth;
      print('📡 استخدام قناة الصحيات الافتراضية: $channelId');
      return channelId;
    }
    
    final channelId = _channelIdElectric;
    print('📡 استخدام قناة الكهربائيات الافتراضية: $channelId');
    return channelId;
  }

  // للتشخيص
  bool get botTokenExists => _botToken.isNotEmpty;
  bool get channelIdExists => _channelIdElectric.isNotEmpty;

  // التحقق من صحة الإعدادات
  bool get isConfigured => _botToken.isNotEmpty && _channelIdElectric.isNotEmpty;
  
  /// الحصول على معلومات التشخيص
  Future<Map<String, dynamic>> getDiagnostics() async {
    final settings = await SettingsManager.getAppSettings();
    return {
      'botTokenConfigured': _botToken.isNotEmpty,
      'botTokenSource': customBotToken?.isNotEmpty == true ? 'custom' : (dotenv.env['TELEGRAM_BOT_TOKEN']?.isNotEmpty == true ? '.env' : 'fallback'),
      'channelIdSource': customChannelId?.isNotEmpty == true ? 'custom_unified' : 'section_based',
      'channelIdElectric': _channelIdElectric,
      'channelIdHealth': _channelIdHealth,
      'currentSection': settings.storeSection,
      'activeChannelId': await _getChannelId(),
      'lastError': _lastError,
    };
  }

  /// تحميل الإعدادات من SharedPreferences
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    customBotToken = prefs.getString(_customBotTokenKey);
    customChannelId = prefs.getString(_customChannelIdKey);
  }

  /// حفظ الإعدادات في SharedPreferences
  Future<void> saveSettings({String? botToken, String? channelId}) async {
    final prefs = await SharedPreferences.getInstance();
    
    if (botToken != null && botToken.isNotEmpty) {
      await prefs.setString(_customBotTokenKey, botToken.trim());
      customBotToken = botToken.trim();
    } else {
      await prefs.remove(_customBotTokenKey);
      customBotToken = null;
    }

    if (channelId != null && channelId.isNotEmpty) {
      await prefs.setString(_customChannelIdKey, channelId.trim());
      customChannelId = channelId.trim();
    } else {
      await prefs.remove(_customChannelIdKey);
      customChannelId = null;
    }
  }

  /// اختبار الاتصال (ترسل رسالة باستخدام التوكن والآي دي المخصص)
  Future<bool> testConnection(String testBotToken, String testChannelId) async {
    try {
      final httpClient = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) {
          return host.contains('telegram.org') || host.contains('api.telegram.org');
        };
      
      final uri = Uri.parse('https://api.telegram.org/bot$testBotToken/sendMessage');
      final request = await httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      
      final text = '🔄 رسالة اختبار من التطبيق لتأكيد اتصال Telegram.';
      final body = 'chat_id=${Uri.encodeComponent(testChannelId)}&text=${Uri.encodeComponent(text)}&parse_mode=HTML';
      request.write(body);
      
      final response = await request.close().timeout(const Duration(seconds: 15));
      httpClient.close();

      return response.statusCode == 200;
    } catch (e) {
      print('❌ خطأ أثناء اختبار اتصال Telegram: $e');
      return false;
    }
  }

  /// إرسال ملف إلى قناة Telegram مع تفاصيل الخطأ
  Future<TelegramSendResult> sendDocumentWithDetails({
    required File file,
    String? caption,
  }) async {
    _lastError = null;
    
    // ✅ إرسال بالتوازي إلى Discord (إذا كان مفعلاً)
    final discordService = DiscordBackupService()..loadSettings();
    if (discordService.isEnabled) {
      print('📤 إرسال بالتوازي إلى Discord...');
      // إرسال في الخلفية بدون انتظار
      discordService.sendBackupFile(file, caption: caption).then((success) {
        if (success) {
          print('✅ Discord: تم الإرسال بنجاح');
        } else {
          print('⚠️ Discord: فشل الإرسال (لكن Telegram سيتابع)');
        }
      });
    }
    
    if (!isConfigured) {
      _lastError = 'إعدادات Telegram غير مكتملة';
      return TelegramSendResult.error('إعدادات Telegram غير مكتملة',
          details: 'Bot Token: ${_botToken.isNotEmpty}, Channel ID: ${_channelIdElectric.isNotEmpty}');
    }

    try {
      final channelId = await _getChannelId();
      print('📤 إرسال ملف إلى القناة: $channelId');
      
      // استخدام HttpClient مخصص لتجاوز مشاكل SSL
      final httpClient = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) {
          return host.contains('telegram.org') || host.contains('api.telegram.org');
        };
      
      final uri = Uri.parse('https://api.telegram.org/bot$_botToken/sendDocument');
      
      // إنشاء multipart request يدوياً
      final boundary = '----DartFormBoundary${DateTime.now().millisecondsSinceEpoch}';
      final request = await httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      
      // بناء body
      final bodyParts = <List<int>>[];
      
      // إضافة chat_id - مع تشفير UTF-8
      bodyParts.add(utf8.encode('--$boundary\r\n'));
      bodyParts.add(utf8.encode('Content-Disposition: form-data; name="chat_id"\r\n\r\n'));
      bodyParts.add(utf8.encode('$channelId\r\n'));
      
      // إضافة caption إذا وجد - مع تشفير UTF-8 للنص العربي
      if (caption != null && caption.isNotEmpty) {
        bodyParts.add(utf8.encode('--$boundary\r\n'));
        bodyParts.add(utf8.encode('Content-Disposition: form-data; name="caption"\r\n\r\n'));
        bodyParts.add(utf8.encode('$caption\r\n'));
      }
      
      // إضافة الملف - استخدام اسم ملف ASCII فقط لتجنب مشاكل Telegram
      final originalFileName = file.uri.pathSegments.last;
      final fileBytes = await file.readAsBytes();
      // تحويل اسم الملف إلى ASCII فقط (استبدال الأحرف العربية بـ underscore)
      final safeFileName = _sanitizeFileNameForTelegram(originalFileName);
      bodyParts.add(utf8.encode('--$boundary\r\n'));
      bodyParts.add(utf8.encode('Content-Disposition: form-data; name="document"; filename="$safeFileName"\r\n'));
      bodyParts.add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'));
      bodyParts.add(fileBytes);
      bodyParts.add(utf8.encode('\r\n'));
      
      // إنهاء
      bodyParts.add(utf8.encode('--$boundary--\r\n'));
      
      // دمج كل الأجزاء
      final body = bodyParts.expand((x) => x).toList();
      request.contentLength = body.length;
      request.add(body);
      
      final response = await request.close().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال (60 ثانية)');
        },
      );
      
      final responseBody = await response.transform(const SystemEncoding().decoder).join();
      httpClient.close();
      
      if (response.statusCode == 200) {
        print('✅ تم إرسال الملف بنجاح');
        return TelegramSendResult.ok();
      } else {
        final errorMsg = 'فشل إرسال الملف';
        _lastError = '$errorMsg - كود: ${response.statusCode} - $responseBody';
        print('❌ $_lastError');
        return TelegramSendResult.error(errorMsg,
            details: responseBody,
            statusCode: response.statusCode);
      }
    } catch (e) {
      _lastError = 'خطأ في إرسال الملف: $e';
      print('❌ $_lastError');
      return TelegramSendResult.error('خطأ في الاتصال', details: e.toString());
    }
  }

  /// إرسال ملف إلى قناة Telegram (للتوافق مع الكود القديم)
  Future<bool> sendDocument({
    required File file,
    String? caption,
  }) async {
    final result = await sendDocumentWithDetails(file: file, caption: caption);
    return result.success;
  }

  /// إرسال رسالة نصية إلى القناة مع تفاصيل الخطأ
  Future<TelegramSendResult> sendMessageWithDetails(String text) async {
    _lastError = null;
    
    if (!isConfigured) {
      _lastError = 'إعدادات Telegram غير مكتملة';
      return TelegramSendResult.error('إعدادات Telegram غير مكتملة');
    }

    try {
      final channelId = await _getChannelId();
      print('📤 إرسال رسالة إلى القناة: $channelId');
      
      // استخدام HttpClient مخصص لتجاوز مشاكل SSL
      final httpClient = HttpClient()
        ..badCertificateCallback = (X509Certificate cert, String host, int port) {
          return host.contains('telegram.org') || host.contains('api.telegram.org');
        };
      
      final uri = Uri.parse('https://api.telegram.org/bot$_botToken/sendMessage');
      final request = await httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      
      final body = 'chat_id=${Uri.encodeComponent(channelId)}&text=${Uri.encodeComponent(text)}&parse_mode=HTML';
      request.write(body);
      
      final response = await request.close().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('انتهت مهلة الاتصال (30 ثانية)');
        },
      );
      
      final responseBody = await response.transform(const SystemEncoding().decoder).join();
      httpClient.close();

      if (response.statusCode == 200) {
        print('✅ تم إرسال الرسالة بنجاح');
        return TelegramSendResult.ok();
      } else {
        final errorMsg = 'فشل إرسال الرسالة';
        _lastError = '$errorMsg - كود: ${response.statusCode} - $responseBody';
        print('❌ $_lastError');
        return TelegramSendResult.error(errorMsg,
            details: responseBody,
            statusCode: response.statusCode);
      }
    } catch (e) {
      _lastError = 'خطأ في إرسال الرسالة: $e';
      print('❌ $_lastError');
      return TelegramSendResult.error('خطأ في الاتصال', details: e.toString());
    }
  }

  /// إرسال رسالة نصية إلى القناة (للتوافق مع الكود القديم)
  Future<bool> sendMessage(String text) async {
    final result = await sendMessageWithDetails(text);
    return result.success;
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
  Future<void> saveLastUploadTime({DateTime? time}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUploadTimeKey, (time ?? DateTime.now()).toIso8601String());
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

  /// بناء نص الملخص الشهري بصيغة Telegram HTML
  Future<String> buildMonthlySummaryMessage() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startStr = startOfMonth.toIso8601String().split('T')[0];
    final endStr = now.toIso8601String().split('T')[0];

    final db = DatabaseService();
    final database = await db.database;
    final nf = NumberFormat('#,##0', 'en_US');

    // 🔎 فلتر «الفواتير المحلية فقط»: عند تفعيله من الإعدادات يرسل كل جهاز
    // مبيعاته هو فقط (is_created_by_me = 1) دون الواردة من المزامنة —
    // لمنع التقارير المزدوجة عندما ترسل عدة أجهزة لنفس جروب التليجرام.
    await DatabaseService.ensureInvoiceOwnershipFlags();
    final settings0 = await SettingsManager.getAppSettings();
    final onlyLocal = settings0.telegramOnlyLocalInvoices;
    final localFilter = onlyLocal ? "AND is_created_by_me = 1" : "";

    final invoices = await database.rawQuery('''
      SELECT
        id, total_amount, discount, amount_paid_on_invoice, payment_type
      FROM invoices
      WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
        AND status = 'محفوظة'
        $localFilter
    ''', [startStr, endStr]);

    int cashCount = 0;
    double cashTotal = 0.0;
    List<int> cashInvoiceIds = [];

    int debtCount = 0;
    double debtTotal = 0.0;
    List<int> debtInvoiceIds = [];

    int mixedCount = 0;
    double mixedTotal = 0.0;
    double mixedPaidAmount = 0.0;
    double mixedDebtAmount = 0.0;
    List<int> mixedInvoiceIds = [];

    for (final inv in invoices) {
      final id = inv['id'] as int;
      final total = (inv['total_amount'] as num?)?.toDouble() ?? 0.0;
      final discount = (inv['discount'] as num?)?.toDouble() ?? 0.0;
      final paid = (inv['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
      final netTotal = total - discount;

      if (paid >= netTotal && netTotal > 0) {
        cashCount++;
        cashTotal += netTotal;
        cashInvoiceIds.add(id);
      } else if (paid <= 0) {
        debtCount++;
        debtTotal += netTotal;
        debtInvoiceIds.add(id);
      } else {
        mixedCount++;
        mixedTotal += netTotal;
        mixedPaidAmount += paid;
        mixedDebtAmount += (netTotal - paid);
        mixedInvoiceIds.add(id);
      }
    }

    double cashProfit = 0.0;
    double debtProfit = 0.0;
    double mixedProfit = 0.0;

    final products = await db.getAllProducts();
    final productMap = <String, dynamic>{};
    for (final p in products) {
      productMap[p.name] = p;
    }

    for (final invId in cashInvoiceIds) {
      cashProfit += await _calculateInvoiceProfitById(db, invId, productMap);
    }
    for (final invId in debtInvoiceIds) {
      debtProfit += await _calculateInvoiceProfitById(db, invId, productMap);
    }
    for (final invId in mixedInvoiceIds) {
      mixedProfit += await _calculateInvoiceProfitById(db, invId, productMap);
    }

    final invoiceTotalProfit = cashProfit + debtProfit + mixedProfit;
    final totalCount = cashCount + debtCount + mixedCount;
    final totalAmount = cashTotal + debtTotal + mixedTotal;

    double returnsTotal = 0.0;
    final invoiceReturnsData = await database.rawQuery('''
      SELECT
        COALESCE(SUM(return_amount), 0) as total
      FROM invoices
      WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
        AND status = 'محفوظة'
        $localFilter
    ''', [startStr, endStr]);

    if (invoiceReturnsData.isNotEmpty) {
      returnsTotal = (invoiceReturnsData.first['total'] as num?)?.toDouble() ?? 0.0;
    }

    double manualReturnsTotal = 0.0;
    final manualReturnsData = await database.rawQuery('''
      SELECT 
        COALESCE(SUM(amount), 0) as total
      FROM returns
      WHERE DATE(return_date) >= ? AND DATE(return_date) <= ?
    ''', [startStr, endStr]);

    if (manualReturnsData.isNotEmpty) {
      manualReturnsTotal = (manualReturnsData.first['total'] as num?)?.toDouble() ?? 0.0;
    }

    final manualPaymentReturnData = await database.rawQuery('''
      SELECT 
        COALESCE(SUM(ABS(amount_changed)), 0) as total
      FROM transactions
      WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
        AND transaction_type = 'manual_payment_return'
        AND is_created_by_me = 1
        AND invoice_id IS NULL
        AND id NOT IN (SELECT COALESCE(transaction_id, 0) FROM returns)
    ''', [startStr, endStr]);

    final extraManualPaymentReturn = (manualPaymentReturnData.isNotEmpty)
        ? (manualPaymentReturnData.first['total'] as num?)?.toDouble() ?? 0.0
        : 0.0;

    final grandTotalReturns = returnsTotal + manualReturnsTotal + extraManualPaymentReturn;

    final manualDebtData = await database.rawQuery('''
      SELECT COUNT(*) as count, COALESCE(SUM(amount_changed), 0) as total
      FROM transactions
      WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
        AND transaction_type IN ('manual_debt', 'opening_balance')
        AND is_created_by_me = 1 AND invoice_id IS NULL
    ''', [startStr, endStr]);

    final manualDebtCount = manualDebtData.first['count'] as int? ?? 0;
    final manualDebtTotal = (manualDebtData.first['total'] as num?)?.toDouble() ?? 0.0;

    final manualDebtProfitData = await database.rawQuery('''
      SELECT COALESCE(SUM(amount_changed), 0) as total
      FROM transactions
      WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
        AND transaction_type = 'manual_debt'
        AND is_created_by_me = 1 AND invoice_id IS NULL
    ''', [startStr, endStr]);

    final manualDebtOnlyTotal = (manualDebtProfitData.first['total'] as num?)?.toDouble() ?? 0.0;
    final manualDebtProfit = manualDebtOnlyTotal * 0.15;

    final manualPaymentData = await database.rawQuery('''
      SELECT COUNT(*) as count, COALESCE(SUM(ABS(amount_changed)), 0) as total
      FROM transactions
      WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
        AND transaction_type = 'manual_payment'
        AND is_created_by_me = 1 AND invoice_id IS NULL
    ''', [startStr, endStr]);

    final manualPaymentCount = manualPaymentData.first['count'] as int? ?? 0;
    final manualPaymentTotal = (manualPaymentData.first['total'] as num?)?.toDouble() ?? 0.0;

    final grandTotalProfit = invoiceTotalProfit + manualDebtProfit;

    final settings = await SettingsManager.getAppSettings();
    final branchName = settings.branchName;

    final monthNames = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    final monthName = monthNames[now.month - 1];

    return '''
📊 <b>ملخص شهر $monthName ${now.year}</b>
🏪 <b>$branchName</b>
📅 من ${startOfMonth.day}/${startOfMonth.month}/${startOfMonth.year} إلى ${now.day}/${now.month}/${now.year}
${onlyLocal ? '📲 مبيعات هذا الجهاز فقط' : '🏬 مبيعات كل الأجهزة (محلي + مزامنة)'}

═════════════════
🧾 <b>الفواتير:</b>
═════════════════
💵 نقدية: $cashCount فاتورة | ${nf.format(cashTotal)} د.ع
📝 دين: $debtCount فاتورة | ${nf.format(debtTotal)} د.ع
🔄 مدمجة: $mixedCount فاتورة | ${nf.format(mixedTotal)} د.ع
   • المدفوع منها: ${nf.format(mixedPaidAmount)} د.ع
   • الدين منها: ${nf.format(mixedDebtAmount)} د.ع
─────────────────
📦 <b>الإجمالي:</b> $totalCount فاتورة | ${nf.format(totalAmount)} د.ع

══════════════════
📈 <b>أرباح الفواتير:</b>
══════════════════
💵 أرباح النقدية: ${nf.format(cashProfit)} د.ع
📝 أرباح الدين: ${nf.format(debtProfit)} د.ع
🔄 أرباح المدمجة: ${nf.format(mixedProfit)} د.ع
─────────────────
💰 <b>إجمالي أرباح الفواتير:</b> ${nf.format(invoiceTotalProfit)} د.ع

═══════════════════
💳 <b>معاملات إضافة الدين (يدوية):</b>
═══════════════════
   • العدد: $manualDebtCount معاملة
   • المبلغ: ${nf.format(manualDebtTotal)} د.ع
   • الأرباح (15%): ${nf.format(manualDebtProfit)} د.ع

══════════════════
💵 <b>معاملات تسديد الدين (يدوية):</b>
═════════════════
   • العدد: $manualPaymentCount معاملة
   • المبلغ: ${nf.format(manualPaymentTotal)} د.ع

════════════════
🏆 <b>إجمالي الأرباح الكلي:</b> ${nf.format(grandTotalProfit)} د.ع
══════════════════
🔄 <b>إجمالي المرتجعات:</b>
═════════════════
   • بضاعة راجعة: ${nf.format(returnsTotal)} د.ع
   • تسديد دين راجع: ${nf.format(manualReturnsTotal + extraManualPaymentReturn)} د.ع
   • الإجمالي: ${nf.format(grandTotalReturns)} د.ع
═══════════════
''';
  }

  /// إرسال ملخص شهري إلى Telegram
  /// يحسب البيانات من أول الشهر الحالي إلى تاريخ اليوم
  Future<bool> sendMonthlySummary() async {
    final result = await sendMonthlySummaryWithDetails();
    return result.success;
  }

  /// 📅 بناء نص الإحصائيات اليومية بصيغة Telegram HTML.
  ///
  /// يحترم إعداد «الفواتير المحلية فقط»: عند تفعيله يرسل كل جهاز مبيعات
  /// يومه هو فقط، فتصل الإدارة رسالة مستقلة من كل كاشير بدل تقارير مزدوجة.
  Future<String> buildDailyStatisticsMessage() async {
    final now = DateTime.now();
    final nowStr = now.toIso8601String().split('T')[0];

    final db = DatabaseService();
    final database = await db.database;
    final nf = NumberFormat('#,##0', 'en_US');

    // 🔎 نفس فلتر الملخص الشهري (محلية فقط / الكل)
    await DatabaseService.ensureInvoiceOwnershipFlags();
    final settings = await SettingsManager.getAppSettings();
    final onlyLocal = settings.telegramOnlyLocalInvoices;
    final localFilter = onlyLocal ? "AND is_created_by_me = 1" : "";

    // 🧾 إحصائيات فواتير اليوم
    final salesResult = await database.rawQuery('''
      SELECT
        COUNT(*) as count,
        COALESCE(SUM(total_amount), 0) as total,
        COALESCE(SUM(discount), 0) as discount,
        COALESCE(SUM(CASE WHEN payment_type = 'نقد' THEN total_amount ELSE 0 END), 0) as cash_total,
        COALESCE(SUM(CASE WHEN payment_type = 'دين' THEN total_amount ELSE 0 END), 0) as debt_total,
        COALESCE(SUM(amount_paid_on_invoice), 0) as paid_total,
        COALESCE(SUM(return_amount), 0) as returns_total
      FROM invoices
      WHERE DATE(invoice_date) = ?
        AND status = 'محفوظة'
        $localFilter
    ''', [nowStr]);

    final s = salesResult.first;
    final invoiceCount = (s['count'] as num?)?.toInt() ?? 0;
    final totalSales = (s['total'] as num?)?.toDouble() ?? 0.0;
    final totalDiscount = (s['discount'] as num?)?.toDouble() ?? 0.0;
    final cashSales = (s['cash_total'] as num?)?.toDouble() ?? 0.0;
    final debtSales = (s['debt_total'] as num?)?.toDouble() ?? 0.0;
    final paidOnInvoices = (s['paid_total'] as num?)?.toDouble() ?? 0.0;
    final returnsTotal = (s['returns_total'] as num?)?.toDouble() ?? 0.0;

    // 💵 تسديدات الدين اليدوية اليوم (من هذا الجهاز كما في الملخص الشهري)
    final manualPaymentData = await database.rawQuery('''
      SELECT COUNT(*) as count, COALESCE(SUM(ABS(amount_changed)), 0) as total
      FROM transactions
      WHERE DATE(transaction_date) = ?
        AND transaction_type = 'manual_payment'
        AND is_created_by_me = 1 AND invoice_id IS NULL
    ''', [nowStr]);
    final manualPaymentCount =
        (manualPaymentData.first['count'] as num?)?.toInt() ?? 0;
    final manualPaymentTotal =
        (manualPaymentData.first['total'] as num?)?.toDouble() ?? 0.0;

    final branchName = settings.branchName;

    return '''
📋 <b>إحصائيات اليوم ${now.day}/${now.month}/${now.year}</b>
🏪 <b>$branchName</b>
${onlyLocal ? '📲 مبيعات هذا الجهاز فقط' : '🏬 مبيعات كل الأجهزة (محلي + مزامنة)'}

🧾 <b>الفواتير:</b> $invoiceCount فاتورة
💰 <b>إجمالي المبيعات:</b> ${nf.format(totalSales)} د.ع
💵 نقدية: ${nf.format(cashSales)} د.ع
📝 دين: ${nf.format(debtSales)} د.ع
💳 مدفوع على الفواتير: ${nf.format(paidOnInvoices)} د.ع
🏷️ خصومات: ${nf.format(totalDiscount)} د.ع
🔄 مرتجعات الفواتير: ${nf.format(returnsTotal)} د.ع
─────────────────
💵 تسديدات دين يدوية: $manualPaymentCount | ${nf.format(manualPaymentTotal)} د.ع
''';
  }

  /// 📤 إرسال الإحصائيات اليومية إلى Telegram مع تفاصيل الخطأ.
  Future<TelegramSendResult> sendDailyStatistics() async {
    _lastError = null;

    if (!isConfigured) {
      _lastError = 'إعدادات Telegram غير مكتملة';
      return TelegramSendResult.error('إعدادات Telegram غير مكتملة');
    }

    try {
      final message = await buildDailyStatisticsMessage();
      return await sendMessageWithDetails(message);
    } catch (e) {
      _lastError = 'خطأ في إعداد الإحصائيات اليومية: $e';
      print('❌ $_lastError');
      return TelegramSendResult.error('خطأ في إعداد الإحصائيات اليومية',
          details: e.toString());
    }
  }
  
  /// إرسال ملخص شهري إلى Telegram مع تفاصيل الخطأ
  Future<TelegramSendResult> sendMonthlySummaryWithDetails() async {
    _lastError = null;
    
    if (!isConfigured) {
      _lastError = 'إعدادات Telegram غير مكتملة';
      return TelegramSendResult.error('إعدادات Telegram غير مكتملة');
    }

    try {
      final message = await buildMonthlySummaryMessage();
      return await sendMessageWithDetails(message);
    } catch (e) {
      _lastError = 'خطأ في إعداد الملخص الشهري: $e';
      print('❌ $_lastError');
      return TelegramSendResult.error('خطأ في إعداد الملخص', details: e.toString());
    }
  }

  /// حساب ربح فاتورة معينة بناءً على ID
  Future<double> _calculateInvoiceProfitById(
    DatabaseService db,
    int invoiceId,
    Map<String, dynamic> productMap,
  ) async {
    try {
      final database = await db.database;
      
      // جلب الخصم
      final invoiceData = await database.rawQuery(
        'SELECT discount FROM invoices WHERE id = ?',
        [invoiceId],
      );
      final discount = invoiceData.isNotEmpty
          ? (invoiceData.first['discount'] as num?)?.toDouble() ?? 0.0
          : 0.0;
      
      // جلب عناصر الفاتورة
      final items = await database.rawQuery(
        'SELECT * FROM invoice_items WHERE invoice_id = ?',
        [invoiceId],
      );
      
      double totalProfit = 0.0;
      
      for (final item in items) {
        final sellingPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
        final acp = (item['actual_cost_price'] as num?)?.toDouble();
        final itemBaseCost = (item['cost_price'] as num?)?.toDouble() ?? 0.0;
        
        final saleType = item['sale_type'] as String? ?? '';
        final qi = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
        final ql = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
        final uilu = (item['units_in_large_unit'] as num?)?.toDouble() ?? 0.0;
        
        final productName = item['product_name'] as String? ?? '';
        final product = productMap[productName];
        
        final String productUnit = product?.unit ?? '';
        final double lengthPerUnit = product?.lengthPerUnit ?? 1.0;
        final double productBaseCost = product?.costPrice ?? 0.0;
        final Map<String, double> unitCosts = product?.getUnitCostsMap() ?? {};
        
        final bool soldAsLargeUnit = ql > 0;
        final double saleUnitsCount = soldAsLargeUnit ? ql : qi;
        
        double costPerSaleUnit;
        
        if (acp != null && acp > 0) {
          costPerSaleUnit = acp;
        } else if (soldAsLargeUnit) {
          if (unitCosts.containsKey(saleType)) {
            costPerSaleUnit = unitCosts[saleType]!;
          } else if (productUnit == 'meter' && saleType == 'لفة') {
            costPerSaleUnit = productBaseCost * lengthPerUnit;
          } else if (uilu > 0) {
            costPerSaleUnit = productBaseCost * uilu;
          } else {
            costPerSaleUnit = productBaseCost;
          }
        } else {
          costPerSaleUnit = itemBaseCost > 0 ? itemBaseCost : productBaseCost;
        }
        
        // إذا كانت التكلفة صفر، افترض أن الربح 10%
        if (costPerSaleUnit <= 0 && sellingPrice > 0) {
          costPerSaleUnit = sellingPrice * 0.9;
        }
        
        final lineAmount = sellingPrice * saleUnitsCount;
        final lineCostTotal = costPerSaleUnit * saleUnitsCount;
        
        totalProfit += (lineAmount - lineCostTotal);
      }
      
      return totalProfit - discount;
    } catch (e) {
      print('Error calculating invoice profit: $e');
      return 0.0;
    }
  }
  
  /// تنظيف اسم الملف ليكون ASCII فقط (لتجنب مشاكل Telegram)
  String _sanitizeFileNameForTelegram(String fileName) {
    // استخراج الامتداد
    final lastDot = fileName.lastIndexOf('.');
    final extension = lastDot > 0 ? fileName.substring(lastDot) : '';
    final nameWithoutExt = lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
    
    // استبدال الأحرف غير ASCII بـ underscore
    final sanitized = nameWithoutExt
        .replaceAll(RegExp(r'[^\x00-\x7F]'), '_') // استبدال non-ASCII
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_') // استبدال الأحرف الممنوعة
        .replaceAll(RegExp(r'_+'), '_') // دمج underscores متتالية
        .replaceAll(RegExp(r'^_|_$'), ''); // إزالة underscore من البداية والنهاية
    
    // إذا أصبح الاسم فارغاً، استخدم اسم افتراضي
    final finalName = sanitized.isEmpty ? 'invoice_${DateTime.now().millisecondsSinceEpoch}' : sanitized;
    
    return '$finalName$extension';
  }
}
