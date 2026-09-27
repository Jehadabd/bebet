// lib/services/sync/sync_tracker.dart
// تتبع التغييرات وإنشاء عمليات المزامنة تلقائياً

import 'dart:convert';
import 'sync_models.dart';
import 'sync_operation.dart';
import 'sync_security.dart';
import 'sync_local_storage.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// متتبع التغييرات للمزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncTracker {
  final SyncLocalStorage _storage;
  String? _deviceId;
  String? _secretKey;
  bool _isEnabled = false;

  SyncTracker([SyncLocalStorage? storage]) 
    : _storage = storage ?? SyncLocalStorage();

  // متغير لتتبع حالة التهيئة
  bool _isInitialized = false;
  bool _isInitializing = false;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🚫 مزامنة Google Drive معطّلة
  // ═══════════════════════════════════════════════════════════════════════════
  // المزامنة المعتمدة في التطبيق هي Firebase وحدها، ولها متتبّعها المستقل
  // (services/firebase_sync/sync_operation_tracker.dart) الذي لا علاقة له
  // بهذا الملف ولا بجدول sync_operations.
  //
  // هذا المتتبّع كان يكتب صفاً في sync_operations مع كل معاملة وكل عميل —
  // 3,489 بايت للصف الواحد (نسخة JSON قبل وبعد + توقيع + checksum)، أي
  // ~13.8 ميجابايت سنوياً — في طابور انتظار لرفع إلى Google Drive لم يحدث
  // ولا مرة: 3,388 عملية بحالة pending منذ 2025-12-16، و uploaded_at فارغ
  // في جميعها.
  //
  // لإعادة تفعيل مزامنة Drive يوماً ما: اجعل هذا الثابت true فقط.
  static const bool kDriveSyncEnabled = false;

  /// تهيئة المتتبع
  Future<void> initialize() async {
    // 🚫 التتبع معطّل: نخرج قبل تفعيل _isEnabled، فتصبح كل دوال التسجيل
    //    بلا أثر (كلها تبدأ بـ if (!isEnabled) return).
    if (!kDriveSyncEnabled) {
      _isInitialized = true;
      print('ℹ️ تتبّع مزامنة Google Drive معطّل — المزامنة عبر Firebase فقط');
      return;
    }

    // تجنب التهيئة المتكررة
    if (_isInitialized) return;
    
    // تجنب التهيئة المتزامنة
    if (_isInitializing) {
      while (_isInitializing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }
    
    _isInitializing = true;
    
    try {
      // استخدام getOrCreateDeviceId لضمان وجود معرف ثابت
      _deviceId = await SyncSecurity.getOrCreateDeviceId();
      _secretKey = await SyncSecurity.getOrCreateSecretKey();
      
      await _storage.ensureSyncTables();
      _isEnabled = true;
      _isInitialized = true;
      print('✅ SyncTracker initialized for device: $_deviceId');
    } finally {
      _isInitializing = false;
    }
  }

  /// هل التتبع مفعل؟
  bool get isEnabled => _isEnabled && _deviceId != null && _secretKey != null;

  /// تعطيل التتبع مؤقتاً (أثناء تطبيق عمليات من أجهزة أخرى)
  void disable() => _isEnabled = false;
  
  /// تفعيل التتبع
  void enable() => _isEnabled = true;

  /// ═══════════════════════════════════════════════════════════════════════
  /// تتبع عمليات العملاء
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تسجيل إنشاء عميل جديد
  Future<String?> trackCustomerCreate(Map<String, dynamic> customerData) async {
    if (!isEnabled) return null;
    
    final syncUuid = customerData['sync_uuid'] as String? ?? SyncSecurity.generateUuid();
    
    final operation = await _createOperation(
      operationType: SyncOperationType.customerCreate,
      entityType: 'customer',
      entityUuid: syncUuid,
      payloadAfter: _sanitizeCustomerData(customerData),
    );
    
    if (operation != null) {
      await _storage.saveOperation(operation);
      print('📝 تم تسجيل عملية إنشاء عميل: $syncUuid');
    }
    
    return syncUuid;
  }


  /// تسجيل تحديث عميل
  Future<void> trackCustomerUpdate(
    String syncUuid,
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
  ) async {
    if (!isEnabled) return;
    
    final operation = await _createOperation(
      operationType: SyncOperationType.customerUpdate,
      entityType: 'customer',
      entityUuid: syncUuid,
      payloadBefore: _sanitizeCustomerData(oldData),
      payloadAfter: _sanitizeCustomerData(newData),
    );
    
    if (operation != null) {
      await _storage.saveOperation(operation);
      print('📝 تم تسجيل عملية تحديث عميل: $syncUuid');
    }
  }

  /// تسجيل حذف عميل
  Future<void> trackCustomerDelete(String syncUuid, Map<String, dynamic> oldData) async {
    if (!isEnabled) return;
    
    final operation = await _createOperation(
      operationType: SyncOperationType.customerDelete,
      entityType: 'customer',
      entityUuid: syncUuid,
      payloadBefore: _sanitizeCustomerData(oldData),
      payloadAfter: {'deleted': true, 'deleted_at': DateTime.now().toUtc().toIso8601String()},
    );
    
    if (operation != null) {
      await _storage.saveOperation(operation);
      print('📝 تم تسجيل عملية حذف عميل: $syncUuid');
    }
  }

  Map<String, dynamic> _sanitizeCustomerData(Map<String, dynamic> data) {
    // إزالة الحقول غير الضرورية للمزامنة
    final sanitized = Map<String, dynamic>.from(data);
    sanitized.remove('id'); // المعرف المحلي
    return sanitized;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// تتبع عمليات المعاملات
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// تسجيل إنشاء معاملة جديدة
  /// يتضمن بيانات العميل للسماح بإنشائه تلقائياً على الجهاز الآخر
  Future<String?> trackTransactionCreate(
    Map<String, dynamic> transactionData,
    String? customerSyncUuid, {
    String? customerName,
    String? customerPhone,
  }) async {
    if (!isEnabled) return null;
    
    final transactionUuid = transactionData['transaction_uuid'] as String? 
        ?? transactionData['sync_uuid'] as String?
        ?? SyncSecurity.generateUuid();
    
    // 🔄 تضمين بيانات العميل في المعاملة (Enriched Operation)
    final enrichedData = _sanitizeTransactionData(transactionData);
    if (customerName != null && customerName.isNotEmpty) {
      enrichedData['customer_name'] = customerName;
    }
    if (customerPhone != null && customerPhone.isNotEmpty) {
      enrichedData['customer_phone'] = customerPhone;
    }
    
    final operation = await _createOperation(
      operationType: SyncOperationType.transactionCreate,
      entityType: 'transaction',
      entityUuid: transactionUuid,
      customerUuid: customerSyncUuid,
      payloadAfter: enrichedData,
    );
    
    if (operation != null) {
      await _storage.saveOperation(operation);
      print('📝 تم تسجيل عملية إنشاء معاملة: $transactionUuid (عميل: $customerName)');
    }
    
    return transactionUuid;
  }

  /// تسجيل تحديث معاملة
  Future<void> trackTransactionUpdate(
    String transactionUuid,
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
    String? customerSyncUuid,
  ) async {
    if (!isEnabled) return;
    
    final operation = await _createOperation(
      operationType: SyncOperationType.transactionUpdate,
      entityType: 'transaction',
      entityUuid: transactionUuid,
      customerUuid: customerSyncUuid,
      payloadBefore: _sanitizeTransactionData(oldData),
      payloadAfter: _sanitizeTransactionData(newData),
    );
    
    if (operation != null) {
      await _storage.saveOperation(operation);
      print('📝 تم تسجيل عملية تحديث معاملة: $transactionUuid');
    }
  }

  /// تسجيل حذف معاملة
  Future<void> trackTransactionDelete(
    String transactionUuid,
    Map<String, dynamic> oldData,
    String? customerSyncUuid,
  ) async {
    if (!isEnabled) return;
    
    final operation = await _createOperation(
      operationType: SyncOperationType.transactionDelete,
      entityType: 'transaction',
      entityUuid: transactionUuid,
      customerUuid: customerSyncUuid,
      payloadBefore: _sanitizeTransactionData(oldData),
      payloadAfter: {'deleted': true, 'deleted_at': DateTime.now().toUtc().toIso8601String()},
    );
    
    if (operation != null) {
      await _storage.saveOperation(operation);
      print('📝 تم تسجيل عملية حذف معاملة: $transactionUuid');
    }
  }

  Map<String, dynamic> _sanitizeTransactionData(Map<String, dynamic> data) {
    final sanitized = Map<String, dynamic>.from(data);
    sanitized.remove('id'); // المعرف المحلي
    sanitized.remove('customer_id'); // سنستخدم customer_uuid بدلاً منه
    return sanitized;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// إنشاء العملية
  /// ═══════════════════════════════════════════════════════════════════════
  
  Future<SyncOperation?> _createOperation({
    required SyncOperationType operationType,
    required String entityType,
    required String entityUuid,
    String? customerUuid,
    Map<String, dynamic>? payloadBefore,
    required Map<String, dynamic> payloadAfter,
  }) async {
    if (_deviceId == null || _secretKey == null) return null;
    
    try {
      // الحصول على التسلسل المحلي التالي
      final localSequence = await _storage.getNextLocalSequence(_deviceId!);
      
      // الحصول على Causality Vector الحالي
      final causalityVector = await _storage.getCurrentCausalityVector();
      causalityVector.increment(_deviceId!);
      
      // إنشاء العملية
      return SyncOperation.create(
        deviceId: _deviceId!,
        localSequence: localSequence,
        operationType: operationType,
        entityType: entityType,
        entityUuid: entityUuid,
        customerUuid: customerUuid,
        payloadBefore: payloadBefore,
        payloadAfter: payloadAfter,
        causalityVector: causalityVector,
        secretKey: _secretKey!,
      );
    } catch (e) {
      print('❌ خطأ في إنشاء عملية المزامنة: $e');
      return null;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// استعلامات
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// الحصول على عدد العمليات المعلقة
  Future<int> getPendingOperationsCount() async {
    final operations = await _storage.getPendingOperations();
    return operations.length;
  }

  /// الحصول على العمليات المعلقة
  Future<List<SyncOperation>> getPendingOperations() async {
    return await _storage.getPendingOperations();
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// Singleton للوصول السهل
/// ═══════════════════════════════════════════════════════════════════════════
class SyncTrackerInstance {
  static SyncTracker? _instance;
  
  static SyncTracker get instance {
    _instance ??= SyncTracker();
    return _instance!;
  }
  
  static Future<void> initialize() async {
    await instance.initialize();
  }
}
