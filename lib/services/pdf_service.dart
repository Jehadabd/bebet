// services/pdf_service.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/customer.dart';
import '../models/account_statement_item.dart';
import 'dart:convert';
import 'settings_manager.dart';
import 'pdf_header.dart';

class PdfService {
  static final PdfService _instance = PdfService._internal();

  factory PdfService() => _instance;

  PdfService._internal();

  Future<File> generateDailyReport(List<Customer> customers) async {
    // تحميل الخط العربي Amiri
    final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);
    // تحميل الشعار الجديد
    final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final pdf = pw.Document();

    String fmt(num v) => NumberFormat('#,##0', 'en_US').format(v);

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(
            base: ttf,
            bold: ttf,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
        build: (context) => [
          // العنوان الرئيسي مع الشعار
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(width: 80, height: 80, child: pw.Image(logoImage, fit: pw.BoxFit.contain)),
              pw.Text(
                'سجل الديون',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 80),
            ],
          ),
          pw.SizedBox(height: 8),
          // التاريخ والوقت
          pw.Container(
            alignment: pw.Alignment.center,
            child: pw.Text(
              'تاريخ التحديث: ${DateTime.now().year}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().day.toString().padLeft(2, '0')} - ${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 14,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.SizedBox(height: 20),
          if (customers.isEmpty)
            pw.Center(
              child: pw.Text(
                'لا يوجد عملاء عليهم دين حالياً',
                style: const pw.TextStyle(fontSize: 16),
              ),
            )
          else ...[
            // إجمالي عدد العملاء
            pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Text(
                'إجمالي عدد العملاء: ${customers.length}',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 10),
            // إجمالي الديون
            pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Text(
                'إجمالي الديون: ${fmt(customers.fold(0.0, (sum, customer) => sum + (customer.currentTotalDebt ?? 0)))} دينار',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.red700,
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            // جدول العملاء
            pw.Table.fromTextArray(
              context: context,
              data: <List<String>>[
                // Header
                [
                  'المبلغ المطلوب',
                  'العنوان',
                  'اسم العميل',
                ],
                // Data
                ...customers.map((customer) => [
                      fmt(customer.currentTotalDebt ?? 0),
                      customer.address ?? '-',
                      customer.name,
                    ]),
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 14,
              ),
              cellStyle: const pw.TextStyle(fontSize: 12),
              cellAlignments: {
                2: pw.Alignment.centerRight,
                1: pw.Alignment.centerRight,
                0: pw.Alignment.center,
              },
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              border: pw.TableBorder.all(
                color: PdfColors.black,
                width: 1,
              ),
              columnWidths: {
                2: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                0: const pw.FlexColumnWidth(1),
              },
            ),
          ],
          pw.SizedBox(height: 20),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 20),
            padding: const pw.EdgeInsets.only(top: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(
                  color: PdfColors.grey,
                  width: 1,
                ),
              ),
            ),
            child: pw.Text(
              'تم إنشاء هذا التقرير تلقائياً بواسطة تطبيق الناصر',
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(
                color: PdfColors.grey,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );

    // Save the PDF file
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/daily_report.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  Future<Uint8List> generateAccountStatement({
    required Customer customer,
    required List<AccountStatementItem> transactions,
    double? finalBalance,
  }) async {
    // تحميل الخط العربي Amiri
    final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);
    // تحميل خط الناصر الصحيح (نفس خط الفاتورة)
    final alnaserFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
    // تحميل الشعار
    final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    // تحميل الإعدادات
    final appSettings = await SettingsManager.getAppSettings();

    // دالة تنسيق الأرقام مع فاصلة كل 3 خانات
    String formatNumber(num value) {
      return NumberFormat('#,##0', 'en_US').format(value);
    }

    String formatDescription(AccountStatementItem item) {
      final hasInvoice = item.transaction?.invoiceId != null;
      final invoicePart = hasInvoice ? 'فاتورة #${item.transaction?.invoiceId}' : '';
      
      // جلب الملاحظة النصية إن وجدت
      final note = item.transaction?.transactionNote?.trim() ?? '';
      final hasNote = note.isNotEmpty;
      
      String baseDescription = '';
      if (item.type == 'transaction' && item.transaction != null) {
        if (item.transaction!.amountChanged > 0) {
          baseDescription = 'إضافة دين';
        } else if (item.transaction!.amountChanged < 0) {
          baseDescription = 'تسديد دين';
        } else {
          baseDescription = 'معاملة مالية';
        }
      } else {
        baseDescription = item.description.replaceAll('(', '').replaceAll(')', '');
      }
      
      // بناء النص النهائي: البيان + الملاحظة + رقم الفاتورة
      List<String> parts = [baseDescription];
      if (hasNote) parts.add(note);
      if (hasInvoice) parts.add(invoicePart);
      
      return parts.join(' - ');
    }

    final pdf = pw.Document();
    final now = DateTime.now();
    final statementId =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    // دالة مساعدة لبناء رأس الصفحة - نفس تصميم الفاتورة
    pw.Widget _buildHeader() {
      return pw.Column(
        children: [
          buildPdfHeader(ttf, alnaserFont, logoImage, appSettings: appSettings, logoSize: 100),
          pw.SizedBox(height: 1),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('السيد: ${customer.name}',
                  style: pw.TextStyle(font: ttf, fontSize: 9)),
              pw.Text(
                  'العنوان: ${customer.address?.isNotEmpty == true ? customer.address : ' ______'}',
                  style: pw.TextStyle(font: ttf, fontSize: 8)),
              pw.Text(
                  'الوقت: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                  style: pw.TextStyle(font: ttf, fontSize: 8)),
              pw.Text(
                'التاريخ: ${now.year}/${now.month}/${now.day}',
                style: pw.TextStyle(font: ttf, fontSize: 8),
              ),
            ],
          ),
          pw.Divider(height: 2, thickness: 0.5),
        ],
      );
    }

    // دالة مساعدة لبناء رأس الجدول
    pw.TableRow _buildTableHeader() {
      return pw.TableRow(
        decoration: const pw.BoxDecoration(),
        children: [
          _headerCell('الدين بعد', ttf),
          _headerCell('الدين قبل', ttf),
          _headerCell('المبلغ', ttf),
          _headerCell('البيان', ttf),
          _headerCell('التاريخ', ttf),
          _headerCell('ت', ttf),
        ],
      );
    }

    // تقسيم المعاملات إلى صفحات (30 معاملة في كل صفحة)
    const int transactionsPerPage = 30;
    final int totalPages = (transactions.length / transactionsPerPage).ceil();
    
    if (transactions.isEmpty) {
      // صفحة واحدة فارغة
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.only(top: 10, bottom: 10, left: 10, right: 10),
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  pw.Spacer(),
                  pw.Center(
                    child: pw.Text(
                      'لا توجد معاملات مالية لهذا العميل',
                      style: pw.TextStyle(
                        font: ttf,
                        fontSize: 16,
                        color: PdfColors.grey,
                      ),
                    ),
                  ),
                  pw.Spacer(),
                ],
              ),
            );
          },
        ),
      );
    } else {
      // إنشاء صفحة لكل مجموعة من المعاملات
      for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
        final startIndex = pageIndex * transactionsPerPage;
        final endIndex = (startIndex + transactionsPerPage > transactions.length)
            ? transactions.length
            : startIndex + transactionsPerPage;
        final pageTransactions = transactions.sublist(startIndex, endIndex);
        final isLastPage = (pageIndex == totalPages - 1);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.only(top: 8, bottom: 8, left: 10, right: 10),
            build: (pw.Context context) {
              return pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    pw.SizedBox(height: 5),
                    if (pageIndex == 0) ...[
                      pw.Text(
                        'سجل المعاملات المالية:',
                        style: pw.TextStyle(
                          font: ttf,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                    ],
                    // جدول المعاملات - ترتيب الأعمدة من اليمين لليسار (RTL)
                    // تم تصغير أعمدة الأرقام والتاريخ وتوسيع عمود البيان
                    pw.Table(
                      border: pw.TableBorder.all(width: 0.2),
                      columnWidths: {
                        0: const pw.FixedColumnWidth(58), // الدين بعد - مصغر
                        1: const pw.FixedColumnWidth(58), // الدين قبل - مصغر
                        2: const pw.FixedColumnWidth(58), // المبلغ - مصغر
                        3: const pw.FlexColumnWidth(3), // البيان - موسع
                        4: const pw.FixedColumnWidth(55), // التاريخ - مصغر
                        5: const pw.FixedColumnWidth(22), // تسلسل - مصغر
                      },
                      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                      children: [
                        // Header - ترتيب من اليمين لليسار
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                          children: [
                            _headerCell('الدين بعد', ttf),
                            _headerCell('الدين قبل', ttf),
                            _headerCell('المبلغ', ttf),
                            _headerCell('البيان', ttf),
                            _headerCell('التاريخ', ttf),
                            _headerCell('ت', ttf),
                          ],
                        ),
                        // Data rows - ترتيب من اليمين لليسار
                        ...pageTransactions.asMap().entries.map((entry) {
                          final globalIndex = startIndex + entry.key;
                          final transaction = entry.value;
                          
                          return pw.TableRow(
                            children: [
                              _dataCell(formatNumber(transaction.balanceAfter ?? 0), ttf),
                              _dataCell(formatNumber(transaction.balanceBefore ?? 0), ttf),
                              _dataCell(formatNumber(transaction.amount ?? 0), ttf),
                              _dataCell(formatDescription(transaction), ttf, align: pw.TextAlign.right),
                              _dataCell(transaction.formattedDate, ttf),
                              _dataCell('${globalIndex + 1}', ttf),
                            ],
                          );
                        }).toList(),
                      ],
                    ),
                    pw.Spacer(),
                    // الرصيد النهائي في الصفحة الأخيرة فقط
                    if (isLastPage) ...[
                      pw.SizedBox(height: 20),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.black, width: 2),
                          borderRadius: pw.BorderRadius.circular(5),
                        ),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'الرصيد النهائي المستحق:',
                              style: pw.TextStyle(
                                font: ttf,
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Text(
                              '${formatNumber(finalBalance ?? 0)} دينار',
                              style: pw.TextStyle(
                                font: ttf,
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                                color: finalBalance != null && finalBalance > 0
                                    ? PdfColors.red
                                    : PdfColors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    pw.SizedBox(height: 10),
                    // رقم الصفحة
                    pw.Align(
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        'صفحة ${pageIndex + 1} من $totalPages',
                        style: pw.TextStyle(font: ttf, fontSize: 10, color: PdfColors.grey),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      }
    }

    return pdf.save();
  }

  pw.Widget _headerCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _dataCell(String text, pw.Font font,
      {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: 8,
        ),
        textAlign: align,
      ),
    );
  }

  // دالة مساعدة لبناء سلسلة التحويل للوحدة المختارة
  String buildUnitConversionStringPdf(dynamic item, List products) {
    // المنتجات التي تباع بالامتار
    if (item['unit'] == 'meter') {
      if (item['saleType'] == 'لفة' && item['unitsInLargeUnit'] != null) {
        return item['unitsInLargeUnit'].toString();
      } else {
        return '';
      }
    }
    // المنتجات التي تباع بالقطعة ولها تسلسل هرمي
    final product = products.firstWhere(
      (p) => p.name == item['productName'],
      orElse: () => null,
    );
    if (product == null ||
        product.unitHierarchy == null ||
        product.unitHierarchy.isEmpty) {
      return item['unitsInLargeUnit']?.toString() ?? '';
    }
    try {
      final List<dynamic> hierarchy =
          json.decode(product.unitHierarchy.replaceAll("'", '"'));
      List<String> factors = [];
      for (int i = 0; i < hierarchy.length; i++) {
        final unitName = hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
        final quantity = hierarchy[i]['quantity'];
        factors.add(quantity.toString());
        if (unitName == item['saleType']) {
          break;
        }
      }
      if (factors.isEmpty) {
        return item['unitsInLargeUnit']?.toString() ?? '';
      }
      return factors.join(' × ');
    } catch (e) {
      return item['unitsInLargeUnit']?.toString() ?? '';
    }
  }

  /// 📄 إنشاء ملف PDF يحتوي على كشوفات حسابات جميع العملاء
  /// العملاء مرتبين أبجدياً
  Future<Uint8List> generateAllCustomersAccountStatements({
    required List<Customer> customers,
    required Future<List<AccountStatementItem>> Function(int customerId) getCustomerTransactions,
  }) async {
    // تحميل الخط العربي Amiri
    final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);
    // تحميل خط الناصر
    final alnaserFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
    // تحميل الشعار
    final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    // تحميل الإعدادات
    final appSettings = await SettingsManager.getAppSettings();

    // دالة تنسيق الأرقام
    String formatNumber(num value) {
      return NumberFormat('#,##0', 'en_US').format(value);
    }

    String formatDescription(AccountStatementItem item) {
      final hasInvoice = item.transaction?.invoiceId != null;
      final invoicePart = hasInvoice ? 'فاتورة #${item.transaction?.invoiceId}' : '';
      
      // جلب الملاحظة النصية إن وجدت
      final note = item.transaction?.transactionNote?.trim() ?? '';
      final hasNote = note.isNotEmpty;
      
      String baseDescription = '';
      if (item.type == 'transaction' && item.transaction != null) {
        if (item.transaction!.amountChanged > 0) {
          baseDescription = 'إضافة دين';
        } else if (item.transaction!.amountChanged < 0) {
          baseDescription = 'تسديد دين';
        } else {
          baseDescription = 'معاملة مالية';
        }
      } else {
        baseDescription = item.description.replaceAll('(', '').replaceAll(')', '');
      }
      
      // بناء النص النهائي: البيان + الملاحظة + رقم الفاتورة
      List<String> parts = [baseDescription];
      if (hasNote) parts.add(note);
      if (hasInvoice) parts.add(invoicePart);
      
      return parts.join(' - ');
    }

    final pdf = pw.Document();
    final now = DateTime.now();

    // ترتيب العملاء أبجدياً
    final sortedCustomers = List<Customer>.from(customers);
    sortedCustomers.sort((a, b) => a.name.compareTo(b.name));
    
    // فلترة العملاء: فقط من لديهم رصيد أو معاملات
    final customersWithActivity = sortedCustomers.where((c) => (c.currentTotalDebt ?? 0) != 0).toList();
    final totalDebt = customersWithActivity.fold(0.0, (sum, c) => sum + (c.currentTotalDebt ?? 0));

    // صفحة الغلاف
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Container(width: 120, height: 120, child: pw.Image(logoImage, fit: pw.BoxFit.contain)),
                pw.SizedBox(height: 30),
                pw.Text(
                  'كشوفات حسابات العملاء',
                  style: pw.TextStyle(font: ttf, fontSize: 28, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'التاريخ: ${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}',
                  style: pw.TextStyle(font: ttf, fontSize: 16, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  'عدد العملاء (لديهم رصيد أو معاملات): يتم حسابه...',
                  style: pw.TextStyle(font: ttf, fontSize: 14, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 40),
                pw.Container(
                  padding: const pw.EdgeInsets.all(15),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'إجمالي الديون: ${formatNumber(totalDebt)} دينار',
                    style: pw.TextStyle(font: ttf, fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.red700),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    // إنشاء كشف حساب لكل عميل (فقط للعملاء الذين لديهم معاملات أو رصيد)
    int customerIndex = 0;
    int includedCustomers = 0;
    for (final customer in sortedCustomers) {
      customerIndex++;

      if (customer.id == null) continue;

      // جلب معاملات العميل
      final transactions = await getCustomerTransactions(customer.id!);
      
      // تخطي العملاء الذين رصيدهم صفر وليس لديهم معاملات
      final hasBalance = (customer.currentTotalDebt ?? 0) != 0;
      final hasTransactions = transactions.isNotEmpty;
      if (!hasBalance && !hasTransactions) {
        continue; // تخطي هذا العميل
      }
      
      includedCustomers++;

      // دالة بناء رأس الصفحة للعميل
      pw.Widget buildCustomerHeader() {
        return pw.Column(
          children: [
            buildPdfHeader(ttf, alnaserFont, logoImage, appSettings: appSettings, logoSize: 80),
            pw.SizedBox(height: 5),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 10),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('السيد: ${customer.name}', style: pw.TextStyle(font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  pw.Text('العنوان: ${customer.address?.isNotEmpty == true ? customer.address : '---'}', style: pw.TextStyle(font: ttf, fontSize: 9)),
                  pw.Text('التاريخ: ${now.year}/${now.month}/${now.day}', style: pw.TextStyle(font: ttf, fontSize: 9)),
                ],
              ),
            ),
            pw.Divider(height: 2, thickness: 0.5),
          ],
        );
      }

      if (transactions.isEmpty) {
        // صفحة واحدة للعميل بدون معاملات
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(15),
            build: (pw.Context context) {
              return pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    buildCustomerHeader(),
                    pw.Spacer(),
                    pw.Center(
                      child: pw.Text(
                        'لا توجد معاملات مالية لهذا العميل',
                        style: pw.TextStyle(font: ttf, fontSize: 14, color: PdfColors.grey),
                      ),
                    ),
                    pw.Spacer(),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.black, width: 1),
                        borderRadius: pw.BorderRadius.circular(5),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('الرصيد المستحق:', style: pw.TextStyle(font: ttf, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                          pw.Text('${formatNumber(customer.currentTotalDebt ?? 0)} دينار',
                            style: pw.TextStyle(font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold,
                              color: (customer.currentTotalDebt ?? 0) > 0 ? PdfColors.red : PdfColors.green)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      } else {
        // تقسيم المعاملات إلى صفحات
        const int transactionsPerPage = 25;
        final int totalPages = (transactions.length / transactionsPerPage).ceil();
        final double finalBalance = transactions.isNotEmpty ? (transactions.last.balanceAfter ?? 0) : (customer.currentTotalDebt ?? 0);

        for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
          final startIndex = pageIndex * transactionsPerPage;
          final endIndex = (startIndex + transactionsPerPage > transactions.length)
              ? transactions.length
              : startIndex + transactionsPerPage;
          final pageTransactions = transactions.sublist(startIndex, endIndex);
          final isLastPage = (pageIndex == totalPages - 1);

          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(10),
              build: (pw.Context context) {
                return pw.Directionality(
                  textDirection: pw.TextDirection.rtl,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      buildCustomerHeader(),
                      pw.SizedBox(height: 3),
                      if (pageIndex == 0)
                        pw.Text('سجل المعاملات المالية:', style: pw.TextStyle(font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 3),
                      // جدول المعاملات - RTL
                      // تم تصغير أعمدة الأرقام والتاريخ وتوسيع عمود البيان
                      pw.Table(
                        border: pw.TableBorder.all(width: 0.2),
                        columnWidths: {
                          0: const pw.FixedColumnWidth(58), // الدين بعد - مصغر
                          1: const pw.FixedColumnWidth(58), // الدين قبل - مصغر
                          2: const pw.FixedColumnWidth(58), // المبلغ - مصغر
                          3: const pw.FlexColumnWidth(3), // البيان - موسع
                          4: const pw.FixedColumnWidth(55), // التاريخ - مصغر
                          5: const pw.FixedColumnWidth(22), // تسلسل - مصغر
                        },
                        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                        children: [
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                            children: [
                              _headerCell('الدين بعد', ttf),
                              _headerCell('الدين قبل', ttf),
                              _headerCell('المبلغ', ttf),
                              _headerCell('البيان', ttf),
                              _headerCell('التاريخ', ttf),
                              _headerCell('ت', ttf),
                            ],
                          ),
                          ...pageTransactions.asMap().entries.map((entry) {
                            final globalIndex = startIndex + entry.key;
                            final transaction = entry.value;
                            return pw.TableRow(
                              children: [
                                _dataCell(formatNumber(transaction.balanceAfter ?? 0), ttf),
                                _dataCell(formatNumber(transaction.balanceBefore ?? 0), ttf),
                                _dataCell(formatNumber(transaction.amount ?? 0), ttf),
                                _dataCell(formatDescription(transaction), ttf, align: pw.TextAlign.right),
                                _dataCell(transaction.formattedDate, ttf),
                                _dataCell('${globalIndex + 1}', ttf),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                      pw.Spacer(),
                      if (isLastPage)
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.black, width: 1.5),
                            borderRadius: pw.BorderRadius.circular(5),
                          ),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text('الرصيد النهائي المستحق:', style: pw.TextStyle(font: ttf, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                              pw.Text('${formatNumber(finalBalance)} دينار',
                                style: pw.TextStyle(font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold,
                                  color: finalBalance > 0 ? PdfColors.red : PdfColors.green)),
                            ],
                          ),
                        ),
                      pw.SizedBox(height: 5),
                      pw.Align(
                        alignment: pw.Alignment.center,
                        child: pw.Text(
                          'عميل $customerIndex/${sortedCustomers.length} | صفحة ${pageIndex + 1} من $totalPages',
                          style: pw.TextStyle(font: ttf, fontSize: 8, color: PdfColors.grey),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        }
      }
    }

    return pdf.save();
  }

  /// 📊 إنشاء PDF لكشف الحساب التجاري
  Future<Uint8List> generateCommercialStatement({
    required Customer customer,
    required Map<String, dynamic> statementData,
    required String periodDescription,
  }) async {
    // تحميل الخط العربي Amiri
    final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);
    
    // تحميل الشعار
    final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final pdf = pw.Document();
    
    String fmt(num v) => NumberFormat('#,##0', 'en_US').format(v);
    
    final entries = statementData['entries'] as List<Map<String, dynamic>>;
    final summary = statementData['summary'] as Map<String, dynamic>;
    final finalBalance = (statementData['finalBalance'] as num).toDouble();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
          textDirection: pw.TextDirection.rtl,
        ),
        build: (context) => [
          // العنوان مع الشعار
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Container(width: 60, height: 60, child: pw.Image(logoImage)),
              pw.Column(
                children: [
                  pw.Text('كشف الحساب التجاري', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(customer.name, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(width: 60),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text('الفترة: $periodDescription', style: const pw.TextStyle(fontSize: 12)),
          pw.Text('تاريخ الطباعة: ${DateFormat('yyyy/MM/dd').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 15),
          
          // ملخص الإحصائيات
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Column(children: [
                      pw.Text('فواتير دين', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('${summary['totalDebtInvoices'] ?? 0}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ]),
                    pw.Column(children: [
                      pw.Text('فواتير نقد', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('${summary['totalCashInvoices'] ?? 0}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    ]),
                    if ((summary['convertedToCash'] ?? 0) > 0)
                      pw.Column(children: [
                        pw.Text('تحولت لنقد', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('${summary['convertedToCash']}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.purple)),
                      ]),
                    if ((summary['convertedToDebt'] ?? 0) > 0)
                      pw.Column(children: [
                        pw.Text('تحولت لدين', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('${summary['convertedToDebt']}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.deepOrange)),
                      ]),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Column(children: [
                      pw.Text('إجمالي الديون', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text(fmt((summary['totalDebts'] as num?) ?? 0), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    ]),
                    pw.Column(children: [
                      pw.Text('إجمالي المدفوعات', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text(fmt((summary['totalPayments'] as num?) ?? 0), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.green700)),
                    ]),
                    pw.Column(children: [
                      pw.Text('الرصيد المتبقي', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text(fmt((summary['remainingBalance'] as num?) ?? 0), 
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, 
                          color: ((summary['remainingBalance'] as num?) ?? 0) > 0 ? PdfColors.red : PdfColors.green700)),
                    ]),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 15),
          
          // جدول السطور - الأعمدة: الدين بعد | الدين قبل | المبلغ | البيان | التاريخ
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(65),  // الدين بعد
              1: const pw.FixedColumnWidth(65),  // الدين قبل
              2: const pw.FixedColumnWidth(65),  // المبلغ
              3: const pw.FlexColumnWidth(2),    // البيان
              4: const pw.FixedColumnWidth(65),  // التاريخ
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('الدين بعد', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('الدين قبل', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('المبلغ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('البيان', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('التاريخ', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                ],
              ),
              ...entries.map((entry) {
                final date = entry['date'] as DateTime;
                final invoiceAmount = (entry['invoiceAmount'] as num?)?.toDouble() ?? 0.0;
                final netAmount = (entry['netAmount'] as num?)?.toDouble() ?? 0.0;
                final debtBefore = (entry['debtBefore'] as num?)?.toDouble() ?? 0.0;
                final debtAfter = (entry['debtAfter'] as num?)?.toDouble() ?? 0.0;
                final type = entry['type'] as String? ?? '';
                
                // تحديد المبلغ المعروض:
                // - فاتورة نقد/محولة/دين: مبلغ الفاتورة الأصلي
                // - معاملة يدوية: المبلغ
                double displayAmount;
                PdfColor amountColor;
                if (type == 'cash_invoice' || type == 'converted_to_cash' || type == 'converted_to_debt' || type == 'debt_invoice') {
                  displayAmount = invoiceAmount;
                  if (type == 'cash_invoice') {
                    amountColor = PdfColors.blue700;
                  } else if (type == 'converted_to_cash') {
                    amountColor = PdfColors.purple;
                  } else if (type == 'converted_to_debt') {
                    amountColor = PdfColors.deepOrange;
                  } else {
                    amountColor = PdfColors.red;
                  }
                } else {
                  displayAmount = netAmount.abs();
                  amountColor = netAmount > 0 ? PdfColors.orange : PdfColors.green700;
                }
                
                return pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(fmt(debtAfter), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: debtAfter > 0 ? PdfColors.red : PdfColors.green700), textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(fmt(debtBefore), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(fmt(displayAmount), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: amountColor), textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(entry['description'] as String, style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(DateFormat('yyyy/MM/dd').format(date), style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                  ],
                );
              }).toList(),
            ],
          ),
          pw.SizedBox(height: 15),
          
          // الرصيد النهائي
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1.5),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('الرصيد النهائي:', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('${fmt(finalBalance)} دينار', 
                  style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, 
                    color: finalBalance > 0 ? PdfColors.red : PdfColors.green700)),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }
}
