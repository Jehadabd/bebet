// main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:get_storage/get_storage.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'screens/main_screen.dart';
import 'screens/product_entry_screen.dart';
import 'screens/create_invoice_screen.dart';
import 'screens/edit_invoices_screen.dart';
import 'screens/edit_products_screen.dart';
import 'screens/installers_list_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/reports_screen.dart';
// removed font settings screen import
import 'screens/suppliers_list_screen.dart';
import 'services/password_service.dart';
import 'screens/password_setup_screen.dart';
 import 'screens/general_settings_screen.dart'; // Import GeneralSettingsScreen

import 'services/printing_service_windows.dart';
import 'services/printing_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة GetStorage
  await GetStorage.init();

  // تحميل ملف .env
  try {
    await dotenv.load();
    print('✅ تم تحميل ملف .env بنجاح');
    print('📊 عدد المفاتيح المحملة: ${dotenv.env.length}');
    
    // طباعة المفاتيح المتعلقة بـ API (مع إخفاء القيم)
    final apiKeys = dotenv.env.keys.where((k) => k.contains('API_KEY')).toList();
    if (apiKeys.isNotEmpty) {
      print('🔑 مفاتيح API الموجودة:');
      for (var key in apiKeys) {
        print('  - $key');
      }
    } else {
      print('⚠️ لم يتم العثور على أي مفاتيح API في ملف .env');
    }
  } catch (e) {
    print('❌ خطأ في تحميل ملف .env: $e');
  }

  // تهيئة sqflite_common_ffi على ويندوز فقط
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Check if passwords are set
  final passwordService = PasswordService();
  final bool passwordsSet = await passwordService.arePasswordsSet();

  runApp(MyApp(initialRoute: passwordsSet ? '/' : '/password_setup'));
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        Provider<PrintingService>(create: (_) => PrintingServiceWindows()),
      ],
      child: MaterialApp(
        title: 'دفتر ديوني',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          fontFamily: 'Cairo',
          textTheme: const TextTheme(
            bodyLarge: TextStyle(fontSize: 16),
            bodyMedium: TextStyle(fontSize: 14),
            titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('ar', 'SA'),
        ],
        locale: const Locale('ar', 'SA'),
        routes: {
          '/': (context) => const MainScreen(),
          '/password_setup': (context) => const PasswordSetupScreen(),
          '/general_settings': (context) => const GeneralSettingsScreen(),
          // removed font settings route
         
          '/debt_register': (context) => const HomeScreen(),
          '/product_entry': (context) => const ProductEntryScreen(),
          '/create_invoice': (context) => const CreateInvoiceScreen(),
          '/edit_invoices': (context) => const EditInvoicesScreen(),
          '/edit_products': (context) => const EditProductsScreen(),
          '/installers': (context) => const InstallersListScreen(),
          '/inventory': (context) => const InventoryScreen(),
          '/reports': (context) => const ReportsScreen(),
          '/suppliers': (context) => const SuppliersListScreen(),
        },
        initialRoute: initialRoute,
      ),
    );
  }
}
