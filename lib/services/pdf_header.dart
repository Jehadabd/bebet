// services/pdf_header.dart
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

pw.Widget buildPdfHeader(
    pw.Font font, pw.Font alnaserFont, pw.ImageProvider logoImage,
    {double logoSize = 150}) {
  return pw.Column(
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
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
                  child: pw.Text('لتجارة المواد الصحية والعدد اليدوية والانشائية',
                      style: pw.TextStyle(font: font, fontSize: 17)),
                ),
                pw.Center(
                  child: pw.Text(
                    'الموصل - الجدعة - مقابل البرج',
                    style: pw.TextStyle(font: font, fontSize: 13),
                  ),
                ),
                pw.Center(
                  child: pw.Text('0771 406 3064  |  0770 305 1353',
                      style: pw.TextStyle(
                          font: font, fontSize: 13, color: PdfColors.black)),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Container(
            width: logoSize,
            height: logoSize,
            child: pw.Image(logoImage, fit: pw.BoxFit.contain),
          ),
        ],
      ),
      pw.SizedBox(height: 4),
    ],
  );
}
