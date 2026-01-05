// lib/screens/firebase_sync_settings_screen.dart
// شاشة إعدادات المزامنة عبر Firebase مع حماية صارمة

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/firebase_sync/firebase_sync_config.dart';
import '../services/firebase_sync/firebase_sync_service.dart';
import '../services/password_service.dart';
import 'sync_stats_screen.dart';

class FirebaseSyncSettingsScreen extends StatefulWidget {
  const FirebaseSyncSettingsScreen({super.key});

  @override
  State<FirebaseSyncSettingsScreen> createState() => _FirebaseSyncSettingsScreenState();
}

class _FirebaseSyncSettingsScreenState extends State<FirebaseSyncSettingsScreen> {
  bool _isLoading = false; // 🔧 تغيير: لا نبدأ بالتحميل
  bool _isLoadingStats = false; // 🆕 تحميل الإحصائيات منفصل
  bool _isEnabled = false;
  String? _currentGroupId;
  Map<String, dynamic>? _syncStats;
  String _loadingMessage = ''; // 🆕 رسالة التحميل
  double _loadingProgress = 0.0; // 🆕 نسبة التقدم (0.0 - 1.0)
  
  // 🔒 إعدادات الأمان
  bool _rejectOldTransactions = false;
  int _maxTransactionAgeDays = 30;
  bool _postSyncVerification = true;
  
  // 🔄 حالة تحميل كل زر
  bool _isSyncing = false;
  bool _isVerifying = false;
  bool _isCleaning = false;
  bool _isRepairing = false;
  bool _isLoadingDevices = false;
  bool _isLoadingTrackingStats = false;
  
  final _firebaseSync = FirebaseSyncService();

  @override
  void initState() {
    super.initState();
    _loadSettingsQuick(); // 🔧 تحميل سريع أولاً
  }

  /// 🔧 تحميل سريع للإعدادات الأساسية فقط (بدون Firebase)
  Future<void> _loadSettingsQuick() async {
    _isEnabled = await FirebaseSyncConfig.isEnabled();
    _currentGroupId = await FirebaseSyncConfig.getSyncGroupId();
    
    // 🔒 تحميل إعدادات الأمان
    _rejectOldTransactions = await FirebaseSyncSecuritySettings.isRejectOldTransactionsEnabled();
    _maxTransactionAgeDays = await FirebaseSyncSecuritySettings.getMaxTransactionAgeDays();
    _postSyncVerification = await FirebaseSyncSecuritySettings.isPostSyncVerificationEnabled();
    
    if (mounted) {
      setState(() {});
    }
    
    // تحميل الإحصائيات في الخلفية
    if (_isEnabled && _currentGroupId != null) {
      _loadStatsInBackground();
    }
  }

  /// 🆕 تحميل الإحصائيات في الخلفية مع مؤشر التقدم
  Future<void> _loadStatsInBackground() async {
    if (!mounted) return;
    setState(() {
      _isLoadingStats = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري الاتصال بـ Firebase...';
    });
    
    try {
      // 🔄 محاولة إعادة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        if (mounted) setState(() { _loadingProgress = 0.1; _loadingMessage = 'جاري تهيئة المزامنة...'; });
        await _firebaseSync.initialize();
      }
      
      // المرحلة 1: الاتصال (20%)
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) setState(() { _loadingProgress = 0.2; _loadingMessage = 'جاري تحميل بيانات المجموعة...'; });
      
      // المرحلة 2: تحميل الإحصائيات (20% -> 80%)
      _syncStats = await _firebaseSync.getSyncStats(
        onProgress: (progress, message) {
          if (mounted) {
            setState(() {
              // التقدم من 20% إلى 80%
              _loadingProgress = 0.2 + (progress * 0.6);
              _loadingMessage = message;
            });
          }
        },
      ); // تم إزالة timeout الطويل
      
