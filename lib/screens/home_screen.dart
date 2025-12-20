// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';
import '../services/sync/sync_service.dart';
import '../services/sync/sync_audit_service.dart';
import '../services/settings_manager.dart';
import 'customer_details_screen.dart';
import 'add_customer_screen.dart';
import 'saved_invoices_screen.dart';
import 'ai_chat_screen.dart';
import 'package:intl/intl.dart';

// أسماء أنواع الترتيب بالعربية
String getSortTypeName(CustomerSortType type) {
  switch (type) {
    case CustomerSortType.alphabetical:
      return 'أبجدي';
    case CustomerSortType.lastDebtAdded:
      return 'آخر إضافة دين';
    case CustomerSortType.lastPayment:
      return 'آخر تسديد';
    case CustomerSortType.lastTransaction:
      return 'آخر معاملة';
    case CustomerSortType.highestDebt:
      return 'الأكبر مبلغاً';
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SyncService _syncService = SyncService();
  
  @override
  void initState() {
    super.initState();
    // Use Future.microtask or addPostFrameCallback to ensure context is available
    // and to avoid issues with calling methods on providers too early.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppProvider>();
      // تأكد من تصفية البحث الفارغة عند الدخول للشاشة لتجنب بقاء فلتر قديم
      app.setSearchQuery('');
      app.initialize();
    });
  }
  
  /// عرض حوار المزامنة المحسّن
  Future<void> _showSyncDialog(BuildContext context) async {
    // التحقق من إعداد رسالة التأكيد
    final settings = await SettingsManager.getAppSettings();
    
    if (settings.syncShowConfirmation) {
      // الحصول على ملخص العمليات المعلقة
      final summary = await _syncService.getPendingSyncSummary();
      
      // عرض رسالة التأكيد
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                settings.syncFullTransferMode ? Icons.cloud_upload : Icons.sync,
                color: settings.syncFullTransferMode ? Colors.orange : Colors.blue,
              ),
              const SizedBox(width: 8),
              Text(settings.syncFullTransferMode ? 'نقل كامل' : 'مزامنة'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (settings.syncFullTransferMode) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'وضع النقل الكامل مفعل!\nسيتم رفع جميع البيانات.',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const Text('ملخص العمليات المعلقة:'),
              const SizedBox(height: 8),
              Text('📊 إجمالي: ${summary['total']} عملية'),
              if (summary['customers']! > 0)
                Text('👥 عملاء: ${summary['customers']} عملية'),
              if (summary['transactions']! > 0)
                Text('💰 معاملات: ${summary['transactions']} عملية'),
              const SizedBox(height: 16),
              const Text('هل تريد المتابعة؟'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: settings.syncFullTransferMode ? Colors.orange : Colors.blue,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                settings.syncFullTransferMode ? 'بدء النقل' : 'بدء المزامنة',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
    }
    
    // متغيرات الحالة
    final ValueNotifier<String> statusMessage = ValueNotifier('جاري التحضير...');
    final ValueNotifier<bool> isComplete = ValueNotifier(false);
    final ValueNotifier<SyncResult?> result = ValueNotifier(null);
    
    // الاستماع لتحديثات الحالة
    final subscription = _syncService.messageStream.listen((msg) {
      if (!isComplete.value) {
        statusMessage.value = msg;
      }
    });
    
    // عرض الـ Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ValueListenableBuilder<bool>(
        valueListenable: isComplete,
        builder: (context, complete, _) => ValueListenableBuilder<String>(
          valueListenable: statusMessage,
          builder: (context, message, _) => ValueListenableBuilder<SyncResult?>(
            valueListenable: result,
            builder: (context, syncResult, _) => AlertDialog(
              title: Row(
                children: [
                  if (!complete) ...[
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                  ] else ...[
                    Icon(
                      syncResult?.success == true ? Icons.check_circle : Icons.error,
                      color: syncResult?.success == true ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      complete 
                        ? (syncResult?.success == true ? 'تمت المزامنة' : 'فشلت المزامنة')
                        : 'جاري المزامنة...',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message),
                    if (complete && syncResult != null) ...[
                      const SizedBox(height: 16),
                      if (syncResult.success) ...[
                        Text('📥 تنزيل: ${syncResult.downloaded} عملية'),
                        Text('📤 رفع: ${syncResult.uploaded} عملية'),
                        if (syncResult.applied > 0)
                          Text('✅ تطبيق: ${syncResult.applied} عملية'),
                        Text('⏱️ المدة: ${syncResult.duration.inSeconds} ثانية'),
                        // عرض العمليات الفاشلة إن وجدت
                        if (syncResult.hasFailedOperations) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 8),
                          Text(
                            '⚠️ عمليات فاشلة (${syncResult.failed}):',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...syncResult.failedOperations.map((op) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.person, size: 16, color: Colors.orange),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        op.customerName,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${op.operationType} - ',
                                      style: TextStyle(
                                        color: op.operationType.contains('تسديد') 
                                            ? Colors.green 
                                            : Colors.red,
                                      ),
                                    ),
                                    Text(
                                      '${op.amount.abs().toStringAsFixed(0)} دينار',
                                      style: const TextStyle(fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '📅 ${op.date}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ],
                      ] else ...[
                        Text('❌ ${syncResult.error ?? syncResult.message}',
                          style: const TextStyle(color: Colors.red)),
                      ],
                    ],
                  ],
                ),
              ),
              actions: complete ? [
                TextButton(
                  onPressed: () {
                    subscription.cancel();
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('إغلاق'),
                ),
              ] : null,
            ),
          ),
        ),
      ),
    );
    
    // تنفيذ المزامنة
    SyncResult syncResult;
    try {
      await _syncService.initialize();
      
      // 🔒 إعداد callback للمعاملات الكبيرة
      _syncService.onLargeTransactionsDetected = (largeTransactions) async {
        // عرض حوار تأكيد للمعاملات الكبيرة
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 28),
                SizedBox(width: 8),
                Text('معاملات كبيرة'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تم اكتشاف ${largeTransactions.length} معاملة كبيرة (أكثر من 10 مليون):',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...largeTransactions.take(5).map((tx) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      color: Colors.orange[50],
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('👤 ${tx.customerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('💰 ${tx.transactionType}: ${NumberFormat('#,###').format(tx.amount.abs())} د.ع'),
                            Text('📅 ${tx.date}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  )),
                  if (largeTransactions.length > 5)
                    Text('... و ${largeTransactions.length - 5} معاملات أخرى', 
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(height: 12),
                  const Text('هل تريد قبول هذه المعاملات؟'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('رفض', style: TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('قبول', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        return confirmed ?? false;
      };
      
      // 🔍 إعداد callback للتحقق بعد المزامنة
      _syncService.onVerificationComplete = (verificationResult) {
        if (!verificationResult.isHealthy && context.mounted) {
          // عرض تحذير للمستخدم
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ وُجدت ${verificationResult.customersWithIssues} مشكلة في الأرصدة - راجع الإعدادات للإصلاح',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'التفاصيل',
                textColor: Colors.white,
                onPressed: () {
                  // عرض تفاصيل المشاكل
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange),
                          SizedBox(width: 8),
                          Text('مشاكل في الأرصدة'),
                        ],
                      ),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('تم فحص ${verificationResult.customersChecked} عميل'),
                            Text('وُجدت ${verificationResult.customersWithIssues} مشكلة:'),
                            const SizedBox(height: 12),
                            ...verificationResult.issues.take(10).map((issue) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Card(
                                color: Colors.red[50],
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('👤 ${issue.customerName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      Text('📊 مسجل: ${NumberFormat('#,###').format(issue.recordedBalance)}'),
                                      Text('📊 محسوب: ${NumberFormat('#,###').format(issue.calculatedBalance)}'),
                                      Text('⚠️ فرق: ${NumberFormat('#,###').format(issue.difference)}', 
                                        style: const TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ),
                            )),
                            const SizedBox(height: 12),
                            const Text(
                              'للإصلاح: اذهب للإعدادات ← أدوات الحماية ← فحص شامل',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('إغلاق'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        }
      };
      
      syncResult = await _syncService.sync();
    } catch (e) {
      syncResult = SyncResult(
        success: false,
        message: 'حدث خطأ',
        error: e.toString(),
      );
    }
    
    // تحديث الحالة - سيتم تحديث الـ Dialog تلقائياً
    result.value = syncResult;
    isComplete.value = true;
    
    // تحديث البيانات إذا نجحت المزامنة
    if (syncResult.success && context.mounted) {
      final app = context.read<AppProvider>();
      await app.initialize(); // إعادة تحميل البيانات
    }
  }

  // Helper to format currency consistently
  String formatCurrency(num value) {
    return NumberFormat('0.00', 'en_US')
        .format(value); // Always two decimal places
  }

  @override
  Widget build(BuildContext context) {
    // Define the consistent theme colors for the screen
    final Color primaryColor = const Color(0xFF3F51B5); // Indigo 700
    final Color accentColor =
        const Color(0xFF8C9EFF); // Light Indigo Accent (Indigo A200)
    final Color textColor =
        const Color(0xFF212121); // Dark grey for general text
    final Color lightBackgroundColor =
        const Color(0xFFF8F8F8); // Very light grey for text field fill
    final Color successColor =
        Colors.green[600]!; // Green for success messages/positive debt
    final Color errorColor =
        Colors.red[700]!; // Red for error messages/negative debt

    return Theme(
      data: ThemeData(
        // Define color scheme for light theme
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white, // Text/icons on primary color
          secondary: accentColor,
          onSecondary: Colors.black, // Text/icons on secondary color
          surface: Colors.white, // Card/sheet background
          onSurface: textColor, // Text/icons on surface
          background: Colors.white, // Scaffold background
          onBackground: textColor, // Text/icons on background
          error: errorColor,
          onError: Colors.white, // Text/icons on error color
          tertiary: successColor, // Custom color for success, used in SnackBars
        ),
        // Define typography (font family and text styles)
        fontFamily: 'Roboto', // Modern, clean font
        textTheme: TextTheme(
          titleLarge: TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.bold,
              color: Colors.white), // AppBar title
          titleMedium: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: textColor), // Section titles
          bodyLarge:
              TextStyle(fontSize: 16.0, color: textColor), // General body text
          bodyMedium:
              TextStyle(fontSize: 14.0, color: textColor), // Smaller body text
          labelLarge: TextStyle(
              fontSize: 16.0,
              color: Colors.white,
              fontWeight: FontWeight.w600), // Button text
          labelMedium: TextStyle(
              fontSize: 14.0, color: Colors.grey[600]), // Input field labels
          bodySmall: TextStyle(
              fontSize: 12.0, color: Colors.grey[700]), // Hint text / captions
        ),
        // Define input field decoration theme
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            // Default border style
            borderRadius: BorderRadius.circular(10.0), // Rounded corners
            borderSide:
                BorderSide(color: Colors.grey[400]!), // Light grey border
          ),
          enabledBorder: OutlineInputBorder(
            // Border when enabled and not focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder(
            // Border when focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
                color: primaryColor, width: 2.0), // Primary color, thicker
          ),
          errorBorder: OutlineInputBorder(
            // Border when in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
                color: errorColor, width: 2.0), // Error color, thicker
          ),
          focusedErrorBorder: OutlineInputBorder(
            // Border when focused and in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          labelStyle: TextStyle(
              color: Colors.grey[700], fontSize: 15.0), // Label text style
          hintStyle: TextStyle(
              color: Colors.grey[500], fontSize: 14.0), // Hint text style
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16.0, horizontal: 16.0), // Inner padding
          filled: true, // Enable fill color
          fillColor: lightBackgroundColor, // Light background for fields
        ),
        // Define AppBar theme
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor, // AppBar background color
          foregroundColor: Colors.white, // AppBar text/icon color
          centerTitle: true, // Center title
          elevation: 4, // Shadow elevation
          titleTextStyle: TextStyle(
            // Title text style (inherits from TextTheme.titleLarge)
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        // Define Card theme
        cardTheme: CardThemeData(
          elevation: 3, // Consistent shadow for cards
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(12.0), // Rounded corners for cards
          ),
          margin: EdgeInsets
              .zero, // Reset default card margin to manage it manually
        ),
        // Define ListTile theme
        listTileTheme: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          tileColor: Colors.transparent, // Default transparent
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
        // Define ElevatedButton theme (for Google Drive sign in)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor, // Default button color
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0)), // Slightly rounded
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            elevation: 2,
            textStyle: TextStyle(fontSize: 15.0, fontWeight: FontWeight.w500),
          ),
        ),
        // Define TextButton theme (for dialogs)
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        // Define IconButton theme
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
        // Define FloatingActionButton theme
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(12.0)), // Consistent rounded shape
          elevation: 6, // Slightly higher elevation for FABs
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('دفتر ديوني'),
          actions: [
            Consumer<AppProvider>(
              builder: (context, provider, child) {
                return Row(
                  children: [
                    if (!provider.isDriveSignedInSync)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: ElevatedButton.icon(
                          icon: const FaIcon(
                            FontAwesomeIcons.google,
                            color: Colors.red,
                            size: 18,
                          ),
                          label: Text(
                            'تسجيل الدخول',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surface, // White background
                            elevation: 2,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  8), // Slightly more rounded
                            ),
                          ),
                          onPressed: () async {
                            try {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'سيتم فتح نافذة تسجيل الدخول إلى Google'),
                                    duration: Duration(seconds: 2),
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .secondary
                                        .withOpacity(0.8),
                                  ),
                                );
                              }
                              await provider.signInToDrive();
                              await provider
                                  .isDriveSignedIn(); // Refresh sign-in status
                              setState(() {}); // Trigger rebuild
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'تم تسجيل الدخول بنجاح! يمكنك الآن رفع التقارير إلى Google Drive'),
                                    backgroundColor:
                                        Theme.of(context).colorScheme.tertiary,
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(e.toString()),
                                    backgroundColor:
                                        Theme.of(context).colorScheme.error,
                                  ),
                                );
                              }
                            }
                          },
                        ),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.logout,
                            color: Colors.white), // Themed icon
                        tooltip: 'تسجيل الخروج من Google Drive',
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('تسجيل الخروج',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              content: Text(
                                  'هل أنت متأكد من تسجيل الخروج من Google Drive؟',
                                  style: Theme.of(context).textTheme.bodyLarge),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text('إلغاء'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text('تسجيل الخروج'),
                                ),
                              ],
                            ),
                          );

                          if (confirmed == true) {
                            await provider.signOutFromDrive();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('تم تسجيل الخروج من Google Drive'),
                                  backgroundColor:
                                      Theme.of(context).colorScheme.secondary,
                                ),
                              );
                            }
                            setState(() {}); // Trigger rebuild
                          }
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.cloud_upload,
                          color: Colors.white), // Themed icon
                      tooltip: provider.isDriveSignedInSync
                          ? 'رفع سجل الديون إلى Google Drive'
                          : 'يجب تسجيل الدخول أولاً',
                      onPressed: provider.isDriveSignedInSync
                          ? () async {
                              try {
                                await provider.uploadDebtRecord();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'تم رفع سجل الديون بنجاح إلى Google Drive'),
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .tertiary,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(e.toString()),
                                      backgroundColor:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  );
                                }
                              }
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.receipt_long,
                          color: Colors.white), // Themed icon
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SavedInvoicesScreen(),
                          ),
                        );
                      },
                      tooltip: 'الفواتير المحفوظة',
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat_bubble_outline,
                          color: Colors.white), // AI Chat icon
                      onPressed: () {
                        Navigator.pushNamed(context, '/ai_chat');
                      },
                      tooltip: 'الدردشة مع الذكاء الاصطناعي',
                    ),
                    // زر ترتيب العملاء
                    PopupMenuButton<CustomerSortType>(
                      icon: const Icon(Icons.sort, color: Colors.white),
                      tooltip: 'ترتيب العملاء',
                      onSelected: (CustomerSortType sortType) async {
                        await provider.setSortType(sortType);
                      },
                      itemBuilder: (BuildContext context) => [
                        PopupMenuItem<CustomerSortType>(
                          value: CustomerSortType.alphabetical,
                          child: Row(
                            children: [
                              Icon(
                                provider.currentSortType == CustomerSortType.alphabetical
                                    ? Icons.check_circle
                                    : Icons.sort_by_alpha,
                                color: provider.currentSortType == CustomerSortType.alphabetical
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              const Text('أبجدي (الافتراضي)'),
                            ],
                          ),
                        ),
                        PopupMenuItem<CustomerSortType>(
                          value: CustomerSortType.lastDebtAdded,
                          child: Row(
                            children: [
                              Icon(
                                provider.currentSortType == CustomerSortType.lastDebtAdded
                                    ? Icons.check_circle
                                    : Icons.add_circle_outline,
                                color: provider.currentSortType == CustomerSortType.lastDebtAdded
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              const SizedBox(width: 8),
                              const Text('آخر إضافة دين'),
                            ],
                          ),
                        ),
                        PopupMenuItem<CustomerSortType>(
                          value: CustomerSortType.lastPayment,
                          child: Row(
                            children: [
                              Icon(
                                provider.currentSortType == CustomerSortType.lastPayment
                                    ? Icons.check_circle
                                    : Icons.payment,
                                color: provider.currentSortType == CustomerSortType.lastPayment
                                    ? Colors.green
                                    : Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              const Text('آخر تسديد'),
                            ],
                          ),
                        ),
                        PopupMenuItem<CustomerSortType>(
                          value: CustomerSortType.lastTransaction,
                          child: Row(
                            children: [
                              Icon(
                                provider.currentSortType == CustomerSortType.lastTransaction
                                    ? Icons.check_circle
                                    : Icons.history,
                                color: provider.currentSortType == CustomerSortType.lastTransaction
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              const Text('آخر معاملة'),
                            ],
                          ),
                        ),
                        PopupMenuItem<CustomerSortType>(
                          value: CustomerSortType.highestDebt,
                          child: Row(
                            children: [
                              Icon(
                                provider.currentSortType == CustomerSortType.highestDebt
                                    ? Icons.check_circle
                                    : Icons.trending_up,
                                color: provider.currentSortType == CustomerSortType.highestDebt
                                    ? Colors.green
                                    : Colors.purple,
                              ),
                              const SizedBox(width: 8),
                              const Text('الأكبر مبلغاً'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        body: Consumer<AppProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(
                  child: CircularProgressIndicator(
                color: Color(0xFF3F51B5), // Explicitly set color
              ));
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24.0), // Consistent padding
                  child: TextFormField(
                    // Changed to TextFormField for consistent styling
                    decoration: InputDecoration(
                      hintText: 'ابحث عن عميل...',
                      prefixIcon: Icon(Icons.search,
                          color: Theme.of(context)
                              .colorScheme
                              .primary), // Themed icon
                      // Inherits other styles from inputDecorationTheme
                    ),
                    onChanged: provider.setSearchQuery,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge, // Themed text style
                  ),
                ),
                Expanded(
                  child: provider.customers.isEmpty
                      ? Center(
                          child: Text(
                            'لا يوجد عملاء',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                    color:
                                        Colors.grey[600]), // Themed text style
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 12.0), // Padding for the list itself
                          itemCount: provider.customers.length,
                          itemBuilder: (context, index) {
                            final customer = provider.customers[index];
                            return CustomerListTile(customer: customer);
                          },
                        ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'add_customer',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddCustomerScreen(),
                  ),
                );
              },
              tooltip: 'إضافة عميل جديد',
              child: const Icon(Icons.person_add_alt_1), // Modern icon
            ),
            const SizedBox(width: 16), // Increased spacing between FABs
            FloatingActionButton(
              heroTag: 'main_debt',
              onPressed: () {
                // Already on main screen, maybe refresh or show a message
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('أنت بالفعل في الشاشة الرئيسية (سجل الديون).'),
                      backgroundColor: Theme.of(context).colorScheme.secondary),
                );
              },
              tooltip: 'سجل الديون',
              child: const Icon(Icons.book_outlined), // Modern icon
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'add_product',
              onPressed: () {
                Navigator.pushNamed(context, '/add_product');
              },
              tooltip: 'إدخال بضاعة',
              child: const Icon(Icons.inventory_2_outlined), // Modern icon
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'installers',
              onPressed: () {
                Navigator.pushNamed(context, '/installers');
              },
              tooltip: 'المؤسسين',
              child: const Icon(Icons.engineering_outlined), // Modern icon
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'create_invoice',
              onPressed: () {
                Navigator.pushNamed(context, '/create_invoice');
              },
              tooltip: 'إنشاء قائمة',
              child: const Icon(Icons.playlist_add_check), // Modern icon
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'edit_invoices',
              onPressed: () {
                Navigator.pushNamed(context, '/edit_invoices');
              },
              tooltip: 'تعديل القوائم',
              child: const Icon(Icons.receipt_long), // Modern icon
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'edit_products',
              onPressed: () {
                Navigator.pushNamed(context, '/edit_products');
              },
              tooltip: 'تعديل البضاعة',
              child: const Icon(Icons.edit_note), // Modern icon
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'sync_debts',
              onPressed: () => _showSyncDialog(context),
              tooltip: 'مزامنة',
              child: const Icon(Icons.sync),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerListTile extends StatelessWidget {
  final Customer customer;

  const CustomerListTile({
    super.key,
    required this.customer,
  });

  // Helper to format currency consistently
  String _formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  @override
  Widget build(BuildContext context) {
    // Determine color based on debt status
    final debtColor = (customer.currentTotalDebt ?? 0.0) > 0
        ? Theme.of(context).colorScheme.error // Red for debt
        : Theme.of(context)
            .colorScheme
            .tertiary; // Green for no debt/positive balance

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0), // Spacing between cards
      elevation: 2, // Consistent card elevation
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 20.0, vertical: 12.0), // Increased internal padding
        leading: CircleAvatar(
          backgroundColor:
              debtColor.withOpacity(0.1), // Lighter background for avatar
          child: Icon(
            (customer.currentTotalDebt ?? 0.0) > 0
                ? Icons.arrow_downward
                : Icons.check_circle_outline, // Dynamic icon based on debt
            color: debtColor, // Themed icon color
            size: 28, // Larger icon
          ),
        ),
        title: Text(
          customer.name,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
        ),
        subtitle: Text(
          customer.phone ?? 'لا يوجد رقم هاتف',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Colors.grey[700]), // Themed text style
        ),
        trailing: Text(
          '${_formatCurrency(customer.currentTotalDebt ?? 0.0)} دينار', // Formatted currency
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: debtColor,
                fontWeight: FontWeight.bold,
              ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomerDetailsScreen(customer: customer),
            ),
          ).then((_) {
            // After returning: clear search filter and refresh full list
            final app = Provider.of<AppProvider>(context, listen: false);
            app.setSearchQuery('');
            app.initialize();
          });
        },
      ),
    );
  }
}
