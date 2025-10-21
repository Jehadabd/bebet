// lib/widgets/customer_info_form.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/invoice_provider.dart';
import '../services/database_service.dart';
import '../models/customer.dart';

class CustomerInfoForm extends StatelessWidget {
  const CustomerInfoForm({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final invoiceProvider = Provider.of<InvoiceProvider>(context, listen: false);
    final db = DatabaseService();
    
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: invoiceProvider.isViewOnly
                  ? TextFormField(
                      controller: invoiceProvider.customerNameController,
                      decoration: const InputDecoration(labelText: 'اسم العميل'),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'الرجاء إدخال اسم العميل';
                        }
                        return null;
                      },
                      enabled: false,
                    )
                  : Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        if (textEditingValue.text == '') {
                          return const Iterable<String>.empty();
                        }
                        // استخدام البحث المحلي للعملاء
                        return _searchCustomersSync(textEditingValue.text);
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        // مزامنة النص بين المتحكمين بعد انتهاء عملية البناء
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (controller.text != invoiceProvider.customerNameController.text) {
                            controller.text = invoiceProvider.customerNameController.text;
                            controller.selection = TextSelection.fromPosition(
                              TextPosition(offset: controller.text.length),
                            );
                          }
                        });
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(labelText: 'اسم العميل'),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'الرجاء إدخال اسم العميل';
                            }
                            return null;
                          },
                          onChanged: (val) {
                            invoiceProvider.customerNameController.text = val;
                            // يمكن إضافة منطق إضافي هنا إذا لزم الأمر
                          },
                        );
                      },
                      onSelected: (String selection) async {
                        invoiceProvider.customerNameController.text = selection;

                        // --- [التحقق من التكرار] ---
                        final matchingCustomers = await db.findCustomersByNormalizedName(selection);

                        if (matchingCustomers.length > 1) {
                          // إذا كان هناك أكثر من عميل، اطلب من المستخدم التحديد
                          Customer? selectedCustomer = await showDialog<Customer>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('يوجد عدة عملاء باسم "$selection"'),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: matchingCustomers.length,
                                  itemBuilder: (context, index) {
                                    final customer = matchingCustomers[index];
                                    return ListTile(
                                      title: Text(customer.name),
                                      subtitle: Text('الهاتف: ${customer.phone ?? "غير متوفر"}'),
                                      onTap: () {
                                        Navigator.of(context).pop(customer);
                                      },
                                    );
                                  },
                                ),
                              ),
                              actions: [TextButton(onPressed: () => Navigator.of(context).pop(null), child: Text('إلغاء'))],
                            ),
                          );

                          if (selectedCustomer != null) {
                            // املأ البيانات بناءً على اختيار المستخدم
                            invoiceProvider.customerNameController.text = selectedCustomer.name;
                            invoiceProvider.customerPhoneController.text = selectedCustomer.phone ?? '';
                            invoiceProvider.customerAddressController.text = selectedCustomer.address ?? '';
                          }
                        } else if (matchingCustomers.length == 1) {
                          // إذا كان هناك عميل واحد فقط، املأ بياناته تلقائيًا
                          invoiceProvider.customerPhoneController.text = matchingCustomers.first.phone ?? '';
                          invoiceProvider.customerAddressController.text = matchingCustomers.first.address ?? '';
                        }
                      },
                    ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: invoiceProvider.customerPhoneController,
                decoration: const InputDecoration(labelText: 'رقم الجوال (اختياري)'),
                keyboardType: TextInputType.phone,
                enabled: !invoiceProvider.isViewOnly,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16.0),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: invoiceProvider.customerAddressController,
                decoration: const InputDecoration(labelText: 'العنوان (اختياري)'),
                enabled: !invoiceProvider.isViewOnly,
              ),
            ),
            const SizedBox(width: 8.0),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: invoiceProvider.installerNameController,
                decoration: const InputDecoration(labelText: 'اسم المثبت (اختياري)'),
                enabled: !invoiceProvider.isViewOnly,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // دالة البحث المحلي للعملاء
  Iterable<String> _searchCustomersSync(String query) {
    // هذه دالة مؤقتة - يمكن تحسينها لاحقاً
    return const Iterable<String>.empty();
  }
}
