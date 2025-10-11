// services/invoice_pdf_service.dart
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'dart:convert';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/customer.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:alnaser/services/settings_manager.dart';
import 'package:alnaser/models/app_settings.dart';

class InvoicePdfService {
  static Future<pw.Document> generateInvoicePdf({
    required List<InvoiceItem> invoiceItems,
    required List<Product> allProducts,
    required String customerName,
    required String customerAddress,
    required int invoiceId,
    required DateTime selectedDate,
    required double discount,
    required double paid,
    required String paymentType,
    required Invoice? invoiceToManage,
    required double previousDebt,
    required double currentDebt,
    required double afterDiscount,
    required double remaining,
    required pw.Font font,
    required pw.Font alnaserFont,
    required pw.MemoryImage logoImage,
    required DateTime? createdAt,
    required AppSettings appSettings,
  }) async {
    final pdf = pw.Document();
    const itemsPerPage = 20;
    final totalPages = (invoiceItems.length / itemsPerPage).ceil();
    for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final start = pageIndex * itemsPerPage;
      final end = (start + itemsPerPage) > invoiceItems.length
          ? invoiceItems.length
          : start + itemsPerPage;
      final pageItems = invoiceItems.sublist(start, end);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.only(top: 0, bottom: 2, left: 10, right: 10),
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Stack(
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
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
                              child: pw.Text(
                                  'لتجارة المواد الصحية والعدد اليدوية والانشائية ',
                                  style: pw.TextStyle(font: font, fontSize: 17)),
                            ),
                            pw.Center(
                              child: pw.Text(
                                'الموصل - الجدعة - مقابل البرج',
                                style: pw.TextStyle(font: font, fontSize: 13),
                              ),
                            ),
                            ...appSettings.phoneNumbers.map((number) => pw.Center(
                                  child: pw.Directionality(
                                    textDirection: pw.TextDirection.ltr,
                                    child: pw.Text(number, style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.black)),
                                  ),
                                )),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Container(
                        width: 150,
                        height: 150,
                        child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('السيد: $customerName',
                          style: pw.TextStyle(font: font, fontSize: 12)),
                      pw.Text(
                          'العنوان: ${customerAddress.isNotEmpty ? customerAddress : ' ______'}',
                          style: pw.TextStyle(font: font, fontSize: 11)),
                      pw.Text('رقم الفاتورة: $invoiceId',
                          style: pw.TextStyle(font: font, fontSize: 10)),
                      pw.Text(
                          'الوقت: ${createdAt?.hour.toString().padLeft(2, '0') ?? DateTime.now().hour.toString().padLeft(2, '0')}:${createdAt?.minute.toString().padLeft(2, '0') ?? DateTime.now().minute.toString().padLeft(2, '0')}',
                          style: pw.TextStyle(font: font, fontSize: 11)),
                      pw.Text(
                        'التاريخ: ${selectedDate.year}/${selectedDate.month}/${selectedDate.day}',
                        style: pw.TextStyle(font: font, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Divider(height: 5, thickness: 0.5),
                  // جدول الفاتورة الرئيسي: ترتيب مطلوب: ت، ID، التفاصيل، نوع البيع، العدد، عدد الوحدات، السعر، المبلغ
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.2),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(20), // ت
                      1: const pw.FixedColumnWidth(60), // ID
                      2: const pw.FlexColumnWidth(1.3), // التفاصيل
                      3: const pw.FixedColumnWidth(70), // نوع البيع
                      4: const pw.FixedColumnWidth(70), // العدد
                      5: const pw.FixedColumnWidth(65), // عدد الوحدات
                      6: const pw.FixedColumnWidth(70), // السعر
                      7: const pw.FixedColumnWidth(90), // المبلغ
                    },
                    defaultVerticalAlignment:
                        pw.TableCellVerticalAlignment.middle,
                    children: [
                      pw.TableRow(children: [
                        headerCell('ت', font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                        headerCell('ID', font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                        headerCell('التفاصيل', font, color: PdfColor.fromInt(appSettings.itemDetailsColor)),
                        headerCell('نوع البيع', font),
                        headerCell('العدد', font, color: PdfColor.fromInt(appSettings.itemQuantityColor)),
                        headerCell('عدد الوحدات', font),
                        headerCell('السعر', font, color: PdfColor.fromInt(appSettings.itemPriceColor)),
                        headerCell('المبلغ', font, color: PdfColor.fromInt(appSettings.itemTotalColor)),
                      ]),
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
                        return pw.TableRow(children: [
                          dataCell('${index + 1}', font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                          dataCell(formatProductId(product?.id), font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                          dataCell(item.productName, font, align: pw.TextAlign.right, color: PdfColor.fromInt(appSettings.itemDetailsColor)),
                          dataCell(item.saleType ?? '', font),
                          dataCell('${formatNumber(quantity, forceDecimal: true)}', font, color: PdfColor.fromInt(appSettings.itemQuantityColor)),
                          dataCell(buildUnitConversionStringForPdf(item, product), font),
                          dataCell(formatNumber(item.appliedPrice, forceDecimal: true), font, color: PdfColor.fromInt(appSettings.itemPriceColor)),
                          dataCell(formatNumber(item.itemTotal, forceDecimal: true), font, color: PdfColor.fromInt(appSettings.itemTotalColor)),
                        ]);
                      }).toList(),
                    ],
                  ),
                  pw.Divider(height: 4, thickness: 0.4),
                  if (pageIndex == totalPages - 1) ...[
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            summaryRow('الاجمالي قبل الخصم:', currentTotalAmount(invoiceItems), font),
                            pw.SizedBox(width: 10),
                            summaryRow('الخصم:', discount, font),
                            pw.SizedBox(width: 10),
                            summaryRow('الاجمالي بعد الخصم:', afterDiscount, font),
                            pw.SizedBox(width: 10),
                            summaryRow('المبلغ المدفوع:', paid, font, color: PdfColor.fromInt(appSettings.paidAmountColor)),
                          ],
                        ),
                        pw.SizedBox(height: 6),
                        if ((invoiceToManage?.status == 'محفوظة') && !(invoiceToManage?.isLocked ?? false)) ...[
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              summaryRow('المبلغ المتبقي:', remaining, font, color: PdfColor.fromInt(appSettings.remainingAmountColor)),
                              pw.SizedBox(width: 10),
                              summaryRow('الدين السابق:', previousDebt, font),
                              pw.SizedBox(width: 10),
                              summaryRow('الدين الحالي:', currentDebt, font),
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
                  // طبقة أمامية: كلمة الناصر نصف شفافة من بداية الجدول حتى أسفل الصفحة
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

  // وثيقة تجهيز بدون أسعار أو مبالغ (تسلسل، ID، التفاصيل، العدد، نوع البيع فقط)
  static Future<pw.Document> generatePickingListPdf({
    required List<InvoiceItem> invoiceItems,
    required List<Product> allProducts,
    required String customerName,
    required int invoiceId,
    required DateTime selectedDate,
    required pw.Font font,
    required pw.Font alnaserFont,
    required pw.MemoryImage logoImage,
    required AppSettings appSettings,
  }) async {
    final pdf = pw.Document();
    const itemsPerPage = 28;
    final totalPages = (invoiceItems.length / itemsPerPage).ceil().clamp(1, 9999);
    for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final start = pageIndex * itemsPerPage;
      final end = (start + itemsPerPage) > invoiceItems.length
          ? invoiceItems.length
          : start + itemsPerPage;
      final pageItems = invoiceItems.sublist(start, end);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Stack(
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('قائمة تجهيز - فاتورة #$invoiceId',
                              style: pw.TextStyle(
                                  font: alnaserFont,
                                  fontSize: 20,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.SizedBox(height: 4),
                          pw.Text('العميل: $customerName',
                              style: pw.TextStyle(font: font, fontSize: 12)),
                          pw.Text(
                              'التاريخ: ${selectedDate.year}/${selectedDate.month}/${selectedDate.day}',
                              style: pw.TextStyle(font: font, fontSize: 12)),
                          ...appSettings.phoneNumbers.map((number) => pw.Text(number, style: pw.TextStyle(font: font, fontSize: 12))),
                        ],
                      ),
                      pw.Container(width: 80, height: 80, child: pw.Image(logoImage))
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  // جدول عناصر التجهيز بالعكس بصرياً: نرتب الأعمدة من اليسار إلى اليمين كالتالي
                  // التأشيرة، العدد، نوع البيع، التفاصيل، ID، ت (ليظهر ت أقصى اليمين)
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.2),
                    columnWidths: const {
                      0: pw.FixedColumnWidth(70),  // التأشيرة (أقصى اليسار)
                      1: pw.FixedColumnWidth(70),  // العدد
                      2: pw.FixedColumnWidth(70),  // نوع البيع
                      3: pw.FlexColumnWidth(1.2),  // التفاصيل
                      4: pw.FixedColumnWidth(60),  // ID
                      5: pw.FixedColumnWidth(22),  // ت (أقصى اليمين)
                    },
                    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
                    children: [
                       pw.TableRow(children: [
                         headerCell('التأشيرة', font),
                         headerCell('العدد', font, color: PdfColor.fromInt(appSettings.itemQuantityColor)),
                         headerCell('نوع البيع', font),
                         headerCell('التفاصيل', font, color: PdfColor.fromInt(appSettings.itemDetailsColor)),
                         headerCell('ID', font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                         headerCell('ت', font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                       ]),
                      ...pageItems.asMap().entries.map((entry) {
                        final idx = entry.key + (pageIndex * itemsPerPage);
                        final item = entry.value;
                        final quantity = (item.quantityIndividual ?? item.quantityLargeUnit ?? 0.0);
                        Product? product;
                        try {
                          product = allProducts.firstWhere((p) => p.name == item.productName);
                        } catch (_) {}
                          return pw.TableRow(children: [
                            dataCell('', font), // التأشيرة
                            dataCell('${formatNumber(quantity, forceDecimal: true)}', font, color: PdfColor.fromInt(appSettings.itemQuantityColor)),
                            dataCell(item.saleType ?? '', font),
                            dataCell(item.productName, font, align: pw.TextAlign.right, color: PdfColor.fromInt(appSettings.itemDetailsColor)),
                            dataCell(formatProductId(product?.id), font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                            dataCell('${idx + 1}', font, color: PdfColor.fromInt(appSettings.itemSerialColor)),
                          ]);
                      }).toList(),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Align(
                    alignment: pw.Alignment.center,
                    child: pw.Text('صفحة ${pageIndex + 1} من $totalPages',
                        style: pw.TextStyle(font: font, fontSize: 11)),
                  ),
                    ],
                  ),
                  pw.Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: pw.Container(
                      alignment: pw.Alignment.topLeft,
                      padding: const pw.EdgeInsets.only(top: 250, left: 0),
                      child: pw.Transform.rotate(
                        angle: 0.8,
                        child: pw.Opacity(
                          opacity: 0.1,
                          child: pw.Text(
                            'الناصر',
                            style: pw.TextStyle(
                              font: alnaserFont,
                              fontSize: 220,
                              color: PdfColors.grey400,
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

  static pw.Widget headerCell(String text, pw.Font font, {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font, fontSize: 13, fontWeight: pw.FontWeight.bold, color: color ?? PdfColors.black),
          textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget dataCell(String text, pw.Font font,
      {pw.TextAlign align = pw.TextAlign.center, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font, fontSize: 13, fontWeight: pw.FontWeight.bold, color: color ?? PdfColors.black),
          textAlign: align),
    );
  }

  static String formatProductId(int? id) {
    // عرض المعرّف كما هو بدون حشو أصفار أو الهاشتاق
    if (id == null) return '';
    return id.toString();
  }

  static pw.Widget summaryRow(String label, num value, pw.Font font, {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 11, color: color)),
          pw.SizedBox(width: 5),
          pw.Text(formatNumber(value, forceDecimal: true),
              style: pw.TextStyle(
                  font: font, fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  static String buildUnitConversionStringForPdf(InvoiceItem item, Product? product) {
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

  static String formatNumber(num value, {bool forceDecimal = false}) {
    if (forceDecimal) {
      return value % 1 == 0 ? value.toInt().toString() : value.toString();
    }
    return value.toInt().toString();
  }

  static double currentTotalAmount(List<InvoiceItem> invoiceItems) {
    return invoiceItems.fold(0, (sum, item) => sum + item.itemTotal);
  }

  static Future<String?> getSavePath(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/$fileName';
    final file = File(path);
    if (await file.exists()) {
      final result = await showDialog<bool>(
        context: navigatorKey.currentContext!,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('تأكيد الحفظ'),
            content: Text('الملف "$fileName" موجود بالفعل. هل تريد استبداله؟'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('لا'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('نعم'),
              ),
            ],
          );
        },
      );
      if (result == true) {
        await file.delete();
        return path;
      }
      return null;
    }
    return path;
  }

  static final navigatorKey = GlobalKey<NavigatorState>();
}
