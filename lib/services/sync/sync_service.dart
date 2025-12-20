// lib/services/sync/sync_service.dart
// خدمة المزامنة الموحدة - واجهة سهلة للاستخدام في التطبيق
//
// هذه الخدمة تربط بين:
// 1. DriveService (للمصادقة مع Google)
// 2. OptimizedSyncEngine (للمزامنة الفعلية)
// 3. SyncTracker (لتتبع التغييرات)

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../drive_service.dart';
import '../database_service.dart';
import 'sync_engine_optimized.dart';
import 'sync_local_storage.dart';
import 'sync_models.dart';
import 'sync_security.dart';
import 'sync_audit_service.dart';

/// حالة المزامنة
enum SyncStatus {
  idle,           // في انتظار
  connecting,     // جاري الاتصال
  syncing,        // جاري المزامنة
  success,        // نجحت
  failed,         // فشلت
  offline,        // لا يوجد اتصال
  notSignedIn,    // غير مسجل الدخول
}

/// معلومات عملية فاشلة
class FailedOperation {
  final String customerName;
  final double amount;
  final String operationType; // تسديد أو إضافة
  final String date;
  final String error;
  
  FailedOperation({
    required this.customerName,
    required this.amount,
    required this.operationType,
    required this.date,
    required this.error,
  });
  
  @override
  String toString() {
    return '$operationType - $customerName: $amount ($date)';
  }
}

/// نتيجة المزامنة
class SyncResult {
  final bool success;
  final String message;
  final int downloaded;
  final int uploaded;
  final int applied;
  final int failed;
  final Duration duration;
  final String? error;
  final List<FailedOperation> failedOperations;
  
  SyncResult({
    required this.success,
    required this.message,
    this.downloaded = 0,
    this.uploaded = 0,
    this.applied = 0,
    this.failed = 0,
    this.duration = Duration.zero,
    this.error,
    this.failedOperations = const [],
  });
  
  /// هل هناك عمليات فاشلة؟
  bool get hasFailedOperations => failedOperations.isNotEmpty;
}

