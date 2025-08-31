// screens/product_entry_screen.dart
// نظام التكلفة الهيراركي التلقائي:
// - المستخدم يدخل فقط تكلفة القطعة الواحدة
// - النظام يحسب تلقائياً تكلفة الباكيت = تكلفة القطعة × عدد القطع في الباكيت
// - النظام يحسب تلقائياً تكلفة الكرتون = تكلفة الباكيت × عدد الباكيتات في الكرتون
// - وهكذا لكل مستوى في الهيراركي
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
  final _piecesPerUnitController =
      TextEditingController(); // Controller exists, but no direct UI field for it in original.
  final _lengthPerUnitController = TextEditingController();
  final _price1Controller = TextEditingController();
  final _price2Controller = TextEditingController();
  final _price3Controller = TextEditingController();
  final _price4Controller = TextEditingController();
  final _price5Controller = TextEditingController();

  final DatabaseService _db = DatabaseService();

  @override
  void initState() {
    super.initState();
    _updateUnitCostControllers();
  }

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

  // --- تكلفة الوحدات ---
  Map<String, TextEditingController> _unitCostControllers = {};

  void _addUnitHierarchyRow() {
    setState(() {
      _unitHierarchyList.add({'unit_name': null, 'quantity': null});
      _updateUnitCostControllers();
    });
  }

  void _updateUnitCostControllers() {
    // إزالة المتحكمات القديمة
    for (var controller in _unitCostControllers.values) {
      controller.dispose();
    }
    _unitCostControllers.clear();

    // إضافة متحكم للوحدة الأساسية
    _unitCostControllers['قطعة'] = TextEditingController(
      text: _costPriceController.text.isEmpty ? '' : _costPriceController.text,
    );

    // إضافة متحكمات للوحدات الإضافية (سيتم حسابها تلقائياً)
    for (var item in _unitHierarchyList) {
      if (item['unit_name'] != null) {
        _unitCostControllers[item['unit_name']] = TextEditingController();
      }
    }
    
    // حساب التكلفة تلقائياً
    _calculateUnitCosts();
  }

  // دالة حساب التكلفة تلقائياً
  void _calculateUnitCosts() {
    if (_costPriceController.text.trim().isEmpty) return;
    
    final baseCost = double.tryParse(_costPriceController.text.trim());
    if (baseCost == null) return;

    double currentCost = baseCost;
    
    for (var item in _unitHierarchyList) {
      if (item['unit_name'] != null && item['quantity'] != null) {
        final quantity = int.tryParse(item['quantity'].toString());
        if (quantity != null && quantity > 0) {
          currentCost = currentCost * quantity;
          
          // تحديث المتحكم مع التكلفة المحسوبة
          final controller = _unitCostControllers[item['unit_name']];
          if (controller != null) {
            controller.text = currentCost.toStringAsFixed(2);
          }
        }
      }
    }
  }

  String? _buildUnitCostsJson() {
    final unitCostsMap = <String, double>{};
    
    // إضافة تكلفة الوحدة الأساسية
    if (_costPriceController.text.trim().isNotEmpty) {
      unitCostsMap['قطعة'] = double.tryParse(_costPriceController.text.trim()) ?? 0.0;
    }

    // إضافة تكلفة الوحدات الإضافية (المحسوبة تلقائياً)
    for (var entry in _unitCostControllers.entries) {
      if (entry.key != 'قطعة' && entry.value.text.trim().isNotEmpty) {
        unitCostsMap[entry.key] = double.tryParse(entry.value.text.trim()) ?? 0.0;
      }
    }

    return unitCostsMap.isEmpty ? null : jsonEncode(unitCostsMap);
  }

  void _removeUnitHierarchyRow(int index) {
    setState(() {
      _unitHierarchyList.removeAt(index);
      _updateUnitCostControllers();
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
    
    // إزالة متحكمات التكلفة
    for (var controller in _unitCostControllers.values) {
      controller.dispose();
    }
    
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
            SnackBar(
              content: const Text('لا يمكن تكرار نفس السعر في أكثر من مستوى!'),
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .error, // استخدام لون الخطأ من الثيم
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
          SnackBar(
            content:
                const Text('يرجى تعبئة جميع وحدات البيع الهيراركية بشكل صحيح!'),
            backgroundColor: Theme.of(context)
                .colorScheme
                .error, // استخدام لون الخطأ من الثيم
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
        unitCosts: _buildUnitCostsJson(),
      );
      final allProducts = await _db.getAllProducts();
      final inputNameForCompare = normalizeProductNameForCompare(inputName);
      final exists = allProducts.any(
          (p) => normalizeProductNameForCompare(p.name) == inputNameForCompare);
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text(
                  'يوجد منتج آخر بنفس الاسم (بغض النظر عن الفراغات)!'),
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .error), // استخدام لون الخطأ من الثيم
        );
        return;
      }
      try {
        await _db.insertProduct(newProduct);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم حفظ المنتج بنجاح!'),
            backgroundColor: Theme.of(context)
                .colorScheme
                .tertiary, // استخدام لون النجاح من الثيم
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
          // لا يتم مسح _unitHierarchyList هنا للحفاظ على السلوك الأصلي للواجهة.
        });
      } catch (e) {
        String errorMessage = 'فشل حفظ المنتج: ${e.toString()}';
        if (e is Exception) {
          errorMessage = e.toString();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Theme.of(context)
                .colorScheme
                .error, // استخدام لون الخطأ من الثيم
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // تعريف حافة متناسقة لجميع حقول الإدخال
    const OutlineInputBorder outlineInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10.0)), // زوايا أكثر نعومة
      borderSide:
          BorderSide(color: Color(0xFFC5CAE9)), // أزرق رمادي فاتح للحدود
    );

    // الألوان الرئيسية لتصميم عصري وجذاب
    final Color primaryColor = Color(0xFF3F51B5); // Indigo
    final Color accentColor = Color(0xFF8C9EFF); // Light Indigo Accent
    final Color textColor = Color(0xFF212121); // رمادي داكن للنص الأساسي
    final Color lightBackgroundColor =
        Color(0xFFF8F8F8); // خلفية فاتحة جداً للحقول

    return Theme(
      data: ThemeData(
        // تطبيق نظام ألوان متناسق
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white,
          secondary: accentColor,
          onSecondary: Colors.black,
          surface: Colors.white,
          onSurface: textColor,
          background: Colors.white,
          onBackground: textColor,
          error: Colors.red[700]!, // أحمر داكن للأخطاء
          onError: Colors.white,
          tertiary: Colors.green[600]!, // أخضر للرسائل الناجحة
        ),
        // تطبيق أنماط خطوط متناسقة
        fontFamily: 'Roboto', // خط نظيف وحديث
        textTheme: TextTheme(
          titleLarge: TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.bold,
              color: Colors.white), // عنوان AppBar
          titleMedium: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: textColor), // عناوين الأقسام
          bodyMedium: TextStyle(fontSize: 16.0, color: textColor), // نص عادي
          labelLarge: TextStyle(
              fontSize: 16.0,
              color: Colors.white,
              fontWeight: FontWeight.w600), // نص الأزرار
          labelMedium: TextStyle(
              fontSize: 14.0, color: Colors.grey[600]), // تسميات الحقول
        ),
        // ثيم لتزيين حقول الإدخال
        inputDecorationTheme: InputDecorationTheme(
          border: outlineInputBorder,
          enabledBorder: outlineInputBorder,
          focusedBorder: outlineInputBorder.copyWith(
            borderSide: BorderSide(color: primaryColor, width: 2.0),
          ),
          errorBorder: outlineInputBorder.copyWith(
            borderSide: BorderSide(color: Colors.red[700]!, width: 2.0),
          ),
          focusedErrorBorder: outlineInputBorder.copyWith(
            borderSide: BorderSide(color: Colors.red[700]!, width: 2.0),
          ),
          labelStyle: TextStyle(color: Colors.grey[700]),
          hintStyle: TextStyle(color: Colors.grey[500]),
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16.0, horizontal: 16.0), // مساحة داخلية مريحة
          filled: true,
          fillColor: lightBackgroundColor, // خلفية فاتحة لحقول الإدخال
        ),
        // ثيم لزر ElevatedButton
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(10.0), // تطابق زوايا حقول الإدخال
            ),
            padding: const EdgeInsets.symmetric(
                vertical: 16.0, horizontal: 20.0), // مساحة داخلية أكبر للزر
            elevation: 3, // ظل خفيف
            textStyle: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
          ),
        ),
        // ثيم لزر TextButton
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        // ثيم للأيقونات
        iconTheme: IconThemeData(
          color: Colors.grey[700], // لون الأيقونات الافتراضي
        ),
        // ثيم لشريط التطبيق
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 4, // ظل أوضح لشريط التطبيق
          titleTextStyle: TextStyle(
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 1.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          margin: EdgeInsets.zero, // لإدارة الهوامش يدوياً
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدخال البضاعة'),
          // نمط العنوان يُدار الآن بواسطة appBarTheme.titleTextStyle
        ),
        body: Padding(
          padding:
              const EdgeInsets.all(24.0), // مسافة داخلية أكبر لتبدو الشاشة أوسع
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
                const SizedBox(height: 20.0), // مسافة أكبر
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
                        _lengthPerUnitController.clear();
                        // لا يتم مسح _unitHierarchyList هنا
                      });
                    }
                  },
                ),
                const SizedBox(height: 20.0),
                TextFormField(
                  controller: _costPriceController,
                  decoration:
                      const InputDecoration(labelText: 'سعر التكلفة للوحدة'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return null; // سعر التكلفة اختياري حسب الفاليجاتور الأصلي
                    }
                    if (double.tryParse(value) == null) {
                      return 'الرجاء إدخال رقم صحيح';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24.0), // مسافة أكبر قبل القسم الجديد
                Visibility(
                  visible: _selectedUnit == 'piece',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'إضافة وحدات أكبر (اختياري):',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary, // لون أساسي لعنوان القسم
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 12.0), // مسافة تحت العنوان
                      ..._unitHierarchyList.asMap().entries.map((entry) {
                        int idx = entry.key;
                        var row = entry.value;
                        String prevUnit = idx == 0
                            ? 'قطعة'
                            : (_unitHierarchyList[idx - 1]['unit_name'] ??
                                'الوحدة السابقة');
                        String label =
                            'كم $prevUnit في ${row['unit_name'] ?? 'الوحدة الجديدة'}؟';

                        return Padding(
                          padding: const EdgeInsets.only(
                              bottom: 16.0), // مسافة بين صفوف الوحدات
                          child: Card(
                            // يتم تطبيق الثيم على البطاقة
                            child: Padding(
                              padding: const EdgeInsets.all(
                                  16.0), // مساحة داخلية للبطاقة
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      value: row['unit_name'],
                                      decoration: const InputDecoration(
                                        labelText: 'اسم الوحدة',
                                        isDense:
                                            true, // لجعل حقل القائمة المنسدلة أكثر إحكاماً
                                        contentPadding: EdgeInsets.symmetric(
                                            vertical: 12.0, horizontal: 10.0),
                                      ),
                                      items: _availableUnitOptions(idx)
                                          .map((unit) => DropdownMenuItem(
                                                value: unit,
                                                child: Text(unit,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodyMedium),
                                              ))
                                          .toList(),
                                                                              onChanged: (val) {
                                          setState(() {
                                            _unitHierarchyList[idx]['unit_name'] =
                                                val;
                                            if (val != null &&
                                                _terminalUnits.contains(val) &&
                                                idx <
                                                    _unitHierarchyList.length -
                                                        1) {
                                              _unitHierarchyList.removeRange(
                                                  idx + 1,
                                                  _unitHierarchyList.length);
                                            }
                                            _updateUnitCostControllers();
                                            // حساب التكلفة تلقائياً بعد تحديث المتحكمات
                                            _calculateUnitCosts();
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
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      initialValue: row['quantity']?.toString(),
                                      decoration: InputDecoration(
                                        labelText: label,
                                        isDense:
                                            true, // لجعل حقل النص أكثر إحكاماً
                                        contentPadding: EdgeInsets.symmetric(
                                            vertical: 12.0, horizontal: 10.0),
                                      ),
                                      keyboardType: TextInputType.number,
                                      onChanged: (val) {
                                        _unitHierarchyList[idx]['quantity'] =
                                            val;
                                        // حساب التكلفة تلقائياً عند تغيير الكمية
                                        _calculateUnitCosts();
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
                                    icon: Icon(Icons.delete_outline,
                                        color:
                                            Theme.of(context).colorScheme.error,
                                        size: 28), // أيقونة حذف عصرية
                                    onPressed: () =>
                                        _removeUnitHierarchyRow(idx),
                                    tooltip: 'حذف الوحدة', // تلميح للمستخدم
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                      
                      // عرض التكلفة المحسوبة تلقائياً
                      if (_unitHierarchyList.isNotEmpty) ...[
                        const SizedBox(height: 20.0),
                        Text(
                          'التكلفة المحسوبة تلقائياً:',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12.0),
                        // تكلفة الوحدة الأساسية
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'قطعة',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: _costPriceController,
                                    decoration: const InputDecoration(
                                      labelText: 'التكلفة',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                        vertical: 12.0, horizontal: 10.0,
                                      ),
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    onChanged: (value) {
                                      setState(() {
                                        _calculateUnitCosts();
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // عرض التكلفة المحسوبة للوحدات الإضافية
                        ..._unitHierarchyList.asMap().entries.map((entry) {
                          int idx = entry.key;
                          var row = entry.value;
                          if (row['unit_name'] == null) return const SizedBox.shrink();
                          
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    row['unit_name'],
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12.0, horizontal: 10.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8.0),
                                      border: Border.all(color: Colors.grey[300]!),
                                    ),
                                    child: Text(
                                      _unitCostControllers[row['unit_name']]?.text.isEmpty == true 
                                          ? '0.00' 
                                          : _unitCostControllers[row['unit_name']]?.text ?? '0.00',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                      if (_canAddMoreUnits)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add_circle_outline,
                                size: 28), // أيقونة إضافة عصرية
                            label: const Text('إضافة وحدة أكبر'),
                            onPressed: _addUnitHierarchyRow,
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary, // لون أساسي لزر النص
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 12), // ضبط المساحة الداخلية
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24.0), // مسافة أكبر
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
                const SizedBox(height: 24.0), // مسافة قبل حقول الأسعار
                TextFormField(
                  controller: _price1Controller,
                  decoration:
                      const InputDecoration(labelText: 'سعر 1 (المفرد)'),
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
                const SizedBox(height: 20.0), // مسافة أكبر
                TextFormField(
                  controller: _price2Controller,
                  decoration:
                      const InputDecoration(labelText: 'سعر 2 (الجملة)'),
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
                const SizedBox(height: 20.0),
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
                const SizedBox(height: 20.0),
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
                const SizedBox(height: 20.0),
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
                const SizedBox(height: 32.0), // مسافة أكبر قبل زر الحفظ
                ElevatedButton(
                  onPressed: _saveProduct,
                  child: const Text('حفظ المنتج'),
                ),
                const SizedBox(height: 24.0), // مسافة في الأسفل
              ],
            ),
          ),
        ),
      ),
    );
  }
}
