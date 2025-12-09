import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  
  final db = await openDatabase(r'C:\Users\jihad\AppData\Roaming\com.example\debt_book\debt_book.db', readOnly: true);
  
  final product = await db.rawQuery('''
    SELECT * FROM products WHERE name LIKE '%بنك%شامي%'
  ''');
  
  print('المنتجات المطابقة:');
  for (final p in product) {
    print('');
    print('الاسم: ${p["name"]}');
    print('ID: ${p["id"]}');
    print('تكلفة الوحدة (cost_price): ${p["cost_price"]}');
    print('سعر البيع (selling_price): ${p["selling_price"]}');
    print('سعر الوحدة (unit_price): ${p["unit_price"]}');
    print('الوحدة: ${p["unit"]}');
    print('unit_costs: ${p["unit_costs"]}');
  }
  
  await db.close();
}