/// ═══════════════════════════════════════════════════════════════════════════
/// خدمة المزامنة الموحدة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();
  
  final DriveService _driveService = DriveService();
  final DatabaseService _db = DatabaseService();
  final SyncLocalStorage _localStorage = SyncLocalStorage();
  
  OptimizedSyncEngine? _syncEngine;
  http.Client? _httpClient;
  
  // حالة المزامنة
  SyncStatus _status = SyncStatus.idle;
  String _statusMessage = '';
  double _progress = 0.0;
  
  // Callbacks
  final _statusController = StreamController<SyncStatus>.broadcast();
  final _messageController = StreamController<String>.broadcast();
  final _progressController = StreamController<double>.broadcast();
  
  Stream<SyncStatus> get statusStream => _statusController.stream;
  Stream<String> get messageStream => _messageController.stream;
  Stream<double> get progressStream => _progressController.stream;
  
  SyncStatus get status => _status;
  String get statusMessage => _statusMessage;
  double get progress => _progress;
  bool get isSyncing => _status == SyncStatus.syncing;
  
  // 🔒 Callbacks للأمان - يمكن تعيينها من الواجهة
  Future<bool> Function(List<PendingLargeTransaction>)? onLargeTransactionsDetected;
  void Function(PostSyncVerificationResult)? onVerificationComplete;
  
  /// الحصول على خدمة التدقيق
  SyncAuditService? get auditService => _syncEngine?.auditService;
  
  // متغير لتتبع حالة التهيئة
  bool _isInitialized = false;
  bool _isInitializing = false;
  
  /// تهيئة خدمة المزامنة
  Future<bool> initialize() async {
    // تجنب التهيئة المتكررة
    if (_isInitialized && _syncEngine != null && _syncEngine!.isReady) {
      return true;
    }
    
    // تجنب التهيئة المتزامنة
    if (_isInitializing) {
      // انتظار حتى تنتهي التهيئة الجارية
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _isInitialized;
    }
    
    _isInitializing = true;
    
    try {
      // التحقق من تسجيل الدخول
      final isSignedIn = await _driveService.isSignedIn();
      if (!isSignedIn) {
        _updateStatus(SyncStatus.notSignedIn, 'يرجى تسجيل الدخول أولاً');
        return false;
      }
      
      // تهيئة جداول المزامنة المحلية
      await _localStorage.ensureSyncTables();
      
      // الحصول على معرف الجهاز
      final deviceId = await _getDeviceId();
      final deviceName = await _getDeviceName();
      
      // الحصول على HTTP Client المصادق
      _httpClient = await _getAuthenticatedClient();
      if (_httpClient == null) {
        _updateStatus(SyncStatus.failed, 'فشل الحصول على صلاحيات Google Drive');
        return false;
      }
      
      // إنشاء محرك المزامنة
      _syncEngine = OptimizedSyncEngine(
        config: const OptimizedSyncConfig(
          maxStorageMB: 300,        // 300MB كحد أقصى
          maxSnapshotsToKeep: 3,
          maxOperationFilesToKeep: 10,
          enableCompression: true,
          snapshotEveryNOperations: 200,
        ),
        securityConfig: const SyncSecurityConfig(
          largeTransactionThreshold: 10000000, // 10 مليون
          maxTransactionAgeDays: 30, // شهر
          maxBackupsToKeep: 3,
          enablePreSyncBackup: true,
          enablePostSyncVerification: true,
          enableLargeTransactionConfirmation: true,
          enableOldTransactionRejection: true,
        ),
      );
      
      // تهيئة المحرك
      await _syncEngine!.initialize(
        httpClient: _httpClient!,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      
      // ربط الـ callbacks
      _syncEngine!.onStatusChange = (msg) {
        _updateStatus(_status, msg);
      };
      
      _syncEngine!.onProgress = (p) {
        _progress = p;
        _progressController.add(p);
      };
      
      // ربط callbacks الأمان
      _syncEngine!.onLargeTransactionsDetected = onLargeTransactionsDetected;
      _syncEngine!.onVerificationComplete = onVerificationComplete;
      
      _updateStatus(SyncStatus.idle, 'جاهز للمزامنة');
      _isInitialized = true;
      return true;
      
    } catch (e) {
      print('❌ فشل تهيئة خدمة المزامنة: $e');
      _updateStatus(SyncStatus.failed, 'فشل التهيئة: $e');
      return false;
    } finally {
      _isInitializing = false;
    }
  }
  
  /// تنفيذ المزامنة الكاملة
  Future<SyncResult> sync() async {
    // التحقق من الحالة
    if (_status == SyncStatus.syncing) {
      return SyncResult(
        success: false,
        message: 'المزامنة جارية بالفعل',
      );
    }
    
    // التحقق من تسجيل الدخول
    final isSignedIn = await _driveService.isSignedIn();
    if (!isSignedIn) {
      _updateStatus(SyncStatus.notSignedIn, 'يرجى تسجيل الدخول أولاً');
      return SyncResult(
        success: false,
        message: 'يرجى تسجيل الدخول إلى Google Drive أولاً',
      );
    }
    
    // تهيئة المحرك إذا لم يكن جاهزاً
    if (_syncEngine == null || !_syncEngine!.isReady) {
      final initialized = await initialize();
      if (!initialized) {
        return SyncResult(
          success: false,
          message: 'فشل تهيئة نظام المزامنة',
        );
      }
    }
    
    _updateStatus(SyncStatus.syncing, 'جاري المزامنة...');
    
    try {
      // تنفيذ المزامنة
      final report = await _syncEngine!.performOptimizedSync();
      
      if (report.success) {
        if (report.hasFailedOperations) {
          _updateStatus(SyncStatus.success, 'تمت المزامنة مع ${report.operationsFailed} عملية فاشلة ⚠️');
        } else {
          _updateStatus(SyncStatus.success, 'تمت المزامنة بنجاح ✅');
        }
        
        // تحويل FailedOperationInfo إلى FailedOperation
        final failedOps = report.failedOperations.map((info) => FailedOperation(
          customerName: info.customerName,
          amount: info.amount,
          operationType: info.operationType,
          date: info.date,
          error: info.error,
        )).toList();
        
        return SyncResult(
          success: true,
          message: report.hasFailedOperations 
              ? 'تمت المزامنة مع ${report.operationsFailed} عملية فاشلة'
              : 'تمت المزامنة بنجاح',
          downloaded: report.operationsDownloaded,
          uploaded: report.operationsUploaded,
          applied: report.operationsApplied,
          failed: report.operationsFailed,
          duration: report.duration,
          failedOperations: failedOps,
        );
      } else {
        _updateStatus(SyncStatus.failed, report.errorMessage ?? 'فشلت المزامنة');
        
        return SyncResult(
          success: false,
          message: report.errorMessage ?? 'فشلت المزامنة',
          error: report.errorMessage,
          duration: report.duration,
        );
      }
      
    } catch (e) {
      print('❌ خطأ في المزامنة: $e');
      _updateStatus(SyncStatus.failed, 'خطأ: $e');
      
      return SyncResult(
        success: false,
        message: 'حدث خطأ أثناء المزامنة',
        error: e.toString(),
      );
    }
  }
  
  /// مزامنة سريعة (تنزيل فقط)
  Future<SyncResult> quickSync() async {
    if (_syncEngine == null || !_syncEngine!.isReady) {
      final initialized = await initialize();
      if (!initialized) {
        return SyncResult(success: false, message: 'فشل التهيئة');
      }
    }
    
    try {
      final report = await _syncEngine!.performQuickSync();
      
      return SyncResult(
        success: report.success,
        message: report.success ? 'تم التحديث' : (report.errorMessage ?? 'فشل'),
        downloaded: report.operationsDownloaded,
        applied: report.operationsApplied,
      );
    } catch (e) {
      return SyncResult(success: false, message: e.toString());
    }
  }
  
  /// فحص المساحة المستخدمة
  Future<Map<String, dynamic>> checkStorage() async {
    if (_syncEngine == null || !_syncEngine!.isReady) {
      return {'error': 'المحرك غير جاهز'};
    }
    
    try {
      final report = await _syncEngine!.checkStorageUsage();
      return report.toJson();
    } catch (e) {
      return {'error': e.toString()};
    }
  }
  
  /// تنظيف المساحة
  Future<bool> cleanupStorage() async {
    if (_syncEngine == null || !_syncEngine!.isReady) {
      return false;
    }
    
    try {
      await _syncEngine!.performSmartCleanup();
      return true;
    } catch (e) {
      print('❌ فشل التنظيف: $e');
      return false;
    }
  }
  
  /// الحصول على ملخص العمليات المعلقة (للعرض في رسالة التأكيد)
  Future<Map<String, int>> getPendingSyncSummary() async {
    try {
      final db = await _db.database;
      
      // عدد العمليات المعلقة
      final pendingOps = await db.query(
        'sync_operations',
        where: 'status = ?',
        whereArgs: ['pending'],
      );
      
      // تصنيف العمليات
      int customerOps = 0;
      int transactionOps = 0;
      
      for (final op in pendingOps) {
        final data = op['data'] as String?;
        if (data != null) {
          if (data.contains('"entity_type":"customer"')) {
            customerOps++;
          } else if (data.contains('"entity_type":"transaction"')) {
            transactionOps++;
          }
        }
      }
      
      return {
        'total': pendingOps.length,
        'customers': customerOps,
        'transactions': transactionOps,
      };
    } catch (e) {
      print('⚠️ خطأ في الحصول على ملخص العمليات: $e');
      return {'total': 0, 'customers': 0, 'transactions': 0};
    }
  }
  
  /// تنفيذ النقل الكامل
  Future<SyncResult> performFullTransfer() async {
    // التحقق من تسجيل الدخول
    final isSignedIn = await _driveService.isSignedIn();
    if (!isSignedIn) {
      return SyncResult(
        success: false,
        message: 'يرجى تسجيل الدخول إلى Google Drive أولاً',
      );
    }
    
    // تهيئة المحرك إذا لم يكن جاهزاً
    if (_syncEngine == null || !_syncEngine!.isReady) {
      final initialized = await initialize();
      if (!initialized) {
        return SyncResult(
          success: false,
          message: 'فشل تهيئة نظام المزامنة',
        );
      }
    }
    
    _updateStatus(SyncStatus.syncing, 'جاري النقل الكامل...');
    
    try {
      final report = await _syncEngine!.performFullTransfer();
      
      if (report.success) {
        _updateStatus(SyncStatus.success, 'تم النقل الكامل بنجاح ✅');
        return SyncResult(
          success: true,
          message: 'تم نقل جميع البيانات بنجاح',
          uploaded: report.operationsUploaded,
          duration: report.duration,
        );
      } else {
        _updateStatus(SyncStatus.failed, report.errorMessage ?? 'فشل النقل الكامل');
        return SyncResult(
          success: false,
          message: report.errorMessage ?? 'فشل النقل الكامل',
          error: report.errorMessage,
        );
      }
    } catch (e) {
      _updateStatus(SyncStatus.failed, 'خطأ: $e');
      return SyncResult(
        success: false,
        message: 'حدث خطأ أثناء النقل الكامل',
        error: e.toString(),
      );
    }
  }
  
  /// الحصول على معرف الجهاز (ثابت ومحفوظ)
  /// 
  /// يتم توليد UUID فريد مرة واحدة فقط عند أول تشغيل
  /// ويُحفظ في التخزين الآمن ليبقى ثابتاً حتى لو تغيرت الشبكة
  Future<String> _getDeviceId() async {
    return await SyncSecurity.getOrCreateDeviceId();
  }
  
  Future<String> _getDeviceName() async {
    // يمكن تحسين هذا لاحقاً للحصول على اسم الجهاز الفعلي
    return 'جهاز المستخدم';
  }
  
  Future<http.Client?> _getAuthenticatedClient() async {
    try {
      final client = await _driveService.getAuthenticatedHttpClient();
      print('✅ تم الحصول على HTTP Client بنجاح');
      return client;
    } catch (e) {
      print('❌ فشل الحصول على HTTP Client: $e');
      _updateStatus(SyncStatus.failed, 'فشل المصادقة: $e');
      return null;
    }
  }
  
  void _updateStatus(SyncStatus status, String message) {
    _status = status;
    _statusMessage = message;
    _statusController.add(status);
    _messageController.add(message);
    print('🔄 Sync: $message');
  }
  
  /// فرض فتح القفل يدوياً (للحالات الطارئة)
  /// يُستخدم عندما يعلق القفل ولا يمكن الحصول عليه
  Future<bool> forceReleaseLock() async {
    // تهيئة المحرك إذا لم يكن جاهزاً
    if (_syncEngine == null || !_syncEngine!.isReady) {
      final initialized = await initialize();
      if (!initialized) {
        print('❌ فشل تهيئة المحرك لفرض فتح القفل');
        return false;
      }
    }
    
    try {
      final result = await _syncEngine!.forceUnlock();
      if (result) {
        _updateStatus(SyncStatus.idle, 'تم فرض فتح القفل بنجاح ✅');
      }
      return result;
    } catch (e) {
      print('❌ خطأ في فرض فتح القفل: $e');
      _updateStatus(SyncStatus.failed, 'فشل فرض فتح القفل: $e');
      return false;
    }
  }
  
  /// التحقق من حالة القفل الحالي
  Future<Map<String, dynamic>?> checkLockStatus() async {
    // تهيئة المحرك إذا لم يكن جاهزاً
    if (_syncEngine == null || !_syncEngine!.isReady) {
      final initialized = await initialize();
      if (!initialized) {
        return {'error': 'فشل تهيئة المحرك'};
      }
    }
    
    try {
      return await _syncEngine!.checkLockStatus();
    } catch (e) {
      print('❌ خطأ في التحقق من حالة القفل: $e');
      return {'error': e.toString()};
    }
  }

  /// إغلاق الخدمة
  void dispose() {
    _syncEngine?.dispose();
    _httpClient?.close();
    _statusController.close();
    _messageController.close();
    _progressController.close();
  }
}

// تم إضافة getAuthenticatedHttpClient() في DriveService
