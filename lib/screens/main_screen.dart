// screens/main_screen.dart
                    import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import 'package:share_plus/share_plus.dart';
import '../services/database_service.dart';
import '../models/customer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/password_service.dart'; // Import PasswordService
// import 'home_screen.dart'; // No longer needed with named routes
// import 'product_entry_screen.dart'; // No longer needed with named routes
// import 'create_invoice_screen.dart'; // No longer needed with named routes

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String _currentMonthYear = '';
  final PasswordService _passwordService = PasswordService(); // Initialize PasswordService

  @override
  void initState() {
    super.initState();
    _updateCurrentMonthYear();
  }

  void _updateCurrentMonthYear() {
    final now = DateTime.now();
    _currentMonthYear = DateFormat.yMMMM('ar').format(now); // Format current month and year in Arabic
  }

  Future<bool> _showPasswordDialog() async {
    final TextEditingController passwordController = TextEditingController();
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('الرجاء إدخال كلمة السر'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'كلمة السر',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final bool isCorrect = await _passwordService.verifyPassword(passwordController.text);
              Navigator.of(context).pop(isCorrect);
            },
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر ديوني - الشاشة الرئيسية'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to Debt Register Screen
                  // Navigator.push( // Use Navigator.push to go to HomeScreen
                  //   context,
                  //   MaterialPageRoute(builder: (context) => const HomeScreen()),
                  // );
                  Navigator.pushNamed(context, '/debt_register'); // Use named route
                },
                child: const Text('سجل الديون'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to Product Entry Screen
                  Navigator.pushNamed(context, '/product_entry'); // Use named route
                },
                child: const Text('إدخال البضاعة'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to Create Invoice Screen
                  Navigator.pushNamed(context, '/create_invoice'); // Use named route
                },
                child: const Text('إنشاء قائمة'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: () async {
                  final TextEditingController _monthsController = TextEditingController();
                  int? selectedMonths;
                  await showDialog<int>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('أدخل عدد الأشهر'),
                        content: TextField(
                          controller: _monthsController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'على سبيل المثال: 10',
                            labelText: 'عدد الأشهر',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('إلغاء'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              final input = int.tryParse(_monthsController.text);
                              if (input != null && input > 0) {
                                Navigator.of(context).pop(input);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('الرجاء إدخال عدد صحيح موجب للأشهر.')),
                                );
                              }
                            },
                            child: const Text('بحث'),
                          ),
                        ],
                      );
                    },
                  ).then((value) {
                    selectedMonths = value;
                  });

                  if (selectedMonths != null) {
                    final db = DatabaseService();
                    final lateCustomers = await db.getLateCustomers(selectedMonths!);
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('المتأخرون عن السداد ($selectedMonths شهر)'),
                        content: lateCustomers.isEmpty
                            ? const Text('لا يوجد عملاء متأخرون عن السداد لهذا المدى.')
                            : SizedBox(
                                width: double.maxFinite,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: lateCustomers.length,
                                  itemBuilder: (context, i) {
                                    final c = lateCustomers[i];
                                    return ListTile(
                                      title: Text(c.name),
                                      subtitle: Text('العنوان: ${c.address ?? "-"}'),
                                      trailing: Text('الدين: ${c.currentTotalDebt.toStringAsFixed(2)}'),
                                    );
                                  },
                                ),
                              ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('إغلاق'),
                          ),
                        ],
                      ),
                    );
                  }
                },
                child: const Text('المتأخرين عن الديون'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: () async {
                  final db = DatabaseService();
                  final allCustomers = await db.getAllCustomers();
                  // استخرج كل الأشهر التي فيها عملاء
                  final months = <String>{};
                  for (final c in allCustomers) {
                    final dt = c.lastModifiedAt;
                    final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
                    months.add(key);
                  }
                  final sortedMonths = months.toList()..sort((a, b) => b.compareTo(a));
                  String? selectedMonth;
                  await showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        title: const Text('اختر الشهر'),
                        content: SizedBox(
                          width: double.maxFinite,
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: sortedMonths.length,
                            itemBuilder: (context, index) {
                              final m = sortedMonths[index];
                              return ListTile(
                                title: Text('ديون شهر $m'),
                                onTap: () {
                                  selectedMonth = m;
                                  Navigator.of(context).pop();
                                },
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
                    final file = await db.generateMonthlyDebtsPdf(customers, year, month);
                    await Share.shareFiles([file.path], text: 'سجل ديون شهر $selectedMonth');
                    // بعد المشاركة، اعرض Dialog فيه زر لفتح المجلد
                    final dirPath = file.parent.path;
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('مشاركة الملف'),
                        content: const Text('إذا لم يظهر التطبيق المطلوب، يمكنك فتح المجلد وإرسال الملف يدويًا عبر أي تطبيق (بلوتوث، تيليجرام، واتساب...)'),
                        actions: [
                          TextButton(
                            onPressed: () async {
                              final uri = Uri.file(dirPath);
                              await launchUrl(uri);
                            },
                            child: const Text('فتح المجلد'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('إغلاق'),
                          ),
                        ],
                      ),
                    );
                  }
                },
                child: const Text('مشاركة الديون PDF'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/printer_settings');
                },
                child: const Text('إعدادات الطابعة'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.book),
                label: const Text('سجل الديون'),
                onPressed: () {
                  Navigator.pushNamed(context, '/debt_register');
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add_box),
                label: const Text('إدخال البضاعة'),
                onPressed: () {
                  Navigator.pushNamed(context, '/product_entry');
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.playlist_add),
                label: const Text('إنشاء قائمة'),
                onPressed: () {
                  Navigator.pushNamed(context, '/create_invoice');
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text('تعديل القوائم'),
                onPressed: () {
                  Navigator.pushNamed(context, '/edit_invoices');
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('تعديل البضاعة'),
                onPressed: () {
                  Navigator.pushNamed(context, '/edit_products');
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.business),
                label: const Text('المؤسسين'),
                onPressed: () {
                  Navigator.pushNamed(context, '/installers');
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.inventory),
                label: Text('الجرد ($_currentMonthYear)'),
                onPressed: () async {
                  final bool canAccess = await _showPasswordDialog();
                  if (canAccess) {
                    Navigator.pushNamed(context, '/inventory');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('كلمة السر غير صحيحة.')),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
} 