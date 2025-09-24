import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/supplier.dart';
import '../services/gemini_service.dart';
import '../services/suppliers_service.dart';

class NewSupplierInvoiceScreen extends StatefulWidget {
  final Supplier supplier;
  const NewSupplierInvoiceScreen({Key? key, required this.supplier}) : super(key: key);

  @override
  State<NewSupplierInvoiceScreen> createState() => _NewSupplierInvoiceScreenState();
}

class _NewSupplierInvoiceScreenState extends State<NewSupplierInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateCtrl = TextEditingController();
  final _numberCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _paidCtrl = TextEditingController(text: '0');
  final _discountCtrl = TextEditingController(text: '0');
  String _paymentType = 'دين'; // نقد أو دين
  bool _saving = false;
  Uint8List? _pickedBytes;
  String? _pickedMime;

  final SuppliersService _service = SuppliersService();

  @override
  void dispose() {
    _dateCtrl.dispose();
    _numberCtrl.dispose();
    _totalCtrl.dispose();
    _paidCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فاتورة مورد جديدة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'ملء تلقائي من صورة',
            onPressed: _onAutofillFromImage,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text('المورد: ${widget.supplier.companyName}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _paymentType,
              decoration: const InputDecoration(labelText: 'طريقة الدفع'),
              items: const [
                DropdownMenuItem(value: 'نقد', child: Text('نقد')),
                DropdownMenuItem(value: 'دين', child: Text('دين')),
              ],
              onChanged: (v) { if (v != null) setState(() { _paymentType = v; }); },
            ),
            const SizedBox(height: 12),
              TextFormField(
                controller: _dateCtrl,
                decoration: const InputDecoration(labelText: 'تاريخ الفاتورة (ISO yyyy-MM-dd)'),
                validator: (v) => (v == null || v.isEmpty) ? 'أدخل التاريخ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _numberCtrl,
                decoration: const InputDecoration(labelText: 'رقم الفاتورة (اختياري)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _totalCtrl,
                decoration: const InputDecoration(labelText: 'الإجمالي'),
                keyboardType: TextInputType.number,
                validator: (v) => (double.tryParse(v ?? '') == null) ? 'أدخل رقم صحيح' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _discountCtrl,
                decoration: const InputDecoration(labelText: 'الخصم (اختياري)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _paidCtrl,
                decoration: const InputDecoration(labelText: 'المدفوع عند الفاتورة (اختياري)'),
                keyboardType: TextInputType.number,
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

  Future<void> _onAutofillFromImage() async {
    // اختر ملف
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    if (file.bytes == null) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mime = ext == 'pdf'
        ? 'application/pdf'
        : (ext == 'png' ? 'image/png' : 'image/jpeg');

    setState(() {
      _pickedBytes = file.bytes!;
      _pickedMime = mime;
    });

    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GEMINI_API_KEY غير مضبوط في .env')));
      return;
    }

    try {
      final gemini = GeminiService(apiKey: apiKey);
      final data = await gemini.extractInvoiceOrReceiptStructured(
        fileBytes: _pickedBytes!,
        fileMimeType: _pickedMime!,
        extractType: 'invoice',
      );
      // عبئ الحقول إن توفرت
      final date = (data['invoice_date'] ?? '').toString();
      final num = (data['invoice_number'] ?? '').toString();
      final total = (data['totals']?['grand_total'] ?? data['grand_total'] ?? data['total'] ?? '').toString();
      setState(() {
        if (date.isNotEmpty) _dateCtrl.text = date;
        if (num.isNotEmpty) _numberCtrl.text = num;
        if (total.isNotEmpty) _totalCtrl.text = total;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل التحليل: $e')));
    }
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final total = double.tryParse(_totalCtrl.text.trim()) ?? 0;
      final discount = double.tryParse(_discountCtrl.text.trim()) ?? 0;
      final paid = double.tryParse(_paidCtrl.text.trim()) ?? 0;
      final inv = SupplierInvoice(
        supplierId: widget.supplier.id!,
        invoiceNumber: _numberCtrl.text.trim().isEmpty ? null : _numberCtrl.text.trim(),
        invoiceDate: DateTime.tryParse(_dateCtrl.text.trim()) ?? DateTime.now(),
        totalAmount: total,
        discount: discount,
        amountPaid: paid,
        paymentType: _paymentType,
      );
      final id = await _service.insertSupplierInvoice(inv);
      if (_pickedBytes != null && _pickedMime != null) {
        final ext = _pickedMime == 'application/pdf' ? 'pdf' : (_pickedMime == 'image/png' ? 'png' : 'jpg');
        final path = await _service.saveAttachmentFile(bytes: _pickedBytes!, extension: ext);
        await _service.insertAttachment(Attachment(
          ownerType: 'SupplierInvoice',
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
}


