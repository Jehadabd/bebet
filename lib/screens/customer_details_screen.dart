// screens/customer_details_screen.dart
// screens/customer_details_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import 'add_transaction_screen.dart';
import 'create_invoice_screen.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart'; // Assume PdfService exists
import '../services/receipt_voucher_pdf_service.dart';
import '../models/account_statement_item.dart'; // Assume AccountStatementItem exists
import 'package:printing/printing.dart'; // Assume this is for PDF preview on non-Windows
import 'dart:io';
// import 'package:path_provider/path_provider.dart'; // Not directly used in final snippet, but for file operations
// import 'package:share_plus/share_plus.dart'; // Not directly used here
import 'package:intl/intl.dart';
import 'package:process/process.dart'; // For Process.start on Windows
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'audit_log_screen.dart';
import 'commercial_statement_screen.dart';
import '../services/commercial_statement_service.dart';
import '../services/password_service.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/firebase_sync/firebase_sync_service.dart';

class CustomerDetailsScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailsScreen({
    super.key,
    required this.customer,
  });

  @override
  State<CustomerDetailsScreen> createState() => _CustomerDetailsScreenState();
}

class _CustomerDetailsScreenState extends State<CustomerDetailsScreen> {
  AudioPlayer? _audioPlayer;
  String? _currentlyPlayingPath;
  bool _isPlaying = false;
  bool _isLoading = false;
  
  // 📊 المعاملات المجمعة (فواتير مجمعة + معاملات يدوية)
  List<GroupedTransactionItem> _groupedTransactions = [];
  bool _useGroupedView = true; // استخدام العرض المجمع افتراضياً
  
  // 🔄 الاستماع لإشعارات المزامنة الفورية
  StreamSubscription<Map<String, dynamic>>? _transactionSubscription;

  @override
  void initState() {
    super.initState();
    // This is good practice for initial data loading from a provider
    Future.microtask(() async {
      await context.read<AppProvider>().selectCustomer(widget.customer);
      await _loadTransactions();
      // 🔒 التحقق التلقائي من الرصيد عند فتح الصفحة
      await _verifyAndAutoFixBalance();
    });
    
    // 🔄 الاستماع لإشعارات المعاملات الجديدة من Firebase
    _setupFirebaseSyncListener();
  }
  
