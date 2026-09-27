import 'package:flutter/material.dart';
import '../services/invoice_settings_service.dart';

class InvoiceSettingsScreen extends StatefulWidget {
  const InvoiceSettingsScreen({Key? key}) : super(key: key);

  @override
  State<InvoiceSettingsScreen> createState() => _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends State<InvoiceSettingsScreen> {
  bool _isLoading = true;
  int _deviceId = 1;
  final TextEditingController _headerController = TextEditingController();
  final TextEditingController _footerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _headerController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      _deviceId = await InvoiceSettingsService.getInvoiceDeviceId();
      _headerController.text = await InvoiceSettingsService.getInvoiceHeader();
      _footerController.text = await InvoiceSettingsService.getInvoiceFooter();
    } catch (e) {
      print('Error loading invoice settings: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      await InvoiceSettingsService.setInvoiceDeviceId(_deviceId);
      await InvoiceSettingsService.setInvoiceHeader(_headerController.text);
      await InvoiceSettingsService.setInvoiceFooter(_footerController.text);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ إعدادات الفواتير بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء الحفظ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات الفواتير والمزامنة'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // قسم معرف الجهاز
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.devices, color: Colors.indigo),
                        SizedBox(width: 8),
                        Text(
                          'معرف الجهاز (Device ID)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'هذا الرقم سيميز الفواتير التي ينشئها هذا الجهاز عن بقية الأجهزة. يُفضل أن تضع (1) للحاسوب الرئيسي، و(2) للهاتف الأول، و(3) للهاتف الثاني.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildDeviceCard(1, 'الحاسوب الرئيسي', Icons.computer),
                        _buildDeviceCard(2, 'هاتف المندوب 1', Icons.phone_android),
                        _buildDeviceCard(3, 'هاتف المندوب 2', Icons.phone_iphone),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // إذا أراد المستخدم رقماً أكبر
                    Row(
                      children: [
                        const Text('أو أدخل رقماً يدوياً:'),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            initialValue: _deviceId.toString(),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            onChanged: (val) {
                              final parsed = int.tryParse(val);
                              if (parsed != null && parsed > 0) {
                                setState(() {
                                  _deviceId = parsed;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // قسم إعدادات الطباعة
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.print, color: Colors.indigo),
                        SizedBox(width: 8),
                        Text(
                          'إعدادات طباعة الفواتير',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _headerController,
                      decoration: const InputDecoration(
                        labelText: 'ترويسة الفاتورة (اسم المحل)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.store),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _footerController,
                      decoration: const InputDecoration(
                        labelText: 'تذييل الفاتورة (رسالة الشكر)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.favorite),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 32),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: const Text(
                  'حفظ الإعدادات',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(int id, String label, IconData icon) {
    final isSelected = _deviceId == id;
    return GestureDetector(
      onTap: () {
        setState(() {
          _deviceId = id;
        });
      },
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.indigo : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.indigo : Colors.grey, size: 32),
            const SizedBox(height: 8),
            Text(
              'جهاز ($id)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.indigo : Colors.grey.shade700,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.indigo : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
