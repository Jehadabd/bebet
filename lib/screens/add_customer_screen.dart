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

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    _initialDebtController.dispose();
    super.dispose();
  }

  Future<void> _saveCustomer() async {
    if (_formKey.currentState!.validate()) {
      final customer = Customer(
        name: _nameController.text,
        phone: _phoneController.text.isEmpty ? null : _phoneController.text,
        generalNote: _noteController.text.isEmpty ? null : _noteController.text,
        currentTotalDebt: double.tryParse(_initialDebtController.text) ?? 0.0,
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
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value != null && value.isNotEmpty && !RegExp(r'^\d+$').hasMatch(value)) {
                  return 'الرجاء إدخال أرقام فقط';
                }
                return null;
              },
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _initialDebtController,
              decoration: const InputDecoration(
                labelText: 'الدين المبدئي',
                hintText: 'أدخل الدين المبدئي (اختياري)',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*\.?[0-9]*')),
              ],
              validator: (value) {
                if (value != null && value.isNotEmpty && double.tryParse(value) == null) {
                  return 'الرجاء إدخال رقم صحيح';
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