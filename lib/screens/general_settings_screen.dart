import 'dart:io';
import 'package:flutter/material.dart';
import 'package:alnaser/models/app_settings.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/database_service.dart';
import '../services/pdf_service.dart';
import '../models/account_statement_item.dart';

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
                      ],
                    ),
                  ),
                ),
                
                if (issueCount == 0 && warningCount == 0) ...[
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
                  const SizedBox(height: 8),
                  // عرض العملاء غير السليمين (سواء لديهم issues أو لا)
                  ...reports.where((r) => !r.isHealthy).take(15).map((r) {
                    // تحديد نص المشكلة
                    String issueText = '';
                    if (r.issues.isNotEmpty) {
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
}
