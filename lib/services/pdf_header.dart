// services/pdf_header.dart
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';
import 'package:alnaser/services/stamp_manager.dart';

pw.Widget _buildStamp(pw.Font font, String paymentType, int invoiceId, double totalAmount, int itemsCount, {bool isBlack = false, String? formattedInvoiceNumber}) {
  final isCash = paymentType == 'نقد';
  final color = isBlack ? PdfColors.black : (isCash ? PdfColor.fromHex('#1A365D') : PdfColor.fromHex('#9B2C2C'));
  final text = isCash ? 'نقداً' : 'آجل';
  
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: color, width: 1.5),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // Text
        pw.Text(
          text,
          style: pw.TextStyle(
            font: font,
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
        pw.SizedBox(width: 8),
        // Checkmark Circle
        pw.Container(
          width: 18,
          height: 18,
          decoration: pw.BoxDecoration(
            shape: pw.BoxShape.circle,
            border: pw.Border.all(color: color, width: 1.5),
          ),
          child: pw.Center(
            child: pw.Transform.scale(
              scale: 0.6,
              child: pw.CustomPaint(
                size: const PdfPoint(10, 10),
                painter: (PdfGraphics g, PdfPoint size) {
                  // رسم علامة الصح مع مراعاة الانعكاس
                  // بدلاً من (8,6) -> (6,3) -> (2,8) التي كانت مقلوبة
                  // نرسم علامة صح قياسية: من اليسار(2,6) إلى الأسفل(4,2) ثم أعلى اليمين(8,8)
                  g.moveTo(2, 6);
                  g.lineTo(4, 2);
                  g.lineTo(8, 8);
                  g.setColor(color);
                  g.setLineWidth(2.5);
                  g.strokePath();
                },
              ),
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        // Vertical Divider
        pw.Container(
          width: 1,
          height: 35,
          color: color,
        ),
        pw.SizedBox(width: 8),
        // QR Code
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(
            errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
          ),
          data: 'رقم الفاتورة: ${formattedInvoiceNumber ?? invoiceId}\nالمبلغ: $totalAmount\nعدد العناصر: $itemsCount',
          width: 35,
          height: 35,
          color: color,
        ),
      ],
    ),
  );
}

pw.Widget _buildImageStamp(pw.MemoryImage? cashImage, pw.MemoryImage? creditImage, String paymentType) {
  final isCash = paymentType == 'نقد';
  final image = isCash ? cashImage : creditImage;
  
  if (image == null) {
    return pw.SizedBox(); // Fallback if image not found
  }
  
  return pw.Container(
    height: 50,
    child: pw.Image(image, fit: pw.BoxFit.contain),
  );
}

pw.Widget buildPdfHeader(
    pw.Font font, pw.Font alnaserFont, pw.ImageProvider logoImage,
    {double logoSize = 150, 
     required AppSettings appSettings,
     String? paymentType,
     int? invoiceId,
     double? totalAmount,
     int? itemsCount,
     String? formattedInvoiceNumber,
    }) {
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
                      fontFallback: [font],
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
                pw.SizedBox(height: 4),
                // أرقام الهواتف على اليمين والختم على اليسار (بين الهواتف واللوغو)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    // أرقام الهواتف (محاذاة لليمين / بداية السطر في RTL)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 35), // دفع الأرقام لليسار قليلاً بمقدار 5 أحرف تقريباً
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (appSettings.phoneNumbers.isNotEmpty) ...[
                            pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.Text('كهربائيات', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                                pw.Directionality(
                                  textDirection: pw.TextDirection.ltr,
                                  child: pw.Text(' ${appSettings.phoneNumbers.length > 0 ? appSettings.phoneNumbers[0] : ''} ${appSettings.phoneNumbers.length > 1 ? ' |  ${appSettings.phoneNumbers[1]}' : ''} ', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColor.fromInt(appSettings.electricPhoneColor))),
                                ),
                              ],
                            ),
                            if (appSettings.phoneNumbers.length > 2) ...[
                              pw.Row(
                                mainAxisSize: pw.MainAxisSize.min,
                                children: [
                                  pw.Text('صـحـيـات', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                                  pw.Directionality(
                                    textDirection: pw.TextDirection.ltr,
                                    child: pw.Text(' ${appSettings.phoneNumbers.length > 2 ? appSettings.phoneNumbers[2] : ''} ${appSettings.phoneNumbers.length > 3 ? ' |  ${appSettings.phoneNumbers[3]}' : ''} ', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColor.fromInt(appSettings.healthPhoneColor))),
                                  ),
                                ],
                              ),
                            ],
                          ] else ...[
                            pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                pw.Text('كهربائيات', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                                pw.Directionality(
                                  textDirection: pw.TextDirection.ltr,
                                  child: pw.Text(' 0773 284 5260  |  0770 304 0821 ', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                                ),
                              ],
                            ),
                            pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              children: [
                                  pw.Text('صـحـيـات', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                                pw.Directionality(
                                  textDirection: pw.TextDirection.ltr,
                                  child: pw.Text(' 0771 406 3064  |  0770 305 1353 ', style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                                ),
                              ],
                            ),
                          ],
                        ]
                      ),
                    ),
                    // الختم (محاذاة لليسار قريباً من اللوغو)
                    if (paymentType != null && invoiceId != null && totalAmount != null && itemsCount != null)
                      if (appSettings.stampType == 'colored')
                        _buildImageStamp(StampManager.coloredCash, StampManager.coloredCredit, paymentType)
                      else if (appSettings.stampType == 'ink')
                        _buildImageStamp(StampManager.inkCash, StampManager.inkCredit, paymentType)
                      else if (appSettings.stampType == 'custom')
                        _buildImageStamp(StampManager.customCash, StampManager.customCredit, paymentType)
                      else if (appSettings.stampType == 'barcode_black')
                        _buildStamp(font, paymentType, invoiceId, totalAmount, itemsCount, isBlack: true, formattedInvoiceNumber: formattedInvoiceNumber)
                      else
                        _buildStamp(font, paymentType, invoiceId, totalAmount, itemsCount, isBlack: false, formattedInvoiceNumber: formattedInvoiceNumber),
                  ],
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
