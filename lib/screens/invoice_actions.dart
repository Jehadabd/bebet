// lib/screens/invoice_actions.dart
import 'dart:async'; // ← لـ unawaited
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
import '../services/stamp_manager.dart';
import '../services/drive_service.dart';
import '../services/expert_training_service.dart'; // 🧠 التدريب الخبير التدريجي
import '../services/pdf_header.dart';
import '../services/pdf_service.dart';
import '../services/printing_service.dart';
import '../services/settings_manager.dart';
import '../services/smart_search/smart_search.dart'; // 🧠 البحث الذكي
import '../services/invoice_prediction_service.dart'; // 🔮 التوقعات الذكية
import '../services/firebase_sync/firebase_sync_helper.dart'; // 🔥 Firebase Sync
import '../services/sync/sync_security.dart'; // 🔐 Sync UUID Generation
import '../services/financial_guardians.dart'; // 🛡️ Financial Guardians
import '../services/smart_pricing_service.dart'; // 🔮 محرك التسعير الذكي
import 'create_invoice_screen.dart';

/// واجهة تحدد المتغيرات المطلوبة للتعامل مع الفواتير
abstract class InvoiceActionsInterface {
  bool get isSaving;
  set isSaving(bool value);
  
  GlobalKey<FormState> get formKey;
  
  Invoice? get invoiceToManage;
  set invoiceToManage(Invoice? value);
  
  void cancelLiveDebtTimer();
  
  TextEditingController get customerNameController;
  TextEditingController get customerPhoneController;
  TextEditingController get customerAddressController;
  TextEditingController get installerNameController;
  TextEditingController get paidAmountController;
  TextEditingController get loadingFeeController;
  TextEditingController get noteController;
  
