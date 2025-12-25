// خدمة إرسال النسخ الاحتياطية إلى Telegram
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'settings_manager.dart';
import 'database_service.dart';

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
      final nf = NumberFormat('#,##0', 'en_US');
      
      // جلب جميع الفواتير المحفوظة في الفترة
      final invoices = await database.rawQuery('''
        SELECT 
          id, total_amount, discount, amount_paid_on_invoice, payment_type
        FROM invoices
        WHERE DATE(invoice_date) >= ? AND DATE(invoice_date) <= ?
          AND status = 'محفوظة'
      ''', [startStr, endStr]);
      
      // تصنيف الفواتير
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
        
        // تصنيف الفاتورة
        if (paid >= netTotal && netTotal > 0) {
          // نقدية بالكامل
          cashCount++;
          cashTotal += netTotal;
          cashInvoiceIds.add(id);
        } else if (paid <= 0) {
          // دين بالكامل
          debtCount++;
          debtTotal += netTotal;
          debtInvoiceIds.add(id);
        } else {
          // مدمجة (نقد + دين)
          mixedCount++;
          mixedTotal += netTotal;
          mixedPaidAmount += paid;
          mixedDebtAmount += (netTotal - paid);
          mixedInvoiceIds.add(id);
        }
      }
      
      // حساب الأرباح لكل نوع
      double cashProfit = 0.0;
      double debtProfit = 0.0;
      double mixedProfit = 0.0;
      
      // جلب جميع المنتجات لحساب الأرباح
      final products = await db.getAllProducts();
      final productMap = <String, dynamic>{};
      for (final p in products) {
        productMap[p.name] = p;
      }
      
      // حساب أرباح الفواتير النقدية
      for (final invId in cashInvoiceIds) {
        final profit = await _calculateInvoiceProfitById(db, invId, productMap);
        cashProfit += profit;
      }
      
      // حساب أرباح فواتير الدين
      for (final invId in debtInvoiceIds) {
        final profit = await _calculateInvoiceProfitById(db, invId, productMap);
        debtProfit += profit;
      }
      
      // حساب أرباح الفواتير المدمجة
      for (final invId in mixedInvoiceIds) {
        final profit = await _calculateInvoiceProfitById(db, invId, productMap);
        mixedProfit += profit;
      }
      
      final invoiceTotalProfit = cashProfit + debtProfit + mixedProfit;
      final totalCount = cashCount + debtCount + mixedCount;
      final totalAmount = cashTotal + debtTotal + mixedTotal;
      
      // معاملات إضافة الدين اليدوية (من هذا الجهاز فقط، غير مرتبطة بفاتورة)
      // تشمل manual_debt + opening_balance للعدد والمبلغ
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
      
      // حساب ربح المعاملات اليدوية (15% من manual_debt فقط - بدون opening_balance)
      // هذا يطابق الحساب في database_service.dart وشاشة الجرد
      final manualDebtProfitData = await database.rawQuery('''
        SELECT 
          COALESCE(SUM(amount_changed), 0) as total
        FROM transactions
        WHERE DATE(transaction_date) >= ? AND DATE(transaction_date) <= ?
          AND transaction_type = 'manual_debt'
          AND is_created_by_me = 1
          AND invoice_id IS NULL
      ''', [startStr, endStr]);
      
      final manualDebtOnlyTotal = (manualDebtProfitData.first['total'] as num?)?.toDouble() ?? 0.0;
      final manualDebtProfit = manualDebtOnlyTotal * 0.15; // 15% أرباح من manual_debt فقط
      
      // معاملات تسديد الدين اليدوية (من هذا الجهاز فقط، غير مرتبطة بفاتورة)
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
      
      // إجمالي الأرباح الكلي
      final grandTotalProfit = invoiceTotalProfit + manualDebtProfit;
      
      // جلب اسم الفرع من الإعدادات
      final settings = await SettingsManager.getAppSettings();
      final branchName = settings.branchName;
      
      // بناء الرسالة
      final monthNames = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
      ];
      final monthName = monthNames[now.month - 1];
      
      final message = '''
📊 <b>ملخص شهر $monthName ${now.year}</b>
🏪 <b>$branchName</b>
📅 من ${startOfMonth.day}/${startOfMonth.month}/${startOfMonth.year} إلى ${now.day}/${now.month}/${now.year}

═══════════════════════════════
🧾 <b>الفواتير:</b>
═══════════════════════════════
💵 نقدية: $cashCount فاتورة | ${nf.format(cashTotal)} د.ع
📝 دين: $debtCount فاتورة | ${nf.format(debtTotal)} د.ع
🔄 مدمجة: $mixedCount فاتورة | ${nf.format(mixedTotal)} د.ع
   • المدفوع منها: ${nf.format(mixedPaidAmount)} د.ع
   • الدين منها: ${nf.format(mixedDebtAmount)} د.ع
───────────────────────────────
📦 <b>الإجمالي:</b> $totalCount فاتورة | ${nf.format(totalAmount)} د.ع

═══════════════════════════════
📈 <b>أرباح الفواتير:</b>
═══════════════════════════════
💵 أرباح النقدية: ${nf.format(cashProfit)} د.ع
📝 أرباح الدين: ${nf.format(debtProfit)} د.ع
🔄 أرباح المدمجة: ${nf.format(mixedProfit)} د.ع
───────────────────────────────
💰 <b>إجمالي أرباح الفواتير:</b> ${nf.format(invoiceTotalProfit)} د.ع

═══════════════════════════════
💳 <b>معاملات إضافة الدين (يدوية):</b>
═══════════════════════════════
   • العدد: $manualDebtCount معاملة
   • المبلغ: ${nf.format(manualDebtTotal)} د.ع
   • الأرباح (15%): ${nf.format(manualDebtProfit)} د.ع

═══════════════════════════════
💵 <b>معاملات تسديد الدين (يدوية):</b>
═══════════════════════════════
   • العدد: $manualPaymentCount معاملة
   • المبلغ: ${nf.format(manualPaymentTotal)} د.ع

═══════════════════════════════
🏆 <b>إجمالي الأرباح الكلي:</b> ${nf.format(grandTotalProfit)} د.ع
═══════════════════════════════
''';
      
      return await sendMessage(message);
    } catch (e) {
      print('Error sending monthly summary: $e');
      return false;
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
}
