// check_invoice_316.dart
// فحص الفاتورة رقم 316 التي تسبب مشكلة التكلفة العالية

import 'dart:io';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  print('');
  print('╔═══════════════════════════════════════════════════════════════════╗');
  print('║  🔍 فحص الفاتورة رقم 316');
  print('╚═══════════════════════════════════════════════════════════════════╝');
  print('');
  
  final dbPath = r'C:\Users\jihad\AppData\Roaming\com.example\debt_book\debt_book.db';
  final db = await openDatabase(dbPath, readOnly: true);
  
  // جلب بيانات الفاتورة
  final invoice = await db.rawQuery('''
    SELECT * FROM invoices WHERE id = 316
  ''');
  
  if (invoice.isEmpty) {
    print('❌ الفاتورة غير موجودة!');
    await db.close();
    return;
  }
  
  print('📄 بيانات الفاتورة:');
  for (final key in invoice.first.keys) {
    print('   $key: ${invoice.first[key]}');
  }
  print('');
  
  // جلب جميع بنود الفاتورة
  final allItems = await db.rawQuery('''
    SELECT * FROM invoice_items WHERE invoice_id = 316
  ''');
  
  print('📋 جميع بنود الفاتورة (${allItems.length} بند):');
  print('');
  
  for (int i = 0; i < allItems.length; i++) {
    final item = allItems[i];
    print('═══════════════════════════════════════════════════════════════════');
    print('بند ${i + 1}:');
    for (final key in item.keys) {
      print('   $key: ${item[key]}');
    }
    
    // جلب بيانات المنتج
    final productName = item['product_name'] as String?;
    if (productName != null) {
      final product = await db.rawQuery('''
        SELECT * FROM products WHERE name = ?
      ''', [productName]);
      
      if (product.isNotEmpty) {
        print('');
        print('   📦 بيانات المنتج:');
        print('   cost_price: ${product.first['cost_price']}');
        print('   unit: ${product.first['unit']}');
        print('   unit_hierarchy: ${product.first['unit_hierarchy']}');
        print('   unit_costs: ${product.first['unit_costs']}');
        print('   length_per_unit: ${product.first['length_per_unit']}');
        
        // حساب التكلفة
        final qi = (item['quantity_individual'] as num?)?.toDouble() ?? 0.0;
        final ql = (item['quantity_large_unit'] as num?)?.toDouble() ?? 0.0;
        final uilu = (item['units_in_large_unit'] as num?)?.toDouble() ?? 0.0;
        final actualCostPerUnit = (item['actual_cost_price'] as num?)?.toDouble();
        final productCost = (product.first['cost_price'] as num?)?.toDouble() ?? 0.0;
        final sellingPrice = (item['applied_price'] as num?)?.toDouble() ?? 0.0;
        final saleType = item['sale_type'] as String? ?? '';
        
        final soldAsLargeUnit = ql > 0;
        final soldUnitsCount = soldAsLargeUnit ? ql : qi;
        
        double costPerSoldUnit;
        String costSource;
        
        if (actualCostPerUnit != null && actualCostPerUnit > 0) {
          costPerSoldUnit = actualCostPerUnit;
          costSource = 'actualCostPerUnit';
        } else if (soldAsLargeUnit && uilu > 0) {
          costPerSoldUnit = productCost * uilu;
          costSource = 'productCost * uilu = $productCost * $uilu';
        } else {
          costPerSoldUnit = productCost;
          costSource = 'productCost';
        }
        
        if (costPerSoldUnit <= 0 && sellingPrice > 0) {
          costPerSoldUnit = sellingPrice * 0.9;
          costSource = 'estimated_10%';
        }
        
        final itemCost = costPerSoldUnit * soldUnitsCount;
        final itemTotal = (item['item_total'] as num?)?.toDouble() ?? 0.0;
        final profit = itemTotal - itemCost;
        
        print('');
        print('   📊 حساب التكلفة:');
        print('   qi: $qi, ql: $ql, uilu: $uilu');
        print('   actualCostPerUnit: $actualCostPerUnit');
        print('   productCost: $productCost');
        print('   saleType: $saleType');
        print('   soldAsLargeUnit: $soldAsLargeUnit');
        print('   soldUnitsCount: $soldUnitsCount');
        print('   costSource: $costSource');
        print('   costPerSoldUnit: $costPerSoldUnit');
        print('   itemCost: $itemCost');
        print('   itemTotal: $itemTotal');
        print('   profit: $profit ${profit < 0 ? "⚠️ سالب!" : "✅"}');
      } else {
        print('   ❌ المنتج غير موجود في قاعدة البيانات!');
      }
    }
    print('');
  }
  
  await db.close();
}
