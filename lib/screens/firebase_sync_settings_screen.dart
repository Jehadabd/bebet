// lib/screens/firebase_sync_settings_screen.dart
// شاشة إعدادات المزامنة عبر Firebase مع حماية صارمة

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_sync/firebase_sync_config.dart';
import '../services/firebase_sync/firebase_sync_service.dart';
import '../services/password_service.dart';

class FirebaseSyncSettingsScreen extends StatefulWidget {
  const FirebaseSyncSettingsScreen({super.key});

  @override
  State<FirebaseSyncSettingsScreen> createState() => _FirebaseSyncSettingsScreenState();
}

class _FirebaseSyncSettingsScreenState extends State<FirebaseSyncSettingsScreen> {
  bool _isLoading = true;
  bool _isEnabled = false;
  String? _currentGroupId;
  Map<String, dynamic>? _syncStats;
  
  final _firebaseSync = FirebaseSyncService();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    _isEnabled = await FirebaseSyncConfig.isEnabled();
    _currentGroupId = await FirebaseSyncConfig.getSyncGroupId();
    
    if (_isEnabled && _currentGroupId != null) {
      _syncStats = await _firebaseSync.getSyncStats();
    }
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مزامنة Firebase'),
          backgroundColor: Colors.deepOrange,
          foregroundColor: Colors.white,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // بطاقة الحالة
                    _buildStatusCard(),
                    const SizedBox(height: 16),
                    
                    // بطاقة الإعدادات
                    _buildSettingsCard(),
                    const SizedBox(height: 16),
                    
                    // بطاقة الإحصائيات
                    if (_isEnabled && _syncStats != null)
                      _buildStatsCard(),
                    
                    const SizedBox(height: 16),
                    
