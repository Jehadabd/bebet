// services/pdf_service.dart
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/customer.dart';

class PdfService {
  static final PdfService _instance = PdfService._internal();

  factory PdfService() => _instance;

  PdfService._internal();

  Future<File> generateDailyReport(List<Customer> customers) async {
    // تحميل الخط العربي Amiri
    final fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);

    final pdf = pw.Document();

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
          // العنوان الرئيسي
          pw.Container(
            alignment: pw.Alignment.center,
            child: pw.Text(
              'سجل الديون',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
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
                'إجمالي الديون: ${customers.fold(0.0, (sum, customer) => sum + customer.currentTotalDebt).toStringAsFixed(2)} دينار',
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
                      customer.currentTotalDebt.toStringAsFixed(2),
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
}
