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
                final TextEditingController _monthsController =
                    TextEditingController();
                int? selectedMonths;
                await showDialog<int>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('أدخل عدد الأشهر',
                          style: TextStyle(fontSize: 20)),
                      content: TextField(
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('إلغاء',
                              style: TextStyle(fontSize: 18)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            final input = int.tryParse(_monthsController.text);
                            if (input != null && input > 0) {
                              Navigator.of(context).pop(input);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'الرجاء إدخال عدد صحيح موجب للأشهر.',
                                      style: TextStyle(fontSize: 16)),
                                ),
                              );
                            }
                          },
                          child:
                              const Text('بحث', style: TextStyle(fontSize: 18)),
                        ),
                      ],
                    );
                  },
                ).then((value) {
                  selectedMonths = value;
                });

                if (selectedMonths != null) {
                  final db = DatabaseService();
                  final lateCustomers =
                      await db.getLateCustomers(selectedMonths!);
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('المتأخرون عن السداد ($selectedMonths شهر)',
                          style: const TextStyle(fontSize: 20)),
                      content: lateCustomers.isEmpty
                          ? const Text(
                              'لا يوجد عملاء متأخرون عن السداد لهذا المدى.',
                              style: TextStyle(fontSize: 18))
                          : SizedBox(
                              width: double.maxFinite,
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: lateCustomers.length,
                                itemBuilder: (context, i) {
                                  final c = lateCustomers[i];
                                  return ListTile(
                                    title: Text(c.name,
                                        style: const TextStyle(fontSize: 18)),
                                    subtitle: Text(
                                        'العنوان: ${c.address ?? "-"}',
                                        style: const TextStyle(fontSize: 16)),
                                    trailing: Text(
                                        'الدين: ${c.currentTotalDebt.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                                  );
                                },
                              ),
                            ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('إغلاق',
                              style: TextStyle(fontSize: 18)),
                        ),
                      ],
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
              icon: Icons.share,
              title: 'مشاركة الديون PDF',
              onTap: () async {
                final db = DatabaseService();
                final allCustomers = await db.getAllCustomers();
                final months = <String>{};
                for (final c in allCustomers) {
                  final dt = c.lastModifiedAt;
                  final key =
                      '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
                  months.add(key);
                }
                final sortedMonths = months.toList()
                  ..sort((a, b) => b.compareTo(a));
                String? selectedMonth;
                await showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('اختر الشهر',
                          style: TextStyle(fontSize: 20)),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: sortedMonths.length,
                          itemBuilder: (context, index) {
                            final m = sortedMonths[index];
                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                title: Text('ديون شهر $m',
                                    style: const TextStyle(fontSize: 18)),
                                onTap: () {
                                  selectedMonth = m;
                                  Navigator.of(context).pop();
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
                if (selectedMonth != null) {
                  final parts = selectedMonth!.split('-');
                  final year = int.parse(parts[0]);
                  final month = int.parse(parts[1]);
                  final customers = await db.getCustomersForMonth(year, month);
                  final file =
                      await db.generateMonthlyDebtsPdf(customers, year, month);
                  await Share.shareFiles([file.path],
                      text: 'سجل ديون شهر $selectedMonth');
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('مشاركة الملف',
                          style: TextStyle(fontSize: 20)),
                      content: const Text(
                          'إذا لم يظهر التطبيق المطلوب، يمكنك فتح المجلد وإرسال الملف يدويًا عبر أي تطبيق',
                          style: TextStyle(fontSize: 18)),
                      actions: [
                        TextButton(
                          onPressed: () async {
                            final dirPath = file.parent.path;
                            final uri = Uri.file(dirPath);
                            await launchUrl(uri);
                          },
                          child: const Text('فتح المجلد',
                              style: TextStyle(fontSize: 18)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('إغلاق',
                              style: TextStyle(fontSize: 18)),
                        ),
                      ],
                    ),
                  );
                }
              },
              color: const Color(0xFF9C27B0),
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
              icon: Icons.folder,
              title: 'الجرد الشهري',
              onTap: () async {
                final bool canAccess = await _showPasswordDialog();
                if (canAccess) {
                  Navigator.pushNamed(context, '/inventory');
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('كلمة السر غير صحيحة.',
                        style: TextStyle(fontSize: 16)),
                  ));
                }
              },
              color: _accentColor,
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
