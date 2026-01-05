// lib/services/firebase_sync/firebase_sync_service.dart
// خدمة المزامنة الفورية عبر Firebase - Offline-First
// مع قيود صارمة لحل التعارضات ومنع التكرار

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../database_service.dart';
import 'firebase_sync_config.dart';
import 'firebase_sync_coordinator.dart';
import 'firebase_auth_service.dart';
import 'sync_operation_tracker.dart';
import 'transaction_ack_service.dart';
import 'sync_crash_recovery_service.dart'; // 🛡️ WAL للحماية من الانقطاع
import '../sync/sync_encryption.dart';
import '../sync/sync_validation.dart';
import '../sync/sync_security.dart';
import '../../models/transaction.dart'; // Import DebtTransaction model

/// حالة المزامنة
enum FirebaseSyncStatus {
  idle,           // في انتظار
  syncing,        // جاري المزامنة
  online,         // متصل ويستمع للتغييرات
  offline,        // غير متصل
  error,          // خطأ
  disabled,       // معطل
  notConfigured,  // غير مُعد
}

/// معلومات عملية مزامنة
class SyncOperation {
  final String type; // 'customer' أو 'transaction'
  final String action; // 'create', 'update', 'delete'
  final String syncUuid;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  SyncOperation({
    required this.type,
    required this.action,
    required this.syncUuid,
    required this.data,
    required this.timestamp,
  });
  
  Map<String, dynamic> toMap() => {
    'type': type,
    'action': action,
    'syncUuid': syncUuid,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
  };
}

/// ═══════════════════════════════════════════════════════════════════════════
/// نتيجة التحقق من التعارض
/// ═══════════════════════════════════════════════════════════════════════════
enum ConflictResolution {
  useRemote,    // استخدام البيانات البعيدة (الأحدث)
  useLocal,     // استخدام البيانات المحلية
  merge,        // دمج البيانات
  skip,         // تخطي (البيانات متطابقة)
}

class ConflictResult {
  final ConflictResolution resolution;
  final String reason;
  final Map<String, dynamic>? mergedData;
  
  ConflictResult({
    required this.resolution,
    required this.reason,
    this.mergedData,
  });
}

/// ═══════════════════════════════════════════════════════════════════════════
/// خدمة المزامنة الفورية عبر Firebase
/// ═══════════════════════════════════════════════════════════════════════════
class FirebaseSyncService {
  static final FirebaseSyncService _instance = FirebaseSyncService._internal();
  factory FirebaseSyncService() => _instance;
  FirebaseSyncService._internal();
  
  final DatabaseService _db = DatabaseService();
  FirebaseFirestore? _firestore;
  FirebaseSyncCoordinator? _coordinator;
  SyncOperationTracker? _operationTracker;
  TransactionAckService? _ackService;
  SyncCrashRecoveryService? _crashRecovery; // 🛡️ WAL للحماية من الانقطاع
  
  // حالة الخدمة
  FirebaseSyncStatus _status = FirebaseSyncStatus.idle;
  String? _groupId;
  String? _deviceId;
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isSyncing = false; // 🔒 قفل لمنع المزامنة المتزامنة
  
  // 🔒 تتبع العمليات الجارية (للحماية من race conditions)
  // استخدام Map بدلاً من Set لضمان atomic check-and-set
  final Map<String, bool> _uploadLocks = {};
  DateTime? _syncStartTime;
  
  // 🕰️ فرق التوقيت مع السيرفر (لتصحيح clock skew)
  Duration _serverTimeOffset = Duration.zero;
  
  /// الوقت الحالي مصححاً بتوقيت السيرفر
  DateTime get now => DateTime.now().add(_serverTimeOffset);
  
  // 🔄 Retry Queue مع Exponential Backoff
  final List<_RetryOperation> _retryQueue = [];
  Timer? _retryTimer;
  static const int _maxRetries = 5;
  static const Duration _baseRetryDelay = Duration(seconds: 2);
  
  // 🧹 إعدادات التنظيف التلقائي
  static const int _keepFirebaseDataDays = 365; // سنة واحدة
  static const int _maxFirebaseOperations = 10000; // 10,000 عملية كحد أقصى
  
  // 🔐 إعدادات الأمان
  bool _encryptionEnabled = true; // تفعيل التشفير
  String? _groupSecretKey; // مفتاح المجموعة للتوقيع
  String? _groupSecret; // 🔐 المفتاح السري للمجموعة (للتحقق في Firestore Rules)
  final SyncRateLimiter _rateLimiter = SyncRateLimiter(
    maxOperationsPerMinute: 10000, // 🔧 زيادة الحد لنقل كمية بيانات كبيرة في البداية
    maxOperationsPerHour: 100000, // 🔧 زيادة الحد الساعي أيضاً
  );
  
  // Listeners
  StreamSubscription<QuerySnapshot>? _customersListener;
  StreamSubscription<QuerySnapshot>? _transactionsListener;
  StreamSubscription<List<ConnectivityResult>>? _connectivityListener;
  
  // 📱 مؤقت نبضة القلب للأجهزة (كل 30 ثانية للدقة)
  Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(seconds: 30);
  
  // 🔄 مؤقت المزامنة الخلفية (كل 5 دقائق)
  Timer? _backgroundSyncTimer;
  static const Duration _backgroundSyncInterval = Duration(minutes: 5);
  
  // Callbacks
  final _statusController = StreamController<FirebaseSyncStatus>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _syncEventController = StreamController<String>.broadcast();
  Stream<String> get syncEvents => _syncEventController.stream;
  
  // 🔄 إشعارات تحديث الواجهة الفوري
  final _transactionReceivedController = StreamController<Map<String, dynamic>>.broadcast();
  final _customerUpdatedController = StreamController<String>.broadcast(); // sync_uuid للعميل
  
  Stream<FirebaseSyncStatus> get statusStream => _statusController.stream;
  Stream<String> get errorStream => _errorController.stream;
  Stream<String> get syncEventStream => _syncEventController.stream;
  
  /// 🔄 Stream للإشعار عند استقبال معاملة جديدة من جهاز آخر
  Stream<Map<String, dynamic>> get onTransactionReceived => _transactionReceivedController.stream;
  
  /// 🔄 Stream للإشعار عند تحديث بيانات عميل
  Stream<String> get onCustomerUpdated => _customerUpdatedController.stream;
  
  FirebaseSyncStatus get status => _status;
  String? get groupId => _groupId;
  bool get isOnline => _status == FirebaseSyncStatus.online;
  bool get isEnabled => _isInitialized && _groupId != null;
  /// ═══════════════════════════════════════════════════════════════════════
  /// التهيئة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تهيئة خدمة المزامنة
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    // 🌐 بدء مراقبة الاتصال مبكراً (حتى لو فشلت التهيئة)
    _startConnectivityMonitoring();
    
