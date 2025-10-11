// services/pdf_header.dart
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';

pw.Widget buildPdfHeader(
    pw.Font font, pw.Font alnaserFont, pw.ImageProvider logoImage,
    {double logoSize = 150, required AppSettings appSettings}) {
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
                      color: PdfColor.fromInt(appSettings.companyNameColor),
                    ),
                  ),
                ),
                pw.Center(
                  child: pw.Text(appSettings.companyDescription,
                      style: pw.TextStyle(font: font, fontSize: 17, color: PdfColor.fromInt(appSettings.companyDescriptionColor))),
                ),
                pw.Center(
                  child: pw.Text(
                    'الموصل - الجدعة - مقابل البرج',
                    style: pw.TextStyle(font: font, fontSize: 13),
                  ),
                ),
                // أرقام الهواتف مع اتجاه LTR لضمان عرض صحيح للأرقام بين العربية
                pw.SizedBox(height: 4),
                // عرض أرقام الهواتف من الإعدادات مع الاحتفاظ بالتصميم
                if (appSettings.phoneNumbers.isNotEmpty) ...[
                  pw.Center(
                    child: pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text('كهربائيات', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                        pw.Directionality(
                          textDirection: pw.TextDirection.ltr,
                          child: pw.Text(' ${appSettings.phoneNumbers.length > 0 ? appSettings.phoneNumbers[0] : ''} ${appSettings.phoneNumbers.length > 1 ? ' |  ${appSettings.phoneNumbers[1]}' : ''} ', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColor.fromInt(appSettings.electricPhoneColor))),
                        ),
                      ],
                    ),
                  ),
                  if (appSettings.phoneNumbers.length > 2) ...[
                    pw.Center(
                      child: pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text('صـحـيـات', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                          pw.Directionality(
                            textDirection: pw.TextDirection.ltr,
                            child: pw.Text(' ${appSettings.phoneNumbers.length > 2 ? appSettings.phoneNumbers[2] : ''} ${appSettings.phoneNumbers.length > 3 ? ' |  ${appSettings.phoneNumbers[3]}' : ''} ', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColor.fromInt(appSettings.healthPhoneColor))),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  // الأرقام الافتراضية في حالة عدم وجود إعدادات
                  pw.Center(
                    child: pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text('كهربائيات', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                        pw.Directionality(
                          textDirection: pw.TextDirection.ltr,
                          child: pw.Text(' 0773 284 5260  |  0770 304 0821 ', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                        ),
                      ],
                    ),
                  ),
                  pw.Center(
                    child: pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                          pw.Text('صـحـيـات', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                        pw.Directionality(
                          textDirection: pw.TextDirection.ltr,
                          child: pw.Text(' 0771 406 3064  |  0770 305 1353 ', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                        ),
                      ],
                    ),
                  ),
                ],
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
