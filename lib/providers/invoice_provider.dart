// lib/providers/invoice_provider.dart
import 'package:flutter/material.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import '../models/customer.dart';
import '../models/debt_transaction.dart';
import '../services/database_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

class InvoiceProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();

  // --- قسم حالة الفاتورة (State) ---
  Invoice? _invoiceToManage;
  bool _isViewOnly = false;
  List<InvoiceItem> _invoiceItems = [];
  
  final TextEditingController customerNameController = TextEditingController();
  final TextEditingController customerPhoneController = TextEditingController();
  final TextEditingController customerAddressController = TextEditingController();
  final TextEditingController installerNameController = TextEditingController();
  final TextEditingController paidAmountController = TextEditingController();
  final TextEditingController discountController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  String _paymentType = 'نقد';
  double _discount = 0.0;
  bool _isSaving = false;
  
  // Getters للوصول إلى البيانات من الواجهة
  List<InvoiceItem> get invoiceItems => _invoiceItems;
  bool get isViewOnly => _isViewOnly;
  DateTime get selectedDate => _selectedDate;
  String get paymentType => _paymentType;
  double get discount => _discount;
  bool get isSaving => _isSaving;
  
  double get totalAmountBeforeDiscount => _invoiceItems.fold(0.0, (sum, item) => sum + item.itemTotal);
  double get totalAmountAfterDiscount => totalAmountBeforeDiscount - _discount;

  // --- قسم منطق العمل (Business Logic) ---

  // دالة لتهيئة الفاتورة عند فتح الشاشة
  void initializeInvoice(Invoice? existingInvoice, bool isViewOnly) {
    _invoiceToManage = existingInvoice;
    _isViewOnly = isViewOnly;

    if (_invoiceToManage != null) {
      customerNameController.text = _invoiceToManage!.customerName;
      customerPhoneController.text = _invoiceToManage!.customerPhone ?? '';
      customerAddressController.text = _invoiceToManage!.customerAddress ?? '';
      installerNameController.text = _invoiceToManage!.installerName ?? '';
      _selectedDate = _invoiceToManage!.invoiceDate;
      _paymentType = _invoiceToManage!.paymentType;
      paidAmountController.text = _invoiceToManage!.amountPaidOnInvoice.toString();
      _discount = _invoiceToManage!.discount;
      discountController.text = _discount.toStringAsFixed(2);
      loadInvoiceItems();
    } else {
      // إعدادات فاتورة جديدة
      _invoiceItems = [
        InvoiceItem(
          invoiceId: 0, 
          productName: '', 
          unit: '', 
          unitPrice: 0.0,
          appliedPrice: 0.0, 
          itemTotal: 0.0, 
          uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
        )
      ];
    }
    notifyListeners();
  }

  Future<void> loadInvoiceItems() async {
    if (_invoiceToManage?.id != null) {
      _invoiceItems = await _db.getInvoiceItems(_invoiceToManage!.id!);
      notifyListeners();
    }
  }

  void addInvoiceItem(Product selectedProduct, double quantity, double priceLevel, String saleType, double baseUnitsPerSelectedUnit) {
    final double finalAppliedPrice = priceLevel;
    final double totalBaseUnitsSold = quantity * baseUnitsPerSelectedUnit;
    final double finalItemCostPrice = (selectedProduct.costPrice ?? 0) * totalBaseUnitsSold;
    final double finalItemTotal = quantity * finalAppliedPrice;
    
    double? quantityIndividual;
    double? quantityLargeUnit;
    if ((selectedProduct.unit == 'piece' && saleType == 'قطعة') ||
        (selectedProduct.unit == 'meter' && saleType == 'متر')) {
      quantityIndividual = quantity;
    } else {
      quantityLargeUnit = quantity;
    }
    
    final newItem = InvoiceItem(
      invoiceId: 0,
      productId: selectedProduct.id, // استخدام productId
      productName: selectedProduct.name,
      unit: selectedProduct.unit,
      unitPrice: selectedProduct.unitPrice,
      costPrice: finalItemCostPrice,
      quantityIndividual: quantityIndividual,
      quantityLargeUnit: quantityLargeUnit,
      appliedPrice: finalAppliedPrice,
      itemTotal: finalItemTotal,
      saleType: saleType,
      unitsInLargeUnit: baseUnitsPerSelectedUnit != 1.0 ? baseUnitsPerSelectedUnit : null,
    );
    
    setState(() {
      final existingIndex = _invoiceItems.indexWhere((item) =>
          item.productName == newItem.productName &&
          item.saleType == newItem.saleType &&
          item.unit == newItem.unit);
      if (existingIndex != -1) {
        final existingItem = _invoiceItems[existingIndex];
        _invoiceItems[existingIndex] = existingItem.copyWith(
          quantityIndividual: (existingItem.quantityIndividual ?? 0) +
              (newItem.quantityIndividual ?? 0),
          quantityLargeUnit: (existingItem.quantityLargeUnit ?? 0) +
              (newItem.quantityLargeUnit ?? 0),
          itemTotal: (existingItem.itemTotal) + (newItem.itemTotal),
          costPrice: (existingItem.costPrice ?? 0) + (newItem.costPrice ?? 0),
          unitsInLargeUnit: newItem.unitsInLargeUnit,
        );
      } else {
        _invoiceItems.add(newItem);
      }
      
      // إزالة الصفوف الفارغة
      _invoiceItems.removeWhere((item) => item.productName.isEmpty);
      
      // إضافة صف فارغ جديد إذا لم يكن موجود
      if (_invoiceItems.isEmpty || _invoiceItems.last.productName.isNotEmpty) {
        _invoiceItems.add(InvoiceItem(
          invoiceId: 0,
          productName: '',
          unit: '',
          unitPrice: 0.0,
          appliedPrice: 0.0,
          itemTotal: 0.0,
          uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
        ));
      }
      
      recalculateTotals();
    });
  }

  void removeInvoiceItemByUid(String uid) {
    setState(() {
      _invoiceItems.removeWhere((item) => item.uniqueId == uid);
      recalculateTotals();
    });
  }

  void updateInvoiceItem(InvoiceItem updatedItem) {
    setState(() {
      final index = _invoiceItems.indexWhere((it) => it.uniqueId == updatedItem.uniqueId);
      if (index != -1) {
        _invoiceItems[index] = updatedItem;
        
        // إذا كان هذا هو الصف الأخير المكتمل، أضف صفًا فارغًا جديدًا
        if (index == _invoiceItems.length - 1 && updatedItem.productName.isNotEmpty) {
          _invoiceItems.add(InvoiceItem(
            invoiceId: 0,
            productName: '',
            unit: '',
            unitPrice: 0.0,
            appliedPrice: 0.0,
            itemTotal: 0.0,
            uniqueId: 'placeholder_${DateTime.now().microsecondsSinceEpoch}',
          ));
        }
      }
      recalculateTotals();
    });
  }

  void updateDiscount(String value) {
    final newDiscount = double.tryParse(value.replaceAll(',', '')) ?? 0.0;
    _discount = newDiscount;
    recalculateTotals();
  }
  
  void setPaymentType(String type) {
    _paymentType = type;
    if (_paymentType == 'نقد') {
      paidAmountController.text = totalAmountAfterDiscount.toStringAsFixed(2);
    }
    notifyListeners();
  }
  
  void setDate(DateTime newDate) {
    _selectedDate = newDate;
    notifyListeners();
  }

  void setState(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  void recalculateTotals() {
    // تحديث الإجماليات والمبلغ المدفوع إذا كان نقداً
    if (_paymentType == 'نقد') {
      paidAmountController.text = totalAmountAfterDiscount.toStringAsFixed(2);
    }
    notifyListeners(); // أهم سطر: يخبر الواجهة بأن البيانات تغيرت
  }

  // دالة تطبيع رقم الهاتف
  String _normalizePhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'[^\d]'), '');
  }

  // دالة حفظ الفاتورة (منقولة من create_invoice_screen.dart)
  Future<Invoice?> saveInvoice(BuildContext context) async {
    if (_isSaving) return null; // منع الحفظ المزدوج
    
    _isSaving = true;
    notifyListeners();

    try {
      final db = DatabaseService();
      
      // التحقق من وجود معرّف للفاتورة
      assert(_invoiceToManage?.id != null, 'Invoice ID is required for updates');
      
      final totalAmountAfterDiscount = totalAmountAfterDiscount;
      final paidAmount = double.tryParse(paidAmountController.text.trim().replaceAll(',', '')) ?? 0.0;
      final paidOnInvoice = _paymentType == 'نقد' ? paidAmount : 0.0;

      // سيتم تنفيذ كل ما بداخل هذا القوس كوحدة واحدة
      await (await db.database).transaction((txn) async {
        // --- البحث عن العميل أو إنشاؤه ---
        Customer? customer;
        if (customerNameController.text.trim().isNotEmpty) {
          String? normalizedPhone;
          if (customerPhoneController.text.trim().isNotEmpty) {
            normalizedPhone = _normalizePhoneNumber(customerPhoneController.text.trim());
          }
          
          // البحث عن العميل داخل المعاملة
          List<Map<String, dynamic>> customerMaps;
          if (normalizedPhone != null) {
            customerMaps = await txn.query(
              'customers',
              where: 'name = ? AND phone = ?',
              whereArgs: [customerNameController.text.trim(), normalizedPhone],
            );
          } else {
            customerMaps = await txn.query(
              'customers',
              where: 'name = ?',
              whereArgs: [customerNameController.text.trim()],
            );
          }
            
          if (customerMaps.isNotEmpty) {
            customer = Customer.fromMap(customerMaps.first);
          } else {
            // إنشاء عميل جديد داخل المعاملة
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

        // --- إنشاء أو تحديث كائن الفاتورة ---
        Invoice invoice = Invoice(
          id: _invoiceToManage?.id,
          customerName: customerNameController.text.trim(),
          customerPhone: customerPhoneController.text.trim().isNotEmpty 
              ? _normalizePhoneNumber(customerPhoneController.text.trim()) 
              : null,
          customerAddress: customerAddressController.text,
          installerName: installerNameController.text.isEmpty
              ? null
              : installerNameController.text,
          invoiceDate: _selectedDate,
          paymentType: _paymentType,
          totalAmount: totalAmountAfterDiscount,
          discount: _discount,
          amountPaidOnInvoice: paidOnInvoice,
          status: 'محفوظة',
          createdAt: _invoiceToManage?.createdAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // --- حفظ أو تحديث الفاتورة ---
        if (_invoiceToManage?.id == null) {
          // إنشاء فاتورة جديدة
          final invoiceId = await txn.insert('invoices', invoice.toMap());
          invoice = invoice.copyWith(id: invoiceId);
        } else {
          // تحديث فاتورة موجودة
          await txn.update(
            'invoices',
            invoice.toMap(),
            where: 'id = ?',
            whereArgs: [invoice.id],
          );
        }

        // --- حذف أصناف الفاتورة القديمة ---
        await txn.delete(
          'invoice_items',
          where: 'invoice_id = ?',
          whereArgs: [invoice.id],
        );

        // --- إضافة أصناف الفاتورة الجديدة ---
        for (final item in _invoiceItems.where((item) => item.productName.isNotEmpty)) {
          final itemToSave = item.copyWith(invoiceId: invoice.id!);
          await txn.insert('invoice_items', itemToSave.toMap());
        }

        // --- تحديث دين العميل ---
        if (customer != null) {
          final invoiceAmount = totalAmountAfterDiscount;
          final paidAmount = double.tryParse(paidAmountController.text.trim().replaceAll(',', '')) ?? 0.0;
          final debtAmount = invoiceAmount - paidAmount;

          if (debtAmount != 0) {
            final debtTransaction = DebtTransaction(
              id: null,
              customerId: customer.id!,
              invoiceId: invoice.id,
              amount: debtAmount,
              transactionType: debtAmount > 0 ? 'debt' : 'payment',
              description: 'فاتورة رقم ${invoice.id}',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
            await txn.insert('transactions', debtTransaction.toMap());
          }

          // تحديث إجمالي دين العميل
          final currentDebt = await txn.rawQuery(
            'SELECT SUM(amount) as total FROM transactions WHERE customer_id = ?',
            [customer.id],
          );
          final newTotalDebt = currentDebt.first['total'] as double? ?? 0.0;
          await txn.update(
            'customers',
            {'current_total_debt': newTotalDebt, 'last_modified_at': DateTime.now().toIso8601String()},
            where: 'id = ?',
            whereArgs: [customer.id],
          );
        }
      });

      _invoiceToManage = invoice;
      _isSaving = false;
      notifyListeners();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الفاتورة بنجاح')),
        );
      }
      
      return invoice;
    } catch (e) {
      _isSaving = false;
      notifyListeners();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حفظ الفاتورة: ${e.toString()}')),
        );
      }
      return null;
    }
  }

  @override
  void dispose() {
    customerNameController.dispose();
    customerPhoneController.dispose();
    customerAddressController.dispose();
    installerNameController.dispose();
    paidAmountController.dispose();
    discountController.dispose();
    super.dispose();
  }
}