                    // ملاحظات
                    _buildNotesCard(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final status = _firebaseSync.status;
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    switch (status) {
      case FirebaseSyncStatus.online:
        statusColor = Colors.green;
        statusText = 'متصل ويستمع للتغييرات';
        statusIcon = Icons.cloud_done;
        break;
      case FirebaseSyncStatus.syncing:
        statusColor = Colors.blue;
        statusText = 'جاري المزامنة...';
        statusIcon = Icons.sync;
        break;
      case FirebaseSyncStatus.offline:
        statusColor = Colors.orange;
        statusText = 'غير متصل - يعمل محلياً';
        statusIcon = Icons.cloud_off;
        break;
      case FirebaseSyncStatus.error:
        statusColor = Colors.red;
        statusText = 'خطأ في المزامنة';
        statusIcon = Icons.error;
        break;
      case FirebaseSyncStatus.disabled:
        statusColor = Colors.grey;
        statusText = 'المزامنة معطلة';
        statusIcon = Icons.pause_circle;
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'غير مُعد';
        statusIcon = Icons.settings;
    }
    
    return Card(
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor, size: 32),
        title: Text(
          'حالة المزامنة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(statusText),
        trailing: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: statusColor,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إعدادات المزامنة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            
            // تفعيل/تعطيل المزامنة
            SwitchListTile(
              title: const Text('تفعيل المزامنة الفورية'),
              subtitle: Text(
                _isEnabled 
                    ? 'المزامنة مفعلة - البيانات تتزامن تلقائياً'
                    : 'المزامنة معطلة',
              ),
              value: _isEnabled,
              onChanged: (value) => _toggleSync(value),
              activeColor: Colors.deepOrange,
            ),
            
            const Divider(),
            
            // المجموعة الحالية
            ListTile(
              leading: const Icon(Icons.group, color: Colors.deepOrange),
              title: const Text('مجموعة المزامنة'),
              subtitle: Text(
                _currentGroupId != null
                    ? SyncGroupIds.getDisplayName(_currentGroupId!)
                    : 'غير محدد',
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: _isEnabled ? _showChangeGroupDialog : _showSelectGroupDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إحصائيات المزامنة',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            
            _buildStatRow('المجموعة', _syncStats?['groupId'] ?? '-'),
            _buildStatRow('العملاء في السحابة', '${_syncStats?['customersInCloud'] ?? 0}'),
            _buildStatRow('المعاملات في السحابة', '${_syncStats?['transactionsInCloud'] ?? 0}'),
            _buildStatRow('آخر مزامنة', _formatLastSync(_syncStats?['lastSync'])),
            
            const SizedBox(height: 16),
            
            // زر المزامنة اليدوية
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _performManualSync,
                icon: const Icon(Icons.sync),
                label: const Text('مزامنة الآن'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // 🔒 زر التحقق من سلامة البيانات
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _verifyDataIntegrity,
                icon: const Icon(Icons.verified_user),
                label: const Text('التحقق من سلامة البيانات'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // 🧹 زر تنظيف البيانات القديمة
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _cleanupOldData,
                icon: const Icon(Icons.cleaning_services),
                label: const Text('تنظيف البيانات القديمة'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // 🔧 زر إصلاح ورفع جميع المعاملات
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _repairAndSyncAll,
                icon: const Icon(Icons.build_circle),
                label: const Text('إصلاح ورفع جميع البيانات'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.purple,
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // 📱 زر عرض الأجهزة المتصلة
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showConnectedDevices,
                icon: const Icon(Icons.devices),
                label: const Text('الأجهزة المتصلة'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatLastSync(String? isoString) {
    if (isoString == null) return 'لم تتم بعد';
    try {
      final date = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inMinutes < 1) return 'الآن';
      if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
      if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
      return 'منذ ${diff.inDays} يوم';
    } catch (e) {
      return isoString;
    }
  }

  Widget _buildNotesCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                Icon(Icons.info, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'ملاحظات مهمة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text('• المزامنة تتم تلقائياً في الخلفية'),
            Text('• يعمل التطبيق بدون إنترنت ويزامن عند العودة'),
            Text('• كل مجموعة مستقلة تماماً عن الأخرى'),
            Text('• تغيير المجموعة يتطلب تأكيد صارم'),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // الإجراءات
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _toggleSync(bool enable) async {
    if (enable) {
      // التحقق من وجود مجموعة
      if (_currentGroupId == null) {
        _showSelectGroupDialog();
        return;
      }
      
      await FirebaseSyncConfig.setEnabled(true);
      await _firebaseSync.initialize();
    } else {
      // تعطيل المزامنة
      await FirebaseSyncConfig.setEnabled(false);
    }
    
    await _loadSettings();
  }

  Future<void> _showSelectGroupDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر مجموعة المزامنة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: SyncGroupIds.all.map((groupId) {
            return ListTile(
              leading: const Icon(Icons.group),
              title: Text(SyncGroupIds.getDisplayName(groupId)),
              onTap: () => Navigator.pop(context, groupId),
            );
          }).toList(),
        ),
      ),
    );
    
    if (selected != null) {
      await FirebaseSyncConfig.setSyncGroupId(selected);
      await FirebaseSyncConfig.setEnabled(true);
      await _firebaseSync.reinitialize();
      await _loadSettings();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تفعيل المزامنة مع ${SyncGroupIds.getDisplayName(selected)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _showChangeGroupDialog() async {
    // المرحلة 1: التحدي الرياضي
    final challenge = MathChallenge.generate();
    final mathPassed = await _showMathChallengeDialog(challenge);
    if (!mathPassed) return;
    
    // المرحلة 2: رسالة تحذيرية
    final warningConfirmed = await _showWarningDialog();
    if (!warningConfirmed) return;
    
    // المرحلة 3: كلمة السر
    final passwordConfirmed = await _showPasswordDialog();
    if (!passwordConfirmed) return;
    
    // عرض اختيار المجموعة الجديدة
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر المجموعة الجديدة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: SyncGroupIds.all
              .where((g) => g != _currentGroupId)
              .map((groupId) {
            return ListTile(
              leading: const Icon(Icons.group),
              title: Text(SyncGroupIds.getDisplayName(groupId)),
              onTap: () => Navigator.pop(context, groupId),
            );
          }).toList(),
        ),
      ),
    );
    
    if (selected != null) {
      await FirebaseSyncConfig.setSyncGroupId(selected);
      await _firebaseSync.reinitialize();
      await _loadSettings();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تغيير المجموعة إلى ${SyncGroupIds.getDisplayName(selected)}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<bool> _showMathChallengeDialog(MathChallenge challenge) async {
    final controller = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.calculate, color: Colors.orange),
            SizedBox(width: 8),
            Text('تحدي التأكيد'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'لتأكيد هويتك، أجب على السؤال التالي:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                challenge.questionText,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'أدخل الناتج',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '💡 استخدم الآلة الحاسبة',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (challenge.verify(controller.text)) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('إجابة خاطئة! حاول مرة أخرى'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  Future<bool> _showWarningDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('تحذير خطير!', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'تغيير المجموعة سيؤدي إلى:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('⚠️ فقدان المزامنة مع الجهاز الحالي'),
                  Text('⚠️ بدء مزامنة مع مجموعة جديدة'),
                  Text('⚠️ احتمال تضارب البيانات'),
                  Text('⚠️ قد تفقد بعض التغييرات غير المزامنة'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'هل أنت متأكد تماماً من رغبتك في المتابعة؟',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('متابعة ⚠️'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  Future<bool> _showPasswordDialog() async {
    final controller = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.lock, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('التأكيد النهائي'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل كلمة سر التطبيق للتأكيد:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: 'كلمة السر',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              // التحقق من كلمة السر
              final passwordService = PasswordService();
              final isValid = await passwordService.verifyPassword(controller.text);
              if (isValid) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('كلمة السر غير صحيحة!'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }

  Future<void> _performManualSync() async {
    setState(() => _isLoading = true);
    
    try {
      await _firebaseSync.performFullSync();
      await _loadSettings();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت المزامنة بنجاح ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشلت المزامنة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }
  
  /// 🔒 التحقق من سلامة البيانات
  Future<void> _verifyDataIntegrity() async {
    setState(() => _isLoading = true);
    
    try {
      final result = await _firebaseSync.verifyDataIntegrity();
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  result['valid'] == true ? Icons.check_circle : Icons.warning,
                  color: result['valid'] == true ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(result['valid'] == true ? 'البيانات سليمة' : 'يوجد اختلاف'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildIntegrityRow('العملاء محلياً', '${result['localCustomers'] ?? 0}'),
                _buildIntegrityRow('العملاء في السحابة', '${result['remoteCustomers'] ?? 0}'),
                _buildIntegrityRow('المعاملات محلياً', '${result['localTransactions'] ?? 0}'),
                _buildIntegrityRow('المعاملات في السحابة', '${result['remoteTransactions'] ?? 0}'),
                if (result['issues'] != null && (result['issues'] as List).isNotEmpty) ...[
                  const Divider(),
                  const Text('المشاكل:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ...((result['issues'] as List).map((issue) => 
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $issue', style: const TextStyle(fontSize: 12)),
                    )
                  )),
                ],
              ],
            ),
            actions: [
              if (result['valid'] != true)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _performManualSync();
                  },
                  child: const Text('مزامنة الآن'),
                ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التحقق: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }
  
  /// 🧹 تنظيف البيانات القديمة
  Future<void> _cleanupOldData() async {
    // تأكيد قبل التنظيف
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.cleaning_services, color: Colors.orange),
            SizedBox(width: 8),
            Text('تنظيف البيانات القديمة'),
          ],
        ),
        content: const Text(
          'سيتم حذف البيانات المحذوفة (soft deleted) الأقدم من سنة من Firebase.\n\n'
          'هذا لن يؤثر على البيانات المحلية أو Google Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('تنظيف'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isLoading = true);
    
    try {
      final result = await _firebaseSync.cleanupOldFirebaseData();
      
      if (mounted) {
        if (result['error'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل التنظيف: ${result['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم حذف ${result['deletedCustomers']} عميل و ${result['deletedTransactions']} معاملة قديمة ✅'
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
      
      await _loadSettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التنظيف: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }
  
  Widget _buildIntegrityRow(String label, String value) {
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
  
  /// 🔧 إصلاح ورفع جميع البيانات
  Future<void> _repairAndSyncAll() async {
    // تأكيد قبل الإصلاح
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.build_circle, color: Colors.purple),
            SizedBox(width: 8),
            Text('إصلاح ورفع البيانات'),
          ],
        ),
        content: const Text(
          'سيتم:\n'
          '• إصلاح المعاملات التي ليس لها معرف مزامنة\n'
          '• رفع جميع العملاء والمعاملات إلى Firebase\n\n'
          'هذه العملية قد تستغرق بعض الوقت حسب حجم البيانات.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
            child: const Text('بدء الإصلاح'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() => _isLoading = true);
    
    try {
      final result = await _firebaseSync.repairAndSyncAllTransactions();
      
      if (mounted) {
        if (result['success'] == true) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('تم الإصلاح بنجاح'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIntegrityRow('معاملات تم إصلاحها', '${result['fixed'] ?? 0}'),
                  _buildIntegrityRow('معاملات تم رفعها', '${result['uploaded'] ?? 0}'),
                  _buildIntegrityRow('أخطاء', '${result['errors'] ?? 0}'),
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
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل الإصلاح: ${result['error']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      
      await _loadSettings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الإصلاح: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }
  
  /// 📱 عرض الأجهزة المتصلة
  Future<void> _showConnectedDevices() async {
    setState(() => _isLoading = true);
    
    try {
      final devices = await _firebaseSync.getConnectedDevices();
      final currentDeviceId = _firebaseSync.deviceId;
      
      if (!mounted) return;
      
      // حساب عدد الأجهزة المتصلة فعلياً
      final onlineCount = devices.where((d) => d['isRealtimeSyncActive'] == true).length;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.devices, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الأجهزة في المجموعة'),
                    Text(
                      '$onlineCount من ${devices.length} متصل الآن',
                      style: TextStyle(
                        fontSize: 12,
                        color: onlineCount > 0 ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: devices.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'لا توجد أجهزة مسجلة في هذه المجموعة',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: devices.length,
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      final isCurrentDevice = device['isCurrentDevice'] == true;
                      final isOnline = device['isOnline'] == true;
                      final isRealtimeSyncActive = device['isRealtimeSyncActive'] == true;
                      final realtimeSyncStatus = device['realtimeSyncStatus'] as String? ?? 'غير معروف';
                      
                      // تحديد لون الحالة
                      Color statusColor;
                      IconData statusIcon;
                      if (isRealtimeSyncActive) {
                        statusColor = Colors.green;
                        statusIcon = Icons.sync;
                      } else if (isOnline) {
                        statusColor = Colors.orange;
                        statusIcon = Icons.sync_disabled;
                      } else {
                        statusColor = Colors.grey;
                        statusIcon = Icons.cloud_off;
                      }
                      
                      return Card(
                        color: isCurrentDevice ? Colors.teal.shade50 : null,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // الصف الأول: اسم الجهاز وحالة الاتصال
                              Row(
                                children: [
                                  // أيقونة الجهاز مع نقطة الحالة
                                  Stack(
                                    children: [
                                      Icon(
                                        _getDeviceIcon(device['platform']),
                                        size: 36,
                                        color: isCurrentDevice ? Colors.teal : Colors.grey.shade600,
                                      ),
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 14,
                                          height: 14,
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2),
                                          ),
                                          child: isRealtimeSyncActive
                                              ? const Icon(Icons.check, size: 8, color: Colors.white)
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  // اسم الجهاز
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                device['deviceName'] ?? 'جهاز غير معروف',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                  color: isCurrentDevice ? Colors.teal.shade700 : null,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isCurrentDevice) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal,
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: const Text(
                                                  'أنت',
                                                  style: TextStyle(color: Colors.white, fontSize: 9),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _shortenDeviceId(device['deviceId']),
                                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // زر الحذف
                                  if (!isCurrentDevice)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                      onPressed: () => _confirmRemoveDevice(device),
                                      tooltip: 'إزالة الجهاز',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // الصف الثاني: حالة المزامنة
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: statusColor.withOpacity(0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(statusIcon, size: 16, color: statusColor),
                                    const SizedBox(width: 6),
                                    Text(
                                      realtimeSyncStatus,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              // الصف الثالث: آخر ظهور
                              Row(
                                children: [
                                  Icon(Icons.access_time, size: 12, color: Colors.grey.shade400),
                                  const SizedBox(width: 4),
                                  Text(
                                    'آخر نشاط: ${device['lastSeenFormatted'] ?? 'غير معروف'}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _showConnectedDevices(); // تحديث القائمة
              },
              child: const Text('تحديث'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل جلب قائمة الأجهزة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }
  
  /// الحصول على أيقونة الجهاز حسب المنصة
  IconData _getDeviceIcon(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'windows':
        return Icons.desktop_windows;
      case 'macos':
        return Icons.desktop_mac;
      case 'linux':
        return Icons.computer;
      case 'android':
        return Icons.phone_android;
      case 'ios':
        return Icons.phone_iphone;
      default:
        return Icons.devices_other;
    }
  }
  
  /// اختصار معرف الجهاز
  String _shortenDeviceId(String? deviceId) {
    if (deviceId == null || deviceId.length < 8) return deviceId ?? '';
    return '${deviceId.substring(0, 8)}...';
  }
  
  /// تأكيد إزالة جهاز
  Future<void> _confirmRemoveDevice(Map<String, dynamic> device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إزالة الجهاز'),
        content: Text(
          'هل تريد إزالة الجهاز "${device['deviceName']}" من المجموعة؟\n\n'
          'سيتم إزالة الجهاز من قائمة الأجهزة المتصلة فقط، '
          'ولن يؤثر ذلك على البيانات المزامنة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      Navigator.pop(context); // إغلاق نافذة الأجهزة
      
      final success = await _firebaseSync.removeDevice(device['deviceId']);
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إزالة الجهاز بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
          // إعادة فتح نافذة الأجهزة
          await _showConnectedDevices();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل إزالة الجهاز'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
