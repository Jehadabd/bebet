// lib/services/firebase_sync/cross_device_verifier.dart
// خدمة الفحص المتبادل بين الأجهزة لضمان أمان 100%

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../database_service.dart';
import 'device_snapshot_service.dart';
import 'firebase_sync_service.dart';

/// خدمة الفحص المتبادل بين الأجهزة
/// تتحقق من تطابق البيانات بين الأجهزة بعد 15 دقيقة اتصال متواصل
class CrossDeviceVerifier {
  static CrossDeviceVerifier? _instance;
  static CrossDeviceVerifier get instance {
    _instance ??= CrossDeviceVerifier._();
    return _instance!;
  }
  
  CrossDeviceVerifier._();
  
  final DatabaseService _db = DatabaseService();
  final DeviceSnapshotService _snapshotService = DeviceSnapshotService.instance;
  
  Timer? _connectionTimer;
  Timer? _verificationCheckTimer;
  StreamSubscription? _connectivitySubscription;
  
  bool _isInitialized = false;
  bool _hasVerifiedThisSession = false;
  String? _deviceId;
  
  // Stream للإشعارات
  final _mismatchController = StreamController<List<BalanceMismatch>>.broadcast();
  Stream<List<BalanceMismatch>> get mismatchStream => _mismatchController.stream;
  
  // Callback لعرض الرسالة
  void Function(List<BalanceMismatch>)? onMismatchDetected;
  
  /// تهيئة الخدمة
  void initialize(String deviceId) {
    _deviceId = deviceId;
    _isInitialized = true;
    _hasVerifiedThisSession = false;
    
    // بدء مراقبة الاتصال
    _startConnectivityMonitoring();
    
    // بدء عداد الفحص الدوري
    _startVerificationChecker();
    
    print('✅ تم تهيئة CrossDeviceVerifier');
  }
  
  /// إيقاف الخدمة
  void dispose() {
    _connectionTimer?.cancel();
    _verificationCheckTimer?.cancel();
    _connectivitySubscription?.cancel();
    _mismatchController.close();
    _isInitialized = false;
  }
  
