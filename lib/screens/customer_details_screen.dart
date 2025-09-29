// screens/customer_details_screen.dart
// screens/customer_details_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import 'add_transaction_screen.dart';
import 'create_invoice_screen.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart'; // Assume PdfService exists
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

  @override
  void initState() {
    super.initState();
    // This is good practice for initial data loading from a provider
    Future.microtask(
        () => context.read<AppProvider>().selectCustomer(widget.customer));
  }

  @override
  void dispose() {
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
      
      // ترميز الرسالة للرابط
      final encodedMessage = Uri.encodeComponent(message);
      
      // إنشاء روابط واتساب
      final whatsappAppUri = Uri.parse('whatsapp://send?phone=$phoneNumber&text=$encodedMessage');
      final whatsappWebUri = Uri.parse('https://wa.me/$phoneNumber?text=$encodedMessage');
      
      bool success = false;
      
      // محاولة فتح تطبيق واتساب أولاً مع timeout
      try {
        if (await canLaunchUrl(whatsappAppUri)) {
          await launchUrl(whatsappAppUri);
          success = true;
        }
      } catch (e) {
        print('خطأ في فتح تطبيق واتساب: $e');
      }
      
      // إذا فشل تطبيق واتساب، انتظر قليلاً ثم جرب واتساب ويب
      if (!success) {
        await Future.delayed(const Duration(milliseconds: 500));
        
        try {
          if (await canLaunchUrl(whatsappWebUri)) {
            await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
            success = true;
          }
        } catch (e) {
          print('خطأ في فتح واتساب ويب: $e');
        }
      }
      
      // إغلاق مؤشر التحميل
      if (mounted) {
        Navigator.pop(context);
      }
      
      if (success) {
        // نجح فتح واتساب
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم فتح واتساب بنجاح!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        // فشل فتح واتساب، انسخ الرسالة للحافظة
        await Clipboard.setData(ClipboardData(text: message));
        
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('تعذر فتح واتساب'),
              content: const Text('تم نسخ رسالة الدين إلى الحافظة. افتح واتساب والصقها لإرسالها.'),
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
      
      // في حالة الخطأ، انسخ الرسالة للحافظة
      final message = _buildDebtMessage();
      await Clipboard.setData(ClipboardData(text: message));
      
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
                  
                  final updated = widget.customer.copyWith(
                    name: nameController.text.trim(),
                    phone: normalizedPhone,
                    address: addressController.text.trim(),
                    lastModifiedAt: DateTime.now(),
                  );
                  await context.read<AppProvider>().updateCustomer(updated);
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
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('تأكيد الحذف',
                        style: TextStyle(
                            fontWeight: FontWeight.bold)), // Bold title
                    content: const Text(
                        'هل أنت متأكد من حذف هذا العميل؟ لا يمكن التراجع عن هذا الإجراء.'), // More informative text
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('إلغاء',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary)), // Themed text button
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('حذف',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .error)), // Themed text button
                      ),
                    ],
                  ),
                );

                if (confirmed == true && mounted) {
                  await context
                      .read<AppProvider>()
                      .deleteCustomer(widget.customer.id!);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'تم حذف العميل ${widget.customer.name} بنجاح!'),
                          backgroundColor:
                              Theme.of(context).colorScheme.tertiary),
                    );
                    Navigator.pop(
                        context); // Pop customer details screen after deletion
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
                      Text(
                        'سجل المعاملات',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AddTransactionScreen(
                                customer: customer,
                              ),
                            ),
                          );
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
                  child: transactions.isEmpty
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
                                final db = DatabaseService();
                                await db.updateTransaction(updated);
                                final newTotal = await db.recalculateAndApplyCustomerDebt(transaction.customerId);
                                // حدث المزود والواجهة
                                await context.read<AppProvider>().selectCustomer((await db.getCustomerById(transaction.customerId))!);
                                await context.read<AppProvider>().loadCustomerTransactions(transaction.customerId);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('تم تحديث المعاملة. الدين الحالي: ${formatCurrency(newTotal)}')),
                                  );
                                }
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
      final transactions =
          await db.getCustomerTransactions(widget.customer.id!);

      final allTransactions = <AccountStatementItem>[];

      for (var transaction in transactions) {
        if (transaction.transactionDate != null) {
          allTransactions.add(AccountStatementItem(
            date: transaction.transactionDate!,
            description: _getTransactionDescription(transaction),
            amount: transaction.amountChanged,
            type: 'transaction',
            transaction: transaction,
          ));
        }
      }

      allTransactions.sort((a, b) => a.date.compareTo(b.date));

      final last15Transactions = allTransactions.length > 15
          ? allTransactions.sublist(allTransactions.length - 15)
          : allTransactions;

      double currentBalance = 0.0;

      if (last15Transactions.isNotEmpty) {
        final firstTransactionDate = last15Transactions.first.date;

        for (var transaction in transactions) {
          if (transaction.transactionDate!.isBefore(firstTransactionDate)) {
            currentBalance += transaction.amountChanged;
          }
        }
      }

      for (var item in last15Transactions) {
        item.balanceBefore = currentBalance;
        currentBalance += item.amount;
        item.balanceAfter = currentBalance;
      }

      final actualCustomerBalance = widget.customer.currentTotalDebt;
      if ((currentBalance - actualCustomerBalance).abs() > 0.01) {
        print(
            'Warning: Calculated balance ($currentBalance) differs from actual customer balance ($actualCustomerBalance)');
        // In a real app, you might re-calculate from scratch or use the actual balance
        // For this scenario, we'll use the actual customer balance as the final one for display
        // but it's important to understand the discrepancy might point to data inconsistencies.
        currentBalance =
            actualCustomerBalance; // Use the actual latest balance from customer model
      }

      final pdfService = PdfService();
      final pdf = await pdfService.generateAccountStatement(
        customer: widget.customer,
        transactions: last15Transactions,
        finalBalance: currentBalance,
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
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading indicator
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء إنشاء كشف الحساب: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
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

  const TransactionListTile({
    super.key,
    required this.transaction,
    required this.isPlaying,
    required this.currentlyPlayingPath,
    required this.onPlayStop,
    required this.audioPath,
    this.onEdit,
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
              'الرصيد بعد المعاملة: ${_formatCurrency(transaction.newBalanceAfterTransaction ?? 0.0)} دينار', // Formatted balance
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
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('تعديل المعاملة'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: amountController,
                              decoration: const InputDecoration(labelText: 'المبلغ (موجب لإضافة دين، سالب لتسديد)'),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                                  selectedDate = picked;
                                }
                              },
                              icon: const Icon(Icons.calendar_today),
                              label: Text('التاريخ: ${_formatDate(selectedDate)}'),
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
                if (ok == true) {
                  final newAmount = double.tryParse(amountController.text.trim()) ?? transaction.amountChanged;
                  final updated = transaction.copyWith(
                    amountChanged: newAmount,
                    transactionNote: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                    transactionDate: selectedDate,
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
    return DateFormat('yyyy/MM/dd').format(date); // Consistent date format
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
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لم يتم العثور على الفاتورة المطلوبة.'),
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
