// lib/screens/invoice_actions.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as pp;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_settings.dart';
import '../models/customer.dart';
import '../models/invoice.dart';
import '../models/invoice_adjustment.dart';
import '../models/invoice_item.dart';
import '../models/printer_device.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../services/drive_service.dart';
import '../services/pdf_header.dart';
import '../services/pdf_service.dart';
import '../services/printing_service.dart';
import '../services/settings_manager.dart';
import 'create_invoice_screen.dart';

/// واجهة تحدد المتغيرات المطلوبة للتعامل مع الفواتير
abstract class InvoiceActionsInterface {
  bool get isSaving;
  set isSaving(bool value);
  
  GlobalKey<FormState> get formKey;
  
  Invoice? get invoiceToManage;
  set invoiceToManage(Invoice? value);
  
  TextEditingController get customerNameController;
  TextEditingController get customerPhoneController;
  TextEditingController get customerAddressController;
  TextEditingController get installerNameController;
  TextEditingController get paidAmountController;
  TextEditingController get loadingFeeController;
  
  List<InvoiceItem> get invoiceItems;
  
  double get discount;
  set discount(double value);
  
  String get paymentType;
  set paymentType(String value);
  
  DateTime get selectedDate;
  set selectedDate(DateTime value);
  
  DatabaseService get db;
  
  bool get isViewOnly;
  set isViewOnly(bool value);
  
  bool get savedOrSuspended;
  set savedOrSuspended(bool value);
  
  bool get hasUnsavedChanges;
  set hasUnsavedChanges(bool value);
  
  PrinterDevice? get selectedPrinter;
  set selectedPrinter(PrinterDevice? value);
  
  PrintingService get printingService;
  
  FlutterSecureStorage get storage;
}

