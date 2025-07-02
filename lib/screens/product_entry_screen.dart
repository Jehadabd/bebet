// screens/product_entry_screen.dart
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import 'dart:convert';

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

  // --- وحدة هرمية الوحدات ---
  List<Map<String, dynamic>> _unitHierarchyList = [];
  final List<String> _allUnitOptions = [
    'سيت',
    'باكيت',
    'ربطة',
    'كيس',
    'صندوق',
    'كرتون',
  ];
  final List<String> _terminalUnits = ['كرتون', 'صندوق', 'ربطة'];

  void _addUnitHierarchyRow() {
    setState(() {
      _unitHierarchyList.add({'unit_name': null, 'quantity': null});
    });
  }

  void _removeUnitHierarchyRow(int index) {
    setState(() {
      _unitHierarchyList.removeAt(index);
    });
  }

  List<String> _availableUnitOptions(int idx) {
    final used = _unitHierarchyList
        .take(idx)
        .map((e) => e['unit_name'])
        .whereType<String>()
        .toSet();
    return _allUnitOptions.where((u) => !used.contains(u)).toList();
  }

  bool get _canAddMoreUnits {
    if (_unitHierarchyList.isEmpty) return true;
    final last = _unitHierarchyList.last['unit_name'];
    return last == null || !_terminalUnits.contains(last);
  }

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

  String normalizeProductNameForCompare(String name) {
    return name.replaceAll(RegExp(r'\s+'), '');
  }

  // --- دالة التحقق من تكرار الأسعار ---
  void _checkDuplicatePrices(String changedField) {
    final prices = {
      'price1': _price1Controller.text.trim(),
      'price2': _price2Controller.text.trim(),
      'price3': _price3Controller.text.trim(),
      'price4': _price4Controller.text.trim(),
      'price5': _price5Controller.text.trim(),
    };
    final entered = prices.entries.where((e) => e.value.isNotEmpty).toList();
    for (int i = 0; i < entered.length; i++) {
      for (int j = i + 1; j < entered.length; j++) {
        if (entered[i].value == entered[j].value) {
          // إذا كان الحقل الذي تم تغييره هو أحد المتكررين، أفرغه
          if (changedField == entered[j].key) {
            setState(() {
              switch (entered[j].key) {
                case 'price1':
                  _price1Controller.clear();
                  break;
                case 'price2':
                  _price2Controller.clear();
                  break;
                case 'price3':
                  _price3Controller.clear();
                  break;
                case 'price4':
                  _price4Controller.clear();
                  break;
                case 'price5':
                  _price5Controller.clear();
                  break;
              }
            });
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يمكن تكرار نفس السعر في أكثر من مستوى!'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }
  }

  Future<void> _saveProduct() async {
    if (_formKey.currentState!.validate()) {
      final inputName = _nameController.text.trim();
      // --- تحويل هرمية الوحدات إلى JSON ---
      String? unitHierarchyJson;
      if (_selectedUnit == 'piece' && _unitHierarchyList.isNotEmpty) {
        final filtered = _unitHierarchyList
            .where((row) =>
                row['unit_name'] != null &&
                row['quantity'] != null &&
                row['quantity'].toString().isNotEmpty)
            .toList();
        if (filtered.isNotEmpty) {
          unitHierarchyJson = json.encode(filtered
              .map((row) => {
                    'unit_name': row['unit_name'],
                    'quantity': int.tryParse(row['quantity'].toString()) ?? 0,
                  })
              .toList());
        }
      }
      print('DEBUG: unitHierarchyJson = $unitHierarchyJson'); // طباعة تتبع
      if (_selectedUnit == 'piece' &&
          (_unitHierarchyList.isNotEmpty &&
              (unitHierarchyJson == null || unitHierarchyJson == '[]'))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى تعبئة جميع وحدات البيع الهيراركية بشكل صحيح!'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final newProduct = Product(
        name: inputName,
        unit: _selectedUnit,
        unitPrice: double.tryParse(_unitPriceController.text.trim()) ?? 0.0,
        costPrice: double.tryParse(_costPriceController.text.trim()),
        piecesPerUnit: _selectedUnit == 'piece' &&
                _piecesPerUnitController.text.trim().isNotEmpty
            ? int.tryParse(_piecesPerUnitController.text.trim())
            : null,
        lengthPerUnit: _selectedUnit == 'meter' &&
                _lengthPerUnitController.text.trim().isNotEmpty
            ? double.tryParse(_lengthPerUnitController.text.trim())
            : null,
        price1: double.tryParse(_price1Controller.text.trim()) ?? 0.0,
        price2: _price2Controller.text.trim().isNotEmpty
            ? double.tryParse(_price2Controller.text.trim())
            : null,
        price3: _price3Controller.text.trim().isNotEmpty
            ? double.tryParse(_price3Controller.text.trim())
            : null,
        price4: _price4Controller.text.trim().isNotEmpty
            ? double.tryParse(_price4Controller.text.trim())
            : null,
        price5: _price5Controller.text.trim().isNotEmpty
            ? double.tryParse(_price5Controller.text.trim())
            : null,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
        unitHierarchy: unitHierarchyJson,
      );
      final allProducts = await _db.getAllProducts();
      final inputNameForCompare = normalizeProductNameForCompare(inputName);
      final exists = allProducts.any(
          (p) => normalizeProductNameForCompare(p.name) == inputNameForCompare);
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('يوجد منتج آخر بنفس الاسم (بغض النظر عن الفراغات)!'),
              backgroundColor: Colors.red),
        );
        return;
      }
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
        String errorMessage = 'فشل حفظ المنتج: ${e.toString()}';
        if (e is Exception) {
          errorMessage = e.toString();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
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
                decoration:
                    const InputDecoration(labelText: 'سعر التكلفة للوحدة'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16.0),
                    const Text(
                      'إضافة وحدات أكبر (اختياري):',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    ..._unitHierarchyList.asMap().entries.map((entry) {
                      int idx = entry.key;
                      var row = entry.value;
                      String prevUnit = idx == 0
                          ? 'قطعة'
                          : (_unitHierarchyList[idx - 1]['unit_name'] ?? '');
                      String label = idx == 0
                          ? 'كم $prevUnit في ${row['unit_name'] ?? 'الوحدة'}؟'
                          : 'كم $prevUnit في ${row['unit_name'] ?? 'الوحدة'}؟';
                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: row['unit_name'],
                              decoration: const InputDecoration(
                                  labelText: 'اسم الوحدة'),
                              items: _availableUnitOptions(idx)
                                  .map((unit) => DropdownMenuItem(
                                        value: unit,
                                        child: Text(unit),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                setState(() {
                                  _unitHierarchyList[idx]['unit_name'] = val;
                                  // إذا اختار وحدة نهائية، احذف كل ما بعدها
                                  if (val != null &&
                                      _terminalUnits.contains(val) &&
                                      idx < _unitHierarchyList.length - 1) {
                                    _unitHierarchyList.removeRange(
                                        idx + 1, _unitHierarchyList.length);
                                  }
                                });
                              },
                              validator: (val) {
                                if (val == null || val.isEmpty) {
                                  return 'اختر اسم الوحدة';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              initialValue: row['quantity']?.toString(),
                              decoration: InputDecoration(labelText: label),
                              keyboardType: TextInputType.number,
                              onChanged: (val) {
                                _unitHierarchyList[idx]['quantity'] = val;
                              },
                              validator: (val) {
                                if (val == null || val.isEmpty) {
                                  return 'أدخل العدد';
                                }
                                if (int.tryParse(val) == null) {
                                  return 'أدخل رقم صحيح';
                                }
                                return null;
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _removeUnitHierarchyRow(idx),
                          ),
                        ],
                      );
                    }).toList(),
                    if (_canAddMoreUnits)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('إضافة وحدة أكبر'),
                          onPressed: _addUnitHierarchyRow,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16.0),
              Visibility(
                visible: _selectedUnit == 'meter',
                child: TextFormField(
                  controller: _lengthPerUnitController,
                  decoration: const InputDecoration(
                      labelText: 'طول القطعة الكاملة (بالمتر)'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (_selectedUnit == 'meter' &&
                        value != null &&
                        value.isNotEmpty &&
                        double.tryParse(value) == null) {
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkDuplicatePrices('price1'),
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
                decoration: const InputDecoration(labelText: 'سعر 2 (الجملة)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkDuplicatePrices('price2'),
                validator: (value) {
                  if (value != null &&
                      value.isNotEmpty &&
                      double.tryParse(value) == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _price3Controller,
                decoration:
                    const InputDecoration(labelText: 'سعر 3 (جملة بيوت)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkDuplicatePrices('price3'),
                validator: (value) {
                  if (value != null &&
                      value.isNotEmpty &&
                      double.tryParse(value) == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _price4Controller,
                decoration: const InputDecoration(labelText: 'سعر 4 (بيوت)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkDuplicatePrices('price4'),
                validator: (value) {
                  if (value != null &&
                      value.isNotEmpty &&
                      double.tryParse(value) == null) {
                    return 'الرجاء إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _price5Controller,
                decoration: const InputDecoration(labelText: 'سعر 5 (أخرى)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkDuplicatePrices('price5'),
                validator: (value) {
                  if (value != null &&
                      value.isNotEmpty &&
                      double.tryParse(value) == null) {
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
