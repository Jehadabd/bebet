// خدمة تصدير الفواتير الجديدة وإرسالها إلى Telegram
// تستخدم نفس تنسيق PDF الموجود في زر "طباعة الفاتورة"
import 'dart:io';
import 'dart:convert';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import 'database_service.dart';
import 'settings_manager.dart';
import 'telegram_backup_service.dart';
import 'discord_backup_service.dart';
import 'pdf_header.dart';

class TelegramInvoiceExportService {
  final DatabaseService _db = DatabaseService();
  final TelegramBackupService _telegram = TelegramBackupService();

  /// تصدير الفواتير المُنشأة بعد تاريخ معين وإرسالها إلى Telegram و/أو Discord
  Future<TelegramExportResult> exportAndSendNewInvoices({
    required DateTime afterDate,
    Function(int current, int total, String status)? onProgress,
    bool sendToTelegram = true,
    bool sendToDiscord = true,
  }) async {
    final result = TelegramExportResult();
    
    try {
      // جلب الفواتير الجديدة
      onProgress?.call(0, 0, 'جاري جلب الفواتير الجديدة...');
      final invoices = await _db.getInvoicesCreatedAfter(afterDate);
      
      if (invoices.isEmpty) {
        result.success = true;
        result.message = 'لا توجد فواتير جديدة منذ آخر رفع';
        return result;
      }

      result.totalCount = invoices.length;
      
      // التحقق من Discord
      final discordService = DiscordBackupService()..loadSettings();
      final bool discordEnabled = sendToDiscord && discordService.isEnabled;
      
      // تحميل الموارد
      onProgress?.call(0, invoices.length, 'جاري تحميل الموارد...');
      final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
      final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
      final alnaserFont = pw.Font.ttf(await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
      final appSettings = await SettingsManager.getAppSettings();
      final branchName = appSettings.branchName;
      final allProducts = await _db.getAllProducts();
      
      // إنشاء خريطة للمنتجات للبحث السريع
      final Map<String, Product> productMap = {
        for (var p in allProducts) p.name: p
      };

      // إرسال رسالة بداية
      final startMsg = '📋 بدء إرسال ${invoices.length} فاتورة جديدة\n'
          '🏪 $branchName\n'
          '📅 منذ: ${_formatDateTime(afterDate)}';
      if (sendToTelegram) await _telegram.sendMessage(startMsg);
      if (discordEnabled) await discordService.sendMessage(startMsg);

      // إنشاء مجلد مؤقت
      final tempDir = await getTemporaryDirectory();
      final exportDir = Directory('${tempDir.path}/telegram_invoices_${DateTime.now().millisecondsSinceEpoch}');
      await exportDir.create(recursive: true);

      // معالجة كل فاتورة
      for (var i = 0; i < invoices.length; i++) {
        final invoice = invoices[i];
        onProgress?.call(i + 1, invoices.length, 'فاتورة #${invoice.id} - ${invoice.customerName}');
        
        try {
          // جلب أصناف الفاتورة
          final items = await _db.getInvoiceItems(invoice.id!);
          
          if (items.isEmpty) {
            result.skippedCount++;
            continue;
          }

          // حساب القيم المالية
          final itemsTotal = items.fold(0.0, (sum, item) => sum + item.itemTotal);
          final afterDiscount = (itemsTotal + invoice.loadingFee) - invoice.discount;
          final remaining = afterDiscount - invoice.amountPaidOnInvoice;
          
          // حساب إجمالي الربح - نفس منطق create_invoice_screen.dart
          final invoiceProfit = _calculateInvoiceProfit(items, productMap, invoice.discount);
          
          double previousDebt = 0.0;
          double currentDebt = 0.0;
          if (invoice.customerId != null) {
            final customer = await _db.getCustomerById(invoice.customerId!);
            if (customer != null) {
              currentDebt = customer.currentTotalDebt;
              previousDebt = currentDebt - remaining;
            }
          }

          // إنشاء PDF باستخدام نفس التنسيق الموجود في invoice_actions.dart
          final pdf = await _generateInvoicePdfLikeOriginal(
            invoice: invoice,
            items: items,
            allProducts: allProducts,
            font: font,
            alnaserFont: alnaserFont,
            logoImage: logoImage,
            appSettings: appSettings,
            itemsTotal: itemsTotal,
            afterDiscount: afterDiscount,
            remaining: remaining,
            previousDebt: previousDebt,
            currentDebt: currentDebt,
          );

          // حفظ PDF مؤقتاً
          final safeCustomerName = _sanitizeFileName(invoice.customerName);
          final safeBranchName = _sanitizeFileName(branchName);
          final fileName = '${safeBranchName}_فاتورة_${invoice.id}_$safeCustomerName.pdf';
          final pdfFile = File('${exportDir.path}/$fileName');
          await pdfFile.writeAsBytes(await pdf.save());

          // وصف الفاتورة المشترك
          final caption = '🧾 فاتورة #${invoice.id}\n'
              '🏪 $branchName\n'
              '👤 ${invoice.customerName}\n'
              '💰 ${_formatNumber(afterDiscount)} د.ع\n'
              '📈 الربح: ${_formatNumber(invoiceProfit)} د.ع\n'
              '📅 ${_formatDate(invoice.invoiceDate)}';
          
          bool sentSuccessfully = false;
          
          // إرسال إلى Telegram
          if (sendToTelegram) {
            final sent = await _telegram.sendDocument(file: pdfFile, caption: caption);
            if (sent) sentSuccessfully = true;
          }
          
          // إرسال إلى Discord
          if (discordEnabled) {
            final sent = await discordService.sendBackupFile(pdfFile, caption: caption);
            if (sent) sentSuccessfully = true;
          }
          
          if (sentSuccessfully) {
            result.sentCount++;
          } else {
            result.failedCount++;
          }

          // تأخير لتجنب rate limiting
          await Future.delayed(const Duration(milliseconds: 3500));
          
        } catch (e) {
          result.failedCount++;
        }
      }

      // تنظيف المجلد المؤقت
      try {
        await exportDir.delete(recursive: true);
      } catch (_) {}

      // إرسال رسالة نهاية
      final endMsg = '✅ تم إرسال ${result.sentCount} فاتورة بنجاح\n'
          '🏪 $branchName\n'
          '${result.failedCount > 0 ? '❌ فشل: ${result.failedCount}\n' : ''}'
          '${result.skippedCount > 0 ? '⏭️ تم تخطي: ${result.skippedCount}\n' : ''}';
      if (sendToTelegram) await _telegram.sendMessage(endMsg);
      if (discordEnabled) await discordService.sendMessage(endMsg);

      result.success = true;
      result.message = 'تم إرسال ${result.sentCount} فاتورة';
      
    } catch (e) {
      result.success = false;
      result.message = 'خطأ: $e';
    }

    return result;
  }

  /// إنشاء PDF بنفس التنسيق الموجود في invoice_actions.dart
  Future<pw.Document> _generateInvoicePdfLikeOriginal({
    required Invoice invoice,
    required List<InvoiceItem> items,
    required List<Product> allProducts,
    required pw.Font font,
    required pw.Font alnaserFont,
    required pw.MemoryImage logoImage,
    required dynamic appSettings,
    required double itemsTotal,
    required double afterDiscount,
    required double remaining,
    required double previousDebt,
    required double currentDebt,
  }) async {
    final pdf = pw.Document();
    
    const itemsPerPage = 19;
    final totalPages = (items.length / itemsPerPage).ceil().clamp(1, 9999);

    for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final start = pageIndex * itemsPerPage;
      final end = (start + itemsPerPage) > items.length ? items.length : start + itemsPerPage;
      final pageItems = items.sublist(start, end);
      final isLastPage = pageIndex == totalPages - 1;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.only(top: 0, bottom: 2, left: 10, right: 10),
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Stack(
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // الهيدر الموحد
                      buildPdfHeader(font, alnaserFont, logoImage, appSettings: appSettings),
                      pw.SizedBox(height: 4),
                      // معلومات الفاتورة
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('السيد: ${invoice.customerName}',
                              style: pw.TextStyle(font: font, fontSize: 12)),
                          pw.Text(
                              'العنوان: ${invoice.customerAddress?.isNotEmpty == true ? invoice.customerAddress : ' ______'}',
                              style: pw.TextStyle(font: font, fontSize: 11)),
                          pw.Text('رقم الفاتورة: ${invoice.id}',
                              style: pw.TextStyle(font: font, fontSize: 10)),
                          pw.Text(
                              'الوقت: ${invoice.createdAt?.hour.toString().padLeft(2, '0') ?? DateTime.now().hour.toString().padLeft(2, '0')}:${invoice.createdAt?.minute.toString().padLeft(2, '0') ?? DateTime.now().minute.toString().padLeft(2, '0')}',
                              style: pw.TextStyle(font: font, fontSize: 11)),
                          pw.Text(
                              'التاريخ: ${invoice.invoiceDate.year}/${invoice.invoiceDate.month}/${invoice.invoiceDate.day}',
                              style: pw.TextStyle(font: font, fontSize: 11)),
                        ],
                      ),
                      pw.Divider(height: 5, thickness: 0.5),
                      // جدول الفاتورة - نفس الترتيب في invoice_actions.dart
                      pw.Table(
                        border: pw.TableBorder.all(width: 0.2),
                        columnWidths: const {
                          0: pw.FixedColumnWidth(90),  // المبلغ
                          1: pw.FixedColumnWidth(70),  // السعر
                          2: pw.FixedColumnWidth(65),  // عدد الوحدات
                          3: pw.FixedColumnWidth(90),  // العدد
                          4: pw.FlexColumnWidth(0.8),  // التفاصيل
                          5: pw.FixedColumnWidth(45),  // ID
                          6: pw.FixedColumnWidth(20),  // ت
                        },
                        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                        children: [
                          pw.TableRow(
                            children: [
                              _headerCell('المبلغ', font, color: PdfColor.fromInt(appSettings.itemTotalColor)),
                              _headerCell('السعر', font, color: PdfColor.fromInt(appSettings.itemPriceColor)),
                              _headerCell('عدد الوحدات', font),
                              _headerCell('العدد', font, color: PdfColor.fromInt(appSettings.itemQuantityColor)),
                              _headerCell('التفاصيل', font, color: PdfColor.fromInt(appSettings.itemDetailsColor)),
                              _headerCell('ID', font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                              _headerCell('ت', font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                            ],
                          ),
                          ...pageItems.asMap().entries.map((entry) {
                            final index = entry.key + (pageIndex * itemsPerPage);
                            final item = entry.value;
                            final quantity = (item.quantityIndividual ?? item.quantityLargeUnit ?? 0.0);
                            Product? product;
                            try {
                              product = allProducts.firstWhere((p) => p.name == item.productName);
                            } catch (e) {
                              product = null;
                            }
                            final idText = _formatProductId5(product?.id);
                            return pw.TableRow(
                              children: [
                                _dataCell(_formatNumber(item.itemTotal), font, color: PdfColor.fromInt(appSettings.itemTotalColor)),
                                _dataCell(_formatNumber(item.appliedPrice), font, color: PdfColor.fromInt(appSettings.itemPriceColor)),
                                _dataCell(_buildUnitConversionString(item, product), font),
                                _dataCell('${_formatNumber(quantity)} ${item.saleType ?? ''}', font, color: PdfColor.fromInt(appSettings.itemQuantityColor)),
                                _dataCell(item.productName, font, align: pw.TextAlign.right, color: PdfColor.fromInt(appSettings.itemDetailsColor)),
                                _dataCell(idText, font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                                _dataCell('${index + 1}', font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                      pw.Divider(height: 4, thickness: 0.4),
                      // الملخص في الصفحة الأخيرة
                      if (isLastPage) ...[
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.end,
                              children: [
                                _summaryRow('الاجمالي قبل الخصم:', itemsTotal + invoice.loadingFee, font),
                                pw.SizedBox(width: 10),
                                _summaryRow('أجور التحميل:', invoice.loadingFee, font, color: PdfColor.fromInt(appSettings.loadingFeesColor)),
                                pw.SizedBox(width: 10),
                                _summaryRow('الخصم:', invoice.discount, font),
                                pw.SizedBox(width: 10),
                                _summaryRow('الاجمالي بعد الخصم:', afterDiscount, font),
                                pw.SizedBox(width: 10),
                                _summaryRow('المبلغ المدفوع:', invoice.amountPaidOnInvoice, font, color: PdfColor.fromInt(appSettings.paidAmountColor)),
                              ],
                            ),
                            pw.SizedBox(height: 6),
                            if ((invoice.status == 'محفوظة') && !(invoice.isLocked)) ...[
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.end,
                                children: [
                                  _summaryRow('المبلغ المتبقي:', remaining, font, color: PdfColor.fromInt(appSettings.remainingAmountColor)),
                                  pw.SizedBox(width: 10),
                                  _summaryRow('الدين السابق:', previousDebt, font),
                                  pw.SizedBox(width: 10),
                                  _summaryRow('المبلغ المطلوب الحالي:', currentDebt, font),
                                ],
                              ),
                            ],
                          ],
                        ),
                        pw.SizedBox(height: 6),
                        pw.Center(
                            child: pw.Text('شكراً لتعاملكم معنا',
                                style: pw.TextStyle(font: font, fontSize: 11))),
                      ],
                      pw.Align(
                        alignment: pw.Alignment.center,
                        child: pw.Text(
                          'صفحة ${pageIndex + 1} من $totalPages',
                          style: pw.TextStyle(font: font, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  // العلامة المائية
                  pw.Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: pw.Container(
                      alignment: pw.Alignment.topLeft,
                      padding: const pw.EdgeInsets.only(top: 130, left: 5),
                      child: pw.Transform.rotate(
                        angle: 0.6,
                        child: pw.Opacity(
                          opacity: 0.20,
                          child: pw.Text(
                            'الناصر',
                            style: pw.TextStyle(
                              font: alnaserFont,
                              fontFallback: [font],
                              fontSize: 200,
                              color: PdfColors.green,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }
    return pdf;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // الدوال المساعدة - نفس الدوال الموجودة في invoice_actions.dart
  // ═══════════════════════════════════════════════════════════════════════════

  pw.Widget _headerCell(String text, pw.Font font, {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font, fontSize: 13, fontWeight: pw.FontWeight.bold, color: color ?? PdfColors.black),
          textAlign: pw.TextAlign.center),
    );
  }

  pw.Widget _dataCell(String text, pw.Font font,
      {pw.TextAlign align = pw.TextAlign.center, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font, fontSize: 13, fontWeight: pw.FontWeight.bold, color: color ?? PdfColors.black),
          textAlign: align),
    );
  }

  pw.Widget _summaryRow(String label, num value, pw.Font font, {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 11, color: color)),
          pw.SizedBox(width: 5),
          pw.Text(_formatNumber(value),
              style: pw.TextStyle(font: font, fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  /// تنسيق الأرقام مع فاصلة كل 3 خانات - نفس الدالة في invoice_actions.dart
  String _formatNumber(num value) {
    final formatter = NumberFormat('#,##0.##', 'en_US');
    return formatter.format(value);
  }

  /// تنسيق معرف المنتج - نفس الدالة في invoice_actions.dart
  String _formatProductId5(int? id) {
    if (id == null) return '-----';
    return id.toString().padLeft(5, '0');
  }

  /// بناء سلسلة تحويل الوحدات - نفس الدالة في invoice_actions.dart
  String _buildUnitConversionString(InvoiceItem item, Product? product) {
    if (item.unit == 'meter') {
      if (item.saleType == 'لفة' && item.unitsInLargeUnit != null) {
        return item.unitsInLargeUnit!.toString();
      } else {
        return '';
      }
    }
    if (item.saleType == 'قطعة' || item.saleType == 'متر') {
      return '';
    }
    if (product == null ||
        product.unitHierarchy == null ||
        product.unitHierarchy!.isEmpty) {
      return item.unitsInLargeUnit?.toString() ?? '';
    }
    try {
      final List<dynamic> hierarchy =
          json.decode(product.unitHierarchy!.replaceAll("'", '"'));
      List<String> factors = [];
      for (int i = 0; i < hierarchy.length; i++) {
        final unitName = hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
        final quantity = hierarchy[i]['quantity'];
        factors.add(quantity.toString());
        if (unitName == item.saleType) {
          break;
        }
      }
      if (factors.isEmpty) {
        return item.unitsInLargeUnit?.toString() ?? '';
      }
      return factors.join(' × ');
    } catch (e) {
      return item.unitsInLargeUnit?.toString() ?? '';
    }
  }

  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}/${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}/${dt.month}/${dt.day}';
  }

  /// حساب إجمالي ربح الفاتورة - نفس منطق create_invoice_screen.dart
  double _calculateInvoiceProfit(List<InvoiceItem> items, Map<String, Product> productMap, double discount) {
    double totalProfit = 0.0;
    
    for (var item in items) {
      final double sellingPrice = item.appliedPrice;
      final double? acp = item.actualCostPrice;
      final double itemBaseCost = item.costPrice ?? 0.0;
      
      final String saleType = item.saleType ?? '';
      final double qi = item.quantityIndividual ?? 0.0;
      final double ql = item.quantityLargeUnit ?? 0.0;
      final double uilu = item.unitsInLargeUnit ?? 0.0;
      
      // جلب بيانات المنتج
      final Product? product = productMap[item.productName];
      final String productUnit = product?.unit ?? '';
      final double lengthPerUnit = product?.lengthPerUnit ?? 1.0;
      final double productBaseCost = product?.costPrice ?? 0.0;
      final Map<String, double> unitCosts = product?.getUnitCostsMap() ?? {};
      
      final bool soldAsLargeUnit = ql > 0;
      final double saleUnitsCount = soldAsLargeUnit ? ql : qi;
      
      double costPerSaleUnit;
      
      if (acp != null && acp > 0) {
        // الأولوية 1: استخدام التكلفة الفعلية إذا كانت متوفرة
        costPerSaleUnit = acp;
      } else if (soldAsLargeUnit) {
        // الأولوية 2 و 3: التعامل مع الوحدات الكبيرة
        if (unitCosts.containsKey(saleType)) {
          costPerSaleUnit = unitCosts[saleType]!;
        } else if (productUnit == 'meter' && saleType == 'لفة') {
          // حالة خاصة للفات: التكلفة = التكلفة الأساسية × الطول
          costPerSaleUnit = productBaseCost * lengthPerUnit;
        } else if (uilu > 0) {
          // الافتراضي: التكلفة = التكلفة الأساسية × عدد الوحدات في الوحدة الكبيرة
          costPerSaleUnit = productBaseCost * uilu;
        } else {
          // إذا كان uilu = 0، نحاول حساب من unit_hierarchy
          costPerSaleUnit = _calculateCostFromHierarchy(
            productCost: productBaseCost,
            saleType: saleType,
            unitHierarchyJson: product?.unitHierarchy,
          );
        }
      } else {
        // الأولوية 4: البيع بالوحدات الأساسية (قطعة، متر)
        costPerSaleUnit = itemBaseCost > 0 ? itemBaseCost : productBaseCost;
      }
      
      // إذا كانت التكلفة صفر، افترض أن الربح 10% فقط
      if (costPerSaleUnit <= 0 && sellingPrice > 0) {
        costPerSaleUnit = sellingPrice * 0.9; // 10% ربح
      }
      
      final double lineAmount = sellingPrice * saleUnitsCount;
      final double lineCostTotal = costPerSaleUnit * saleUnitsCount;
      
      totalProfit += (lineAmount - lineCostTotal);
    }
    
    // طرح الخصم من الربح
    return totalProfit - discount;
  }

  /// حساب التكلفة من unit_hierarchy عندما لا تتوفر بيانات أخرى
  double _calculateCostFromHierarchy({
    required double productCost,
    required String saleType,
    required String? unitHierarchyJson,
  }) {
    if (unitHierarchyJson == null || unitHierarchyJson.trim().isEmpty) {
      return productCost;
    }
    
    try {
      final List<dynamic> hierarchy = json.decode(unitHierarchyJson.replaceAll("'", '"'));
      double multiplier = 1.0;
      
      for (final level in hierarchy) {
        final String unitName = (level['unit_name'] ?? level['name'] ?? '').toString();
        final double qty = (level['quantity'] is num)
            ? (level['quantity'] as num).toDouble()
            : double.tryParse(level['quantity'].toString()) ?? 1.0;
        multiplier *= qty;
        
        if (unitName == saleType) {
          return productCost * multiplier;
        }
      }
      
      return productCost;
    } catch (e) {
      return productCost;
    }
  }
}

class TelegramExportResult {
  bool success = false;
  String message = '';
  int totalCount = 0;
  int sentCount = 0;
  int failedCount = 0;
  int skippedCount = 0;
}