  // معدل النقاط لكل 100,000
  double get installerPointsRate;
  
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
    // التحقق من أن الكمية موجودة وأكبر من صفر
    final hasValidQuantity = (item.quantityIndividual != null && item.quantityIndividual! > 0) ||
                             (item.quantityLargeUnit != null && item.quantityLargeUnit! > 0);
    return (item.productName.isNotEmpty &&
        hasValidQuantity &&
        item.appliedPrice > 0 &&
        item.itemTotal > 0 &&
        (item.saleType != null && item.saleType!.isNotEmpty));
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // 🔒 تحسين الأمان: التحقق المسبق من صحة البيانات المالية
  // ═══════════════════════════════════════════════════════════════════════════
  _ValidationResult _validateInvoiceDataBeforeSave() {
    // 1. التحقق من وجود أصناف مكتملة
    final completeItems = invoiceItems.where(_isInvoiceItemComplete).toList();
    final incompleteItems = invoiceItems.where((item) => 
      item.productName.isNotEmpty && !_isInvoiceItemComplete(item)
    ).toList();
    
    if (completeItems.isEmpty) {
      // تحديد سبب عدم اكتمال الأصناف
      if (incompleteItems.isNotEmpty) {
        final problems = <String>[];
        for (final item in incompleteItems) {
          final itemProblems = <String>[];
          final hasQty = (item.quantityIndividual != null && item.quantityIndividual! > 0) ||
                         (item.quantityLargeUnit != null && item.quantityLargeUnit! > 0);
          if (!hasQty) itemProblems.add('الكمية');
          if (item.appliedPrice <= 0) itemProblems.add('السعر');
          if (item.saleType == null || item.saleType!.isEmpty) itemProblems.add('نوع البيع');
          if (itemProblems.isNotEmpty) {
            problems.add('${item.productName}: ينقص ${itemProblems.join('، ')}');
          }
        }
        if (problems.isNotEmpty) {
          return _ValidationResult(
            isValid: false, 
            errorMessage: 'أصناف غير مكتملة:\n${problems.take(3).join('\n')}${problems.length > 3 ? '\n... و${problems.length - 3} أصناف أخرى' : ''}'
          );
        }
      }
      return _ValidationResult(isValid: false, errorMessage: 'لا يمكن حفظ فاتورة بدون أصناف. أضف صنفاً واحداً على الأقل مع الكمية والسعر ونوع البيع.');
    }
    
    // 2. حساب الإجمالي والتحقق من صحته
    double calculatedTotal = 0.0;
    for (final item in completeItems) {
      final quantity = item.quantityIndividual ?? item.quantityLargeUnit ?? 0;
      final expectedItemTotal = quantity * item.appliedPrice;
      
      // التحقق من صحة إجمالي الصنف
      if ((item.itemTotal - expectedItemTotal).abs() > 0.01) {
        print('⚠️ تحذير: إجمالي الصنف ${item.productName} غير متطابق: ${item.itemTotal} ≠ $expectedItemTotal');
        // تصحيح تلقائي
        // item.itemTotal = expectedItemTotal; // لا يمكن تعديل final
      }
      
      calculatedTotal += item.itemTotal;
    }
    
    // 3. التحقق من الخصم
    if (discount < 0) {
      return _ValidationResult(isValid: false, errorMessage: 'الخصم لا يمكن أن يكون سالباً');
    }
    if (discount >= calculatedTotal) {
      return _ValidationResult(isValid: false, errorMessage: 'الخصم لا يمكن أن يساوي أو يتجاوز الإجمالي');
    }
    
    // 4. التحقق من أجور التحميل
    final loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
    if (loadingFee < 0) {
      return _ValidationResult(isValid: false, errorMessage: 'أجور التحميل لا يمكن أن تكون سالبة');
    }
    
    // 5. التحقق من المبلغ المدفوع
    final paid = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0;
    final finalTotal = (calculatedTotal + loadingFee) - discount;
    
    if (paid < 0) {
      return _ValidationResult(isValid: false, errorMessage: 'المبلغ المدفوع لا يمكن أن يكون سالباً');
    }
    if (paid > finalTotal + 0.01) {
      return _ValidationResult(isValid: false, errorMessage: 'المبلغ المدفوع لا يمكن أن يتجاوز الإجمالي');
    }
    
    // 🔒 شرط جديد: منع تقليل إجمالي الفاتورة عن المبلغ المسدد الجديد
    // عند تعديل فاتورة محفوظة، لا يمكن أن يصبح الإجمالي أقل من المبلغ المسدد (الجديد الذي أدخله المستخدم)
    if (invoiceToManage != null && invoiceToManage!.id != null) {
      // نستخدم المبلغ المسدد الجديد (paid) وليس الأصلي
      if (finalTotal < paid - 0.01) {
        return _ValidationResult(
          isValid: false, 
          errorMessage: 'لا يمكن أن يكون إجمالي الفاتورة (${finalTotal.toStringAsFixed(0)}) أقل من المبلغ المسدد (${paid.toStringAsFixed(0)}). يرجى تقليل المبلغ المسدد أولاً.',
        );
      }
    }
    
    // 🔒 ملاحظة: التحقق من الرصيد السالب يتم في _validateDebtChangeWontCauseNegativeBalance
    
    // 6. التحقق من نوع الدفع
    if (paymentType == 'نقد' && (paid - finalTotal).abs() > 0.01) {
      return _ValidationResult(isValid: false, errorMessage: 'في حالة الدفع النقدي، يجب أن يساوي المبلغ المدفوع الإجمالي. المسدد: $paid، الإجمالي: $finalTotal');
    }
    
    return _ValidationResult(isValid: true);
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // 🔒 تحسين الأمان: التحقق من أن تعديل الفاتورة لن يسبب رصيد سالب للعميل
  // ═══════════════════════════════════════════════════════════════════════════
  Future<_ValidationResult> _validateDebtChangeWontCauseNegativeBalance() async {
    // هذا التحقق فقط للفواتير المحفوظة (تعديل فاتورة موجودة)
    if (invoiceToManage == null || invoiceToManage!.id == null) {
      return _ValidationResult(isValid: true);
    }
    
    final oldInvoice = invoiceToManage;
    if (oldInvoice == null) {
      return _ValidationResult(isValid: true);
    }
    
    // فقط للفواتير التي كانت بالدين
    if (oldInvoice.paymentType != 'دين') {
      return _ValidationResult(isValid: true);
    }
    
    // جلب رصيد العميل القديم
    final oldCustomerId = oldInvoice.customerId;
    if (oldCustomerId == null) {
      return _ValidationResult(isValid: true);
    }
    
    final dbService = DatabaseService();
    final oldCustomer = await dbService.getCustomerById(oldCustomerId);
    if (oldCustomer == null) {
      return _ValidationResult(isValid: true);
    }
    
    final currentCustomerDebt = oldCustomer.currentTotalDebt;
    
    // حساب الدين القديم
    final oldRemaining = oldInvoice.totalAmount - oldInvoice.amountPaidOnInvoice;
    
    // حساب الإجمالي الجديد
    final completeItems = invoiceItems.where(_isInvoiceItemComplete).toList();
    double calculatedTotal = completeItems.fold(0.0, (sum, item) => sum + item.itemTotal);
    final loadingFee = double.tryParse(loadingFeeController.text.replaceAll(',', '')) ?? 0.0;
    final newTotal = (calculatedTotal + loadingFee) - discount;
    final newPaid = double.tryParse(paidAmountController.text.replaceAll(',', '')) ?? 0.0;
    
    // التحقق من تغيير اسم العميل (عميل جديد)
    final newCustomerName = customerNameController.text.trim();
    final oldCustomerName = oldInvoice.customerName?.trim() ?? '';
    final isCustomerChanged = newCustomerName.replaceAll(' ', '').toLowerCase() != 
                              oldCustomerName.replaceAll(' ', '').toLowerCase();
    
    double debtChange = 0.0;
    
    // حالة 1: تحويل من دين إلى نقد
    if (paymentType == 'نقد') {
      debtChange = -oldRemaining; // سيُخصم كل الدين القديم
    }
    // حالة 2: تغيير العميل في فاتورة دين
    else if (paymentType == 'دين' && isCustomerChanged) {
      debtChange = -oldRemaining; // سيُخصم كل الدين القديم من العميل القديم
    }
    // حالة 3: تعديل فاتورة دين (نفس العميل ونفس نوع الدفع)
    else if (paymentType == 'دين') {
      final newRemaining = newTotal - newPaid;
      debtChange = newRemaining - oldRemaining;
    }
    
    // التحقق: هل سيصبح رصيد العميل القديم سالباً؟
    final expectedNewBalance = currentCustomerDebt + debtChange;
    
    if (expectedNewBalance < -0.01) {
      final debtToDeduct = (-debtChange).toStringAsFixed(0);
      String reason = '';
      String solution = '';
      
      if (isCustomerChanged) {
        reason = 'تم تغيير اسم العميل، وسيُخصم الدين من العميل القديم "${oldCustomer.name}".';
        solution = 'تأكد من أن العميل القديم لديه رصيد كافٍ، أو عدّل المعاملات أولاً.';
      } else if (paymentType == 'نقد') {
        reason = 'تم تحويل الفاتورة من دين إلى نقد.';
        solution = 'راجع معاملات العميل أو أبقِ الفاتورة بالدين.';
      } else {
        reason = 'تم تسديد جزء من هذه الفاتورة من سجل الديون.';
        solution = 'راجع معاملات العميل أو عدّل المبلغ المسدد.';
      }
      
      return _ValidationResult(
        isValid: false,
        errorMessage: 'لا يمكن إتمام هذا التعديل!\n\n'
            'رصيد العميل "${oldCustomer.name}" الحالي: ${currentCustomerDebt.toStringAsFixed(0)}\n'
            'المبلغ الذي سيُخصم: $debtToDeduct\n'
            'الرصيد المتوقع: ${expectedNewBalance.toStringAsFixed(0)} (سالب!)\n\n'
            'السبب: $reason\n'
            'الحل: $solution',
      );
    }
    
    return _ValidationResult(isValid: true);
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // 🔒 تحسين الأمان: التحقق بعد الحفظ
  // ═══════════════════════════════════════════════════════════════════════════
  Future<bool> _verifyInvoiceAfterSave(int invoiceId) async {
    try {
      final db = DatabaseService();
      final savedInvoice = await db.getInvoiceById(invoiceId);
      final savedItems = await db.getInvoiceItems(invoiceId);
      
      if (savedInvoice == null) {
        return false;
      }
      
      // التحقق من تطابق عدد الأصناف
      final expectedItemsCount = invoiceItems.where(_isInvoiceItemComplete).length;
      if (savedItems.length != expectedItemsCount) {
        return false;
      }
      
      // التحقق من تطابق الإجمالي
      final savedTotal = savedItems.fold(0.0, (sum, item) => sum + item.itemTotal);
      final expectedTotal = invoiceItems.where(_isInvoiceItemComplete).fold(0.0, (sum, item) => sum + item.itemTotal);
      
      if ((savedTotal - expectedTotal).abs() > 0.01) {
        return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
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
    // 🧹 إيقاف المزامنة الحية فوراً بمجرد بدء الحفظ
    cancelLiveDebtTimer();
    
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
      
      // ═══════════════════════════════════════════════════════════════════════════
      // 🔒 تحسين الأمان: التحقق المسبق من صحة البيانات المالية
      // ═══════════════════════════════════════════════════════════════════════════
      final preValidation = _validateInvoiceDataBeforeSave();
      if (!preValidation.isValid) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ في البيانات: ${preValidation.errorMessage}'),
          backgroundColor: Colors.red,
        ));
        setState(() => isSaving = false);
        return null;
      }

      // 🚨 إضافة تحقق صارم مستقل للأرقام دون تعديل الكود القديم:
      bool _strictMathFailed = false;
      String _strictMathErrorMsg = '';
      for (final item in invoiceItems.where(_isInvoiceItemComplete)) {
        final double qty = item.quantityIndividual ?? item.quantityLargeUnit ?? 0;
        final double expected = qty * item.appliedPrice;
        if ((item.itemTotal - expected).abs() > 0.01) {
          _strictMathFailed = true;
          _strictMathErrorMsg = 'توقف! يوجد خلل حسابي في الصنف "${item.productName}". المسجل ${item.itemTotal} لكن الحساب الفعلي هو $expected. احذفه وأضفه من جديد.';
          break;
        }
      }
      
      if (_strictMathFailed) {
         if (mounted) {
             showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('⚠️ خطأ برمجي في الحسابات', style: TextStyle(color: Colors.red)),
                  content: Text(_strictMathErrorMsg),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
                )
             );
         }
         setState(() => isSaving = false);
         return null; // نُوقف الحفظ فوراً
      }

      
      // ═══════════════════════════════════════════════════════════════════════════
      // 🔒 تحسين الأمان: التحقق من أن التعديل لن يسبب رصيد سالب للعميل
      // ═══════════════════════════════════════════════════════════════════════════
      final debtValidation = await _validateDebtChangeWontCauseNegativeBalance();
      if (!debtValidation.isValid) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('⚠️ تحذير مالي', style: TextStyle(color: Colors.red)),
              content: Text(debtValidation.errorMessage ?? 'خطأ في التحقق من الرصيد'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('حسناً'),
                ),
              ],
            ),
          );
        }
        setState(() => isSaving = false);
        return null;
      }

      if (!isNewInvoice && invoiceToManage?.id == null) {
        throw Exception('خطأ فادح: محاولة تعديل فاتورة بدون معرّف (ID).');
      }

      final db = DatabaseService();
      Invoice? savedInvoice;

      // 📸 حفظ نسخة من الفاتورة قبل التعديل
      if (!isNewInvoice && invoiceToManage?.id != null) {
        try {
          // التحقق من وجود نسخة أصلية
          final hasSnapshots = await db.hasInvoiceBeenModified(invoiceToManage!.id!);
          if (!hasSnapshots) {
            // حفظ النسخة الأصلية (أول مرة يتم التعديل)
            await db.saveInvoiceSnapshot(
              invoiceId: invoiceToManage!.id!,
              snapshotType: 'original',
              notes: 'النسخة الأصلية قبل أي تعديل',
            );
          }
          // حفظ نسخة قبل التعديل الحالي
          await db.saveInvoiceSnapshot(
            invoiceId: invoiceToManage!.id!,
            snapshotType: 'before_edit',
            notes: 'قبل التعديل',
          );
        } catch (e) {
          print('تحذير: فشل حفظ نسخة الفاتورة: $e');
        }
      }

      // 🧹 قبل بدء معاملة الحفظ النهائية، نرسل أمر تنظيف المعاملات المؤقتة
      // هذا يضمن أن رصيد العميل نظيف قبل أن نضيف عليه دين هذه الفاتورة
      if (!isNewInvoice && invoiceToManage?.id != null) {
        try {
          await db.deleteLiveDebtTransactions(invoiceToManage!.id!);
        } catch (e) {
          print('تحذير: فشل تنظيف المعاملات المؤقتة قبل الحفظ: $e');
        }
      }

      await (await db.database).transaction((txn) async {
        // 🚨 إضافة أمان: معالجة ذرية داخل نفس الترانسكشن للديون المعلقة لضمان عدم تلف البيانات لو انقطع الاتصال
        if (!isNewInvoice && invoiceToManage?.id != null) {
          try {
             await txn.delete('live_debt_transactions', where: 'invoice_id = ?', whereArgs: [invoiceToManage!.id!]);
          } catch (e) {
             print('تحذير: فشل تنظيف المعاملات المؤقتة داخل الـ transaction: $e');
          }
        }
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
            // 🔄 إنشاء sync_uuid للعميل الجديد لتمكين المزامنة
            final customerSyncUuid = SyncSecurity.generateUuid();
            
            customer = Customer(
              id: null,
              name: customerNameController.text.trim(),
              phone: normalizedPhone,
              address: customerAddressController.text.trim(),
              createdAt: DateTime.now(),
              lastModifiedAt: DateTime.now(),
              currentTotalDebt: 0.0,
              syncUuid: customerSyncUuid, // 🔄 تضمين sync_uuid
            );
            
            // إدراج العميل مع sync_uuid
            final customerMap = customer.toMap();
            customerMap['sync_uuid'] = customerSyncUuid;
            final insertedId = await txn.insert('customers', customerMap);
            customer = customer.copyWith(id: insertedId, syncUuid: customerSyncUuid);
            
            // 🔥 تسجيل أن هذا عميل جديد يحتاج رفع
            print('🆕 تم إنشاء عميل جديد من الفاتورة: ${customer.name} (UUID: $customerSyncUuid)');
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

        // ═══════════════════════════════════════════════════════════════════════════
        // 🔧 إنشاء مؤسس جديد تلقائياً إذا لم يكن موجوداً
        // ═══════════════════════════════════════════════════════════════════════════
        if (installerNameController.text.trim().isNotEmpty) {
          final installerName = installerNameController.text.trim();
          final existingInstallers = await txn.query(
            'installers',
            where: 'name = ?',
            whereArgs: [installerName],
            limit: 1,
          );
          
          if (existingInstallers.isEmpty) {
            // إنشاء مؤسس جديد
            await txn.insert('installers', {
              'name': installerName,
              'total_billed_amount': 0.0,
              'total_points': 0.0,
            });
            print('🆕 تم إنشاء مؤسس جديد من الفاتورة: $installerName');
          }
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
          notes: noteController.text.trim().isNotEmpty ? noteController.text.trim() : null,
          pointsRate: installerPointsRate, // حفظ معدل النقاط مع الفاتورة
        );

        // 🛡️ الطبقة الدفاعية: حارس الفواتير النقدية والمدقق الرياضي
        try {
          FinancialGuardians.validateCashInvoiceIntegrity(invoice);
          FinancialGuardians.auditInvoiceMath(invoice, invoiceItems, totalAmount, discount);
        } catch (e) {
          throw Exception(e.toString());
        }

        int invoiceId;
        if (isNewInvoice) {
          invoiceId = await txn.insert('invoices', invoice.toMap());
          invoice = invoice.copyWith(id: invoiceId);
        } else {
          invoiceId = invoiceToManage!.id!;
          await txn.update('invoices', invoice.toMap(),
              where: 'id = ?', whereArgs: [invoiceId]);
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // 🔒 حماية الأصناف: تحضير الأصناف المكتملة قبل الحذف
        // ═══════════════════════════════════════════════════════════════════════════
        final products = await txn.rawQuery('SELECT * FROM products');
        final productMap = <String, Map<String, dynamic>>{};
        for (var productData in products) {
          final productName = productData['name'] as String?;
          if (productName != null) {
            productMap[productName] = productData;
          }
        }

        // تحضير قائمة الأصناف المكتملة مسبقاً
        final List<Map<String, dynamic>> itemsToInsert = [];
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
            itemsToInsert.add(itemMap);
          }
        }

        // 🔒 التحقق من وجود أصناف مكتملة قبل الحذف (للفواتير الموجودة)
        if (!isNewInvoice && itemsToInsert.isEmpty) {
          throw Exception('لا يمكن حفظ الفاتورة بدون أصناف مكتملة. تأكد من إدخال اسم المنتج والكمية والسعر ونوع البيع.');
        }

        // الآن نحذف الأصناف القديمة بعد التأكد من وجود أصناف جديدة
        await txn.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
        
        // إدراج الأصناف الجديدة
        final batch = txn.batch();
        int savedItemsCount = 0;
        for (var itemMap in itemsToInsert) {
          batch.insert('invoice_items', itemMap);
          savedItemsCount++;
        }
        await batch.commit(noResult: true);
        
        // 🔒 التحقق من نجاح الإدراج
        if (savedItemsCount == 0 && !isNewInvoice) {
          throw Exception('فشل حفظ أصناف الفاتورة. يرجى المحاولة مرة أخرى.');
        }

        // ═══════════════════════════════════════════════════════════════════════════
        // ✅ منطق الدين المحسّن - يتعامل مع جميع الحالات
        // ═══════════════════════════════════════════════════════════════════════════
        
        if (!isNewInvoice) {
          final oldInvoice = invoiceToManage!;
          final oldPaymentType = oldInvoice.paymentType;
          final oldCustomerId = oldInvoice.customerId;
          final newCustomerId = customer?.id;
          final newRemaining = totalAmount - paid;
          
          // ═══════════════════════════════════════════════════════════════════════
          // 🔧 إصلاح: جلب الدين الحالي من المعاملات (المصدر الحقيقي للدين)
          // بدلاً من الاعتماد على widget.existingInvoice الذي قد يكون قديماً
          // ═══════════════════════════════════════════════════════════════════════
          double currentDebtFromTx = 0.0;
          if (oldCustomerId != null) {
            final txSum = await txn.rawQuery(
              'SELECT COALESCE(SUM(amount_changed), 0) as total FROM transactions WHERE invoice_id = ?',
              [invoiceId]
            );
            currentDebtFromTx = (txSum.first['total'] as num?)?.toDouble() ?? 0.0;
            
            // تحقق إضافي: مقارنة مع الفاتورة المخزنة
            final dbInvoice = await txn.query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
            if (dbInvoice.isNotEmpty) {
              final dbTotal = (dbInvoice.first['total_amount'] as num?)?.toDouble() ?? 0.0;
              // 🔧 إصلاح: استخدام الحقل الصحيح amount_paid_on_invoice بدلاً من paid_amount
              final dbPaid = (dbInvoice.first['amount_paid_on_invoice'] as num?)?.toDouble() ?? 0.0;
              final expectedDebt = dbTotal - dbPaid;
              if ((currentDebtFromTx - expectedDebt).abs() > 1) {
                print('⚠️ تحذير: فرق بين دين المعاملات ($currentDebtFromTx) ودين الفاتورة ($expectedDebt)');
              }
            }
          }
          
          // ═══════════════════════════════════════════════════════════════════════
          // حالة 1: تغيير من دين إلى نقد - إلغاء الدين القديم
          // ═══════════════════════════════════════════════════════════════════════
          if (oldPaymentType == 'دين' && paymentType == 'نقد' && oldCustomerId != null) {
            if (currentDebtFromTx.abs() > 0.001) {
              // جلب العميل القديم
              final oldCustomerMaps = await txn.query('customers', where: 'id = ?', whereArgs: [oldCustomerId]);
              if (oldCustomerMaps.isNotEmpty) {
                final oldCustomer = Customer.fromMap(oldCustomerMaps.first);
                final balanceBefore = oldCustomer.currentTotalDebt;
                final balanceAfter = balanceBefore - currentDebtFromTx;
                
                // تحديث رصيد العميل
                await txn.update('customers', {
                  'current_total_debt': balanceAfter,
                  'last_modified_at': DateTime.now().toIso8601String(),
                }, where: 'id = ?', whereArgs: [oldCustomerId]);
                
                // تسجيل معاملة إلغاء الدين
                final txUuid = await DriveService().generateTransactionUuid();
                await txn.insert('transactions', {
                  'customer_id': oldCustomerId,
                  'transaction_date': DateTime.now().toIso8601String(),
                  'amount_changed': -currentDebtFromTx,
                  'balance_before_transaction': balanceBefore,
                  'new_balance_after_transaction': balanceAfter,
                  'transaction_type': 'invoice_payment_type_change',
                  'description': 'إلغاء دين فاتورة رقم $invoiceId (تحويل لنقد)',
                  'invoice_id': invoiceId,
                  'transaction_uuid': txUuid,
                  'created_at': DateTime.now().toIso8601String(),
                });
              }
            }
          }
          
          // ═══════════════════════════════════════════════════════════════════════
          // حالة 2: تغيير من نقد إلى دين - إضافة دين جديد
          // 🔧 إصلاح: جلب رصيد العميل من قاعدة البيانات داخل المعاملة
          // ═══════════════════════════════════════════════════════════════════════
          else if (oldPaymentType == 'نقد' && paymentType == 'دين' && customer != null) {
            if (newRemaining > 0.001) {
              // 🔧 إصلاح: جلب الرصيد الحالي من قاعدة البيانات (وليس من الذاكرة)
              final freshCustomerMaps = await txn.query('customers', where: 'id = ?', whereArgs: [customer.id]);
              if (freshCustomerMaps.isEmpty) {
                throw Exception('العميل غير موجود في قاعدة البيانات');
              }
              final freshCustomer = Customer.fromMap(freshCustomerMaps.first);
              final balanceBefore = freshCustomer.currentTotalDebt;
              final balanceAfter = balanceBefore + newRemaining;
              
              // تحديث رصيد العميل
              await txn.update('customers', {
                'current_total_debt': balanceAfter,
                'last_modified_at': DateTime.now().toIso8601String(),
              }, where: 'id = ?', whereArgs: [customer.id]);
              
              // تسجيل معاملة إضافة الدين
              final txUuid = await DriveService().generateTransactionUuid();
              await txn.insert('transactions', {
                'customer_id': customer.id,
                'transaction_date': DateTime.now().toIso8601String(),
                'amount_changed': newRemaining,
                'balance_before_transaction': balanceBefore,
                'new_balance_after_transaction': balanceAfter,
                'transaction_type': 'invoice_payment_type_change',
                'description': 'إضافة دين فاتورة رقم $invoiceId (تحويل من نقد)',
                'invoice_id': invoiceId,
                'transaction_uuid': txUuid,
                'created_at': DateTime.now().toIso8601String(),
              });
            }
          }
          
          // ═══════════════════════════════════════════════════════════════════════
          // حالة 3: تغيير العميل في فاتورة دين
          // 🔧 إصلاح: استخدام الدين من المعاملات بدلاً من widget.existingInvoice
          // ═══════════════════════════════════════════════════════════════════════
          else if (oldPaymentType == 'دين' && paymentType == 'دين' && 
                   oldCustomerId != null && newCustomerId != null && 
                   oldCustomerId != newCustomerId) {
            
            // 3.1: خصم الدين من العميل القديم (استخدام الدين من المعاملات)
            if (currentDebtFromTx.abs() > 0.001) {
              final oldCustomerMaps = await txn.query('customers', where: 'id = ?', whereArgs: [oldCustomerId]);
              if (oldCustomerMaps.isNotEmpty) {
                final oldCustomer = Customer.fromMap(oldCustomerMaps.first);
                final oldBalanceBefore = oldCustomer.currentTotalDebt;
                final oldBalanceAfter = oldBalanceBefore - currentDebtFromTx;
                
                await txn.update('customers', {
                  'current_total_debt': oldBalanceAfter,
                  'last_modified_at': DateTime.now().toIso8601String(),
                }, where: 'id = ?', whereArgs: [oldCustomerId]);
                
                final txUuid1 = await DriveService().generateTransactionUuid();
                await txn.insert('transactions', {
                  'customer_id': oldCustomerId,
                  'transaction_date': DateTime.now().toIso8601String(),
                  'amount_changed': -currentDebtFromTx,
                  'balance_before_transaction': oldBalanceBefore,
                  'new_balance_after_transaction': oldBalanceAfter,
                  'transaction_type': 'invoice_customer_change',
                  'description': 'نقل دين فاتورة رقم $invoiceId إلى عميل آخر',
                  'invoice_id': invoiceId,
                  'transaction_uuid': txUuid1,
                  'created_at': DateTime.now().toIso8601String(),
                });
              }
            }
            
            // 3.2: إضافة الدين للعميل الجديد
            if (newRemaining > 0.001 && customer != null) {
              // إعادة جلب العميل الجديد للحصول على الرصيد المحدث
              final newCustomerMaps = await txn.query('customers', where: 'id = ?', whereArgs: [newCustomerId]);
              if (newCustomerMaps.isNotEmpty) {
                final newCustomer = Customer.fromMap(newCustomerMaps.first);
                final newBalanceBefore = newCustomer.currentTotalDebt;
                final newBalanceAfter = newBalanceBefore + newRemaining;
                
                await txn.update('customers', {
                  'current_total_debt': newBalanceAfter,
                  'last_modified_at': DateTime.now().toIso8601String(),
                }, where: 'id = ?', whereArgs: [newCustomerId]);
                
                final txUuid2 = await DriveService().generateTransactionUuid();
                await txn.insert('transactions', {
                  'customer_id': newCustomerId,
                  'transaction_date': DateTime.now().toIso8601String(),
                  'amount_changed': newRemaining,
                  'balance_before_transaction': newBalanceBefore,
                  'new_balance_after_transaction': newBalanceAfter,
                  'transaction_type': 'invoice_customer_change',
                  'description': 'استلام دين فاتورة رقم $invoiceId من عميل آخر',
                  'invoice_id': invoiceId,
                  'transaction_uuid': txUuid2,
                  'created_at': DateTime.now().toIso8601String(),
                });
              }
            }
          }
          
          // ═══════════════════════════════════════════════════════════════════════
          // حالة 4: تعديل فاتورة دين عادي (نفس العميل ونفس نوع الدفع)
          // 🔧 إصلاح: استخدام الدين من المعاملات بدلاً من widget.existingInvoice
          // ═══════════════════════════════════════════════════════════════════════
          else if (oldPaymentType == 'دين' && paymentType == 'دين' && customer != null &&
                   (oldCustomerId == newCustomerId || oldCustomerId == null)) {
            // حساب الفرق بين الدين الجديد والدين الحالي من المعاملات
            final debtChange = newRemaining - currentDebtFromTx;
            
            if (debtChange.abs() > 0.001) {
              // جلب رصيد العميل الحالي من قاعدة البيانات
              final customerMaps = await txn.query('customers', where: 'id = ?', whereArgs: [customer.id]);
              final currentCustomer = Customer.fromMap(customerMaps.first);
              final balanceBefore = currentCustomer.currentTotalDebt;
              final balanceAfter = balanceBefore + debtChange;
              
              await txn.update('customers', {
                'current_total_debt': balanceAfter,
                'last_modified_at': DateTime.now().toIso8601String(),
              }, where: 'id = ?', whereArgs: [customer.id]);
              
              final txUuid = await DriveService().generateTransactionUuid();
              await txn.insert('transactions', {
                'customer_id': customer.id,
                'transaction_date': DateTime.now().toIso8601String(),
                'amount_changed': debtChange,
                'balance_before_transaction': balanceBefore,
                'new_balance_after_transaction': balanceAfter,
                'transaction_type': 'invoice_edit',
                'description': 'تعديل فاتورة دين رقم $invoiceId',
                'invoice_id': invoiceId,
                'transaction_uuid': txUuid,
                'created_at': DateTime.now().toIso8601String(),
              });
            }
          }
        }
        // ═══════════════════════════════════════════════════════════════════════
        // حالة 5: فاتورة جديدة بالدين
        // 🔧 إصلاح: جلب رصيد العميل من قاعدة البيانات داخل المعاملة
        // ═══════════════════════════════════════════════════════════════════════
        else if (isNewInvoice && customer != null && paymentType == 'دين') {
          final newRemaining = totalAmount - paid;
          
          if (newRemaining > 0.001) {
            // 🔧 إصلاح: جلب الرصيد الحالي من قاعدة البيانات (وليس من الذاكرة)
            // هذا يضمن أن الرصيد محدث حتى لو تم تعديله من مكان آخر
            final freshCustomerMaps = await txn.query('customers', where: 'id = ?', whereArgs: [customer.id]);
            if (freshCustomerMaps.isEmpty) {
              throw Exception('العميل غير موجود في قاعدة البيانات');
            }
            final freshCustomer = Customer.fromMap(freshCustomerMaps.first);
            final balanceBefore = freshCustomer.currentTotalDebt;
            final balanceAfter = balanceBefore + newRemaining;
            
            await txn.update('customers', {
              'current_total_debt': balanceAfter,
              'last_modified_at': DateTime.now().toIso8601String(),
            }, where: 'id = ?', whereArgs: [customer.id]);
            
            final txUuid = await DriveService().generateTransactionUuid();
            final txSyncUuid = SyncSecurity.generateUuid(); // 🔄 sync_uuid للمزامنة
            
            final transactionId = await txn.insert('transactions', {
              'customer_id': customer.id,
              'transaction_date': DateTime.now().toIso8601String(),
              'amount_changed': newRemaining,
              'balance_before_transaction': balanceBefore,
              'new_balance_after_transaction': balanceAfter,
              'transaction_type': 'invoice_debt',
              'description': 'دين فاتورة جديدة رقم $invoiceId',
              'invoice_id': invoiceId,
              'transaction_uuid': txUuid,
              'sync_uuid': txSyncUuid, // 🔄 إضافة sync_uuid
              'created_at': DateTime.now().toIso8601String(),
            });
            
            print('🆕 تم إنشاء معاملة دين فاتورة: $newRemaining (Transaction ID: $transactionId, Sync UUID: $txSyncUuid)');
          }
        }

        final maps = await txn
            .query('invoices', where: 'id = ?', whereArgs: [invoiceId]);
        savedInvoice = Invoice.fromMap(maps.first);
      });

      // ═══════════════════════════════════════════════════════════════════════════
      // 🔥 Firebase Sync: رفع العميل والمعاملات الجديدة
      // ═══════════════════════════════════════════════════════════════════════════
      if (savedInvoice != null && savedInvoice!.customerId != null) {
        try {
          final syncHelper = FirebaseSyncHelper();
          final database = await db.database;
          
          // جلب بيانات العميل للرفع
          final customerRows = await database.query(
            'customers',
            where: 'id = ?',
            whereArgs: [savedInvoice!.customerId],
          );
          
          if (customerRows.isNotEmpty) {
            final customerData = customerRows.first;
            final customerSyncUuid = customerData['sync_uuid'] as String?;
            
            // رفع العميل إلى Firebase
            if (customerSyncUuid != null && customerSyncUuid.isNotEmpty) {
              syncHelper.syncCustomer(customerData);
              print('🔥 Firebase: تم رفع/تحديث العميل: ${customerData['name']}');
            }
            
            // جلب المعاملات المرتبطة بهذه الفاتورة ورفعها
            final transactionRows = await database.query(
              'transactions',
              where: 'invoice_id = ? AND sync_uuid IS NOT NULL',
              whereArgs: [savedInvoice!.id],
            );
            
            for (final txData in transactionRows) {
              final txSyncUuid = txData['sync_uuid'] as String?;
              if (txSyncUuid != null && customerSyncUuid != null) {
                syncHelper.syncTransaction(Map<String, dynamic>.from(txData), customerSyncUuid);
                print('🔥 Firebase: تم رفع معاملة: ${txData['amount_changed']} (Sync UUID: $txSyncUuid)');
              }
            }
          }
        } catch (syncError) {
          print('⚠️ Firebase Sync Error (non-blocking): $syncError');
        }
      }

      // Update Installer Points
      if (savedInvoice != null && 
          savedInvoice!.installerName != null && 
          savedInvoice!.installerName!.isNotEmpty) {
         try {
           // استخدام معدل النقاط من الواجهة
           final double pointsRate = installerPointsRate;
           
           await db.updateInstallerPointsFromInvoice(
             savedInvoice!.id!, 
             savedInvoice!.installerName!, 
             savedInvoice!.totalAmount,
             pointsPerHundredThousand: pointsRate,
           );
           
           // Also update the total billed amount for the installer
           final installer = await db.getInstallerByName(savedInvoice!.installerName!);
           if (installer != null && installer.id != null) {
             await db.updateInstallerBilledAmount(installer.id!);
           }
         } catch (e) {
           print('Error updating installer points/amount: $e');
         }
      }

      // ═══════════════════════════════════════════════════════════════════════════
      // ✅ تسجيل التدقيق المالي
      // ═══════════════════════════════════════════════════════════════════════════
      try {
        if (savedInvoice != null) {
          final double totalAmount = savedInvoice!.totalAmount;
          final double discountVal = savedInvoice!.discount;
          final double paidVal = savedInvoice!.amountPaidOnInvoice;
          final int? customerId = savedInvoice!.customerId;
          
          // تسجيل للفاتورة
          await db.insertAuditLog(
            operationType: isNewInvoice ? 'invoice_create' : 'invoice_update',
            entityType: 'invoice',
            entityId: savedInvoice!.id!,
            oldValues: isNewInvoice ? null : jsonEncode({
              'total_amount': invoiceToManage?.totalAmount,
              'discount': invoiceToManage?.discount,
              'payment_type': invoiceToManage?.paymentType,
              'paid_amount': invoiceToManage?.amountPaidOnInvoice,
              'customer_id': invoiceToManage?.customerId,
            }),
            newValues: jsonEncode({
              'total_amount': totalAmount,
              'discount': discountVal,
              'payment_type': paymentType,
              'paid_amount': paidVal,
              'customer_id': customerId,
              'customer_name': customerNameController.text,
              'items_count': invoiceItems.where((i) => _isInvoiceItemComplete(i)).length,
            }),
            notes: isNewInvoice 
              ? 'إنشاء فاتورة جديدة' 
              : 'تعديل فاتورة - الإجمالي: $totalAmount، الخصم: $discountVal، المدفوع: $paidVal',
          );
          
          // تسجيل للعميل أيضاً (لتظهر في سجل تدقيق العميل)
          if (customerId != null) {
            await db.insertAuditLog(
              operationType: isNewInvoice ? 'invoice_create' : 'invoice_update',
              entityType: 'customer',
              entityId: customerId,
              oldValues: isNewInvoice ? null : jsonEncode({
                'invoice_id': savedInvoice!.id,
                'total_amount': invoiceToManage?.totalAmount,
                'payment_type': invoiceToManage?.paymentType,
              }),
              newValues: jsonEncode({
                'invoice_id': savedInvoice!.id,
                'total_amount': totalAmount,
                'discount': discountVal,
                'payment_type': paymentType,
                'paid_amount': paidVal,
              }),
              notes: isNewInvoice 
                ? 'فاتورة جديدة رقم ${savedInvoice!.id} بقيمة $totalAmount' 
                : 'تعديل فاتورة رقم ${savedInvoice!.id}',
            );
          }
          
          // 📸 حفظ النسخة الأصلية عند إنشاء فاتورة جديدة
          if (isNewInvoice) {
            try {
              await db.saveInvoiceSnapshot(
                invoiceId: savedInvoice!.id!,
                snapshotType: 'original',
                notes: 'النسخة الأصلية عند الإنشاء',
              );
            } catch (e) {
              // تجاهل خطأ حفظ النسخة الأصلية
            }
          } else {
            // 📸 حفظ نسخة بعد التعديل
            try {
              await db.saveInvoiceSnapshot(
                invoiceId: savedInvoice!.id!,
                snapshotType: 'after_edit',
                notes: 'بعد التعديل - الإجمالي: $totalAmount',
              );
            } catch (e) {
              // تجاهل خطأ حفظ نسخة بعد التعديل
            }
          }
        }
      } catch (auditError) {
        // لا نوقف العملية إذا فشل التسجيل
      }

      await storage.delete(key: 'temp_invoice_data');
      savedOrSuspended = true;
      hasUnsavedChanges = false;

      // 🧠 التدريب التلقائي في الخلفية — لا يُبطئ المستخدم أبداً
      if (savedInvoice != null && savedInvoice!.id != null) {
        final invoiceIdForTraining = savedInvoice!.id!;
        // unawaited: الحفظ يكتمل فوراً والمستخدم يتنقل بحرية
        // بينما التدريب يعمل في الخلفية بشكل صامت
        unawaited(() async {
          try {
            // 1️⃣ التعلم الفوري: تحديث علاقات المنتجات وتفضيلات العميل/الفني
            await SmartSearchService.instance.trainOnNewInvoice(invoiceIdForTraining);
          } catch (e) {
            print('⚠️ [BG] SmartSearch training error: $e');
          }
          try {
            // 2️⃣ التدريب التدريجي للنظام الخبير: يُضيف على البيانات الموجودة
            await ExpertTrainingService.instance.learnFromSingleInvoice(invoiceIdForTraining);
          } catch (e) {
            print('⚠️ [BG] ExpertTraining incremental error: $e');
          }
          try {
            // 3️⃣ نظام التوقعات الذكية (stub — يتعلم تلقائياً من قاعدة البيانات)
            await InvoicePredictionService.instance.trainOnInvoice(invoiceIdForTraining);
          } catch (e) {
            print('⚠️ [BG] PredictionService training error: $e');
          }
          try {
            // 4️⃣ 🔮 تحديث إحصائيات التسعير الذكي لكل صنف في الفاتورة وبناء علاقات مستويات الأسعار
            final smartPricing = SmartPricingService();
            final smartSearchDb = SmartSearchDatabase.instance;
            
            // قراءة مستويات أسعار الفاتورة الحالية لربطها ببعض
            List<Map<String, dynamic>> invoicePriceLevels = [];
            final dbService = DatabaseService();
            final database = await dbService.database;

            final customerId = savedInvoice!.customerId;
            // تحديث التسعير الذكي حتى بدون زبون (تم إلغاء شرط if (customerId != null))
            final productsList = await db.getAllProducts();
            final productIdByName = <String, int>{};
            for (var p in productsList) {
              if (p.id != null) productIdByName[p.name] = p.id!;
            }
            
            // 1. حساب مستوى السعر لكل عنصر
            for (var item in invoiceItems.where(_isInvoiceItemComplete)) {
              final productId = productIdByName[item.productName];
              if (productId != null && item.appliedPrice > 0) {
                // تحديث الإحصائيات
                await smartPricing.updateOnInvoiceSave(
                  productId: productId,
                  customerId: customerId, // قد يكون null في الفواتير النقدية
                  price: item.appliedPrice,
                  saleType: item.saleType,
                  invoiceDate: selectedDate.toIso8601String(),
                );
                
                // جلب الإحصائيات لتحديد المستوى
                String level = 'average';
                final statsMap = await database.query('product_price_stats', where: 'product_id = ?', whereArgs: [productId]);
                if (statsMap.isNotEmpty) {
                  double median = (statsMap.first['median_price'] as num).toDouble();
                  if (item.appliedPrice <= median * 0.95) level = 'wholesale';
                  else if (item.appliedPrice >= median * 1.05) level = 'retail';
                }
                invoicePriceLevels.add({'id': productId, 'level': level});
              }
            }

            // 2. بناء العلاقات السعرية بين العناصر
            for (int i = 0; i < invoicePriceLevels.length; i++) {
              for (int j = i + 1; j < invoicePriceLevels.length; j++) {
                final itemA = invoicePriceLevels[i];
                final itemB = invoicePriceLevels[j];
                
                if (itemA['id'] != itemB['id']) {
                  await smartSearchDb.upsertPriceLevelAssociation(
                    productIdA: itemA['id'],
                    productIdB: itemB['id'],
                    priceLevelA: itemA['level'],
                    priceLevelB: itemB['level'],
                  );
                }
              }
            }
          } catch (e) {
            print('⚠️ [BG] SmartPricing update error: $e');
          }
        }());
      }
      
      // 🧠 مسح جلسة البحث الذكي بعد حفظ الفاتورة بنجاح
      // الجلسة الجديدة ستبدأ عند إنشاء فاتورة جديدة
      SmartSearchService.instance.forceNewSession();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                isNewInvoice ? 'تم حفظ الفاتورة بنجاح' : 'تم تعديل الفاتورة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        
        // ═══════════════════════════════════════════════════════════════════════════
        // 🔧 إصلاح: إعادة تحميل الأصناف من قاعدة البيانات بعد الحفظ
        // لضمان تزامن البيانات المعروضة مع البيانات المحفوظة
        // ═══════════════════════════════════════════════════════════════════════════
        if (savedInvoice != null && savedInvoice!.id != null) {
          try {
            // 🔒 تحسين الأمان: التحقق بعد الحفظ
            final verificationPassed = await _verifyInvoiceAfterSave(savedInvoice!.id!);
            if (!verificationPassed) {
              // فشل التحقق بعد الحفظ - قد تكون هناك مشكلة في البيانات
              // 🚨 إضافة أمان مكمل للتحذير:
              if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ تم حفظ الفاتورة لكن النظام اكتشف وجود فارق في مطابقة الأرقام، يرجى مراجعة تفاصيلها!'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 8)
                    )
                 );
              }
            }
            
            final freshItems = await db.getInvoiceItems(savedInvoice!.id!);
            // تهيئة الـ controllers لكل صنف
            for (var item in freshItems) {
              item.initializeControllers();
            }
            setState(() {
              invoiceItems.clear();
              invoiceItems.addAll(freshItems);
              invoiceToManage = savedInvoice;
              isViewOnly = true;
            });
          } catch (e) {
            setState(() {
              invoiceToManage = savedInvoice;
              isViewOnly = true;
            });
          }
        } else {
          setState(() {
            invoiceToManage = savedInvoice;
            isViewOnly = true;
          });
        }
        
        if (isNewInvoice) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }

      final savedId = savedInvoice?.id;
      if (savedId != null) {
        // 🛡️ تشغيل أداة التدقيق الصامتة (تطبع في الـ Console ولا تعدل البيانات)
        await db.auditInvoiceIntegrity(savedId);
      }

      return savedInvoice;
    } catch (e) {
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
      await StampManager.loadStamps(appSettings);

      final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
      final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      final font =
          pw.Font.ttf(await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
      final alnaserFont =
          pw.Font.ttf(await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
      
      // ═══════════════════════════════════════════════════════════════════════════
      // 🔧 إصلاح: جلب الأصناف من قاعدة البيانات لضمان عرض البيانات المحدثة
      // ═══════════════════════════════════════════════════════════════════════════
      List<InvoiceItem> itemsForPdf = invoiceItems;
      if (invoiceToManage != null && invoiceToManage!.id != null) {
        try {
          final freshItems = await db.getInvoiceItems(invoiceToManage!.id!);
          if (freshItems.isNotEmpty) {
            itemsForPdf = freshItems;
          }
        } catch (e) {
          // استخدام الأصناف من الذاكرة في حالة الفشل
        }
      }

      String buildUnitConversionStringForPdf(InvoiceItem item, Product? product) {
        // 1) إذا لا يوجد تحويل وحدات فعلي، لا نعرض شيئاً
        if (item.unitsInLargeUnit == null || item.unitsInLargeUnit! <= 1) {
          return '';
        }

        // 2) نفس منطق شاشة الإنشاء: إذا نوع البيع هو الوحدة الأساسية → فارغ
        if (product != null && item.saleType != null && item.saleType!.isNotEmpty) {
          String baseUnit = product.unit;
          if (baseUnit == 'piece') baseUnit = 'قطعة';
          if (baseUnit == 'meter') baseUnit = 'متر';
          if (item.saleType == baseUnit) {
            return '';
          }
        }

        // 3) مؤشر إضافي موثوق: quantityIndividual يعني بيع بالأصغر
        if (item.quantityIndividual != null && item.quantityIndividual! > 0) {
          return '';
        }

        // 4) إن كان saleType غير موجود في الهرمية فهو غالباً أصغر وحدة مخصصة
        if (product != null &&
            product.unitHierarchy != null &&
            product.unitHierarchy!.isNotEmpty &&
            item.saleType != null &&
            item.saleType!.isNotEmpty) {
          try {
            final List<dynamic> hierarchy =
                json.decode(product.unitHierarchy!.replaceAll("'", '"'));
            bool foundInHierarchy = false;
            for (int i = 0; i < hierarchy.length; i++) {
              final unitName = hierarchy[i]['unit_name'] ?? hierarchy[i]['name'];
              if (unitName == item.saleType) {
                foundInHierarchy = true;
                break;
              }
            }
            if (!foundInHierarchy) {
              return '';
            }
          } catch (e) {
            // في حالة خطأ parsing، نكمل بقية المنطق
          }
        }

        // 5) حالة المتر/لفة
        if ((item.unit == 'meter' || item.saleType == 'متر') && item.saleType == 'لفة') {
          return item.unitsInLargeUnit!.toString();
        }

        // 6) بناء سلسلة التحويل من الهرمية للوحدة الكبيرة (مثل 12 × 6)
        if (product != null &&
            product.unitHierarchy != null &&
            product.unitHierarchy!.isNotEmpty) {
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
            if (factors.isNotEmpty) {
              return factors.join(' × ');
            }
          } catch (e) {
            // fallback للأسفل
          }
        }

        // 7) fallback للوحدة الكبيرة
        return item.unitsInLargeUnit?.toString() ?? '';
      }

      final allProducts = await db.getAllProducts();
      final filteredItems =
          itemsForPdf.where((item) => _isInvoiceItemComplete(item)).toList();

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
                        buildPdfHeader(
                          font, 
                          alnaserFont, 
                          logoImage,
                          appSettings: appSettings,
                          paymentType: paymentType,
                          invoiceId: invoiceId,
                          totalAmount: afterDiscount,
                          itemsCount: filteredItems.length,
                        ),
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
                                _headerCell('التعبئة', font),
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

// ═══════════════════════════════════════════════════════════════════════════
// 🔒 نتيجة التحقق الداخلية
// ═══════════════════════════════════════════════════════════════════════════
class _ValidationResult {
  final bool isValid;
  final String? errorMessage;
  
  _ValidationResult({required this.isValid, this.errorMessage});
}
