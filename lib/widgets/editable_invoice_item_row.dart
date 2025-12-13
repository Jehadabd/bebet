// widgets/editable_invoice_item_row.dart
// widgets/editable_invoice_item_row.dart
import 'package:flutter/material.dart';
import '../models/invoice_item.dart';
import 'formatters.dart';
import '../models/product.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'safe_autocomplete.dart';
import '../services/database_service.dart';

class EditableInvoiceItemRow extends StatefulWidget {
  final InvoiceItem item;
  final int index;
  final Function(InvoiceItem) onItemUpdated;
  final Function(String) onItemRemovedByUid;
  final List<Product> allProducts;
  final bool isViewOnly;
  final bool isPlaceholder;
  final FocusNode? detailsFocusNode;
  final FocusNode? quantityFocusNode;
  final FocusNode? priceFocusNode;
  final VoidCallback? onPriceSubmitted;
  final DatabaseService? databaseService;
  final String? currentCustomerName;
  final String? currentCustomerPhone;

  const EditableInvoiceItemRow({
    Key? key,
    required this.item,
    required this.index,
    required this.onItemUpdated,
    required this.onItemRemovedByUid,
    required this.allProducts,
    required this.isViewOnly,
    required this.isPlaceholder,
    this.detailsFocusNode,
    this.quantityFocusNode,
    this.priceFocusNode,
    this.onPriceSubmitted,
    this.databaseService,
    this.currentCustomerName,
    this.currentCustomerPhone,
  }) : super(key: key);

  @override
  State<EditableInvoiceItemRow> createState() => _EditableInvoiceItemRowState();
}

class _EditableInvoiceItemRowState extends State<EditableInvoiceItemRow> {
  late InvoiceItem _currentItem;
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  late FocusNode _quantityFocusNode;
  late FocusNode _priceFocusNode;
  late FocusNode _detailsFocusNode;
  late FocusNode _saleTypeFocusNode;
  bool _openSaleTypeDropdown = false;
  bool _openPriceDropdown = false;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح: تحديد الكمية الصحيحة بناءً على نوع البيع
    // ═══════════════════════════════════════════════════════════════════════════
    final quantity = _getCorrectQuantity(widget.item);
    final price = widget.item.appliedPrice;
    
    _quantityController = TextEditingController(
      text: quantity > 0 ? NumberFormat('#,##0.##', 'en_US').format(quantity) : ''
    );
    _priceController = TextEditingController(
      text: price > 0 ? NumberFormat('#,##0.##', 'en_US').format(price) : ''
    );
    