/// Mixin للتعامل مع عمليات الفواتير
mixin InvoiceActionsMixin on State<CreateInvoiceScreen> implements InvoiceActionsInterface {
// الدوال المساعدة التي تم نقلها
  String formatNumber(num value, {bool forceDecimal = false}) {
    final formatter = NumberFormat('#,##0.##', 'en_US');
    return formatter.format(value);
  }

  String _normalizePhoneNumber(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    }
    if (cleaned.startsWith('0')) {
      cleaned = '964' + cleaned.substring(1);
    }
    if (!cleaned.startsWith('964')) {
      cleaned = '964' + cleaned;
    }
    return cleaned;
  }

  bool _isInvoiceItemComplete(InvoiceItem item) {
    return (item.productName.isNotEmpty &&
        (item.quantityIndividual != null || item.quantityLargeUnit != null) &&
        item.appliedPrice > 0 &&
        item.itemTotal > 0 &&
        (item.saleType != null && item.saleType!.isNotEmpty));
  }

  double calculateActualCostPrice(
      Product product, String saleUnit, double quantity) {
    final double baseCost = product.costPrice ?? 0.0;
    if ((product.unit == 'piece' && saleUnit == 'قطعة') ||
        (product.unit == 'meter' && saleUnit == 'متر')) {
      return baseCost;
    }
    Map<String, double> unitCosts = const {};
    try {
      unitCosts = product.getUnitCostsMap();
    } catch (_) {}
    final double? stored = unitCosts[saleUnit];
    if (stored != null && stored > 0) {
      return stored;
    }
    if (product.unit == 'meter' && saleUnit == 'لفة') {
      final double lengthPerUnit = product.lengthPerUnit ?? 1.0;
      return baseCost * lengthPerUnit;
    }
    if (product.unit == 'piece' &&
        product.unitHierarchy != null &&
        product.unitHierarchy!.isNotEmpty) {
      try {
        final List<dynamic> hierarchy =
            jsonDecode(product.unitHierarchy!) as List<dynamic>;
        double multiplier = 1.0;
        for (final level in hierarchy) {
          final String unitName =
              (level['unit_name'] ?? level['name'] ?? '').toString();
          final double qty = (level['quantity'] is num)
              ? (level['quantity'] as num).toDouble()
              : double.tryParse(level['quantity'].toString()) ?? 1.0;
          multiplier *= qty;
          if (unitName == saleUnit) {
            return baseCost * multiplier;
          }
        }
      } catch (e) {
        print('خطأ في حساب التكلفة الهيراركية: $e');
      }
    }
    return baseCost;
  }

  Future<String> saveInvoicePdf(
      pw.Document pdf, String customerName, DateTime invoiceDate) async {
    try {
      final safeCustomerName =
          customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '');
      final formattedDate = DateFormat('yyyy-MM-dd').format(invoiceDate);
      final fileName = '${safeCustomerName}_$formattedDate.pdf';

      final String? userProfile = Platform.environment['USERPROFILE'];
      if (userProfile == null) {
        throw Exception('Could not find user profile directory.');
      }
      final directory = Directory(p.join(userProfile, 'Documents', 'invoices'));

      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final filePath = p.join(directory.path, fileName);
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());
      return filePath;
    } catch (e) {
      print('Error saving PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حفظ ملف PDF: $e')),
        );
      }
      rethrow;
    }
  }

  Future<String> saveInvoicePdfToTemp(
      pw.Document pdf, String customerName, DateTime invoiceDate) async {
    final safeCustomerName =
        customerName.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '');
    final formattedDate = DateFormat('yyyy-MM-dd').format(invoiceDate);
    final fileName = '${safeCustomerName}_$formattedDate.pdf';
    final dir = await pp.getTemporaryDirectory();
    final folder = Directory(p.join(dir.path, 'invoices_share_cache'));
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final filePath = p.join(folder.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save(), flush: true);
    return filePath;
  }

  pw.Widget _headerCell(String text, pw.Font font, {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: color ?? PdfColors.black),
          textAlign: pw.TextAlign.center),
    );
  }

  pw.Widget _dataCell(String text, pw.Font font,
      {pw.TextAlign align = pw.TextAlign.center, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(text,
          style: pw.TextStyle(
              font: font,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: color ?? PdfColors.black),
          textAlign: align),
    );
  }

  pw.Widget _summaryRow(String label, num value, pw.Font font,
      {PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label,
              style: pw.TextStyle(font: font, fontSize: 11, color: color)),
          pw.SizedBox(width: 5),
          pw.Text(formatNumber(value, forceDecimal: true),
              style: pw.TextStyle(
                  font: font,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

// ============================================
// 1. دالة حفظ الفاتورة (saveInvoice)
// ============================================
  Future<Invoice?> saveInvoice({bool printAfterSave = false}) async {
    if (isSaving) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('جاري الحفظ بالفعل...'),
        backgroundColor: Colors.orange,
      ));
      return null;
    }

    if (!formKey.currentState!.validate()) return null;

    setState(() {
      isSaving = true;
    });

    try {
      final bool isNewInvoice = invoiceToManage == null;

      if (!isNewInvoice && invoiceToManage?.id == null) {
        throw Exception('خطأ فادح: محاولة تعديل فاتورة بدون معرّف (ID).');
      }

      final db = DatabaseService();
      Invoice? savedInvoice;

      await (await db.database).transaction((txn) async {
        Customer? customer;
        if (customerNameController.text.trim().isNotEmpty) {
          String? normalizedPhone;
          if (customerPhoneController.text.trim().isNotEmpty) {
            normalizedPhone =
                _normalizePhoneNumber(customerPhoneController.text.trim());
          }

          final normalizedName =
              customerNameController.text.trim().replaceAll(' ', '');
          List<Map<String, dynamic>> customerMaps;
          if (normalizedPhone != null && normalizedPhone.trim().isNotEmpty) {
            customerMaps = await txn.rawQuery(
              "SELECT * FROM customers WHERE REPLACE(name, ' ', '') = ? AND phone = ? LIMIT 1",
              [normalizedName, normalizedPhone.trim()],
            );
          } else {
            customerMaps = await txn.rawQuery(
              "SELECT * FROM customers WHERE REPLACE(name, ' ', '') = ? LIMIT 1",
              [normalizedName],
            );
          }

          if (customerMaps.isNotEmpty) {
            customer = Customer.fromMap(customerMaps.first);
          }

          if (customer == null) {
            customer = Customer(
              id: null,
              name: customerNameController.text.trim(),
              phone: normalizedPhone,
              address: customerAddressController.text.trim(),
              createdAt: DateTime.now(),
              lastModifiedAt: DateTime.now(),
              currentTotalDebt: 0.0,
            );
            final insertedId = await txn.insert('customers', customer.toMap());
            customer = customer.copyWith(id: insertedId);
          }
        }

        double currentTotalAmount =
            invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        final double loadingFee =
            double.tryParse(loadingFeeController.text.replaceAll(',', '')) ??
                0.0;
        double totalAmount = (currentTotalAmount + loadingFee) - discount;

        double paid =
            double.tryParse(paidAmountController.text.replaceAll(',', '')) ??
                0.0;
        if (invoiceToManage != null && paymentType == 'نقد') {
          paid = totalAmount;
          paidAmountController.text = formatNumber(paid);
        }

        final totalAmountForDiscount =
            invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
        if (discount >= totalAmountForDiscount) {
          throw Exception(
              'نسبة الخصم خاطئة! (الخصم: ${discount.toStringAsFixed(2)} الإجمالي: ${totalAmountForDiscount.toStringAsFixed(2)})');
        }

        String newStatus = 'محفوظة';
        bool newIsLocked = invoiceToManage?.isLocked ?? false;

        if (invoiceToManage != null) {
          if (invoiceToManage!.status == 'معلقة') {
            newStatus = 'محفوظة';
            newIsLocked = false;
          }
        } else {
          newIsLocked = false;
        }

        String? normalizedPhoneForInvoice;
        if (customerPhoneController.text.trim().isNotEmpty) {
          normalizedPhoneForInvoice =
              _normalizePhoneNumber(customerPhoneController.text.trim());
        }

        Invoice invoice = Invoice(
          id: invoiceToManage?.id,
          customerName: customerNameController.text,
          customerPhone: normalizedPhoneForInvoice,
          customerAddress: customerAddressController.text,
          installerName: installerNameController.text.isEmpty
              ? null
              : installerNameController.text,
          invoiceDate: selectedDate,
          paymentType: paymentType,
          totalAmount: totalAmount,
          discount: discount,
          amountPaidOnInvoice: paid,
          loadingFee: loadingFee,
          createdAt: invoiceToManage?.createdAt ?? DateTime.now(),
          lastModifiedAt: DateTime.now(),
          customerId: customer?.id,
          status: newStatus,
          isLocked: false,
        );

        int invoiceId;
        if (isNewInvoice) {
          invoiceId = await txn.insert('invoices', invoice.toMap());
          invoice = invoice.copyWith(id: invoiceId);
        } else {
          invoiceId = invoiceToManage!.id!;
          await txn.update('invoices', invoice.toMap(),
              where: 'id = ?', whereArgs: [invoiceId]);
        }

        await txn
            .delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);

        final products = await txn.rawQuery('SELECT * FROM products');
        final productMap = <String, Map<String, dynamic>>{};
        for (var productData in products) {
          final productName = productData['name'] as String?;
          if (productName != null) {
            productMap[productName] = productData;
          }
        }

        final batch = txn.batch();

        for (var item in invoiceItems) {
          if (_isInvoiceItemComplete(item)) {
            final productData = productMap[item.productName];
            Product matchedProduct;

            if (productData != null) {
              matchedProduct = Product.fromMap(productData);
            } else {
              matchedProduct = Product(
                name: '',
                unit: '',
                unitPrice: 0.0,
                price1: 0.0,
                createdAt: DateTime.now(),
                lastModifiedAt: DateTime.now(),
              );
            }

            final actualCostPrice = calculateActualCostPrice(
                matchedProduct,
                item.saleType ?? 'قطعة',
                item.quantityIndividual ?? item.quantityLargeUnit ?? 0);

            final invoiceItem = item.copyWith(
              invoiceId: invoiceId,
              actualCostPrice: actualCostPrice,
            );

            var itemMap = invoiceItem.toMap();
            itemMap.remove('id');
            batch.insert('invoice_items', itemMap);
          }
        }
        await batch.commit(noResult: true);

        if (customer != null && paymentType == 'دين') {
          double debtChange = 0.0;
          String transactionDescription = '';

          if (isNewInvoice) {
            final newRemaining = totalAmount - paid;
            debtChange = newRemaining;
            transactionDescription = 'دين فاتورة جديدة رقم $invoiceId';
          } else {
            final oldInvoice = widget.existingInvoice!;
            final oldRemaining =
                oldInvoice.totalAmount - oldInvoice.amountPaidOnInvoice;
            final newRemaining = totalAmount - paid;
            debtChange = newRemaining - oldRemaining;

            if (debtChange.abs() > 0.01) {
              transactionDescription = 'تعديل فاتورة دين رقم $invoiceId';
            } else {
              debtChange = 0.0;
            }
          }

          if (debtChange != 0.0) {
            final updatedCustomer = customer.copyWith(
              currentTotalDebt: (customer.currentTotalDebt) + debtChange,
              lastModifiedAt: DateTime.now(),
            );
            await txn.update(
                'customers',
                {
                  'current_total_debt': updatedCustomer.currentTotalDebt,
                  'last_modified_at': DateTime.now().toIso8601String(),
                },
                where: 'id = ?',
                whereArgs: [customer.id]);

            final txUuid = await DriveService().generateTransactionUuid();
            await txn.insert('transactions', {
              'customer_id': customer.id,
              'transaction_date': DateTime.now().toIso8601String(),
              'amount_changed': debtChange,
              'new_balance_after_transaction': updatedCustomer.currentTotalDebt,
              'transaction_type':
                  isNewInvoice ? 'invoice_debt' : 'invoice_edit',
              'description': transactionDescription,
              'invoice_id': invoiceId,
              'transaction_uuid': txUuid,
              'created_at': DateTime.now().toIso8601String(),
            });
          }
        }

        final maps = await txn
            .query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
        savedInvoice = Invoice.fromMap(maps.first);
      });

      await storage.delete(key: 'temp_invoice_data');
      savedOrSuspended = true;
      hasUnsavedChanges = false;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                isNewInvoice ? 'تم حفظ الفاتورة بنجاح' : 'تم تعديل الفاتورة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {
          invoiceToManage = savedInvoice;
          isViewOnly = true;
        });
        if (isNewInvoice) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }

      return savedInvoice;
    } catch (e) {
      print('خطأ فادح ومُحاط بمعاملة عند حفظ الفاتورة: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('فشل حفظ الفاتورة: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

// ============================================
// 2. دالة إنشاء PDF (generateInvoicePdf)// ============================================
  Future<pw.Document> generateInvoicePdf() async {
    try {
      final pdf = pw.Document();

      final appSettings = await SettingsManager.getAppSettings();

      final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
      final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      final font =
          pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
      final alnaserFont =
          pw.Font.ttf(await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));

      String buildUnitConversionStringForPdf(InvoiceItem item, Product? product) {
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

      final allProducts = await db.getAllProducts();
      final filteredItems =
          invoiceItems.where((item) => _isInvoiceItemComplete(item)).toList();

      final itemsTotal =
          filteredItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final discount = this.discount;
      final double loadingFee =
          double.tryParse(loadingFeeController.text.replaceAll(',', '')) ??
              0.0;

      List<InvoiceAdjustment> adjs = [];
      double settlementsTotal = 0.0;
      if (invoiceToManage != null && invoiceToManage!.id != null) {
        try {
          adjs = await db.getInvoiceAdjustments(invoiceToManage!.id!);
          settlementsTotal = adjs.fold(0.0, (sum, a) => sum + a.amountDelta);
        } catch (_) {}
      }
      final bool hasAdjustments = adjs.isNotEmpty;
      final DateTime invoiceDateOnly = DateTime(
          selectedDate.year, selectedDate.month, selectedDate.day);
      final List<InvoiceAdjustment> sameDayAddedItemAdjs = adjs.where((a) {
        if (a.productId == null) return false;
        if (a.type != 'debit') return false;
        final d =
            DateTime(a.createdAt.year, a.createdAt.month, a.createdAt.day);
        return d == invoiceDateOnly;
      }).toList();
      final List<InvoiceAdjustment> itemAdditionsForSection = adjs
          .where((a) =>
              a.productId != null &&
              a.type == 'debit' &&
              !sameDayAddedItemAdjs.contains(a))
          .toList();
      final List<InvoiceAdjustment> itemCreditsForSection =
          adjs.where((a) => a.productId != null && a.type == 'credit').toList();
      final List<InvoiceAdjustment> amountOnlyAdjs =
          adjs.where((a) => a.productId == null).toList();
      final bool showSettlementSections = itemAdditionsForSection.isNotEmpty ||
          itemCreditsForSection.isNotEmpty ||
          amountOnlyAdjs.isNotEmpty ||
          sameDayAddedItemAdjs.isNotEmpty;

      final bool includeSameDayOnlyCase =
          sameDayAddedItemAdjs.isNotEmpty && !showSettlementSections;

      final double sameDayAddsTotal =
          sameDayAddedItemAdjs.fold(0.0, (sum, a) {
        final double price = a.price ?? 0.0;
        final double quantity = a.quantity ?? 0.0;
        return sum + (price * quantity);
      });
      final double itemsTotalForDisplay =
          includeSameDayOnlyCase ? (itemsTotal + sameDayAddsTotal) : itemsTotal;
      final double settlementsTotalForDisplay =
          includeSameDayOnlyCase ? 0.0 : settlementsTotal;
      final double preDiscountTotal =
          (itemsTotalForDisplay + settlementsTotalForDisplay + loadingFee);
      final double afterDiscount =
          ((preDiscountTotal - discount).clamp(0.0, double.infinity)).toDouble();

        final double paid =
            double.tryParse(paidAmountController.text.replaceAll(',', '')) ??
                0.0;
        final isCash = paymentType == 'نقد';

      final double cashSettlements = showSettlementSections
          ? [...adjs, ...sameDayAddedItemAdjs]
              .where((a) => a.settlementPaymentType == 'نقد')
              .fold(0.0, (sum, a) {
              if (a.productId != null) {
                final double price = a.price ?? 0.0;
                final double quantity = a.quantity ?? 0.0;
                return sum + (price * quantity);
              } else {
                return sum + a.amountDelta;
              }
            })
          : 0.0;
      final double debtSettlements = showSettlementSections
          ? [...adjs, ...sameDayAddedItemAdjs]
              .where((a) => a.settlementPaymentType == 'دين')
              .fold(0.0, (sum, a) {
              if (a.productId != null) {
                final double price = a.price ?? 0.0;
                final double quantity = a.quantity ?? 0.0;
                return sum + (price * quantity);
              } else {
                return sum + a.amountDelta;
              }
            })
          : 0.0;

      double displayedPaidForSettlementsCase;
      if (isCash && !showSettlementSections) {
        displayedPaidForSettlementsCase = afterDiscount;
      } else {
        displayedPaidForSettlementsCase = paid + cashSettlements;
      }

      double previousDebt = 0.0;
      double currentDebt = 0.0;
        final customerName = customerNameController.text.trim();
        final customerPhone = customerPhoneController.text.trim();
        if (customerName.isNotEmpty) {
          final customers = await db.searchCustomers(customerName);
        Customer? matchedCustomer;
        if (customerPhone.isNotEmpty) {
          matchedCustomer = customers.firstWhere(
            (c) =>
                c.name.trim() == customerName &&
                (c.phone ?? '').trim() == customerPhone,
            orElse: () => Customer(
                id: null,
                name: '',
                phone: null,
                address: null,
                createdAt: DateTime.now(),
                lastModifiedAt: DateTime.now(),
                currentTotalDebt: 0.0), // Dummy to avoid exception
          );
          if (matchedCustomer?.name == '' || matchedCustomer == null) matchedCustomer = null;
        } else {
          matchedCustomer = customers.firstWhere(
            (c) => c.name.trim() == customerName,
            orElse: () => Customer(
                id: null,
                name: '',
                phone: null,
                address: null,
                createdAt: DateTime.now(),
                lastModifiedAt: DateTime.now(),
                currentTotalDebt: 0.0), // Dummy
          );
          if (matchedCustomer?.name == '' || matchedCustomer == null) matchedCustomer = null;
        }
        if (matchedCustomer != null) {
          previousDebt = matchedCustomer.currentTotalDebt;
        }
      }

      final double remainingForPdf;
      if (isCash && !showSettlementSections) {
        remainingForPdf = 0;
      } else {
        remainingForPdf = afterDiscount - displayedPaidForSettlementsCase;
      }

      if (showSettlementSections) {
        currentDebt = previousDebt + debtSettlements;
      } else {
        if (isCash) {
          currentDebt = previousDebt;
        } else {
          currentDebt = previousDebt + remainingForPdf;
        }
      }

        final double currentDebtForPdf =
            (invoiceToManage != null && invoiceToManage!.status == 'محفوظة')
                ? previousDebt
                : currentDebt;

      int invoiceId;
      if (invoiceToManage != null && invoiceToManage!.id != null) {
        invoiceId = invoiceToManage!.id!;
      } else {
        invoiceId = (await db.getLastInvoiceId()) + 1;
      }

      final List<Map<String, dynamic>> combinedRows = [
        ...filteredItems.map((it) => {'type': 'item', 'item': it}),
        if (includeSameDayOnlyCase)
          ...sameDayAddedItemAdjs.map((a) => {'type': 'adj', 'adj': a}),
      ];

      const itemsPerPage = 19;
      final totalPages =
          (combinedRows.length / itemsPerPage).ceil().clamp(1, double.infinity).toInt();
      bool printedSummaryInLastPage = false;

      for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
        final start = pageIndex * itemsPerPage;
        final end = (start + itemsPerPage) > combinedRows.length
            ? combinedRows.length
            : start + itemsPerPage;
        final pageRows = combinedRows.sublist(start, end);

        final bool isLast = pageIndex == totalPages - 1;
        final bool deferSummary =
            isLast && (pageRows.length >= 17) && showSettlementSections;

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
                        buildPdfHeader(font, alnaserFont, logoImage,
                            appSettings: appSettings),
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text('السيد: ${customerNameController.text}',
                                style: pw.TextStyle(font: font, fontSize: 12)),
                            pw.Text(
                                'العنوان: ${customerAddressController.text.isNotEmpty ? customerAddressController.text : ' ______'}',
                                style: pw.TextStyle(font: font, fontSize: 11)),
                            pw.Text('رقم الفاتورة: $invoiceId',
                                style: pw.TextStyle(font: font, fontSize: 10)),
                            pw.Text(
                                'الوقت: ${invoiceToManage?.createdAt?.hour.toString().padLeft(2, '0') ?? DateTime.now().hour.toString().padLeft(2, '0')}:${invoiceToManage?.createdAt?.minute.toString().padLeft(2, '0') ?? DateTime.now().minute.toString().padLeft(2, '0')}',
                                style: pw.TextStyle(font: font, fontSize: 11)),
                            pw.Text(
                                'التاريخ: ${selectedDate.year}/${selectedDate.month}/${selectedDate.day}',
                                style: pw.TextStyle(font: font, fontSize: 11)),
                          ],
                        ),
                        pw.Divider(height: 5, thickness: 0.5),
                        pw.Table(
                          border: pw.TableBorder.all(width: 0.2),
                          columnWidths: {
                            0: const pw.FixedColumnWidth(90),
                            1: const pw.FixedColumnWidth(70),
                            2: const pw.FixedColumnWidth(65),
                            3: const pw.FixedColumnWidth(90),
                            4: const pw.FlexColumnWidth(0.8),
                            5: const pw.FixedColumnWidth(45),
                            6: const pw.FixedColumnWidth(20),
                          },
                          defaultVerticalAlignment:
                              pw.TableCellVerticalAlignment.middle,
                          children: [
                            pw.TableRow(
                              children: [
                                _headerCell('المبلغ', font,
                                    color: PdfColor.fromInt(
                                        appSettings.itemTotalColor)),
                                _headerCell('السعر', font,
                                    color: PdfColor.fromInt(
                                        appSettings.itemPriceColor)),
                                _headerCell('عدد الوحدات', font),
                                _headerCell('العدد', font,
                                    color: PdfColor.fromInt(
                                        appSettings.itemQuantityColor)),
                                _headerCell('التفاصيل ', font,
                                    color: PdfColor.fromInt(
                                        appSettings.itemDetailsColor)),
                                _headerCell('ID', font,
                                    color: PdfColor.fromInt(
                                        appSettings.itemSerialColor)),
                                _headerCell('ت', font,
                                    color: PdfColor.fromInt(
                                        appSettings.itemSerialColor)),
                              ],
                            ),
                            ...pageRows.asMap().entries.map((entry) {
                              final index = entry.key + (pageIndex * itemsPerPage);
                              final row = entry.value;
                              if (row['type'] == 'item') {
                                final item = row['item'] as InvoiceItem;
                                final quantity =
                                    (item.quantityIndividual ??
                                            item.quantityLargeUnit ??
                                            0.0);
                                Product? product;
                                try {
                                  product = allProducts
                                      .firstWhere((p) => p.name == item.productName);
                                } catch (e) {
                                  product = null;
                                }
                                final idText = formatProductId5(product?.id);
                                return pw.TableRow(
                                  children: [
                                    _dataCell(
                                        formatNumber(item.itemTotal,
                                            forceDecimal: true),
                                        font,
                                        color: PdfColor.fromInt(
                                            appSettings.itemTotalColor)),
                                    _dataCell(
                                        formatNumber(item.appliedPrice,
                                            forceDecimal: true),
                                        font,
                                        color: PdfColor.fromInt(
                                            appSettings.itemPriceColor)),
                                    _dataCell(
                                        buildUnitConversionStringForPdf(
                                            item, product),
                                        font),
                                    _dataCell(
                                        '${formatNumber(quantity, forceDecimal: true)} ${item.saleType ?? ''}',
                                        font,
                                        color: PdfColor.fromInt(
                                            appSettings.itemQuantityColor)),
                                    _dataCell(item.productName, font,
                                        align: pw.TextAlign.right,
                                        color: PdfColor.fromInt(
                                            appSettings.itemDetailsColor)),
                                    _dataCell(idText, font,
                                        color: PdfColor.fromInt(
                                            appSettings.itemSerialColor)),
                                    _dataCell('${index + 1}', font,
                                        color: PdfColor.fromInt(
                                            appSettings.itemSerialColor)),
                                  ],
                                );
                              } else {
                                final a = row['adj'] as InvoiceAdjustment;
                                final double price = a.price ?? 0.0;
                                final double qty = a.quantity ?? 0.0;
                                final double total = a.amountDelta != 0.0
                                    ? a.amountDelta
                                    : (price * qty);
                                Product? product;
                                try {
                                  product = allProducts
                                      .firstWhere((p) => p.id == a.productId);
                                } catch (e) {
                                  product = null;
                                }
                                final idText = formatProductId5(product?.id);
                                final unitConv = () {
                                  try {
                                    if (product == null ||
                                        product.unitHierarchy == null ||
                                        product.unitHierarchy!.isEmpty)
                                      return (a.unitsInLargeUnit?.toString() ??
                                          '');
                                    final List<dynamic> hierarchy = json.decode(
                                        product.unitHierarchy!.replaceAll("'", '"'));
                                    List<String> factors = [];
                                    for (int i = 0; i < hierarchy.length; i++) {
                                      final unitName =
                                          hierarchy[i]['unit_name'] ??
                                              hierarchy[i]['name'];
                                      final quantity = hierarchy[i]['quantity'];
                                      factors.add(quantity.toString());
                                      if (unitName == a.saleType) break;
                                    }
                                    return factors.isEmpty
                                        ? a.unitsInLargeUnit?.toString() ?? ''
                                        : factors.join(' × ');
                                  } catch (_) {
                                    return a.unitsInLargeUnit?.toString() ?? '';
                                  }
                                }();
                                return pw.TableRow(
                                  children: [
                                    _dataCell(
                                        formatNumber(total, forceDecimal: true),
                                        font,
                                        color: PdfColor.fromInt(
                                            appSettings.itemTotalColor)),
                                    _dataCell(
                                        formatNumber(price, forceDecimal: true),
                                        font,
                                        color: PdfColor.fromInt(
                                            appSettings.itemPriceColor)),
                                    _dataCell(unitConv, font),
                                    _dataCell(
                                        '${formatNumber(qty, forceDecimal: true)} ${a.saleType ?? ''}',
                                        font,
                                        color: PdfColor.fromInt(
                                            appSettings.itemQuantityColor)),
                                    _dataCell(a.productName ?? '-', font,
                                        align: pw.TextAlign.right,
                                        color: PdfColor.fromInt(
                                            appSettings.itemDetailsColor)),
                                    _dataCell(idText, font,
                                        color: PdfColor.fromInt(
                                            appSettings.itemSerialColor)),
                                    _dataCell('${index + 1}', font,
                                        color: PdfColor.fromInt(
                                            appSettings.itemSerialColor)),
                                  ],
                                );
                              }
                            }).toList(),
                          ],
                        ),
                        pw.Divider(height: 4, thickness: 0.4),
                        if (isLast && !deferSummary) ...[
                          if (invoiceToManage != null &&
                              invoiceToManage!.id != null &&
                              (itemAdditionsForSection.isNotEmpty ||
                                  itemCreditsForSection.isNotEmpty ||
                                  amountOnlyAdjs.isNotEmpty)) ...[
                            // ... (All settlement sections code)
                          ],
                          pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: [
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.end,
                                  children: [
                                    _summaryRow("الإجمالي قبل الخصم", preDiscountTotal, font,
                                        color: PdfColor.fromInt(appSettings.totalBeforeDiscountColor)),
                                    pw.SizedBox(width: 10),
                                    _summaryRow("الخصم", discount, font,
                                        color: PdfColor.fromInt(appSettings.discountColor)),
                                    pw.SizedBox(width: 10),
                                    _summaryRow("الإجمالي بعد الخصم", afterDiscount, font,
                                        color: PdfColor.fromInt(appSettings.totalAfterDiscountColor)),
                                    pw.SizedBox(width: 10),
                                    _summaryRow("المبلغ المدفوع", displayedPaidForSettlementsCase, font,
                                        color: PdfColor.fromInt(appSettings.paidAmountColor)),
                                  ],
                                ),
                                pw.SizedBox(height: 4),
                                pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.end,
                                  children: [
                                    _summaryRow("المبلغ المتبقي", remainingForPdf, font,
                                        color: PdfColor.fromInt(appSettings.remainingAmountColor)),
                                    pw.SizedBox(width: 10),
                                    _summaryRow("المبلغ المطلوب الحالي", currentDebtForPdf, font,
                                        color: PdfColor.fromInt(appSettings.currentDebtColor)),
                                    pw.SizedBox(width: 10),
                                    _summaryRow("أجور التحميل", loadingFee, font,
                                        color: PdfColor.fromInt(appSettings.loadingFeesColor)),
                                  ],
                                ),
                              ]),
                          pw.SizedBox(height: 6),
                          pw.Align(
                              child: pw.Text(
                                  'تنويه: أي ملاحظات على تجهيز المواد تُقبل خلال 3 أيام من تاريخ الفاتورة فقط  وشكراً لتعاملكم معنا',
                                  style: pw.TextStyle(
                                      font: font,
                                      fontSize: 11,
                                      color: PdfColor.fromInt(
                                          appSettings.noticeColor)))),
                        ],
                        pw.Spacer(),
                        pw.Align(
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            'صفحة ${pageIndex + 1} من $totalPages',
                            style: pw.TextStyle(font: font, fontSize: 11),
                          ),
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
                            opacity: 0.11,
                            child: pw.Text('الناصر',
                                style: pw.TextStyle(
                                    font: alnaserFont,
                                    fontSize: 220,
                                    color: PdfColors.grey400,
                                    fontWeight: pw.FontWeight.bold)),
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
        if (isLast && !deferSummary) {
          printedSummaryInLastPage = true;
        }
      }

      if (!printedSummaryInLastPage) {
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.only(top: 10, bottom: 10, left: 10, right: 10),
          build: (pw.Context context) {
            // Logic for the deferred summary page
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text("ملخص الفاتورة",
                    style:
                        pw.TextStyle(font: font, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Divider(),
                // Re-add your summary rows here
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    _summaryRow("الإجمالي قبل الخصم", preDiscountTotal, font,
                        color: PdfColor.fromInt(appSettings.totalBeforeDiscountColor)),
                    pw.SizedBox(width: 10),
                    _summaryRow("الخصم", discount, font,
                        color: PdfColor.fromInt(appSettings.discountColor)),
                    pw.SizedBox(width: 10),
                    _summaryRow("الإجمالي بعد الخصم", afterDiscount, font,
                        color: PdfColor.fromInt(appSettings.totalAfterDiscountColor)),
                    pw.SizedBox(width: 10),
                    _summaryRow("المبلغ المدفوع", displayedPaidForSettlementsCase, font,
                        color: PdfColor.fromInt(appSettings.paidAmountColor)),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    _summaryRow("المبلغ المتبقي", remainingForPdf, font,
                        color: PdfColor.fromInt(appSettings.remainingAmountColor)),
                    pw.SizedBox(width: 10),
                    _summaryRow("المبلغ المطلوب الحالي", currentDebtForPdf, font,
                        color: PdfColor.fromInt(appSettings.currentDebtColor)),
                    pw.SizedBox(width: 10),
                    _summaryRow("أجور التحميل", loadingFee, font,
                        color: PdfColor.fromInt(appSettings.loadingFeesColor)),
                  ],
                ),
              ],
            );
          },
        ));
      }
      return pdf;
    } catch (e) {
      print('Error generating PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء إنشاء ملف PDF: $e')),
        );
      }
      rethrow;
    }
  }

