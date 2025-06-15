import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/database_service.dart';

class ProductEntryScreen extends StatefulWidget {
  const ProductEntryScreen({super.key});

  @override
  State<ProductEntryScreen> createState() => _ProductEntryScreenState();
}

class _ProductEntryScreenState extends State<ProductEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _selectedUnit = 'piece'; // Default unit
  final _unitPriceController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _piecesPerUnitController = TextEditingController();
  final _lengthPerUnitController = TextEditingController();
  final _price1Controller = TextEditingController();
  final _price2Controller = TextEditingController();
  final _price3Controller = TextEditingController();
  final _price4Controller = TextEditingController();
  final _price5Controller = TextEditingController();

  final DatabaseService _db = DatabaseService();

  @override
  void dispose() {
    _nameController.dispose();
    _unitPriceController.dispose();
    _costPriceController.dispose();
    _piecesPerUnitController.dispose();
    _lengthPerUnitController.dispose();
    _price1Controller.dispose();
    _price2Controller.dispose();
    _price3Controller.dispose();
    _price4Controller.dispose();
    _price5Controller.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (_formKey.currentState!.validate()) {
      final newProduct = Product(
        name: _nameController.text.trim(),
        unit: _selectedUnit,
        unitPrice: double.tryParse(_unitPriceController.text.trim()) ?? 0.0,
        costPrice: double.tryParse(_costPriceController.text.trim()),
        piecesPerUnit: _selectedUnit == 'piece' && _piecesPerUnitController.text.trim().isNotEmpty ? int.tryParse(_piecesPerUnitController.text.trim()) : null,
        lengthPerUnit: _selectedUnit == 'meter' && _lengthPerUnitController.text.trim().isNotEmpty ? double.tryParse(_lengthPerUnitController.text.trim()) : null,
        price1: double.tryParse(_price1Controller.text.trim()) ?? 0.0,
        price2: _price2Controller.text.trim().isNotEmpty ? double.tryParse(_price2Controller.text.trim()) : null,
        price3: _price3Controller.text.trim().isNotEmpty ? double.tryParse(_price3Controller.text.trim()) : null,
        price4: _price4Controller.text.trim().isNotEmpty ? double.tryParse(_price4Controller.text.trim()) : null,
        price5: _price5Controller.text.trim().isNotEmpty ? double.tryParse(_price5Controller.text.trim()) : null,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      );
      try {
        await _db.insertProduct(newProduct);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ المنتج بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
        _nameController.clear();
        _unitPriceController.clear();
        _costPriceController.clear();
        _piecesPerUnitController.clear();
        _lengthPerUnitController.clear();
        _price1Controller.clear();
        _price2Controller.clear();
        _price3Controller.clear();
        _price4Controller.clear();
        _price5Controller.clear();
        setState(() {
          _selectedUnit = 'piece';
        });
      } catch (e) {
        // نستخدم رسالة الخطأ المفهومة التي جاءت مع الاستثناء من DatabaseService
        String errorMessage = 'فشل حفظ المنتج: ${e.toString()}'; // رسالة افتراضية
         if (e is Exception) {
           errorMessage = e.toString(); // نستخدم الرسالة التي قدمتها دالة _handleDatabaseError
         }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage), // عرض الرسالة المفهومة
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدخال البضاعة'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم البضاعة'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'الرجاء إدخال اسم البضاعة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              DropdownButtonFormField<String>(
                value: _selectedUnit,
                decoration: const InputDecoration(labelText: 'وحدة البيع'),
                items: const [
                  DropdownMenuItem(value: 'piece', child: Text('قطعة')),
                  DropdownMenuItem(value: 'meter', child: Text('متر')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedUnit = value;
                      _piecesPerUnitController.clear();
                      _lengthPerUnitController.clear();
                    });
                  }
                },
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _costPriceController,
                decoration: const InputDecoration(labelText: 'سعر التكلفة للوحدة'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return null;
                  }
                  if (double.tryParse(value) == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              Visibility(
                visible: _selectedUnit == 'piece',
                child: TextFormField(
                  controller: _piecesPerUnitController,
                  decoration: const InputDecoration(labelText: 'عدد القطع في الوحدة الأكبر (كرتون/باكيت)'),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (_selectedUnit == 'piece' && value != null && value.isNotEmpty && int.tryParse(value) == null) {
                      return 'الرجاء إدخال عدد صحيح';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16.0),
              Visibility(
                visible: _selectedUnit == 'meter',
                child: TextFormField(
                  controller: _lengthPerUnitController,
                  decoration: const InputDecoration(labelText: 'طول القطعة الكاملة (بالمتر)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (_selectedUnit == 'meter' && value != null && value.isNotEmpty && double.tryParse(value) == null) {
                      return 'الرجاء إدخال رقم صحيح';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _price1Controller,
                decoration: const InputDecoration(labelText: 'سعر 1 (المفرد)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'الرجاء إدخال السعر الأول';
                  }
                  if (double.tryParse(value) == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _price2Controller,
                decoration: const InputDecoration(labelText: 'سعر 2 (اختياري)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value != null && value.isNotEmpty && double.tryParse(value) == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _price3Controller,
                decoration: const InputDecoration(labelText: 'سعر 3 (اختياري)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value != null && value.isNotEmpty && double.tryParse(value) == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _price4Controller,
                decoration: const InputDecoration(labelText: 'سعر 4 (اختياري)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value != null && value.isNotEmpty && double.tryParse(value) == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _price5Controller,
                decoration: const InputDecoration(labelText: 'سعر 5 (اختياري)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value != null && value.isNotEmpty && double.tryParse(value) == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24.0),
              ElevatedButton(
                onPressed: _saveProduct,
                child: const Text('حفظ المنتج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 