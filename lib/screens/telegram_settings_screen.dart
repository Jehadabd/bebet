// screens/telegram_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/telegram_backup_service.dart';

class TelegramSettingsScreen extends StatefulWidget {
  const TelegramSettingsScreen({super.key});

  @override
  State<TelegramSettingsScreen> createState() => _TelegramSettingsScreenState();
}

class _TelegramSettingsScreenState extends State<TelegramSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _telegramService = TelegramBackupService();
  final _botTokenController = TextEditingController();
  final _channelIdController = TextEditingController();

  bool _isLoading = true;
  bool _isTesting = false;
  String? _testResult;
  bool _hasCustomSettings = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeInOut);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _telegramService.loadSettings();
    _botTokenController.text = _telegramService.customBotToken ?? '';
    _channelIdController.text = _telegramService.customChannelId ?? '';
    _hasCustomSettings = _botTokenController.text.isNotEmpty || _channelIdController.text.isNotEmpty;
    setState(() => _isLoading = false);
    _animController.forward();
  }

  @override
  void dispose() {
    _botTokenController.dispose();
    _channelIdController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    final botToken = _botTokenController.text.trim();
    final channelId = _channelIdController.text.trim();

    if (botToken.isEmpty || channelId.isEmpty) {
      _showSnackBar('يرجى إدخال توكن البوت ومعرف القناة', Colors.orange);
      return;
    }

    // تحقق بسيط من صيغة التوكن
    if (!botToken.contains(':')) {
      _showSnackBar('صيغة التوكن غير صحيحة. يجب أن يحتوي على ":"', Colors.orange);
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final connected = await _telegramService.testConnection(botToken, channelId);

      if (connected) {
        // حفظ الإعدادات بعد نجاح الاختبار
        await _telegramService.saveSettings(botToken: botToken, channelId: channelId);
        setState(() {
          _testResult = 'success';
          _hasCustomSettings = true;
        });
        _showSnackBar('✅ تم الاتصال بنجاح وحفظ الإعدادات!', Colors.green);
      } else {
        setState(() {
          _testResult = 'failed';
        });
        _showSnackBar('❌ فشل الاتصال. تحقق من البيانات المدخلة', Colors.red);
      }
    } catch (e) {
      setState(() {
        _testResult = 'error';
      });
      _showSnackBar('❌ خطأ: $e', Colors.red);
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.restore, color: Colors.orange),
            SizedBox(width: 8),
            Text('إرجاع للافتراضي'),
          ],
        ),
        content: const Text(
          'سيتم مسح الإعدادات المخصصة والعودة للإعدادات الافتراضية.\n\nهل أنت متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرجاع'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _telegramService.saveSettings(botToken: '', channelId: '');
      _botTokenController.clear();
      _channelIdController.clear();
      setState(() {
        _hasCustomSettings = false;
        _testResult = null;
      });
      _showSnackBar('تم الإرجاع للإعدادات الافتراضية', Colors.blue);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('إعدادات Telegram'),
          backgroundColor: const Color(0xFF0088CC),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات Telegram'),
        backgroundColor: const Color(0xFF0088CC),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_hasCustomSettings)
            IconButton(
              icon: const Icon(Icons.restore),
              tooltip: 'إرجاع للافتراضي',
              onPressed: _resetToDefaults,
            ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─── شعار Telegram ───
            _buildHeader(),
            const SizedBox(height: 20),

            // ─── حالة الاتصال الحالية ───
            _buildConnectionStatus(),
            const SizedBox(height: 20),

            // ─── حقل توكن البوت ───
            _buildInputCard(
              icon: Icons.vpn_key_rounded,
              iconColor: const Color(0xFF0088CC),
              label: 'توكن البوت (Bot Token)',
              hint: '123456789:ABCdefGHIjklMNOpqrSTUvwxYZ',
              controller: _botTokenController,
              helpText: 'التوكن الذي حصلت عليه من @BotFather',
              isSecret: true,
            ),
            const SizedBox(height: 16),

            // ─── حقل معرف القناة ───
            _buildInputCard(
              icon: Icons.tag,
              iconColor: const Color(0xFF0088CC),
              label: 'معرف القناة (Chat ID)',
              hint: '-1001234567890',
              controller: _channelIdController,
              helpText: 'يبدأ بـ -100 للقنوات والمجموعات',
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 24),

            // ─── زر الاختبار والحفظ ───
            _buildTestButton(),

            // ─── نتيجة الاختبار ───
            if (_testResult != null) ...[
              const SizedBox(height: 16),
              _buildTestResultCard(),
            ],

            const SizedBox(height: 28),

            // ─── التعليمات ───
            _buildInstructionsSection(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0088CC), Color(0xFF00AAEE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0088CC).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.telegram, size: 56, color: Colors.white),
          const SizedBox(height: 10),
          const Text(
            'إعدادات Telegram',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ربط التطبيق بقناة Telegram لإرسال النسخ الاحتياطية',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    final bool isCustom = _hasCustomSettings;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCustom ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCustom ? Colors.green.shade300 : Colors.orange.shade300,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCustom ? Icons.check_circle : Icons.info_outline,
            color: isCustom ? Colors.green : Colors.orange,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCustom ? 'إعدادات مخصصة مفعّلة' : 'يتم استخدام الإعدادات الافتراضية',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isCustom ? Colors.green.shade800 : Colors.orange.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isCustom
                      ? 'التطبيق يستخدم بوتك وقناتك الخاصة'
                      : 'أدخل بيانات بوت وقناة جديدين لتغيير الوجهة',
                  style: TextStyle(
                    fontSize: 12,
                    color: isCustom ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String hint,
    required TextEditingController controller,
    String? helpText,
    bool isSecret = false,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF0088CC), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'نسخ',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: controller.text));
                          _showSnackBar('تم النسخ', Colors.grey);
                        },
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (helpText != null) ...[
              const SizedBox(height: 6),
              Text(
                helpText,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTestButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isTesting ? null : _testAndSave,
        icon: _isTesting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : const Icon(Icons.send_rounded, size: 22),
        label: Text(
          _isTesting ? 'جاري اختبار الاتصال...' : 'اختبار الاتصال وحفظ',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0088CC),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 3,
        ),
      ),
    );
  }

  Widget _buildTestResultCard() {
    final isSuccess = _testResult == 'success';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSuccess ? Colors.green.shade300 : Colors.red.shade300,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : Icons.error_rounded,
            color: isSuccess ? Colors.green : Colors.red,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isSuccess
                  ? '✅ تم الاتصال بنجاح!\nتم إرسال رسالة اختبار إلى قناتك وحفظ الإعدادات.'
                  : '❌ فشل الاتصال.\nتأكد من:\n• صحة توكن البوت\n• صحة معرف القناة\n• أن البوت مضاف كمسؤول في القناة',
              style: TextStyle(
                fontSize: 13,
                color: isSuccess ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: const Icon(Icons.help_outline_rounded, color: Color(0xFF0088CC)),
          title: const Text(
            'كيفية الإعداد خطوة بخطوة',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(),
                  const SizedBox(height: 8),

                  // ── الخطوة 1: إنشاء البوت ──
                  _buildInstructionGroup(
                    title: '📱 الخطوة 1: إنشاء بوت جديد',
                    steps: [
                      'افتح تطبيق Telegram وابحث عن @BotFather',
                      'أرسل له الأمر: /newbot',
                      'اختر اسم للبوت (مثلاً: My Backup Bot)',
                      'اختر username ينتهي بـ bot (مثلاً: my_backup_bot)',
                      'سيعطيك BotFather التوكن (Token) → انسخه وضعه في الحقل أعلاه',
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── الخطوة 2: إنشاء القناة ──
                  _buildInstructionGroup(
                    title: '📢 الخطوة 2: إنشاء قناة جديدة',
                    steps: [
                      'في Telegram اضغط على "إنشاء قناة جديدة" (New Channel)',
                      'اختر اسمًا للقناة (مثلاً: نسخ احتياطية)',
                      'اجعل القناة خاصة (Private)',
                      'أضف البوت الذي أنشأته كمسؤول (Admin) في القناة',
                      'امنحه صلاحية "إرسال الرسائل" على الأقل',
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── الخطوة 3: الحصول على Chat ID ──
                  _buildInstructionGroup(
                    title: '🔢 الخطوة 3: الحصول على Chat ID',
                    steps: [
                      'أرسل أي رسالة في القناة',
                      'افتح المتصفح وادخل الرابط التالي:',
                    ],
                  ),
                  Container(
                    margin: const EdgeInsets.only(right: 32, top: 4, bottom: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            'https://api.telegram.org/bot<TOKEN>/getUpdates',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Colors.blueGrey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSingleStep('3', 'استبدل <TOKEN> بالتوكن الخاص ببوتك'),
                        _buildSingleStep('4', 'ابحث في النتيجة عن "chat":{"id":-100...}'),
                        _buildSingleStep('5', 'انسخ الرقم كاملاً (يبدأ بـ -100) وضعه في حقل Chat ID'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── ملاحظات مهمة ──
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'ملاحظات مهمة:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text('• البوت يجب أن يكون مسؤولاً (Admin) في القناة', style: TextStyle(fontSize: 12)),
                        Text('• Chat ID للقنوات يبدأ دائماً بـ -100', style: TextStyle(fontSize: 12)),
                        Text('• لا تشارك التوكن مع أي شخص', style: TextStyle(fontSize: 12)),
                        Text('• إذا حذفت حسابك، ستحتاج لإنشاء بوت وقناة جديدين', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionGroup({required String title, required List<String> steps}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0088CC)),
        ),
        const SizedBox(height: 8),
        ...List.generate(steps.length, (i) => _buildSingleStep('${i + 1}', steps[i])),
      ],
    );
  }

  Widget _buildSingleStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              color: Color(0xFF0088CC),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
