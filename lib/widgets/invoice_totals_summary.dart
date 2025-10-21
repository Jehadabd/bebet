// lib/widgets/invoice_totals_summary.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/invoice_provider.dart';

class InvoiceTotalsSummary extends StatelessWidget {
  const InvoiceTotalsSummary({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<InvoiceProvider>(
      builder: (context, invoiceProvider, child) {
        return Card(
          margin: const EdgeInsets.all(16.0),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ملخص الفاتورة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('إجمالي البنود:'),
                    Text(
                      '${invoiceProvider.totalAmountBeforeDiscount.toStringAsFixed(2)} ريال',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('الخصم:'),
                    Text(
                      '${invoiceProvider.discount.toStringAsFixed(2)} ريال',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'الإجمالي النهائي:',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${invoiceProvider.totalAmountAfterDiscount.toStringAsFixed(2)} ريال',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: invoiceProvider.paymentType,
                        decoration: const InputDecoration(
                          labelText: 'نوع الدفع',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                          DropdownMenuItem(value: 'دين', child: Text('دين')),
                        ],
                        onChanged: invoiceProvider.isViewOnly ? null : (value) {
                          if (value != null) {
                            invoiceProvider.setPaymentType(value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextFormField(
                        controller: invoiceProvider.paidAmountController,
                        decoration: const InputDecoration(
                          labelText: 'المبلغ المدفوع',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        enabled: !invoiceProvider.isViewOnly,
                        onChanged: (value) {
                          // يمكن إضافة منطق إضافي هنا إذا لزم الأمر
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: invoiceProvider.discountController,
                  decoration: const InputDecoration(
                    labelText: 'الخصم (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !invoiceProvider.isViewOnly,
                  onChanged: (value) {
                    invoiceProvider.updateDiscount(value);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
