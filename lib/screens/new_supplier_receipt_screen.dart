import 'package:flutter/material.dart';

import '../models/supplier.dart';
import '../services/suppliers_service.dart';

class NewSupplierReceiptScreen extends StatefulWidget {
  final Supplier supplier;
  const NewSupplierReceiptScreen({Key? key, required this.supplier}) : super(key: key);

  @override
  State<NewSupplierReceiptScreen> createState() => _NewSupplierReceiptScreenState();
}

class _NewSupplierReceiptScreenState extends State<NewSupplierReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _methodCtrl = TextEditingController(text: 'نقد');
  bool _saving = false;

  final SuppliersService _service = SuppliersService();

  @override
  void dispose() {
    _dateCtrl.dispose();
    _numberCtrl.dispose();
    _amountCtrl.dispose();
    _methodCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سند قبض جديد')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text('المورد: ${widget.supplier.companyName}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _dateCtrl,
                decoration: const InputDecoration(labelText: 'تاريخ السند (ISO yyyy-MM-dd)'),
                validator: (v) => (v == null || v.isEmpty) ? 'أدخل التاريخ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _numberCtrl,
                decoration: const InputDecoration(labelText: 'رقم السند (اختياري)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                decoration: const InputDecoration(labelText: 'المبلغ'),
                keyboardType: TextInputType.number,
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'أدخل رقم صحيح' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _methodCtrl,
                decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
                  label: const Text('حفظ'),
                  onPressed: _saving ? null : _onSave,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
      final rec = SupplierReceipt(
        supplierId: widget.supplier.id!,
        receiptNumber: _numberCtrl.text.trim().isEmpty ? null : _numberCtrl.text.trim(),
        receiptDate: DateTime.tryParse(_dateCtrl.text.trim()) ?? DateTime.now(),
        amount: amount,
        paymentMethod: _methodCtrl.text.trim().isEmpty ? 'نقد' : _methodCtrl.text.trim(),
      );
      await _service.insertSupplierReceipt(rec);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}


