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
              child: pw.Column(
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
                            pw.Center(
                              child: pw.Text(
                                  '0771 406 3064  |  0770 305 1353',
                                  style: pw.TextStyle(
                                      font: font,
                                      fontSize: 13,
                                      color: PdfColors.black)),
                            ),
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
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.2),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(20), // تسلسل
                      1: const pw.FixedColumnWidth(90), // المبلغ
                      2: const pw.FixedColumnWidth(35), // ID
                      3: const pw.FixedColumnWidth(70), // السعر
                      4: const pw.FixedColumnWidth(65), // عدد الوحدات
                      5: const pw.FixedColumnWidth(80), // العدد
                      6: const pw.FlexColumnWidth(0.8), // التفاصيل
                    },
                    defaultVerticalAlignment:
                        pw.TableCellVerticalAlignment.middle,
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(),
                        children: [
                          headerCell('ت', font),
                          headerCell('المبلغ', font),
                          headerCell('ID', font),
                          headerCell('السعر', font),
                          headerCell('عدد الوحدات', font),
                          headerCell('العدد', font),
                          headerCell('التفاصيل ', font),
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
                        return pw.TableRow(
                          children: [
                            dataCell('${index + 1}', font),
                            dataCell(formatNumber(item.itemTotal, forceDecimal: true), font),
                            dataCell(formatProductId(product?.id), font),
                            dataCell(formatNumber(item.appliedPrice, forceDecimal: true), font),
                            dataCell(buildUnitConversionStringForPdf(item, product), font),
                            dataCell('${formatNumber(quantity, forceDecimal: true)} ${item.saleType ?? ''}', font),
                            dataCell(item.productName, font, align: pw.TextAlign.right),
                          ],
                        );
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
                            summaryRow('المبلغ المدفوع:', paid, font),
                          ],
                        ),
                        pw.SizedBox(height: 6),
                        if ((invoiceToManage?.status == 'محفوظة') && !(invoiceToManage?.isLocked ?? false)) ...[
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.end,
                            children: [
                              summaryRow('المبلغ المتبقي:', remaining, font),
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
            );
          },
        ),
      );
    }
    return pdf;
  }

  static pw.Widget headerCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget dataCell(String text, pw.Font font,
      {pw.TextAlign align = pw.TextAlign.center}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font, fontSize: 13, fontWeight: pw.FontWeight.bold),
          textAlign: align),
    );
  }

  static String formatProductId(int? id) {
    if (id == null) return '-----';
    final s = id.toString();
    if (s.length >= 5) return s.substring(0, 5);
    return s.padLeft(5, '0');
  }

  static pw.Widget summaryRow(String label, num value, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 11)),
          pw.SizedBox(width: 5),
          pw.Text(formatNumber(value, forceDecimal: true),
              style: pw.TextStyle(
                  font: font, fontSize: 13, fontWeight: pw.FontWeight.bold)),
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
