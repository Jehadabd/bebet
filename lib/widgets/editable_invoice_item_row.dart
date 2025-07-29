// widgets/editable_invoice_item_row.dart
// widgets/editable_invoice_item_row.dart
import 'package:flutter/material.dart';
import '../models/invoice_item.dart';
import '../models/product.dart';
import 'dart:convert';

class EditableInvoiceItemRow extends StatefulWidget {
  final InvoiceItem item;
  final int index;
  final Function(InvoiceItem) onItemUpdated;
  final Function(int) onItemRemoved;
  final List<Product> allProducts;
  final bool isViewOnly;
  final bool isPlaceholder;
  final FocusNode? detailsFocusNode;
  final FocusNode? quantityFocusNode;
  final FocusNode? priceFocusNode;

  const EditableInvoiceItemRow({
    Key? key,
    required this.item,
    required this.index,
    required this.onItemUpdated,
    required this.onItemRemoved,
    required this.allProducts,
    required this.isViewOnly,
    required this.isPlaceholder,
    this.detailsFocusNode,
    this.quantityFocusNode,
    this.priceFocusNode,
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
    _quantityController = widget.item.quantityIndividualController;
    _priceController = widget.item.appliedPriceController;
    _detailsFocusNode = widget.detailsFocusNode ?? FocusNode();
    _quantityFocusNode = widget.quantityFocusNode ?? FocusNode();
    _priceFocusNode = widget.priceFocusNode ?? FocusNode();
    _saleTypeFocusNode = FocusNode();
  }

  @override
  void dispose() {
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
    double? newQuantity = double.tryParse(value);
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
      _priceController.text = _currentItem.appliedPrice.toStringAsFixed(2);
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
                conversionFactor = unit['quantity'] is int
                    ? (unit['quantity'] as int).toDouble()
                    : double.tryParse(unit['quantity'].toString()) ?? 1.0;
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
      _quantityController.text = quantity.toString();
      _priceController.text =
          (newAppliedPrice > 0) ? newAppliedPrice.toString() : '';
      widget.onItemUpdated(_currentItem);
      FocusScope.of(context).requestFocus(_priceFocusNode);
      setState(() {
        _openPriceDropdown = true;
      });
    });
  }

  void _updatePrice(String value) {
    double? newPrice = double.tryParse(value);
    if (newPrice == null || newPrice <= 0) return;
    setState(() {
      double quantity = _currentItem.quantityIndividual ??
          _currentItem.quantityLargeUnit ??
          1;
      _currentItem = _currentItem.copyWith(
        appliedPrice: newPrice,
        itemTotal: quantity * newPrice,
      );
      widget.onItemUpdated(_currentItem);
    });
  }

  String formatCurrency(num value) {
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
        child: Row(
          children: [
            Expanded(
                flex: 1,
                child: Text((widget.index + 1).toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium)),
            Expanded(
                flex: 2,
                child: widget.isViewOnly
                    ? Text(
                        widget.item.itemTotal.toStringAsFixed(2),
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
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(widget.item.productName,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium)
                    : Builder(
                        builder: (context) {
                          TextEditingController? detailsController;
                          return Autocomplete<String>(
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
                                focusNode: focusNode,
                                enabled: !widget.isViewOnly,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 0, vertical: 8),
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
                              setState(() {
                                _currentItem = _currentItem.copyWith(
                                    productName: selection);
                                widget.onItemUpdated(_currentItem);
                              });
                              detailsController?.text = selection;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _quantityFocusNode.requestFocus();
                                if (widget.quantityFocusNode != null) {
                                  widget.quantityFocusNode!.requestFocus();
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(
                        ((widget.item.quantityIndividual ??
                                    widget.item.quantityLargeUnit) ??
                                '')
                            .toString(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : TextFormField(
                        controller: _quantityController,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        enabled: !widget.isViewOnly,
                        onChanged: _updateQuantity,
                        focusNode: _quantityFocusNode,
                        onFieldSubmitted: (val) {
                          _saleTypeFocusNode.requestFocus();
                          setState(() {
                            _openSaleTypeDropdown = true;
                          });
                        },
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                          isDense: true,
                        ),
                      ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(
                        widget.item.saleType ?? '',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : DropdownButtonHideUnderline(
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
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: widget.isViewOnly
                    ? Text(
                        widget.item.appliedPrice.toStringAsFixed(2),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : TextFormField(
                        controller: _priceController,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        enabled: !widget.isViewOnly,
                        onChanged: _updatePrice,
                        focusNode: _priceFocusNode,
                        onFieldSubmitted: (val) {
                          if (widget.priceFocusNode != null) {
                            widget.priceFocusNode!.requestFocus();
                          }
                        },
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                          isDense: true,
                        ),
                      ),
              ),
            ),
            Expanded(
              flex: 2,
              child: widget.isViewOnly
                  ? ((widget.item.saleType == 'قطعة' ||
                          widget.item.saleType == 'متر')
                      ? const SizedBox.shrink()
                      : Text(
                          widget.item.unitsInLargeUnit?.toStringAsFixed(0) ??
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
            if (!widget.isViewOnly && !widget.isPlaceholder)
              SizedBox(
                width: 40,
                child: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 24),
                  onPressed: () => widget.onItemRemoved(widget.index),
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
}
