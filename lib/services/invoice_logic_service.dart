// services/invoice_logic_service.dart
// جميع منطق الفاتورة والدوال المساعدة (بدون UI)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/customer.dart';
import '../models/installer.dart';
import '../models/transaction.dart';
import '../services/database_service.dart';
import '../models/printer_device.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';
import '../services/drive_service.dart';
import '../services/financial_validation_service.dart';
import '../services/financial_audit_service.dart';

class InvoiceLogicService {
  // هنا يتم نقل جميع الدوال المنطقية من شاشة الفاتورة
  // كل دالة يجب أن تأخذ كل المتغيرات المطلوبة كـ parameters
  // لا تستعمل setState أو ScaffoldMessenger هنا
  // فقط منطق الأعمال (Business Logic)

  // مثال على دالة: (الباقي يتم نقله بنفس الأسلوب)
  static void loadAutoSavedData({
    required bool isViewOnly,
    required Invoice? existingInvoice,
    required GetStorage storage,
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required void Function(DateTime) setSelectedDate,
    required void Function(String) setPaymentType,
    required void Function(double) setDiscount,
    required TextEditingController discountController,
    required TextEditingController paidAmountController,
    required void Function(List<InvoiceItem>) setInvoiceItems,
    required TextEditingController totalAmountController,
  }) {
    if (isViewOnly || existingInvoice != null) {
      return;
    }
    final data = storage.read('temp_invoice_data');
    if (data == null) return;
    customerNameController.text = data['customerName'] ?? '';
    customerPhoneController.text = data['customerPhone'] ?? '';
    customerAddressController.text = data['customerAddress'] ?? '';
    installerNameController.text = data['installerName'] ?? '';
    if (data['selectedDate'] != null) {
      setSelectedDate(DateTime.parse(data['selectedDate']));
    }
    setPaymentType(data['paymentType'] ?? 'نقد');
    setDiscount(data['discount'] ?? 0);
    discountController.text = (data['discount'] ?? 0).toStringAsFixed(2);
    paidAmountController.text = data['paidAmount'] ?? '';
    final items = (data['invoiceItems'] as List<dynamic>).map((item) {
      return InvoiceItem(
        invoiceId: 0,
        productName: item['productName'],
        unit: item['unit'],
        unitPrice: item['unitPrice'],
        costPrice: item['costPrice'] ?? 0,
        quantityIndividual: item['quantityIndividual'],
        quantityLargeUnit: item['quantityLargeUnit'],
        appliedPrice: item['appliedPrice'],
        itemTotal: item['itemTotal'],
        saleType: item['saleType'],
        unitsInLargeUnit: item['unitsInLargeUnit'],
      );
    }).toList();
    setInvoiceItems(items);
    totalAmountController.text = items
        .fold(0.0, (sum, item) => sum + item.itemTotal)
        .toStringAsFixed(2);
  }

  // حفظ البيانات تلقائياً
  static void autoSave({
    required bool savedOrSuspended,
    required bool isViewOnly,
    required Invoice? existingInvoice,
    required GetStorage storage,
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required DateTime selectedDate,
    required String paymentType,
    required double discount,
    required TextEditingController paidAmountController,
    required List<InvoiceItem> invoiceItems,
  }) {
    if (savedOrSuspended || isViewOnly || existingInvoice != null) {
      return;
    }
    final data = {
      'customerName': customerNameController.text,
      'customerPhone': customerPhoneController.text,
      'customerAddress': customerAddressController.text,
      'installerName': installerNameController.text,
      'selectedDate': selectedDate.toIso8601String(),
      'paymentType': paymentType,
      'discount': discount,
      'paidAmount': paidAmountController.text,
      'invoiceItems': invoiceItems
          .map((item) => {
                'productName': item.productName,
                'unit': item.unit,
                'unitPrice': item.unitPrice,
                'costPrice': item.costPrice,
                'quantityIndividual': item.quantityIndividual,
                'quantityLargeUnit': item.quantityLargeUnit,
                'appliedPrice': item.appliedPrice,
                'itemTotal': item.itemTotal,
                'saleType': item.saleType,
                'unitsInLargeUnit': item.unitsInLargeUnit,
              })
          .toList(),
    };
    storage.write('temp_invoice_data', data);
  }

