// screens/main_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/telegram_backup_service.dart';
import '../services/telegram_invoice_export_service.dart';
import '../models/customer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/password_service.dart';
import '../screens/general_settings_screen.dart';
import '../services/pdf_service.dart';
import 'customer_details_screen.dart'; // إضافة استيراد شاشة تفاصيل العميل

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String _currentMonthYear = '';
  final PasswordService _passwordService = PasswordService();
  final Color _primaryColor = const Color(0xFF6C63FF);
  final Color _accentColor = const Color(0xFFFFD54F);
  final Color _backgroundColor = const Color(0xFFF5F7FB);

  @override
  void initState() {
    super.initState();
    _updateCurrentMonthYear();
    // تأكد من تهيئة مزود التطبيق لتفعيل دعم Google Drive
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().initialize();
    });
  }

  void _updateCurrentMonthYear() {
    final now = DateTime.now();
    _currentMonthYear = DateFormat.yMMMM('ar').format(now);
  }

  Future<bool> _showPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الرجاء إدخال كلمة السر',
            style: TextStyle(fontSize: 20)),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'كلمة السر',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.lock, size: 28),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          ),
          style: const TextStyle(fontSize: 18),
          autofocus: true,
          onSubmitted: (value) async {
            final bool isCorrect = await _passwordService.verifyPassword(value);
            Navigator.of(context).pop(isCorrect);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontSize: 18)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: () async {
              final bool isCorrect = await _passwordService
                  .verifyPassword(passwordController.text);
              Navigator.of(context).pop(isCorrect);
            },
            child: const Text('تأكيد', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildFeatureButton({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color color = const Color(0xFF6C63FF),
    double fontSize = 40,
    double iconSize = 30,
    double padding = 6,
    double spacing = 4,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: iconSize, color: color),
            SizedBox(height: spacing),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 600;
    final crossAxisCount = isLargeScreen ? 6 : 5;
    final childAspectRatio = 0.7;
    final buttonFontSize = 40.0;
    final iconSize = 60.0;
    final buttonPadding = 4.0;
    final buttonSpacing = 4.0;
    final gridSpacing = 32.0;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text('دفتر ديوني', style: TextStyle(fontSize: 24)),
        centerTitle: true,
        backgroundColor: _primaryColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: gridSpacing,
          crossAxisSpacing: gridSpacing,
          childAspectRatio: childAspectRatio,
          children: [

            _buildFeatureButton(
              icon: Icons.book,
              title: 'سجل الديون',
              onTap: () => Navigator.pushNamed(context, '/debt_register'),
              color: _primaryColor,
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),
            _buildFeatureButton(
              icon: Icons.inventory,
              title: 'إدخال البضاعة',
              onTap: () => Navigator.pushNamed(context, '/product_entry'),
              color: const Color(0xFF4CAF50),
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),
            _buildFeatureButton(
              icon: Icons.list_alt,
              title: 'إنشاء قائمة',
              onTap: () => Navigator.pushNamed(context, '/create_invoice'),
              color: const Color(0xFF2196F3),
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),
            _buildFeatureButton(
              icon: Icons.warning,
              title: 'المتأخرين عن الديون',
              onTap: () async {
                final TextEditingController _monthsController = TextEditingController();
                int? selectedMonths = await showDialog<int>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('أدخل عدد الأشهر', style: TextStyle(fontSize: 20)),
                    content: TextField(
                      controller: _monthsController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'عدد الأشهر',
                        hintText: 'مثلاً 12',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('إلغاء'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          final val = int.tryParse(_monthsController.text);
                          if (val != null && val > 0) {
                            Navigator.pop(context, val);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('الرجاء إدخال عدد صحيح')),
                            );
                          }
                        },
                        child: const Text('بحث'),
                      ),
                    ],
                  ),
                );

                if (selectedMonths != null) {
                  final db = DatabaseService();
                  final pdfService = PdfService();
                  var results = await db.getLateCustomers(selectedMonths!);
                  
                  // متغير للترتيب (false = من الأقدم للأحدث، true = من الأحدث للأقدم)
                  bool isReversed = false;

                  if (!mounted) return;

                  showDialog(
                    context: context,
                    builder: (context) => StatefulBuilder(
                      builder: (context, setState) {
                        // دالة لعكس الترتيب
                        void toggleSort() {
                          setState(() {
                            isReversed = !isReversed;
                            results = results.reversed.toList();
                          });
                        }
                        
                        // دالة للحصول على نص نوع المعاملة
                        String getTransactionTypeText(String? type, int? invoiceId) {
                          if (type == null) return '';
                          switch (type) {
                            case 'manual_payment':
                              return 'تسديد دين';
                            case 'return_payment':
                              return 'تسديد دين راجع';
                            case 'manual_debt':
                              return 'إضافة دين يدوي';
                            case 'invoice':
                              return invoiceId != null ? 'إضافة دين فاتورة #$invoiceId' : 'إضافة دين فاتورة';
                            case 'initial_debt':
                              return 'دين أولي';
                            default:
                              return type;
                          }
                        }
                        
                        // دالة للانتقال لصفحة العميل
                        Future<void> navigateToCustomer(int customerId) async {
                          try {
                            final customer = await db.getCustomerById(customerId);
                            if (customer != null && mounted) {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CustomerDetailsScreen(customer: customer),
                                ),
                              );
                              // بعد الرجوع، نبقى في نفس الـ Dialog
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('خطأ في فتح تفاصيل العميل: $e')),
                              );
                            }
                          }
                        }

                        return AlertDialog(
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'المتأخرون ($selectedMonths شهر أقدم)',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                ),
                              ),
                              // زر عكس الترتيب
                              if (results.isNotEmpty)
                                IconButton(
                                  icon: Icon(
                                    isReversed ? Icons.arrow_downward : Icons.arrow_upward,
                                    color: _primaryColor,
                                  ),
                                  tooltip: isReversed ? 'من الأقدم للأحدث' : 'من الأحدث للأقدم',
                                  onPressed: toggleSort,
                                ),
                            ],
                          ),
                          content: results.isEmpty
                              ? const Text('لا يوجد عملاء متأخرون', style: TextStyle(fontSize: 18))
                              : Container(
                                  width: MediaQuery.of(context).size.width * 0.98,
                                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: Table(
                                      border: TableBorder.all(color: Colors.grey.shade400, width: 1.5),
                                      columnWidths: const {
                                        0: FixedColumnWidth(40),  // ت
                                        1: FlexColumnWidth(2.0), // الاسم
                                        2: FlexColumnWidth(0.9), // العنوان (تم تقليله بنسبة 40%)
                                        3: FixedColumnWidth(130), // الهاتف
                                        4: FixedColumnWidth(200), // آخر معاملة (تم زيادته)
                                        5: FixedColumnWidth(110), // المبلغ
                                      },
                                      children: [
                                        TableRow(
                                          decoration: BoxDecoration(color: Colors.grey.shade300),
                                          children: const [
                                            Padding(padding: EdgeInsets.all(6), child: Text('ت', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                            Padding(padding: EdgeInsets.all(6), child: Text('الاسم', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                            Padding(padding: EdgeInsets.all(6), child: Text('العنوان', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                            Padding(padding: EdgeInsets.all(6), child: Text('الهاتف', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                            Padding(padding: EdgeInsets.all(6), child: Text('آخر معاملة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                            Padding(padding: EdgeInsets.all(6), child: Text('المبلغ', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                          ],
                                        ),
                                        ...results.asMap().entries.map((entry) {
                                          final i = entry.key;
                                          final r = entry.value;
                                          final customerId = r['id'] as int?;
                                          final lastDate = r['last_transaction_date'] != null 
                                              ? DateFormat('yyyy-MM-dd').format(DateTime.parse(r['last_transaction_date']))
                                              : 'لا يوجد';
                                          final transactionType = r['last_transaction_type'] as String?;
                                          final invoiceId = r['last_transaction_invoice_id'] as int?;
                                          final transactionTypeText = getTransactionTypeText(transactionType, invoiceId);
                                          final amount = (r['current_total_debt'] as num?)?.toDouble() ?? 0.0;
                                          
                                          return TableRow(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.all(6),
                                                child: Text(
                                                  '${i + 1}',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontSize: 14),
                                                ),
                                              ),
                                              // الاسم - قابل للنقر مع تأثير hover
                                              Padding(
                                                padding: const EdgeInsets.all(6),
                                                child: MouseRegion(
                                                  cursor: SystemMouseCursors.click,
                                                  child: GestureDetector(
                                                    onTap: customerId != null ? () => navigateToCustomer(customerId) : null,
                                                    child: HoverText(
                                                      text: r['name'] ?? '-',
                                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                                      hoverColor: Colors.red,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(6),
                                                child: Text(
                                                  r['address'] ?? '-',
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(fontSize: 14),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(6),
                                                child: Text(
                                                  r['phone'] ?? '-',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontSize: 15),
                                                ),
                                              ),
                                              // آخر معاملة - مع التاريخ ونوع المعاملة
                                              Padding(
                                                padding: const EdgeInsets.all(6),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      lastDate,
                                                      textAlign: TextAlign.center,
                                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                                    ),
                                                    if (transactionTypeText.isNotEmpty)
                                                      Text(
                                                        transactionTypeText,
                                                        textAlign: TextAlign.center,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey[700],
                                                          fontStyle: FontStyle.italic,
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(6),
                                                child: Text(
                                                  NumberFormat('#,##0').format(amount),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.red,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ],
                                    ),
                                  ),
                                ),
                          actions: [
                            if (results.isNotEmpty)
                              ElevatedButton.icon(
                                icon: const Icon(Icons.open_in_new, size: 24),
                                label: const Text('فتح PDF', style: TextStyle(fontSize: 18)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                                onPressed: () async {
                                  try {
                                    final file = await pdfService.generateDelayedDebtsPdf(results, selectedMonths!);
                                    if (await file.exists()) {
                                      final uri = Uri.file(file.path);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri);
                                      } else {
                                        await Share.shareXFiles([XFile(file.path)]);
                                      }
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في فتح الملف: $e')));
                                  }
                                },
                              ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('إغلاق', style: TextStyle(fontSize: 18)),
                            ),
                          ],
                        );
                      },
                    ),
                  );
                }
              },
              color: const Color(0xFFF44336),
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),
            _buildFeatureButton(
              icon: Icons.cloud_upload,
              title: 'رفع قاعدة\nالبيانات',
              onTap: () async {
                final progressNotifier = ValueNotifier<double>(0.0);
                final statusNotifier = ValueNotifier<String>('جاري رفع قاعدة البيانات...');
                final errorNotifier = ValueNotifier<String?>(''); // لتتبع الأخطاء
                bool uploadSucceeded = false;

                // جلب وقت آخر رفع
                final telegramService = TelegramBackupService();
                final lastUploadTime = await telegramService.getLastUploadTime();
                
                // طباعة معلومات التشخيص
                final diagnostics = await telegramService.getDiagnostics();
                print('📊 معلومات تشخيص Telegram:');
                diagnostics.forEach((key, value) => print('   $key: $value'));

                // ابدأ الرفع في مهمة منفصلة وتحديث المؤشر ثم إغلاق الحوار
                Future(() async {
                  try {
                    // متغير لتتبع نجاح إرسال الفواتير لتيليجرام
                    bool allInvoicesSentSuccessfully = true;
                    List<String> errors = [];
                    
                    // 1) رفع قاعدة البيانات إلى Drive و Telegram
                    await context.read<AppProvider>().uploadDatabaseToDrive(
                      onProgress: (p) {
                        progressNotifier.value = p * 0.5; // 50% للرفع الأساسي
                      },
                    );

                    // 2) إرسال الفواتير الجديدة إلى Telegram (إذا كان هناك وقت سابق)
                    if (telegramService.isConfigured && lastUploadTime != null) {
                      statusNotifier.value = 'جاري إرسال الفواتير الجديدة...';
                      final exportService = TelegramInvoiceExportService();
                      final exportResult = await exportService.exportAndSendNewInvoices(
                        afterDate: lastUploadTime,
                        onProgress: (current, total, status) {
                          if (total > 0) {
                            progressNotifier.value = 0.5 + (current / total) * 0.40;
                            statusNotifier.value = status;
                          }
                        },
                      );
                      
                      // التحقق من نجاح إرسال جميع الفواتير
                      if (exportResult.failedCount > 0) {
                        allInvoicesSentSuccessfully = false;
                        errors.add('فشل إرسال ${exportResult.failedCount} فاتورة');
                      }
                    } else if (!telegramService.isConfigured) {
                      errors.add('إعدادات Telegram غير مكتملة');
                    }

                    // 3) إرسال الملخص الشهري إلى Telegram
                    if (telegramService.isConfigured) {
                      statusNotifier.value = 'جاري إرسال الملخص الشهري...';
                      progressNotifier.value = 0.92;
                      final summaryResult = await telegramService.sendMonthlySummaryWithDetails();
                      if (!summaryResult.success) {
                        errors.add('فشل إرسال الملخص الشهري: ${summaryResult.errorMessage}');
                        if (summaryResult.errorDetails != null) {
                          errors.add('التفاصيل: ${summaryResult.errorDetails}');
                        }
                      }
                    }

                    // 4) حفظ وقت الرفع الحالي فقط إذا نجح إرسال جميع الفواتير
                    if (allInvoicesSentSuccessfully && errors.isEmpty) {
                      await telegramService.saveLastUploadTime();
                    }
                    
                    progressNotifier.value = 1.0;
                    
                    if (errors.isNotEmpty) {
                      errorNotifier.value = errors.join('\n');
                      uploadSucceeded = false;
                    } else {
                      uploadSucceeded = true;
                    }
                  } catch (e) {
                    print('Upload error: $e');
                    errorNotifier.value = 'خطأ: $e';
                    uploadSucceeded = false;
                  } finally {
                    if (Navigator.of(context, rootNavigator: true).canPop()) {
                      Navigator.of(context, rootNavigator: true).pop({
                        'success': uploadSucceeded,
                        'error': errorNotifier.value,
                      });
                    }
                  }
                });

                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => AlertDialog(
                    title: const Text('رفع قاعدة البيانات'),
                    content: ValueListenableBuilder<double>(
                      valueListenable: progressNotifier,
                      builder: (context, progress, _) => ValueListenableBuilder<String>(
                        valueListenable: statusNotifier,
                        builder: (context, status, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LinearProgressIndicator(value: progress <= 0 || progress >= 1 ? null : progress),
                            const SizedBox(height: 12),
                            Text('${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%'),
                            const SizedBox(height: 8),
                            Text(status, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );

                if (result?['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('تم رفع قاعدة البيانات وإرسال الفواتير بنجاح'),
                    duration: Duration(seconds: 3),
                  ));
                } else {
                  final errorMsg = result?['error'] as String?;
                  // عرض dialog مفصل للخطأ
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red),
                          SizedBox(width: 8),
                          Text('فشل الإرسال'),
                        ],
                      ),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('حدث خطأ أثناء إرسال البيانات إلى Telegram:',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.withOpacity(0.3)),
                              ),
                              child: Text(
                                errorMsg ?? 'خطأ غير معروف - تحقق من اتصال الإنترنت',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text('الحلول المقترحة:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            const Text('• تأكد من اتصال الإنترنت'),
                            const Text('• تأكد من اختيار القسم الصحيح (كهربائيات/صحيات)'),
                            const Text('• حاول مرة أخرى بعد قليل'),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('حسناً'),
                        ),
                      ],
                    ),
                  );
                }
              },
              color: const Color(0xFF0D47A1),
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),
            _buildFeatureButton(
              icon: Icons.print,
              title: 'الإعدادات',
              onTap: () => Navigator.pushNamed(context, '/general_settings'),
              color: const Color(0xFF607D8B),
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),
            
            _buildFeatureButton(
              icon: Icons.edit_note,
              title: 'تعديل القوائم',
              onTap: () => Navigator.pushNamed(context, '/edit_invoices'),
              color: const Color(0xFF795548),
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),
            _buildFeatureButton(
              icon: Icons.edit,
              title: 'تعديل البضاعة',
              onTap: () => Navigator.pushNamed(context, '/edit_products'),
              color: const Color(0xFF009688),
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),
            _buildFeatureButton(
              icon: Icons.business,
              title: 'المؤسسين',
              onTap: () => Navigator.pushNamed(context, '/installers'),
              color: const Color(0xFFE91E63),
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),
            
            _buildFeatureButton(
              icon: Icons.analytics,
              title: 'التقارير',
              onTap: () async {
                final bool canAccess = await _showPasswordDialog();
                if (canAccess) {
                  Navigator.pushNamed(context, '/reports');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('كلمة السر غير صحيحة.',
                        style: TextStyle(fontSize: 16)),
                  ));
                }
              },
              color: const Color(0xFF673AB7),
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),           
              _buildFeatureButton(
              icon: Icons.factory,
              title: 'الموردون',
              onTap: () => Navigator.pushNamed(context, '/suppliers'),
              color: const Color(0xFF455A64),
              fontSize: buttonFontSize,
              iconSize: iconSize,
              padding: buttonPadding,
              spacing: buttonSpacing,
            ),
          ],
        ),
      ),
    );
  }
}


// Widget مساعد لتأثير Hover على النص
class HoverText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color hoverColor;

  const HoverText({
    super.key,
    required this.text,
    required this.style,
    required this.hoverColor,
  });

  @override
  State<HoverText> createState() => _HoverTextState();
}

class _HoverTextState extends State<HoverText> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Text(
        widget.text,
        textAlign: TextAlign.right,
        style: widget.style.copyWith(
          color: _isHovering ? widget.hoverColor : widget.style.color,
          decoration: _isHovering ? TextDecoration.underline : null,
        ),
      ),
    );
  }
}
