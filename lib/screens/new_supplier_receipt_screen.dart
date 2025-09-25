import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';

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
  Uint8List? _pickedBytes;
  String? _pickedMime;
  String? _pickedName;
  final NumberFormat _nf = NumberFormat('#,##0.##', 'en');
  bool _formatting = false;

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
                onChanged: (_) => _onFormatNumber(_amountCtrl),
                validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '')) == null) ? 'أدخل رقم صحيح' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _methodCtrl,
                decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file),
                title: Text(_pickedName == null ? 'إرفاق ملف (اختياري)' : _pickedName!),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _onPickAttachment,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('اختيار'),
                    ),
                    if (_pickedBytes != null)
                      IconButton(
                        tooltip: 'إزالة',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() { _pickedBytes = null; _pickedMime = null; _pickedName = null; }),
                      )
                  ],
                ),
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
      final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
      final rec = SupplierReceipt(
        supplierId: widget.supplier.id!,
        receiptNumber: _numberCtrl.text.trim().isEmpty ? null : _numberCtrl.text.trim(),
        receiptDate: DateTime.tryParse(_dateCtrl.text.trim()) ?? DateTime.now(),
        amount: amount,
        paymentMethod: _methodCtrl.text.trim().isEmpty ? 'نقد' : _methodCtrl.text.trim(),
      );
      final id = await _service.insertSupplierReceipt(rec);
      if (_pickedBytes != null && _pickedMime != null) {
        final ext = _pickedMime == 'application/pdf' ? 'pdf' : (_pickedMime == 'image/png' ? 'png' : 'jpg');
        final path = await _service.saveAttachmentFile(bytes: _pickedBytes!, extension: ext);
        await _service.insertAttachment(Attachment(
          ownerType: 'SupplierReceipt',
          ownerId: id,
          filePath: path,
          fileType: ext == 'pdf' ? 'pdf' : 'image',
          extractedText: null,
          extractionConfidence: null,
        ));
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onPickAttachment() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : 'image/jpeg');
    setState(() {
      _pickedBytes = file.bytes!;
      _pickedMime = mime;
      _pickedName = file.name;
    });
  }

  void _onFormatNumber(TextEditingController ctrl) {
    if (_formatting) return;
    _formatting = true;
    final raw = ctrl.text.replaceAll(',', '').trim();
    if (raw.isEmpty) { _formatting = false; return; }
    final val = double.tryParse(raw);
    if (val != null) {
      ctrl.text = _nf.format(val);
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
    _formatting = false;
  }
}


