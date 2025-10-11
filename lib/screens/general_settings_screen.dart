import 'package:flutter/material.dart';
import 'package:alnaser/models/app_settings.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  final SettingsManager _settingsManager = SettingsManager();
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

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _appSettings = await _settingsManager.getAppSettings();
    
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
    );
    await _settingsManager.saveAppSettings(_appSettings);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات العامة'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('أرقام الهواتف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
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
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          if (_phoneNumberControllers.length > 1) // Only show remove button if more than one field
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
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة رقم هاتف'),
                      onPressed: _addPhoneNumberField,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // وصف الشركة
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('وصف الشركة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _companyDescriptionController,
                    decoration: InputDecoration(
                      labelText: 'وصف الشركة',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    title: const Text('لون اسم الشركة (الناصر)'),
                    trailing: CircleAvatar(backgroundColor: _companyNameColor, radius: 15),
                    onTap: () => _pickColor('companyName'),
                  ),
                  ListTile(
                    title: const Text('لون وصف الشركة'),
                    trailing: CircleAvatar(backgroundColor: _companyDescriptionColor, radius: 15),
                    onTap: () => _pickColor('companyDescription'),
                  ),
                ],
              ),
            ),
          ),
          
          // ألوان عناصر الفاتورة
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ألوان عناصر الفاتورة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  
                  // المبلغ المتبقي
                  ListTile(
                    title: const Text('المبلغ المتبقي'),
                    trailing: CircleAvatar(backgroundColor: _remainingAmountColor, radius: 15),
                    onTap: () => _pickColor('remainingAmount'),
                  ),
                  
                  // الخصم
                  ListTile(
                    title: const Text('الخصم'),
                    trailing: CircleAvatar(backgroundColor: _discountColor, radius: 15),
                    onTap: () => _pickColor('discount'),
                  ),
                  
                  // الإجمالي قبل الخصم
                  ListTile(
                    title: const Text('الإجمالي قبل الخصم'),
                    trailing: CircleAvatar(backgroundColor: _totalBeforeDiscountColor, radius: 15),
                    onTap: () => _pickColor('totalBeforeDiscount'),
                  ),
                  
                  // الإجمالي بعد الخصم
                  ListTile(
                    title: const Text('الإجمالي بعد الخصم'),
                    trailing: CircleAvatar(backgroundColor: _totalAfterDiscountColor, radius: 15),
                    onTap: () => _pickColor('totalAfterDiscount'),
                  ),
                  
                  // أجور التحميل
                  ListTile(
                    title: const Text('أجور التحميل'),
                    trailing: CircleAvatar(backgroundColor: _loadingFeesColor, radius: 15),
                    onTap: () => _pickColor('loadingFees'),
                  ),
                  
                  // الدين السابق
                  ListTile(
                    title: const Text('الدين السابق'),
                    trailing: CircleAvatar(backgroundColor: _previousDebtColor, radius: 15),
                    onTap: () => _pickColor('previousDebt'),
                  ),
                  
                  // الدين الحالي
                  ListTile(
                    title: const Text('الدين الحالي'),
                    trailing: CircleAvatar(backgroundColor: _currentDebtColor, radius: 15),
                    onTap: () => _pickColor('currentDebt'),
                  ),
                ],
              ),
            ),
          ),
          
          // ألوان أرقام الهواتف
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ألوان أرقام الهواتف', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  
                  // أرقام الكهربائيات
                  ListTile(
                    title: const Text('أرقام الكهربائيات'),
                    trailing: CircleAvatar(backgroundColor: _electricPhoneColor, radius: 15),
                    onTap: () => _pickColor('electricPhone'),
                  ),
                  
                  // أرقام الصحيات
                  ListTile(
                    title: const Text('أرقام الصحيات'),
                    trailing: CircleAvatar(backgroundColor: _healthPhoneColor, radius: 15),
                    onTap: () => _pickColor('healthPhone'),
                  ),
                ],
              ),
            ),
          ),
          
          // ألوان عناصر الجدول
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ألوان عناصر الجدول', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  
                  // التسلسل
                  ListTile(
                    title: const Text('التسلسل'),
                    trailing: CircleAvatar(backgroundColor: _itemSerialColor, radius: 15),
                    onTap: () => _pickColor('itemSerial'),
                  ),
                  
                  // التفاصيل
                  ListTile(
                    title: const Text('التفاصيل (أسماء المواد)'),
                    trailing: CircleAvatar(backgroundColor: _itemDetailsColor, radius: 15),
                    onTap: () => _pickColor('itemDetails'),
                  ),
                  
                  // العدد
                  ListTile(
                    title: const Text('العدد'),
                    trailing: CircleAvatar(backgroundColor: _itemQuantityColor, radius: 15),
                    onTap: () => _pickColor('itemQuantity'),
                  ),
                  
                  // السعر
                  ListTile(
                    title: const Text('السعر'),
                    trailing: CircleAvatar(backgroundColor: _itemPriceColor, radius: 15),
                    onTap: () => _pickColor('itemPrice'),
                  ),
                  
                  // المبلغ
                  ListTile(
                    title: const Text('المبلغ'),
                    trailing: CircleAvatar(backgroundColor: _itemTotalColor, radius: 15),
                    onTap: () => _pickColor('itemTotal'),
                  ),
                ],
              ),
            ),
          ),
          
          // ألوان أخرى
          Card(
            margin: const EdgeInsets.only(bottom: 20),
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ألوان أخرى', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  
                  // التنويه
                  ListTile(
                    title: const Text('التنويه'),
                    trailing: CircleAvatar(backgroundColor: _noticeColor, radius: 15),
                    onTap: () => _pickColor('notice'),
                  ),
                  
                  // المبلغ المدفوع
                  ListTile(
                    title: const Text('المبلغ المدفوع'),
                    trailing: CircleAvatar(backgroundColor: _paidAmountColor, radius: 15),
                    onTap: () => _pickColor('paidAmount'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