  /// 🔄 إعداد الاستماع لإشعارات المزامنة الفورية
  void _setupFirebaseSyncListener() {
    final firebaseSync = FirebaseSyncService();
    
    _transactionSubscription = firebaseSync.onTransactionReceived.listen((data) {
      // التحقق من أن المعاملة تخص هذا العميل
      final customerId = data['customerId'] as int?;
      
      if (customerId == widget.customer.id && mounted) {
        print('🔄 تحديث فوري: معاملة جديدة للعميل ${widget.customer.name}');
        
        // إعادة تحميل البيانات
        _loadTransactions();
        context.read<AppProvider>().selectCustomer(widget.customer);
        
        // إظهار إشعار صغير
        final amountChanged = data['amountChanged'] as double? ?? 0;
        final typeLabel = amountChanged >= 0 ? 'إضافة دين' : 'تسديد';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.sync, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🔄 $typeLabel جديد: ${amountChanged.abs().toStringAsFixed(0)} (من جهاز آخر)',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue.shade700,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }
  
  Future<void> _loadTransactions() async {
    if (!mounted) return;
    if (widget.customer.id != null) {
      await context.read<AppProvider>().loadCustomerTransactions(widget.customer.id!);
      
      // تحميل المعاملات المجمعة
      try {
        final db = DatabaseService();
        final grouped = await db.getGroupedCustomerTransactions(widget.customer.id!);
        if (mounted) {
          setState(() {
            _groupedTransactions = grouped;
          });
        }
      } catch (e) {
        debugPrint('خطأ في تحميل المعاملات المجمعة: $e');
      }
    }
  }

  /// 🔒 التحقق التلقائي من رصيد العميل وإصلاح الفروقات البسيطة
  /// هذه الدالة تضمن أن الرصيد المعروض = مجموع المعاملات بنسبة 99.9%
  Future<void> _verifyAndAutoFixBalance() async {
    if (!mounted || widget.customer.id == null) return;
    
    try {
      final db = DatabaseService();
      final result = await db.getVerifiedCustomerBalance(widget.customer.id!);
      
      if (result.wasAutoFixed && mounted) {
        // تم إصلاح فرق بسيط تلقائياً - إعادة تحميل البيانات
        await context.read<AppProvider>().selectCustomer(widget.customer);
        await _loadTransactions();
        
        // إظهار رسالة صغيرة (اختياري - يمكن إزالتها للإصلاح الصامت)
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(
        //     content: Text(result.autoFixNote ?? 'تم تصحيح الرصيد تلقائياً'),
        //     duration: const Duration(seconds: 2),
        //     backgroundColor: Colors.green,
        //   ),
        // );
      }
    } catch (e) {
      // تجاهل الأخطاء - لا نريد إيقاف التطبيق
      debugPrint('خطأ في التحقق التلقائي من الرصيد: $e');
    }
  }

  @override
  void dispose() {
    _transactionSubscription?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }

  // Helper to format numbers with thousand separators (no decimals)
  String formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  // تشغيل الملاحظة الصوتية (audioPath قد يكون اسم ملف فقط)
  Future<void> _playAudioNote(String audioPath) async {
    try {
      // إيقاف التشغيل الحالي إذا كان هناك تشغيل
      if (_isPlaying) {
        await _stopAudio();
      }

      // حل المسار إلى المسار المطلق ضمن مجلد التطبيق
      final resolvedPath = await DatabaseService().resolveStoredAudioPath(audioPath);
      if (File(resolvedPath).existsSync()) {
        _audioPlayer = AudioPlayer();
        _currentlyPlayingPath = resolvedPath;
        
        await _audioPlayer!.play(DeviceFileSource(resolvedPath));
        
        setState(() {
          _isPlaying = true;
        });

        // الاستماع لانتهاء التشغيل
        _audioPlayer!.onPlayerComplete.listen((_) {
          setState(() {
            _isPlaying = false;
            _currentlyPlayingPath = null;
          });
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ملف الصوت غير موجود')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تشغيل الصوت: $e')),
      );
    }
  }

  // إيقاف تشغيل الملاحظة الصوتية
  Future<void> _stopAudio() async {
    if (_audioPlayer != null) {
      await _audioPlayer!.stop();
      await _audioPlayer!.dispose();
      _audioPlayer = null;
    }
    
    setState(() {
      _isPlaying = false;
      _currentlyPlayingPath = null;
    });
  }

  // دالة تنسيق رقم الهاتف للصيغة الدولية
  String _normalizePhoneNumber(String phone) {
    // إزالة كل شيء غير الأرقام أو +
    String cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    
    // إزالة علامة + إذا كانت موجودة
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    }
    
    // إذا بدأ بصفر محلي، استبدله برمز الدولة العراقية
    if (cleaned.startsWith('0')) {
      cleaned = '964' + cleaned.substring(1);
    }
    
    // إذا لم يبدأ برمز الدولة، أضف رمز العراق
    if (!cleaned.startsWith('964')) {
      cleaned = '964' + cleaned;
    }
    
    return cleaned;
  }

  // دالة بناء رسالة الدين
  String _buildDebtMessage() {
    final customer = widget.customer;
    final provider = context.read<AppProvider>();
    final currentBalance = provider.selectedCustomer?.currentTotalDebt ?? 0.0;

    // تنسيق المبلغ
    final amountFormatter = NumberFormat('#,##0', 'en_US');
    final formattedAmount = amountFormatter.format(currentBalance.abs());

    // تحديد تاريخ آخر تحديث من آخر معاملة، وإن لم تتوفر فآخر تعديل للعميل
    final transactions = provider.customerTransactions;
    DateTime? lastTransactionDate;
    for (final t in transactions) {
      if (t.transactionDate != null) {
        if (lastTransactionDate == null || t.transactionDate!.isAfter(lastTransactionDate)) {
          lastTransactionDate = t.transactionDate;
        }
      }
    }
    final DateTime lastUpdate = lastTransactionDate ?? customer.lastModifiedAt;
    final dateFormatter = DateFormat('yyyy-MM-dd', 'en_US');
    final formattedLastUpdate = dateFormatter.format(lastUpdate);

    // نص العنوان المطلوب
    const String storeAddress = 'موقعنا : الموصل - القيارة - الجدعة - الشارع العام- مقابل برج اسياسيل\nمجمع الناصر لبيع المواد الكهربائية والصحية';

    // بناء الرسالة
    final StringBuffer message = StringBuffer();
    message.writeln('السلام عليكم');
    message.writeln('عزيزي ${customer.name}،');
    message.writeln();

    if (currentBalance > 0) {
      message.writeln('لديك دين بقيمة $formattedAmount دينار.');
    } else if (currentBalance < 0) {
      message.writeln('لديك رصيد ائتماني بقيمة $formattedAmount دينار.');
    } else {
      message.writeln('رصيدك الحالي متوازن (صفر دينار).');
    }

    message.writeln('تاريخ آخر تحديث: $formattedLastUpdate');
    message.writeln('الرجاء التواصل معنا لمراجعه الحساب');
    message.writeln(storeAddress);
    message.writeln('مع الشكر والتقدير');

    return message.toString();
  }

  // دالة إرسال رسالة واتساب
  Future<void> _sendWhatsAppMessage() async {
    final provider = context.read<AppProvider>();
    final customer = provider.selectedCustomer ?? widget.customer;
    
    // التحقق من وجود رقم هاتف
    if (customer.phone == null || customer.phone!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد رقم هاتف مسجل للعميل'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // إظهار مؤشر تحميل
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              const SizedBox(width: 16),
              const Text('جاري فتح واتساب...'),
            ],
          ),
        ),
      );
    }

    try {
      // تنسيق رقم الهاتف
      final phoneNumber = _normalizePhoneNumber(customer.phone!);
      
      // بناء رسالة الدين
      final message = _buildDebtMessage();
      
      // انسخ الرسالة للحافظة مسبقاً كخطة احتياطية في حال لم تُرفق تلقائياً
      await Clipboard.setData(ClipboardData(text: message));

      // ترميز الرسالة للرابط
      final encodedMessage = Uri.encodeComponent(message);

      // إنشاء روابط واتساب بحسب المنصة مع تسلسل محاولات قوي
      final Uri androidDeepLink = Uri.parse('whatsapp://send?phone=$phoneNumber&text=$encodedMessage');
      final Uri apiLink = Uri.parse('https://api.whatsapp.com/send?phone=$phoneNumber&text=$encodedMessage');
      final Uri waMeLink = Uri.parse('https://wa.me/$phoneNumber?text=$encodedMessage');
      final Uri webLink = Uri.parse('https://web.whatsapp.com/send?phone=$phoneNumber&text=$encodedMessage');

      final List<Uri> attempts;
      if (Platform.isAndroid) {
        attempts = [androidDeepLink, apiLink, waMeLink];
      } else if (Platform.isIOS) {
        attempts = [waMeLink, apiLink];
      } else {
        // لسطح المكتب (ويندوز/ماك/لينكس): أعطِ أولوية لتطبيق سطح المكتب إن أمكن
        attempts = [androidDeepLink, waMeLink, apiLink, webLink];
      }

      bool success = false;

      // محاولة خاصة بويندوز لفتح بروتوكول whatsapp:// مباشرة عبر start
      if (Platform.isWindows && !success) {
        try {
          final desktopProtocol = 'whatsapp://send?phone=$phoneNumber&text=$encodedMessage';
          await Process.start('cmd', ['/c', 'start', '""', desktopProtocol]);
          success = true;
        } catch (_) {
          // تجاهل واستمر بالمحاولات الأخرى
        }
      }
      for (final uri in attempts) {
        try {
          if (await canLaunchUrl(uri)) {
            final opened = await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
            );
            if (opened) {
              success = true;
              break;
            }
          }
        } catch (e) {
          // جرّب الرابط التالي في حال الفشل
          continue;
        }
      }
      
      // إغلاق مؤشر التحميل
      if (mounted) {
        Navigator.pop(context);
      }
      
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم فتح واتساب وتهيئة المحادثة. إذا لم تظهر الرسالة، اضغط Ctrl+V للصقها (تم نسخها).'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        // فشل فتح أي رابط — الرسالة موجودة في الحافظة بالفعل
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('تعذر فتح واتساب'),
              content: const Text('لم نتمكن من فتح محادثة واتساب. تم نسخ الرسالة إلى الحافظة، افتح واتساب والصقها يدوياً.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسناً'),
                ),
              ],
            ),
          );
        }
      }
      
    } catch (e) {
      // إغلاق مؤشر التحميل في حالة الخطأ
      if (mounted) {
        Navigator.pop(context);
      }

      // الرسالة منسوخة أصلاً للحافظة
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: ${e.toString()}. تم نسخ الرسالة للحافظة.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
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
        // Define TextButton theme
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor, // Primary color for text buttons
            textStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        // Define IconButton color
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.customer.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: 'تعديل معلومات العميل',
              onPressed: () async {
                final nameController = TextEditingController(text: widget.customer.name);
                final phoneController = TextEditingController(text: widget.customer.phone ?? '');
                final addressController = TextEditingController(text: widget.customer.address ?? '');
                final result = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('تعديل معلومات العميل'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: nameController,
                              decoration: const InputDecoration(labelText: 'الاسم'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: phoneController,
                              decoration: const InputDecoration(labelText: 'الهاتف'),
                              keyboardType: TextInputType.phone,
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: addressController,
                              decoration: const InputDecoration(labelText: 'العنوان'),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
                      ],
                    );
                  },
                );
                if (result == true && mounted) {
                  // تحويل رقم الهاتف إلى الصيغة الدولية تلقائياً
                  String? normalizedPhone;
                  if (phoneController.text.trim().isNotEmpty) {
                    normalizedPhone = _normalizePhoneNumber(phoneController.text.trim());
                  }
                  
                  // الحصول على البيانات المحدثة من المزود (Provider)
                  final provider = context.read<AppProvider>();
                  final currentCustomer = provider.selectedCustomer ?? widget.customer;
                  
                  final updated = currentCustomer.copyWith(
                    name: nameController.text.trim(),
                    phone: normalizedPhone,
                    address: addressController.text.trim(),
                    currentTotalDebt: currentCustomer.currentTotalDebt, // الحفاظ على قيمة الدين المحدثة
                    lastModifiedAt: DateTime.now(),
                  );
                  await provider.updateCustomer(updated);
                  
                  // تحديث الفواتير القديمة المرتبطة بهذا العميل
                  try {
                    final db = DatabaseService();
                    await db.updateOldInvoicesWithCustomerIds();
                  } catch (e) {
                    // تجاهل الخطأ
                  }
                  
                  if (mounted) {
                    String message = 'تم تحديث بيانات العميل';
                    if (normalizedPhone != null) {
                      message += '\nتم تحويل رقم الهاتف إلى: $normalizedPhone';
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.receipt_long,
                  color: Colors.white), // Color changed
              tooltip: 'كشف الحساب',
              onPressed: () => _generateAccountStatement(),
            ),
            // 📊 زر كشف الحساب التجاري
            IconButton(
              icon: const Icon(Icons.analytics, color: Colors.white),
              tooltip: 'كشف الحساب التجاري',
              onPressed: () => _showCommercialStatement(),
            ),
            // 📄 زر أرشيف سندات القبض
            IconButton(
              icon: const Icon(Icons.archive, color: Colors.white),
              tooltip: 'أرشيف سندات القبض',
              onPressed: () => _showReceiptVouchersArchive(),
            ),
            // 🛡️ زر فحص السلامة المالية
            IconButton(
              icon: const Icon(Icons.verified_user, color: Colors.white),
              tooltip: 'فحص السلامة المالية',
              onPressed: () => _showFinancialIntegrityReport(),
            ),
            // 📋 زر سجل التدقيق المالي
            IconButton(
              icon: const Icon(Icons.history, color: Colors.white),
              tooltip: 'سجل التدقيق المالي',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AuditLogScreen(
                      customerId: widget.customer.id,
                      customerName: widget.customer.name,
                      entityType: 'customer',
                    ),
                  ),
                );
              },
            ),
            // زر إيقاف الصوت
            if (_isPlaying)
              IconButton(
                icon: const Icon(Icons.stop,
                    color: Colors.red),
                tooltip: 'إيقاف تشغيل الصوت',
                onPressed: () async {
                  await _stopAudio();
                },
              ),
            // زر إرسال واتساب
            IconButton(
              icon: const Icon(Icons.message, color: Colors.white),
              tooltip: 'إرسال رسالة واتساب',
              onPressed: _sendWhatsAppMessage,
            ),
            IconButton(
              icon: const Icon(Icons.delete,
                  color: Colors.white), // Color changed
              tooltip: 'حذف العميل', // Added tooltip
              onPressed: () async {
                final provider = context.read<AppProvider>();
                final customer = provider.selectedCustomer ?? widget.customer;
                final hasDebt = (customer.currentTotalDebt ?? 0) > 0.01;
                
                if (hasDebt) {
                  // العميل عليه دين - عرض تحذير خاص
                  final warningConfirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 28),
                          const SizedBox(width: 8),
                          const Text('تنبيه!', style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'هذا العميل عليه دين بقيمة:',
                            style: TextStyle(fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red[300]!),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.monetization_on, color: Colors.red[700]),
                                const SizedBox(width: 8),
                                Text(
                                  '${NumberFormat('#,##0', 'en_US').format(customer.currentTotalDebt ?? 0)} دينار',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'هل أنت متأكد من حذف هذا العميل؟\nسيتم حذف جميع سجلات الديون والمعاملات المرتبطة به.',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text('إلغاء', style: TextStyle(color: Colors.grey[700])),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  );
                  
                  if (warningConfirmed != true || !mounted) return;
                  
                  // طلب كلمة السر
                  final passwordController = TextEditingController();
                  final passwordService = PasswordService();
                  final passwordVerified = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('أدخل كلمة السر للتأكيد', style: TextStyle(fontSize: 18)),
                      content: TextField(
                        controller: passwordController,
                        obscureText: true,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'كلمة السر',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.lock),
                        ),
                        onSubmitted: (value) async {
                          final isCorrect = await passwordService.verifyPassword(value);
                          Navigator.of(context).pop(isCorrect);
                        },
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            final isCorrect = await passwordService.verifyPassword(passwordController.text);
                            Navigator.of(context).pop(isCorrect);
                          },
                          child: const Text('تأكيد'),
                        ),
                      ],
                    ),
                  );
                  
                  if (passwordVerified != true) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('كلمة السر غير صحيحة أو تم الإلغاء'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }
                } else {
                  // العميل ليس عليه دين - تأكيد عادي
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('تأكيد الحذف',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      content: const Text(
                          'هل أنت متأكد من حذف هذا العميل؟ لا يمكن التراجع عن هذا الإجراء.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text('إلغاء',
                              style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text('حذف',
                              style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirmed != true || !mounted) return;
                }
                
                // تنفيذ الحذف
                try {
                  await provider.deleteCustomer(widget.customer.id!);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('تم حذف العميل ${widget.customer.name} بنجاح!'),
                          backgroundColor: Theme.of(context).colorScheme.tertiary),
                    );
                    Navigator.pop(context);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(e.toString().replaceAll('Exception: ', '')),
                          backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          ],
        ),
        body: Consumer<AppProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(
                  child: CircularProgressIndicator(
                color: Color(0xFF3F51B5), // Explicitly set color for indicator
              ));
            }

            final customer = provider.selectedCustomer ?? widget.customer;
            final transactions = provider.customerTransactions;

            return Column(
              children: [
                // التحقق من تطابق الرصيد وعرض تنبيه
                Builder(
                  builder: (context) {
                    double calculatedBalance = 0.0;
                    for (var t in transactions) {
                      calculatedBalance += t.amountChanged;
                    }
                    final diff = (calculatedBalance - (customer.currentTotalDebt ?? 0.0)).abs();
                    
                    if (diff > 0.01) {
                      return Container(
                        margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          border: Border.all(color: Colors.orange),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'تنبيه: يوجد اختلاف بين رصيد العميل ومجموع المعاملات.\nالرصيد المسجل: ${formatCurrency(customer.currentTotalDebt ?? 0)}\nالمجموع الفعلي: ${formatCurrency(calculatedBalance)}',
                                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () async {
                                  // Dialog 1: Check if accounts are correct
                                  final result = await showDialog<String>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('تحقق من الحسابات'),
                                      content: Text(
                                        'يوجد اختلاف بين الرصيد المسجل (${formatCurrency(customer.currentTotalDebt ?? 0)}) ومجموع المعاملات (${formatCurrency(calculatedBalance)}).\n\nهل أنت متأكد من أن الرصيد المسجل هو الصحيح؟'
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, 'no'),
                                          child: const Text('لا'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, 'yes'),
                                          child: const Text('نعم'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (!mounted) return;

                                  if (result == 'yes') {
                                    // User says Recorded Balance is correct -> Add correction transaction
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('إضافة معاملة تصحيحية'),
                                        content: Text(
                                          'سيتم إضافة معاملة بقيمة الفرق (${formatCurrency(customer.currentTotalDebt! - calculatedBalance)}) ليصبح مجموع المعاملات مطابقاً للرصيد المسجل.\n\nهل أنت متأكد؟'
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('نعم، أضف المعاملة')),
                                        ],
                                      ),
                                    );

                                    if (confirmed == true && mounted) {
                                      try {
                                        final db = DatabaseService();
                                        final diffAmount = (customer.currentTotalDebt ?? 0.0) - calculatedBalance;
                                        final targetBalance = customer.currentTotalDebt ?? 0.0;
                                        
                                        // 🔧 استخدام دالة التصحيح الخاصة التي تتجاوز التحقق الأمني
                                        await db.insertCorrectionTransaction(
                                          customerId: customer.id!,
                                          correctionAmount: diffAmount,
                                          targetBalance: targetBalance,
                                          note: 'تصحيح رصيد (رصيد افتتاحي سابق)',
                                        );
                                        
                                        // إعادة حساب تسلسل الأرصدة
                                        await db.recalculateCustomerTransactionBalances(customer.id!);
                                        
                                        // Reload customer and transactions to update UI with correct final values
                                        final provider = context.read<AppProvider>();
                                        await provider.selectCustomer(customer);
                                        await _loadTransactions();
                                        
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('تم تصحيح الرصيد بنجاح')),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('خطأ: $e')),
                                          );
                                        }
                                      }
                                    }
                                  } else if (result == 'no') {
                                    // User says Recorded Balance is WRONG -> Ask to update it to match transactions
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('تحديث الرصيد المسجل'),
                                        content: Text(
                                          'مجموع المعاملات لهذا العميل هو ${formatCurrency(calculatedBalance)}.\n\nهل تريد اعتماد هذا المجموع كرصيد نهائي (بدلاً من ${formatCurrency(customer.currentTotalDebt ?? 0)})؟'
                                        ),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('نعم، اعتمد المجموع')),
                                        ],
                                      ),
                                    );

                                    if (confirmed == true && mounted) {
                                      try {
                                        final provider = context.read<AppProvider>();
                                        final updatedCustomer = customer.copyWith(
                                          currentTotalDebt: calculatedBalance,
                                          lastModifiedAt: DateTime.now(),
                                        );
                                        
                                        await provider.updateCustomer(updatedCustomer);
                                        // Force reload to refresh UI
                                        await _loadTransactions();

                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('تم تحديث الرصيد المسجل بنجاح')),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('خطأ: $e')),
                                          );
                                        }
                                      }
                                    }
                                  }
                                },
                                icon: const Icon(Icons.build, size: 16),
                                label: const Text('حل مشكلة الاختلاف'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.orange[900],
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      // التحقق من تزامن سجل المعاملات بشكل شامل
                      // 1. التحقق من آخر معاملة
                      final lastTxBalance = transactions.isNotEmpty ? (transactions.first.newBalanceAfterTransaction ?? 0.0) : 0.0;
                      bool historyMismatch = (calculatedBalance - lastTxBalance).abs() > 0.01;
                      
                      // 2. التحقق من تسلسل جميع المعاملات (balance_before صحيح لكل معاملة)
                      if (!historyMismatch && transactions.isNotEmpty) {
                        // ترتيب المعاملات من الأقدم للأحدث
                        final sortedTx = List.of(transactions)..sort((a, b) => a.transactionDate.compareTo(b.transactionDate));
                        double runningBalance = 0.0;
                        for (final tx in sortedTx) {
                          final expectedBefore = runningBalance;
                          final actualBefore = tx.balanceBeforeTransaction ?? 0.0;
                          // إذا كان الفرق أكبر من 0.01، هناك مشكلة في التسلسل
                          if ((expectedBefore - actualBefore).abs() > 0.01) {
                            historyMismatch = true;
                            break;
                          }
                          runningBalance += tx.amountChanged;
                        }
                      }
                      
                      if (historyMismatch) {
                         return Container(
                        margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          border: Border.all(color: Colors.blue),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: Colors.blue),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'تنبيه: تسلسل الأرصدة في السجل يحتاج إلى تحديث.\nالمجموع صحيح (${formatCurrency(calculatedBalance)}) ولكن الأرصدة التراكمية غير متزامنة.',
                                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('تحديث السجل'),
                                      content: const Text(
                                        'سيتم إعادة حساب "الرصيد قبل" و "الرصيد بعد" لجميع المعاملات لضمان تسلسل صحيح.\nلن يتم تغيير المبلغ الإجمالي.\n\nهل تريد المتابعة؟'
                                      ),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('نعم، تحديث')),
                                      ],
                                    ),
                                  );
                                  
                                  if (confirmed == true && mounted) {
                                    try {
                                      final db = DatabaseService();
                                      // إعادة حساب تسلسل الأرصدة فقط
                                      await db.recalculateCustomerTransactionBalances(customer.id!);
                                      
                                      // تحديث الواجهة
                                      await _loadTransactions();
                                      
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('تم تحديث سجل المعاملات بنجاح')),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('خطأ: $e')),
                                        );
                                      }
                                    }
                                  }
                                },
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('تحديث تسلسل الأرصدة'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.blue[900],
                                  padding: EdgeInsets.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                      }
                    }
                    return const SizedBox.shrink();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(
                      24.0), // Increased padding for more spacious look
                  child: Card(
                    // Card theme applied from ThemeData
                    child: Padding(
                      padding: const EdgeInsets.all(
                          20.0), // Increased internal padding
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'معلومات العميل',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary, // Primary color for heading
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 20.0), // Increased spacing
                          _buildInfoRow('رقم الهاتف',
                              customer.phone ?? 'غير متوفر', context),
                          const SizedBox(height: 12.0),
                          _buildInfoRow(
                              'العنوان',
                              (customer.address != null && customer.address!.isNotEmpty)
                                  ? customer.address!
                                  : 'غير متوفر',
                              context),
                          const SizedBox(height: 12.0), // Increased spacing
                          _buildInfoRow(
                            'إجمالي الدين',
                            '${formatCurrency(customer.currentTotalDebt ?? 0.0)} دينار',
                            context,
                            valueColor: (customer.currentTotalDebt ?? 0.0) > 0
                                ? Theme.of(context)
                                    .colorScheme
                                    .error // Red for debt
                                : Theme.of(context)
                                    .colorScheme
                                    .tertiary, // Green for no debt
                          ),
                          if (customer.generalNote != null &&
                              customer.generalNote!.isNotEmpty) ...[
                            const SizedBox(height: 12.0), // Increased spacing
                            _buildInfoRow(
                                'ملاحظات', customer.generalNote!, context),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0), // Consistent horizontal padding
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'سجل المعاملات',
                            style:
                                Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                          ),
                          const SizedBox(width: 8),
                          // زر التبديل بين العرض المجمع والتفصيلي
                          IconButton(
                            icon: Icon(
                              _useGroupedView ? Icons.view_agenda : Icons.view_list,
                              color: Theme.of(context).colorScheme.primary,
                              size: 20,
                            ),
                            tooltip: _useGroupedView ? 'عرض تفصيلي' : 'عرض مجمع',
                            onPressed: () {
                              setState(() {
                                _useGroupedView = !_useGroupedView;
                              });
                            },
                          ),
                        ],
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AddTransactionScreen(
                                customer: customer,
                              ),
                            ),
                          );
                          // تحديث المعاملات المجمعة بعد العودة من شاشة الإضافة
                          if (mounted) {
                            await _loadTransactions();
                          }
                        },
                        icon: Icon(Icons.add_circle_outline,
                            color: Theme.of(context).colorScheme.secondary,
                            size: 28), // Themed icon
                        label: Text('إضافة معاملة',
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondary)), // Themed text
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _useGroupedView
                      // 📊 العرض المجمع الجديد
                      ? _groupedTransactions.isEmpty
                          ? Center(
                              child: Text('لا توجد معاملات',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(color: Colors.grey[600])),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                  vertical: 12.0),
                              itemCount: _groupedTransactions.length,
                              itemBuilder: (context, index) {
                                final item = _groupedTransactions[index];
                                return GroupedTransactionListTile(
                                  item: item,
                                  isPlaying: _isPlaying,
                                  currentlyPlayingPath: _currentlyPlayingPath,
                                  customerId: widget.customer.id!,
                                  onPlayStop: () async {
                                    if (item.audioNotePath != null) {
                                      if (_isPlaying && _currentlyPlayingPath == item.audioNotePath) {
                                        await _stopAudio();
                                      } else {
                                        await _playAudioNote(item.audioNotePath!);
                                      }
                                    }
                                  },
                                  onRefresh: () async {
                                    // 🔄 جلب بيانات العميل المحدّثة من قاعدة البيانات
                                    final db = DatabaseService();
                                    final updatedCustomer = await db.getCustomerById(widget.customer.id!);
                                    if (updatedCustomer != null && mounted) {
                                      await context.read<AppProvider>().selectCustomer(updatedCustomer);
                                    }
                                    await _loadTransactions();
                                  },
                                );
                              },
                            )
                      // العرض التفصيلي القديم
                      : transactions.isEmpty
                          ? Center(
                              child: Text('لا توجد معاملات',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(color: Colors.grey[600])),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24.0,
                                  vertical: 12.0), // Padding for the list
                              itemCount: transactions.length,
                              itemBuilder: (context, index) {
                                final transaction = transactions[index];
                                return TransactionListTile(
                                  transaction: transaction,
                                  isPlaying: _isPlaying,
                                  currentlyPlayingPath: _currentlyPlayingPath,
                                  audioPath: transaction.audioNotePath ?? '',
                                  onPlayStop: () async {
                                    if (_isPlaying && _currentlyPlayingPath == transaction.audioNotePath) {
                                      await _stopAudio();
                                    } else {
                                      await _playAudioNote(transaction.audioNotePath!);
                                    }
                                  },
                                  onEdit: (updated) async {
                                    try {
                                      final db = DatabaseService();
                                      final updatedCustomer = await db.updateTransaction(updated);
                                      
                                      // تحديث البيانات بعد التعديل
                                      setState(() {
                                        _isLoading = true;
                                      });
                                      await _loadTransactions();
                                      setState(() {
                                        _isLoading = false;
                                      });
                                      
                                      // تحديث المزود والواجهة بالبيانات المحدثة
                                      if (updatedCustomer != null) {
                                        await context.read<AppProvider>().selectCustomer(updatedCustomer);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('تم تحديث المعاملة. الدين الحالي: ${formatCurrency(updatedCustomer.currentTotalDebt ?? 0.0)}')),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('حدث خطأ: ${e.toString()}'),
                                            backgroundColor: Theme.of(context).colorScheme.error,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  onConvertType: (transactionId) async {
                                try {
                                  final db = DatabaseService();
                                  final updatedCustomer = await db.convertTransactionType(transactionId);
                                  // تحديث البيانات بعد التحويل
                                  setState(() {
                                    _isLoading = true;
                                  });
                                  await _loadTransactions();
                                  setState(() {
                                    _isLoading = false;
                                  });
                                  
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('تم تحويل نوع المعاملة بنجاح'),
                                        backgroundColor: Theme.of(context).colorScheme.tertiary,
                                      ),
                                    );
                                  }
                                  
                                  // حدث المزود والواجهة بالبيانات المحدثة
                                  if (updatedCustomer != null) {
                                    await context.read<AppProvider>().selectCustomer(updatedCustomer);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('تم تحديث المعاملة. الدين الحالي: ${formatCurrency(updatedCustomer.currentTotalDebt ?? 0.0)}')),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('حدث خطأ: ${e.toString()}'),
                                        backgroundColor: Theme.of(context).colorScheme.error,
                                      ),
                                    );
                                  }
                                }
                              },
                                  onRefresh: () async {
                                    // 🔄 جلب بيانات العميل المحدّثة من قاعدة البيانات
                                    final db = DatabaseService();
                                    final updatedCustomer = await db.getCustomerById(widget.customer.id!);
                                    if (updatedCustomer != null && mounted) {
                                      await context.read<AppProvider>().selectCustomer(updatedCustomer);
                                    }
                                    await _loadTransactions();
                                  },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // Modified to take BuildContext for theme access and ensure consistent text styles
  Widget _buildInfoRow(String label, String value, BuildContext context,
      {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  // 🛡️ دالة عرض تقرير السلامة المالية
  Future<void> _showFinancialIntegrityReport() async {
    try {
      // إظهار مؤشر التحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final db = DatabaseService();
      final report = await db.verifyCustomerFinancialIntegrity(widget.customer.id!);

      if (mounted) {
        Navigator.pop(context); // إغلاق مؤشر التحميل
      }

      if (!mounted) return;

      // عرض التقرير
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                report.isHealthy ? Icons.check_circle : Icons.warning,
                color: report.isHealthy ? Colors.green : Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                report.isHealthy ? 'البيانات سليمة ✅' : 'يوجد تحذيرات ⚠️',
                style: TextStyle(
                  color: report.isHealthy ? Colors.green[700] : Colors.orange[700],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // معلومات الرصيد
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📊 معلومات الرصيد:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('الرصيد المسجل: ${formatCurrency(report.recordedBalance)} دينار'),
                        Text('الرصيد المحسوب: ${formatCurrency(report.calculatedBalance)} دينار'),
                        Text('عدد المعاملات: ${report.transactionCount}'),
                        if ((report.recordedBalance - report.calculatedBalance).abs() > 0.01)
                          Text(
                            'الفرق: ${formatCurrency((report.recordedBalance - report.calculatedBalance).abs())} دينار',
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                ),
                
                // 📈 ملخص كشف الحساب التجاري
                const SizedBox(height: 12),
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📈 ملخص كشف الحساب التجاري:', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('إجمالي الفواتير: ${report.totalInvoices}'),
                                  Text('فواتير دين: ${report.debtInvoices}', style: TextStyle(color: Colors.orange[700])),
                                  Text('فواتير نقد: ${report.cashInvoices}', style: TextStyle(color: Colors.green[700])),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('مبالغ الفواتير: ${formatCurrency(report.totalInvoiceAmount)}'),
                                  Text('المدفوعات: ${formatCurrency(report.totalPayments)}', style: TextStyle(color: Colors.green[700])),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                // المشاكل
                if (report.issues.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('❌ مشاكل:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ...report.issues.map((issue) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $issue', style: const TextStyle(color: Colors.red)),
                  )),
                ],
                
                // التحذيرات
                if (report.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('⚠️ تحذيرات:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  ...report.warnings.take(5).map((warning) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $warning', style: TextStyle(color: Colors.orange[800], fontSize: 12)),
                  )),
                  if (report.warnings.length > 5)
                    Text('... و ${report.warnings.length - 5} تحذيرات أخرى', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                ],
                
                // 🔍 مشاكل الفواتير (تفصيلية)
                if (report.invoiceIssues.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.receipt_long, color: Colors.red, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              '🧾 مشاكل في الفواتير (${report.invoiceIssues.length}):',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 14),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...report.invoiceIssues.map((issue) => Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '📄 فاتورة #${issue.invoiceId} - ${issue.invoiceDate}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  // 🔧 زر الإصلاح
                                  ElevatedButton.icon(
                                    onPressed: () => _showRepairConfirmationDialog(context, issue),
                                    icon: const Icon(Icons.build, size: 14),
                                    label: const Text('إصلاح', style: TextStyle(fontSize: 11)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      minimumSize: const Size(0, 28),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                issue.description,
                                style: TextStyle(color: Colors.red[700], fontSize: 12),
                              ),
                              Text(
                                'الفرق: ${issue.difference.toStringAsFixed(2)} دينار',
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              if (issue.details.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  childrenPadding: const EdgeInsets.only(right: 8),
                                  title: const Text('عرض التفاصيل', style: TextStyle(fontSize: 11, color: Colors.blue)),
                                  children: issue.details.map((d) => Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(d, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
                                  )).toList(),
                                ),
                              ],
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
                
                // رسالة النجاح
                if (report.isHealthy && report.issues.isEmpty && report.warnings.isEmpty && report.invoiceIssues.isEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.verified, color: Colors.green),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'جميع البيانات المالية لهذا العميل سليمة 100%',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // إغلاق مؤشر التحميل إن كان مفتوحاً
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في فحص السلامة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 🔧 دالة عرض نافذة تأكيد الإصلاح
  Future<void> _showRepairConfirmationDialog(BuildContext parentContext, InvoiceIssue issue) async {
    final confirmed = await showDialog<bool>(
      context: parentContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 28),
            const SizedBox(width: 8),
            const Text('تأكيد الإصلاح', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // تفاصيل المشكلة
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📄 فاتورة #${issue.invoiceId}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text('التاريخ: ${issue.invoiceDate}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      'المشكلة: ${issue.description}',
                      style: TextStyle(color: Colors.red[700], fontSize: 12),
                    ),
                    Text(
                      'الفرق: ${issue.difference.toStringAsFixed(0)} دينار',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // التحذيرات
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                        const SizedBox(width: 8),
                        const Text('تحذيرات مهمة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('• سيتم إضافة معاملة تصحيحية لموازنة الفرق', style: TextStyle(fontSize: 12)),
                    const Text('• هذا الإجراء لا يمكن التراجع عنه', style: TextStyle(fontSize: 12)),
                    const Text('• تأكد من مراجعة الفاتورة يدوياً قبل الإصلاح', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // السؤال
              const Text(
                'هل أنت متأكد من الإصلاح؟\nهل قمت بجميع المراجعات اليدوية؟',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: TextStyle(color: Colors.grey[700])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم، متأكد'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // عرض التحدي الرياضي
      await _showMathChallengeDialog(parentContext, issue);
    }
  }

  // 🧮 دالة عرض التحدي الرياضي
  Future<void> _showMathChallengeDialog(BuildContext parentContext, InvoiceIssue issue) async {
    final random = DateTime.now().millisecondsSinceEpoch;
    final num1 = (random % 10); // رقم من 0 إلى 9
    final num2 = ((random ~/ 10) % 10); // رقم آخر من 0 إلى 9
    final correctAnswer = num1 + num2;
    final answerController = TextEditingController();

    final passed = await showDialog<bool>(
      context: parentContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.calculate, color: Colors.blue[700], size: 28),
            const SizedBox(width: 8),
            const Text('تحدي التأكيد', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'للتأكد من أنك تريد الإصلاح فعلاً،\nأجب على السؤال التالي:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Text(
                '$num1 + $num2 = ؟',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: answerController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'أدخل الإجابة',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              onSubmitted: (value) {
                final answer = int.tryParse(value) ?? -1;
                Navigator.pop(context, answer == correctAnswer);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء', style: TextStyle(color: Colors.grey[700])),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final answer = int.tryParse(answerController.text) ?? -1;
              Navigator.pop(context, answer == correctAnswer);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (passed == true && mounted) {
      // تنفيذ الإصلاح
      await _executeInvoiceRepair(issue);
    } else if (passed == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الإجابة غير صحيحة - تم إلغاء الإصلاح'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // 🔧 دالة تنفيذ الإصلاح الفعلي
  Future<void> _executeInvoiceRepair(InvoiceIssue issue) async {
    try {
      // إظهار مؤشر التحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final db = DatabaseService();
      
      // تنفيذ الإصلاح
      final result = await db.repairInvoiceTransactionMismatch(
        invoiceId: issue.invoiceId,
        customerId: widget.customer.id!,
        expectedDifference: issue.difference,
      );

      if (mounted) {
        Navigator.pop(context); // إغلاق مؤشر التحميل
      }

      if (!mounted) return;

      if (result['success'] == true) {
        // إعادة تحميل البيانات
        await _loadTransactions();
        await context.read<AppProvider>().selectCustomer(widget.customer);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${result['message']}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // إغلاق نافذة التقرير وإعادة فتحها لعرض النتائج المحدثة
        Navigator.pop(context);
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          await _showFinancialIntegrityReport();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${result['message']}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // إغلاق مؤشر التحميل إن كان مفتوحاً
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الإصلاح: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 📄 دالة عرض أرشيف سندات القبض
  Future<void> _showReceiptVouchersArchive() async {
    try {
      // إظهار مؤشر التحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final db = DatabaseService();
      final receipts = await db.getCustomerReceiptVouchers(widget.customer.id!);

      if (mounted) {
        Navigator.pop(context); // إغلاق مؤشر التحميل
      }

      if (!mounted) return;

      // عرض قائمة سندات القبض
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.archive, color: Color(0xFF3F51B5)),
              const SizedBox(width: 12),
              Text('أرشيف سندات القبض (${receipts.length})'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: receipts.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'لا توجد سندات قبض محفوظة',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: receipts.length,
                    itemBuilder: (context, index) {
                      final receipt = receipts[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green[100],
                            child: Text(
                              '${receipt.receiptNumber}',
                              style: TextStyle(
                                color: Colors.green[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            '${formatCurrency(receipt.paidAmount)} دينار',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'رقم السند: ${receipt.receiptNumber} | التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(receipt.createdAt)}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                'قبل: ${formatCurrency(receipt.beforePayment)} → بعد: ${formatCurrency(receipt.afterPayment)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.print, color: Color(0xFF3F51B5)),
                            tooltip: 'إعادة طباعة السند',
                            onPressed: () => _reprintReceiptVoucher(receipt),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // إغلاق مؤشر التحميل إن كان مفتوحاً
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل سندات القبض: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // 📄 دالة إعادة طباعة سند القبض
  Future<void> _reprintReceiptVoucher(CustomerReceiptVoucher receipt) async {
    try {
      final font = pw.Font.ttf(
          await rootBundle.load('assets/fonts/Amiri-Regular.ttf'));
      // استخدام نفس خط الفاتورة لكلمة الناصر
      final alnaserFont = pw.Font.ttf(
          await rootBundle.load('assets/fonts/PTBLDHAD.TTF'));
      final logoBytes = await rootBundle.load('assets/icon/alnasser.jpg');
      final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
      
      final pdf = await ReceiptVoucherPdfService.generateReceiptVoucherPdf(
        customerName: receipt.customerName,
        beforePayment: receipt.beforePayment,
        paidAmount: receipt.paidAmount,
        afterPayment: receipt.afterPayment,
        dateTime: receipt.createdAt,
        font: font,
        alnaserFont: alnaserFont,
        logoImage: logoImage,
        receiptNumber: receipt.receiptNumber,
      );

      // حفظ PDF في ملف مؤقت وفتحه
      final tempDir = Directory.systemTemp;
      final filePath =
          '${tempDir.path}/receipt_voucher_${receipt.receiptNumber}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', 'msedge', filePath]);
      } else {
        await Printing.layoutPdf(
          onLayout: (format) async => await pdf.save(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم فتح سند القبض للطباعة'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في طباعة السند: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 📊 عرض كشف الحساب التجاري
  Future<void> _showCommercialStatement() async {
    try {
      // جلب السنوات المتاحة
      final service = CommercialStatementService();
      final years = await service.getAvailableYears(widget.customer.id!);
      
      if (!mounted) return;
      
      // عرض حوار اختيار الفترة
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => PeriodSelectionDialog(availableYears: years),
      );
      
      if (result == null || !mounted) return;
      
      // تحديد الفترة
      DateTime? startDate;
      DateTime? endDate;
      String periodDescription;
      
      switch (result['type']) {
        case 'all':
          periodDescription = 'كشف حساب شامل';
          break;
        case 'year':
          final year = result['year'] as int;
          startDate = DateTime(year, 1, 1);
          endDate = DateTime(year, 12, 31);
          periodDescription = 'سنة $year';
          break;
        case 'month':
          final year = result['year'] as int;
          final month = result['month'] as int;
          startDate = DateTime(year, month, 1);
          endDate = DateTime(year, month + 1, 0);
          periodDescription = 'شهر $month - $year';
          break;
        default:
          return;
      }
      
      // الانتقال لشاشة كشف الحساب التجاري
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CommercialStatementScreen(
            customer: widget.customer,
            startDate: startDate,
            endDate: endDate,
            periodDescription: periodDescription,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _generateAccountStatement() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      final db = DatabaseService();
      // 🔧 جلب المعاملات مرتبة بنفس طريقة recalculateCustomerTransactionBalances
      final transactions = await db.getCustomerTransactions(
        widget.customer.id!,
        orderBy: 'transaction_date ASC, id ASC', // ترتيب من الأقدم للأحدث
      );

      final allTransactions = <AccountStatementItem>[];

      for (var transaction in transactions) {
        if (transaction.transactionDate != null) {
          final item = AccountStatementItem(
            date: transaction.transactionDate!,
            description: _getTransactionDescription(transaction),
            amount: transaction.amountChanged,
            type: 'transaction',
            transaction: transaction,
          );
          // 🔧 استخدام القيم المحفوظة في قاعدة البيانات
          item.balanceBefore = transaction.balanceBeforeTransaction ?? 0.0;
          item.balanceAfter = transaction.newBalanceAfterTransaction ?? 0.0;
          allTransactions.add(item);
        }
      }

      // 🔧 لا نحتاج للترتيب لأن المعاملات مرتبة مسبقاً من قاعدة البيانات
      // allTransactions.sort((a, b) => a.date.compareTo(b.date));

      // استخدام جميع المعاملات بدلاً من آخر 15 فقط - كشف حساب تفصيلي كامل
      final allTransactionsToShow = allTransactions;

      // 🔧 حساب الرصيد النهائي من آخر معاملة (أو صفر إذا لم توجد معاملات)
      double currentBalance = allTransactionsToShow.isNotEmpty 
          ? allTransactionsToShow.last.balanceAfter 
          : 0.0;

      final actualCustomerBalance = widget.customer.currentTotalDebt;
      
      // ملاحظة: نستخدم الرصيد المحسوب (currentBalance) وليس الرصيد المعروض
      // لأن الرصيد المحسوب هو الصحيح بناءً على المعاملات الفعلية
      
      // تحديد عدد المعاملات (حد أقصى 500 معاملة لتجنب مشاكل الذاكرة)
      final transactionsForPdf = allTransactionsToShow.length > 500
          ? allTransactionsToShow.sublist(allTransactionsToShow.length - 500)
          : allTransactionsToShow;
      

      
      final pdfService = PdfService();
      final pdf = await pdfService.generateAccountStatement(
        customer: widget.customer,
        transactions: transactionsForPdf,
        finalBalance: currentBalance, // ✅ دائماً نستخدم الرصيد المحسوب من المعاملات
      );

      if (mounted) {
        Navigator.pop(context); // Dismiss loading indicator
      }

      if (Platform.isWindows) {
        final safeCustomerName = widget.customer.name
            .replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
        final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final fileName = 'كشف_حساب_${safeCustomerName}_$formattedDate.pdf';
        final directory = Directory(
            '${Platform.environment['USERPROFILE']}/Documents/account_statements');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pdf);

        await Process.start('cmd', ['/c', 'start', '/min', '', filePath]);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إنشاء كشف الحساب وفتحه في المتصفح!'),
              backgroundColor: Theme.of(context).colorScheme.tertiary,
            ),
          );
        }
      } else {
        if (mounted) {
          await Printing.layoutPdf(
            onLayout: (format) async => pdf,
          );
        }
      }
    } catch (e, stackTrace) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading indicator
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء إنشاء كشف الحساب: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  String _getTransactionDescription(DebtTransaction transaction) {
    final hasInvoice = transaction.invoiceId != null;
    final invoicePart = hasInvoice ? ' (فاتورة #${transaction.invoiceId})' : '';
    if (transaction.transactionType == 'invoice_debt') {
      return 'معاملة مالية - إضافة دين$invoicePart';
    } else if (transaction.transactionType == 'manual_payment') {
      return 'دفعة نقدية (تسديد)';
    } else if (transaction.transactionType == 'manual_debt') {
      return 'معاملة يدوية (إضافة دين)';
    } else if (transaction.transactionType == 'Invoice_Debt_Adjustment') {
      return 'تعديل فاتورة رقم: ${transaction.invoiceId}';
    } else if (transaction.transactionType == 'Invoice_Debt_Reversal') {
      return 'حذف فاتورة رقم: ${transaction.invoiceId}';
    } else if (hasInvoice) {
      // أي معاملة أخرى مرتبطة بفاتورة
      return 'معاملة مالية$invoicePart';
    } else {
      return transaction.transactionNote ?? 'معاملة مالية';
    }
  }
}

class TransactionListTile extends StatelessWidget {
  final DebtTransaction transaction;
  final bool isPlaying;
  final String? currentlyPlayingPath;
  final VoidCallback onPlayStop;
  final String audioPath;
  
  // Callbacks for edit and refresh after change
  final Future<void> Function(DebtTransaction updated)? onEdit;
  // Callback for converting transaction type
  final Future<void> Function(int transactionId)? onConvertType;
  // 🔄 Callback لتحديث البيانات عند الرجوع من الفاتورة
  final VoidCallback? onRefresh;

  const TransactionListTile({
    super.key,
    required this.transaction,
    required this.isPlaying,
    required this.currentlyPlayingPath,
    required this.onPlayStop,
    required this.audioPath,
    this.onEdit,
    this.onConvertType,
    this.onRefresh,
  });

  // Helper to format numbers with thousand separators
  String _formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  @override
  Widget build(BuildContext context) {
    final isDebt = transaction.amountChanged > 0;
    final color = isDebt
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary; // Use themed colors
    final icon = isDebt ? Icons.add : Icons.remove;
    final isInvoiceRelated = transaction.invoiceId != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0), // Spacing between cards
      elevation: 2, // Consistent card elevation
      child: ListTile(
        onTap: isInvoiceRelated
            ? () => _navigateToInvoiceDetails(
                context, transaction.customerId, transaction.invoiceId!)
            : null,
        leading: CircleAvatar(
          backgroundColor:
              color.withOpacity(0.1), // Lighter background for avatar
          child: Icon(icon, color: color, size: 28), // Larger, themed icon
        ),
        title: Text(
          '${_formatCurrency(transaction.amountChanged.abs())} دينار', // Formatted amount
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                // Themed text style
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الرصيد قبل المعاملة: ${_formatCurrency(transaction.balanceBeforeTransaction ?? 0.0)} دينار', // Formatted balance before
              style:
                  Theme.of(context).textTheme.bodyMedium, // Themed text style
            ),
            Text(
              'الرصيد بعد المعاملة: ${_formatCurrency(transaction.newBalanceAfterTransaction ?? 0.0)} دينار', // Formatted balance after
              style:
                  Theme.of(context).textTheme.bodyMedium, // Themed text style
            ),
            if (transaction.transactionNote != null &&
                transaction.transactionNote!.isNotEmpty)
              Text(transaction.transactionNote!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall), // Themed text style
            if (isInvoiceRelated)
              Text(
                'مرتبطة بالفاتورة #${transaction.invoiceId}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600]), // Themed text style
              ),
            if (transaction.audioNotePath != null &&
                transaction.audioNotePath!.isNotEmpty)
              Row(
                children: [
                  // زر التشغيل/الإيقاف
                  IconButton(
                    icon: Icon(
                      isPlaying && currentlyPlayingPath == audioPath
                          ? Icons.stop_circle
                          : Icons.play_circle_fill,
                      color: isPlaying && currentlyPlayingPath == audioPath
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                    ),
                    tooltip: isPlaying && currentlyPlayingPath == audioPath
                        ? 'إيقاف تشغيل الملاحظة الصوتية'
                        : 'تشغيل الملاحظة الصوتية',
                    onPressed: onPlayStop,
                  ),
                  // نص الحالة
                  Text(
                    isPlaying && currentlyPlayingPath == audioPath
                        ? 'إيقاف تشغيل الملاحظة الصوتية'
                        : 'تشغيل الملاحظة الصوتية',
                    style: TextStyle(
                      color: isPlaying && currentlyPlayingPath == audioPath
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: SizedBox(
          height: 48, // التزام بارتفاع ListTile القياسي لمنع overflow
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // تمت إزالة زر تحويل نوع المعاملة بناءً على طلب المستخدم
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'تعديل المعاملة',
                onPressed: () async {
                if (onEdit == null) return;
                final amountController = TextEditingController(text: transaction.amountChanged.toStringAsFixed(2));
                final noteController = TextEditingController(text: transaction.transactionNote ?? '');
                DateTime selectedDate = transaction.transactionDate ?? DateTime.now();
                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (context) {
                    bool isDebt = transaction.amountChanged >= 0;
                    amountController.text = transaction.amountChanged.abs().toString();
                    double previewBalance = (transaction.newBalanceAfterTransaction ?? 0);

                    void computePreview() {
                      final entered = double.tryParse(amountController.text.trim()) ?? transaction.amountChanged.abs();
                      final signed = isDebt ? entered : -entered;
                      final delta = signed - transaction.amountChanged;
                      previewBalance = (transaction.newBalanceAfterTransaction ?? 0) + delta;
                    }

                    computePreview();

                    return StatefulBuilder(
                      builder: (ctx, setState) {
                        return AlertDialog(
                          title: const Text('تعديل المعاملة'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // نوع العملية: إضافة دين أو تسديد دين
                                Row(
                                  children: [
                                    Expanded(
                                      child: ChoiceChip(
                                        selected: isDebt,
                                        label: const Text('إضافة دين'),
                                        onSelected: (v) {
                                          setState(() {
                                            isDebt = true;
                                            computePreview();
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ChoiceChip(
                                        selected: !isDebt,
                                        label: const Text('تسديد دين'),
                                        onSelected: (v) {
                                          setState(() {
                                            isDebt = false;
                                            computePreview();
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: amountController,
                                  decoration: const InputDecoration(labelText: 'المبلغ'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) => setState(() => computePreview()),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'الرصيد المتوقع بعد الحفظ: ${_formatCurrency(previewBalance)}',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: noteController,
                                  decoration: const InputDecoration(labelText: 'ملاحظة'),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: selectedDate,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        selectedDate = picked;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.calendar_today),
                                  label: Text('التاريخ: ${_formatDate(selectedDate)}'),
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, {'ok': false}), child: const Text('إلغاء')),
                            TextButton(onPressed: () => Navigator.pop(context, {'ok': true, 'isDebt': isDebt}), child: const Text('حفظ')),
                          ],
                        );
                      },
                    );
                  },
                );
                if (result != null && (result['ok'] == true)) {
                  final bool isDebtSelected = result['isDebt'] as bool? ?? (transaction.amountChanged >= 0);
                  final entered = double.tryParse(amountController.text.trim()) ?? transaction.amountChanged.abs();
                  final newAmount = (amountController.text.trim().isEmpty)
                      ? transaction.amountChanged
                      : (isDebtSelected ? entered : -entered);
                  final updated = transaction.copyWith(
                    amountChanged: newAmount,
                    transactionNote: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                    transactionDate: selectedDate,
                    transactionType: (newAmount >= 0) ? 'manual_debt' : 'manual_payment',
                  );
                  await onEdit!(updated);
                }
              },
              ),
              const SizedBox(width: 8),
              Text(
                _formatDate(transaction.transactionDate!),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[700],
                      fontSize: 12,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd HH:mm').format(date); // التاريخ مع الوقت (ساعة:دقيقة)
  }

  void _navigateToInvoiceDetails(
      BuildContext context, int customerId, int invoiceId) async {
    try {
      final db = DatabaseService();
      final invoice = await db.getInvoiceById(invoiceId);
      DebtTransaction? relatedDebtTransaction;
      final transactions = await db.getCustomerTransactions(customerId);
      for (var transaction in transactions) {
        if (transaction.invoiceId == invoiceId &&
            transaction.amountChanged > 0) {
          relatedDebtTransaction = transaction;
          break;
        }
      }

      if (invoice != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateInvoiceScreen(
              existingInvoice: invoice,
              isViewOnly: invoice.status == 'محفوظة',
              relatedDebtTransaction: relatedDebtTransaction,
            ),
          ),
        ).then((_) {
          // 🔄 تحديث البيانات عند الرجوع من الفاتورة
          onRefresh?.call();
        });
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('لم يتم العثور على الفاتورة المطلوبة.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ عند تحميل الفاتورة: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}


// ═══════════════════════════════════════════════════════════════════════════
// 📊 Widget لعرض المعاملات المجمعة
// ═══════════════════════════════════════════════════════════════════════════

class GroupedTransactionListTile extends StatelessWidget {
  final GroupedTransactionItem item;
  final bool isPlaying;
  final String? currentlyPlayingPath;
  final VoidCallback onPlayStop;
  final VoidCallback onRefresh;
  final int customerId; // إضافة معرف العميل للتنقل للفاتورة

  const GroupedTransactionListTile({
    super.key,
    required this.item,
    required this.isPlaying,
    required this.currentlyPlayingPath,
    required this.onPlayStop,
    required this.onRefresh,
    required this.customerId,
  });

  String _formatCurrency(num value) {
    return NumberFormat('#,##0', 'en_US').format(value);
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy/MM/dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    if (item.isInvoice) {
      return _buildInvoiceTile(context);
    } else if (item.isManualDebtGroup) {
      return _buildManualGroupTile(context, isDebt: true, isSync: false);
    } else if (item.isManualPaymentGroup) {
      return _buildManualGroupTile(context, isDebt: false, isSync: false);
    } else if (item.isSyncDebtGroup) {
      return _buildManualGroupTile(context, isDebt: true, isSync: true);
    } else if (item.isSyncPaymentGroup) {
      return _buildManualGroupTile(context, isDebt: false, isSync: true);
    } else {
      return _buildManualTransactionTile(context);
    }
  }

  /// بناء بطاقة الفاتورة المجمعة
  Widget _buildInvoiceTile(BuildContext context) {
    final isDebt = item.amount > 0;
    final color = item.isFullyPaid
        ? Colors.green
        : (isDebt ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.tertiary);
    
    final icon = item.isFullyPaid
        ? Icons.check_circle
        : (item.isCashInvoice ? Icons.payments : Icons.receipt_long);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 2,
      child: InkWell(
        onTap: () => _showInvoiceDetails(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // أيقونة الفاتورة
              CircleAvatar(
                backgroundColor: color.withOpacity(0.1),
                radius: 24,
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              // معلومات الفاتورة
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item.description,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (item.transactionCount > 1) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${item.transactionCount} تعديل',
                              style: TextStyle(fontSize: 10, color: Colors.blue[800]),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'إجمالي الفاتورة: ${_formatCurrency(item.invoiceTotal ?? 0)} دينار',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'التاريخ: ${_formatDate(item.date)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              // المبلغ المتبقي وزر الذهاب للفاتورة
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // زر الذهاب للفاتورة
                  IconButton(
                    icon: Icon(Icons.open_in_new, color: Theme.of(context).colorScheme.primary, size: 20),
                    tooltip: 'الذهاب للفاتورة',
                    onPressed: () => _navigateToInvoice(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        item.isFullyPaid ? 'مسددة' : 'المتبقي',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      Text(
                        '${_formatCurrency(item.amount.abs())}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Icon(Icons.chevron_left, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// بناء بطاقة المعاملة اليدوية
  Widget _buildManualTransactionTile(BuildContext context) {
    final isDebt = item.amount > 0;
    final color = isDebt
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary;
    final icon = isDebt ? Icons.add : Icons.remove;

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          '${_formatCurrency(item.amount.abs())} دينار',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الرصيد قبل: ${_formatCurrency(item.balanceBefore ?? 0)} دينار',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              'الرصيد بعد: ${_formatCurrency(item.balanceAfter ?? 0)} دينار',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Text(
              item.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              _formatDate(item.date),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            // زر تشغيل الصوت إذا كان موجوداً
            if (item.audioNotePath != null && item.audioNotePath!.isNotEmpty)
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      isPlaying && currentlyPlayingPath == item.audioNotePath
                          ? Icons.stop_circle
                          : Icons.play_circle_fill,
                      color: isPlaying && currentlyPlayingPath == item.audioNotePath
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                    ),
                    tooltip: isPlaying && currentlyPlayingPath == item.audioNotePath
                        ? 'إيقاف'
                        : 'تشغيل',
                    onPressed: onPlayStop,
                  ),
                  Text(
                    'ملاحظة صوتية',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// بناء بطاقة مجموعة المعاملات اليدوية أو المزامنة (إضافة دين أو تسديد)
  Widget _buildManualGroupTile(BuildContext context, {required bool isDebt, required bool isSync}) {
    final color = isDebt
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary;
    
    // أيقونة مختلفة للمزامنة
    final IconData icon;
    final String title;
    if (isSync) {
      icon = isDebt ? Icons.cloud_download : Icons.cloud_upload;
      title = isDebt ? 'معاملات مزامنة (إضافة دين)' : 'معاملات مزامنة (تسديد)';
    } else {
      icon = isDebt ? Icons.add_circle : Icons.remove_circle;
      title = isDebt ? 'معاملات يدوية (إضافة دين)' : 'معاملات يدوية (تسديد)';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 2,
      // خلفية مميزة لمعاملات المزامنة
      color: isSync ? Colors.blue[50] : null,
      child: InkWell(
        onTap: () => _showManualGroupDetails(context, isDebt: isDebt, isSync: isSync),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // أيقونة المجموعة
              CircleAvatar(
                backgroundColor: isSync ? Colors.blue.withOpacity(0.2) : color.withOpacity(0.1),
                radius: 24,
                child: Icon(icon, color: isSync ? Colors.blue : color, size: 24),
              ),
              const SizedBox(width: 12),
              // معلومات المجموعة
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSync ? Colors.blue.withOpacity(0.1) : color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${item.transactionCount} معاملة',
                            style: TextStyle(fontSize: 10, color: isSync ? Colors.blue : color),
                          ),
                        ),
                        // شارة المزامنة
                        if (isSync) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.sync, color: Colors.white, size: 10),
                                SizedBox(width: 2),
                                Text(
                                  'مزامنة',
                                  style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'آخر تاريخ: ${_formatDate(item.date)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              // المجموع
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'المجموع',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  Text(
                    '${isDebt ? '+' : ''}${_formatCurrency(item.amount.abs())}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Icon(Icons.chevron_left, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// عرض تفاصيل مجموعة المعاملات اليدوية أو المزامنة
  void _showManualGroupDetails(BuildContext context, {required bool isDebt, required bool isSync}) {
    final color = isDebt
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.tertiary;
    
    final String title;
    final IconData icon;
    if (isSync) {
      title = isDebt ? 'معاملات المزامنة (إضافة دين)' : 'معاملات المزامنة (تسديد)';
      icon = isDebt ? Icons.cloud_download : Icons.cloud_upload;
    } else {
      title = isDebt ? 'معاملات الإضافة اليدوية' : 'معاملات التسديد اليدوية';
      icon = isDebt ? Icons.add_circle : Icons.remove_circle;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // المقبض
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // العنوان
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, color: isSync ? Colors.blue : color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                            if (isSync) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.sync, color: Colors.white, size: 12),
                                    SizedBox(width: 2),
                                    Text(
                                      'من جهاز آخر',
                                      style: TextStyle(fontSize: 10, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${item.transactionCount} معاملة',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  // المجموع
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${isDebt ? '+' : ''}${_formatCurrency(item.amount.abs())} دينار',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            // قائمة المعاملات
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: item.transactions.length,
                itemBuilder: (context, index) {
                  final tx = item.transactions[index];
                  final isPositive = tx.amountChanged > 0;
                  final txColor = isPositive ? Colors.red : Colors.green;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    // خلفية مميزة لمعاملات المزامنة
                    color: isSync ? Colors.blue[50] : null,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSync ? Colors.blue.withOpacity(0.2) : txColor.withOpacity(0.1),
                        radius: 18,
                        child: isSync 
                            ? const Icon(Icons.sync, color: Colors.blue, size: 16)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(color: txColor, fontWeight: FontWeight.bold),
                              ),
                      ),
                      title: Text(
                        '${isPositive ? '+' : ''}${_formatCurrency(tx.amountChanged)} دينار',
                        style: TextStyle(
                          color: txColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTransactionTypeLabel(tx.transactionType),
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (tx.transactionNote != null && tx.transactionNote!.isNotEmpty)
                            Text(
                              tx.transactionNote!,
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          Text(
                            DateFormat('yyyy/MM/dd HH:mm').format(tx.transactionDate),
                            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'قبل: ${_formatCurrency(tx.balanceBeforeTransaction ?? 0)}',
                            style: const TextStyle(fontSize: 10),
                          ),
                          Text(
                            'بعد: ${_formatCurrency(tx.newBalanceAfterTransaction ?? 0)}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // ملخص
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'المجموع:',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Text(
                    '${isDebt ? '+' : ''}${_formatCurrency(item.amount.abs())} دينار',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// عرض تفاصيل الفاتورة (جميع المعاملات المرتبطة)
  void _showInvoiceDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // المقبض
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // العنوان
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.receipt_long, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تفاصيل فاتورة #${item.invoiceId}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'إجمالي الفاتورة: ${_formatCurrency(item.invoiceTotal ?? 0)} دينار',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  // المبلغ المتبقي
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: item.isFullyPaid ? Colors.green[100] : Colors.orange[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      item.isFullyPaid
                          ? 'مسددة ✓'
                          : 'متبقي: ${_formatCurrency(item.amount.abs())}',
                      style: TextStyle(
                        color: item.isFullyPaid ? Colors.green[800] : Colors.orange[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // زر الذهاب للفاتورة
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context); // إغلاق الـ BottomSheet
                    _navigateToInvoice(context);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('الذهاب للفاتورة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
            // قائمة المعاملات
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: item.transactions.length,
                itemBuilder: (context, index) {
                  final tx = item.transactions[index];
                  final isPositive = tx.amountChanged > 0;
                  final txColor = isPositive ? Colors.red : Colors.green;
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: txColor.withOpacity(0.1),
                        radius: 18,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: txColor, fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        '${isPositive ? '+' : ''}${_formatCurrency(tx.amountChanged)} دينار',
                        style: TextStyle(
                          color: txColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTransactionTypeLabel(tx.transactionType),
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (tx.transactionNote != null && tx.transactionNote!.isNotEmpty)
                            Text(
                              tx.transactionNote!,
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            ),
                          Text(
                            DateFormat('yyyy/MM/dd HH:mm').format(tx.transactionDate),
                            style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'قبل: ${_formatCurrency(tx.balanceBeforeTransaction ?? 0)}',
                            style: const TextStyle(fontSize: 10),
                          ),
                          Text(
                            'بعد: ${_formatCurrency(tx.newBalanceAfterTransaction ?? 0)}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // ملخص
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'صافي المعاملات:',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Text(
                    '${_formatCurrency(item.amount)} دينار',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: item.amount > 0 ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// الذهاب مباشرة لشاشة الفاتورة
  void _navigateToInvoice(BuildContext context) async {
    if (item.invoiceId == null) return;
    
    try {
      final db = DatabaseService();
      final invoice = await db.getInvoiceById(item.invoiceId!);
      DebtTransaction? relatedDebtTransaction;
      final transactions = await db.getCustomerTransactions(customerId);
      for (var transaction in transactions) {
        if (transaction.invoiceId == item.invoiceId &&
            transaction.amountChanged > 0) {
          relatedDebtTransaction = transaction;
          break;
        }
      }

      if (invoice != null && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateInvoiceScreen(
              existingInvoice: invoice,
              isViewOnly: invoice.status == 'محفوظة',
              relatedDebtTransaction: relatedDebtTransaction,
            ),
          ),
        ).then((_) {
          // 🔄 تحديث البيانات عند الرجوع من الفاتورة
          onRefresh();
        });
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('لم يتم العثور على الفاتورة المطلوبة.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ عند تحميل الفاتورة: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _getTransactionTypeLabel(String? type) {
    switch (type) {
      case 'invoice_debt':
      case 'debt_invoice':
        return '📄 إنشاء دين الفاتورة';
      case 'invoice_payment':
        return '💰 تسديد على الفاتورة';
      case 'invoice_adjustment':
        return '✏️ تعديل الفاتورة';
      case 'invoice_discount':
        return '🏷️ خصم على الفاتورة';
      case 'payment_type_change':
        return '🔄 تحويل نوع الدفع';
      case 'manual_payment':
        return '💵 تسديد يدوي';
      case 'manual_debt':
        return '📝 دين يدوي';
      default:
        return '📋 معاملة';
    }
  }
}
