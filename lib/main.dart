// main.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'services/smart_pricing_service.dart'; // 🔮 محرك التسعير الذكي

// 🛡️ ملاحظة: Single Instance يُعالج على مستوى C++ في main.cpp
// باستخدام Named Mutex + RegisterWindowMessage قبل تشغيل Flutter



void main(List<String> args) async {
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

  // Check if passwords are set (عملية سريعة محلية)
  final passwordService = PasswordService();
  final bool passwordsSet = await passwordService.arePasswordsSet();

  // 🛡️ تهيئة Window Manager أولاً وبسرعة
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

  // تشغيل الواجهة للمستخدم فوراً بدون أي تأخير
  runApp(MyApp(initialRoute: passwordsSet ? '/' : '/password_setup'));

  // 🚀 إطلاق الخدمات الخلفية التي تأخذ وقتاً طويلاً كمعالجة متوازية ولا ننتظرها
  _initializeBackgroundServices();
}

// 🚀 دالة تقوم بتهيئة الخدمات المعتمدة على الشبكة أو الثقيلة بشكل متوازي في الخلفية
Future<void> _initializeBackgroundServices() async {
  print('🔄 بدء تهيئة الخدمات الخلفية بشكل متوازي...');
  
  await Future.wait([
    // المهمة 1: فحص سلامة البيانات المالية (محلي)
    Future(() async {
      try {
        final dbService = DatabaseService();
        await dbService.performQuickIntegrityCheck();
        
        // 🛡️ الفحص السريع للبيانات تلقائياً
        print('✅ اكتمل الفحص السريع للبيانات وتدقيق الأرصدة');
      } catch (e) {
        // تجاهل الخطأ
      }
    }),

    // المهمة 2: نظام تتبع المزامنة (محلي)
    Future(() async {
      try {
        await SyncTrackerInstance.initialize();
        print('✅ تم تهيئة نظام تتبع المزامنة');
      } catch (e) {
        print('⚠️ تحذير: فشل تهيئة نظام تتبع المزامنة: $e');
      }
    }),

    // المهمة 3: اتصال Firebase وتسجيل الدخول (يعتمد على الشبكة ويأخذ وقتاً طويلاً)
    Future(() async {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        print('✅ تم تهيئة Firebase بنجاح');
        
        final authService = FirebaseAuthService();
        final uid = await authService.signInAnonymously();
        if (uid != null) {
          print('✅ تم تسجيل الدخول المجهول: $uid');
        } else {
          print('⚠️ فشل تسجيل الدخول المجهول - المزامنة قد لا تعمل');
        }
        
        final firebaseSync = FirebaseSyncService();
        final success = await firebaseSync.initialize();
        if (success) {
          print('✅ تم تهيئة مزامنة Firebase - الجهاز مرئي للأجهزة الأخرى');
        } else {
          print('⚠️ تهيئة المزامنة لم تكتمل بنجاح');
        }
      } catch (e) {
        print('⚠️ تحذير: فشل تهيئة Firebase بالكامل: $e');
      }
    }),

    // المهمة 4: 🔮 محرك التسعير الذكي
    Future(() async {
      try {
        final smartPricingService = SmartPricingService();
        final dbService = DatabaseService();
        await smartPricingService.initialize(dbService);
        print('✅ تم تهيئة محرك التسعير الذكي');
      } catch (e) {
        print('⚠️ تحذير: فشل تهيئة محرك التسعير الذكي: $e');
      }
    }),
  ]);
  
  print('✨ اكتملت جميع مهام التهيئة الخلفية!');
}

// ⌨️ نوايا الاختصارات العالمية (F1, F2, F3)
class _NavigateToDebtRegisterIntent extends Intent {
  const _NavigateToDebtRegisterIntent();
}
class _NavigateToCreateInvoiceIntent extends Intent {
  const _NavigateToCreateInvoiceIntent();
}
class _NavigateToEditProductsIntent extends Intent {
  const _NavigateToEditProductsIntent();
}

class MyApp extends StatefulWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  State<MyApp> createState() => _MyAppState();
}

// 🔑 مفتاح تنقل عام للاستخدام من أي مكان
final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>();

// 📍 تتبع اسم المسار الحالي لتفادي إعادة فتح نفس الشاشة عند الاختصارات
String? _currentRouteName;

class AppRouteObserver extends NavigatorObserver {
  void _updateCurrentRoute(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && name.isNotEmpty) {
      _currentRouteName = name;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _updateCurrentRoute(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _updateCurrentRoute(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _updateCurrentRoute(previousRoute);
  }
}

final AppRouteObserver appRouteObserver = AppRouteObserver();


class _MyAppState extends State<MyApp> with WindowListener {
  bool _isClosing = false;

  void _navigateIfNotCurrent(String routeName) {
    if (_currentRouteName == routeName) return;
    globalNavigatorKey.currentState?.pushNamed(routeName);
  }


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
    if (_isClosing) return;

    _isClosing = true;
    if (mounted) setState(() {});

    // تنظيف الموارد بمهلة زمنية قصيرة
    try {
      await DatabaseService().closeDatabaseForShutdown().timeout(
        const Duration(seconds: 3),
        onTimeout: () => print('⚠️ انتهت مهلة إغلاق قاعدة البيانات.'),
      );
    } catch (e) {
      print('⚠️ خطأ أثناء إغلاق قاعدة البيانات: $e');
    }

    try {
      await FirebaseSyncService().dispose().timeout(
        const Duration(seconds: 3),
        onTimeout: () => print('⚠️ انتهت مهلة إغلاق Firebase.'),
      );
    } catch (e) {
      print('⚠️ خطأ أثناء إغلاق Firebase: $e');
    }

    // 🛡️ نسمح بالإغلاق أولاً (احتياطاً)
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {}

    // ⚠️ مهم جداً: لا نستخدم windowManager.destroy() أو close()
    // لأنهما قد يدمران النافذة قبل أن ينفذ exit(0)، فتتعلق العملية في الخلفية.
    // exit(0) هو الطريقة الوحيدة الموثوقة لإنهاء تطبيق Flutter Desktop بالكامل.
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
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          // ⌨️ F1 → سجل الديون
          LogicalKeySet(LogicalKeyboardKey.f1): const _NavigateToDebtRegisterIntent(),
          // ⌨️ F2 → إنشاء فاتورة
          LogicalKeySet(LogicalKeyboardKey.f2): const _NavigateToCreateInvoiceIntent(),
          // ⌨️ F3 → تعديل القوائم/المنتجات
          LogicalKeySet(LogicalKeyboardKey.f3): const _NavigateToEditProductsIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _NavigateToDebtRegisterIntent: CallbackAction<_NavigateToDebtRegisterIntent>(
              // إذا كنا في نفس الشاشة لا نفعل شيئاً
              onInvoke: (_) => _navigateIfNotCurrent('/debt_register'),
            ),
            _NavigateToCreateInvoiceIntent: CallbackAction<_NavigateToCreateInvoiceIntent>(
              // إذا كنا في نفس الشاشة لا نفعل شيئاً
              onInvoke: (_) => _navigateIfNotCurrent('/create_invoice'),
            ),
            _NavigateToEditProductsIntent: CallbackAction<_NavigateToEditProductsIntent>(
              // F3 → تعديل القوائم، وإذا كنا فيها لا نفعل شيئاً
              onInvoke: (_) => _navigateIfNotCurrent('/edit_invoices'),
            ),
          },
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
        navigatorKey: globalNavigatorKey,
        navigatorObservers: [appRouteObserver],
      ),
        ), // نهاية Actions
      ), // نهاية Shortcuts
    );
  }
}