// ========================================
// 
// ====
// 3. دالة طباعة الفاتورة (printInvoice)
// ============================================
  Future<void> printInvoice() async {
    try {
      final pdf = await generateInvoicePdf();
      if (Platform.isWindows) {
        final filePath = await saveInvoicePdf(
            pdf, customerNameController.text, selectedDate);
        await Process.start('cmd', ['/c', 'start', '/min', '', filePath]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال الفاتورة للطابعة مباشرة!')),
          );
        }
        return;
      }
      if (Platform.isAndroid) {
        if (selectedPrinter == null) {
          List<PrinterDevice> printers = [];
          final bluetoothPrinters =
              await printingService.findBluetoothPrinters();
          final systemPrinters =
              await printingService.findSystemPrinters();
          printers = [...bluetoothPrinters, ...systemPrinters];
          if (printers.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('لا توجد طابعات متاحة.')),
              );
            }
            return;
          }
          final selected = await showDialog<PrinterDevice>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('اختر الطابعة'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: printers.length,
                    itemBuilder: (context, index) {
                      final printer = printers[index];
                      return ListTile(
                        title: Text(printer.name),
                        subtitle: Text(printer.connectionType.name),
                        onTap: () => Navigator.of(context).pop(printer),
                      );
                    },
                  ),
                ),
              );
            },
          );
          if (selected == null) return;
          setState(() {
            selectedPrinter = selected;
          });
        }
        if (selectedPrinter != null) {
          try {
            await printingService.printData(
              await pdf.save(),
              printerDevice: selectedPrinter,
              escPosCommands: null,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'تم إرسال الفاتورة إلى الطابعة: ${selectedPrinter!.name}')),
              );
            }
          } catch (e) {
            print('Error during print: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('حدث خطأ أثناء الطباعة: ${e.toString()}')),
              );
            }
          }
        }
        return;
      }
    } catch (e) {
      print('Error printing invoice: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الطباعة: $e')),
        );
      }
    }
  }

// ============================================
// 4. دالة مشاركة الفاتورة (shareInvoice)
// ============================================
  Future<void> shareInvoice() async {
    try {
      final pdf = await generateInvoicePdf();
      final filePath = await saveInvoicePdfToTemp(
          pdf, customerNameController.text, selectedDate);
      final fileName = p.basename(filePath);
      await Share.shareXFiles([
        XFile(filePath, mimeType: 'application/pdf', name: fileName)
      ], text: 'فاتورة ${customerNameController.text}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل مشاركة الفاتورة: $e')),
        );
      }
    }
  }
}

// Helper function that might be in another file, but is needed for the PDF generation.
String formatProductId5(int? id) {
  if (id == null) return '-----';
  return id.toString().padLeft(5, '0');
}