  // معالج تغيير الحقول مع تأخير
  static void onFieldChanged({
    required Timer? debounceTimer,
    required void Function() autoSave,
    required void Function(Timer) setDebounceTimer,
  }) {
    if (debounceTimer?.isActive ?? false) {
      debounceTimer!.cancel();
    }
    final timer = Timer(const Duration(seconds: 1), autoSave);
    setDebounceTimer(timer);
  }

  // باقي الدوال يتم نقلها بنفس الأسلوب ...

  static void recalculateTotals({
    required List<InvoiceItem> invoiceItems,
    required TextEditingController totalAmountController,
    required String paymentType,
    required double discount,
    required TextEditingController paidAmountController,
    required void Function(void Function()) setState,
  }) {
    double total = invoiceItems.fold(0, (sum, item) => sum + item.itemTotal);
    totalAmountController.text = total.toStringAsFixed(2);
    if (paymentType == 'نقد') {
      paidAmountController.text = (total - discount).toStringAsFixed(2);
    }
    setState(() {});
  }

  static Future<Invoice?> saveInvoiceWithBusinessLogic({
    required GlobalKey<FormState> formKey,
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required DateTime selectedDate,
    required String paymentType,
    required double discount,
    required TextEditingController paidAmountController,
    required TextEditingController loadingFeeController,
    required List<InvoiceItem> invoiceItems,
    required Invoice? invoiceToManage,
    required DatabaseService db,
    required TextEditingController returnAmountController,
    required GetStorage storage,
    // يمكن إضافة أي متغيرات أخرى حسب الحاجة
  }) async {
    if (!formKey.currentState!.validate()) return null;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // التحقق من صحة البيانات المالية (Financial Validation)
    // ═══════════════════════════════════════════════════════════════════════════
    
    try {
      // 1. التحقق من وجود أصناف
      final itemsValidation = FinancialValidationService.validateInvoiceItems(invoiceItems.length);
      if (!itemsValidation.isValid) {
        throw Exception(itemsValidation.errorMessage ?? 'لا يمكن حفظ فاتورة بدون أصناف');
      }
      
      // 2. حساب المبالغ
      double currentTotalAmount = invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      double paid = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0;
      final double loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
      
      // 3. التحقق من أجور التحميل
      final loadingFeeValidation = FinancialValidationService.validateLoadingFee(loadingFee);
      if (!loadingFeeValidation.isValid) {
        throw Exception(loadingFeeValidation.errorMessage ?? 'أجور التحميل غير صحيحة');
      }
      
      // 4. التحقق من الخصم
      final discountValidation = FinancialValidationService.validateDiscount(discount, currentTotalAmount);
      if (!discountValidation.isValid) {
        throw Exception(discountValidation.errorMessage ?? 'الخصم غير صحيح');
      }
      
      // 5. حساب الإجمالي النهائي
      double totalAmount = (currentTotalAmount + loadingFee) - discount;
      
      // 6. التحقق من المبلغ المدفوع
      final paidValidation = FinancialValidationService.validatePaidAmount(paid, totalAmount, paymentType);
      if (!paidValidation.isValid) {
        throw Exception(paidValidation.errorMessage ?? 'المبلغ المدفوع غير صحيح');
      }
      
      // 7. التحقق الشامل من الفاتورة
      final invoiceValidation = FinancialValidationService.validateInvoiceBeforeSave(
        itemsCount: invoiceItems.length,
        totalAmount: totalAmount,
        discount: discount,
        paidAmount: paid,
        loadingFee: loadingFee,
        paymentType: paymentType,
      );
      if (!invoiceValidation.isValid) {
        throw Exception(invoiceValidation.errorMessage ?? 'بيانات الفاتورة غير صحيحة');
      }
      
      // ═══════════════════════════════════════════════════════════════════════════
      // حفظ الفاتورة (بعد التحقق من صحة البيانات)
      // ═══════════════════════════════════════════════════════════════════════════
      
    try {
      Customer? customer;
      if (customerNameController.text.trim().isNotEmpty) {
        customer = await db.findCustomerByNormalizedName(
          customerNameController.text.trim(),
          phone: customerPhoneController.text.trim().isEmpty
              ? null
              : customerPhoneController.text.trim(),
        );
        if (customer == null) {
          customer = Customer(
            id: null,
            name: customerNameController.text.trim(),
            phone: customerPhoneController.text.trim().isEmpty
                ? null
                : customerPhoneController.text.trim(),
            address: customerAddressController.text.trim(),
            createdAt: DateTime.now(),
            lastModifiedAt: DateTime.now(),
            currentTotalDebt: 0.0,
          );
          final insertedId = await db.insertCustomer(customer);
          customer = customer.copyWith(id: insertedId);
        }
      }
      double currentTotalAmount =
          invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      // إزالة فواصل الآلاف قبل تحويل النص إلى رقم لضمان دقة الحساب
      double paid =
          double.tryParse(paidAmountController.text.replaceAll(',', '')) ??
              0.0;
      final double loadingFee =
          double.tryParse(loadingFeeController.text.replaceAll(',', '')) ??
              0.0;
      double debt = ((currentTotalAmount + loadingFee) - discount) - paid;
      double totalAmount = (currentTotalAmount + loadingFee) - discount;
      // تحقق من نسبة الخصم
      final totalAmountForDiscount =
          invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      if (discount >= totalAmountForDiscount) {
        return null;
      }
      // تحديد الحالة الجديدة
      String newStatus = 'محفوظة';
      bool newIsLocked = invoiceToManage?.isLocked ?? false;
      if (invoiceToManage != null) {
        if (invoiceToManage.status == 'معلقة') {
          newStatus = 'محفوظة';
          newIsLocked = false;
        }
      } else {
        newIsLocked = false;
      }
      Invoice invoice = Invoice(
        id: invoiceToManage?.id,
        customerName: customerNameController.text,
        customerPhone: customerPhoneController.text,
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
        returnAmount: returnAmountController.text.isNotEmpty
            ? double.parse(returnAmountController.text)
            : 0.0,
        isLocked: false,
      );
      if (invoice.installerName != null && invoice.installerName!.isNotEmpty) {
        final existingInstaller =
            await db.getInstallerByName(invoice.installerName!);
        if (existingInstaller == null) {
          final newInstaller = Installer(
            id: null,
            name: invoice.installerName!,
            totalBilledAmount: 0.0,
          );
          await db.insertInstaller(newInstaller);
        }
      }
      int invoiceId;
      if (invoiceToManage != null) {
        invoiceId = invoiceToManage.id!;
        final oldItems = await db.getInvoiceItems(invoiceId);
        for (var oldItem in oldItems) {
          await db.deleteInvoiceItem(oldItem.id!);
        }
        for (var item in invoiceItems) {
          item.invoiceId = invoiceId;
          await db.insertInvoiceItem(item);
        }
        await db.updateInvoice(invoice);
      } else {
        invoiceId = await db.insertInvoice(invoice);
        final savedInvoice = await db.getInvoiceById(invoiceId);
        if (savedInvoice != null) {
          invoice = savedInvoice;
        }
        for (var item in invoiceItems) {
          item.invoiceId = invoiceId;
          await db.insertInvoiceItem(item);
        }
      }
      if (paymentType == 'دين' && customer != null && debt > 0) {
        // جلب الرصيد الفعلي قبل العملية
        final beforeDebt = (await db.getCustomerById(customer.id!))?.currentTotalDebt ?? 0.0;
        final afterDebt = beforeDebt + debt;
        final updatedCustomer = customer.copyWith(
          currentTotalDebt: afterDebt,
          lastModifiedAt: DateTime.now(),
        );
        await db.updateCustomer(updatedCustomer);
        final txUuid = await DriveService().generateTransactionUuid();
        final debtTransaction = DebtTransaction(
          id: null,
          customerId: customer.id!,
          amountChanged: debt,
          transactionType: 'invoice_debt',
          description: 'دين فاتورة رقم ${invoiceId ?? invoiceToManage?.id}',
          balanceBeforeTransaction: beforeDebt,
          newBalanceAfterTransaction: afterDebt,
          invoiceId: invoiceId,
          transactionUuid: txUuid,
        );
        await db.insertDebtTransaction(debtTransaction);
      }
      
      // ═══════════════════════════════════════════════════════════════════════════
      // تسجيل العملية في سجل التدقيق
      // ═══════════════════════════════════════════════════════════════════════════
      try {
        final auditService = FinancialAuditService();
        if (invoiceToManage != null) {
          // تعديل فاتورة موجودة
          await auditService.logInvoiceUpdate(
            invoiceId,
            {
              'total_amount': invoiceToManage.totalAmount,
              'discount': invoiceToManage.discount,
              'payment_type': invoiceToManage.paymentType,
              'paid_amount': invoiceToManage.amountPaidOnInvoice,
            },
            {
              'total_amount': totalAmount,
              'discount': discount,
              'payment_type': paymentType,
              'paid_amount': paid,
            },
            customerId: customer?.id,
          );
        } else {
          // إنشاء فاتورة جديدة
          await auditService.logInvoiceCreation(invoiceId, {
            'total_amount': totalAmount,
            'discount': discount,
            'payment_type': paymentType,
            'paid_amount': paid,
            'customer_name': customerNameController.text,
            'items_count': invoiceItems.length,
          }, customerId: customer?.id);
        }
      } catch (auditError) {
        print('تحذير: فشل تسجيل التدقيق: $auditError');
        // لا نوقف العملية إذا فشل التسجيل
      }
      
      storage.remove('temp_invoice_data');
      return await db.getInvoiceById(invoiceId);
    } catch (e) {
      // إعادة رمي الاستثناء مع رسالة واضحة
      print('خطأ في حفظ الفاتورة: $e');
      rethrow;
    }
    } catch (validationError) {
      // خطأ في التحقق من البيانات
      print('خطأ في التحقق من البيانات: $validationError');
      rethrow;
    }
  }

