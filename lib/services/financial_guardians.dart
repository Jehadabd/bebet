import '../models/invoice.dart';
import '../models/invoice_item.dart';

/// 🛡️ الطبقة الدفاعية: خطوط الدفاع الإضافية لحماية سلامة الفواتير
/// تم تصميم هذا الكلاس ليعمل كحارس إضافي (Guardian) دون المساس بالكود الأصلي
class FinancialGuardians {
  
  /// الطبقة الثالثة: حارس الفواتير النقدية (Cash Invoice Firewall)
  /// يمنع تماماً وجود ديون في الفواتير النقدية، ويصحح القيم إذا لزم الأمر
  static void validateCashInvoiceIntegrity(Invoice invoice) {
    if (invoice.paymentType == 'نقد') {
      // قاعدة صارمة: إذا كانت الفاتورة نقداً، يجب أن يكون المبلغ المدفوع يساوي الإجمالي
      // ولا يسمح بوجود ديون
      if (invoice.amountPaidOnInvoice != invoice.totalAmount) {
        throw Exception('🛡️ [حماية] لا يمكن حفظ فاتورة نقدية بمبلغ مدفوع لا يساوي الإجمالي. '
            'الإجمالي: ${invoice.totalAmount}، المدفوع: ${invoice.amountPaidOnInvoice}');
      }
    }
  }

  /// الطبقة الرابعة: المدقق الرياضي المسبق (Pre-Save Math Auditor)
  /// يراجع كل الأرقام والحسابات الخاصة بأصناف الفاتورة ويقارنها بالإجمالي
  static void auditInvoiceMath(Invoice invoice, List<InvoiceItem> items, double originalTotalAmount, double discount) {
    double calculatedItemsTotal = 0;

    for (var item in items) {
      // تجاهل الأصناف غير المكتملة
      if (item.productName.isEmpty) continue;
      
      final qty = (item.quantityLargeUnit ?? 0) > 0 ? item.quantityLargeUnit! : (item.quantityIndividual ?? 0);
      final expectedTotal = qty * item.appliedPrice;
      
      // التسامح مع فروق طفيفة بسبب التقريب (مثلاً 0.01)
      if ((item.itemTotal - expectedTotal).abs() > 0.1) {
         throw Exception('🛡️ [حماية] خطأ حسابي في الصنف: ${item.productName}. '
             'المتوقع: $expectedTotal، المسجل: ${item.itemTotal}');
      }
      
      calculatedItemsTotal += item.itemTotal;
    }

    // إضافة أجور التحميل لو وجدت (من الفاتورة نفسها)
    double expectedGrandTotal = calculatedItemsTotal + (invoice.loadingFee) - discount;

    if ((expectedGrandTotal - originalTotalAmount).abs() > 0.1) {
      throw Exception('🛡️ [حماية] خطأ حسابي في الإجمالي العام. '
          'مجموع الأصناف المحسوب: $expectedGrandTotal، الإجمالي المسجل: $originalTotalAmount');
    }
  }
}