      // المرحلة 3: الانتهاء (100%)
      if (mounted) setState(() { _loadingProgress = 1.0; _loadingMessage = 'تم التحميل!'; });
      await Future.delayed(const Duration(milliseconds: 300));
      
    } catch (e) {
      _syncStats = {'error': e.toString()};
    }
    
    if (mounted) {
      setState(() {
        _isLoadingStats = false;
        _loadingProgress = 0.0;
        _loadingMessage = '';
      });
    }
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري تحميل الإعدادات...';
    });
    
    _isEnabled = await FirebaseSyncConfig.isEnabled();
    _currentGroupId = await FirebaseSyncConfig.getSyncGroupId();
    
    if (_isEnabled && _currentGroupId != null) {
      if (mounted) {
        setState(() {
          _loadingProgress = 0.2;
          _loadingMessage = 'جاري تحميل الإحصائيات...';
        });
      }
      
      try {
        _syncStats = await _firebaseSync.getSyncStats(
          onProgress: (progress, message) {
            if (mounted) {
              setState(() {
                _loadingProgress = 0.2 + (progress * 0.8);
                _loadingMessage = message;
              });
            }
          },
        );
      } catch (e) {
        _syncStats = {'error': e.toString()};
      }
    }
    
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
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
                    if (_isEnabled)
                      _buildStatsCard(),
                    
                    const SizedBox(height: 16),
                    
                    // 🔒 بطاقة إعدادات الأمان
                    if (_isEnabled)
                      _buildSecuritySettingsCard(),
                    
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'إحصائيات المزامنة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                // 🔧 مؤشر تحميل الإحصائيات مع النسبة
                if (_isLoadingStats)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(_loadingProgress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: _loadingProgress > 0 ? _loadingProgress : null,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepOrange),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(),
            
            // 🔧 عرض حالة التحميل أو الإحصائيات
            if (_isLoadingStats && _syncStats == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    // شريط التقدم الخطي
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _loadingProgress > 0 ? _loadingProgress : null,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepOrange),
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // النسبة المئوية
                    Text(
                      '${(_loadingProgress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // رسالة التحميل
                    Text(
                      _loadingMessage,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else if (_syncStats?['error'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _syncStats!['timeout'] == true 
                            ? 'انتهت مهلة التحميل - اضغط مزامنة الآن'
                            : 'خطأ: ${_syncStats!['error']}',
                        style: const TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              _buildStatRow('المجموعة', _syncStats?['groupId'] ?? '-'),
              _buildStatRow('العملاء في السحابة', '${_syncStats?['customersInCloud'] ?? 0}'),
              _buildStatRow('المعاملات في السحابة', '${_syncStats?['transactionsInCloud'] ?? 0}'),
              _buildStatRow('آخر مزامنة', _formatLastSync(_syncStats?['lastSync'])),
            ],
            
            const SizedBox(height: 16),
            
            // زر المزامنة اليدوية مع مؤشر التقدم
            _buildActionButton(
              icon: Icons.sync,
              label: 'مزامنة الآن',
              isLoading: _isSyncing,
              progress: _isSyncing ? _loadingProgress : null,
              message: _isSyncing ? _loadingMessage : null,
              color: Colors.deepOrange,
              onPressed: _isSyncing ? null : _performManualSync,
              isPrimary: true,
            ),
            
            const SizedBox(height: 8),
            
            // 📊 زر إحصائيات المزامنة (جديد)
            _buildActionButton(
              icon: Icons.analytics,
              label: '📊 إحصائيات المزامنة',
              isLoading: false,
              color: Colors.purple,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SyncStatsScreen()),
                );
              },
            ),
            
            const SizedBox(height: 8),
            
            // 🔒 زر التحقق من سلامة البيانات
            _buildActionButton(
              icon: Icons.verified_user,
              label: 'التحقق من سلامة البيانات',
              isLoading: _isVerifying,
              progress: _isVerifying ? _loadingProgress : null,
              message: _isVerifying ? _loadingMessage : null,
              color: Colors.blue,
              onPressed: _isVerifying ? null : _verifyDataIntegrity,
            ),
            
            const SizedBox(height: 8),
            
            // 🧹 زر تنظيف البيانات القديمة
            _buildActionButton(
              icon: Icons.cleaning_services,
              label: 'تنظيف البيانات القديمة',
              isLoading: _isCleaning,
              progress: _isCleaning ? _loadingProgress : null,
              message: _isCleaning ? _loadingMessage : null,
              color: Colors.orange,
              onPressed: _isCleaning ? null : _cleanupOldData,
            ),
            
            const SizedBox(height: 8),
            
            // 🔧 زر إصلاح ورفع جميع المعاملات
            _buildActionButton(
              icon: Icons.build_circle,
              label: 'إصلاح ورفع جميع البيانات',
              isLoading: _isRepairing,
              progress: _isRepairing ? _loadingProgress : null,
              message: _isRepairing ? _loadingMessage : null,
              color: Colors.purple,
              onPressed: _isRepairing ? null : _repairAndSyncAll,
            ),
            
            const SizedBox(height: 8),
            
            // 📱 زر عرض الأجهزة المتصلة
            _buildActionButton(
              icon: Icons.devices,
              label: 'الأجهزة المتصلة',
              isLoading: _isLoadingDevices,
              color: Colors.teal,
              onPressed: _isLoadingDevices ? null : _showConnectedDevices,
            ),
            
            const SizedBox(height: 8),
            
            // 📊 زر عرض إحصائيات التتبع والإقرار
            _buildActionButton(
              icon: Icons.analytics,
              label: 'إحصائيات التتبع والإقرار',
              isLoading: _isLoadingTrackingStats,
              color: Colors.indigo,
              onPressed: _isLoadingTrackingStats ? null : _showTrackingStats,
            ),
          ],
        ),
      ),
    );
  }
  
  /// 🆕 Widget لبناء زر مع مؤشر تقدم
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isLoading,
    double? progress,
    String? message,
    required Color color,
    required VoidCallback? onPressed,
    bool isPrimary = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          if (isPrimary)
            ElevatedButton.icon(
              onPressed: onPressed,
              icon: isLoading 
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: progress,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(icon),
              label: Text(isLoading && progress != null 
                  ? '$label (${(progress * 100).toInt()}%)'
                  : label),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: onPressed,
              icon: isLoading 
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: progress,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    )
                  : Icon(icon),
              label: Text(isLoading && progress != null 
                  ? '$label (${(progress * 100).toInt()}%)'
                  : label),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
              ),
            ),
          // عرض رسالة التقدم إذا كانت موجودة
          if (isLoading && message != null && message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                message,
                style: TextStyle(fontSize: 11, color: color.withOpacity(0.8)),
                textAlign: TextAlign.center,
              ),
            ),
        ],
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

  /// 🔒 بطاقة إعدادات الأمان
  Widget _buildSecuritySettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.security, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  'إعدادات الأمان',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            
            // 🔒 رفض المعاملات القديمة
            SwitchListTile(
              title: const Text('رفض المعاملات القديمة'),
              subtitle: Text(
                _rejectOldTransactions 
                    ? 'سيتم رفض المعاملات الأقدم من $_maxTransactionAgeDays يوم'
                    : 'قبول جميع المعاملات بغض النظر عن تاريخها',
              ),
              value: _rejectOldTransactions,
              onChanged: (value) async {
                await FirebaseSyncSecuritySettings.setRejectOldTransactionsEnabled(value);
                setState(() => _rejectOldTransactions = value);
              },
              activeColor: Colors.green,
              secondary: const Icon(Icons.history, color: Colors.orange),
            ),
            
            // عدد الأيام (يظهر فقط إذا كان الرفض مفعلاً)
            if (_rejectOldTransactions)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Text('الحد الأقصى للعمر: '),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _maxTransactionAgeDays,
                      items: [7, 14, 30, 60, 90].map((days) {
                        return DropdownMenuItem(
                          value: days,
                          child: Text('$days يوم'),
                        );
                      }).toList(),
                      onChanged: (value) async {
                        if (value != null) {
                          await FirebaseSyncSecuritySettings.setMaxTransactionAgeDays(value);
                          setState(() => _maxTransactionAgeDays = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
            
            const Divider(),
            
            // 🔍 التحقق من الأرصدة بعد المزامنة
            SwitchListTile(
              title: const Text('التحقق من الأرصدة بعد المزامنة'),
              subtitle: Text(
                _postSyncVerification 
                    ? 'سيتم التحقق من صحة الأرصدة بعد كل مزامنة'
                    : 'لن يتم التحقق من الأرصدة تلقائياً',
              ),
              value: _postSyncVerification,
              onChanged: (value) async {
                await FirebaseSyncSecuritySettings.setPostSyncVerificationEnabled(value);
                setState(() => _postSyncVerification = value);
              },
              activeColor: Colors.green,
              secondary: const Icon(Icons.account_balance_wallet, color: Colors.blue),
            ),
          ],
        ),
      ),
    );
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
    if (_isSyncing) return;
    
    setState(() {
      _isSyncing = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري بدء المزامنة...';
    });
    
    try {
      // 🔄 محاولة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        setState(() {
          _loadingProgress = 0.05;
          _loadingMessage = 'جاري تهيئة المزامنة...';
        });
        final initSuccess = await _firebaseSync.initialize().timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
        if (!initSuccess) {
          throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
        }
      }
      
      // استخدام callback للتقدم
      await _firebaseSync.performFullSync(
        onProgress: (progress, message) {
          if (mounted) {
            setState(() {
              _loadingProgress = 0.1 + (progress * 0.75); // 10-85% للمزامنة
              _loadingMessage = message;
            });
          }
        },
      );
      
      // التحقق من الأرصدة (85-95%)
      if (_postSyncVerification) {
        setState(() {
          _loadingProgress = 0.88;
          _loadingMessage = 'جاري التحقق من الأرصدة...';
        });
        
        final verificationResult = await _firebaseSync.verifyBalancesAfterSync();
        
        setState(() {
          _loadingProgress = 0.95;
          _loadingMessage = 'اكتمل التحقق من الأرصدة';
        });
        
        if (verificationResult['hasIssues'] == true) {
          final issues = verificationResult['issues'] as List? ?? [];
          if (mounted && issues.isNotEmpty) {
            _showBalanceVerificationResult(verificationResult);
          }
        }
      }
      
      // الانتهاء (100%)
      setState(() {
        _loadingProgress = 1.0;
        _loadingMessage = 'تمت المزامنة بنجاح!';
      });
      
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadSettingsQuick();
      
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
    
    setState(() {
      _isSyncing = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
  }
  
  /// 🔍 عرض نتيجة التحقق من الأرصدة
  void _showBalanceVerificationResult(Map<String, dynamic> result) {
    final issues = result['issues'] as List? ?? [];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('تحذير: فروقات في الأرصدة'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تم اكتشاف ${issues.length} فرق في الأرصدة:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...issues.take(5).map((issue) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        issue['customerName'] ?? 'عميل غير معروف',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'الرصيد المسجل: ${issue['recordedBalance']?.toStringAsFixed(2) ?? 0}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'الرصيد المحسوب: ${issue['calculatedBalance']?.toStringAsFixed(2) ?? 0}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'الفرق: ${issue['difference']?.toStringAsFixed(2) ?? 0}',
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              )),
              if (issues.length > 5)
                Text(
                  '... و ${issues.length - 5} فروقات أخرى',
                  style: const TextStyle(color: Colors.grey),
                ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }
  
  /// 🔒 التحقق من سلامة البيانات
  Future<void> _verifyDataIntegrity() async {
    if (_isVerifying) return;
    
    setState(() {
      _isVerifying = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري بدء التحقق...';
    });
    
    try {
      // 🔄 محاولة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        setState(() {
          _loadingProgress = 0.05;
          _loadingMessage = 'جاري تهيئة المزامنة...';
        });
        final initSuccess = await _firebaseSync.initialize().timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
        if (!initSuccess) {
          throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
        }
      }
      
      // المرحلة 1: الاتصال بـ Firebase (0-20%)
      setState(() {
        _loadingProgress = 0.1;
        _loadingMessage = 'جاري الاتصال بـ Firebase...';
      });
      await Future.delayed(const Duration(milliseconds: 200));
      
      // المرحلة 2: جلب عدد العملاء (20-40%)
      setState(() {
        _loadingProgress = 0.25;
        _loadingMessage = 'جاري حساب عدد العملاء...';
      });
      
      // المرحلة 3: جلب عدد المعاملات (40-60%)
      setState(() {
        _loadingProgress = 0.45;
        _loadingMessage = 'جاري حساب عدد المعاملات...';
      });
      
      // المرحلة 4: المقارنة (60-90%)
      setState(() {
        _loadingProgress = 0.65;
        _loadingMessage = 'جاري مقارنة البيانات...';
      });
      
      final result = await _firebaseSync.verifyDataIntegrity();
      
      // المرحلة 5: الانتهاء (90-100%)
      setState(() {
        _loadingProgress = 1.0;
        _loadingMessage = 'اكتمل التحقق!';
      });
      
      await Future.delayed(const Duration(milliseconds: 300));
      
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
    
    setState(() {
      _isVerifying = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
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
    
    setState(() {
      _isCleaning = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري بدء التنظيف...';
    });
    
    try {
      // 🔄 محاولة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        setState(() {
          _loadingProgress = 0.05;
          _loadingMessage = 'جاري تهيئة المزامنة...';
        });
        final initSuccess = await _firebaseSync.initialize().timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
        if (!initSuccess) {
          throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
        }
      }
      
      // المرحلة 1: البحث عن المعاملات القديمة (0-30%)
      setState(() {
        _loadingProgress = 0.15;
        _loadingMessage = 'جاري البحث عن المعاملات القديمة...';
      });
      await Future.delayed(const Duration(milliseconds: 200));
      
      // المرحلة 2: حذف المعاملات (30-60%)
      setState(() {
        _loadingProgress = 0.4;
        _loadingMessage = 'جاري حذف المعاملات القديمة...';
      });
      
      // المرحلة 3: البحث عن العملاء القدامى (60-80%)
      setState(() {
        _loadingProgress = 0.65;
        _loadingMessage = 'جاري البحث عن العملاء القدامى...';
      });
      
      final result = await _firebaseSync.cleanupOldFirebaseData();
      
      // المرحلة 4: الانتهاء (80-100%)
      setState(() {
        _loadingProgress = 1.0;
        _loadingMessage = 'اكتمل التنظيف!';
      });
      
      await Future.delayed(const Duration(milliseconds: 300));
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
      
      await _loadSettingsQuick();
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
    
    setState(() {
      _isCleaning = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
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
    
    setState(() {
      _isRepairing = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري بدء الإصلاح...';
    });
    
    try {
      // 🔄 محاولة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        setState(() {
          _loadingProgress = 0.05;
          _loadingMessage = 'جاري تهيئة المزامنة...';
        });
        final initSuccess = await _firebaseSync.initialize().timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
        if (!initSuccess) {
          throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
        }
      }
      
      // المرحلة 1: البحث عن المعاملات بدون UUID (0-20%)
      setState(() {
        _loadingProgress = 0.1;
        _loadingMessage = 'جاري البحث عن المعاملات بدون معرف...';
      });
      await Future.delayed(const Duration(milliseconds: 200));
      
      // المرحلة 2: إصلاح المعاملات (20-50%)
      setState(() {
        _loadingProgress = 0.3;
        _loadingMessage = 'جاري إصلاح المعاملات...';
      });
      
      // المرحلة 3: رفع العملاء (50-70%)
      setState(() {
        _loadingProgress = 0.55;
        _loadingMessage = 'جاري رفع العملاء...';
      });
      
      // المرحلة 4: رفع المعاملات (70-95%)
      setState(() {
        _loadingProgress = 0.75;
        _loadingMessage = 'جاري رفع المعاملات...';
      });
      
      final result = await _firebaseSync.repairAndSyncAllTransactions();
      
      // المرحلة 5: الانتهاء (95-100%)
      setState(() {
        _loadingProgress = 1.0;
        _loadingMessage = 'اكتمل الإصلاح!';
      });
      
      await Future.delayed(const Duration(milliseconds: 300));
      
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
      
      await _loadSettingsQuick();
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
    
    setState(() {
      _isRepairing = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
  }
  
  /// 📱 عرض الأجهزة المتصلة
  Future<void> _showConnectedDevices() async {
    setState(() {
      _isLoadingDevices = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري جلب قائمة الأجهزة...';
    });
    
    try {
      // 🔄 محاولة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        setState(() {
          _loadingProgress = 0.1;
          _loadingMessage = 'جاري تهيئة المزامنة...';
        });
        final initSuccess = await _firebaseSync.initialize().timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
        if (!initSuccess) {
          throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
        }
      }
      
      // المرحلة 1: الاتصال (0-30%)
      setState(() {
        _loadingProgress = 0.2;
        _loadingMessage = 'جاري الاتصال بـ Firebase...';
      });
      
      // المرحلة 2: جلب البيانات (30-80%)
      setState(() {
        _loadingProgress = 0.5;
        _loadingMessage = 'جاري جلب بيانات الأجهزة...';
      });
      
      final devices = await _firebaseSync.getConnectedDevices();
      final currentDeviceId = _firebaseSync.deviceId;
      
      // المرحلة 3: الانتهاء (80-100%)
      setState(() {
        _loadingProgress = 1.0;
        _loadingMessage = 'تم جلب البيانات!';
      });
      
      await Future.delayed(const Duration(milliseconds: 200));
      
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
    
    setState(() {
      _isLoadingDevices = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
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
  
  /// 📊 عرض إحصائيات التتبع والإقرار
  Future<void> _showTrackingStats() async {
    if (!mounted) return;
    
    setState(() {
      _isLoadingTrackingStats = true;
      _loadingProgress = 0.0;
      _loadingMessage = 'جاري جلب الإحصائيات...';
    });
    
    try {
      // 🔄 محاولة التهيئة إذا لم تكن مكتملة
      if (_firebaseSync.status == FirebaseSyncStatus.notConfigured ||
          _firebaseSync.status == FirebaseSyncStatus.idle ||
          _firebaseSync.status == FirebaseSyncStatus.error) {
        setState(() {
          _loadingProgress = 0.05;
          _loadingMessage = 'جاري تهيئة المزامنة...';
        });
        final initSuccess = await _firebaseSync.initialize().timeout(
          const Duration(minutes: 2),
          onTimeout: () => false,
        );
        if (!initSuccess) {
          throw Exception('فشلت تهيئة المزامنة - تأكد من الاتصال بالإنترنت');
        }
      }
      
      // المرحلة 1: جلب إحصائيات التتبع (0-25%)
      setState(() {
        _loadingProgress = 0.15;
        _loadingMessage = 'جاري جلب إحصائيات التتبع...';
      });
      final trackerStats = await _firebaseSync.getOperationTrackerStats();
      
      // المرحلة 2: جلب ملخص التأكيدات (25-50%)
      setState(() {
        _loadingProgress = 0.35;
        _loadingMessage = 'جاري جلب ملخص التأكيدات...';
      });
      final ackSummary = await _firebaseSync.getAckSummary();
      
      // المرحلة 3: جلب التأكيدات المعلقة (50-70%)
      setState(() {
        _loadingProgress = 0.55;
        _loadingMessage = 'جاري جلب التأكيدات المعلقة...';
      });
      final pendingAcks = await _firebaseSync.getPendingAckTransactions();
      
      // المرحلة 4: جلب إحصائيات WAL (70-90%)
      setState(() {
        _loadingProgress = 0.75;
        _loadingMessage = 'جاري جلب إحصائيات الحماية...';
      });
      final walStats = await _firebaseSync.getWalRecoveryStats();
      final pendingWal = await _firebaseSync.getPendingWalOperationsCount();
      
      // المرحلة 5: الانتهاء (90-100%)
      setState(() {
        _loadingProgress = 1.0;
        _loadingMessage = 'تم جلب الإحصائيات!';
      });
      
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.analytics, color: Colors.indigo),
              SizedBox(width: 8),
              Text('إحصائيات التتبع والإقرار'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🛡️ قسم WAL (الحماية من الانقطاع)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🛡️ الحماية من الانقطاع (WAL)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow('العمليات المعلقة', '$pendingWal'),
                      _buildStatRow('إجمالي العمليات', '${walStats['totalOperations'] ?? 0}'),
                      _buildStatRow('العمليات المستردة', '${walStats['recoveredOperations'] ?? 0}'),
                      _buildStatRow('نقاط الاسترداد', '${walStats['activeCheckpoints'] ?? 0}'),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // قسم تتبع العمليات
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🔄 تتبع العمليات',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow('العمليات المعلقة', '${trackerStats['pendingOperations'] ?? 0}'),
                      _buildStatRow('الكيانات المتتبعة', '${trackerStats['trackedEntities'] ?? 0}'),
                      _buildStatRow('سجلات العمليات', '${trackerStats['logEntries'] ?? 0}'),
                    ],
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // قسم تأكيدات الاستلام
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📬 تأكيدات الاستلام (ACK)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow('المعاملات المرسلة', '${ackSummary['sentTransactions'] ?? 0}'),
                      _buildStatRow('التأكيدات المستلمة', '${ackSummary['receivedAcks'] ?? 0}'),
                      _buildStatRow('في انتظار التأكيد', '${pendingAcks.length}'),
                    ],
                  ),
                ),
                
                if (pendingAcks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.warning, color: Colors.orange, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'معاملات لم يتم تأكيدها',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'هناك ${pendingAcks.length} معاملة لم يتم تأكيد استلامها من الأجهزة الأخرى بعد.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                // تنظيف السجلات القديمة
                final deletedAcks = await _firebaseSync.cleanupOldAcks();
                final deletedLogs = await _firebaseSync.cleanupOldOperationLogs();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('تم حذف $deletedAcks تأكيد و $deletedLogs سجل قديم'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('تنظيف القديم'),
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
            content: Text('فشل جلب الإحصائيات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    if (!mounted) return;
    setState(() {
      _isLoadingTrackingStats = false;
      _loadingProgress = 0.0;
      _loadingMessage = '';
    });
  }
}
