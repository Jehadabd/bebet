// main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:get_storage/get_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:window_manager/window_manager.dart'; // 🛡️ لإدارة النافذة والإغلاق النظيف
import 'firebase_options.dart';
import 'providers/app_provider.dart';
import 'screens/home_screen.dart';
import 'screens/main_screen.dart';
import 'screens/product_entry_screen.dart';
import 'screens/create_invoice_screen.dart';
import 'screens/edit_invoices_screen.dart';
import 'screens/edit_products_screen.dart';
import 'screens/installers_list_screen.dart';

import 'screens/reports_screen.dart';
// removed font settings screen import
import 'screens/suppliers_list_screen.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/firebase_sync_settings_screen.dart';
import 'services/password_service.dart';
import 'services/database_service.dart';
import 'screens/password_setup_screen.dart';
import 'screens/general_settings_screen.dart';
import 'services/printing_service_windows.dart';
import 'services/printing_service.dart';
import 'services/sync/sync_tracker.dart'; // 🔄 تتبع المزامنة
import 'services/firebase_sync/firebase_sync.dart'; // 🔥 مزامنة Firebase
import 'services/firebase_sync/firebase_auth_service.dart'; // 🔐 مصادقة Firebase

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة GetStorage
  await GetStorage.init();

  // تحميل ملف .env من عدة مواقع محتملة
  bool envLoaded = false;
  try {
    // محاولة 1: من مجلد التطبيق الحالي (للـ EXE)
    final exeDir = Platform.resolvedExecutable;
    final exePath = exeDir.substring(0, exeDir.lastIndexOf(Platform.pathSeparator));
    final envFile = File('$exePath${Platform.pathSeparator}.env');
    
    if (await envFile.exists()) {
      await dotenv.load(fileName: envFile.path);
      envLoaded = true;
      print('✅ تم تحميل .env من مجلد التطبيق: ${envFile.path}');
    }
  } catch (e) {
    print('⚠️ فشل تحميل .env من مجلد التطبيق: $e');
  }
  
  // محاولة 2: من المجلد الافتراضي (للتطوير)
  if (!envLoaded) {
    try {
      await dotenv.load();
      envLoaded = true;
      print('✅ تم تحميل .env من المجلد الافتراضي');
    } catch (e) {
      print('⚠️ ملف .env غير موجود - سيتم استخدام القيم الافتراضية المُضمنة');
    }
  }

  // تهيئة sqflite_common_ffi على ويندوز فقط
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // فحص سلامة البيانات المالية (صامت - بدون طباعة)
  try {
    final dbService = DatabaseService();
    await dbService.performQuickIntegrityCheck();
  } catch (e) {
    // تجاهل الخطأ - لا نوقف التطبيق
  }

  // 🔄 تهيئة نظام تتبع المزامنة
  try {
    await SyncTrackerInstance.initialize();
    print('✅ تم تهيئة نظام تتبع المزامنة');
  } catch (e) {
    print('⚠️ تحذير: فشل تهيئة نظام تتبع المزامنة: $e');
    // لا نوقف التطبيق - المزامنة اختيارية
  }

  // 🔥 تهيئة Firebase (في الخلفية - لا تؤخر بدء التطبيق)
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('✅ تم تهيئة Firebase');
    
    // 🔐 تسجيل الدخول المجهول (للحماية)
    final authService = FirebaseAuthService();
    final uid = await authService.signInAnonymously();
    if (uid != null) {
      print('✅ تم تسجيل الدخول المجهول: $uid');
    } else {
      print('⚠️ فشل تسجيل الدخول المجهول - المزامنة قد لا تعمل');
    }
    
    // 🔥 تهيئة مزامنة Firebase (في الخلفية بالكامل)
    final firebaseSync = FirebaseSyncService();
    // لا ننتظر النتيجة ولا نضع timeout لكي لا نؤخر التطبيق
    firebaseSync.initialize().then((success) {
      if (success) {
        print('✅ تم تهيئة مزامنة Firebase - الجهاز مرئي للأجهزة الأخرى');
      } else {
        print('⚠️ تهيئة المزامنة لم تكتمل في الخلفية');
      }
    });

  } catch (e) {
    print('⚠️ تحذير: فشل تهيئة Firebase: $e');
    // لا نوقف التطبيق - Firebase اختياري
  }

  // Check if passwords are set
  final passwordService = PasswordService();
  final bool passwordsSet = await passwordService.arePasswordsSet();

  // 🛡️ تهيئة Window Manager
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    title: 'دفتر ديوني',
    center: true,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    // 🛡️ نمنع الإغلاق المباشر لمعالجته بشكل نظيف
    await windowManager.setPreventClose(true);
  });

  runApp(MyApp(initialRoute: passwordsSet ? '/' : '/password_setup'));
}

class MyApp extends StatefulWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (_isClosing) return; // تم بدء الإغلاق بالفعل
    
    setState(() => _isClosing = true);
    
    // 🛡️ إغلاق قواعد البيانات وإلغاء الاشتراكات
    try {
      final dbService = DatabaseService();
      await dbService.closeDatabaseForShutdown();
      
      // إيقاف أي خدمات Firebase تعمل في الخلفية
      FirebaseSyncService().dispose();
      
    } catch (e) {
      print('⚠️ خطأ أثناء إغلاق الموارد: $e');
    }
    
    // الانتظار ثانية واحدة للتأكد من حفظ كل شيء وإظهار رسالة الإغلاق
    await Future.delayed(const Duration(milliseconds: 1500));
    
    // إغلاق النافذة فعلياً وإنهاء العملية
    await windowManager.destroy();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    if (_isClosing) {
      // شاشة بسيطة تظهر أثناء الإغلاق
      return MaterialApp(
        title: 'دفتر ديوني',
        theme: ThemeData(
          fontFamily: 'Cairo', // Same font family as main app for consistency
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
        home: const Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('جاري حفظ البيانات وإغلاق التطبيق بأمان...', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
    }

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

          '/reports': (context) => const ReportsScreen(),
          '/suppliers': (context) => const SuppliersListScreen(),
          '/ai_chat': (context) => const AIChatScreen(),
          '/firebase_sync_settings': (context) => const FirebaseSyncSettingsScreen(),
        },
        initialRoute: widget.initialRoute,
      ),
    );
  }
}
