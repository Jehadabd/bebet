import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final db = await openDatabase(r'C:\Users\jihad\AppData\Roaming\com.example\debt_book\debt_book.db', readOnly: true);
  
  final product = await db.rawQuery('''
    SELECT * FROM products WHERE name LIKE '%كيبل 4%16%'
  ''');
  
  print('المنتجات المطابقة:');
  for (final p in product) {
    print('');
    print('الاسم: ${p["name"]}');
    print('تكلفة المتر: ${p["cost_price"]}');
    print('سعر البيع: ${p["selling_price"]}');
    print('الوحدة: ${p["unit"]}');
    print('طول اللفة: ${p["length_per_unit"]}');
    print('unit_costs: ${p["unit_costs"]}');
    print('unit_hierarchy: ${p["unit_hierarchy"]}');
  }
  
  await db.close();
}
