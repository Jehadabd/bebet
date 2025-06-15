import 'package:flutter/material.dart';
import '../models/installer.dart';
import '../services/database_service.dart';
import 'installer_details_screen.dart';
import 'add_installer_screen.dart';

class InstallersListScreen extends StatefulWidget {
  const InstallersListScreen({super.key});

  @override
  State<InstallersListScreen> createState() => _InstallersListScreenState();
}

class _InstallersListScreenState extends State<InstallersListScreen> {
  final DatabaseService _db = DatabaseService();
  final TextEditingController _searchController = TextEditingController();
  List<Installer> _installers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInstallers();
  }

  Future<void> _loadInstallers() async {
    setState(() => _isLoading = true);
    try {
      final installers = await _db.getAllInstallers();
      setState(() {
        _installers = installers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل قائمة المؤسسين: $e')),
        );
      }
    }
  }

  Future<void> _searchInstallers(String query) async {
    if (query.isEmpty) {
      await _loadInstallers();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final results = await _db.searchInstallers(query);
      setState(() {
        _installers = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في البحث: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المؤسسين'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'بحث عن مؤسس',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: _searchInstallers,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _installers.isEmpty
                    ? const Center(child: Text('لا يوجد مؤسسين'))
                    : ListView.builder(
                        itemCount: _installers.length,
                        itemBuilder: (context, index) {
                          final installer = _installers[index];
                          return ListTile(
                            title: Text(installer.name),
                            subtitle: Text(
                              'إجمالي المبلغ المفوتر: ${installer.totalBilledAmount.toStringAsFixed(2)} دينار عراقي',
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => InstallerDetailsScreen(
                                    installer: installer,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddInstallerScreen(),
            ),
          ).then((_) => _loadInstallers());
        },
        tooltip: 'إضافة مؤسس جديد',
        child: const Icon(Icons.add),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
} 