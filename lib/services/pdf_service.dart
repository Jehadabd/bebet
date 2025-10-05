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
              'تم إنشاء هذا التقرير تلقائياً بواسطة تطبيق دفتر ديوني',
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
    // تحميل خط Old Antic Outline Shaded لكلمة الناصر
    final alnaserFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Old Antic Outline Shaded.ttf'));

    String formatNumber(num value) {
      if (value % 1 == 0) {
        return value.toInt().toString();
      } else {
        return value.toStringAsFixed(2);
      }
    }

    String formatDescription(AccountStatementItem item) {
      final hasInvoice = item.transaction?.invoiceId != null;
      final invoicePart =
          hasInvoice ? ' (فاتورة #${item.transaction?.invoiceId})' : '';
      if (item.type == 'transaction' && item.transaction != null) {
        if (item.transaction!.amountChanged > 0) {
          return 'معاملة مالية - إضافة دين$invoicePart';
        } else if (item.transaction!.amountChanged < 0) {
          return 'معاملة مالية - تسديد دين$invoicePart';
        }
      }
      if (hasInvoice) {
        return 'معاملة مالية$invoicePart';
      }
      return item.description.replaceAll('(', '').replaceAll(')', '');
    }

    final pdf = pw.Document();
    final now = DateTime.now();
    final statementId =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.only(top: 0, bottom: 2, left: 10, right: 10),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // --- الرأس الجديد مع معلومات المتجر ---
                pw.Container(
                  padding: const pw.EdgeInsets.all(2),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(1),
                  ),
                  child: pw.Column(
                    children: [
                      pw.SizedBox(height: 0),
                      pw.Center(
                        child: pw.Text(
                          'الــــــنــــــاصــــــر',
                          style: pw.TextStyle(
                            font: alnaserFont,
                            fontSize: 45,
                            height: 0,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.black,
                          ),
                        ),
                      ),
                      pw.Center(
                        child: pw.Text(
                            'لتجارة المواد الصحية والعدد اليدوية والانشائية',
                            style: pw.TextStyle(font: ttf, fontSize: 17)),
                      ),
                      pw.Center(
                        child: pw.Text(
                          'الموصل - الجدعة - مقابل البرج',
                          style: pw.TextStyle(font: ttf, fontSize: 13),
                        ),
                      ),
                      pw.Center(
                        child: pw.Text('0771 406 3064  |  0770 305 1353',
                            style: pw.TextStyle(
                                font: ttf,
                                fontSize: 13,
                                color: PdfColors.black)),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 4),
                // --- معلومات العميل والتاريخ ---
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('السيد: ${customer.name}',
                        style: pw.TextStyle(font: ttf, fontSize: 12)),
                    pw.Text(
                        'العنوان: ${customer.address?.isNotEmpty == true ? customer.address : ' ______'}',
                        style: pw.TextStyle(font: ttf, fontSize: 11)),
                    pw.Text(
                        'الوقت: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                        style: pw.TextStyle(font: ttf, fontSize: 11)),
                    pw.Text(
                      'التاريخ: ${now.year}/${now.month}/${now.day}',
                      style: pw.TextStyle(font: ttf, fontSize: 11),
                    ),
                  ],
                ),
                pw.Divider(height: 5, thickness: 0.5),

                // --- جدول المعاملات ---
                if (transactions.isNotEmpty) ...[
                  pw.Text(
                    'سجل المعاملات المالية:',
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.2),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(80), // الدين بعد
                      1: const pw.FixedColumnWidth(80), // الدين قبل
                      2: const pw.FixedColumnWidth(80), // المبلغ
                      3: const pw.FlexColumnWidth(2), // البيان
                      4: const pw.FixedColumnWidth(80), // التاريخ
                      5: const pw.FixedColumnWidth(30), // تسلسل
                    },
                    defaultVerticalAlignment:
                        pw.TableCellVerticalAlignment.middle,
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(),
                        children: [
                          _headerCell('الدين بعد', ttf),
                          _headerCell('الدين قبل', ttf),
                          _headerCell('المبلغ', ttf),
                          _headerCell('البيان', ttf),
                          _headerCell('التاريخ', ttf),
                          _headerCell('ت', ttf),
                        ],
                      ),
                      ...transactions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final transaction = entry.value;
                        return pw.TableRow(
                          children: [
                            _dataCell(
                                formatNumber(transaction.balanceAfter ?? 0),
                                ttf),
                            _dataCell(
                                formatNumber(transaction.balanceBefore ?? 0),
                                ttf),
                            _dataCell(
                                formatNumber(transaction.amount ?? 0), ttf),
                            _dataCell(formatDescription(transaction), ttf,
                                align: pw.TextAlign.right),
                            _dataCell(transaction.formattedDate, ttf),
                            _dataCell('${index + 1}', ttf),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                  // --- الرصيد النهائي ---
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
                ] else ...[
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
                ],
                pw.SizedBox(height: 30),
                // --- تذييل الصفحة ---
                pw.Center(
                  child: pw.Text(
                    'معاملة كشف حساب',
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: 11,
                      color: PdfColors.grey,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    return pdf.save();
  }

  pw.Widget _headerCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _dataCell(String text, pw.Font font,
      {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: 11,
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
}
