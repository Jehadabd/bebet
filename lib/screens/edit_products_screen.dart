// screens/edit_products_screen.dart
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import '../services/password_service.dart';

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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadProducts();
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
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل البضاعة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'بحث باسم البضاعة',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredProducts.isEmpty
                      ? const Center(child: Text('لا توجد بضائع مطابقة'))
                      : ListView.builder(
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: ListTile(
                                title: Text(product.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    'الوحدة: ${product.unit} | سعر 1: ${product.price1.toStringAsFixed(2)}'),
                                trailing: const Icon(Icons.edit),
                                onTap: () => _editProduct(product),
                              ),
                            );
                          },
                        ),
                ),
              ],
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
  String _selectedUnit = 'piece';
  bool _showCostPrice = false;
  final PasswordService _passwordService = PasswordService();

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
    _selectedUnit = widget.product.unit;
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

  Future<void> _save() async {
    final db = DatabaseService();
    final updatedProduct = widget.product.copyWith(
      name: _nameController.text.trim(),
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
      lastModifiedAt: DateTime.now(),
    );
    await db.updateProduct(updatedProduct);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل البضاعة')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
                if (value != null) setState(() => _selectedUnit = value);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _unitPriceController,
              decoration: const InputDecoration(labelText: 'سعر الوحدة الأصلي'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () async {
                if (!_showCostPrice) {
                  final bool canAccess = await _showPasswordDialog();
                  if (canAccess) {
                    setState(() {
                      _showCostPrice = true;
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('كلمة السر غير صحيحة.')),
                    );
                  }
                }
              },
              child: AbsorbPointer(
                absorbing: !_showCostPrice,
                child: AnimatedOpacity(
                  opacity: _showCostPrice ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: TextField(
                    controller: _costPriceController,
                    decoration: InputDecoration(
                      labelText: _showCostPrice
                          ? 'سعر التكلفة'
                          : 'انقر للإدخال (محمي)',
                      enabled: _showCostPrice,
                      fillColor: _showCostPrice ? null : Colors.grey[200],
                      filled: !_showCostPrice,
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    readOnly: !_showCostPrice,
                  ),
                ),
              ),
            ),
            if (!_showCostPrice)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  'سعر التكلفة محمي بكلمة سر. انقر لإظهاره.',
                  style: TextStyle(
                      color: Colors.redAccent, fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _price1Controller,
              decoration: const InputDecoration(labelText: 'سعر 1'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _price2Controller,
              decoration: const InputDecoration(labelText: 'سعر 2 (اختياري)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _price3Controller,
              decoration: const InputDecoration(labelText: 'سعر 3 (اختياري)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _price4Controller,
              decoration: const InputDecoration(labelText: 'سعر 4 (اختياري)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _price5Controller,
              decoration: const InputDecoration(labelText: 'سعر 5 (اختياري)'),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              child: const Text('حفظ التعديلات'),
            ),
          ],
        ),
      ),
    );
  }
}
