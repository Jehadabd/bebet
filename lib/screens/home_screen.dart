// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../providers/app_provider.dart';
import '../models/customer.dart';
import 'customer_details_screen.dart';
import 'add_customer_screen.dart';
import 'saved_invoices_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<AppProvider>().initialize());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                        label: const Text(
                          'تسجيل الدخول',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        onPressed: () async {
                          try {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'سيتم فتح نافذة تسجيل الدخول إلى Google'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                            await provider.signInToDrive();
                            await provider.isDriveSignedIn();
                            setState(() {});
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'تم تسجيل الدخول بنجاح! يمكنك الآن رفع التقارير إلى Google Drive'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString()),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.logout),
                      tooltip: 'تسجيل الخروج من Google Drive',
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('تسجيل الخروج'),
                            content: const Text(
                                'هل أنت متأكد من تسجيل الخروج من Google Drive؟'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('إلغاء'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('تسجيل الخروج'),
                              ),
                            ],
                          ),
                        );

                        if (confirmed == true) {
                          await provider.signOutFromDrive();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('تم تسجيل الخروج من Google Drive'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                          setState(() {});
                        }
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.cloud_upload),
                    tooltip: provider.isDriveSignedInSync
                        ? 'رفع سجل الديون إلى Google Drive'
                        : 'يجب تسجيل الدخول أولاً',
                    onPressed: provider.isDriveSignedInSync
                        ? () async {
                            try {
                              await provider.uploadDebtRecord();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'تم رفع سجل الديون بنجاح إلى Google Drive'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(e.toString()),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.receipt_long),
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
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'ابحث عن عميل...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: provider.setSearchQuery,
                ),
              ),
              Expanded(
                child: provider.customers.isEmpty
                    ? const Center(
                        child: Text('لا يوجد عملاء'),
                      )
                    : ListView.builder(
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
            child: const Icon(Icons.person_add),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            heroTag: 'main_debt',
            onPressed: () {
              // Already on main screen, maybe refresh or show a message
            },
            tooltip: 'سجل الديون',
            child: const Icon(Icons.book),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            heroTag: 'add_product',
            onPressed: () {
              Navigator.pushNamed(context, '/add_product');
            },
            tooltip: 'إدخال بضاعة',
            child: const Icon(Icons.add_box),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            heroTag: 'installers',
            onPressed: () {
              Navigator.pushNamed(context, '/installers');
            },
            tooltip: 'المؤسسين',
            child: const Icon(Icons.engineering),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            heroTag: 'create_invoice',
            onPressed: () {
              Navigator.pushNamed(context, '/create_invoice');
            },
            tooltip: 'إنشاء قائمة',
            child: const Icon(Icons.playlist_add),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            heroTag: 'edit_invoices',
            onPressed: () {
              Navigator.pushNamed(context, '/edit_invoices');
            },
            tooltip: 'تعديل القوائم',
            child: const Icon(Icons.edit_note),
          ),
          const SizedBox(width: 10),
          FloatingActionButton(
            heroTag: 'edit_products',
            onPressed: () {
              Navigator.pushNamed(context, '/edit_products');
            },
            tooltip: 'تعديل البضاعة',
            child: const Icon(Icons.edit),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        title: Text(
          customer.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          customer.phone ?? 'لا يوجد رقم هاتف',
        ),
        trailing: Text(
          '${customer.currentTotalDebt.toStringAsFixed(2)} دينار',
          style: TextStyle(
            color: customer.currentTotalDebt > 0 ? Colors.red : Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CustomerDetailsScreen(customer: customer),
            ),
          );
        },
      ),
    );
  }
}