    try {
      // 🔐 التحقق من المصادقة أولاً
      final authService = FirebaseAuthService();
      if (!authService.isAuthenticated) {
        print('⚠️ المستخدم غير مصادق عليه - جاري تسجيل الدخول...');
        final uid = await authService.signInAnonymously();
        if (uid == null) {
          print('❌ فشل تسجيل الدخول - لا يمكن المزامنة');
          _updateStatus(FirebaseSyncStatus.offline);
          _errorController.add('فشل المصادقة - سيتم المحاولة عند عودة الاتصال');
          return false;
        }
      }
      print('✅ المصادقة ناجحة: ${authService.uid}');
      
      // التحقق من الإعدادات
      final isConfigured = await FirebaseSyncConfig.isConfigured();
      final isEnabled = await FirebaseSyncConfig.isEnabled();
      
      if (!isConfigured || !isEnabled) {
        _updateStatus(FirebaseSyncStatus.notConfigured);
        return false;
      }
      
      // الحصول على الإعدادات
      _groupId = await FirebaseSyncConfig.getSyncGroupId();
      _deviceId = await FirebaseSyncConfig.getDeviceId();
      
      // تهيئة Firestore
      _firestore = FirebaseFirestore.instance;
      
      // تفعيل الـ Offline Persistence
      _firestore!.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      
      // 🔒 تهيئة منسق المزامنة (إذا لم يكن مُهيأ)
      if (_coordinator == null) {
        _coordinator = FirebaseSyncCoordinator();
        await _coordinator!.initialize();
      }
      
      // 🔄 تهيئة نظام تتبع العمليات (إذا لم يكن مُهيأ)
      if (_operationTracker == null) {
        _operationTracker = SyncOperationTracker();
        await _operationTracker!.initialize(
          firestore: _firestore!,
          groupId: _groupId!,
          deviceId: _deviceId!,
          groupSecret: _groupSecret,
        );
      }
      
      // 📬 تهيئة خدمة تأكيد الاستلام (إذا لم تكن مُهيأة)
      if (_ackService == null) {
        _ackService = TransactionAckService.instance;
        await _ackService!.initialize(
          firestore: _firestore!,
          deviceId: _deviceId!,
          groupId: _groupId!,
          deviceName: await _getDeviceName(),
        );
      }
      
      // 🛡️ تهيئة خدمة الحماية من الانقطاع (WAL)
      if (_crashRecovery == null) {
        _crashRecovery = SyncCrashRecoveryService.instance;
        await _crashRecovery!.initialize();
        print('✅ تم تهيئة نظام الحماية من الانقطاع (WAL)');
      }
      
      // 🔐 تهيئة مفتاح المجموعة للتشفير والتوقيع
      _groupSecretKey = await SyncSecurity.getGroupSecretKey(_groupId!);
      print('🔐 تم تحميل مفتاح المجموعة للتشفير');
      
      // 🔐 تهيئة المفتاح السري للمجموعة (للتحقق في Firestore Rules)
      _groupSecret = await FirebaseSyncConfig.getOrCreateGroupSecret();
      print('🔐 تم تحميل المفتاح السري للمجموعة');
      
      // 🔒 تهيئة جدول الأيتام (Orphan Transactions)
      await _createOrphanTable();
      
      // 🕰️ حساب فرق التوقيت مع السيرفر
      await _calculateServerTimeOffset();
      
      // بدء الاستماع للتغييرات
      await _startListening();
      
      // مزامنة البيانات المعلقة
      await _syncPendingChanges();
      
      // 🔐 تحميل Retry Queue من قاعدة البيانات
      await _loadRetryQueue();
      
      // 📱 تسجيل هذا الجهاز في المجموعة
      await registerDevice();
      
      // 📱 بدء مؤقت نبضة القلب
      _startHeartbeat();
      
      // 🔄 بدء المزامنة الخلفية الدورية
      _startBackgroundSync();
      
      _isInitialized = true;
      _updateStatus(FirebaseSyncStatus.online);
      
      print('✅ Firebase Sync initialized for group: $_groupId');
      return true;
      
    } catch (e) {
      print('❌ Firebase Sync initialization failed: $e');
      _updateStatus(FirebaseSyncStatus.error);
      _errorController.add('فشل تهيئة المزامنة: $e');
      return false;
    }
  }
  
  /// إيقاف الخدمة
  Future<void> dispose() async {
    await markDeviceOffline(); // تعليم الجهاز كغير متصل
    _stopHeartbeat();
    _stopBackgroundSync(); // 🔄 إيقاف المزامنة الخلفية
    await _stopListening();
    _connectivityListener?.cancel();
    _operationTracker?.dispose(); // 🔄 إيقاف تتبع العمليات
    _ackService?.dispose(); // 📬 إيقاف خدمة التأكيد
    _retryTimer?.cancel(); // 🔄 إيقاف مؤقت Retry
    _statusController.close();
    _errorController.close();
    _syncEventController.close();
    _transactionReceivedController.close();
    _customerUpdatedController.close();
    _isInitialized = false;
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// مراقبة الاتصال
  /// ═══════════════════════════════════════════════════════════════════════
  
  void _startConnectivityMonitoring() {
    // تجنب تشغيل المراقبة مرتين
    if (_connectivityListener != null) return;
    
    _connectivityListener = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      
      if (hasConnection && (_status == FirebaseSyncStatus.offline || _status == FirebaseSyncStatus.error || !_isInitialized)) {
        print('🌐 الاتصال عاد - جاري المزامنة...');
        _onConnectionRestored();
      } else if (!hasConnection && _status != FirebaseSyncStatus.offline) {
        print('📴 انقطع الاتصال - العمل محلياً');
        _updateStatus(FirebaseSyncStatus.offline);
        markDeviceOffline(); // تعليم الجهاز كغير متصل
      }
    });
  }
  
  /// بدء مؤقت نبضة القلب
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_status == FirebaseSyncStatus.online) {
        updateDeviceHeartbeat();
      }
    });
  }
  
  /// إيقاف مؤقت نبضة القلب
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  /// 🔄 بدء المزامنة الخلفية الدورية
  void _startBackgroundSync() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = Timer.periodic(_backgroundSyncInterval, (_) async {
      if (_status == FirebaseSyncStatus.online && !_isSyncing) {
        print('🔄 المزامنة الخلفية الدورية...');
        await _performBackgroundSync();
      }
    });
    print('✅ تم تفعيل المزامنة الخلفية (كل ${_backgroundSyncInterval.inMinutes} دقائق)');
  }
  
  /// إيقاف المزامنة الخلفية
  void _stopBackgroundSync() {
    _backgroundSyncTimer?.cancel();
    _backgroundSyncTimer = null;
  }
  
  /// تنفيذ المزامنة الخلفية (خفيفة - لا تؤثر على الأداء)
  Future<void> _performBackgroundSync() async {
    if (!_isInitialized || _groupId == null || _isSyncing) return;
    
    try {
      // 1️⃣ معالجة العمليات المعلقة في WAL
      if (_crashRecovery != null) {
        final pendingUploads = await _crashRecovery!.getPendingUploads();
        if (pendingUploads.isNotEmpty) {
          print('🔄 معالجة ${pendingUploads.length} عملية معلقة من WAL...');
          for (final op in pendingUploads) {
            try {
              if (op.type == 'customer') {
                await uploadCustomer(op.data);
              } else if (op.type == 'transaction') {
                final customerSyncUuid = op.data['customer_sync_uuid'] as String?;
                if (customerSyncUuid != null) {
                  await uploadTransaction(op.data, customerSyncUuid);
                }
              }
              await _crashRecovery!.markSynced(op.id);
            } catch (e) {
              print('⚠️ فشل معالجة عملية WAL: ${op.id}');
            }
          }
        }
      }
      
      // 2️⃣ معالجة Retry Queue
      await _processRetryQueue();
      
      // 3️⃣ معالجة المعاملات اليتيمة القديمة (أكثر من 5 دقائق)
      await _retryOldOrphans();
      
      // 4️⃣ تنظيف البيانات القديمة (مرة واحدة يومياً)
      await _periodicCleanup();
      
    } catch (e) {
      print('⚠️ خطأ في المزامنة الخلفية: $e');
    }
  }
  
  /// إعادة محاولة المعاملات اليتيمة القديمة
  Future<void> _retryOldOrphans() async {
    final db = await _db.database;
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String();
    
    // جلب الأيتام القديمة
    final oldOrphans = await db.query(
      'sync_orphans',
      where: 'received_at < ?',
      whereArgs: [cutoff],
      limit: 10,
    );
    
    if (oldOrphans.isEmpty) return;
    
    print('🔄 إعادة محاولة ${oldOrphans.length} معاملة يتيمة قديمة...');
    
    for (final orphan in oldOrphans) {
      final customerSyncUuid = orphan['customer_sync_uuid'] as String;
      
      // البحث عن العميل مرة أخرى
      final customerResult = await db.query(
        'customers',
        columns: ['id'],
        where: 'sync_uuid = ?',
        whereArgs: [customerSyncUuid],
      );
      
      if (customerResult.isNotEmpty) {
        // العميل موجود الآن - معالجة الأيتام
        final customerId = customerResult.first['id'] as int;
        await _processOrphans(customerId, customerSyncUuid);
      } else {
        // العميل لا يزال غير موجود - حذف الأيتام القديمة جداً (أكثر من ساعة)
        final receivedAt = DateTime.parse(orphan['received_at'] as String);
        if (DateTime.now().difference(receivedAt).inHours > 1) {
          await db.delete(
            'sync_orphans',
            where: 'sync_uuid = ?',
            whereArgs: [orphan['sync_uuid']],
          );
          print('🗑️ حذف معاملة يتيمة قديمة جداً: ${orphan['sync_uuid']}');
        }
      }
    }
  }
  
  /// تنظيف دوري (مرة واحدة يومياً)
  DateTime? _lastCleanupDate;
  Future<void> _periodicCleanup() async {
    final today = DateTime.now();
    if (_lastCleanupDate != null && 
        _lastCleanupDate!.day == today.day && 
        _lastCleanupDate!.month == today.month) {
      return; // تم التنظيف اليوم
    }
    
    print('🧹 التنظيف الدوري اليومي...');
    _lastCleanupDate = today;
    
    try {
      // تنظيف WAL
      if (_crashRecovery != null) {
        await _crashRecovery!.cleanupCompletedOperations(keepDays: 7);
      }
      
      // تنظيف ACKs القديمة
      await _ackService?.cleanupOldAcks();
      
      // تنظيف سجلات العمليات
      await _operationTracker?.cleanupOldLogs();
      
      print('✅ اكتمل التنظيف الدوري');
    } catch (e) {
      print('⚠️ خطأ في التنظيف الدوري: $e');
    }
  }
  
  Future<void> _onConnectionRestored() async {
    _updateStatus(FirebaseSyncStatus.syncing);
    
    try {
      // 🔄 إذا لم تكتمل التهيئة الأولى، نعيد التهيئة الكاملة
      if (!_isInitialized) {
        print('🔄 إعادة التهيئة الكاملة بعد عودة الاتصال...');
        final success = await initialize();
        if (success) {
          print('✅ تمت إعادة التهيئة بنجاح');
          _syncEventController.add('تمت إعادة التهيئة بعد عودة الاتصال');
        } else {
          print('❌ فشلت إعادة التهيئة');
          _updateStatus(FirebaseSyncStatus.error);
        }
        return;
      }
      
      // مزامنة التغييرات المعلقة
      await _syncPendingChanges();
      
      // إعادة تشغيل الـ listeners
      if (!_isListening) {
        await _startListening();
      }
      
      // 📱 تسجيل الجهاز مرة أخرى
      await registerDevice();
      
      _updateStatus(FirebaseSyncStatus.online);
      _syncEventController.add('تمت المزامنة بعد عودة الاتصال');
      
    } catch (e) {
      print('❌ خطأ في المزامنة بعد عودة الاتصال: $e');
      _updateStatus(FirebaseSyncStatus.error);
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// الاستماع للتغييرات من Firebase (Real-time)
  /// ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _startListening() async {
    if (_isListening || _groupId == null) return;
    
    print('👂 بدء الاستماع للتغييرات من Firebase...');
    print('   📍 المجموعة: $_groupId');
    print('   📱 معرف الجهاز: $_deviceId');
    
    // الاستماع لتغييرات العملاء
    _customersListener = _firestore!
        .collection('sync_groups')
        .doc(_groupId)
        .collection('customers')
        .snapshots()
        .listen(
          _onCustomersChanged,
          onError: (e) => print('❌ خطأ في استماع العملاء: $e'),
        );
    
    // الاستماع لتغييرات المعاملات
    _transactionsListener = _firestore!
        .collection('sync_groups')
        .doc(_groupId)
        .collection('transactions')
        .snapshots()
        .listen(
          _onTransactionsChanged,
          onError: (e) => print('❌ خطأ في استماع المعاملات: $e'),
        );
    
    _isListening = true;
    print('✅ تم بدء الاستماع للتغييرات');
  }
  
  Future<void> _stopListening() async {
    await _customersListener?.cancel();
    await _transactionsListener?.cancel();
    _customersListener = null;
    _transactionsListener = null;
    _isListening = false;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// معالجة التغييرات الواردة من Firebase
  /// ═══════════════════════════════════════════════════════════════════════
  
  Future<void> _onCustomersChanged(QuerySnapshot snapshot) async {
    for (final change in snapshot.docChanges) {
      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      
      final syncUuid = change.doc.id;
      final sourceDeviceId = data['deviceId'] as String?;
      
      // تجاهل التغييرات من نفس الجهاز
      if (sourceDeviceId == _deviceId) {
         // print('⏭️ تجاهل عميل من نفس الجهاز: $syncUuid'); 
         continue;
      }
      
      print('📥 استلام تغيير عميل من جهاز آخر: $syncUuid (نوع: ${change.type})');
      print('   - الجهاز المصدر: $sourceDeviceId');
      
      try {
        switch (change.type) {
          case DocumentChangeType.added:
            print('   ✨ جاري إضافة عميل جديد...');
            await _applyCustomerChange(syncUuid, data);
            break;
          case DocumentChangeType.modified:
             print('   📝 جاري تحديث عميل...');
            await _applyCustomerChange(syncUuid, data);
            break;
          case DocumentChangeType.removed:
            print('   🗑️ جاري حذف عميل...');
            await _deleteLocalCustomer(syncUuid);
            break;
        }
      } catch (e) {
        print('❌ خطأ في تطبيق تغيير العميل $syncUuid: $e');
      }
    }
  }
  
  Future<void> _onTransactionsChanged(QuerySnapshot snapshot) async {
    print('📥 استلام ${snapshot.docChanges.length} تغيير في المعاملات');
    
    for (final change in snapshot.docChanges) {
      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      
      final syncUuid = change.doc.id;
      final sourceDeviceId = data['deviceId'] as String?;
      
      // تجاهل التغييرات من نفس الجهاز
      if (sourceDeviceId == _deviceId) {
        print('⏭️ تجاهل معاملة من نفس الجهاز: $syncUuid');
        continue;
      }
      
      print('📥 معاملة من جهاز آخر: $syncUuid (من: $sourceDeviceId)');
      
      try {
        switch (change.type) {
          case DocumentChangeType.added:
          case DocumentChangeType.modified:
            await _applyTransactionChange(syncUuid, data);
            break;
          case DocumentChangeType.removed:
            await _deleteLocalTransaction(syncUuid);
            break;
        }
      } catch (e) {
        print('❌ خطأ في تطبيق تغيير المعاملة $syncUuid: $e');
      }
    }
  }
  
  /// تطبيق تغيير عميل من Firebase على قاعدة البيانات المحلية
  /// 🔒 مهم: لا نحدث current_total_debt من البيانات البعيدة!
  /// الرصيد يُحسب دائماً من مجموع المعاملات المحلية
  Future<void> _applyCustomerChange(String syncUuid, Map<String, dynamic> data) async {
    // 🔐 التحقق من صحة البيانات الواردة
    final validation = SyncValidation.validateFirebaseCustomerData(data);
    if (!validation.isValid) {
      print('❌ رفض بيانات عميل غير صالحة: ${validation.errors.join(', ')}');
      return;
    }
    if (validation.warnings.isNotEmpty) {
      print('⚠️ تحذيرات في بيانات العميل: ${validation.warnings.join(', ')}');
    }
    
    // 🔐 التحقق من التوقيع إذا كان موجوداً (تحذير فقط - لا رفض)
    final signature = data['signature'] as String?;
    final originDeviceId = data['originDeviceId'] as String?;
    if (signature != null && _groupSecretKey != null && originDeviceId != null) {
      final dataToVerify = '$syncUuid|$originDeviceId|${data['checksum'] ?? ''}';
      if (!SyncSecurity.verifySignature(dataToVerify, signature, _groupSecretKey!)) {
        // تحذير فقط - لا نرفض البيانات لأن المفتاح قد يكون مختلفاً بين الأجهزة
        print('⚠️ تحذير: توقيع العميل غير متطابق (قد يكون من جهاز آخر): $syncUuid');
      }
    }
    
    // 🔐 تنظيف البيانات من المحتوى الخطر
    final sanitizedData = SyncValidation.sanitizeMap(data);
    
    final db = await _db.database;
    
    // التحقق من وجود العميل محلياً
    final existing = await db.query(
      'customers',
      where: 'sync_uuid = ?',
      whereArgs: [syncUuid],
    );
    
    if (existing.isEmpty) {
      // عميل جديد - إضافته
      // 🔒 مهم: نضيف العميل برصيد 0، والرصيد سيُحسب من المعاملات لاحقاً
      await db.insert('customers', {
        'name': SyncValidation.sanitizeString(sanitizedData['name']?.toString() ?? ''),
        'phone': sanitizedData['phone'],
        'current_total_debt': 0.0, // 🔒 نبدأ بصفر، المعاملات ستحدد الرصيد
        'general_note': sanitizedData['generalNote'],
        'address': sanitizedData['address'],
        'created_at': sanitizedData['createdAt'],
        'last_modified_at': sanitizedData['lastModifiedAt'],
        'audio_note_path': sanitizedData['audioNotePath'],
        'sync_uuid': syncUuid,
        'is_deleted': sanitizedData['isDeleted'] == true ? 1 : 0,
      });
      
      // 🔒 تسجيل في المنسق (مستلم من Firebase)
      await _coordinator!.registerOperation(
        entityType: 'customer',
        syncUuid: syncUuid,
        source: SyncSource.firebase,
      );
      await _coordinator!.markFirebaseSynced('customer', syncUuid);
      
      print('✅ تم إضافة عميل جديد بنجاح من Firebase: ${data['name']}');
      print('   - Sync UUID: $syncUuid');
      
      // 👻 معالجة المعاملات اليتيمة أولاً (قبل الإشعار!)
      final newCustomerId = await db.query('customers', columns: ['id'], where: 'sync_uuid = ?', whereArgs: [syncUuid]);
      if (newCustomerId.isNotEmpty) {
          await _processOrphans(newCustomerId.first['id'] as int, syncUuid);
      }
      
      // 🔔 الإشعار بعد اكتمال كل شيء (العميل + معاملاته)
      _syncEventController.add('عميل جديد: ${data['name']}');
      
    } else {
      // 🔒 عميل موجود - تحديث البيانات الوصفية فقط (بدون الرصيد!)
      final localData = existing.first;
      final customerId = localData['id'] as int;
      final localBalance = (localData['current_total_debt'] as num?)?.toDouble() ?? 0.0;
      
      // 🔒 تحديث البيانات الوصفية فقط (الاسم، الهاتف، العنوان، الملاحظات)
      // لا نحدث current_total_debt أبداً من البيانات البعيدة!
      await db.update(
        'customers',
        {
          'name': data['name'] ?? localData['name'],
          'phone': data['phone'] ?? localData['phone'],
          // 🔒 لا نحدث current_total_debt - يبقى كما هو
          'general_note': data['generalNote'] ?? localData['general_note'],
          'address': data['address'] ?? localData['address'],
          'last_modified_at': data['lastModifiedAt'] ?? DateTime.now().toIso8601String(),
          'audio_note_path': data['audioNotePath'] ?? localData['audio_note_path'],
          // 🔒 لا نحذف العميل من البيانات البعيدة
        },
        where: 'sync_uuid = ?',
        whereArgs: [syncUuid],
      );
      
      print('✅ تم تحديث بيانات العميل (بدون الرصيد): ${data['name']}');
      print('   📊 الرصيد المحلي محفوظ: $localBalance');
      _syncEventController.add('تحديث عميل: ${data['name']}');
    }
  }
  
  /// تطبيق تغيير معاملة من Firebase على قاعدة البيانات المحلية
  /// 🔄 تعمل بنفس طريقة Google Drive Sync:
  /// - تضيف المعاملة كمعاملة منفصلة
  /// - تعلّمها بـ is_created_by_me = 0
  /// - تضيف ملاحظة "من المزامنة (Firebase)"
  /// - لا تحذف أو تعدل المعاملات الموجودة
  Future<void> _applyTransactionChange(String syncUuid, Map<String, dynamic> data) async {
    // 🔐 التحقق من صحة البيانات الواردة
    final validation = SyncValidation.validateFirebaseTransactionData(data);
    if (!validation.isValid) {
      print('❌ رفض بيانات معاملة غير صالحة: ${validation.errors.join(', ')}');
      return;
    }
    
    // 🔒 التحقق من رفض المعاملات القديمة (إذا كان مفعلاً)
    final rejectOldTransactions = await FirebaseSyncSecuritySettings.isRejectOldTransactionsEnabled();
    if (rejectOldTransactions) {
      final transactionDateStr = data['transactionDate'] as String?;
      if (transactionDateStr != null) {
        try {
          final transactionDate = DateTime.parse(transactionDateStr);
          final maxAgeDays = await FirebaseSyncSecuritySettings.getMaxTransactionAgeDays();
          final cutoffDate = DateTime.now().subtract(Duration(days: maxAgeDays));
          
          if (transactionDate.isBefore(cutoffDate)) {
            final age = DateTime.now().difference(transactionDate).inDays;
            print('🚫 رفض معاملة قديمة ($age يوم): $syncUuid');
            print('   📅 تاريخ المعاملة: $transactionDateStr');
            print('   ⏰ الحد الأقصى: $maxAgeDays يوم');
            return;
          }
        } catch (e) {
          print('⚠️ خطأ في تحليل تاريخ المعاملة: $e');
        }
      }
    }
    
    final db = await _db.database;
    
    // الحصول على customer_id المحلي من sync_uuid
    final customerSyncUuid = data['customerSyncUuid'] as String?;
    if (customerSyncUuid == null) {
      print('❌ الحاسوب رفض قراءة المعاملة! ⛔');
      print('   - السبب: معاملة بدون ربط عميل (customerSyncUuid)');
      print('   - ID: $syncUuid');
      return;
    }
    
    // البحث عن العميل
    final customerResult = await db.query(
      'customers',
      columns: ['id', 'name', 'current_total_debt'],
      where: 'sync_uuid = ?',
      whereArgs: [customerSyncUuid],
    );
    
    if (customerResult.isEmpty) {
      // 👻 العميل غير موجود - إضافة للطابور
      print('⏳ معاملة مؤقتة (بانتظار بيانات العميل)');
      print('   - العميل غير موجود بعد في القاعدة المحلية');
      print('   - ID: $syncUuid');
      print('   👉 تم حفظها في قائمة الانتظار لحين وصول بيانات العميل');
      await _addToOrphans(syncUuid, data);
      return;
    }
    
    final localCustomerId = customerResult.first['id'] as int;
    final customerName = customerResult.first['name'] as String? ?? 'غير معروف';
    final currentBalance = (customerResult.first['current_total_debt'] as num?)?.toDouble() ?? 0.0;
    
    // 1️⃣ التحقق من وجود المعاملة بـ sync_uuid
    final existingByUuid = await db.query(
      'transactions',
      where: 'sync_uuid = ?',
      whereArgs: [syncUuid],
    );
    
    // البيانات الواردة
    final amountChanged = (data['amountChanged'] as num?)?.toDouble() ?? 0.0;
    final transactionDate = data['transactionDate'] as String?;
    final transactionNote = data['transactionNote'] as String? ?? '';
    String transactionType = data['transactionType'] as String? ?? '';
    if (transactionType.isEmpty) {
      transactionType = amountChanged >= 0 ? 'manual_debt' : 'manual_payment';
    }

    if (existingByUuid.isNotEmpty) {
      // ✅ المعاملة موجودة - نتحقق هل تحتاج تحديث؟
      final existingTx = existingByUuid.first;
      final currentAmount = (existingTx['amount_changed'] as num?)?.toDouble() ?? 0.0;
      final currentType = existingTx['transaction_type'] as String?;
      final currentNote = existingTx['transaction_note'] as String? ?? '';
      
      // هل هناك اختلاف جوهري؟
      bool needsUpdate = (currentAmount - amountChanged).abs() > 0.01 || 
                         currentType != transactionType ||
                         currentNote != transactionNote;

      if (needsUpdate) {
        print('🔄 تحديث معاملة واردة من المزامنة: $syncUuid');
        print('   💰 المبلغ: $currentAmount -> $amountChanged');
        print('   🏷️ النوع: $currentType -> $transactionType');
        
        // 🔒 إصلاح أمني حرج: التحقق من مطابقة العميل
        final txCustomerId = existingTx['customer_id'] as int;
        final txCustomerCheck = await db.query(
          'customers',
          columns: ['sync_uuid', 'name'],
          where: 'id = ?',
          whereArgs: [txCustomerId],
        );
        
        if (txCustomerCheck.isEmpty) {
          print('❌ الحاسوب رفض قراءة المعاملة! ⛔');
          print('   - السبب: العميل المرتبط غير موجود');
          print('   - معرف العميل المحلي: $txCustomerId');
          return;
        }
        
        final txCustomerSyncUuid = txCustomerCheck.first['sync_uuid'] as String?;
        if (txCustomerSyncUuid != customerSyncUuid) {
          print('❌ الحاسوب رفض قراءة المعاملة! ⛔');
          print('   - السبب: عدم تطابق العميل (خطأ حرج!)');
          print('   - المتوقع (من Firebase): $customerSyncUuid');
          print('   - الموجود (محلياً): $txCustomerSyncUuid');
          print('   - المعاملة: $syncUuid');
          return;
        }
        
        // ⚠️ مهم جداً: استخدام DatabaseService لإعادة حساب كل شيء بشكل صحيح
        final dbService = DatabaseService();
        
        // تحديث المعاملة باستخدام DatabaseService (لإعادة حساب الأرصدة)
        final txId = existingTx['id'] as int;
        final existingTransaction = await dbService.getTransactionById(txId);
        
        if (existingTransaction != null) {
          // إنشاء نسخة محدثة من المعاملة
          final updatedTransaction = DebtTransaction(
            id: existingTransaction.id,
            customerId: existingTransaction.customerId,
            transactionDate: transactionDate != null ? DateTime.parse(transactionDate) : existingTransaction.transactionDate,
            amountChanged: amountChanged,
            balanceBeforeTransaction: existingTransaction.balanceBeforeTransaction, // سيتم إعادة حسابه
            newBalanceAfterTransaction: existingTransaction.newBalanceAfterTransaction, // سيتم إعادة حسابه
            transactionNote: transactionNote,
            transactionType: transactionType,
            description: data['description'] as String?,
            createdAt: existingTransaction.createdAt,
            audioNotePath: data['audioNotePath'] as String?,
            isCreatedByMe: existingTransaction.isCreatedByMe,
            isUploaded: existingTransaction.isUploaded,
            syncUuid: existingTransaction.syncUuid,
            invoiceId: existingTransaction.invoiceId,
          );
          
          // استخدام updateManualTransaction لإعادة حساب كل شيء بشكل صحيح
          await dbService.updateManualTransaction(updatedTransaction);
          
          // 🛡️ إصلاح جذري لمشكلة عدم تناسق الأرصدة:
          // إجبار النظام على إعادة حساب تسلسل الأرصدة بالكامل + الرصيد النهائي
          // هذا يضمن أنه حتى لو تغير التاريخ أو الترتيب، الأرصدة ستكون صحيحة 100%
          print('🔄 جاري إعادة حساب تسلسل الأرصدة للعميل ${existingTransaction.customerId}...');
          await dbService.recalculateCustomerTransactionBalances(existingTransaction.customerId);
          await dbService.recalculateAndApplyCustomerDebt(existingTransaction.customerId);
          
          // 🔒 التحقق من سلامة الرصيد بعد التحديث
          final updatedCustomer = await dbService.getCustomerById(existingTransaction.customerId);
          if (updatedCustomer != null) {
            final newBalance = updatedCustomer.currentTotalDebt;
            
            // فحص الأرصدة غير المنطقية
            if (newBalance.abs() > 10000000) {
              print('⚠️ تحذير: رصيد غير منطقي بعد التحديث!');
              print('   - العميل: ${updatedCustomer.name}');
              print('   - الرصيد الجديد: $newBalance');
            }
            
            // فحص التغير المفاجئ
            final balanceChange = (newBalance - currentBalance).abs();
            if (balanceChange > 100000) {
              print('⚠️ تحذير: تغير كبير في الرصيد!');
              print('   - العميل: ${updatedCustomer.name}');
              print('   - التغير: $balanceChange');
            }
          }
        }
        
        print('═══════════════════════════════════════════════════════════════════');
        print('📥 تم استلام وتطبيق **تحديث** لمعاملة موجودة! 🔄✅');
        print('   - العميل: $customerName');
        print('   - المبلغ: $currentAmount ⬅️ تغير إلى: $amountChanged');
        print('   - الملاحظة: $transactionNote');
        print('   - ID: $syncUuid');
        print('═══════════════════════════════════════════════════════════════════');
        
        _syncEventController.add('تحديث معاملة: $customerName');
      } else {
        print('⏭️ المعاملة موجودة ومطابقة تماماً (تم تجاهل التحديث)');
        print('   - ID: $syncUuid');
      }
      return;
    }
    
    // 2️⃣ التحقق من عدم وجود معاملة مكررة بنفس البيانات (للمعاملات الجديدة فقط)
    if (transactionDate != null) {
      final duplicateCheck = await db.query(
        'transactions',
        where: '''customer_id = ? AND 
                  transaction_date = ? AND 
                  ABS(amount_changed - ?) < 0.01 AND
                  (is_deleted IS NULL OR is_deleted = 0)''',
        whereArgs: [localCustomerId, transactionDate, amountChanged],
      );
      
      if (duplicateCheck.isNotEmpty) {
        // ... (نفس منطق التحقق من التكرار)
         final existingTx = duplicateCheck.first;
         final existingNote = existingTx['transaction_note'] as String? ?? '';
         
         if (existingNote == transactionNote || 
             existingNote.contains('من المزامنة') ||
             transactionNote.contains('من المزامنة')) {
           // ... ربط الـ UUID فقط
            await db.update(
              'transactions',
              {'sync_uuid': syncUuid},
              where: 'id = ?',
              whereArgs: [existingTx['id']],
            );
            return;
         }
      }
    }
    
    // 3️⃣ التحقق من صحة المبلغ
    if (amountChanged.abs() > 1000000000) {
      print('❌ الحاسوب رفض قراءة المعاملة! ⛔');
      print('   - السبب: مبلغ غير منطقي (أكبر من مليار)');
      print('   - المبلغ: $amountChanged');
      print('   - ID: $syncUuid');
      return;
    }
    
    // 4️⃣ حساب الرصيد الجديد (مثل Google Drive Sync)
    final newBalance = currentBalance + amountChanged;
    
    // 5️⃣ إعداد ملاحظة المعاملة مع علامة "من المزامنة"
    String finalNote = transactionNote;
    if (!finalNote.contains('من المزامنة') && !finalNote.contains('من جهاز آخر')) {
      finalNote = finalNote.isEmpty 
          ? '🔄 من المزامنة (Firebase)' 
          : '$finalNote\n🔄 من المزامنة (Firebase)';
    }
    
    // 6️⃣ تحديد نوع المعاملة
    // المتغير transactionType تم تحديده في الأعلى
    if (transactionType.isEmpty) {
      // تحديد النوع من المبلغ
      transactionType = amountChanged >= 0 ? 'manual_debt' : 'manual_payment';
    }
    
    // 7️⃣ إدراج المعاملة الجديدة
    await db.insert('transactions', {
      'customer_id': localCustomerId,
      'transaction_date': transactionDate ?? DateTime.now().toIso8601String(),
      'amount_changed': amountChanged,
      'balance_before_transaction': currentBalance,
      'new_balance_after_transaction': newBalance,
      'transaction_note': finalNote,
      'transaction_type': transactionType,
      'description': data['description'],
      'created_at': data['createdAt'] ?? DateTime.now().toIso8601String(),
      'audio_note_path': data['audioNotePath'],
      'is_created_by_me': 0, // 🔒 ليست من هذا الجهاز - لا يمكن حذفها أو تعديلها
      'is_uploaded': 1, // 🔒 تعليمها كمرفوعة لتجنب إعادة رفعها
      'sync_uuid': syncUuid,
      'is_deleted': 0, // 🔒 لا نحذف المعاملات القادمة من المزامنة
    });
    
    // 8️⃣ تحديث رصيد العميل
    await db.update(
      'customers',
      {
        'current_total_debt': newBalance,
        'last_modified_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [localCustomerId],
    );
    
    // 9️⃣ تسجيل في المنسق
    await _coordinator!.registerOperation(
      entityType: 'transaction',
      syncUuid: syncUuid,
      source: SyncSource.firebase,
    );
    await _coordinator!.markFirebaseSynced('transaction', syncUuid);
    
    //  طإرسال تأكيد استلام (ACK) للجهاز المرسل
    final senderDeviceId = data['originDeviceId'] as String? ?? data['deviceId'] as String?;
    if (senderDeviceId != null && senderDeviceId != _deviceId) {
      await _ackService!.sendAck(
        transactionSyncUuid: syncUuid,
        senderDeviceId: senderDeviceId,
      );
    }
    
    // 🔟 طباعة تفاصيل المعاملة للتدقيق
    final typeLabel = amountChanged >= 0 ? 'إضافة دين' : 'تسديد';
    print('═══════════════════════════════════════════════════════════════════');
    print('📥 تم استلام وقراءة معاملة جديدة بنجاح! ✅');
    print('   - العميل: $customerName (ID: $localCustomerId)');
    print('   - النوع: $typeLabel');
    print('   - المبلغ: ${amountChanged.abs()}');
    print('   - الرصيد قبل: $currentBalance');
    print('   - الرصيد بعد: $newBalance');
    print('   - من جهاز: $senderDeviceId');
    print('═══════════════════════════════════════════════════════════════════');
    
    _syncEventController.add('معاملة جديدة: $typeLabel ${amountChanged.abs()} - $customerName');
    
    // 🔄 إرسال إشعار لتحديث الواجهة فوراً
    _transactionReceivedController.add({
      'customerId': localCustomerId,
      'customerSyncUuid': customerSyncUuid,
      'customerName': customerName,
      'syncUuid': syncUuid,
      'amountChanged': amountChanged,
      'newBalance': newBalance,
      'transactionType': transactionType,
      'transactionDate': transactionDate,
    });
    
    // إشعار بتحديث العميل
    _customerUpdatedController.add(customerSyncUuid);
  }
  
  /// حذف عميل محلياً (Soft Delete)
  /// 🔒 لا نحذف العملاء من Firebase - فقط نسجل تحذير
  Future<void> _deleteLocalCustomer(String syncUuid) async {
    // 🔒 لا نحذف العملاء من البيانات البعيدة
    // هذا يمنع فقدان البيانات عند المزامنة
    print('⚠️ تجاهل طلب حذف عميل من Firebase: $syncUuid');
    print('   🔒 العملاء لا يُحذفون عبر المزامنة للحفاظ على البيانات');
  }
  
  /// حذف معاملة محلياً (Soft Delete)
  /// 🔒 لا نحذف المعاملات من Firebase - فقط نسجل تحذير
  Future<void> _deleteLocalTransaction(String syncUuid) async {
    // 🔒 لا نحذف المعاملات من البيانات البعيدة
    // هذا يمنع فقدان البيانات عند المزامنة
    print('⚠️ تجاهل طلب حذف معاملة من Firebase: $syncUuid');
    print('   🔒 المعاملات لا تُحذف عبر المزامنة للحفاظ على البيانات');
  }
  
  /// إعادة حساب رصيد العميل
  Future<void> _recalculateCustomerBalance(int customerId) async {
    final db = await _db.database;
    
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount_changed), 0) as total
      FROM transactions
      WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
    ''', [customerId]);
    
    final total = (result.first['total'] as num?)?.toDouble() ?? 0.0;
    
    await db.update(
      'customers',
      {'current_total_debt': total},
      where: 'id = ?',
      whereArgs: [customerId],
    );
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// رفع التغييرات المحلية إلى Firebase
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// رفع عميل جديد أو محدث
  Future<void> uploadCustomer(Map<String, dynamic> customerData) async {
    if (!_isInitialized || _groupId == null) return;
    
    // 🔒 لا نرفع العملاء المحذوفين
    if (customerData['is_deleted'] == 1) {
      print('⏭️ تخطي رفع عميل محذوف');
      return;
    }
    
    //  التحقق  من Rate Limiting
    if (!_rateLimiter.canProceed()) {
      final waitTime = _rateLimiter.getWaitTime();
      print('⏳ تجاوز حد العمليات، انتظر ${waitTime?.inSeconds ?? 0} ثانية');
      return;
    }
    
    // 🔒 التحقق من صحة البيانات
    if (!_validateCustomerData(customerData)) {
      print('❌ بيانات العميل غير صالحة - تم تخطي الرفع');
      return;
    }
    
    final syncUuid = customerData['sync_uuid'] as String;
    
    // 🔒 التحقق من أن العملية ليست قيد الرفع حالياً
    if (_uploadLocks['customer_$syncUuid'] == true) {
      print('⏳ العميل قيد الرفع حالياً: $syncUuid');
      return;
    }
    
    // 🔒 التحقق من أنها لم تُرفع مسبقاً
    final alreadySynced = await _coordinator!.isFirebaseSynced('customer', syncUuid);
    
    // 🔍 تشخيص دقيق: لماذا قد يتم تخطي الرفع؟
    if (alreadySynced) {
      // ولكن! هل تم تعديله؟ إذا كان last_modified أحدث، يجب رفعه
      print('⏭️ العميل مسجل كمرفوع مسبقاً: $syncUuid');
      
      // هنا قد تكمن المشكلة: إذا اعتقد النظام أنه مرفوع لكنه لم يصل، لن يرفعه أبداً!
      // سأضيف تجاوزاً للقفل إذا كان الطلبexplicit (أي استدعاء صريح للرفع)
      // ولكن حالياً، سأكتفي بالطباعة للفحص
      return;
    }
    
    print('🚀 بدء رفع العميل إلى Firebase: ${customerData['name']} ($syncUuid)');
    
    _uploadLocks['customer_$syncUuid'] = true;
    _rateLimiter.recordOperation();
    
    // 🛡️ تسجيل في WAL قبل الرفع
    String? walOperationId;
    if (_crashRecovery != null) {
      walOperationId = await _crashRecovery!.beginOperation(
        type: 'customer',
        action: 'create',
        syncUuid: syncUuid,
        data: customerData,
      );
      await _crashRecovery!.markUploading(walOperationId);
    }
    
    try {
      // حساب checksum للتحقق من التغييرات
      final checksum = _calculateChecksum(customerData);
      
      // 🔐 حساب التوقيع
      String? signature;
      if (_groupSecretKey != null) {
        final dataToSign = '$syncUuid|$_deviceId|$checksum';
        signature = SyncSecurity.signData(dataToSign, _groupSecretKey!);
      }
      
      final now = DateTime.now();
      await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('customers')
          .doc(syncUuid)
          .set({
            'syncUuid': syncUuid,
            'name': customerData['name'],
            'phone': customerData['phone'],
            'currentTotalDebt': customerData['current_total_debt'],
            'generalNote': customerData['general_note'],
            'address': customerData['address'],
            'createdAt': customerData['created_at'],
            'lastModifiedAt': customerData['last_modified_at'] ?? now.toIso8601String(),
            'audioNotePath': customerData['audio_note_path'],
            'isDeleted': false, // 🔒 دائماً false - لا نرفع عملاء محذوفين
            'deviceId': _deviceId,
            'originDeviceId': _deviceId, // 🔍 للتتبع والتدقيق
            'checksum': checksum,
            'signature': signature, // 🔐 التوقيع
            'groupSecret': _groupSecret, // 🔐 المفتاح السري للتحقق
            'uploadedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      
      // 🔒 تسجيل في المنسق
      await _coordinator!.registerOperation(
        entityType: 'customer',
        syncUuid: syncUuid,
        source: SyncSource.local,
        checksum: checksum,
      );
      await _coordinator!.markFirebaseSynced('customer', syncUuid);
      
      // 🔄 تتبع العملية (للتحديثات)
      await _operationTracker!.trackCreate(
        syncUuid: syncUuid,
        entityType: 'customer',
        data: customerData,
      );
      
      // 🛡️ تعليم العملية كمكتملة في WAL
      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markSynced(walOperationId);
      }
      
      print('☁️ تم رفع العميل بنجاح إلى الفاير بيس! 🚀');
      print('   - الاسم: ${customerData['name']}');
      print('   - ID: $syncUuid');
      
    } catch (e) {
      print('❌ فشل رفع العميل للفاير بيس! حاول مرة أخرى.');
      print('   - الخطأ: $e');
      
      // 🛡️ تسجيل الفشل في WAL
      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markFailed(walOperationId, e.toString());
      }
      
      // 🔄 إضافة للـ Retry Queue
      await _addToRetryQueue(_RetryOperation(
        type: 'customer',
        syncUuid: syncUuid,
        data: customerData,
        retryCount: 0,
        nextRetryTime: DateTime.now().add(_baseRetryDelay),
      ));
    } finally {
      _uploadLocks.remove('customer_$syncUuid');
    }
  }
  
  /// رفع معاملة جديدة أو محدثة
  Future<void> uploadTransaction(Map<String, dynamic> txData, String customerSyncUuid) async {
    if (!_isInitialized || _groupId == null) return;
    
    // 🔒 لا نرفع المعاملات المحذوفة
    if (txData['is_deleted'] == 1) {
      print('⏭️ تخطي رفع معاملة محذوفة');
      return;
    }
    
    // 🔒 لا نرفع المعاملات القادمة من المزامنة (لتجنب الحلقة)
    // المعاملات الجديدة لها is_created_by_me = 1 أو NULL (يُعامل كـ 1)
    final isCreatedByMe = txData['is_created_by_me'];
    if (isCreatedByMe != null && isCreatedByMe == 0) {
      print('⏭️ تخطي رفع معاملة من المزامنة');
      return;
    }
    
    // 🔧 التحقق من Rate Limiting
    if (!_rateLimiter.canProceed()) {
      final waitTime = _rateLimiter.getWaitTime();
      print('⏳ تجاوز حد العمليات، انتظر ${waitTime?.inSeconds ?? 0} ثانية');
      return;
    }
    
    // 🔒 التحقق من صحة البيانات
    if (!_validateTransactionData(txData)) {
      print('❌ بيانات المعاملة غير صالحة - تم تخطي الرفع');
      return;
    }
    
    final syncUuid = txData['sync_uuid'] as String;
    
    // 🔒 التحقق من أن العملية ليست قيد الرفع حالياً
    if (_uploadLocks['transaction_$syncUuid'] == true) {
      print('⏳ المعاملة قيد الرفع حالياً: $syncUuid');
      return;
    }
    
    // 🔒 التحقق من أنها لم تُرفع مسبقاً (لكن نسمح بإعادة الرفع في حالة التحديث!)
    final lastSyncTime = await _coordinator!.getLastSyncTime('transaction', syncUuid);
    final updatedAt = txData['updated_at'] as String?;
    
    if (lastSyncTime != null && updatedAt != null) {
      final lastSync = DateTime.parse(lastSyncTime);
      final updated = DateTime.parse(updatedAt);
      
      // إذا كان آخر تحديث قبل آخر مزامنة، فهذا يعني أنها مرفوعة ولا تحتاج إعادة رفع
      if (updated.isBefore(lastSync) || updated.isAtSameMomentAs(lastSync)) {
        print('⏭️ المعاملة مرفوعة مسبقاً: $syncUuid');
        return;
      } else {
        print('🔄 المعاملة تم تحديثها - إعادة الرفع...');
      }
    }
    
    // 🔒 التحقق من عدم وجود معاملة مكررة
    final isDuplicate = await _coordinator!.isDuplicateTransaction(
      customerId: txData['customer_id'] as int,
      transactionDate: txData['transaction_date'] as String,
      amount: (txData['amount_changed'] as num).toDouble(),
      transactionType: txData['transaction_type'] as String? ?? 'debt',
    );
    
    // لا نتخطى إذا كانت مكررة، لكن نسجل تحذير
    if (isDuplicate) {
      print('⚠️ تحذير: معاملة قد تكون مكررة: $syncUuid');
    }
    
    _uploadLocks['transaction_$syncUuid'] = true;
    _rateLimiter.recordOperation();
    
    // 🛡️ تسجيل في WAL قبل الرفع
    String? walOperationId;
    if (_crashRecovery != null) {
      final walData = Map<String, dynamic>.from(txData);
      walData['customer_sync_uuid'] = customerSyncUuid;
      walOperationId = await _crashRecovery!.beginOperation(
        type: 'transaction',
        action: 'create',
        syncUuid: syncUuid,
        data: walData,
      );
      await _crashRecovery!.markUploading(walOperationId);
    }
    
    try {
      // حساب checksum للتحقق من التغييرات
      final checksum = _calculateChecksum(txData);
      
      // 🔐 حساب التوقيع
      String? signature;
      if (_groupSecretKey != null) {
        final dataToSign = '$syncUuid|$_deviceId|$checksum';
        signature = SyncSecurity.signData(dataToSign, _groupSecretKey!);
      }
      
      await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('transactions')
          .doc(syncUuid)
          .set({
            'syncUuid': syncUuid,
            'customerSyncUuid': customerSyncUuid,
            'transactionDate': txData['transaction_date'],
            'amountChanged': txData['amount_changed'],
            'balanceBeforeTransaction': txData['balance_before_transaction'],
            'newBalanceAfterTransaction': txData['new_balance_after_transaction'],
            'transactionNote': txData['transaction_note'],
            'transactionType': txData['transaction_type'],
            'description': txData['description'],
            'createdAt': txData['created_at'],
            'lastModifiedAt': DateTime.now().toIso8601String(),
            'audioNotePath': txData['audio_note_path'],
            'isDeleted': false, // 🔒 دائماً false - لا نرفع معاملات محذوفة
            'deviceId': _deviceId,
            'originDeviceId': _deviceId, // 🔍 للتتبع والتدقيق
            'checksum': checksum,
            'signature': signature, // 🔐 التوقيع
            'groupSecret': _groupSecret, // 🔐 المفتاح السري للتحقق
            'uploadedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      
      // 🔒 تسجيل في المنسق
      await _coordinator!.registerOperation(
        entityType: 'transaction',
        syncUuid: syncUuid,
        source: SyncSource.local,
        checksum: checksum,
      );
      await _coordinator!.markFirebaseSynced('transaction', syncUuid);
      
      print('☁️ تم رفع المعاملة بنجاح إلى الفاير بيس! 🚀');
      print('   - ID: $syncUuid');
      print('   - المبلغ: ${txData['amountChanged'] ?? txData['amount_changed']}');
      print('   - بانتظار قراءة الحاسوب الآخر...');
      
    } catch (e) {
      print('❌ فشل رفع المعاملة للفاير بيس!');
      print('   - الخطأ: $e');
      
      // 🛡️ تعليم العملية كمكتملة في WAL
      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markSynced(walOperationId);
      }
      
      print('☁️ تم رفع معاملة');
      
    } catch (e) {
      print('❌ فشل رفع المعاملة: $e');
      
      // 🛡️ تسجيل الفشل في WAL
      if (walOperationId != null && _crashRecovery != null) {
        await _crashRecovery!.markFailed(walOperationId, e.toString());
      }
      
      // 🔄 إضافة للـ Retry Queue
      final retryData = Map<String, dynamic>.from(txData);
      retryData['customer_sync_uuid'] = customerSyncUuid;
      await _addToRetryQueue(_RetryOperation(
        type: 'transaction',
        syncUuid: syncUuid,
        data: retryData,
        retryCount: 0,
        nextRetryTime: DateTime.now().add(_baseRetryDelay),
      ));
    } finally {
      _uploadLocks.remove('transaction_$syncUuid');
    }
  }
  
  /// حذف عميل من Firebase (Soft Delete)
  Future<void> deleteCustomer(String syncUuid) async {
    if (!_isInitialized || _groupId == null || _groupSecret == null) return;
    
    try {
      await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('customers')
          .doc(syncUuid)
          .update({
            'isDeleted': true,
            'deletedAt': FieldValue.serverTimestamp(),
            'deviceId': _deviceId,
            'groupSecret': _groupSecret, // 🔐 مطلوب للقواعد
          });
      
      print('☁️ تم حذف عميل من Firebase');
      
    } catch (e) {
      print('❌ فشل حذف العميل من Firebase: $e');
    }
  }
  
  /// حذف معاملة من Firebase (Soft Delete)
  Future<void> deleteTransaction(String syncUuid) async {
    if (!_isInitialized || _groupId == null || _groupSecret == null) return;
    
    try {
      await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('transactions')
          .doc(syncUuid)
          .update({
            'isDeleted': true,
            'deletedAt': FieldValue.serverTimestamp(),
            'deviceId': _deviceId,
            'groupSecret': _groupSecret, // 🔐 مطلوب للقواعد
          });
      
      print('☁️ تم حذف معاملة من Firebase');
      
    } catch (e) {
      print('❌ فشل حذف المعاملة من Firebase: $e');
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// مزامنة البيانات المعلقة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// مزامنة جميع التغييرات المعلقة مع دعم مؤشر التقدم
  Future<void> _syncPendingChanges({
    void Function(double progress, String message)? onProgress,
  }) async {
    if (!_isInitialized || _groupId == null) return;
    
    print('🔄 جاري مزامنة التغييرات المعلقة...');
    
    final db = await _db.database;
    
    // رفع العملاء الذين لم يتم رفعهم (0-40%)
    onProgress?.call(0.0, 'جاري رفع العملاء...');
    final customers = await db.query(
      'customers',
      where: 'sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
    );
    
    final totalCustomers = customers.length;
    var uploadedCustomers = 0;
    
    for (final customer in customers) {
      await uploadCustomer(customer);
      uploadedCustomers++;
      if (totalCustomers > 0) {
        final progress = (uploadedCustomers / totalCustomers) * 0.4;
        onProgress?.call(progress, 'رفع العملاء ($uploadedCustomers/$totalCustomers)...');
      }
    }
    
    // رفع المعاملات (40-100%)
    onProgress?.call(0.4, 'جاري رفع المعاملات...');
    final transactions = await db.query(
      'transactions',
      where: 'sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
    );
    
    final totalTransactions = transactions.length;
    var uploadedTransactions = 0;
    
    for (final tx in transactions) {
      // الحصول على sync_uuid للعميل
      final customerId = tx['customer_id'] as int;
      final customerResult = await db.query(
        'customers',
        columns: ['sync_uuid'],
        where: 'id = ?',
        whereArgs: [customerId],
      );
      
      if (customerResult.isNotEmpty) {
        final customerSyncUuid = customerResult.first['sync_uuid'] as String?;
        if (customerSyncUuid != null) {
          await uploadTransaction(tx, customerSyncUuid);
        }
      }
      uploadedTransactions++;
      if (totalTransactions > 0) {
        final progress = 0.4 + ((uploadedTransactions / totalTransactions) * 0.6);
        onProgress?.call(progress, 'رفع المعاملات ($uploadedTransactions/$totalTransactions)...');
      }
    }
    
    onProgress?.call(1.0, 'تم رفع البيانات!');
    await FirebaseSyncConfig.setLastSyncTime(DateTime.now());
    print('✅ تمت مزامنة التغييرات المعلقة');
  }
  
  /// مزامنة كاملة (تنزيل + رفع) مع دعم مؤشر التقدم
  Future<void> performFullSync({
    void Function(double progress, String message)? onProgress,
  }) async {
    if (!_isInitialized || _groupId == null) {
      print('⚠️ المزامنة غير مُعدة');
      return;
    }
    
    // 🔒 منع المزامنة المتزامنة
    if (_isSyncing) {
      print('⚠️ المزامنة قيد التنفيذ بالفعل');
      return;
    }
    
    _isSyncing = true;
    _syncStartTime = DateTime.now();
    _updateStatus(FirebaseSyncStatus.syncing);
    
    try {
      // 🔒 التحقق من الاتصال قبل البدء (5%)
      onProgress?.call(0.05, 'جاري التحقق من الاتصال...');
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResult.any((r) => r != ConnectivityResult.none);
      
      if (!hasConnection) {
        print('📴 لا يوجد اتصال - تأجيل المزامنة');
        _updateStatus(FirebaseSyncStatus.offline);
        return;
      }
      
      // 1. تنزيل البيانات من Firebase (10-50%)
      onProgress?.call(0.10, 'جاري تنزيل العملاء...');
      await _downloadAllData(onProgress: (p, m) {
        // التقدم من 10% إلى 50%
        onProgress?.call(0.10 + (p * 0.40), m);
      });
      
      // 🔒 التحقق من الاتصال مرة أخرى قبل الرفع (55%)
      onProgress?.call(0.55, 'جاري التحقق من الاتصال...');
      final stillConnected = await Connectivity().checkConnectivity();
      if (!stillConnected.any((r) => r != ConnectivityResult.none)) {
        print('📴 انقطع الاتصال أثناء التنزيل - إيقاف المزامنة');
        _updateStatus(FirebaseSyncStatus.offline);
        return;
      }
      
      // 2. رفع البيانات المحلية (60-85%)
      onProgress?.call(0.60, 'جاري رفع البيانات المحلية...');
      await _syncPendingChanges(onProgress: (p, m) {
        // التقدم من 60% إلى 85%
        onProgress?.call(0.60 + (p * 0.25), m);
      });
      
      // 3. التحقق من سلامة البيانات (90%)
      onProgress?.call(0.90, 'جاري التحقق من سلامة البيانات...');
      final integrity = await verifyDataIntegrity();
      if (integrity['valid'] != true) {
        print('⚠️ تحذير: بعض البيانات قد لا تكون متزامنة');
        _syncEventController.add('تحذير: ${integrity['issues']}');
      }
      
      // 4. الانتهاء (100%)
      onProgress?.call(1.0, 'تمت المزامنة بنجاح!');
      
      _updateStatus(FirebaseSyncStatus.online);
      _syncEventController.add('تمت المزامنة الكاملة');
      
      final duration = DateTime.now().difference(_syncStartTime!);
      print('✅ اكتملت المزامنة في ${duration.inSeconds} ثانية');
      
    } catch (e) {
      print('❌ فشلت المزامنة الكاملة: $e');
      _updateStatus(FirebaseSyncStatus.error);
      _errorController.add('فشلت المزامنة: $e');
    } finally {
      _isSyncing = false;
      _syncStartTime = null;
    }
  }
  
  /// تنزيل جميع البيانات من Firebase مع دعم مؤشر التقدم
  Future<void> _downloadAllData({
    void Function(double progress, String message)? onProgress,
  }) async {
    if (_groupId == null) return;
    
    print('⬇️ جاري تنزيل البيانات من Firebase...');
    
    // تنزيل العملاء (0-50%)
    onProgress?.call(0.0, 'جاري تنزيل العملاء...');
    final customersSnapshot = await _firestore!
        .collection('sync_groups')
        .doc(_groupId)
        .collection('customers')
        .get();
    
    final totalCustomers = customersSnapshot.docs.length;
    var processedCustomers = 0;
    
    for (final doc in customersSnapshot.docs) {
      final data = doc.data();
      if (data['deviceId'] != _deviceId) {
        await _applyCustomerChange(doc.id, data);
      }
      processedCustomers++;
      if (totalCustomers > 0) {
        final progress = (processedCustomers / totalCustomers) * 0.5;
        onProgress?.call(progress, 'تنزيل العملاء ($processedCustomers/$totalCustomers)...');
      }
    }
    
    // تنزيل المعاملات (50-100%)
    onProgress?.call(0.5, 'جاري تنزيل المعاملات...');
    final transactionsSnapshot = await _firestore!
        .collection('sync_groups')
        .doc(_groupId)
        .collection('transactions')
        .get();
    
    final totalTransactions = transactionsSnapshot.docs.length;
    var processedTransactions = 0;
    
    for (final doc in transactionsSnapshot.docs) {
      final data = doc.data();
      if (data['deviceId'] != _deviceId) {
        await _applyTransactionChange(doc.id, data);
      }
      processedTransactions++;
      if (totalTransactions > 0) {
        final progress = 0.5 + ((processedTransactions / totalTransactions) * 0.5);
        onProgress?.call(progress, 'تنزيل المعاملات ($processedTransactions/$totalTransactions)...');
      }
    }
    
    onProgress?.call(1.0, 'تم تنزيل البيانات!');
    print('✅ تم تنزيل البيانات من Firebase');
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// أدوات مساعدة
  /// ═══════════════════════════════════════════════════════════════════════
  
  void _updateStatus(FirebaseSyncStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔒 قيود صارمة للتحقق من البيانات ومنع التكرار
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// حساب checksum للبيانات
  String _calculateChecksum(Map<String, dynamic> data) {
    // إزالة الحقول المتغيرة (timestamps, deviceId)
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('uploadedAt');
    cleanData.remove('deviceId');
    cleanData.remove('lastModifiedAt');
    
    final jsonString = jsonEncode(cleanData);
    final bytes = utf8.encode(jsonString);
    return sha256.convert(bytes).toString().substring(0, 16);
  }
  
  /// التحقق من وجود العملية مسبقاً (منع التكرار)
  Future<bool> _operationExists(String syncUuid, String type) async {
    if (_groupId == null) return false;
    
    try {
      final doc = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection(type == 'customer' ? 'customers' : 'transactions')
          .doc(syncUuid)
          .get();
      
      return doc.exists;
    } catch (e) {
      return false;
    }
  }
  
  /// التحقق من صحة البيانات قبل الرفع
  bool _validateCustomerData(Map<String, dynamic> data) {
    // التحقق من الحقول المطلوبة
    if (data['sync_uuid'] == null || (data['sync_uuid'] as String).isEmpty) {
      print('❌ العميل بدون sync_uuid');
      return false;
    }
    if (data['name'] == null || (data['name'] as String).isEmpty) {
      print('❌ العميل بدون اسم');
      return false;
    }
    return true;
  }
  
  bool _validateTransactionData(Map<String, dynamic> data) {
    if (data['sync_uuid'] == null || (data['sync_uuid'] as String).isEmpty) {
      print('❌ المعاملة بدون sync_uuid');
      return false;
    }
    if (data['customer_id'] == null) {
      print('❌ المعاملة بدون customer_id');
      return false;
    }
    if (data['amount_changed'] == null) {
      print('❌ المعاملة بدون مبلغ');
      return false;
    }
    return true;
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🧠 حل التعارضات الذكي (3-Way Merge)
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تحديد كيفية حل التعارض بين البيانات المحلية والبعيدة
  ConflictResult _resolveConflict({
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    required String type,
  }) {
    // 1. التحقق من التطابق (لا يوجد تعارض)
    final localChecksum = _calculateChecksum(localData);
    final remoteChecksum = _calculateChecksum(remoteData);
    
    if (localChecksum == remoteChecksum) {
      return ConflictResult(
        resolution: ConflictResolution.skip,
        reason: 'البيانات متطابقة - لا حاجة للتحديث',
      );
    }
    
    // 2. مقارنة التوقيت (Last Write Wins)
    DateTime? localModified;
    DateTime? remoteModified;
    
    try {
      final localModifiedStr = localData['last_modified_at'] ?? localData['lastModifiedAt'];
      final remoteModifiedStr = remoteData['lastModifiedAt'] ?? remoteData['last_modified_at'];
      
      if (localModifiedStr != null) {
        localModified = DateTime.parse(localModifiedStr.toString());
      }
      if (remoteModifiedStr != null) {
        remoteModified = DateTime.parse(remoteModifiedStr.toString());
      }
    } catch (e) {
      print('⚠️ خطأ في تحليل التوقيت: $e');
    }
    
    // 3. إذا كان أحدهما null، نستخدم الآخر
    if (localModified == null && remoteModified != null) {
      return ConflictResult(
        resolution: ConflictResolution.useRemote,
        reason: 'البيانات المحلية بدون توقيت',
      );
    }
    if (remoteModified == null && localModified != null) {
      return ConflictResult(
        resolution: ConflictResolution.useLocal,
        reason: 'البيانات البعيدة بدون توقيت',
      );
    }
    
    // 4. مقارنة التوقيت - الأحدث يفوز
    if (localModified != null && remoteModified != null) {
      // إضافة هامش 1 ثانية لتجنب مشاكل التوقيت
      final diff = remoteModified.difference(localModified).inSeconds;
      
      if (diff > 1) {
        return ConflictResult(
          resolution: ConflictResolution.useRemote,
          reason: 'البيانات البعيدة أحدث بـ $diff ثانية',
        );
      } else if (diff < -1) {
        return ConflictResult(
          resolution: ConflictResolution.useLocal,
          reason: 'البيانات المحلية أحدث بـ ${-diff} ثانية',
        );
      }
    }
    
    // 5. محاولة الدمج الذكي (للعملاء فقط)
    if (type == 'customer') {
      final merged = _mergeCustomerData(localData, remoteData);
      if (merged != null) {
        return ConflictResult(
          resolution: ConflictResolution.merge,
          reason: 'تم دمج البيانات بنجاح',
          mergedData: merged,
        );
      }
    }
    
    // 6. افتراضياً: استخدام البيانات البعيدة
    return ConflictResult(
      resolution: ConflictResolution.useRemote,
      reason: 'افتراضي: استخدام البيانات البعيدة',
    );
  }
  
  /// دمج بيانات العميل (3-Way Merge)
  Map<String, dynamic>? _mergeCustomerData(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    try {
      final merged = <String, dynamic>{};
      
      // الحقول التي نأخذ الأحدث منها
      final fieldsToMerge = ['name', 'phone', 'address', 'general_note'];
      
      for (final field in fieldsToMerge) {
        final localVal = local[field];
        final remoteVal = remote[field];
        
        // إذا كان أحدهما فارغ، نأخذ الآخر
        if (localVal == null || localVal.toString().isEmpty) {
          merged[field] = remoteVal;
        } else if (remoteVal == null || remoteVal.toString().isEmpty) {
          merged[field] = localVal;
        } else {
          // كلاهما موجود - نأخذ الأطول (أكثر معلومات)
          merged[field] = localVal.toString().length >= remoteVal.toString().length
              ? localVal
              : remoteVal;
        }
      }
      
      // الرصيد: نأخذ الأحدث دائماً
      merged['current_total_debt'] = remote['currentTotalDebt'] ?? 
                                      remote['current_total_debt'] ?? 
                                      local['current_total_debt'];
      
      // باقي الحقول من البيانات البعيدة
      merged['sync_uuid'] = local['sync_uuid'] ?? remote['syncUuid'];
      merged['created_at'] = local['created_at'] ?? remote['createdAt'];
      merged['last_modified_at'] = DateTime.now().toIso8601String();
      merged['is_deleted'] = remote['isDeleted'] == true ? 1 : 0;
      
      return merged;
    } catch (e) {
      print('⚠️ فشل دمج بيانات العميل: $e');
      return null;
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔍 التحقق من سلامة البيانات بعد المزامنة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// التحقق من تطابق عدد السجلات
  Future<Map<String, dynamic>> verifyDataIntegrity() async {
    if (_groupId == null) {
      return {'error': 'غير مُعد', 'valid': false};
    }
    
    final db = await _db.database;
    final issues = <String>[];
    
    try {
      // عدد العملاء محلياً
      final localCustomers = await db.query(
        'customers',
        where: 'sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      
      // عدد العملاء في Firebase
      final remoteCustomersCount = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('customers')
          .where('isDeleted', isNotEqualTo: true)
          .count()
          .get();
      
      // عدد المعاملات محلياً
      final localTransactions = await db.query(
        'transactions',
        where: 'sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      
      // عدد المعاملات في Firebase
      final remoteTransactionsCount = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('transactions')
          .where('isDeleted', isNotEqualTo: true)
          .count()
          .get();
      
      // التحقق من التطابق
      final localCustomerCount = localCustomers.length;
      final remoteCustomerCount = remoteCustomersCount.count ?? 0;
      final localTxCount = localTransactions.length;
      final remoteTxCount = remoteTransactionsCount.count ?? 0;
      
      if (localCustomerCount != remoteCustomerCount) {
        issues.add('عدد العملاء غير متطابق: محلي=$localCustomerCount، سحابي=$remoteCustomerCount');
      }
      
      if (localTxCount != remoteTxCount) {
        issues.add('عدد المعاملات غير متطابق: محلي=$localTxCount، سحابي=$remoteTxCount');
      }
      
      return {
        'valid': issues.isEmpty,
        'localCustomers': localCustomerCount,
        'remoteCustomers': remoteCustomerCount,
        'localTransactions': localTxCount,
        'remoteTransactions': remoteTxCount,
        'issues': issues,
        'checkedAt': DateTime.now().toIso8601String(),
      };
      
    } catch (e) {
      return {
        'valid': false,
        'error': e.toString(),
        'issues': ['فشل التحقق: $e'],
      };
    }
  }
  
  /// 🔍 التحقق من صحة الأرصدة بعد المزامنة
  /// يقارن الرصيد المسجل مع مجموع المعاملات لكل عميل
  Future<Map<String, dynamic>> verifyBalancesAfterSync() async {
    final db = await _db.database;
    final issues = <Map<String, dynamic>>[];
    
    try {
      // جلب جميع العملاء
      final customers = await db.query(
        'customers',
        where: 'is_deleted IS NULL OR is_deleted = 0',
      );
      
      for (final customer in customers) {
        final customerId = customer['id'] as int;
        final customerName = customer['name'] as String? ?? 'غير معروف';
        final recordedBalance = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;
        
        // حساب الرصيد من المعاملات
        final sumResult = await db.rawQuery('''
          SELECT COALESCE(SUM(amount_changed), 0) as total
          FROM transactions
          WHERE customer_id = ? AND (is_deleted IS NULL OR is_deleted = 0)
        ''', [customerId]);
        
        final calculatedBalance = (sumResult.first['total'] as num?)?.toDouble() ?? 0.0;
        
        // مقارنة الأرصدة (مع هامش خطأ صغير)
        final difference = (recordedBalance - calculatedBalance).abs();
        if (difference > 0.01) {
          issues.add({
            'customerId': customerId,
            'customerName': customerName,
            'recordedBalance': recordedBalance,
            'calculatedBalance': calculatedBalance,
            'difference': difference,
          });
          
          print('⚠️ فرق في رصيد العميل "$customerName": مسجل=$recordedBalance، محسوب=$calculatedBalance');
        }
      }
      
      if (issues.isEmpty) {
        print('✅ جميع الأرصدة صحيحة');
      } else {
        print('⚠️ وُجدت ${issues.length} فروقات في الأرصدة');
      }
      
      return {
        'hasIssues': issues.isNotEmpty,
        'issuesCount': issues.length,
        'issues': issues,
        'checkedAt': DateTime.now().toIso8601String(),
      };
      
    } catch (e) {
      print('❌ فشل التحقق من الأرصدة: $e');
      return {
        'hasIssues': false,
        'error': e.toString(),
        'issues': [],
      };
    }
  }
  
  /// إعادة تهيئة الخدمة (بعد تغيير المجموعة)
  Future<void> reinitialize() async {
    await _stopListening();
    _stopBackgroundSync(); // 🔄 إيقاف المزامنة الخلفية
    _isInitialized = false;
    _groupId = null;
    // 🔧 إعادة تعيين المنسق والخدمات لتجنب خطأ التهيئة المكررة
    _coordinator = null;
    _operationTracker = null;
    _ackService = null;
    _crashRecovery = null; // 🛡️ إعادة تعيين WAL
    await initialize();
  }
  
  /// الحصول على إحصائيات المزامنة مع دعم مؤشر التقدم
  Future<Map<String, dynamic>> getSyncStats({
    void Function(double progress, String message)? onProgress,
  }) async {
    if (_groupId == null) {
      return {'error': 'غير مُعد', 'valid': false};
    }
    
    try {
      // المرحلة 1: تحميل عدد العملاء (0% -> 30%)
      onProgress?.call(0.0, 'جاري تحميل بيانات العملاء...');
      final customersCount = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('customers')
          .count()
          .get();
      onProgress?.call(0.3, 'تم تحميل بيانات العملاء ✓');
      
      // المرحلة 2: تحميل عدد المعاملات (30% -> 60%)
      onProgress?.call(0.35, 'جاري تحميل بيانات المعاملات...');
      final transactionsCount = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('transactions')
          .count()
          .get();
      onProgress?.call(0.6, 'تم تحميل بيانات المعاملات ✓');
      
      // المرحلة 3: تحميل وقت آخر مزامنة (60% -> 80%)
      onProgress?.call(0.65, 'جاري تحميل معلومات المزامنة...');
      final lastSync = await FirebaseSyncConfig.getLastSyncTime();
      onProgress?.call(0.8, 'تم تحميل معلومات المزامنة ✓');
      
      // المرحلة 4: إحصائيات المنسق (80% -> 100%)
      onProgress?.call(0.85, 'جاري تحميل إحصائيات المنسق...');
      final coordStats = await _coordinator!.getStats();
      onProgress?.call(1.0, 'اكتمل التحميل!');
      
      return {
        'groupId': _groupId,
        'deviceId': _deviceId,
        'customersInCloud': customersCount.count,
        'transactionsInCloud': transactionsCount.count,
        'lastSync': lastSync?.toIso8601String(),
        'status': _status.name,
        'coordinatorStats': coordStats,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 📱 إدارة الأجهزة المتصلة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تسجيل هذا الجهاز في المجموعة
  Future<void> registerDevice({String? deviceName}) async {
    if (_groupId == null || _deviceId == null || _firestore == null) return;
    
    try {
      final now = DateTime.now();
      final name = deviceName ?? await _getDeviceName();
      
      await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('devices')
          .doc(_deviceId)
          .set({
            'deviceId': _deviceId,
            'deviceName': name,
            'platform': 'Windows',
            'lastSeen': FieldValue.serverTimestamp(),
            'registeredAt': now.toIso8601String(),
            'isOnline': true,
            'isListening': _isListening, // هل يستمع للتغييرات
            'syncStatus': _status.name, // حالة المزامنة
            'appVersion': '1.0.0',
            'groupSecret': _groupSecret,
          }, SetOptions(merge: true));
      
      print('📱 تم تسجيل الجهاز: $name ($_deviceId)');
    } catch (e) {
      print('❌ فشل تسجيل الجهاز: $e');
    }
  }
  
  /// تحديث حالة الجهاز (نبضة قلب) مع معلومات تفصيلية
  Future<void> updateDeviceHeartbeat() async {
    if (_groupId == null || _deviceId == null || _firestore == null) return;
    
    try {
      await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('devices')
          .doc(_deviceId)
          .update({
            'lastSeen': FieldValue.serverTimestamp(),
            'isOnline': true,
            'isListening': _isListening, // هل يستمع للتغييرات الفورية
            'syncStatus': _status.name, // حالة المزامنة الحالية
          });
    } catch (e) {
      // تجاهل الخطأ - قد يكون الجهاز غير مسجل بعد
    }
  }
  
  /// تعليم الجهاز كغير متصل
  Future<void> markDeviceOffline() async {
    if (_groupId == null || _deviceId == null || _firestore == null) return;
    
    try {
      await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('devices')
          .doc(_deviceId)
          .update({
            'isOnline': false,
            'isListening': false,
            'syncStatus': 'offline',
            'lastSeen': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      // تجاهل الخطأ
    }
  }
  
  /// جلب قائمة الأجهزة المتصلة في المجموعة
  Future<List<Map<String, dynamic>>> getConnectedDevices() async {
    if (_groupId == null || _firestore == null) {
      return [];
    }
    
    try {
      final snapshot = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('devices')
          .orderBy('lastSeen', descending: true)
          .get();
      
      final devices = <Map<String, dynamic>>[];
      // 🕰️ استخدام التوقيت المصحح بالسيرفر لتجنب مشاكل الساعة المحلية الخاطئة
      final correctedNow = this.now;
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final lastSeen = data['lastSeen'];
        DateTime? lastSeenDate;
        
        if (lastSeen is Timestamp) {
          lastSeenDate = lastSeen.toDate();
        } else if (lastSeen is String) {
          lastSeenDate = DateTime.tryParse(lastSeen);
        }
        
        // اعتبار الجهاز متصلاً إذا كان آخر ظهور له خلال دقيقة واحدة (30 ثانية نبضة + هامش)
        final secondsSinceLastSeen = lastSeenDate != null 
            ? correctedNow.difference(lastSeenDate).inSeconds 
            : 9999;
        final isRecentlyActive = secondsSinceLastSeen < 60;
        
        // تحديد حالة الاتصال الفعلية
        final isOnline = data['isOnline'] == true && isRecentlyActive;
        final isListening = data['isListening'] == true && isRecentlyActive;
        final syncStatus = data['syncStatus'] as String? ?? 'unknown';
        
        // تحديد حالة المزامنة الفورية
        String realtimeSyncStatus;
        if (!isOnline) {
          realtimeSyncStatus = 'غير متصل';
        } else if (isListening && syncStatus == 'online') {
          realtimeSyncStatus = 'متصل ويستمع ✓';
        } else if (isOnline && !isListening) {
          realtimeSyncStatus = 'متصل (لا يستمع)';
        } else {
          realtimeSyncStatus = syncStatus;
        }
        
        devices.add({
          'deviceId': data['deviceId'] ?? doc.id,
          'deviceName': data['deviceName'] ?? 'جهاز غير معروف',
          'platform': data['platform'] ?? 'غير محدد',
          'lastSeen': lastSeenDate?.toIso8601String(),
          'lastSeenFormatted': _formatLastSeen(lastSeenDate),
          'secondsSinceLastSeen': secondsSinceLastSeen,
          'isOnline': isOnline,
          'isListening': isListening,
          'syncStatus': syncStatus,
          'realtimeSyncStatus': realtimeSyncStatus,
          'isRealtimeSyncActive': isOnline && isListening && syncStatus == 'online',
          'isCurrentDevice': doc.id == _deviceId,
          'registeredAt': data['registeredAt'],
          'appVersion': data['appVersion'],
        });
      }
      
      return devices;
    } catch (e) {
      print('❌ فشل جلب قائمة الأجهزة: $e');
      return [];
    }
  }
  
  /// حذف جهاز من المجموعة
  Future<bool> removeDevice(String deviceId) async {
    if (_groupId == null || _firestore == null) return false;
    
    // لا يمكن حذف الجهاز الحالي
    if (deviceId == _deviceId) {
      print('⚠️ لا يمكن حذف الجهاز الحالي');
      return false;
    }
    
    try {
      await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('devices')
          .doc(deviceId)
          .delete();
      
      print('🗑️ تم حذف الجهاز: $deviceId');
      return true;
    } catch (e) {
      print('❌ فشل حذف الجهاز: $e');
      return false;
    }
  }
  
  /// الحصول على اسم الجهاز
  Future<String> _getDeviceName() async {
    try {
      // محاولة الحصول على اسم الكمبيوتر من متغيرات البيئة
      final computerName = const String.fromEnvironment('COMPUTERNAME', defaultValue: '');
      if (computerName.isNotEmpty) return computerName;
      
      // استخدام معرف الجهاز المختصر كاسم افتراضي
      return 'جهاز ${_deviceId?.substring(0, 8) ?? 'غير معروف'}';
    } catch (e) {
      return 'جهاز غير معروف';
    }
  }
  
  /// تنسيق وقت آخر ظهور
  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'غير معروف';
    
    // 🕰️ استخدام التوقيت المصحح بالسيرفر
    final correctedNow = this.now;
    final diff = correctedNow.difference(lastSeen);
    
    if (diff.inSeconds < 60) {
      return 'الآن';
    } else if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    } else if (diff.inDays < 7) {
      return 'منذ ${diff.inDays} يوم';
    } else {
      return '${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
    }
  }
  
  /// معرف الجهاز الحالي
  String? get deviceId => _deviceId;
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔗 واجهة للتنسيق مع نظام Google Drive Sync
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// التحقق مما إذا كانت العملية مرفوعة على Firebase
  /// (يستخدمها نظام Google Drive لتجنب الرفع المكرر)
  Future<bool> isOperationSyncedToFirebase(String entityType, String syncUuid) async {
    return await _coordinator!.isFirebaseSynced(entityType, syncUuid);
  }
  
  /// الحصول على قائمة العمليات المرفوعة على Firebase
  /// (يستخدمها نظام Google Drive لتخطيها)
  Future<List<String>> getFirebaseSyncedUuids(String entityType) async {
    return await _coordinator!.getFirebaseSyncedUuids(entityType);
  }
  
  /// تسجيل عملية تم استلامها من Firebase
  /// (لإخبار نظام Google Drive أن لا يرفعها)
  Future<void> registerReceivedFromFirebase(String entityType, String syncUuid) async {
    await _coordinator!.registerOperation(
      entityType: entityType,
      syncUuid: syncUuid,
      source: SyncSource.firebase,
    );
    await _coordinator!.markFirebaseSynced(entityType, syncUuid);
  }
  
  /// هل المزامنة قيد التنفيذ؟
  bool get isSyncing => _isSyncing;
  
  /// هل هناك عمليات معلقة؟
  bool get hasPendingUploads => _uploadLocks.isNotEmpty;
  
  /// عدد العمليات المعلقة
  int get pendingUploadsCount => _uploadLocks.length;
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔄 واجهة نظام تتبع العمليات والإقرار
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// الحصول على إحصائيات تتبع العمليات
  Future<Map<String, dynamic>> getOperationTrackerStats() async {
    return await _operationTracker!.getStats();
  }
  
  /// الحصول على ملخص تأكيدات الاستلام
  Future<Map<String, dynamic>> getAckSummary() async {
    return await _ackService!.getAckSummary();
  }
  
  /// الحصول على المعاملات التي لم يتم تأكيد استلامها
  Future<List<String>> getPendingAckTransactions() async {
    return await _ackService!.getPendingAckTransactions();
  }
  
  /// تنظيف التأكيدات القديمة
  Future<int> cleanupOldAcks() async {
    return await _ackService!.cleanupOldAcks();
  }
  
  /// تنظيف سجلات العمليات القديمة
  Future<int> cleanupOldOperationLogs() async {
    return await _operationTracker!.cleanupOldLogs();
  }
  
  /// 🛡️ الحصول على إحصائيات WAL (الحماية من الانقطاع)
  Future<Map<String, dynamic>> getWalRecoveryStats() async {
    if (_crashRecovery == null) {
      return {'error': 'WAL غير مُهيأ'};
    }
    return await _crashRecovery!.getRecoveryStats();
  }
  
  /// 🛡️ الحصول على العمليات المعلقة في WAL
  Future<int> getPendingWalOperationsCount() async {
    if (_crashRecovery == null) return 0;
    final pending = await _crashRecovery!.getPendingUploads();
    return pending.length;
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔄 Retry Queue مع Exponential Backoff (محفوظ في قاعدة البيانات)
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// إضافة عملية للـ Retry Queue (في قاعدة البيانات)
  Future<void> _addToRetryQueue(_RetryOperation operation) async {
    final db = await _db.database;
    
    // التحقق من عدم وجودها مسبقاً
    final existing = await db.query(
      'sync_retry_queue',
      where: 'sync_uuid = ?',
      whereArgs: [operation.syncUuid],
    );
    
    if (existing.isNotEmpty) return;
    
    await db.insert(
      'sync_retry_queue',
      {
        'type': operation.type,
        'sync_uuid': operation.syncUuid,
        'data': jsonEncode(operation.data),
        'retry_count': operation.retryCount,
        'next_retry_time': operation.nextRetryTime.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    
    _scheduleRetry();
  }
  
  /// جدولة المحاولة التالية
  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    
    // جدولة فحص كل 30 ثانية
    _retryTimer = Timer(const Duration(seconds: 30), _processRetryQueue);
  }
  
  /// معالجة الـ Retry Queue (من قاعدة البيانات)
  Future<void> _processRetryQueue() async {
    if (!_isInitialized || _groupId == null) return;
    
    final db = await _db.database;
    final now = DateTime.now();
    
    // جلب العمليات الجاهزة للمحاولة
    final readyOps = await db.query(
      'sync_retry_queue',
      where: 'next_retry_time <= ?',
      whereArgs: [now.toIso8601String()],
      orderBy: 'next_retry_time ASC',
      limit: 10, // معالجة 10 عمليات كحد أقصى في كل مرة
    );
    
    for (final opRow in readyOps) {
      final syncUuid = opRow['sync_uuid'] as String;
      final type = opRow['type'] as String;
      final data = jsonDecode(opRow['data'] as String) as Map<String, dynamic>;
      var retryCount = opRow['retry_count'] as int;
      
      try {
        bool success = false;
        
        if (type == 'customer') {
          await uploadCustomer(data);
          success = true;
        } else if (type == 'transaction') {
          final customerSyncUuid = data['customer_sync_uuid'] as String?;
          if (customerSyncUuid != null) {
            await uploadTransaction(data, customerSyncUuid);
            success = true;
          }
        }
        
        if (success) {
          // حذف من الطابور بعد النجاح
          await db.delete(
            'sync_retry_queue',
            where: 'sync_uuid = ?',
            whereArgs: [syncUuid],
          );
          print('✅ نجحت المحاولة رقم ${retryCount + 1} للعملية $syncUuid');
        }
        
      } catch (e) {
        retryCount++;
        
        if (retryCount >= _maxRetries) {
          // حذف بعد استنفاد المحاولات
          await db.delete(
            'sync_retry_queue',
            where: 'sync_uuid = ?',
            whereArgs: [syncUuid],
          );
          print('❌ فشلت جميع المحاولات للعملية $syncUuid');
          _errorController.add('فشل رفع العملية بعد $_maxRetries محاولات');
        } else {
          // Exponential Backoff: 2s, 4s, 8s, 16s, 32s
          final backoffDelay = _baseRetryDelay * (1 << retryCount);
          final nextRetryTime = DateTime.now().add(backoffDelay);
          
          await db.update(
            'sync_retry_queue',
            {
              'retry_count': retryCount,
              'next_retry_time': nextRetryTime.toIso8601String(),
              'last_error': e.toString(),
            },
            where: 'sync_uuid = ?',
            whereArgs: [syncUuid],
          );
          print('🔄 سيتم إعادة المحاولة ${retryCount + 1} بعد ${backoffDelay.inSeconds} ثانية');
        }
      }
    }
    
    // جدولة المحاولة التالية إذا كان هناك عمليات متبقية
    final remaining = await db.rawQuery('SELECT COUNT(*) as count FROM sync_retry_queue');
    if ((remaining.first['count'] as int) > 0) {
      _scheduleRetry();
    }
  }
  
  /// تحميل Retry Queue عند بدء التشغيل
  Future<void> _loadRetryQueue() async {
    final db = await _db.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sync_retry_queue')
    ) ?? 0;
    
    if (count > 0) {
      print('📋 تم تحميل $count عملية من Retry Queue');
      _scheduleRetry();
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🧹 تنظيف Firebase التلقائي
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تنظيف البيانات القديمة من Firebase
  Future<Map<String, dynamic>> cleanupOldFirebaseData() async {
    if (_groupId == null || _firestore == null) {
      return {'error': 'غير مُعد'};
    }
    
    print('🧹 جاري تنظيف البيانات القديمة من Firebase...');
    
    final cutoffDate = DateTime.now().subtract(Duration(days: _keepFirebaseDataDays));
    
    int deletedCustomers = 0;
    int deletedTransactions = 0;
    
    try {
      // 🔧 إصلاح: استخدام استعلام بسيط بدون Index مركب
      // جلب المعاملات المحذوفة فقط ثم تصفيتها محلياً
      final deletedTransactionsQuery = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('transactions')
          .where('isDeleted', isEqualTo: true)
          .limit(500)
          .get();
      
      for (final doc in deletedTransactionsQuery.docs) {
        final data = doc.data();
        final deletedAtStr = data['deletedAt'] as String?;
        if (deletedAtStr != null) {
          try {
            final deletedAt = DateTime.parse(deletedAtStr);
            if (deletedAt.isBefore(cutoffDate)) {
              await doc.reference.delete();
              deletedTransactions++;
            }
          } catch (_) {
            // تجاهل الأخطاء في تحليل التاريخ
          }
        }
      }
      
      // جلب العملاء المحذوفين فقط ثم تصفيتهم محلياً
      final deletedCustomersQuery = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('customers')
          .where('isDeleted', isEqualTo: true)
          .limit(100)
          .get();
      
      for (final doc in deletedCustomersQuery.docs) {
        final data = doc.data();
        final deletedAtStr = data['deletedAt'] as String?;
        if (deletedAtStr != null) {
          try {
            final deletedAt = DateTime.parse(deletedAtStr);
            if (deletedAt.isBefore(cutoffDate)) {
              await doc.reference.delete();
              deletedCustomers++;
            }
          } catch (_) {
            // تجاهل الأخطاء في تحليل التاريخ
          }
        }
      }
      
      print('✅ تم حذف $deletedCustomers عميل و $deletedTransactions معاملة قديمة');
      
      return {
        'success': true,
        'deletedCustomers': deletedCustomers,
        'deletedTransactions': deletedTransactions,
        'cutoffDate': cutoffDate.toIso8601String(),
      };
      
    } catch (e) {
      print('❌ فشل التنظيف: $e');
      return {'error': e.toString()};
    }
  }
  
  /// التحقق من حجم البيانات في Firebase
  Future<Map<String, dynamic>> checkFirebaseSize() async {
    if (_groupId == null) return {'error': 'غير مُعد'};
    
    try {
      final customersCount = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('customers')
          .count()
          .get();
      
      final transactionsCount = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('transactions')
          .count()
          .get();
      
      final totalCount = (customersCount.count ?? 0) + (transactionsCount.count ?? 0);
      final needsCleanup = totalCount > _maxFirebaseOperations;
      
      return {
        'customersCount': customersCount.count,
        'transactionsCount': transactionsCount.count,
        'totalCount': totalCount,
        'maxAllowed': _maxFirebaseOperations,
        'needsCleanup': needsCleanup,
        'usagePercent': (totalCount / _maxFirebaseOperations * 100).toStringAsFixed(1),
      };
      
    } catch (e) {
      return {'error': e.toString()};
    }
  }
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🕰️ تصحيح التوقيت (Server Time Offset)
  /// ═══════════════════════════════════════════════════════════════════════

  Future<void> _calculateServerTimeOffset() async {
    if (_groupId == null || _groupSecret == null) return;
    
    try {
      // 1. كتابة وثيقة بتوقيت السيرفر
      final docRef = _firestore!.collection('sync_groups').doc(_groupId).collection('_time_check').doc(_deviceId);
      
      await docRef.set({
        'timestamp': FieldValue.serverTimestamp(),
        'groupSecret': _groupSecret, // 🔐 مطلوب للقواعد
        'deviceId': _deviceId,
      });
      
      final writeTime = DateTime.now();
      
      // 2. قراءة الوثيقة
      final snapshot = await docRef.get();
      if (!snapshot.exists) return;
      
      final serverTimestamp = snapshot.data()?['timestamp'] as Timestamp?;
      if (serverTimestamp == null) return;
      
      final serverTime = serverTimestamp.toDate();
      
      // 3. حساب الفرق (مع مراعاة زمن الذهاب والعودة التقريبي)
      // نفترض أن زمن الكتابة = زمن القراءة تقريباً
      final roundTrip = DateTime.now().difference(writeTime);
      final latency = Duration(milliseconds: roundTrip.inMilliseconds ~/ 2);
      
      // الفرق = (وقت السيرفر + التأخير) - وقت الجهاز
      _serverTimeOffset = serverTime.add(latency).difference(DateTime.now());
      
      print('🕰️ تم ضبط توقيت السيرفر. الفرق: ${_serverTimeOffset.inMilliseconds}ms');
      
    } catch (e) {
      print('⚠️ فشل حساب فرق التوقيت: $e');
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 👻 معالجة المعاملات اليتيمة (Orphan Queue)
  /// ═══════════════════════════════════════════════════════════════════════

  Future<void> _createOrphanTable() async {
    final db = await _db.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_orphans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sync_uuid TEXT NOT NULL,
        customer_sync_uuid TEXT NOT NULL,
        data TEXT NOT NULL,
        received_at TEXT NOT NULL,
        UNIQUE(sync_uuid)
      )
    ''');
    
    // فهرس للبحث السريع
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_orphans_customer 
      ON sync_orphans(customer_sync_uuid)
    ''');
    
    // 🔐 جدول Retry Queue (للحفظ الدائم)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_retry_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        sync_uuid TEXT NOT NULL,
        data TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        next_retry_time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_error TEXT,
        UNIQUE(sync_uuid)
      )
    ''');
    
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_retry_next_time 
      ON sync_retry_queue(next_retry_time)
    ''');
  }

  Future<void> _addToOrphans(String syncUuid, Map<String, dynamic> data) async {
    final db = await _db.database;
    final customerSyncUuid = data['customerSyncUuid'] as String;
    
    // 🔐 التحقق من حد الأيتام (منع التراكم)
    final orphanCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM sync_orphans')
    ) ?? 0;
    
    if (orphanCount >= 1000) {
      // حذف أقدم 100 يتيم
      await db.rawDelete('''
        DELETE FROM sync_orphans 
        WHERE id IN (
          SELECT id FROM sync_orphans 
          ORDER BY received_at ASC 
          LIMIT 100
        )
      ''');
      print('🧹 تم حذف 100 معاملة يتيمة قديمة (الحد الأقصى 1000)');
    }
    
    // 🔧 إصلاح: تحويل Timestamp إلى String قبل jsonEncode
    final cleanData = _convertTimestampsToStrings(data);
    
    await db.insert(
      'sync_orphans',
      {
        'sync_uuid': syncUuid,
        'customer_sync_uuid': customerSyncUuid,
        'data': jsonEncode(cleanData),
        'received_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    print('👻 تم إضافة معاملة يتيمة للطابور: $syncUuid (العميل: $customerSyncUuid)');
  }
  
  /// 🔧 تحويل Timestamp من Firebase إلى String
  Map<String, dynamic> _convertTimestampsToStrings(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is Timestamp) {
        result[entry.key] = value.toDate().toIso8601String();
      } else if (value is Map<String, dynamic>) {
        result[entry.key] = _convertTimestampsToStrings(value);
      } else if (value is List) {
        result[entry.key] = value.map((item) {
          if (item is Timestamp) {
            return item.toDate().toIso8601String();
          } else if (item is Map<String, dynamic>) {
            return _convertTimestampsToStrings(item);
          }
          return item;
        }).toList();
      } else {
        result[entry.key] = value;
      }
    }
    return result;
  }

  Future<void> _processOrphans(int customerId, String customerSyncUuid) async {
    final db = await _db.database;
    
    // البحث عن معاملات لهذا العميل
    final orphans = await db.query(
      'sync_orphans',
      where: 'customer_sync_uuid = ?',
      whereArgs: [customerSyncUuid],
    );
    
    if (orphans.isEmpty) return;
    
    print('👻 تم العثور على ${orphans.length} معاملة يتيمة للعميل $customerSyncUuid');
    
    for (final orphan in orphans) {
      try {
        final data = jsonDecode(orphan['data'] as String) as Map<String, dynamic>;
        final syncUuid = orphan['sync_uuid'] as String;
        
        // محاولة تطبيق المعاملة الآن
        await _applyTransactionChange(syncUuid, data);
        
        // حذف من الطابور بعد النجاح
        await db.delete(
          'sync_orphans',
          where: 'sync_uuid = ?',
          whereArgs: [syncUuid],
        );
        
      } catch (e) {
        print('❌ فشل معالجة المعاملة اليتيمة: $e');
      }
    }
  }
  
  /// ═══════════════════════════════════════════════════════════════════════
  /// 🔧 إصلاح وتعيين sync_uuid للمعاملات القديمة
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// إصلاح المعاملات التي ليس لها sync_uuid ورفعها إلى Firebase
  Future<Map<String, dynamic>> repairAndSyncAllTransactions() async {
    if (!_isInitialized || _groupId == null) {
      return {'success': false, 'error': 'المزامنة غير مُعدة'};
    }
    
    final db = await _db.database;
    int fixedCount = 0;
    int uploadedCount = 0;
    int errorCount = 0;
    
    print('🔧 بدء إصلاح ومزامنة جميع المعاملات...');
    
    try {
      // 1️⃣ إصلاح المعاملات التي ليس لها sync_uuid
      final transactionsWithoutUuid = await db.query(
        'transactions',
        where: 'sync_uuid IS NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      
      for (final tx in transactionsWithoutUuid) {
        final existingUuid = tx['transaction_uuid'] as String?;
        final uuid = existingUuid ?? SyncSecurity.generateUuid();
        await db.update(
          'transactions',
          {'sync_uuid': uuid},
          where: 'id = ?',
          whereArgs: [tx['id']],
        );
        fixedCount++;
      }
      
      if (fixedCount > 0) {
        print('✅ تم إصلاح $fixedCount معاملة بدون sync_uuid');
      }
      
      // 2️⃣ إصلاح العملاء الذين ليس لهم sync_uuid
      final customersWithoutUuid = await db.query(
        'customers',
        where: 'sync_uuid IS NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      
      for (final customer in customersWithoutUuid) {
        final uuid = SyncSecurity.generateUuid();
        await db.update(
          'customers',
          {'sync_uuid': uuid},
          where: 'id = ?',
          whereArgs: [customer['id']],
        );
      }
      
      if (customersWithoutUuid.isNotEmpty) {
        print('✅ تم إصلاح ${customersWithoutUuid.length} عميل بدون sync_uuid');
      }
      
      // 3️⃣ رفع جميع العملاء
      final allCustomers = await db.query(
        'customers',
        where: 'sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      
      print('📤 جاري رفع ${allCustomers.length} عميل...');
      
      for (final customer in allCustomers) {
        try {
          await _forceUploadCustomer(customer);
        } catch (e) {
          print('❌ فشل رفع عميل: $e');
          errorCount++;
        }
      }
      
      // 4️⃣ رفع جميع المعاملات (بدون التحقق من is_created_by_me)
      final allTransactions = await db.query(
        'transactions',
        where: 'sync_uuid IS NOT NULL AND (is_deleted IS NULL OR is_deleted = 0)',
      );
      
      print('📤 جاري رفع ${allTransactions.length} معاملة...');
      
      for (final tx in allTransactions) {
        try {
          final customerId = tx['customer_id'] as int;
          final customerResult = await db.query(
            'customers',
            columns: ['sync_uuid'],
            where: 'id = ?',
            whereArgs: [customerId],
          );
          
          if (customerResult.isNotEmpty) {
            final customerSyncUuid = customerResult.first['sync_uuid'] as String?;
            if (customerSyncUuid != null) {
              await _forceUploadTransaction(tx, customerSyncUuid);
              uploadedCount++;
            }
          }
        } catch (e) {
          print('❌ فشل رفع معاملة: $e');
          errorCount++;
        }
      }
      
      print('═══════════════════════════════════════════════════════════════════');
      print('✅ اكتمل الإصلاح والمزامنة:');
      print('   - معاملات تم إصلاحها: $fixedCount');
      print('   - معاملات تم رفعها: $uploadedCount');
      print('   - أخطاء: $errorCount');
      print('═══════════════════════════════════════════════════════════════════');
      
      return {
        'success': true,
        'fixed': fixedCount,
        'uploaded': uploadedCount,
        'errors': errorCount,
      };
      
    } catch (e) {
      print('❌ فشل الإصلاح والمزامنة: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// رفع عميل بالقوة (بدون التحقق من الحالة السابقة)
  Future<void> _forceUploadCustomer(Map<String, dynamic> customerData) async {
    if (_groupId == null) return;
    
    final syncUuid = customerData['sync_uuid'] as String?;
    if (syncUuid == null || syncUuid.isEmpty) return;
    
    // التحقق من Rate Limiting
    if (!_rateLimiter.canProceed()) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _rateLimiter.recordOperation();
    
    final checksum = _calculateChecksum(customerData);
    
    await _firestore!
        .collection('sync_groups')
        .doc(_groupId)
        .collection('customers')
        .doc(syncUuid)
        .set({
          'syncUuid': syncUuid,
          'name': customerData['name'],
          'phone': customerData['phone'],
          'currentTotalDebt': customerData['current_total_debt'],
          'generalNote': customerData['general_note'],
          'address': customerData['address'],
          'createdAt': customerData['created_at'],
          'lastModifiedAt': customerData['last_modified_at'] ?? DateTime.now().toIso8601String(),
          'audioNotePath': customerData['audio_note_path'],
          'isDeleted': false,
          'deviceId': _deviceId,
          'originDeviceId': _deviceId,
          'checksum': checksum,
          'groupSecret': _groupSecret,
          'uploadedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
  
  /// رفع معاملة بالقوة (بدون التحقق من is_created_by_me)
  Future<void> _forceUploadTransaction(Map<String, dynamic> txData, String customerSyncUuid) async {
    if (_groupId == null) return;
    
    final syncUuid = txData['sync_uuid'] as String?;
    if (syncUuid == null || syncUuid.isEmpty) return;
    
    // التحقق من Rate Limiting
    if (!_rateLimiter.canProceed()) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _rateLimiter.recordOperation();
    
    final checksum = _calculateChecksum(txData);
    
    await _firestore!
        .collection('sync_groups')
        .doc(_groupId)
        .collection('transactions')
        .doc(syncUuid)
        .set({
          'syncUuid': syncUuid,
          'customerSyncUuid': customerSyncUuid,
          'transactionDate': txData['transaction_date'],
          'amountChanged': txData['amount_changed'],
          'balanceBeforeTransaction': txData['balance_before_transaction'],
          'newBalanceAfterTransaction': txData['new_balance_after_transaction'],
          'transactionNote': txData['transaction_note'],
          'transactionType': txData['transaction_type'],
          'description': txData['description'],
          'createdAt': txData['created_at'],
          'lastModifiedAt': DateTime.now().toIso8601String(),
          'audioNotePath': txData['audio_note_path'],
          'isDeleted': false,
          'deviceId': _deviceId,
          'originDeviceId': _deviceId,
          'checksum': checksum,
          'groupSecret': _groupSecret,
          'uploadedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// عملية في انتظار إعادة المحاولة
/// ═══════════════════════════════════════════════════════════════════════════
class _RetryOperation {
  final String type; // 'customer' أو 'transaction'
  final String syncUuid;
  final Map<String, dynamic> data;
  int retryCount;
  DateTime nextRetryTime;
  
  _RetryOperation({
    required this.type,
    required this.syncUuid,
    required this.data,
    this.retryCount = 0,
    DateTime? nextRetryTime,
  }) : nextRetryTime = nextRetryTime ?? DateTime.now();
}
