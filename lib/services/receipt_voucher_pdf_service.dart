// services/receipt_voucher_pdf_service.dart
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import 'pdf_header.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';

class ReceiptVoucherPdfService {
  static Future<pw.Document> generateReceiptVoucherPdf({
    required String customerName,
    required double beforePayment,
    required double paidAmount,
    required double afterPayment,
    required DateTime dateTime,
    required pw.Font font,
    
    required pw.Font alnaserFont,
    required pw.MemoryImage logoImage,
  }) async {
    // تحميل الإعدادات العامة
    final settingsManager = SettingsManager();
    final appSettings = await settingsManager.getAppSettings();
    
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                buildPdfHeader(font, alnaserFont, logoImage, logoSize: 150, appSettings: appSettings),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'سند قبض',
                    style: pw.TextStyle(
                        font: font,
                        fontSize: 32,
                        fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('السيد: $customerName',
                        style: pw.TextStyle(font: font, fontSize: 14)),
                    pw.Text(
                        'التاريخ: ${dateTime.year}/${dateTime.month}/${dateTime.day}',
                        style: pw.TextStyle(font: font, fontSize: 13)),
                    pw.Text(
                        'الوقت: ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}',
                        style: pw.TextStyle(font: font, fontSize: 13)),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Divider(thickness: 0.7),
                pw.SizedBox(height: 16),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('إجمالي الدين قبل التسديد:',
                        style: pw.TextStyle(font: font, fontSize: 14)),
                    pw.Text(beforePayment.toStringAsFixed(2),
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('المبلغ المسدد:',
                        style: pw.TextStyle(font: font, fontSize: 14)),
                    pw.Text(paidAmount.toStringAsFixed(2),
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('إجمالي الدين بعد التسديد:',
                        style: pw.TextStyle(font: font, fontSize: 14)),
                    pw.Text(afterPayment.toStringAsFixed(2),
                        style: pw.TextStyle(
                            font: font,
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 32),
                pw.Center(
                  child: pw.Text(
                    'يجب حفظ هذه الورقة لحفظ جميع حقوقك',
                    style: pw.TextStyle(
                        font: font, fontSize: 13, color: PdfColors.red),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    return pdf;
  }
}
