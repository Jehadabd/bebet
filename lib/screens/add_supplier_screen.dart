import 'package:flutter/material.dart';
import '../models/supplier.dart';

class AddSupplierScreen extends StatefulWidget {
  const AddSupplierScreen({Key? key}) : super(key: key);

  @override
  State<AddSupplierScreen> createState() => _AddSupplierScreenState();
}

class _AddSupplierScreenState extends State<AddSupplierScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _openingBalanceController = TextEditingController(text: '0');
  String _currency = 'IQD'; // التلقائي دينار عراقي

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _openingBalanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // Slate 50
      appBar: AppBar(
        title: const Text('إضافة مورد', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 100,
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: const Center(
                child: Icon(Icons.business_center, size: 48, color: Colors.white24),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -32),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  elevation: 8,
                  shadowColor: Colors.black12,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'بيانات المورد الأساسية',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          _buildModernTextField(
                            controller: _nameController,
                            label: 'اسم الشركة',
                            icon: Icons.business,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                          ),
                          const SizedBox(height: 16),
                          
                          _buildModernTextField(
                            controller: _phoneController,
                            label: 'الهاتف (اختياري)',
                            icon: Icons.phone,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 16),
                          
                          _buildModernTextField(
                            controller: _addressController,
                            label: 'العنوان (اختياري)',
                            icon: Icons.location_on,
                          ),
                          const SizedBox(height: 16),
                          
                          _buildModernTextField(
                            controller: _openingBalanceController,
                            label: 'رصيد افتتاحي (اختياري)',
                            icon: Icons.account_balance_wallet,
                            keyboardType: TextInputType.number,
                            helperText: 'إذا كان لك دين عليه فاكتب الرقم بالموجب. إذا كان له دين فاكتب رقماً سالباً.',
                          ),
                          const SizedBox(height: 16),
                          
                          // العملة الافتراضية للمورد
                          const Text(
                            'العملة الافتراضية للتعامل',
                            style: TextStyle(fontSize: 14, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _currency,
                                isExpanded: true,
                                icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF64748B)),
                                dropdownColor: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                items: const [
                                  DropdownMenuItem(value: 'IQD', child: Text('دينار عراقي (IQD)', style: TextStyle(color: Color(0xFF0F172A)))),
                                  DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي (USD)', style: TextStyle(color: Color(0xFF0F172A)))),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _currency = val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _onSave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6), // Blue 500
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: const Text('حفظ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixIcon: Icon(icon, color: const Color(0xFF64748B)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade300, width: 1),
        ),
      ),
    );
  }

  void _onSave() {
    if (!_formKey.currentState!.validate()) return;
    final opening = double.tryParse(_openingBalanceController.text.trim()) ?? 0;
    final supplier = Supplier(
      companyName: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      openingBalance: opening,
      currentBalance: opening,
      defaultCurrency: _currency,
    );
    Navigator.of(context).pop(supplier);
  }
}


