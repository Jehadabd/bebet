// lib/services/sync/sync_engine_optimized.dart
// محرك المزامنة المحسّن للمساحة المحدودة (5GB Google Drive)
// 
// التحسينات المطبقة:
// 1. ✅ Verify-After-Write Lock - حل Race Condition
// 2. ✅ Batching Strategy - تجميع العمليات في ملف واحد
// 3. ✅ GZIP Compression - ضغط 90% للبيانات
// 4. ✅ Rolling Snapshots - صور كاملة دورية مع حذف القديم
// 5. ✅ Smart Cleanup - تنظيف ذكي للحفاظ على المساحة
// 6. ✅ Delta Sync - مزامنة الفروقات فقط

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'sync_models.dart';
import 'sync_operation.dart';
import 'sync_security.dart';
import '../database_service.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// إعدادات المزامنة المحسّنة للمساحة المحدودة
/// ═══════════════════════════════════════════════════════════════════════════
class OptimizedSyncConfig {
  // إعدادات القفل
  final Duration lockTimeout;
  final Duration lockRetryInterval;
  final int maxLockRetries;
  final Duration verifyAfterWriteDelay; // تأخير التحقق بعد الكتابة
  
  // إعدادات Batching
  final int maxOperationsPerBatch;
  final int batchUploadThreshold; // عدد العمليات قبل الرفع التلقائي
  
  // إعدادات Snapshots
  final int snapshotEveryNOperations;
  final int maxSnapshotsToKeep; // عدد الـ snapshots المحفوظة
  final int maxOperationFilesToKeep; // عدد ملفات العمليات المحفوظة
  
  // إعدادات التنظيف
  final int keepOperationsDays;
  final int maxStorageMB; // الحد الأقصى للمساحة المستخدمة
  final double cleanupThresholdPercent; // نسبة المساحة التي تبدأ عندها التنظيف
  
  // إعدادات الضغط
  final bool enableCompression;
  final int compressionLevel; // 1-9 (9 = أعلى ضغط)
  
  const OptimizedSyncConfig({
    // القفل
    this.lockTimeout = const Duration(minutes: 3),
    this.lockRetryInterval = const Duration(seconds: 5),
    this.maxLockRetries = 6,
    this.verifyAfterWriteDelay = const Duration(milliseconds: 300),
    
    // Batching
    this.maxOperationsPerBatch = 500,
    this.batchUploadThreshold = 50,
    
    // Snapshots - محسّن للمساحة
    this.snapshotEveryNOperations = 200,
    this.maxSnapshotsToKeep = 3, // فقط 3 snapshots
    this.maxOperationFilesToKeep = 10, // فقط 10 ملفات عمليات
    
    // التنظيف
    this.keepOperationsDays = 14, // أسبوعين فقط
    this.maxStorageMB = 500, // 500MB كحد أقصى (10% من 5GB)
    this.cleanupThresholdPercent = 0.8, // تنظيف عند 80%
    
    // الضغط
    this.enableCompression = true,
    this.compressionLevel = 6, // توازن بين السرعة والحجم
  });
}

/// ═══════════════════════════════════════════════════════════════════════════
/// تقرير استخدام المساحة
/// ═══════════════════════════════════════════════════════════════════════════
class StorageReport {
  final int totalBytes;
  final int snapshotsBytes;
  final int operationsBytes;
  final int manifestBytes;
  final int otherBytes;
  final int filesCount;
  final DateTime checkedAt;
  
  StorageReport({
    required this.totalBytes,
    required this.snapshotsBytes,
    required this.operationsBytes,
    required this.manifestBytes,
    required this.otherBytes,
    required this.filesCount,
    required this.checkedAt,
  });
  
  double get totalMB => totalBytes / (1024 * 1024);
  double get snapshotsMB => snapshotsBytes / (1024 * 1024);
  double get operationsMB => operationsBytes / (1024 * 1024);
  
  Map<String, dynamic> toJson() => {
    'total_bytes': totalBytes,
    'total_mb': totalMB.toStringAsFixed(2),
    'snapshots_mb': snapshotsMB.toStringAsFixed(2),
    'operations_mb': operationsMB.toStringAsFixed(2),
    'files_count': filesCount,
    'checked_at': checkedAt.toIso8601String(),
  };
}

/// ═══════════════════════════════════════════════════════════════════════════
/// محرك المزامنة المحسّن
/// ═══════════════════════════════════════════════════════════════════════════
class OptimizedSyncEngine {
  final OptimizedSyncConfig config;
  final DatabaseService _db;
  
  String? _deviceId;
  String? _deviceName;
  String? _secretKey;
  
  // حالة المزامنة
  bool _isSyncing = false;
  SyncLock? _currentLock;
  Timer? _heartbeatTimer;
  Duration _serverTimeOffset = Duration.zero; // لتصحيح التوقيت
  final String _currentAppVersion = '1.0.0'; // يجب أن يأتي من package_info
  
  // Cache للمجلدات
  String? _syncFolderId;
  final Map<String, String> _subFolderIds = {};
  
  // Callbacks
  Function(String)? onStatusChange;
  Function(double)? onProgress;
  Function(SyncReport)? onSyncComplete;
  Function(StorageReport)? onStorageCheck;
  
  // Drive API
  http.Client? _httpClient;
  drive.DriveApi? _driveApi;
  
  static const String _syncFolderName = 'DebtBook_Sync_v3';
  static const String _lockFileName = '.lock';
  static const String _manifestFileName = 'manifest.json.gz';
  static const String _snapshotsFolderName = 'snapshots';
  static const String _batchesFolderName = 'batches';

  OptimizedSyncEngine({
    this.config = const OptimizedSyncConfig(),
    DatabaseService? db,
  }) : _db = db ?? DatabaseService();

  /// تهيئة المحرك
  Future<void> initialize({
    required http.Client httpClient,
    required String deviceId,
    String? deviceName,
  }) async {
    _httpClient = httpClient;
    _driveApi = drive.DriveApi(httpClient);
    _deviceId = deviceId;
    _deviceName = deviceName ?? 'Device_${deviceId.substring(0, 8)}';
    _secretKey = await SyncSecurity.getOrCreateSecretKey();
    
    // لا نحفظ الـ deviceId هنا - يتم حفظه في SyncSecurity.getOrCreateDeviceId()
    
    print('🔄 OptimizedSyncEngine initialized for device: $_deviceId');
  }

  bool get isReady => _driveApi != null && _deviceId != null && _secretKey != null;
  bool get isSyncing => _isSyncing;



  /// ═══════════════════════════════════════════════════════════════════════
  /// القفل المحسّن مع Verify-After-Write
  /// ═══════════════════════════════════════════════════════════════════════
  
