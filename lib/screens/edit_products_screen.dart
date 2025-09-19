// screens/edit_products_screen.dart

// screens/edit_products_screen.dart
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../services/password_service.dart';
import 'dart:convert';

class EditProductsScreen extends StatefulWidget {
  const EditProductsScreen({super.key});

  @override
  State<EditProductsScreen> createState() => _EditProductsScreenState();
}

class _EditProductsScreenState extends State<EditProductsScreen> {
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();
  final PasswordService _passwordService = PasswordService();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // Require password before showing the screen content
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final bool canAccess = await _showPasswordDialog();
      if (!mounted) return;
      if (canAccess) {
        _loadProducts();
      } else {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> _loadProducts() async {
    final db = DatabaseService();
    final products = await db.getAllProducts();
    products.sort((a, b) => a.name.compareTo(b.name));
    setState(() {
      _products = products;
      _applyFilter();
      _loading = false;
    });
  }

  void _onSearchChanged() {
    setState(() {
      _applyFilter();
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _filteredProducts = _products;
    } else {
      _filteredProducts =
          _products.where((p) => p.name.contains(query)).toList();
    }
  }

  Future<bool> _showPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الرجاء إدخال كلمة السر'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'كلمة السر',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final bool isCorrect =
                  await _passwordService.verifyPassword(passwordController.text);
              Navigator.of(context).pop(isCorrect);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _editProduct(Product product) async {
    final updated = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductEditScreen(product: product),
      ),
    );
    if (updated == true) {
      _loadProducts();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const OutlineInputBorder outlineInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10.0)),
      borderSide: BorderSide(color: Color(0xFFC5CAE9)),
    );

    final Color primaryColor = const Color(0xFF3F51B5);
    final Color accentColor = const Color(0xFF8C9EFF);
    final Color textColor = const Color(0xFF212121);
    final Color lightBackgroundColor = const Color(0xFFF8F8F8);

    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white,
          secondary: accentColor,
          onSecondary: Colors.black,
          surface: Colors.white,
          onSurface: textColor,
          background: Colors.white,
          onBackground: textColor,
          error: Colors.red.shade700,
          onError: Colors.white,
          tertiary: Colors.green.shade600,
        ),
        fontFamily: 'Roboto',
        inputDecorationTheme: InputDecorationTheme(
          border: outlineInputBorder,
          enabledBorder: outlineInputBorder,
          focusedBorder: outlineInputBorder.copyWith(
            borderSide: BorderSide(color: primaryColor, width: 2.0),
          ),
          errorBorder: outlineInputBorder.copyWith(
            borderSide: BorderSide(color: Colors.red.shade700, width: 2.0),
          ),
          focusedErrorBorder: outlineInputBorder.copyWith(
            borderSide: BorderSide(color: Colors.red.shade700, width: 2.0),
          ),
          labelStyle: TextStyle(color: Colors.grey[700]),
          hintStyle: TextStyle(color: Colors.grey[500]),
          contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
          filled: true,
          fillColor: lightBackgroundColor,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 4,
          titleTextStyle: const TextStyle(fontSize: 24.0, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        cardTheme: CardThemeData(
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          margin: EdgeInsets.zero,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('تعديل البضاعة')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'بحث باسم البضاعة',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    Expanded(
                      child: _filteredProducts.isEmpty
                          ? const Center(child: Text('لا توجد بضائع مطابقة'))
                          : ListView.separated(
                              itemCount: _filteredProducts.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12.0),
                              itemBuilder: (context, index) {
                                final product = _filteredProducts[index];
                                return Card(
                                  child: ListTile(
                                    title: Text(
                                      product.name,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text('الوحدة: ${product.unit} | سعر 1: ${product.price1.toStringAsFixed(2)} | التكلفة: ${product.costPrice != null ? product.costPrice!.toStringAsFixed(2) : '-'}'),
                                    trailing: const Icon(Icons.edit),
                                    onTap: () => _editProduct(product),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class ProductEditScreen extends StatefulWidget {
  final Product product;
  const ProductEditScreen({super.key, required this.product});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  late TextEditingController _nameController;
  late TextEditingController _unitPriceController;
  late TextEditingController _price1Controller;
  late TextEditingController _price2Controller;
  late TextEditingController _price3Controller;
  late TextEditingController _price4Controller;
  late TextEditingController _price5Controller;
  late TextEditingController _costPriceController;
  late TextEditingController _piecesPerUnitController;
  late TextEditingController _lengthPerUnitController;
  String _selectedUnit = 'piece';
  bool _showCostPrice = true;
  final PasswordService _passwordService = PasswordService();
  List<Map<String, dynamic>> _unitHierarchyList = [];
  final List<String> _unitOptions = [
    'باكيت',
    'ربطة',
    'سيت',
    'كيس',
    'صندوق',
    'كرتون',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product.name);
    _unitPriceController =
        TextEditingController(text: widget.product.unitPrice.toString());
    _price1Controller =
        TextEditingController(text: widget.product.price1.toString());
    _price2Controller =
        TextEditingController(text: widget.product.price2?.toString() ?? '');
    _price3Controller =
        TextEditingController(text: widget.product.price3?.toString() ?? '');
    _price4Controller =
        TextEditingController(text: widget.product.price4?.toString() ?? '');
    _price5Controller =
        TextEditingController(text: widget.product.price5?.toString() ?? '');
    _costPriceController =
        TextEditingController(text: widget.product.costPrice?.toString() ?? '');
    _piecesPerUnitController = TextEditingController(
        text: widget.product.piecesPerUnit?.toString() ?? '');
    _lengthPerUnitController = TextEditingController(
        text: widget.product.lengthPerUnit?.toString() ?? '');
    _selectedUnit = widget.product.unit;
    // Normalize legacy/base unit: 'roll' should not be a base option; treat it as 'meter'
    if (_selectedUnit == 'roll') {
      _selectedUnit = 'meter';
    }
    if (_selectedUnit == 'piece' &&
        widget.product.unitHierarchy != null &&
        widget.product.unitHierarchy!.isNotEmpty) {
      try {
        final List<dynamic> parsed =
            json.decode(widget.product.unitHierarchy!.replaceAll("'", '"'));
        _unitHierarchyList =
            parsed.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (e) {
        _unitHierarchyList = [];
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitPriceController.dispose();
    _price1Controller.dispose();
    _price2Controller.dispose();
    _price3Controller.dispose();
    _price4Controller.dispose();
    _price5Controller.dispose();
    _costPriceController.dispose();
    _piecesPerUnitController.dispose();
    _lengthPerUnitController.dispose();
    super.dispose();
  }

  Future<bool> _showPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الرجاء إدخال كلمة السر'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'كلمة السر',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final bool isCorrect = await _passwordService
                  .verifyPassword(passwordController.text);
              Navigator.of(context).pop(isCorrect);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String normalizeProductName(String name) {
    return name.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String normalizeProductNameForCompare(String name) {
    return name.replaceAll(RegExp(r'\s+'), '');
  }

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

  Future<void> _save() async {
    final db = DatabaseService();
    final inputName = _nameController.text.trim();
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
    if (_selectedUnit == 'meter') {
      unitHierarchyJson = null;
    }
    final updatedProduct = widget.product.copyWith(
      name: inputName,
      unit: _selectedUnit,
      unitPrice: double.tryParse(_unitPriceController.text.trim()) ?? 0.0,
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
      costPrice: _showCostPrice && _costPriceController.text.trim().isNotEmpty
          ? double.tryParse(_costPriceController.text.trim())
          : widget.product.costPrice,
      piecesPerUnit: _selectedUnit == 'piece' &&
              _piecesPerUnitController.text.trim().isNotEmpty
          ? int.tryParse(_piecesPerUnitController.text.trim())
          : null,
      lengthPerUnit: _selectedUnit == 'meter' &&
              _lengthPerUnitController.text.trim().isNotEmpty
          ? double.tryParse(_lengthPerUnitController.text.trim())
          : null,
      lastModifiedAt: DateTime.now(),
      unitHierarchy: unitHierarchyJson,
    );
    final allProducts = await db.getAllProducts();
    final inputNameForCompare = normalizeProductNameForCompare(inputName);
    final exists = allProducts.any((p) =>
        normalizeProductNameForCompare(p.name) == inputNameForCompare &&
        p.id != widget.product.id);
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('يوجد منتج آخر بنفس الاسم (بغض النظر عن الفراغات)!')),
      );
      return;
    }
    await db.updateProduct(updatedProduct);
    if (mounted) Navigator.pop(context, true);
  }

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

  @override
  Widget build(BuildContext context) {
    const OutlineInputBorder outlineInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10.0)),
      borderSide: BorderSide(color: Color(0xFFC5CAE9)),
    );

    final Color primaryColor = const Color(0xFF3F51B5);
    final Color accentColor = const Color(0xFF8C9EFF);
    final Color textColor = const Color(0xFF212121);
    final Color lightBackgroundColor = const Color(0xFFF8F8F8);

    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white,
          secondary: accentColor,
          onSecondary: Colors.black,
          surface: Colors.white,
          onSurface: textColor,
          background: Colors.white,
          onBackground: textColor,
          error: Colors.red.shade700,
          onError: Colors.white,
          tertiary: Colors.green.shade600,
        ),
        fontFamily: 'Roboto',
        inputDecorationTheme: InputDecorationTheme(
          border: outlineInputBorder,
          enabledBorder: outlineInputBorder,
          focusedBorder: outlineInputBorder.copyWith(
            borderSide: BorderSide(color: primaryColor, width: 2.0),
          ),
          errorBorder: outlineInputBorder.copyWith(
            borderSide: BorderSide(color: Colors.red.shade700, width: 2.0),
          ),
          focusedErrorBorder: outlineInputBorder.copyWith(
            borderSide: BorderSide(color: Colors.red.shade700, width: 2.0),
          ),
          labelStyle: TextStyle(color: Colors.grey[700]),
          hintStyle: TextStyle(color: Colors.grey[500]),
          contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
          filled: true,
          fillColor: lightBackgroundColor,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 4,
          titleTextStyle: const TextStyle(fontSize: 24.0, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(title: const Text('تعديل البضاعة')),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ListView(
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'اسم البضاعة'),
              ),
              const SizedBox(height: 16),
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
                      if (_selectedUnit != 'piece') {
                        _unitHierarchyList.clear();
                      }
                    });
                  }
                },
              ),
              if (_selectedUnit == 'piece')
                Column(
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
                      return Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              value: row['unit_name'],
                              decoration:
                                  const InputDecoration(labelText: 'اسم الوحدة', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0)),
                              items: _unitOptions
                                  .map((unit) => DropdownMenuItem(
                                        value: unit,
                                        child: Text(unit),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                setState(() {
                                  _unitHierarchyList[idx]['unit_name'] = val;
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
                              decoration:
                                  const InputDecoration(labelText: 'العدد', isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0)),
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
              if (_selectedUnit == 'meter')
                TextField(
                  controller: _lengthPerUnitController,
                  decoration:
                      const InputDecoration(labelText: 'عدد الأمتار في اللفة'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: widget.product.id?.toString() ?? '-',
                decoration: const InputDecoration(labelText: 'ID المنتج'),
                enabled: false,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _costPriceController,
                decoration: const InputDecoration(labelText: 'سعر التكلفة'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _price1Controller,
                decoration: const InputDecoration(labelText: 'سعر 1 (المفرد)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkDuplicatePrices('price1'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _price2Controller,
                decoration: const InputDecoration(labelText: 'سعر 2 (الجملة)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkDuplicatePrices('price2'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _price3Controller,
                decoration: const InputDecoration(labelText: 'سعر 3 (جملة بيوت)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkDuplicatePrices('price3'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _price4Controller,
                decoration: const InputDecoration(labelText: 'سعر 4 (بيوت)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkDuplicatePrices('price4'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _price5Controller,
                decoration: const InputDecoration(labelText: 'سعر 5 (أخرى)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkDuplicatePrices('price5'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  padding: const EdgeInsets.symmetric(
                      vertical: 16.0, horizontal: 20.0),
                  elevation: 3,
                  textStyle: const TextStyle(
                      fontSize: 18.0, fontWeight: FontWeight.bold),
                ),
                child: const Text('حفظ التعديلات'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('تأكيد الحذف'),
                      content: const Text(
                          'هل أنت متأكد أنك تريد حذف هذا المنتج؟ لا يمكن التراجع عن هذه العملية.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('حذف'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    final db = DatabaseService();
                    await db.deleteProduct(widget.product.id!);
                    if (mounted) {
                      Navigator.of(context).pop(true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('تم حذف المنتج بنجاح'),
                            backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('حذف المنتج'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