    _detailsFocusNode = widget.detailsFocusNode ?? FocusNode();
    _quantityFocusNode = widget.quantityFocusNode ?? FocusNode();
    _priceFocusNode = widget.priceFocusNode ?? FocusNode();
    _saleTypeFocusNode = FocusNode();
  }
  
  // ═══════════════════════════════════════════════════════════════════════════
  // 🔧 دالة مساعدة: الحصول على الكمية الصحيحة بناءً على نوع البيع
  // ═══════════════════════════════════════════════════════════════════════════
  double _getCorrectQuantity(InvoiceItem item) {
    // إذا كان نوع البيع قطعة أو متر، استخدم quantityIndividual
    // وإلا استخدم quantityLargeUnit (للفة، كرتون، إلخ)
    if (item.saleType == 'قطعة' || item.saleType == 'متر') {
      return item.quantityIndividual ?? item.quantityLargeUnit ?? 0;
    } else {
      // للوحدات الكبيرة (لفة، كرتون، إلخ) استخدم quantityLargeUnit أولاً
      return item.quantityLargeUnit ?? item.quantityIndividual ?? 0;
    }
  }

  @override
  void didUpdateWidget(covariant EditableInvoiceItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح مشكلة عدم تزامن البيانات عند التعديلات المتكررة
    // ═══════════════════════════════════════════════════════════════════════════
    // إذا تغير الـ item من الخارج (مثلاً بعد إعادة جلب البيانات من قاعدة البيانات)
    // يجب تحديث الـ _currentItem والمتحكمات
    if (widget.item.uniqueId != oldWidget.item.uniqueId ||
        widget.item.quantityIndividual != oldWidget.item.quantityIndividual ||
        widget.item.quantityLargeUnit != oldWidget.item.quantityLargeUnit ||
        widget.item.appliedPrice != oldWidget.item.appliedPrice ||
        widget.item.saleType != oldWidget.item.saleType ||
        widget.item.productName != oldWidget.item.productName) {
      
      _currentItem = widget.item;
      
      // 🔧 إصلاح: استخدام الدالة المساعدة للحصول على الكمية الصحيحة
      final newQuantity = _getCorrectQuantity(widget.item);
      final newPrice = widget.item.appliedPrice;
      
      // تحديث الكمية
      if (!_quantityFocusNode.hasFocus) {
        final newQuantityText = newQuantity > 0 ? NumberFormat('#,##0.##', 'en_US').format(newQuantity) : '';
        if (_quantityController.text != newQuantityText) {
          _quantityController.text = newQuantityText;
        }
      }
      
      // تحديث السعر
      if (!_priceFocusNode.hasFocus) {
        final newPriceText = newPrice > 0 ? NumberFormat('#,##0.##', 'en_US').format(newPrice) : '';
        if (_priceController.text != newPriceText) {
          _priceController.text = newPriceText;
        }
      }
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    if (widget.detailsFocusNode == null) {
      _detailsFocusNode.dispose();
    }
    if (widget.quantityFocusNode == null) {
      _quantityFocusNode.dispose();
    }
    if (widget.priceFocusNode == null) {
      _priceFocusNode.dispose();
    }
    _saleTypeFocusNode.dispose();
    super.dispose();
  }

  List<DropdownMenuItem<String>> _getUnitOptions() {
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    List<String> options = ['قطعة'];
    if (product.unit == 'piece' &&
        product.unitHierarchy != null &&
        product.unitHierarchy!.isNotEmpty) {
      try {
        List<dynamic> hierarchy =
            json.decode(product.unitHierarchy!.replaceAll("'", '"'));
        options.addAll(hierarchy
            .map((e) => (e['unit_name'] ?? e['name'] ?? '').toString()));
      } catch (e) {}
    } else if (product.unit == 'meter' && product.lengthPerUnit != null) {
      options = ['متر'];
      options.add('لفة');
    } else if (product.unit != 'piece' && product.unit != 'meter') {
      options = [product.unit];
    }
    options = options.where((e) => e != null && e.isNotEmpty).toSet().toList();
    if (_currentItem.saleType != null &&
        _currentItem.saleType!.isNotEmpty &&
        !options.contains(_currentItem.saleType)) {
      options.add(_currentItem.saleType!);
    }
    return options
        .map((unit) => DropdownMenuItem(
              value: unit,
              child: Text(unit, textAlign: TextAlign.center),
            ))
        .toList();
  }

  void _updateQuantity(String value) {
    double? newQuantity = double.tryParse(value.replaceAll(',', ''));
    if (newQuantity == null || newQuantity <= 0) return;
    
    setState(() {
      if (_currentItem.saleType == 'قطعة' || _currentItem.saleType == 'متر') {
        _currentItem = _currentItem.copyWith(
          quantityIndividual: newQuantity,
          quantityLargeUnit: null,
          itemTotal: newQuantity * _currentItem.appliedPrice,
        );
      } else {
        _currentItem = _currentItem.copyWith(
          quantityLargeUnit: newQuantity,
          quantityIndividual: null,
          itemTotal: newQuantity * _currentItem.appliedPrice,
        );
      }
      _quantityController.text = NumberFormat('#,##0.##', 'en_US').format(newQuantity);
      _priceController.text = NumberFormat('#,##0.##', 'en_US').format(_currentItem.appliedPrice);
      widget.onItemUpdated(_currentItem);
    });
  }

  void _updateSaleType(String newType) {
    Product? product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    double conversionFactor = 1.0;
    if (product != null) {
      if (product.unit == 'piece' && newType != 'قطعة') {
        if (product.unitHierarchy != null &&
            product.unitHierarchy!.isNotEmpty) {
          try {
            List<dynamic> hierarchy =
                json.decode(product.unitHierarchy!.replaceAll("'", '"'));
            for (var unit in hierarchy) {
              if ((unit['unit_name'] ?? unit['name']) == newType) {
                conversionFactor = (unit['quantity'] as num).toDouble();
                break;
              }
            }
          } catch (e) {}
        }
      } else if (product.unit == 'meter' && newType == 'لفة') {
        conversionFactor = product.lengthPerUnit ?? 1.0;
      }
    }
    setState(() {
      double newAppliedPrice;
      if ((product?.unit == 'piece' && newType != 'قطعة') ||
          (product?.unit == 'meter' && newType == 'لفة')) {
        newAppliedPrice = _currentItem.appliedPrice * conversionFactor;
      } else if ((product?.unit == 'piece' &&
              _currentItem.saleType != 'قطعة' &&
              newType == 'قطعة') ||
          (product?.unit == 'meter' &&
              _currentItem.saleType == 'لفة' &&
              newType == 'متر')) {
        newAppliedPrice = _currentItem.appliedPrice / conversionFactor;
      } else {
        newAppliedPrice = _currentItem.appliedPrice;
      }
      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ??
          1;
      _currentItem = _currentItem.copyWith(
        saleType: newType,
        appliedPrice: newAppliedPrice,
        unitsInLargeUnit: conversionFactor != 1.0 ? conversionFactor : null,
        itemTotal: quantity * newAppliedPrice,
        quantityIndividual:
            (newType == 'قطعة' || newType == 'متر') ? quantity : null,
        quantityLargeUnit:
            (newType != 'قطعة' && newType != 'متر') ? quantity : null,
      );
      _quantityController.text = NumberFormat('#,##0.##', 'en_US').format(quantity);
      _priceController.text =
          (newAppliedPrice > 0) ? NumberFormat('#,##0.##', 'en_US').format(newAppliedPrice) : '';
      widget.onItemUpdated(_currentItem);
      FocusScope.of(context).requestFocus(_priceFocusNode);
      setState(() {
        _openPriceDropdown = true;
      });
    });
  }

  void _updatePrice(String value) {
    double? newPrice = double.tryParse(value.replaceAll(',', ''));
    if (newPrice == null || newPrice <= 0) return;
    setState(() {
      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ??
          1;
      _currentItem = _currentItem.copyWith(
        appliedPrice: newPrice,
        itemTotal: quantity * newPrice,
      );
      _priceController.text = NumberFormat('#,##0.##', 'en_US').format(newPrice);
      widget.onItemUpdated(_currentItem);
    });
  }

  String formatCurrency(num value) {
    return NumberFormat('#,##0.##', 'en_US').format(value);
  }

  // الحصول على ID المنتج من قائمة المنتجات
  int? _getProductId() {
    if (_currentItem.productName.isEmpty) return null;
    final product = widget.allProducts.firstWhere(
      (p) => p.name == _currentItem.productName,
      orElse: () => Product(
        id: null,
        name: '',
        unit: 'piece',
        unitPrice: 0,
        price1: 0,
        createdAt: DateTime.now(),
        lastModifiedAt: DateTime.now(),
      ),
    );
    return product.id;
  }

  // بناء حقل إدخال بحدود مربعة
  Widget _buildSquareInputField({
    required Widget child,
    bool showBorder = true,
  }) {
    return Container(
      decoration: showBorder
          ? BoxDecoration(
              border: Border.all(color: Colors.grey.shade400, width: 1),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // ═══════════════════════════════════════════════════════════════════════════
    // 🔧 إصلاح: استخدام _currentItem دائماً لضمان عرض البيانات المحدثة
    // ═══════════════════════════════════════════════════════════════════════════
    final displayItem = _currentItem;
    final productId = _getProductId();
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 0.0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Row(
          children: [
            // عمود التسلسل (ت)
            Expanded(
                flex: 1,
                child: Text((widget.index + 1).toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium)),
            // عمود المبلغ
            Expanded(
                flex: 2,
                child: widget.isViewOnly
                    ? Text(
                        NumberFormat('#,##0.##', 'en_US').format(displayItem.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary),
                      )
                    : Text(formatCurrency(_currentItem.itemTotal),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary))),
            // عمود ID
            Expanded(
              flex: 2,
              child: _buildSquareInputField(
                child: Text(
                  productId?.toString() ?? '',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
            // عمود التفاصيل (اسم المنتج)
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(displayItem.productName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium)
                      : Builder(
                          builder: (context) {
                            TextEditingController? detailsController;
                            return SafeAutocomplete<String>(
                              initialValue:
                                  TextEditingValue(text: widget.item.productName),
                              optionsBuilder:
                                  (TextEditingValue textEditingValue) {
                                if (textEditingValue.text == '') {
                                  return const Iterable<String>.empty();
                                }
                                return widget.allProducts
                                    .map((p) => p.name)
                                    .where((option) =>
                                        option.contains(textEditingValue.text));
                              },
                              fieldViewBuilder: (context, controller, focusNode,
                                  onFieldSubmitted) {
                                detailsController = controller;
                                return TextField(
                                  controller: controller,
                                  focusNode: _detailsFocusNode,
                                  enabled: !widget.isViewOnly,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 8),
                                    isDense: true,
                                  ),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  onChanged: (val) {
                                    _currentItem =
                                        _currentItem.copyWith(productName: val);
                                  },
                                  onSubmitted: (val) {
                                    onFieldSubmitted();
                                  },
                                );
                              },
                              onSelected: (String selection) {
                                // الحصول على المنتج المحدد لتعيين نوع البيع الافتراضي
                                final selectedProduct = widget.allProducts.firstWhere(
                                  (p) => p.name == selection,
                                  orElse: () => Product(
                                    id: null,
                                    name: '',
                                    unit: 'piece',
                                    unitPrice: 0,
                                    price1: 0,
                                    createdAt: DateTime.now(),
                                    lastModifiedAt: DateTime.now(),
                                  ),
                                );
                                
                                // تحديد نوع البيع الافتراضي (أصغر وحدة)
                                String defaultSaleType = 'قطعة';
                                if (selectedProduct.unit == 'meter') {
                                  defaultSaleType = 'متر';
                                }
                                
                                setState(() {
                                  _currentItem = _currentItem.copyWith(
                                    productName: selection,
                                    saleType: defaultSaleType,
                                    appliedPrice: selectedProduct.price1 ?? selectedProduct.unitPrice,
                                    costPrice: selectedProduct.costPrice,
                                  );
                                  widget.onItemUpdated(_currentItem);
                                });
                                detailsController?.text = selection;
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _quantityFocusNode.requestFocus();
                                });
                              },
                            );
                          },
                        ),
                ),
              ),
            ),
            // عمود العدد
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(
                          // 🔧 إصلاح: استخدام الدالة المساعدة للحصول على الكمية الصحيحة
                          NumberFormat('#,##0.##', 'en_US').format(_getCorrectQuantity(displayItem)),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : TextFormField(
                          controller: _quantityController,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            ThousandSeparatorDecimalInputFormatter(),
                          ],
                          enabled: !widget.isViewOnly,
                          onChanged: _updateQuantity,
                          focusNode: _quantityFocusNode,
                          onFieldSubmitted: (val) {
                            // عند الضغط على Enter في حقل العدد
                            // اختر أصغر وحدة تلقائياً وانتقل للسعر
                            _selectDefaultSaleTypeAndMoveToPrice();
                          },
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            isDense: true,
                          ),
                        ),
                ),
              ),
            ),
            // عمود نوع البيع
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(
                          displayItem.saleType ?? '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : Focus(
                          onKeyEvent: (node, event) {
                            // عند الضغط على Enter في قائمة نوع البيع
                            if (event.logicalKey.keyLabel == 'Enter') {
                              _selectDefaultSaleTypeAndMoveToPrice();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _currentItem.saleType,
                              items: _getUnitOptions(),
                              onChanged: widget.isViewOnly
                                  ? null
                                  : (value) => _updateSaleType(value!),
                              isExpanded: true,
                              alignment: AlignmentDirectional.center,
                              style: Theme.of(context).textTheme.bodyMedium,
                              itemHeight: 48,
                              autofocus: _openSaleTypeDropdown,
                              focusNode: _saleTypeFocusNode,
                              onTap: () {
                                setState(() {
                                  _openSaleTypeDropdown = false;
                                });
                              },
                            ),
                          ),
                        ),
                ),
              ),
            ),
            // عمود السعر
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: _buildSquareInputField(
                  child: widget.isViewOnly
                      ? Text(
                          NumberFormat('#,##0.##', 'en_US').format(displayItem.appliedPrice),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      : TextFormField(
                          controller: _priceController,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            ThousandSeparatorDecimalInputFormatter(),
                          ],
                          enabled: !widget.isViewOnly,
                          onChanged: _updatePrice,
                          focusNode: _priceFocusNode,
                          onFieldSubmitted: (val) {
                            // عند الضغط على Enter في حقل السعر، انتقل للصف التالي
                            widget.onPriceSubmitted?.call();
                          },
                          style: Theme.of(context).textTheme.bodyMedium,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                            isDense: true,
                          ),
                        ),
                ),
              ),
            ),
            // عمود عدد الوحدات
            Expanded(
              flex: 2,
              child: widget.isViewOnly
                  ? ((displayItem.saleType == 'قطعة' ||
                          displayItem.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          displayItem.unitsInLargeUnit?.toStringAsFixed(0) ??
                              '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium))
                  : (_currentItem.saleType == 'قطعة' ||
                          _currentItem.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          _currentItem.unitsInLargeUnit?.toStringAsFixed(0) ??
                              '',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium),
            ),
            // زر الحذف
            if (!widget.isViewOnly && !widget.isPlaceholder)
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 24),
                  onPressed: () => widget.onItemRemovedByUid(widget.item.uniqueId),
                  tooltip: 'حذف الصنف',
                ),
              )
            else
              const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }

  // دالة لاختيار نوع البيع الافتراضي (أصغر وحدة) والانتقال للسعر
  void _selectDefaultSaleTypeAndMoveToPrice() {
    // الحصول على خيارات الوحدات
    final options = _getUnitOptions();
    if (options.isEmpty) return;
    
    // اختيار أول وحدة (أصغر وحدة) إذا لم يكن هناك نوع بيع محدد
    final firstOption = options.first.value;
    if (firstOption != null && (_currentItem.saleType == null || _currentItem.saleType!.isEmpty)) {
      _updateSaleType(firstOption);
    }
    
    // الانتقال مباشرة إلى حقل السعر
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _priceFocusNode.requestFocus();
    });
  }
}