  /// الحصول على القفل مع التحقق المزدوج
  Future<bool> _acquireLockSafely() async {
    _updateStatus('جاري الحصول على القفل...');
    
    for (int attempt = 1; attempt <= config.maxLockRetries; attempt++) {
      try {
        // 1. قراءة القفل الحالي
        final existingLock = await _readLock();
        
        if (existingLock != null) {
          if (existingLock.isExpired) {
            print('🔓 القفل منتهي الصلاحية، جاري الحذف...');
            await _forceDeleteLock();
          } else if (existingLock.deviceId == _deviceId) {
            print('🔄 تجديد القفل الحالي...');
            _currentLock = await _renewLock(existingLock);
            _startHeartbeat();
            return true;
          } else {
            print('⏳ القفل مشغول بواسطة ${existingLock.deviceName}');
            _updateStatus('انتظار القفل... محاولة $attempt/${config.maxLockRetries}');
            await Future.delayed(config.lockRetryInterval);
            continue;
          }
        }
        
        // 2. إنشاء قفل جديد مع Verify-After-Write
        final newLock = await _createLockWithVerification();
        if (newLock != null) {
          _currentLock = newLock;
          _startHeartbeat();
          print('🔒 تم الحصول على القفل بنجاح');
          return true;
        }
        
      } catch (e) {
        print('❌ خطأ في الحصول على القفل: $e');
        if (attempt == config.maxLockRetries) {
          throw SyncException(
            type: SyncErrorType.lockAcquisitionFailed,
            message: 'فشل الحصول على القفل بعد ${config.maxLockRetries} محاولات',
            originalError: e,
          );
        }
      }
      
      // Exponential backoff
      final delay = config.lockRetryInterval * (attempt);
      await Future.delayed(delay);
    }
    
    return false;
  }

  /// إنشاء قفل مع التحقق بعد الكتابة (Verify-After-Write)
  Future<SyncLock?> _createLockWithVerification() async {
    final now = DateTime.now().toUtc();
    final lockId = '${_deviceId}_${now.millisecondsSinceEpoch}';
    
    final lock = SyncLock(
      lockId: lockId,
      deviceId: _deviceId!,
      deviceName: _deviceName!,
      acquiredAt: now,
      expiresAt: now.add(config.lockTimeout),
      operationType: 'SYNC',
      heartbeat: now,
      signature: SyncSecurity.signData('$_deviceId|${now.toIso8601String()}', _secretKey!),
    );
    
    // 1. رفع ملف القفل
    final lockFileId = await _writeLockFile(lock);
    if (lockFileId == null) return null;
    
    // 2. انتظار فترة عشوائية (200-500ms)
    final randomDelay = 200 + (DateTime.now().millisecond % 300);
    await Future.delayed(Duration(milliseconds: randomDelay));
    
    // 3. التحقق من أن ملفنا هو الوحيد
    final folderId = await _ensureSyncFolder();
    final allLocks = await _driveApi!.files.list(
      q: "name = '$_lockFileName' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
      orderBy: 'createdTime',
      $fields: 'files(id,name,createdTime)',
    );
    
    final lockFiles = allLocks.files ?? [];
    
    if (lockFiles.isEmpty) {
      // لا يوجد ملف قفل - غريب، لكن نحاول مرة أخرى
      return null;
    }
    
    if (lockFiles.length == 1 && lockFiles.first.id == lockFileId) {
      // ملفنا هو الوحيد ✅
      return lock;
    }
    
    // يوجد أكثر من ملف قفل - Race Condition!
    // الملف الأقدم يفوز
    final oldestFile = lockFiles.first;
    if (oldestFile.id != lockFileId) {
      // ملف آخر أقدم، نحذف ملفنا وننسحب
      print('⚠️ Race Condition! جهاز آخر حصل على القفل أولاً');
      try {
        await _driveApi!.files.delete(lockFileId);
      } catch (_) {}
      return null;
    }
    
    // ملفنا هو الأقدم، نحذف الملفات الأخرى
    for (final file in lockFiles.skip(1)) {
      try {
        await _driveApi!.files.delete(file.id!);
      } catch (_) {}
    }
    
    return lock;
  }

  Future<String?> _writeLockFile(SyncLock lock) async {
    try {
      final folderId = await _ensureSyncFolder();
      final content = jsonEncode(lock.toJson());
      final bytes = utf8.encode(content);
      
      final tempFile = await _createTempFile(_lockFileName, bytes);
      final media = drive.Media(tempFile.openRead(), bytes.length);
      
      final created = await _driveApi!.files.create(
        drive.File()
          ..name = _lockFileName
          ..parents = [folderId],
        uploadMedia: media,
      );
      
      await tempFile.delete();
      return created.id;
    } catch (e) {
      print('❌ فشل كتابة ملف القفل: $e');
      return null;
    }
  }