  static Future<Invoice?> autoSaveSuspendedInvoiceWithBusinessLogic({
    required Invoice? invoiceToManage,
    required List<InvoiceItem> invoiceItems,
    required TextEditingController customerNameController,
    required TextEditingController customerPhoneController,
    required TextEditingController customerAddressController,
    required TextEditingController installerNameController,
    required DateTime selectedDate,
    required String paymentType,
    required double discount,
    required TextEditingController paidAmountController,
    required TextEditingController returnAmountController,
    required TextEditingController loadingFeeController,
    required DatabaseService db,
  }) async {
    if (invoiceToManage == null ||
        invoiceToManage.status != 'معلقة' ||
        (invoiceToManage.isLocked)) return null;
    Customer? customer;
    if (customerNameController.text.trim().isNotEmpty) {
      final customers = await db.getAllCustomers();
      try {
        customer = customers.firstWhere(
          (c) =>
              c.name.trim() == customerNameController.text.trim() &&
              (c.phone == null ||
                  c.phone!.isEmpty ||
                  customerPhoneController.text.trim().isEmpty ||
                  c.phone == customerPhoneController.text.trim()),
        );
      } catch (e) {
        customer = null;
      }
    }
    double currentTotalAmount =
        invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    // إزالة فواصل الآلاف قبل التحويل
    double paid =
        double.tryParse(paidAmountController.text.replaceAll(',', '')) ??
            0.0;
    final double loadingFee =
        double.tryParse(loadingFeeController.text.replaceAll(',', '')) ??
            0.0;
    double totalAmount = (currentTotalAmount + loadingFee) - discount;
    Invoice invoice = invoiceToManage.copyWith(
      customerName: customerNameController.text,
      customerPhone: customerPhoneController.text,
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
      lastModifiedAt: DateTime.now(),
      customerId: customer?.id,
      returnAmount: returnAmountController.text.isNotEmpty
          ? double.parse(returnAmountController.text)
          : 0.0,
      isLocked: false,
    );
    int invoiceId = invoiceToManage.id!;
    final oldItems = await db.getInvoiceItems(invoiceId);
    for (var oldItem in oldItems) {
      await db.deleteInvoiceItem(oldItem.id!);
    }
    for (var item in invoiceItems) {
      item.invoiceId = invoiceId;
      await db.insertInvoiceItem(item);
    }
    await db.updateInvoice(invoice);
    return invoice;
  }
}
