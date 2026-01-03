import 'dart:io';
import 'package:flutter/material.dart';
import '../services/sync/sync_service.dart';
import 'package:alnaser/models/app_settings.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../services/sync/sync_audit_service.dart';
import '../services/password_service.dart';
import '../models/account_statement_item.dart';
import '../services/smart_search/smart_search.dart' as smart_search; // 🧠 البحث الذكي

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  late AppSettings _appSettings;
  final List<TextEditingController> _phoneNumberControllers = [];
  final TextEditingController _companyDescriptionController = TextEditingController();
  
  // ألوان العناصر المختلفة
  Color _remainingAmountColor = Colors.black;
  Color _discountColor = Colors.black;
  Color _loadingFeesColor = Colors.black;
  Color _totalBeforeDiscountColor = Colors.black;
  Color _totalAfterDiscountColor = Colors.black;
  Color _previousDebtColor = Colors.black;
  Color _currentDebtColor = Colors.black;
  Color _electricPhoneColor = Colors.black;
  Color _healthPhoneColor = Colors.black;
  Color _companyDescriptionColor = Colors.black;
  Color _companyNameColor = Colors.green;
  Color _itemSerialColor = Colors.black;
  Color _itemDetailsColor = Colors.black;
  Color _itemQuantityColor = Colors.black;
  Color _itemPriceColor = Colors.black;
  Color _itemTotalColor = Colors.black;
  Color _noticeColor = Colors.red;
  Color _paidAmountColor = Colors.black;
  
  // إعدادات نقاط المؤسسين
  double _pointsPerHundredThousand = 1.0;
  final TextEditingController _pointsController = TextEditingController();
  
  // إعدادات الفاتورة
  bool _autoScrollInvoice = true;
  
  // 🔄 إعدادات المزامنة
  bool _syncFullTransferMode = false;
  bool _syncShowConfirmation = true;
  bool _syncAutoCreateCustomers = true;
  
  // 📱 قسم المحل
  String _storeSection = 'كهربائيات';
  
  // 🏪 اسم الفرع
  String _branchName = 'الفرع الرئيسي';
  
  // 🔐 خدمة كلمة السر
  final PasswordService _passwordService = PasswordService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _appSettings = await SettingsManager.getAppSettings();
    
    // تحميل الألوان
    _remainingAmountColor = Color(_appSettings.remainingAmountColor);
    _discountColor = Color(_appSettings.discountColor);
    _loadingFeesColor = Color(_appSettings.loadingFeesColor);
    _totalBeforeDiscountColor = Color(_appSettings.totalBeforeDiscountColor);
    _totalAfterDiscountColor = Color(_appSettings.totalAfterDiscountColor);
    _previousDebtColor = Color(_appSettings.previousDebtColor);
    _currentDebtColor = Color(_appSettings.currentDebtColor);
    _electricPhoneColor = Color(_appSettings.electricPhoneColor);
    _healthPhoneColor = Color(_appSettings.healthPhoneColor);
    _companyDescriptionColor = Color(_appSettings.companyDescriptionColor);
    _companyNameColor = Color(_appSettings.companyNameColor);
    _itemSerialColor = Color(_appSettings.itemSerialColor);
    _itemDetailsColor = Color(_appSettings.itemDetailsColor);
    _itemQuantityColor = Color(_appSettings.itemQuantityColor);
    _itemPriceColor = Color(_appSettings.itemPriceColor);
    _itemTotalColor = Color(_appSettings.itemTotalColor);
    _noticeColor = Color(_appSettings.noticeColor);
    _paidAmountColor = Color(_appSettings.paidAmountColor);
    
    // تحميل إعدادات نقاط المؤسسين
    _pointsPerHundredThousand = _appSettings.pointsPerHundredThousand;
    _pointsController.text = _pointsPerHundredThousand.toString();
    
    // تحميل إعدادات الفاتورة
    _autoScrollInvoice = _appSettings.autoScrollInvoice;
    
    // تحميل إعدادات المزامنة
    _syncFullTransferMode = _appSettings.syncFullTransferMode;
    _syncShowConfirmation = _appSettings.syncShowConfirmation;
    _syncAutoCreateCustomers = _appSettings.syncAutoCreateCustomers;
    
    // تحميل قسم المحل
    _storeSection = _appSettings.storeSection;
    
    // تحميل اسم الفرع
    _branchName = _appSettings.branchName;
    
    // تحميل وصف الشركة
    _companyDescriptionController.text = _appSettings.companyDescription;
    
    // تحميل أرقام الهواتف
    _phoneNumberControllers.clear();
    for (var number in _appSettings.phoneNumbers) {
      _phoneNumberControllers.add(TextEditingController(text: number));
    }
    if (_phoneNumberControllers.isEmpty) {
      _phoneNumberControllers.add(TextEditingController());
    }
    setState(() {});
  }

  Future<void> _saveSettings() async {
    final newPhoneNumbers = _phoneNumberControllers
        .map((controller) => controller.text)
        .where((text) => text.isNotEmpty)
        .toList();

    _appSettings = _appSettings.copyWith(
      phoneNumbers: newPhoneNumbers,
      remainingAmountColor: _remainingAmountColor.value,
      discountColor: _discountColor.value,
      loadingFeesColor: _loadingFeesColor.value,
      totalBeforeDiscountColor: _totalBeforeDiscountColor.value,
      totalAfterDiscountColor: _totalAfterDiscountColor.value,
      previousDebtColor: _previousDebtColor.value,
      currentDebtColor: _currentDebtColor.value,
      electricPhoneColor: _electricPhoneColor.value,
      healthPhoneColor: _healthPhoneColor.value,
      companyDescriptionColor: _companyDescriptionColor.value,
      companyDescription: _companyDescriptionController.text,
      companyNameColor: _companyNameColor.value,
      itemSerialColor: _itemSerialColor.value,
      itemDetailsColor: _itemDetailsColor.value,
      itemQuantityColor: _itemQuantityColor.value,
      itemPriceColor: _itemPriceColor.value,
      itemTotalColor: _itemTotalColor.value,
      noticeColor: _noticeColor.value,
      paidAmountColor: _paidAmountColor.value,
      pointsPerHundredThousand: _pointsPerHundredThousand,
      autoScrollInvoice: _autoScrollInvoice,
      syncFullTransferMode: _syncFullTransferMode,
      syncShowConfirmation: _syncShowConfirmation,
      syncAutoCreateCustomers: _syncAutoCreateCustomers,
      storeSection: _storeSection,
      branchName: _branchName,
    );
    await SettingsManager.saveAppSettings(_appSettings);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات بنجاح')),
      );
    }
  }

  void _addPhoneNumberField() {
    setState(() {
      _phoneNumberControllers.add(TextEditingController());
    });
  }

  void _removePhoneNumberField(int index) {
    setState(() {
      _phoneNumberControllers[index].dispose();
      _phoneNumberControllers.removeAt(index);
    });
  }

  void _pickColor(String colorType) {
    Color currentColor;
    switch (colorType) {
      case 'remainingAmount':
        currentColor = _remainingAmountColor;
        break;
      case 'discount':
        currentColor = _discountColor;
        break;
      case 'loadingFees':
        currentColor = _loadingFeesColor;
        break;
      case 'totalBeforeDiscount':
        currentColor = _totalBeforeDiscountColor;
        break;
      case 'totalAfterDiscount':
        currentColor = _totalAfterDiscountColor;
        break;
      case 'previousDebt':
        currentColor = _previousDebtColor;
        break;
      case 'currentDebt':
        currentColor = _currentDebtColor;
        break;
      case 'electricPhone':
        currentColor = _electricPhoneColor;
        break;
      case 'healthPhone':
        currentColor = _healthPhoneColor;
        break;
      case 'companyDescription':
        currentColor = _companyDescriptionColor;
        break;
      case 'companyName':
        currentColor = _companyNameColor;
        break;
      case 'itemSerial':
        currentColor = _itemSerialColor;
        break;
      case 'itemDetails':
        currentColor = _itemDetailsColor;
        break;
      case 'itemQuantity':
        currentColor = _itemQuantityColor;
        break;
      case 'itemPrice':
        currentColor = _itemPriceColor;
        break;
      case 'itemTotal':
        currentColor = _itemTotalColor;
        break;
      case 'notice':
        currentColor = _noticeColor;
        break;
      case 'paidAmount':
        currentColor = _paidAmountColor;
        break;
      default:
        currentColor = Colors.black;
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        Color tempColor = currentColor;
        return AlertDialog(
          title: Text('اختر لون $colorType'),
          content: SingleChildScrollView(
            child: BlockPicker(
              pickerColor: currentColor,
              onColorChanged: (color) {
                tempColor = color;
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('إلغاء'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('حفظ'),
              onPressed: () {
                setState(() {
                  switch (colorType) {
                    case 'remainingAmount':
                      _remainingAmountColor = tempColor;
                      break;
                    case 'discount':
                      _discountColor = tempColor;
                      break;
                    case 'loadingFees':
                      _loadingFeesColor = tempColor;
                      break;
                    case 'totalBeforeDiscount':
                      _totalBeforeDiscountColor = tempColor;
                      break;
                    case 'totalAfterDiscount':
                      _totalAfterDiscountColor = tempColor;
                      break;
                    case 'previousDebt':
                      _previousDebtColor = tempColor;
                      break;
                    case 'currentDebt':
                      _currentDebtColor = tempColor;
                      break;
                    case 'electricPhone':
                      _electricPhoneColor = tempColor;
                      break;
                    case 'healthPhone':
                      _healthPhoneColor = tempColor;
                      break;
                    case 'companyDescription':
                      _companyDescriptionColor = tempColor;
                      break;
                    case 'companyName':
                      _companyNameColor = tempColor;
                      break;
                    case 'itemSerial':
                      _itemSerialColor = tempColor;
                      break;
                    case 'itemDetails':
                      _itemDetailsColor = tempColor;
                      break;
                    case 'itemQuantity':
                      _itemQuantityColor = tempColor;
                      break;
                    case 'itemPrice':
                      _itemPriceColor = tempColor;
                      break;
                    case 'itemTotal':
                      _itemTotalColor = tempColor;
                      break;
                    case 'notice':
                      _noticeColor = tempColor;
                      break;
                    case 'paidAmount':
                      _paidAmountColor = tempColor;
                      break;
                  }
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    for (var controller in _phoneNumberControllers) {
      controller.dispose();
    }
    _companyDescriptionController.dispose();
    _pointsController.dispose();
    super.dispose();
  }

  /// دالة لعرض حوار تأكيد محمي بكلمة سر
  Future<bool> _showProtectedChangeDialog({
    required String title,
    required String message,
  }) async {
    // أولاً: عرض رسالة التحذير
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('متابعة', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return false;
    
    // ثانياً: طلب كلمة السر
    final passwordController = TextEditingController();
    final passwordConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock, color: Colors.deepPurple, size: 28),
            SizedBox(width: 8),
            Text('أدخل كلمة السر', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'كلمة السر',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.lock_outline),
          ),
          onSubmitted: (value) async {
            final isCorrect = await _passwordService.verifyPassword(value);
            Navigator.of(context).pop(isCorrect);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final isCorrect = await _passwordService.verifyPassword(passwordController.text);
              Navigator.of(context).pop(isCorrect);
            },
            child: const Text('تأكيد', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
    
    if (passwordConfirmed != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('كلمة السر غير صحيحة'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
    
    return true;
  }

  static const Color primaryColor = Color(0xFF3F51B5);

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
      onTap: onTap,
    );
  }

  Widget _buildColorTile(String title, Color color, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      trailing: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade300, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      onTap: onTap,
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget child,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات العامة'),
        centerTitle: true,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'حفظ الإعدادات',
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          
          // 📱 قسم المحل
          _buildSettingsCard(
            icon: Icons.store,
            iconColor: Colors.deepPurple,
            title: 'قسم المحل والفرع',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'اختر القسم لتحديد قناة Telegram للنسخ الاحتياطي',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _storeSection,
                  decoration: InputDecoration(
                    labelText: 'قسم المحل',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: primaryColor, width: 2),
                    ),
                    prefixIcon: Icon(
                      _storeSection == 'كهربائيات' ? Icons.electrical_services : Icons.plumbing,
                      color: _storeSection == 'كهربائيات' ? Colors.amber : Colors.blue,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'كهربائيات',
                      child: Row(
                        children: [
                          Icon(Icons.electrical_services, color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Text('كهربائيات'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'صحيات',
                      child: Row(
                        children: [
                          Icon(Icons.plumbing, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text('صحيات'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value != null && value != _storeSection) {
                      // طلب تأكيد وكلمة سر
                      final confirmed = await _showProtectedChangeDialog(
                        title: 'تغيير قسم المحل',
                        message: 'هل أنت متأكد من تغيير القسم من "$_storeSection" إلى "$value"؟\n\nسيؤثر هذا على قناة Telegram التي يتم إرسال النسخ الاحتياطية إليها.',
                      );
                      if (confirmed) {
                        setState(() {
                          _storeSection = value;
                        });
                      }
                    }
                  },
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _storeSection == 'كهربائيات' ? Colors.amber[50] : Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: _storeSection == 'كهربائيات' ? Colors.amber[700] : Colors.blue[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _storeSection == 'كهربائيات'
                              ? 'سيتم إرسال النسخ الاحتياطية إلى قناة: قاعدة بيانات الناصر'
                              : 'سيتم إرسال النسخ الاحتياطية إلى قناة: قاعدة بيانات الناصر (الصحيات)',
                          style: TextStyle(
                            fontSize: 11,
                            color: _storeSection == 'كهربائيات' ? Colors.amber[800] : Colors.blue[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'اختر الفرع لتمييز ملفات الرفع',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _branchName,
                  decoration: InputDecoration(
                    labelText: 'اسم الفرع',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: primaryColor, width: 2),
                    ),
                    prefixIcon: const Icon(Icons.business, color: Colors.deepPurple),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'الفرع الرئيسي',
                      child: Row(
                        children: [
                          Icon(Icons.home_work, color: Colors.green, size: 20),
                          SizedBox(width: 8),
                          Text('الفرع الرئيسي'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'الفرع الثاني',
                      child: Row(
                        children: [
                          Icon(Icons.store, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Text('الفرع الثاني'),
                        ],
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'الفرع الثالث',
                      child: Row(
                        children: [
                          Icon(Icons.storefront, color: Colors.purple, size: 20),
                          SizedBox(width: 8),
                          Text('الفرع الثالث'),
                        ],
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value != null && value != _branchName) {
                      // طلب تأكيد وكلمة سر
                      final confirmed = await _showProtectedChangeDialog(
                        title: 'تغيير اسم الفرع',
                        message: 'هل أنت متأكد من تغيير الفرع من "$_branchName" إلى "$value"؟\n\nسيؤثر هذا على اسم ملفات النسخ الاحتياطي وسجل الديون.',
                      );
                      if (confirmed) {
                        setState(() {
                          _branchName = value;
                        });
                      }
                    }
                  },
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.deepPurple[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'سيتم إضافة "$_branchName" إلى اسم ملفات النسخ الاحتياطي وسجل الديون',
                          style: TextStyle(fontSize: 11, color: Colors.deepPurple[800]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          _buildSettingsCard(
            icon: Icons.phone,
            iconColor: Colors.green,
            title: 'أرقام الهواتف',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._phoneNumberControllers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final controller = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText: 'رقم الهاتف ${index + 1}',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: primaryColor, width: 2),
                              ),
                            ),
                          ),
                        ),
                        if (_phoneNumberControllers.length > 1)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () => _removePhoneNumberField(index),
                          ),
                      ],
                    ),
                  );
                }).toList(),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, color: primaryColor),
                    label: const Text('إضافة رقم هاتف', style: TextStyle(color: primaryColor)),
                    onPressed: _addPhoneNumberField,
                  ),
                ),
              ],
            ),
          ),
          // وصف الشركة
          _buildSettingsCard(
            icon: Icons.business,
            iconColor: primaryColor,
            title: 'وصف الشركة',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _companyDescriptionController,
                  decoration: InputDecoration(
                    labelText: 'وصف الشركة',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: primaryColor, width: 2),
                    ),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                _buildColorTile('لون اسم الشركة (الناصر)', _companyNameColor, () => _pickColor('companyName')),
                _buildColorTile('لون وصف الشركة', _companyDescriptionColor, () => _pickColor('companyDescription')),
              ],
            ),
          ),
          
          // ألوان عناصر الفاتورة
          _buildSettingsCard(
            icon: Icons.receipt_long,
            iconColor: Colors.blue,
            title: 'ألوان عناصر الفاتورة',
            child: Column(
              children: [
                _buildColorTile('المبلغ المتبقي', _remainingAmountColor, () => _pickColor('remainingAmount')),
                _buildColorTile('الخصم', _discountColor, () => _pickColor('discount')),
                _buildColorTile('الإجمالي قبل الخصم', _totalBeforeDiscountColor, () => _pickColor('totalBeforeDiscount')),
                _buildColorTile('الإجمالي بعد الخصم', _totalAfterDiscountColor, () => _pickColor('totalAfterDiscount')),
                _buildColorTile('أجور التحميل', _loadingFeesColor, () => _pickColor('loadingFees')),
                _buildColorTile('الدين السابق', _previousDebtColor, () => _pickColor('previousDebt')),
                _buildColorTile('الدين الحالي', _currentDebtColor, () => _pickColor('currentDebt')),
                _buildColorTile('المبلغ المدفوع', _paidAmountColor, () => _pickColor('paidAmount')),
              ],
            ),
          ),
          
          // ألوان أرقام الهواتف
          _buildSettingsCard(
            icon: Icons.phone_android,
            iconColor: Colors.orange,
            title: 'ألوان أرقام الهواتف',
            child: Column(
              children: [
                _buildColorTile('أرقام الكهربائيات', _electricPhoneColor, () => _pickColor('electricPhone')),
                _buildColorTile('أرقام الصحيات', _healthPhoneColor, () => _pickColor('healthPhone')),
              ],
            ),
          ),
          
          // ألوان عناصر الجدول
          _buildSettingsCard(
            icon: Icons.table_chart,
            iconColor: Colors.purple,
            title: 'ألوان عناصر الجدول',
            child: Column(
              children: [
                _buildColorTile('التسلسل', _itemSerialColor, () => _pickColor('itemSerial')),
                _buildColorTile('التفاصيل (أسماء المواد)', _itemDetailsColor, () => _pickColor('itemDetails')),
                _buildColorTile('العدد', _itemQuantityColor, () => _pickColor('itemQuantity')),
                _buildColorTile('السعر', _itemPriceColor, () => _pickColor('itemPrice')),
                _buildColorTile('المبلغ', _itemTotalColor, () => _pickColor('itemTotal')),
              ],
            ),
          ),
          
          // ألوان أخرى
          _buildSettingsCard(
            icon: Icons.color_lens,
            iconColor: Colors.red,
            title: 'ألوان أخرى',
            child: Column(
              children: [
                _buildColorTile('التنويه', _noticeColor, () => _pickColor('notice')),
              ],
            ),
          ),
          
          // 📝 إعدادات الفاتورة
          _buildSettingsCard(
            icon: Icons.receipt_long,
            iconColor: Colors.indigo,
            title: 'إعدادات الفاتورة',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('التمرير التلقائي مع الفاتورة'),
                  subtitle: Text(
                    'عند إضافة عنصر جديد، تتمرر الشاشة تلقائياً لإظهار الصف الجديد والمجاميع',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  value: _autoScrollInvoice,
                  activeColor: primaryColor,
                  onChanged: (value) {
                    setState(() {
                      _autoScrollInvoice = value;
                    });
                  },
                ),
              ],
            ),
          ),
          
          // 🔄 إعدادات المزامنة
          _buildSettingsCard(
            icon: Icons.sync,
            iconColor: Colors.teal,
            title: 'إعدادات المزامنة',
            child: Column(
              children: [
                // 🔥 مزامنة Firebase الفورية
                _buildActionTile(
                  icon: Icons.cloud_sync,
                  iconColor: Colors.deepOrange,
                  title: 'مزامنة Firebase الفورية',
                  subtitle: 'مزامنة تلقائية في الخلفية بين الأجهزة',
                  onTap: () => Navigator.pushNamed(context, '/firebase_sync_settings'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('وضع النقل الكامل'),
                  subtitle: Text(
                    'عند التفعيل، يتم رفع جميع البيانات عند المزامنة (للنقل لجهاز جديد)',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  value: _syncFullTransferMode,
                  activeColor: Colors.teal,
                  onChanged: (value) async {
                    if (value) {
                      // بدء النقل الكامل فوراً
                      await _startFullTransfer();
                    } else {
                      setState(() => _syncFullTransferMode = false);
                    }
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إظهار رسالة تأكيد قبل المزامنة'),
                  subtitle: Text(
                    'عرض ملخص العمليات قبل بدء المزامنة',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  value: _syncShowConfirmation,
                  activeColor: Colors.teal,
                  onChanged: (value) {
                    setState(() => _syncShowConfirmation = value);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('إنشاء العملاء تلقائياً'),
                  subtitle: Text(
                    'عند استلام معاملة لعميل غير موجود، يتم إنشاؤه تلقائياً',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  value: _syncAutoCreateCustomers,
                  activeColor: Colors.teal,
                  onChanged: (value) {
                    setState(() => _syncAutoCreateCustomers = value);
                  },
                ),
                const Divider(height: 16),
                // 🔓 أدوات القفل
                _buildActionTile(
                  icon: Icons.lock_open,
                  iconColor: Colors.orange,
                  title: 'فحص حالة القفل',
                  subtitle: 'التحقق من حالة قفل المزامنة الحالي',
                  onTap: () => _checkLockStatus(),
                ),
                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.lock_reset,
                  iconColor: Colors.red,
                  title: 'فرض فتح القفل',
                  subtitle: 'استخدم هذا إذا علقت المزامنة بسبب قفل من جهاز آخر',
                  onTap: () => _forceReleaseLock(),
                ),
              ],
            ),
          ),
          
          // ⭐ إعدادات نقاط المؤسسين
          _buildSettingsCard(
            icon: Icons.star,
            iconColor: Colors.amber,
            title: 'إعدادات نقاط المؤسسين',
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      flex: 2,
                      child: Text('عدد النقاط لكل 100,000:', style: TextStyle(fontSize: 14)),
                    ),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _pointsController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: primaryColor, width: 2),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          hintText: '1.0',
                        ),
                        onChanged: (value) {
                          final parsed = double.tryParse(value);
                          if (parsed != null && parsed > 0) {
                            setState(() {
                              _pointsPerHundredThousand = parsed;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'مثال: إذا كانت القيمة 1.5، فاتورة بـ 200,000 = 3 نقاط',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          
          // 🧠 البحث الذكي
          _buildSettingsCard(
            icon: Icons.psychology,
            iconColor: Colors.deepPurple,
            title: 'البحث الذكي (AI)',
            child: Column(
              children: [
                _buildActionTile(
                  icon: Icons.model_training,
                  iconColor: Colors.purple,
                  title: 'تدريب البحث الذكي',
                  subtitle: 'تدريب النظام على جميع الفواتير السابقة',
                  onTap: () => _trainSmartSearch(),
                ),
                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.info_outline,
                  iconColor: Colors.blue,
                  title: 'إحصائيات التدريب',
                  subtitle: 'عرض معلومات آخر تدريب',
                  onTap: () => _showSmartSearchStats(),
                ),
                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.label,
                  iconColor: Colors.teal,
                  title: 'إدارة الماركات',
                  subtitle: 'عرض وإضافة وحذف الماركات المكتشفة',
                  onTap: () => _showBrandsManagement(),
                ),
              ],
            ),
          ),
          
          // 🛡️ أدوات الحماية والتدقيق المالي
          _buildSettingsCard(
            icon: Icons.verified_user,
            iconColor: Colors.green,
            title: 'أدوات الحماية والتدقيق المالي',
            child: Column(
              children: [
                _buildActionTile(
                  icon: Icons.fact_check,
                  iconColor: Colors.blue,
                  title: 'فحص شامل لجميع العملاء',
                  subtitle: 'التحقق من سلامة جميع البيانات المالية',
                  onTap: () => _runFullIntegrityCheck(),
                ),
                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.analytics,
                  iconColor: Colors.purple,
                  title: 'ملخص مالي سريع',
                  subtitle: 'عرض إحصائيات مالية عامة',
                  onTap: () => _showFinancialSummary(),
                ),
                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.history,
                  iconColor: Colors.indigo,
                  title: 'سجل المزامنات',
                  subtitle: 'عرض تاريخ عمليات المزامنة والنسخ الاحتياطية',
                  onTap: () => _showSyncAuditLog(),
                ),
                const Divider(height: 1),
                _buildActionTile(
                  icon: Icons.share,
                  iconColor: Colors.teal,
                  title: 'مشاركة كشوفات الحساب',
                  subtitle: 'إنشاء ملف PDF لجميع كشوفات العملاء',
                  onTap: () => _shareAllAccountStatements(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 🧠 دالة تدريب البحث الذكي
  Future<void> _trainSmartSearch() async {
    // تأكيد من المستخدم
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.psychology, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('تدريب البحث الذكي'),
          ],
        ),
        content: const Text(
          'سيقوم النظام بقراءة جميع الفواتير السابقة وتعلم:\n\n'
          '• تفضيلات العملاء للعلامات التجارية\n'
          '• تفضيلات المُركّبين\n'
          '• المنتجات التي تُشترى معاً\n\n'
          'قد يستغرق هذا بضع ثوانٍ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: const Text('بدء التدريب'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // عرض مؤشر التقدم
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('جاري التدريب على الفواتير...'),
            SizedBox(height: 8),
            Text(
              'يرجى الانتظار',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    try {
      final stats = await smart_search.SmartSearchService.instance.trainOnAllInvoices(
        onProgress: (current, total, message) {
          print('🧠 $message ($current/$total)');
        },
      );

      if (mounted) Navigator.pop(context);

      if (!mounted) return;

      // عرض النتائج
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('اكتمل التدريب'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatRow('📄 الفواتير', '${stats.totalInvoices}'),
              _buildStatRow('📦 الأصناف', '${stats.totalItems}'),
              _buildStatRow('🔗 العلاقات', '${stats.totalAssociations}'),
              _buildStatRow('👥 تفضيلات العملاء', '${stats.totalCustomerPreferences}'),
              _buildStatRow('🔧 تفضيلات المُركّبين', '${stats.totalInstallerPreferences}'),
              _buildStatRow('🏷️ العلامات التجارية', '${stats.uniqueBrands}'),
              _buildStatRow('⏱️ وقت التدريب', '${stats.trainingDuration.inSeconds} ثانية'),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في التدريب: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🧠 دالة عرض إحصائيات البحث الذكي
  Future<void> _showSmartSearchStats() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري تحميل الإحصائيات...'),
          ],
        ),
      ),
    );

    try {
      final stats = await smart_search.SmartSearchService.instance.getTrainingStats();

      if (mounted) Navigator.pop(context);

      if (!mounted) return;

      if (stats == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لم يتم تدريب النظام بعد. اضغط على "تدريب البحث الذكي" أولاً.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue),
              SizedBox(width: 8),
              Text('إحصائيات البحث الذكي'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatRow('📄 الفواتير', '${stats.totalInvoices}'),
              _buildStatRow('📦 الأصناف', '${stats.totalItems}'),
              _buildStatRow('🔗 العلاقات', '${stats.totalAssociations}'),
              _buildStatRow('👥 تفضيلات العملاء', '${stats.totalCustomerPreferences}'),
              _buildStatRow('🔧 تفضيلات المُركّبين', '${stats.totalInstallerPreferences}'),
              _buildStatRow('🏷️ العلامات التجارية', '${stats.uniqueBrands}'),
              const Divider(),
              _buildStatRow('📅 آخر تدريب', _formatDate(stats.trainedAt)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  // 🏷️ دالة إدارة الماركات
  Future<void> _showBrandsManagement() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري تحميل الماركات...'),
          ],
        ),
      ),
    );

    try {
      final brands = await smart_search.SmartSearchService.instance.getAllBrandsWithCount();
      
      if (mounted) Navigator.pop(context);
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => _BrandsManagementDialog(brands: brands),
      );
      
      // إعادة تحميل الماركات بعد الإغلاق
      await smart_search.SmartSearchService.instance.loadAutoDiscoveredBrands();
      
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🛡️ دالة الفحص الشامل
  Future<void> _runFullIntegrityCheck() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري فحص جميع العملاء...'),
          ],
        ),
      ),
    );

    try {
      final db = DatabaseService();
      final reports = await db.verifyAllCustomersFinancialIntegrity();
      
      if (mounted) Navigator.pop(context);
      
      final healthyCount = reports.where((r) => r.isHealthy).length;
      final issueCount = reports.where((r) => !r.isHealthy).length;
      final warningCount = reports.where((r) => r.warnings.isNotEmpty).length;
      final invoiceIssueCount = reports.fold<int>(0, (sum, r) => sum + r.invoiceIssues.length);
      
      if (!mounted) return;
      
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                issueCount == 0 ? Icons.check_circle : Icons.warning,
                color: issueCount == 0 ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              const Text('نتيجة الفحص الشامل'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي العملاء:'),
                            Text('${reports.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('✅ سليم:'),
                            Text('$healthyCount', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('❌ يحتاج إصلاح:'),
                            Text('$issueCount', style: TextStyle(fontWeight: FontWeight.bold, color: issueCount > 0 ? Colors.red : Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('⚠️ تحذيرات:'),
                            Text('$warningCount', style: TextStyle(fontWeight: FontWeight.bold, color: warningCount > 0 ? Colors.orange : Colors.green)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('🧾 مشاكل فواتير:'),
                            Text('$invoiceIssueCount', style: TextStyle(fontWeight: FontWeight.bold, color: invoiceIssueCount > 0 ? Colors.red : Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                if (issueCount == 0 && warningCount == 0 && invoiceIssueCount == 0) ...[
                  const SizedBox(height: 16),
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
                            '🎉 جميع البيانات المالية سليمة 100%!',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // عرض العملاء الذين لديهم مشاكل
                if (issueCount > 0) ...[
                  const SizedBox(height: 16),
                  const Text('العملاء الذين لديهم مشاكل:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange, size: 16),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'للإصلاح: اذهب لسجل الديون ← اختر العميل ← اضغط زر فحص السلامة المالية 🛡️',
                            style: TextStyle(fontSize: 11, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // عرض العملاء غير السليمين (سواء لديهم issues أو لا)
                  ...reports.where((r) => !r.isHealthy).take(15).map((r) {
                    // تحديد نص المشكلة
                    String issueText = '';
                    if (r.invoiceIssues.isNotEmpty) {
                      // إذا كانت المشكلة في الفواتير، نعرض تفاصيل أكثر
                      issueText = '${r.invoiceIssues.length} فاتورة بها مشكلة';
                    } else if (r.issues.isNotEmpty) {
                      issueText = r.issues.first;
                    } else if (r.calculatedBalance != r.recordedBalance) {
                      issueText = 'الرصيد المسجل (${r.recordedBalance.toStringAsFixed(0)}) ≠ المحسوب (${r.calculatedBalance.toStringAsFixed(0)})';
                    } else {
                      issueText = 'مشكلة في البيانات';
                    }
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('• ${r.customerName}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red)),
                          Text('  $issueText', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                          // عرض تفاصيل مشاكل الفواتير
                          if (r.invoiceIssues.isNotEmpty)
                            ...r.invoiceIssues.take(3).map((inv) => Padding(
                              padding: const EdgeInsets.only(right: 16, top: 2),
                              child: Text(
                                '📄 فاتورة #${inv.invoiceId}: فرق ${inv.difference.toStringAsFixed(0)} دينار',
                                style: TextStyle(fontSize: 10, color: Colors.red[400]),
                              ),
                            )),
                          if (r.invoiceIssues.length > 3)
                            Padding(
                              padding: const EdgeInsets.only(right: 16, top: 2),
                              child: Text(
                                '... و ${r.invoiceIssues.length - 3} فواتير أخرى',
                                style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  if (issueCount > 15)
                    Text('... و ${issueCount - 15} عملاء آخرين', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                ],
                
                // عرض العملاء الذين لديهم تحذيرات (فقط إذا لم تكن هناك مشاكل)
                if (warningCount > 0 && issueCount == 0) ...[
                  const SizedBox(height: 16),
                  const Text('عملاء لديهم تحذيرات:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 8),
                  ...reports.where((r) => r.warnings.isNotEmpty).take(10).map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ${r.customerName}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange)),
                        Text('  ${r.warnings.first}', style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                      ],
                    ),
                  )),
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
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 📦 دالة بدء النقل الكامل فوراً
  Future<void> _startFullTransfer() async {
    // التحقق من اتصال الإنترنت
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ لا يوجد اتصال بالإنترنت'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ لا يوجد اتصال بالإنترنت'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    
    // متغير لتتبع حالة الـ Dialog
    bool dialogOpen = false;
    
    // إظهار مؤشر التحميل
    if (mounted) {
      dialogOpen = true;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('جاري رفع البيانات للمزامنة...')),
            ],
          ),
        ),
      );
    }
    
    // دالة مساعدة لإغلاق الـ Dialog بأمان
    void closeDialog() {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
    
    try {
      // تفعيل وضع النقل الكامل وحفظه
      setState(() => _syncFullTransferMode = true);
      await _saveSettings();
      
      print('📦 بدء النقل الكامل...');
      
      // الحصول على خدمة المزامنة وتنفيذ النقل
      final syncService = await _getSyncService();
      if (syncService != null) {
        print('📦 خدمة المزامنة جاهزة، جاري تنفيذ النقل...');
        final result = await syncService.performFullTransfer();
        print('📦 انتهى النقل: success=${result.success}, uploaded=${result.uploaded}');
        
        // إغلاق مؤشر التحميل
        closeDialog();
        
        // تحديث الحالة
        setState(() => _syncFullTransferMode = false);
        await _saveSettings();
        
        if (result.success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ تم رفع ${result.uploaded} عميل بنجاح'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ فشل النقل: ${result.error ?? "خطأ غير معروف"}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
      } else {
        closeDialog();
        setState(() => _syncFullTransferMode = false);
        await _saveSettings();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ خدمة المزامنة غير متاحة - تأكد من تسجيل الدخول'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('📦 خطأ في النقل الكامل: $e');
      closeDialog();
      setState(() => _syncFullTransferMode = false);
      await _saveSettings();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // الحصول على خدمة المزامنة
  Future<SyncService?> _getSyncService() async {
    try {
      final syncService = SyncService();
      await syncService.initialize();
      return syncService;
    } catch (e) {
      print('❌ فشل الحصول على خدمة المزامنة: $e');
      return null;
    }
  }

  // 🔓 فحص حالة القفل
  Future<void> _checkLockStatus() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري فحص حالة القفل...'),
          ],
        ),
      ),
    );

    try {
      final syncService = await _getSyncService();
      if (syncService == null) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ فشل الاتصال بخدمة المزامنة'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final status = await syncService.checkLockStatus();
      if (mounted) Navigator.pop(context);

      if (status == null || status.containsKey('error')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ خطأ: ${status?['error'] ?? 'غير معروف'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      final lockStatus = status['status'] as String;
      final isFree = lockStatus == 'free';
      final isExpired = lockStatus == 'expired';
      final isMine = status['is_mine'] as bool? ?? false;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isFree ? Icons.lock_open : (isExpired ? Icons.lock_clock : Icons.lock),
                color: isFree ? Colors.green : (isExpired ? Colors.orange : Colors.red),
              ),
              const SizedBox(width: 8),
              const Text('حالة القفل'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: isFree ? Colors.green[50] : (isExpired ? Colors.orange[50] : Colors.red[50]),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('الحالة: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(
                            status['message'] as String? ?? 'غير معروف',
                            style: TextStyle(
                              color: isFree ? Colors.green : (isExpired ? Colors.orange : Colors.red),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (!isFree) ...[
                        const SizedBox(height: 8),
                        Text('الجهاز: ${status['device_name'] ?? 'غير معروف'}'),
                        const SizedBox(height: 4),
                        Text('هل هو جهازي: ${isMine ? 'نعم ✅' : 'لا ❌'}'),
                        const SizedBox(height: 4),
                        Text('عمر الـ heartbeat: ${status['heartbeat_age_seconds'] ?? 0} ثانية'),
                        const SizedBox(height: 4),
                        Text('الوقت المتبقي: ${status['remaining_seconds'] ?? 0} ثانية'),
                      ],
                    ],
                  ),
                ),
              ),
              if (!isFree && !isMine) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isExpired || (status['heartbeat_age_seconds'] as int? ?? 0) > 60
                              ? 'يبدو أن الجهاز الآخر توقف. يمكنك فرض فتح القفل.'
                              : 'انتظر حتى ينتهي الجهاز الآخر من المزامنة.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (!isFree && (isExpired || (status['heartbeat_age_seconds'] as int? ?? 0) > 60))
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _forceReleaseLock();
                },
                child: const Text('فرض فتح القفل', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🔓 فرض فتح القفل
  Future<void> _forceReleaseLock() async {
    // تأكيد من المستخدم
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('تأكيد فرض فتح القفل'),
          ],
        ),
        content: const Text(
          'هل أنت متأكد من فرض فتح القفل؟\n\n'
          '⚠️ تحذير: إذا كان جهاز آخر يقوم بالمزامنة حالياً، '
          'قد يؤدي هذا إلى تعارض في البيانات.\n\n'
          'استخدم هذا الخيار فقط إذا كنت متأكداً أن الجهاز الآخر توقف.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('فرض فتح القفل', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري فرض فتح القفل...'),
          ],
        ),
      ),
    );

    try {
      final syncService = await _getSyncService();
      if (syncService == null) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ فشل الاتصال بخدمة المزامنة'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final success = await syncService.forceReleaseLock();
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '✅ تم فرض فتح القفل بنجاح' : '❌ فشل فرض فتح القفل'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🛡️ دالة عرض الملخص المالي
  Future<void> _showFinancialSummary() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري تحميل الملخص...'),
          ],
        ),
      ),
    );

    try {
      final db = DatabaseService();
      final summary = await db.getFinancialSummary();
      
      if (mounted) Navigator.pop(context);
      
      final formatter = NumberFormat('#,##0', 'en_US');
      
      if (!mounted) return;
      
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.analytics, color: Colors.purple),
              SizedBox(width: 8),
              Text('📊 ملخص مالي'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text('👥 العملاء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي العملاء:'),
                            Text('${summary.totalCustomers}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('العملاء المدينون:'),
                            Text('${summary.debtorCount}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Colors.red[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text('💰 الديون', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي الديون:'),
                            Text('${formatter.format(summary.totalCustomerDebt)} د.ع', 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('أرصدة دائنة:'),
                            Text('${formatter.format(summary.totalCustomerCredit)} د.ع', 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text('🧾 الفواتير', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('عدد الفواتير:'),
                            Text('${summary.totalInvoices}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('إجمالي المبيعات:'),
                            Text('${formatter.format(summary.totalInvoiceAmount)} د.ع', 
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'آخر تحديث: ${DateFormat('yyyy-MM-dd HH:mm').format(summary.generatedAt)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
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
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 📄 دالة مشاركة كشوفات حسابات جميع العملاء
  Future<void> _shareAllAccountStatements() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('جاري إنشاء كشوفات الحساب لجميع العملاء...\nقد يستغرق هذا بعض الوقت')),
          ],
        ),
      ),
    );

    try {
      final db = DatabaseService();
      final pdfService = PdfService();
      
      // جلب جميع العملاء
      final customers = await db.getAllCustomers();
      
      if (customers.isEmpty) {
        if (mounted) Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يوجد عملاء في النظام'), backgroundColor: Colors.orange),
          );
        }
        return;
      }

      // دالة لجلب معاملات العميل وتحويلها إلى AccountStatementItem
      Future<List<AccountStatementItem>> getCustomerTransactionsForStatement(int customerId) async {
        final transactions = await db.getCustomerTransactions(customerId, orderBy: 'transaction_date ASC, id ASC');
        final allTransactions = <AccountStatementItem>[];
        
        for (var transaction in transactions) {
          if (transaction.transactionDate != null) {
            String description = '';
            if (transaction.amountChanged > 0) {
              description = 'إضافة دين';
            } else if (transaction.amountChanged < 0) {
              description = 'تسديد دين';
            } else {
              description = 'معاملة مالية';
            }
            if (transaction.invoiceId != null) {
              description += ' (فاتورة #${transaction.invoiceId})';
            }
            
            allTransactions.add(AccountStatementItem(
              date: transaction.transactionDate!,
              description: description,
              amount: transaction.amountChanged,
              type: 'transaction',
              transaction: transaction,
            ));
          }
        }
        
        // حساب الرصيد قبل وبعد كل معاملة
        double currentBalance = 0.0;
        for (var item in allTransactions) {
          item.balanceBefore = currentBalance;
          currentBalance += item.amount;
          item.balanceAfter = currentBalance;
        }
        
        return allTransactions;
      }

      // إنشاء ملف PDF
      final pdfBytes = await pdfService.generateAllCustomersAccountStatements(
        customers: customers,
        getCustomerTransactions: getCustomerTransactionsForStatement,
      );

      if (mounted) Navigator.pop(context);

      // حفظ الملف
      final now = DateTime.now();
      final fileName = 'كشوفات_الحسابات_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.pdf';
      
      if (Platform.isWindows) {
        // على Windows: حفظ في مجلد المستندات وفتح للمشاركة
        final directory = Directory('${Platform.environment['USERPROFILE']}/Documents/account_statements');
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pdfBytes);
        
        // فتح الملف
        await Process.start('cmd', ['/c', 'start', '', filePath]);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم حفظ الملف في:\n$filePath'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        // على الأجهزة الأخرى: استخدام share_plus للمشاركة
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pdfBytes);
        
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'كشوفات حسابات العملاء - ${now.year}/${now.month}/${now.day}',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء كشوفات الحساب: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 📜 دالة عرض سجل المزامنات
  Future<void> _showSyncAuditLog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('جاري تحميل سجل المزامنات...'),
          ],
        ),
      ),
    );

    try {
      final auditService = SyncAuditService();
      final logs = await auditService.getSyncLogs(limit: 20);
      final backups = await auditService.getAvailableBackups();
      final years = await auditService.getAvailableYears();
      
      if (mounted) Navigator.pop(context);
      
      if (!mounted) return;
      
      await showDialog(
        context: context,
        builder: (context) => _SyncAuditLogDialog(
          logs: logs,
          backups: backups,
          years: years,
          auditService: auditService,
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 📜 Dialog سجل المزامنات مع 3 تبويبات
// ═══════════════════════════════════════════════════════════════════════════
class _SyncAuditLogDialog extends StatefulWidget {
  final List<SyncAuditLog> logs;
  final List<Map<String, dynamic>> backups;
  final List<int> years;
  final SyncAuditService auditService;

  const _SyncAuditLogDialog({
    required this.logs,
    required this.backups,
    required this.years,
    required this.auditService,
  });

  @override
  State<_SyncAuditLogDialog> createState() => _SyncAuditLogDialogState();
}

class _SyncAuditLogDialogState extends State<_SyncAuditLogDialog> {
  // للتبويب الثالث (تفاصيل المزامنة)
  int? _selectedYear;
  int? _selectedMonth;
  List<int> _availableMonths = [];
  List<SyncOperationDetail> _operationDetails = [];
  Map<String, dynamic> _monthStats = {};
  bool _isLoadingDetails = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.history, color: Colors.indigo),
          SizedBox(width: 8),
          Text('📜 سجل المزامنات'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: DefaultTabController(
          length: 3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TabBar(
                labelColor: Colors.indigo,
                isScrollable: true,
                tabs: [
                  Tab(text: 'المزامنات', icon: Icon(Icons.sync, size: 18)),
                  Tab(text: 'النسخ الاحتياطية', icon: Icon(Icons.backup, size: 18)),
                  Tab(text: 'تفاصيل العمليات', icon: Icon(Icons.list_alt, size: 18)),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 400,
                child: TabBarView(
                  children: [
                    // تبويب المزامنات
                    _buildSyncLogsTab(),
                    // تبويب النسخ الاحتياطية
                    _buildBackupsTab(),
                    // تبويب تفاصيل العمليات
                    _buildOperationDetailsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }

  Widget _buildSyncLogsTab() {
    if (widget.logs.isEmpty) {
      return const Center(child: Text('لا توجد عمليات مزامنة مسجلة'));
    }
    
    return ListView.builder(
      itemCount: widget.logs.length,
      itemBuilder: (context, index) {
        final log = widget.logs[index];
        final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
        return Card(
          color: log.success ? Colors.green[50] : Colors.red[50],
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      log.success ? Icons.check_circle : Icons.error,
                      color: log.success ? Colors.green : Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      dateFormat.format(log.syncStartTime.toLocal()),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        log.syncType == 'full_transfer' ? 'نقل كامل' : 'عادي',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('📥 ${log.operationsDownloaded}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 12),
                    Text('📤 ${log.operationsUploaded}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 12),
                    Text('✅ ${log.operationsApplied}', style: const TextStyle(fontSize: 12)),
                    if (log.operationsFailed > 0) ...[
                      const SizedBox(width: 12),
                      Text('❌ ${log.operationsFailed}', 
                        style: const TextStyle(fontSize: 12, color: Colors.red)),
                    ],
                  ],
                ),
                if (log.errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '⚠️ ${log.errorMessage}',
                    style: TextStyle(fontSize: 11, color: Colors.red[700]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBackupsTab() {
    if (widget.backups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.backup_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('لا توجد نسخ احتياطية'),
            SizedBox(height: 4),
            Text(
              'سيتم إنشاء نسخة احتياطية تلقائياً\nقبل كل عملية مزامنة',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      itemCount: widget.backups.length,
      itemBuilder: (context, index) {
        final backup = widget.backups[index];
        final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
        final sizeKB = (backup['size'] as int) / 1024;
        final sizeMB = sizeKB / 1024;
        final sizeStr = sizeMB >= 1 
            ? '${sizeMB.toStringAsFixed(1)} MB'
            : '${sizeKB.toStringAsFixed(0)} KB';
        return Card(
          color: Colors.blue[50],
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.backup, color: Colors.blue),
            title: Text(
              dateFormat.format(backup['created'] as DateTime),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('الحجم: $sizeStr'),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }

  Widget _buildOperationDetailsTab() {
    return Column(
      children: [
        // اختيار السنة والشهر
        Row(
          children: [
            // اختيار السنة
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedYear,
                decoration: const InputDecoration(
                  labelText: 'السنة',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: widget.years.isEmpty
                    ? [const DropdownMenuItem(value: null, child: Text('لا توجد بيانات'))]
                    : widget.years.map((year) => DropdownMenuItem(
                        value: year,
                        child: Text(year.toString()),
                      )).toList(),
                onChanged: widget.years.isEmpty ? null : (year) async {
                  setState(() {
                    _selectedYear = year;
                    _selectedMonth = null;
                    _operationDetails = [];
                    _monthStats = {};
                  });
                  if (year != null) {
                    final months = await widget.auditService.getAvailableMonths(year);
                    setState(() {
                      _availableMonths = months;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            // اختيار الشهر
            Expanded(
              child: DropdownButtonFormField<int>(
                value: _selectedMonth,
                decoration: const InputDecoration(
                  labelText: 'الشهر',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: _availableMonths.isEmpty
                    ? [const DropdownMenuItem(value: null, child: Text('اختر السنة أولاً'))]
                    : _availableMonths.map((month) => DropdownMenuItem(
                        value: month,
                        child: Text(month.toString().padLeft(2, '0')),
                      )).toList(),
                onChanged: _availableMonths.isEmpty ? null : (month) async {
                  if (month != null && _selectedYear != null) {
                    setState(() {
                      _selectedMonth = month;
                      _isLoadingDetails = true;
                    });
                    
                    final details = await widget.auditService.getOperationDetails(
                      year: _selectedYear!,
                      month: month,
                    );
                    final stats = await widget.auditService.getMonthStats(_selectedYear!, month);
                    
                    setState(() {
                      _operationDetails = details;
                      _monthStats = stats;
                      _isLoadingDetails = false;
                    });
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // إحصائيات الشهر
        if (_monthStats.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.indigo[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('الكل', _monthStats['total'] ?? 0, Colors.indigo),
                _buildStatItem('نجح', _monthStats['successful'] ?? 0, Colors.green),
                _buildStatItem('فشل', _monthStats['failed'] ?? 0, Colors.red),
                _buildStatItem('تنزيل', _monthStats['downloaded'] ?? 0, Colors.blue),
                _buildStatItem('رفع', _monthStats['uploaded'] ?? 0, Colors.orange),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        
        // قائمة العمليات
        Expanded(
          child: _isLoadingDetails
              ? const Center(child: CircularProgressIndicator())
              : _operationDetails.isEmpty
                  ? Center(
                      child: Text(
                        _selectedMonth == null 
                            ? 'اختر السنة والشهر لعرض التفاصيل'
                            : 'لا توجد عمليات في هذا الشهر',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _operationDetails.length,
                      itemBuilder: (context, index) {
                        final detail = _operationDetails[index];
                        return _buildOperationDetailCard(detail);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 16,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildOperationDetailCard(SyncOperationDetail detail) {
    final dateFormat = DateFormat('dd/MM HH:mm');
    final isTransaction = detail.entityType == 'transaction';
    final isDebt = (detail.amount ?? 0) > 0;
    
    Color cardColor;
    IconData icon;
    
    if (!detail.success) {
      cardColor = Colors.red[50]!;
      icon = Icons.error;
    } else if (isTransaction) {
      cardColor = isDebt ? Colors.orange[50]! : Colors.green[50]!;
      icon = isDebt ? Icons.add_circle : Icons.remove_circle;
    } else {
      cardColor = Colors.blue[50]!;
      icon = Icons.person;
    }
    
    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // الأيقونة
            CircleAvatar(
              radius: 16,
              backgroundColor: detail.success ? Colors.white : Colors.red[100],
              child: Icon(icon, size: 18, color: detail.success ? (isDebt ? Colors.orange : Colors.green) : Colors.red),
            ),
            const SizedBox(width: 10),
            // المعلومات
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          detail.customerName ?? 'غير معروف',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: detail.direction == 'download' ? Colors.blue[100] : Colors.orange[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          detail.directionLabel,
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${detail.operationTypeLabel} ${detail.entityTypeLabel}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                      if (detail.amount != null) ...[
                        const Text(' • ', style: TextStyle(fontSize: 11)),
                        Text(
                          '${NumberFormat('#,##0').format(detail.amount!.abs())} د.ع',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDebt ? Colors.orange[700] : Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (!detail.success && detail.errorMessage != null)
                    Text(
                      detail.errorMessage!,
                      style: const TextStyle(fontSize: 10, color: Colors.red),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // التاريخ
            Text(
              dateFormat.format(detail.operationTime.toLocal()),
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

// 🏷️ Dialog لإدارة الماركات
class _BrandsManagementDialog extends StatefulWidget {
  final List<Map<String, dynamic>> brands;
  
  const _BrandsManagementDialog({required this.brands});
  
  @override
  State<_BrandsManagementDialog> createState() => _BrandsManagementDialogState();
}

class _BrandsManagementDialogState extends State<_BrandsManagementDialog> {
  late List<Map<String, dynamic>> _brands;
  final TextEditingController _newBrandController = TextEditingController();
  bool _isLoading = false;
  String _searchQuery = '';
  
  @override
  void initState() {
    super.initState();
    _brands = List.from(widget.brands);
  }
  
  @override
  void dispose() {
    _newBrandController.dispose();
    super.dispose();
  }
  
  List<Map<String, dynamic>> get _filteredBrands {
    if (_searchQuery.isEmpty) return _brands;
    return _brands.where((b) => 
      (b['brand'] as String).toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }
  
  Future<void> _addBrand() async {
    final brandName = _newBrandController.text.trim();
    if (brandName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم الماركة'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    // التحقق من عدم وجود الماركة
    final exists = _brands.any((b) => 
      (b['brand'] as String).toLowerCase() == brandName.toLowerCase()
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الماركة موجودة بالفعل'), backgroundColor: Colors.orange),
      );
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      await smart_search.SmartSearchService.instance.addManualBrand(brandName);
      
      setState(() {
        _brands.insert(0, {
          'brand': brandName,
          'count': 999,
          'created_at': DateTime.now().toIso8601String(),
        });
        _newBrandController.clear();
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تمت إضافة الماركة: $brandName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  Future<void> _deleteBrand(String brand) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('حذف الماركة'),
          ],
        ),
        content: Text('هل تريد حذف الماركة "$brand"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isLoading = true);
    
    try {
      await smart_search.SmartSearchService.instance.deleteBrand(brand);
      
      setState(() {
        _brands.removeWhere((b) => b['brand'] == brand);
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف الماركة: $brand'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.label, color: Colors.teal),
          const SizedBox(width: 8),
          const Expanded(child: Text('إدارة الماركات')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.teal[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${_brands.length}',
              style: TextStyle(fontSize: 14, color: Colors.teal[700], fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 450,
        child: Column(
          children: [
            // حقل إضافة ماركة جديدة
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newBrandController,
                    decoration: InputDecoration(
                      hintText: 'اسم الماركة الجديدة',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      prefixIcon: const Icon(Icons.add, size: 20),
                    ),
                    onSubmitted: (_) => _addBrand(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: _isLoading ? null : _addBrand,
                  child: const Text('إضافة'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // حقل البحث
            TextField(
              decoration: InputDecoration(
                hintText: 'بحث في الماركات...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: const Icon(Icons.search, size: 20),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
            const SizedBox(height: 12),
            // قائمة الماركات
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredBrands.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.label_off, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isEmpty 
                                    ? 'لا توجد ماركات مكتشفة\nقم بتدريب البحث الذكي أولاً'
                                    : 'لا توجد نتائج للبحث',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredBrands.length,
                          itemBuilder: (context, index) {
                            final brand = _filteredBrands[index];
                            final brandName = brand['brand'] as String;
                            final count = brand['count'] as int;
                            final isManual = count >= 999;
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 4),
                              child: ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isManual ? Colors.teal[100] : Colors.grey[200],
                                  child: Icon(
                                    isManual ? Icons.person_add : Icons.auto_awesome,
                                    size: 16,
                                    color: isManual ? Colors.teal : Colors.grey[600],
                                  ),
                                ),
                                title: Text(
                                  brandName,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                subtitle: Text(
                                  isManual ? 'مضافة يدوياً' : 'مكتشفة ($count منتج)',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                  onPressed: () => _deleteBrand(brandName),
                                  tooltip: 'حذف',
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}