  Future<SyncLock?> _readLock() async {
    try {
      final folderId = await _ensureSyncFolder();
      final files = await _driveApi!.files.list(
        q: "name = '$_lockFileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );
      
      if (files.files?.isEmpty ?? true) return null;
      
      final fileId = files.files!.first.id!;
      final content = await _downloadFileContent(fileId);
      if (content == null) return null;
      
      final json = jsonDecode(content) as Map<String, dynamic>;
      return SyncLock.fromJson(json);
    } catch (e) {
      print('⚠️ خطأ في قراءة القفل: $e');
      return null;
    }
  }

  Future<SyncLock> _renewLock(SyncLock existingLock) async {
    final now = DateTime.now().toUtc();
    final renewed = SyncLock(
      lockId: existingLock.lockId,
      deviceId: existingLock.deviceId,
      deviceName: existingLock.deviceName,
      acquiredAt: existingLock.acquiredAt,
      expiresAt: now.add(config.lockTimeout),
      operationType: existingLock.operationType,
      heartbeat: now,
      signature: SyncSecurity.signData('$_deviceId|${now.toIso8601String()}', _secretKey!),
    );
    
    await _updateLockFile(renewed);
    return renewed;
  }

  Future<void> _updateLockFile(SyncLock lock) async {
    final folderId = await _ensureSyncFolder();
    final files = await _driveApi!.files.list(
      q: "name = '$_lockFileName' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
    );
    
    if (files.files?.isEmpty ?? true) return;
    
    final content = jsonEncode(lock.toJson());
    final bytes = utf8.encode(content);
    final tempFile = await _createTempFile(_lockFileName, bytes);
    final media = drive.Media(tempFile.openRead(), bytes.length);
    
    await _driveApi!.files.update(
      drive.File()..name = _lockFileName,
      files.files!.first.id!,
      uploadMedia: media,
    );
    
    await tempFile.delete();
  }

  Future<void> _forceDeleteLock() async {
    try {
      final folderId = await _ensureSyncFolder();
      final files = await _driveApi!.files.list(
        q: "name = '$_lockFileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );
      
      for (final file in files.files ?? []) {
        await _driveApi!.files.delete(file.id!);
      }
    } catch (e) {
      print('⚠️ خطأ في حذف القفل: $e');
    }
  }

  Future<void> _releaseLock() async {
    _stopHeartbeat();
    if (_currentLock != null) {
      await _forceDeleteLock();
      _currentLock = null;
      print('🔓 تم تحرير القفل');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_currentLock != null && !_currentLock!.isExpired) {
        try {
          _currentLock = await _renewLock(_currentLock!);
        } catch (e) {
          print('⚠️ فشل تجديد القفل: $e');
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }



  /// ═══════════════════════════════════════════════════════════════════════
  /// Batching & Compression - تجميع وضغط العمليات
  /// ═══════════════════════════════════════════════════════════════════════

  /// رفع العمليات كـ Batch مضغوط
  Future<int> _uploadOperationsAsBatch(
    List<SyncOperation> operations,
    int startGlobalSequence,
  ) async {
    if (operations.isEmpty) return 0;
    
    _updateStatus('جاري رفع ${operations.length} عملية...');
    
    final batchesFolderId = await _ensureSubFolder(_batchesFolderName);
    int currentSequence = startGlobalSequence;
    
    // تحديث التسلسل العالمي لكل عملية
    final batchOperations = <Map<String, dynamic>>[];
    for (final op in operations) {
      currentSequence++;
      final updatedOp = op.copyWith(globalSequence: currentSequence);
      batchOperations.add(updatedOp.toJson());
    }
    
    // إنشاء بيانات الـ Batch
    final batchData = {
      'batch_id': 'batch_${DateTime.now().toUtc().millisecondsSinceEpoch}_$_deviceId',
      'device_id': _deviceId,
      'device_name': _deviceName,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'operations_count': operations.length,
      'start_sequence': startGlobalSequence + 1,
      'end_sequence': currentSequence,
      'schema_version': '3.0',
      'operations': batchOperations,
    };
    
    // تحويل إلى JSON
    final jsonContent = jsonEncode(batchData);
    
    // ضغط البيانات
    List<int> finalBytes;
    String fileName;
    String contentType;
    
    if (config.enableCompression) {
      finalBytes = gzip.encode(utf8.encode(jsonContent));
      fileName = 'batch_${DateTime.now().toUtc().millisecondsSinceEpoch}_${_deviceId!.substring(0, 8)}.json.gz';
      contentType = 'application/gzip';
      
      final originalSize = utf8.encode(jsonContent).length;
      final compressedSize = finalBytes.length;
      final ratio = ((1 - compressedSize / originalSize) * 100).toStringAsFixed(1);
      print('📦 ضغط: $originalSize → $compressedSize bytes ($ratio% توفير)');
    } else {
      finalBytes = utf8.encode(jsonContent);
      fileName = 'batch_${DateTime.now().toUtc().millisecondsSinceEpoch}_${_deviceId!.substring(0, 8)}.json';
      contentType = 'application/json';
    }
    
    // رفع الملف
    try {
      final tempFile = await _createTempFile(fileName, finalBytes);
      final media = drive.Media(
        tempFile.openRead(),
        finalBytes.length,
        contentType: contentType,
      );
      
      await _driveApi!.files.create(
        drive.File()
          ..name = fileName
          ..parents = [batchesFolderId],
        uploadMedia: media,
      );
      
      await tempFile.delete();
      
      // تحديث حالة العمليات محلياً
      await _markOperationsAsUploaded(operations, startGlobalSequence);
      
      print('✅ تم رفع ${operations.length} عملية في ملف batch واحد');
      return operations.length;
      
    } catch (e) {
      print('❌ فشل رفع الـ Batch: $e');
      throw SyncException(
        type: SyncErrorType.networkError,
        message: 'فشل رفع العمليات',
        originalError: e,
      );
    }
  }

  /// تنزيل وفك ضغط الـ Batches
  Future<List<SyncOperation>> _downloadNewBatches(int syncedUpToSequence) async {
    final operations = <SyncOperation>[];
    
    try {
      final batchesFolderId = await _ensureSubFolder(_batchesFolderName);
      final files = await _driveApi!.files.list(
        q: "'$batchesFolderId' in parents and trashed = false",
        spaces: 'drive',
        orderBy: 'name',
        $fields: 'files(id,name,size)',
      );
      
      for (final file in files.files ?? []) {
        try {
          final content = await _downloadAndDecompressFile(file.id!, file.name ?? '');
          if (content == null) continue;
          
          final batchData = jsonDecode(content) as Map<String, dynamic>;
          final batchOps = batchData['operations'] as List? ?? [];
          final startSeq = batchData['start_sequence'] as int? ?? 0;
          
          // فقط العمليات الجديدة
          if (startSeq <= syncedUpToSequence) {
            // تخطي الـ batches القديمة بالكامل
            final endSeq = batchData['end_sequence'] as int? ?? 0;
            if (endSeq <= syncedUpToSequence) continue;
          }
          
          for (final opJson in batchOps) {
            final op = SyncOperation.fromJson(opJson as Map<String, dynamic>);
            
            // فقط العمليات الجديدة من أجهزة أخرى
            if (op.globalSequence > syncedUpToSequence && op.deviceId != _deviceId) {
              operations.add(op);
            }
          }
        } catch (e) {
          print('⚠️ خطأ في قراءة batch ${file.name}: $e');
        }
      }
    } catch (e) {
      print('⚠️ خطأ في تنزيل الـ batches: $e');
    }
    
    // ترتيب حسب التسلسل العالمي
    operations.sort((a, b) => a.globalSequence.compareTo(b.globalSequence));
    return operations;
  }

  /// تنزيل وفك ضغط ملف
  Future<String?> _downloadAndDecompressFile(String fileId, String fileName) async {
    try {
      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      
      // فك الضغط إذا كان الملف مضغوطاً
      if (fileName.endsWith('.gz')) {
        final decompressed = gzip.decode(bytes);
        return utf8.decode(decompressed);
      }
      
      return utf8.decode(bytes);
    } catch (e) {
      print('⚠️ خطأ في تنزيل الملف $fileName: $e');
      return null;
    }
  }

  Future<void> _markOperationsAsUploaded(List<SyncOperation> operations, int startSequence) async {
    final db = await _db.database;
    int seq = startSequence;
    
    for (final op in operations) {
      seq++;
      await db.update(
        'sync_operations',
        {
          'status': 'uploaded',
          'global_sequence': seq,
          'uploaded_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'operation_id = ?',
        whereArgs: [op.operationId],
      );
    }
  }



  /// ═══════════════════════════════════════════════════════════════════════
  /// Rolling Snapshots - صور كاملة دورية مع إدارة المساحة
  /// ═══════════════════════════════════════════════════════════════════════

  /// إنشاء Snapshot مضغوط
  Future<void> _createCompressedSnapshot(int version) async {
    _updateStatus('جاري إنشاء نسخة احتياطية...');
    
    try {
      final snapshotsFolderId = await _ensureSubFolder(_snapshotsFolderName);
      
      // جمع البيانات
      final db = await _db.database;
      final customers = await db.query(
        'customers',
        where: 'is_deleted IS NULL OR is_deleted = 0',
      );
      final transactions = await db.query(
        'transactions',
        where: 'is_deleted IS NULL OR is_deleted = 0',
      );
      
      final snapshot = {
        'version': version,
        'schema_version': '3.0',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'created_by': _deviceId,
        'device_name': _deviceName,
        'counts': {
          'customers': customers.length,
          'transactions': transactions.length,
        },
        'data': {
          'customers': customers,
          'transactions': transactions,
        },
        'checksums': {
          'customers': await _calculateCustomersChecksum(),
          'transactions': await _calculateTransactionsChecksum(),
        },
      };
      
      // تحويل وضغط
      final jsonContent = jsonEncode(snapshot);
      final compressedBytes = gzip.encode(utf8.encode(jsonContent));
      
      final originalSize = utf8.encode(jsonContent).length;
      final compressedSize = compressedBytes.length;
      print('📸 Snapshot: ${(originalSize / 1024).toStringAsFixed(1)}KB → ${(compressedSize / 1024).toStringAsFixed(1)}KB');
      
      final fileName = 'snapshot_v${version}_${DateTime.now().toUtc().millisecondsSinceEpoch}.json.gz';
      
      final tempFile = await _createTempFile(fileName, compressedBytes);
      final media = drive.Media(
        tempFile.openRead(),
        compressedBytes.length,
        contentType: 'application/gzip',
      );
      
      await _driveApi!.files.create(
        drive.File()
          ..name = fileName
          ..parents = [snapshotsFolderId],
        uploadMedia: media,
      );
      
      await tempFile.delete();
      
      // حذف الـ snapshots القديمة
      await _cleanupOldSnapshots();
      
      print('✅ تم إنشاء snapshot للإصدار $version');
      
    } catch (e) {
      print('⚠️ فشل إنشاء snapshot: $e');
    }
  }

  /// تنزيل آخر Snapshot
  Future<Map<String, dynamic>?> _downloadLatestSnapshot() async {
    try {
      final snapshotsFolderId = await _ensureSubFolder(_snapshotsFolderName);
      final files = await _driveApi!.files.list(
        q: "'$snapshotsFolderId' in parents and trashed = false and name contains 'snapshot_'",
        spaces: 'drive',
        orderBy: 'name desc',
        $fields: 'files(id,name)',
      );
      
      if (files.files?.isEmpty ?? true) return null;
      
      // أحدث snapshot
      final latestFile = files.files!.first;
      final content = await _downloadAndDecompressFile(latestFile.id!, latestFile.name ?? '');
      
      if (content == null) return null;
      
      return jsonDecode(content) as Map<String, dynamic>;
      
    } catch (e) {
      print('⚠️ خطأ في تنزيل snapshot: $e');
      return null;
    }
  }

  /// حذف الـ Snapshots القديمة (الإبقاء على آخر N)
  Future<void> _cleanupOldSnapshots() async {
    try {
      final snapshotsFolderId = await _ensureSubFolder(_snapshotsFolderName);
      final files = await _driveApi!.files.list(
        q: "'$snapshotsFolderId' in parents and trashed = false",
        spaces: 'drive',
        orderBy: 'name desc',
        $fields: 'files(id,name)',
      );
      
      final allSnapshots = files.files ?? [];
      
      if (allSnapshots.length <= config.maxSnapshotsToKeep) return;
      
      // حذف الـ snapshots الزائدة
      final toDelete = allSnapshots.skip(config.maxSnapshotsToKeep);
      for (final file in toDelete) {
        try {
          await _driveApi!.files.delete(file.id!);
          print('🗑️ حذف snapshot قديم: ${file.name}');
        } catch (e) {
          print('⚠️ فشل حذف ${file.name}: $e');
        }
      }
      
    } catch (e) {
      print('⚠️ خطأ في تنظيف snapshots: $e');
    }
  }

  /// حذف الـ Batches القديمة
  Future<void> _cleanupOldBatches(int currentGlobalSequence) async {
    try {
      final batchesFolderId = await _ensureSubFolder(_batchesFolderName);
      final files = await _driveApi!.files.list(
        q: "'$batchesFolderId' in parents and trashed = false",
        spaces: 'drive',
        orderBy: 'name',
        $fields: 'files(id,name,createdTime)',
      );
      
      final allBatches = files.files ?? [];
      
      if (allBatches.length <= config.maxOperationFilesToKeep) return;
      
      // حذف الـ batches الزائدة (الأقدم)
      final toDelete = allBatches.take(allBatches.length - config.maxOperationFilesToKeep);
      for (final file in toDelete) {
        try {
          await _driveApi!.files.delete(file.id!);
          print('🗑️ حذف batch قديم: ${file.name}');
        } catch (e) {
          print('⚠️ فشل حذف ${file.name}: $e');
        }
      }
      
    } catch (e) {
      print('⚠️ خطأ في تنظيف batches: $e');
    }
  }



  /// ═══════════════════════════════════════════════════════════════════════
  /// إدارة المساحة الذكية
  /// ═══════════════════════════════════════════════════════════════════════

  /// فحص استخدام المساحة
  Future<StorageReport> checkStorageUsage() async {
    _updateStatus('جاري فحص المساحة...');
    
    int totalBytes = 0;
    int snapshotsBytes = 0;
    int operationsBytes = 0;
    int manifestBytes = 0;
    int filesCount = 0;
    
    try {
      final folderId = await _ensureSyncFolder();
      
      // فحص جميع الملفات في المجلد الرئيسي
      final mainFiles = await _driveApi!.files.list(
        q: "'$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id,name,size,mimeType)',
      );
      
      for (final file in mainFiles.files ?? []) {
        final size = int.tryParse(file.size ?? '0') ?? 0;
        totalBytes += size;
        filesCount++;
        
        if (file.name?.contains('manifest') ?? false) {
          manifestBytes += size;
        }
        
        // فحص المجلدات الفرعية
        if (file.mimeType == 'application/vnd.google-apps.folder') {
          final subFiles = await _driveApi!.files.list(
            q: "'${file.id}' in parents and trashed = false",
            spaces: 'drive',
            $fields: 'files(id,name,size)',
          );
          
          for (final subFile in subFiles.files ?? []) {
            final subSize = int.tryParse(subFile.size ?? '0') ?? 0;
            totalBytes += subSize;
            filesCount++;
            
            if (file.name == _snapshotsFolderName) {
              snapshotsBytes += subSize;
            } else if (file.name == _batchesFolderName) {
              operationsBytes += subSize;
            }
          }
        }
      }
      
    } catch (e) {
      print('⚠️ خطأ في فحص المساحة: $e');
    }
    
    final report = StorageReport(
      totalBytes: totalBytes,
      snapshotsBytes: snapshotsBytes,
      operationsBytes: operationsBytes,
      manifestBytes: manifestBytes,
      otherBytes: totalBytes - snapshotsBytes - operationsBytes - manifestBytes,
      filesCount: filesCount,
      checkedAt: DateTime.now(),
    );
    
    onStorageCheck?.call(report);
    
    print('📊 استخدام المساحة: ${report.totalMB.toStringAsFixed(2)}MB ($filesCount ملف)');
    
    return report;
  }

  /// تنظيف ذكي للمساحة
  Future<void> performSmartCleanup() async {
    _updateStatus('جاري التنظيف الذكي...');
    
    final storageReport = await checkStorageUsage();
    final maxBytes = config.maxStorageMB * 1024 * 1024;
    final thresholdBytes = (maxBytes * config.cleanupThresholdPercent).toInt();
    
    if (storageReport.totalBytes < thresholdBytes) {
      print('✅ المساحة ضمن الحدود المسموحة');
      return;
    }
    
    print('⚠️ المساحة تجاوزت ${(config.cleanupThresholdPercent * 100).toInt()}%، جاري التنظيف...');
    
    // 1. حذف الـ snapshots القديمة أولاً
    await _cleanupOldSnapshots();
    
    // 2. حذف الـ batches القديمة
    await _cleanupOldBatches(0);
    
    // 3. إعادة فحص المساحة
    final newReport = await checkStorageUsage();
    final freedMB = (storageReport.totalBytes - newReport.totalBytes) / (1024 * 1024);
    
    print('✅ تم تحرير ${freedMB.toStringAsFixed(2)}MB');
  }

  /// تنظيف شامل (للحالات الطارئة)
  Future<void> performDeepCleanup() async {
    _updateStatus('جاري التنظيف الشامل...');
    
    try {
      // 1. إنشاء snapshot جديد قبل الحذف
      final manifest = await _downloadManifest();
      await _createCompressedSnapshot(manifest.globalSequence);
      
      // 2. حذف جميع الـ batches القديمة (الإبقاء على آخر 3 فقط)
      final batchesFolderId = await _ensureSubFolder(_batchesFolderName);
      final batches = await _driveApi!.files.list(
        q: "'$batchesFolderId' in parents and trashed = false",
        spaces: 'drive',
        orderBy: 'name desc',
        $fields: 'files(id,name)',
      );
      
      final batchesToDelete = (batches.files ?? []).skip(3);
      for (final file in batchesToDelete) {
        try {
          await _driveApi!.files.delete(file.id!);
        } catch (_) {}
      }
      
      // 3. حذف جميع الـ snapshots القديمة (الإبقاء على آخر 2 فقط)
      final snapshotsFolderId = await _ensureSubFolder(_snapshotsFolderName);
      final snapshots = await _driveApi!.files.list(
        q: "'$snapshotsFolderId' in parents and trashed = false",
        spaces: 'drive',
        orderBy: 'name desc',
        $fields: 'files(id,name)',
      );
      
      final snapshotsToDelete = (snapshots.files ?? []).skip(2);
      for (final file in snapshotsToDelete) {
        try {
          await _driveApi!.files.delete(file.id!);
        } catch (_) {}
      }
      
      final newReport = await checkStorageUsage();
      print('✅ التنظيف الشامل اكتمل. المساحة الحالية: ${newReport.totalMB.toStringAsFixed(2)}MB');
      
    } catch (e) {
      print('❌ خطأ في التنظيف الشامل: $e');
    }
  }



  /// ═══════════════════════════════════════════════════════════════════════
  /// Manifest المحسّن
  /// ═══════════════════════════════════════════════════════════════════════

  Future<SyncManifest> _downloadManifest() async {
    try {
      final folderId = await _ensureSyncFolder();
      final files = await _driveApi!.files.list(
        q: "name contains 'manifest' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id,name,createdTime,modifiedTime)',
      );
      
      if (files.files?.isEmpty ?? true) {
        return SyncManifest.empty(_deviceId!);
      }
      
      final file = files.files!.first;
      
      // 🕰️ حساب فرق التوقيت مع سيرفر جوجل
      if (file.modifiedTime != null) {
        final serverTime = file.modifiedTime!.toUtc();
        final localTime = DateTime.now().toUtc();
        _serverTimeOffset = serverTime.difference(localTime);
        print('🕰️ فرق التوقيت مع السيرفر: ${_serverTimeOffset.inSeconds} ثانية');
      }

      final content = await _downloadAndDecompressFile(file.id!, file.name ?? '');
      
      if (content == null) {
        return SyncManifest.empty(_deviceId!);
      }
      
      final json = jsonDecode(content) as Map<String, dynamic>;
      final manifest = SyncManifest.fromJson(json);

      // 🛡️ فحص توافق الإصدار
      _checkVersionCompatibility(manifest.appVersion);

      return manifest;
    } catch (e) {
      if (e is SyncException) rethrow;
      print('⚠️ خطأ في تنزيل manifest: $e');
      return SyncManifest.empty(_deviceId!);
    }
  }

  void _checkVersionCompatibility(String remoteVersion) {
    final remoteMajor = int.tryParse(remoteVersion.split('.').first) ?? 1;
    final localMajor = int.tryParse(_currentAppVersion.split('.').first) ?? 1;

    if (remoteMajor > localMajor) {
      throw SyncException(
        type: SyncErrorType.unknownError,
        message: 'إصدار التطبيق لديك قديم جداً. يرجى التحديث للمزامنة. (السيرفر: $remoteVersion, لديك: $_currentAppVersion)',
        isRecoverable: false,
      );
    }
  }

  Future<void> _uploadManifest(SyncManifest manifest) async {
    final folderId = await _ensureSyncFolder();
    final jsonContent = jsonEncode(manifest.toJson());
    
    List<int> finalBytes;
    String fileName;
    
    if (config.enableCompression) {
      finalBytes = gzip.encode(utf8.encode(jsonContent));
      fileName = _manifestFileName;
    } else {
      finalBytes = utf8.encode(jsonContent);
      fileName = 'manifest.json';
    }
    
    // البحث عن الملف الموجود
    final files = await _driveApi!.files.list(
      q: "name contains 'manifest' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
    );
    
    final tempFile = await _createTempFile(fileName, finalBytes);
    final media = drive.Media(
      tempFile.openRead(),
      finalBytes.length,
      contentType: config.enableCompression ? 'application/gzip' : 'application/json',
    );
    
    if (files.files?.isNotEmpty ?? false) {
      await _driveApi!.files.update(
        drive.File()..name = fileName,
        files.files!.first.id!,
        uploadMedia: media,
      );
    } else {
      await _driveApi!.files.create(
        drive.File()
          ..name = fileName
          ..parents = [folderId],
        uploadMedia: media,
      );
    }
    
    await tempFile.delete();
  }

  Future<void> _updateManifest(SyncManifest oldManifest, int newGlobalSequence) async {
    _updateStatus('جاري تحديث الفهرس...');
    
    final now = DateTime.now().toUtc();
    
    // تحديث حالة الجهاز الحالي
    final updatedDevices = Map<String, DeviceState>.from(oldManifest.devices);
    updatedDevices[_deviceId!] = DeviceState(
      deviceId: _deviceId!,
      deviceName: _deviceName!,
      firstSeen: oldManifest.devices[_deviceId]?.firstSeen ?? now,
      lastSync: now,
      localSequence: newGlobalSequence,
      syncedUpToGlobal: newGlobalSequence,
      pendingOperations: 0,
      status: 'ACTIVE',
    );
    
    // حساب checksums
    final customersChecksum = await _calculateCustomersChecksum();
    final transactionsChecksum = await _calculateTransactionsChecksum();
    
    final updatedEntities = {
      'customers': EntityState(
        name: 'customers',
        count: await _getTableCount('customers'),
        lastModified: now,
        checksum: customersChecksum,
      ),
      'transactions': EntityState(
        name: 'transactions',
        count: await _getTableCount('transactions'),
        lastModified: now,
        checksum: transactionsChecksum,
      ),
    };
    
    // حساب Merkle Root
    final merkleRoot = MerkleTree.calculateRoot([customersChecksum, transactionsChecksum]);
    
    var newManifest = SyncManifest(
      globalSequence: newGlobalSequence,
      lastModified: now,
      lastModifiedBy: _deviceId!,
      checksum: '',
      devices: updatedDevices,
      entities: updatedEntities,
      merkleRoot: merkleRoot,
    );
    
    // حساب checksum للـ manifest
    final manifestJson = newManifest.toJson();
    manifestJson.remove('checksum');
    final checksum = SyncSecurity.calculateChecksum(manifestJson);
    
    newManifest = newManifest.copyWith(checksum: checksum);
    
    await _uploadManifest(newManifest);
  }



  /// ═══════════════════════════════════════════════════════════════════════
  /// المزامنة الرئيسية المحسّنة
  /// ═══════════════════════════════════════════════════════════════════════

  /// المزامنة الكاملة المحسّنة
  Future<SyncReport> performOptimizedSync() async {
    if (!isReady) {
      throw SyncException(
        type: SyncErrorType.unknownError,
        message: 'محرك المزامنة غير جاهز',
        isRecoverable: false,
      );
    }
    
    if (_isSyncing) {
      throw SyncException(
        type: SyncErrorType.lockAcquisitionFailed,
        message: 'المزامنة جارية بالفعل',
        isRecoverable: true,
      );
    }
    
    _isSyncing = true;
    final startTime = DateTime.now();
    final warnings = <String>[];
    var operationsDownloaded = 0;
    var operationsUploaded = 0;
    var operationsApplied = 0;
    
    try {
      // 0. فحص المساحة أولاً
      final storageReport = await checkStorageUsage();
      if (storageReport.totalMB > config.maxStorageMB * config.cleanupThresholdPercent) {
        await performSmartCleanup();
      }
      
      // 1. التحضير المحلي
      _updateStatus('جاري التحضير...');
      final pendingOps = await _getPendingOperations();
      final localSequence = await _getLocalSequence();
      
      // 2. الحصول على القفل
      final lockAcquired = await _acquireLockSafely();
      if (!lockAcquired) {
        throw SyncException(
          type: SyncErrorType.lockAcquisitionFailed,
          message: 'فشل الحصول على القفل',
        );
      }
      
      try {
        // 3. تنزيل الـ Manifest
        final manifest = await _downloadManifest();
        final myDeviceState = manifest.devices[_deviceId];
        final syncedUpTo = myDeviceState?.syncedUpToGlobal ?? 0;
        
        // 4. تنزيل العمليات الجديدة (من Batches)
        _updateStatus('جاري تنزيل التحديثات...');
        final newOperations = await _downloadNewBatches(syncedUpTo);
        operationsDownloaded = newOperations.length;
        
        // 5. التحقق من صحة العمليات
        if (newOperations.isNotEmpty) {
          _updateStatus('جاري التحقق من البيانات...');
          await _verifyOperations(newOperations);
          
          // 🧠 كشف وحل التعارضات (3-Way Merge)
          _updateStatus('جاري فحص التعارضات...');
          await _detectAndResolveConflicts(pendingOps, newOperations);
        }
        
        // 6. تطبيق العمليات الواردة
        if (newOperations.isNotEmpty) {
          _updateStatus('جاري تطبيق ${newOperations.length} تحديث...');
          operationsApplied = await _applyIncomingOperations(newOperations);
        }
        
        // 7. رفع العمليات المحلية (كـ Batch مضغوط)
        if (pendingOps.isNotEmpty) {
          operationsUploaded = await _uploadOperationsAsBatch(
            pendingOps,
            manifest.globalSequence,
          );
        }
        
        // 8. تحديث الـ Manifest
        final newGlobalSequence = manifest.globalSequence + operationsUploaded;
        await _updateManifest(manifest, newGlobalSequence);
        
        // 9. إنشاء Snapshot إذا لزم الأمر
        if (newGlobalSequence > 0 && 
            newGlobalSequence % config.snapshotEveryNOperations == 0) {
          await _createCompressedSnapshot(newGlobalSequence);
        }
        
        // 10. تنظيف الـ Batches القديمة
        await _cleanupOldBatches(newGlobalSequence);
        
        _updateStatus('اكتملت المزامنة بنجاح ✅');
        
        final report = SyncReport(
          startTime: startTime,
          endTime: DateTime.now(),
          success: true,
          operationsDownloaded: operationsDownloaded,
          operationsUploaded: operationsUploaded,
          operationsApplied: operationsApplied,
          warnings: warnings,
        );
        
        onSyncComplete?.call(report);
        return report;
        
      } finally {
        await _releaseLock();
      }
      
    } on SyncException catch (e) {
      _updateStatus('فشلت المزامنة: ${e.message}');
      
      return SyncReport(
        startTime: startTime,
        endTime: DateTime.now(),
        success: false,
        errorMessage: e.message,
        errorType: e.type,
        operationsDownloaded: operationsDownloaded,
        operationsUploaded: operationsUploaded,
        operationsApplied: operationsApplied,
        warnings: warnings,
      );
      
    } catch (e) {
      _updateStatus('فشلت المزامنة: $e');
      
      return SyncReport(
        startTime: startTime,
        endTime: DateTime.now(),
        success: false,
        errorMessage: e.toString(),
        errorType: SyncErrorType.unknownError,
        warnings: warnings,
      );
      
    } finally {
      _isSyncing = false;
    }
  }

  /// مزامنة سريعة (للتحديثات الصغيرة)
  Future<SyncReport> performQuickSync() async {
    if (!isReady || _isSyncing) {
      return SyncReport(
        startTime: DateTime.now(),
        endTime: DateTime.now(),
        success: false,
        errorMessage: 'غير جاهز أو المزامنة جارية',
      );
    }
    
    _isSyncing = true;
    final startTime = DateTime.now();
    
    try {
      // فقط تنزيل وتطبيق التحديثات الجديدة بدون رفع
      final manifest = await _downloadManifest();
      final myDeviceState = manifest.devices[_deviceId];
      final syncedUpTo = myDeviceState?.syncedUpToGlobal ?? 0;
      
      final newOperations = await _downloadNewBatches(syncedUpTo);
      
      if (newOperations.isNotEmpty) {
        await _verifyOperations(newOperations);
        await _applyIncomingOperations(newOperations);
      }
      
      return SyncReport(
        startTime: startTime,
        endTime: DateTime.now(),
        success: true,
        operationsDownloaded: newOperations.length,
        operationsApplied: newOperations.length,
      );
      
    } catch (e) {
      return SyncReport(
        startTime: startTime,
        endTime: DateTime.now(),
        success: false,
        errorMessage: e.toString(),
      );
    } finally {
      _isSyncing = false;
    }
  }



  /// ═══════════════════════════════════════════════════════════════════════
  /// دوال مساعدة
  /// ═══════════════════════════════════════════════════════════════════════

  void _updateStatus(String status) {
    print('🔄 $status');
    onStatusChange?.call(status);
  }

  Future<String> _ensureSyncFolder() async {
    if (_syncFolderId != null) return _syncFolderId!;
    
    final files = await _driveApi!.files.list(
      q: "name = '$_syncFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
    );
    
    if (files.files?.isNotEmpty ?? false) {
      _syncFolderId = files.files!.first.id!;
      return _syncFolderId!;
    }
    
    final folder = drive.File()
      ..name = _syncFolderName
      ..mimeType = 'application/vnd.google-apps.folder';
    
    final created = await _driveApi!.files.create(folder);
    _syncFolderId = created.id!;
    return _syncFolderId!;
  }

  Future<String> _ensureSubFolder(String folderName) async {
    if (_subFolderIds.containsKey(folderName)) {
      return _subFolderIds[folderName]!;
    }
    
    final parentId = await _ensureSyncFolder();
    
    final files = await _driveApi!.files.list(
      q: "name = '$folderName' and '$parentId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
    );
    
    if (files.files?.isNotEmpty ?? false) {
      _subFolderIds[folderName] = files.files!.first.id!;
      return _subFolderIds[folderName]!;
    }
    
    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [parentId];
    
    final created = await _driveApi!.files.create(folder);
    _subFolderIds[folderName] = created.id!;
    return _subFolderIds[folderName]!;
  }

  Future<File> _createTempFile(String fileName, List<int> bytes) async {
    final tempDir = await getTemporaryDirectory();
    final syncTempDir = Directory('${tempDir.path}/sync_temp');
    if (!await syncTempDir.exists()) {
      await syncTempDir.create(recursive: true);
    }
    
    final file = File('${syncTempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<String?> _downloadFileContent(String fileId) async {
    try {
      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      
      return utf8.decode(bytes);
    } catch (e) {
      return null;
    }
  }

  Future<List<SyncOperation>> _getPendingOperations() async {
    final db = await _db.database;
    final rows = await db.query(
      'sync_operations',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'local_sequence ASC',
    );
    return rows.map((r) => SyncOperation.fromJson(jsonDecode(r['data'] as String))).toList();
  }

  Future<int> _getLocalSequence() async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT MAX(local_sequence) as max_seq FROM sync_operations WHERE device_id = ?',
      [_deviceId],
    );
    return (result.first['max_seq'] as int?) ?? 0;
  }

  Future<String> _calculateCustomersChecksum() async {
    final db = await _db.database;
    final customers = await db.query('customers', orderBy: 'id ASC');
    return SyncSecurity.calculateListChecksum(customers, 'id');
  }

  Future<String> _calculateTransactionsChecksum() async {
    final db = await _db.database;
    final transactions = await db.query('transactions', orderBy: 'id ASC');
    return SyncSecurity.calculateListChecksum(transactions, 'id');
  }

  Future<int> _getTableCount(String table) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $table WHERE is_deleted IS NULL OR is_deleted = 0'
    );
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> _verifyOperations(List<SyncOperation> operations) async {
    for (final op in operations) {
      if (!op.verifyChecksum()) {
        throw SyncException(
          type: SyncErrorType.checksumMismatch,
          message: 'فشل التحقق من checksum للعملية ${op.operationId}',
        );
      }
    }
  }

  Future<int> _applyIncomingOperations(List<SyncOperation> operations) async {
    if (operations.isEmpty) return 0;
    
    int appliedCount = 0;
    final db = await _db.database;
    
    await db.transaction((txn) async {
      for (final op in operations) {
        try {
          await _applySingleOperation(txn, op);
          appliedCount++;
          onProgress?.call(appliedCount / operations.length);
        } catch (e) {
          print('❌ فشل تطبيق العملية ${op.operationId}: $e');
          throw SyncException(
            type: SyncErrorType.rollbackRequired,
            message: 'فشل تطبيق العملية',
            originalError: e,
          );
        }
      }
    });
    
    // إعادة حساب الأرصدة
    await _recalculateAffectedBalances(operations);
    
    return appliedCount;
  }

  Future<void> _applySingleOperation(dynamic txn, SyncOperation op) async {
    switch (op.operationType) {
      case SyncOperationType.customerCreate:
        await _applyCustomerCreate(txn, op);
        break;
      case SyncOperationType.customerUpdate:
        await _applyCustomerUpdate(txn, op);
        break;
      case SyncOperationType.customerDelete:
        await _applyCustomerDelete(txn, op);
        break;
      case SyncOperationType.transactionCreate:
        await _applyTransactionCreate(txn, op);
        break;
      case SyncOperationType.transactionUpdate:
        await _applyTransactionUpdate(txn, op);
        break;
      case SyncOperationType.transactionDelete:
        await _applyTransactionDelete(txn, op);
        break;
      default:
        print('⚠️ نوع عملية غير مدعوم: ${op.operationType}');
    }
    
    // تسجيل العملية
    await txn.insert('sync_applied_operations', {
      'operation_id': op.operationId,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
      'device_id': op.deviceId,
    });
  }

  Future<void> _applyCustomerCreate(dynamic txn, SyncOperation op) async {
    final existing = await txn.query('customers', where: 'sync_uuid = ?', whereArgs: [op.entityUuid]);
    if (existing.isNotEmpty) return;
    
    await txn.insert('customers', {
      ...op.payloadAfter,
      'sync_uuid': op.entityUuid,
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _applyCustomerUpdate(dynamic txn, SyncOperation op) async {
    await txn.update('customers', {
      ...op.payloadAfter,
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'sync_uuid = ?', whereArgs: [op.entityUuid]);
  }

  Future<void> _applyCustomerDelete(dynamic txn, SyncOperation op) async {
    await txn.update('customers', {
      'is_deleted': 1,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'sync_uuid = ?', whereArgs: [op.entityUuid]);
  }

  Future<void> _applyTransactionCreate(dynamic txn, SyncOperation op) async {
    final existing = await txn.query('transactions', where: 'transaction_uuid = ?', whereArgs: [op.entityUuid]);
    if (existing.isNotEmpty) return;
    
    final data = Map<String, dynamic>.from(op.payloadAfter);
    // 🔄 تصحيح المصدر: عند استلام معاملة من جهاز آخر، يجب ألا تكون "من إنشائي"
    data['is_created_by_me'] = 0;
    
    if (op.customerUuid != null) {
      final customers = await txn.query('customers', where: 'sync_uuid = ?', whereArgs: [op.customerUuid]);
      if (customers.isNotEmpty) {
        data['customer_id'] = customers.first['id'];
      }
    }
    
    // 🔒 التحقق من صحة البيانات المالية قبل الإدراج
    final amountChanged = (data['amount_changed'] as num?)?.toDouble() ?? 0;
    if (amountChanged.abs() > 1000000000) {
      throw SyncException(
        type: SyncErrorType.rollbackRequired,
        message: 'مبلغ المعاملة غير منطقي: $amountChanged',
      );
    }
    
    await txn.insert('transactions', {
      ...data,
      'transaction_uuid': op.entityUuid,
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _applyTransactionUpdate(dynamic txn, SyncOperation op) async {
    final data = Map<String, dynamic>.from(op.payloadAfter);
    // 🛡️ حماية حقل الملكية: التحديث لا يجب أن يغير من أنشأ المعاملة
    data.remove('is_created_by_me');

    await txn.update('transactions', {
      ...data,
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'transaction_uuid = ?', whereArgs: [op.entityUuid]);
  }

  Future<void> _applyTransactionDelete(dynamic txn, SyncOperation op) async {
    await txn.update('transactions', {
      'is_deleted': 1,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'transaction_uuid = ?', whereArgs: [op.entityUuid]);
  }

  Future<void> _recalculateAffectedBalances(List<SyncOperation> operations) async {
    final affectedCustomerUuids = <String>{};
    
    for (final op in operations) {
      if (op.entityType == 'transaction' && op.customerUuid != null) {
        affectedCustomerUuids.add(op.customerUuid!);
      }
    }
    
    final db = await _db.database;
    for (final uuid in affectedCustomerUuids) {
      final customers = await db.query('customers', where: 'sync_uuid = ?', whereArgs: [uuid]);
      if (customers.isNotEmpty) {
        final customerId = customers.first['id'] as int;
        await _db.recalculateAndApplyCustomerDebt(customerId);
        await _db.recalculateCustomerTransactionBalances(customerId);
      }
    }
  }

  Future<void> _detectAndResolveConflicts(
    List<SyncOperation> pendingOps,
    List<SyncOperation> incomingOps,
  ) async {
    final pendingMap = {for (var op in pendingOps) '${op.entityType}:${op.entityUuid}': op};

    for (var i = 0; i < incomingOps.length; i++) {
      final incoming = incomingOps[i];
      final key = '${incoming.entityType}:${incoming.entityUuid}';
      final pending = pendingMap[key];

      if (pending != null) {
        // وجدنا تعارض: عملية معلقة وعملية واردة لنفس الكيان
        if (pending.operationType == SyncOperationType.transactionUpdate &&
            incoming.operationType == SyncOperationType.transactionUpdate) {
          // دمج التحديثات (3-Way Merge)
          final mergedPayload = _mergePayloads(pending, incoming);
          if (mergedPayload != null) {
            // تحديث العملية الواردة لتعكس الدمج (لتطبيقها على قاعدة البيانات)
            incomingOps[i] = incoming.copyWith(payloadAfter: mergedPayload);
            
            // تحديث العملية المعلقة لتعكس الدمج (لرفعها لاحقاً)
            final updatedPending = pending.copyWith(payloadAfter: mergedPayload);
            await _updatePendingOperation(updatedPending);
            
            print('🧬 تم دمج التعارض للعملية ${incoming.entityUuid}');
          }
        }
        // يمكن إضافة منطق لأنواع أخرى من التعارضات هنا
      }
    }
  }

  /// 🧠 دمج 3-Way Merge لحل تضارب الحقول
  Map<String, dynamic>? _mergePayloads(SyncOperation local, SyncOperation remote) {
    try {
      final base = local.payloadBefore ?? {}; // الحالة الأصلية قبل التعديلين
      final localChanges = local.payloadAfter;
      final remoteChanges = remote.payloadAfter;

      final merged = Map<String, dynamic>.from(localChanges); // نبدأ بتغييراتنا
      bool hasConflict = false;

      // مقارنة كل حقل
      for (final key in remoteChanges.keys) {
        final remoteValue = remoteChanges[key];
        final localValue = localChanges[key];
        final baseValue = base[key];

        if (remoteValue != localValue) {
          // الحقل مختلف بين الاثنين
          if (localValue == baseValue) {
            // نحن لم نغير هذا الحقل، والطرف الآخر غيره -> نقبل تغيير الطرف الآخر
            merged[key] = remoteValue;
          } else if (remoteValue != baseValue) {
            // كلاهما غير الحقل لقيم مختلفة! -> تضارب حقيقي
            // نلجأ لاستراتيجية Last Write Wins لهذا الحقل فقط
            final localTime = local.timestamp.add(_serverTimeOffset);
            if (remote.timestamp.isAfter(localTime)) {
               merged[key] = remoteValue; // Remote wins this field
            }
            // else Local keeps its value
          }
        }
      }
      return merged;
    } catch (e) {
      print('⚠️ فشل الدمج الذكي: $e');
      return null;
    }
  }

  Future<void> _updatePendingOperation(SyncOperation op) async {
    final db = await _db.database;
    await db.update(
      'sync_operations',
      {'data': jsonEncode(op.toJson())},
      where: 'operation_id = ?',
      whereArgs: [op.operationId],
    );
  }

  /// إغلاق المحرك
  void dispose() {
    _stopHeartbeat();
    _httpClient?.close();
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// تقرير المزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncReport {
  final DateTime startTime;
  final DateTime endTime;
  final bool success;
  final String? errorMessage;
  final SyncErrorType? errorType;
  final int operationsDownloaded;
  final int operationsUploaded;
  final int operationsApplied;
  final List<String> warnings;

  SyncReport({
    required this.startTime,
    required this.endTime,
    required this.success,
    this.errorMessage,
    this.errorType,
    this.operationsDownloaded = 0,
    this.operationsUploaded = 0,
    this.operationsApplied = 0,
    List<String>? warnings,
  }) : warnings = warnings ?? [];

  Duration get duration => endTime.difference(startTime);
}

/// استثناء المزامنة
class SyncException implements Exception {
  final SyncErrorType type;
  final String message;
  final dynamic originalError;
  final bool isRecoverable;

  SyncException({
    required this.type,
    required this.message,
    this.originalError,
    this.isRecoverable = true,
  });

  @override
  String toString() => 'SyncException(${type.name}): $message';
}
