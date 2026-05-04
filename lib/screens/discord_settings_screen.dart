// screens/discord_settings_screen.dart
import 'package:flutter/material.dart';
import '../services/discord_backup_service.dart';

class DiscordSettingsScreen extends StatefulWidget {
  const DiscordSettingsScreen({super.key});

  @override
  State<DiscordSettingsScreen> createState() => _DiscordSettingsScreenState();
}

class _DiscordSettingsScreenState extends State<DiscordSettingsScreen> {
  final _discordService = DiscordBackupService();
  final _webhookController = TextEditingController();
  
  bool _isEnabled = false;
  bool _isTesting = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _discordService.loadSettings();
    _webhookController.text = _discordService.webhookUrl ?? '';
    _isEnabled = _discordService.isEnabled;
  }

  @override
  void dispose() {
    _webhookController.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    if (_webhookController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال Webhook URL')),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      // حفظ مؤقت للاختبار
      await _discordService.saveSettings(
        webhookUrl: _webhookController.text,
        enabled: true,
      );

      // اختبار الاتصال
      final connected = await _discordService.testConnection();
      
      if (connected) {
        setState(() {
          _testResult = '✅ تم الاتصال بنجاح!';
          _isEnabled = true;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ تم الاتصال بنجاح!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _testResult = '❌ فشل الاتصال. تحقق من الـ Webhook URL';
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل الاتصال'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _testResult = '❌ خطأ: $e';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value && _webhookController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال Webhook URL أولاً')),
      );
      return;
    }

    setState(() {
      _isEnabled = value;
    });

    await _discordService.saveSettings(
      webhookUrl: _webhookController.text,
      enabled: value,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? '✅ تم تفعيل Discord' : '⏸️ تم إيقاف Discord'),
        backgroundColor: value ? Colors.green : Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات Discord'),
        backgroundColor: const Color(0xFF5865F2),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // شعار Discord
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF5865F2).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.discord,
                  size: 48,
                  color: Color(0xFF5865F2),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Discord Webhook',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5865F2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'بديل Telegram - يعمل في كل مكان',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // زر التفعيل/الإيقاف
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SwitchListTile(
              title: const Text(
                'تفعيل النسخ الاحتياطي إلى Discord',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                _isEnabled 
                    ? 'سيتم إرسال النسخ الاحتياطية بالتوازي مع Telegram'
                    : 'النسخ الاحتياطية معطلة',
                style: TextStyle(
                  color: _isEnabled ? Colors.green : Colors.grey,
                  fontSize: 12,
                ),
              ),
              value: _isEnabled,
              onChanged: _toggleEnabled,
              activeColor: const Color(0xFF5865F2),
            ),
          ),
          const SizedBox(height: 24),

          // حقل Webhook URL
          TextField(
            controller: _webhookController,
            decoration: InputDecoration(
              labelText: 'Webhook URL',
              hintText: 'https://discord.com/api/webhooks/...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.link),
              helperText: 'انسخه من إعدادات القناة في Discord',
            ),
          ),
          const SizedBox(height: 24),

          // زر الاختبار والحفظ
          ElevatedButton.icon(
            onPressed: _isTesting ? null : _testAndSave,
            icon: _isTesting 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle),
            label: Text(_isTesting ? 'جاري الاختبار...' : 'اختبار الاتصال وحفظ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5865F2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // نتيجة الاختبار
          if (_testResult != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.contains('✅') 
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.contains('✅') ? Colors.green : Colors.red,
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // تعليمات
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.help_outline, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'كيفية الحصول على Webhook URL:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildStep('1', 'افتح Discord وأنشئ سيرفر جديد'),
                _buildStep('2', 'أنشئ قناة نصية (مثلاً: backups)'),
                _buildStep('3', 'اذهب لإعدادات القناة'),
                _buildStep('4', 'اختر Integrations → Webhooks'),
                _buildStep('5', 'اضغط Create Webhook'),
                _buildStep('6', 'انسخ الـ Webhook URL'),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // مميزات Discord
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF5865F2).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✨ مميزات Discord:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text('✅ لا يحتاج بروكسي', style: TextStyle(fontSize: 12)),
                Text('✅ Webhook بسيط (رابط واحد)', style: TextStyle(fontSize: 12)),
                Text('✅ رفع ملفات سريع', style: TextStyle(fontSize: 12)),
                Text('✅ إشعارات فورية', style: TextStyle(fontSize: 12)),
                Text('✅ مجاني بالكامل', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Color(0xFF5865F2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