  /// مراقبة حالة الاتصال
  void _startConnectivityMonitoring() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      
      if (!hasConnection) {
        // انقطع الإنترنت - تصفير الوقت
        _snapshotService.resetOnlineSince();
        _hasVerifiedThisSession = false;
        print('📴 انقطع الإنترنت - تم تصفير عداد الاتصال');
      }
    });
  }
  
  /// فحص دوري كل دقيقة
  void _startVerificationChecker() {
    _verificationCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _checkAndVerify();
    });
  }
  
  /// فحص الشروط وتنفيذ التحقق
  Future<void> _checkAndVerify() async {
    if (!_isInitialized) return;
    if (_hasVerifiedThisSession) return; // تم الفحص في هذه الجلسة
    
    // التحقق من الاتصال
    final connectivityResult = await Connectivity().checkConnectivity();
    final hasConnection = connectivityResult.any((r) => r != ConnectivityResult.none);
    if (!hasConnection) return;
    
    // التحقق من شرط الـ 15 دقيقة
    if (!_snapshotService.hasBeenOnlineFor15Minutes) {
      print('⏳ لم تمر 15 دقيقة بعد (${_snapshotService.connectionDurationSeconds ~/ 60} دقيقة)');
      return;
    }
    
    // جلب أجهزة أخرى متصلة
    final remoteSnapshots = await _snapshotService.getAllRemoteSnapshots();
    if (remoteSnapshots.isEmpty) {
      print('ℹ️ لا توجد أجهزة أخرى للمقارنة');
      return;
    }
    
    // التحقق من أن الأجهزة الأخرى متصلة لـ 15 دقيقة أيضاً
    final now = DateTime.now().toUtc();
    final eligibleDevices = remoteSnapshots.where((snapshot) {
      final onlineSinceStr = snapshot['onlineSince'] as String?;
      if (onlineSinceStr == null) return false;
      
      try {
        final onlineSince = DateTime.parse(onlineSinceStr);
        final connectionDuration = now.difference(onlineSince).inSeconds;
        return connectionDuration >= 900; // 15 دقيقة
      } catch (_) {
        return false;
      }
    }).toList();
    
    if (eligibleDevices.isEmpty) {
      print('⏳ لا توجد أجهزة متصلة لـ 15 دقيقة للمقارنة');
      return;
    }
    
    print('🔍 بدء الفحص المتبادل مع ${eligibleDevices.length} جهاز...');
    
    // تنفيذ الفحص
    final allMismatches = <BalanceMismatch>[];
    
    for (final remoteSnapshot in eligibleDevices) {
      final remoteDeviceId = remoteSnapshot['deviceId'] as String?;
      if (remoteDeviceId == null || remoteDeviceId == _deviceId) continue;
      
      final mismatches = await _snapshotService.compareWithRemoteDevice(remoteDeviceId);
      allMismatches.addAll(mismatches);
    }
    
    _hasVerifiedThisSession = true;
    
    if (allMismatches.isNotEmpty) {
      print('⚠️ تم اكتشاف ${allMismatches.length} اختلاف!');
      
      // تسجيل الأخطاء في قاعدة البيانات
      await _logMismatches(allMismatches);
      
      // إرسال إشعار
      _mismatchController.add(allMismatches);
      onMismatchDetected?.call(allMismatches);
    } else {
      print('✅ جميع الأرصدة متطابقة!');
    }
  }
  
  /// تسجيل الأخطاء في قاعدة البيانات
  Future<void> _logMismatches(List<BalanceMismatch> mismatches) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    
    for (final mismatch in mismatches) {
      await db.insert('sync_integrity_errors', {
        'error_type': 'balance_mismatch',
        'customer_name': mismatch.customerName,
        'local_balance': mismatch.localBalance,
        'remote_balance': mismatch.remoteBalance,
        'difference': mismatch.difference,
        'local_device_id': _deviceId,
        'remote_device_id': mismatch.remoteDeviceId,
        'detected_at': now,
        'resolved': 0,
      });
    }
    
    print('📝 تم تسجيل ${mismatches.length} خطأ في السجل');
  }
  
  /// الحصول على الأخطاء غير المحلولة
  Future<List<Map<String, dynamic>>> getUnresolvedErrors() async {
    final db = await _db.database;
    return await db.query(
      'sync_integrity_errors',
      where: 'resolved = 0',
      orderBy: 'detected_at DESC',
    );
  }
  
  /// الحصول على جميع الأخطاء
  Future<List<Map<String, dynamic>>> getAllErrors() async {
    final db = await _db.database;
    return await db.query(
      'sync_integrity_errors',
      orderBy: 'detected_at DESC',
    );
  }
  
  /// تعليم خطأ كمحلول
  Future<void> markErrorAsResolved(int errorId, {String? notes}) async {
    final db = await _db.database;
    await db.update(
      'sync_integrity_errors',
      {
        'resolved': 1,
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
        'notes': notes,
      },
      where: 'id = ?',
      whereArgs: [errorId],
    );
  }
  
  /// فحص فوري (يدوي)
  Future<List<BalanceMismatch>> performManualVerification() async {
    final allMismatches = <BalanceMismatch>[];
    
    final remoteSnapshots = await _snapshotService.getAllRemoteSnapshots();
    
    for (final remoteSnapshot in remoteSnapshots) {
      final remoteDeviceId = remoteSnapshot['deviceId'] as String?;
      if (remoteDeviceId == null || remoteDeviceId == _deviceId) continue;
      
      final mismatches = await _snapshotService.compareWithRemoteDevice(remoteDeviceId);
      allMismatches.addAll(mismatches);
    }
    
    if (allMismatches.isNotEmpty) {
      await _logMismatches(allMismatches);
    }
    
    return allMismatches;
  }
  
  /// إعادة تعيين الجلسة (للاختبار)
  void resetSession() {
    _hasVerifiedThisSession = false;
  }
}

/// دالة مساعدة لعرض رسالة الخطأ
void showMismatchDialog(BuildContext context, List<BalanceMismatch> mismatches) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'اكتشاف اختلاف في الأرصدة',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تم اكتشاف ${mismatches.length} اختلاف في أرصدة العملاء:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: mismatches.length,
                itemBuilder: (context, index) {
                  final mismatch = mismatches[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person, size: 16, color: Colors.orange),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  mismatch.customerName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('رصيده هنا: ${_formatNumber(mismatch.localBalance)}'),
                          Text('رصيده في ${mismatch.remoteDeviceName}: ${_formatNumber(mismatch.remoteBalance)}'),
                          Text(
                            'الفرق: ${_formatNumber(mismatch.difference)}',
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'يرجى مراجعة سجل الديون لهؤلاء العملاء يدوياً للتأكد من صحة البيانات.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepOrange,
            foregroundColor: Colors.white,
          ),
          child: const Text('حسناً'),
        ),
      ],
    ),
  );
}

String _formatNumber(double number) {
  if (number >= 1000000) {
    return '${(number / 1000000).toStringAsFixed(2)} مليون';
  } else if (number >= 1000) {
    return '${(number / 1000).toStringAsFixed(1)} ألف';
  }
  return number.toStringAsFixed(0);
}
