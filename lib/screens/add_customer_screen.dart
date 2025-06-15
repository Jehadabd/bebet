import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';
import 'package:flutter/services.dart';

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();
  final _initialDebtController = TextEditingController();
  final _addressController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    _initialDebtController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (_formKey.currentState!.validate()) {
      final customer = Customer(
        name: _nameController.text,
        phone: _phoneController.text.isEmpty ? null : _phoneController.text,
        generalNote: _noteController.text.isEmpty ? null : _noteController.text,
        currentTotalDebt: double.tryParse(_initialDebtController.text) ?? 0.0,
        address: _addressController.text.isEmpty ? null : _addressController.text,
      );

      await context.read<AppProvider>().addCustomer(customer);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة عميل جديد'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'اسم العميل',
                hintText: 'أدخل اسم العميل',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'الرجاء إدخال اسم العميل';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                hintText: 'أدخل رقم الهاتف (اختياري)',
                prefixText: '+964 ',
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (!RegExp(r'^\d{10}$').hasMatch(value)) {
                    return 'الرجاء إدخال رقم هاتف صحيح (10 أرقام)';
                  }
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: TextEditingController(),
              decoration: const InputDecoration(
                labelText: 'العنوان',
                hintText: 'أدخل عنوان العميل (اختياري)',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _initialDebtController,
              decoration: const InputDecoration(
                labelText: 'الدين المبدئي',
                hintText: 'أدخل الدين المبدئي (اختياري)',
                suffixText: 'دينار',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*\.?[0-9]*')),
                LengthLimitingTextInputFormatter(10),
              ],
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final number = double.tryParse(value);
                  if (number == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  if (number < 0) {
                    return 'لا يمكن إدخال قيمة سالبة';
                  }
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                hintText: 'أدخل ملاحظات إضافية (اختياري)',
              ),
              maxLines: 3,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveCustomer,
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
} 