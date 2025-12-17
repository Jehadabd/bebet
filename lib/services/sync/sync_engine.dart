// lib/services/sync/sync_engine.dart
// محرك المزامنة الرئيسي - الجزء الأول

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
  final int conflictsDetected;
  final int conflictsResolved;
  
  final String? localChecksum;
  final String? remoteChecksum;
  final bool checksumsMatch;
  
  final List<String> warnings;
  final List<SyncConflict> unresolvedConflicts;

  SyncReport({
    required this.startTime,
    required this.endTime,
    required this.success,
    this.errorMessage,
    this.errorType,
    this.operationsDownloaded = 0,
    this.operationsUploaded = 0,
    this.operationsApplied = 0,
    this.conflictsDetected = 0,
    this.conflictsResolved = 0,
    this.localChecksum,
    this.remoteChecksum,
    this.checksumsMatch = true,
    List<String>? warnings,
    List<SyncConflict>? unresolvedConflicts,
  }) : warnings = warnings ?? [],
       unresolvedConflicts = unresolvedConflicts ?? [];

  Duration get duration => endTime.difference(startTime);
  
  Map<String, dynamic> toJson() => {
    'start_time': startTime.toIso8601String(),
    'end_time': endTime.toIso8601String(),
    'duration_ms': duration.inMilliseconds,
    'success': success,
    if (errorMessage != null) 'error_message': errorMessage,
    if (errorType != null) 'error_type': errorType!.name,
    'operations_downloaded': operationsDownloaded,
    'operations_uploaded': operationsUploaded,
    'operations_applied': operationsApplied,
    'conflicts_detected': conflictsDetected,
    'conflicts_resolved': conflictsResolved,
    'checksums_match': checksumsMatch,
    'warnings': warnings,
  };
}

/// ═══════════════════════════════════════════════════════════════════════════
/// استثناء المزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncException implements Exception {
  final SyncErrorType type;
  final String message;
  final Map<String, dynamic>? details;
  final bool isRecoverable;
  final dynamic originalError;

  SyncException({
    required this.type,
    required this.message,
    this.details,
    this.isRecoverable = true,
    this.originalError,
  });

  @override
  String toString() => 'SyncException(${type.name}): $message';
}

/// ═══════════════════════════════════════════════════════════════════════════
/// إعدادات المزامنة
/// ═══════════════════════════════════════════════════════════════════════════
class SyncConfig {
  final Duration lockTimeout;
  final Duration lockRetryInterval;
  final int maxLockRetries;
  final Duration heartbeatInterval;
  final int snapshotEveryNOperations;
  final int keepOperationsDays;
  final bool autoResolveConflicts;
  final String conflictResolutionStrategy; // LAST_WRITE_WINS, FIRST_WRITE_WINS, ASK_USER
  
  const SyncConfig({
    this.lockTimeout = const Duration(minutes: 3),
    this.lockRetryInterval = const Duration(seconds: 10),
    this.maxLockRetries = 5,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.snapshotEveryNOperations = 100,
    this.keepOperationsDays = 30,
    this.autoResolveConflicts = true,
    this.conflictResolutionStrategy = 'LAST_WRITE_WINS',
  });
}


/// ═══════════════════════════════════════════════════════════════════════════
/// محرك المزامنة الرئيسي
/// ═══════════════════════════════════════════════════════════════════════════
class SyncEngine {
  final SyncConfig config;
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
  
  // Callbacks
  Function(String)? onStatusChange;
  Function(double)? onProgress;
  Function(SyncReport)? onSyncComplete;
  Function(SyncConflict)? onConflictDetected;
  
  // Drive API client (يتم تمريره من DriveService)
  http.Client? _httpClient;
  drive.DriveApi? _driveApi;
  String? _syncFolderId;
  
  static const String _syncFolderName = 'DebtBook_Sync_v2';
  static const String _lockFileName = '.lock';
  static const String _manifestFileName = 'manifest.json';
  static const String _devicesFolderName = 'devices';
  static const String _operationsFolderName = 'operations';
  static const String _snapshotsFolderName = 'snapshots';
  static const String _conflictsFolderName = 'conflicts';

  SyncEngine({
    this.config = const SyncConfig(),
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
    _deviceName = deviceName ?? 'Unknown Device';
    _secretKey = await SyncSecurity.getOrCreateSecretKey();
    
    // لا نحفظ الـ deviceId هنا - يتم حفظه في SyncSecurity.getOrCreateDeviceId()
    
    print('🔄 SyncEngine initialized for device: $_deviceId');
  }

  /// هل المحرك جاهز؟
  bool get isReady => _driveApi != null && _deviceId != null && _secretKey != null;
  
  /// هل المزامنة جارية؟
  bool get isSyncing => _isSyncing;


  /// ═══════════════════════════════════════════════════════════════════════
  /// المرحلة 0: التحضير المحلي
  /// ═══════════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _prepareLocalState() async {
    _updateStatus('جاري التحضير المحلي...');
    
    // 1. إنشاء نسخة احتياطية محلية
    final backupPath = await _createLocalBackup();
    
    // 2. حساب checksums لجميع الجداول
    final customersChecksum = await _calculateCustomersChecksum();
    final transactionsChecksum = await _calculateTransactionsChecksum();
    
    // 3. جمع العمليات المعلقة
    final pendingOperations = await _getPendingOperations();
    
    // 4. الحصول على آخر تسلسل محلي
    final localSequence = await _getLocalSequence();
    
    return {
      'backup_path': backupPath,
      'checksums': {
        'customers': customersChecksum,
        'transactions': transactionsChecksum,
      },
      'pending_operations': pendingOperations,
      'local_sequence': localSequence,
    };
  }

  Future<String> _createLocalBackup() async {
    final supportDir = await getApplicationSupportDirectory();
    final backupDir = Directory('${supportDir.path}/sync_backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupPath = '${backupDir.path}/backup_$timestamp.db';
    
    final dbFile = await _db.getDatabaseFile();
    if (await dbFile.exists()) {
      await dbFile.copy(backupPath);
    }
    
    // حذف النسخ القديمة (الإبقاء على آخر 5)
    final backups = await backupDir.list().toList();
    if (backups.length > 5) {
      backups.sort((a, b) => a.path.compareTo(b.path));
      for (int i = 0; i < backups.length - 5; i++) {
        try { await backups[i].delete(); } catch (_) {}
      }
    }
    
    return backupPath;
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


  /// ═══════════════════════════════════════════════════════════════════════
  /// المرحلة 1: الحصول على القفل
  /// ═══════════════════════════════════════════════════════════════════════
  Future<bool> _acquireLock() async {
    _updateStatus('جاري الحصول على القفل...');
    
    for (int attempt = 1; attempt <= config.maxLockRetries; attempt++) {
      try {
        // قراءة القفل الحالي
        final existingLock = await _readLock();
        
        if (existingLock != null) {
          if (existingLock.isExpired) {
            // القفل منتهي الصلاحية، نحذفه
            print('🔓 القفل منتهي الصلاحية، جاري الحذف...');
            await _deleteLock();
          } else if (existingLock.deviceId == _deviceId) {
            // القفل لنا، نجدده
            print('🔄 تجديد القفل الحالي...');
            _currentLock = await _renewLock(existingLock);
            _startHeartbeat();
            return true;
          } else {
            // القفل لجهاز آخر
            print('⏳ القفل مشغول بواسطة ${existingLock.deviceName}، انتظار...');
            _updateStatus('القفل مشغول بواسطة ${existingLock.deviceName}، محاولة $attempt من ${config.maxLockRetries}');
            await Future.delayed(config.lockRetryInterval);
            continue;
          }
        }
        
        // إنشاء قفل جديد
        final newLock = await _createLock();
        
        // التحقق من نجاح إنشاء القفل (قراءة وتأكيد)
        await Future.delayed(const Duration(milliseconds: 500));
        final verifyLock = await _readLock();
        
        if (verifyLock != null && verifyLock.lockId == newLock.lockId) {
          _currentLock = newLock;
          _startHeartbeat();
          print('🔒 تم الحصول على القفل بنجاح');
          return true;
        } else {
          print('⚠️ فشل التحقق من القفل، إعادة المحاولة...');
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
      
      await Future.delayed(config.lockRetryInterval);
    }
    
    return false;
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
      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return SyncLock.fromJson(json);
    } catch (e) {
      print('⚠️ خطأ في قراءة القفل: $e');
      return null;
    }
  }

  /// إنشاء قفل مع التحقق بعد الكتابة (Verify-After-Write)
  /// هذا يحل مشكلة Race Condition في Google Drive
  Future<SyncLock> _createLock() async {
    final now = DateTime.now().toUtc();
    final lockId = SyncSecurity.generateLockId(_deviceId!);
    
    final lock = SyncLock(
      lockId: lockId,
      deviceId: _deviceId!,
      deviceName: _deviceName!,
      acquiredAt: now,
      expiresAt: now.add(config.lockTimeout),
      operationType: 'FULL_SYNC',
      heartbeat: now,
      signature: SyncSecurity.signData('${_deviceId!}|${now.toIso8601String()}', _secretKey!),
    );
    
    // 1. رفع ملف القفل
    await _writeLock(lock);
    
    // 2. انتظار فترة عشوائية (200-500ms) لتجنب Race Condition
    final randomDelay = 200 + (DateTime.now().millisecond % 300);
    await Future.delayed(Duration(milliseconds: randomDelay));
    
    // 3. التحقق من أن ملفنا هو الوحيد (Verify-After-Write)
    final folderId = await _ensureSyncFolder();
    final allLocks = await _driveApi!.files.list(
      q: "name contains '.lock' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
      orderBy: 'createdTime',
    );
    
    // 4. إذا وجدنا أكثر من ملف قفل، نتحقق من الأقدم
    if ((allLocks.files?.length ?? 0) > 1) {
      // الملف الأقدم يفوز
      final oldestLock = allLocks.files!.first;
      
      // قراءة محتوى أقدم قفل
      final oldestLockData = await _readLockFile(oldestLock.id!);
      
      if (oldestLockData != null && oldestLockData.lockId != lockId) {
        // ملف آخر أقدم، نحذف ملفنا وننسحب
        print('⚠️ Race Condition detected! Another device got the lock first.');
        await _deleteLock();
        throw SyncException(
          type: SyncErrorType.lockAcquisitionFailed,
          message: 'جهاز آخر حصل على القفل أولاً',
          isRecoverable: true,
        );
      }
    }
    
    return lock;
  }
  
  Future<SyncLock?> _readLockFile(String fileId) async {
    try {
      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return SyncLock.fromJson(json);
    } catch (e) {
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
      signature: SyncSecurity.signData('${_deviceId!}|${now.toIso8601String()}', _secretKey!),
    );
    
    await _writeLock(renewed);
    return renewed;
  }


  Future<void> _writeLock(SyncLock lock) async {
    final folderId = await _ensureSyncFolder();
    final content = jsonEncode(lock.toJson());
    final bytes = utf8.encode(content);
    
    // البحث عن ملف القفل الموجود
    final files = await _driveApi!.files.list(
      q: "name = '$_lockFileName' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
    );
    
    final tempFile = await _createTempFile(_lockFileName, bytes);
    final media = drive.Media(tempFile.openRead(), bytes.length);
    
    if (files.files?.isNotEmpty ?? false) {
      // تحديث الملف الموجود
      await _driveApi!.files.update(
        drive.File()..name = _lockFileName,
        files.files!.first.id!,
        uploadMedia: media,
      );
    } else {
      // إنشاء ملف جديد
      await _driveApi!.files.create(
        drive.File()
          ..name = _lockFileName
          ..parents = [folderId],
        uploadMedia: media,
      );
    }
    
    await tempFile.delete();
  }

  Future<void> _deleteLock() async {
    try {
      final folderId = await _ensureSyncFolder();
      final files = await _driveApi!.files.list(
        q: "name = '$_lockFileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );
      
      if (files.files?.isNotEmpty ?? false) {
        await _driveApi!.files.delete(files.files!.first.id!);
      }
    } catch (e) {
      print('⚠️ خطأ في حذف القفل: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(config.heartbeatInterval, (_) async {
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

  Future<void> _releaseLock() async {
    _stopHeartbeat();
    if (_currentLock != null) {
      await _deleteLock();
      _currentLock = null;
      print('🔓 تم تحرير القفل');
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// المرحلة 2: تنزيل الحالة البعيدة
  /// ═══════════════════════════════════════════════════════════════════════
  Future<Map<String, dynamic>> _downloadRemoteState() async {
    _updateStatus('جاري تنزيل البيانات البعيدة...');
    
    // 1. تنزيل manifest
    final manifest = await _downloadManifest();
    
    // 2. تنزيل ملفات الأجهزة الأخرى
    final otherDevicesData = await _downloadOtherDevicesData();
    
    // 3. تنزيل العمليات الجديدة
    final newOperations = await _downloadNewOperations(manifest);
    
    return {
      'manifest': manifest,
      'other_devices': otherDevicesData,
      'new_operations': newOperations,
    };
  }

  Future<SyncManifest> _downloadManifest() async {
    try {
      final folderId = await _ensureSyncFolder();
      final files = await _driveApi!.files.list(
        q: "name = '$_manifestFileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, createdTime, modifiedTime)', // طلب التوقيت
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

      final media = await _driveApi!.files.get(
        file.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final manifest = SyncManifest.fromJson(json);

      // 🛡️ فحص توافق الإصدار
      _checkVersionCompatibility(manifest.appVersion);

      return manifest;
    } catch (e) {
      if (e is SyncException) rethrow; // إعادة رمي أخطاء الإصدار
      print('⚠️ خطأ في تنزيل manifest: $e');
      return SyncManifest.empty(_deviceId!);
    }
  }

  void _checkVersionCompatibility(String remoteVersion) {
    // منطق بسيط: إذا كان الإصدار الرئيسي مختلفاً، نرفض المزامنة
    // (يمكن تحسينه باستخدام مكتبة pub_semver)
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


  Future<Map<String, List<SyncOperation>>> _downloadOtherDevicesData() async {
    final result = <String, List<SyncOperation>>{};
    
    try {
      final devicesFolderId = await _ensureSubFolder(_devicesFolderName);
      final files = await _driveApi!.files.list(
        q: "'$devicesFolderId' in parents and trashed = false and name contains '.json'",
        spaces: 'drive',
      );
      
      for (final file in files.files ?? []) {
        final fileName = file.name ?? '';
        if (fileName == '$_deviceId.json') continue; // تخطي ملفنا
        
        try {
          final media = await _driveApi!.files.get(
            file.id!,
            downloadOptions: drive.DownloadOptions.fullMedia,
          ) as drive.Media;
          
          final bytes = <int>[];
          await for (final chunk in media.stream) {
            bytes.addAll(chunk);
          }
          
          final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          final operations = (json['pending_operations'] as List?)
              ?.map((e) => SyncOperation.fromJson(e as Map<String, dynamic>))
              .toList() ?? [];
          
          final deviceId = json['device_id'] as String? ?? fileName.replaceAll('.json', '');
          result[deviceId] = operations;
        } catch (e) {
          print('⚠️ خطأ في قراءة ملف الجهاز $fileName: $e');
        }
      }
    } catch (e) {
      print('⚠️ خطأ في تنزيل بيانات الأجهزة: $e');
    }
    
    return result;
  }

  Future<List<SyncOperation>> _downloadNewOperations(SyncManifest manifest) async {
    final operations = <SyncOperation>[];
    
    try {
      final myDeviceState = manifest.devices[_deviceId];
      final syncedUpTo = myDeviceState?.syncedUpToGlobal ?? 0;
      
      final opsFolderId = await _ensureSubFolder(_operationsFolderName);
      final files = await _driveApi!.files.list(
        q: "'$opsFolderId' in parents and trashed = false and name contains '.json'",
        spaces: 'drive',
        orderBy: 'name',
      );
      
      for (final file in files.files ?? []) {
        try {
          final media = await _driveApi!.files.get(
            file.id!,
            downloadOptions: drive.DownloadOptions.fullMedia,
          ) as drive.Media;
          
          final bytes = <int>[];
          await for (final chunk in media.stream) {
            bytes.addAll(chunk);
          }
          
          final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
          final op = SyncOperation.fromJson(json);
          
          // فقط العمليات الجديدة التي لم نطبقها بعد
          if (op.globalSequence > syncedUpTo && op.deviceId != _deviceId) {
            operations.add(op);
          }
        } catch (e) {
          print('⚠️ خطأ في قراءة عملية ${file.name}: $e');
        }
      }
    } catch (e) {
      print('⚠️ خطأ في تنزيل العمليات: $e');
    }
    
    // ترتيب حسب التسلسل العالمي
    operations.sort((a, b) => a.globalSequence.compareTo(b.globalSequence));
    return operations;
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// المرحلة 3: التحقق والمصادقة
  /// ═══════════════════════════════════════════════════════════════════════
  Future<void> _verifyOperations(List<SyncOperation> operations) async {
    _updateStatus('جاري التحقق من صحة البيانات...');
    
    for (final op in operations) {
      // التحقق من checksum
      if (!op.verifyChecksum()) {
        throw SyncException(
          type: SyncErrorType.checksumMismatch,
          message: 'فشل التحقق من checksum للعملية ${op.operationId}',
          details: {'operation_id': op.operationId},
        );
      }
      
      // التحقق من التوقيع
      if (!op.verifySignature(_secretKey!)) {
        throw SyncException(
          type: SyncErrorType.signatureInvalid,
          message: 'توقيع غير صالح للعملية ${op.operationId}',
          details: {'operation_id': op.operationId},
        );
      }
    }
    
    print('✅ تم التحقق من ${operations.length} عملية بنجاح');
  }


  /// ═══════════════════════════════════════════════════════════════════════
  /// المرحلة 4 و 5: كشف وحل التعارضات
  /// ═══════════════════════════════════════════════════════════════════════
  Future<List<SyncConflict>> _detectAndResolveConflicts(
    List<SyncOperation> localOps,
    List<SyncOperation> remoteOps,
  ) async {
    _updateStatus('جاري فحص التعارضات...');
    final conflicts = <SyncConflict>[];
    
    // تجميع العمليات حسب الكيان
    final localByEntity = <String, List<SyncOperation>>{};
    final remoteByEntity = <String, List<SyncOperation>>{};
    
    for (final op in localOps) {
      final key = '${op.entityType}:${op.entityUuid}';
      localByEntity.putIfAbsent(key, () => []).add(op);
    }
    
    for (final op in remoteOps) {
      final key = '${op.entityType}:${op.entityUuid}';
      remoteByEntity.putIfAbsent(key, () => []).add(op);
    }
    
    // البحث عن التعارضات
    for (final key in localByEntity.keys) {
      if (remoteByEntity.containsKey(key)) {
        final localEntityOps = localByEntity[key]!;
        final remoteEntityOps = remoteByEntity[key]!;
        
        // فحص كل زوج من العمليات
        for (final localOp in localEntityOps) {
          for (final remoteOp in remoteEntityOps) {
            if (localOp.causalityVector.conflictsWith(remoteOp.causalityVector)) {
              final conflict = SyncConflict(
                conflictId: 'conflict_${DateTime.now().millisecondsSinceEpoch}_${SyncSecurity.generateUuid().substring(0, 8)}',
                detectedAt: DateTime.now().toUtc(),
                entityType: localOp.entityType,
                entityUuid: localOp.entityUuid,
                localOperation: localOp,
                remoteOperation: remoteOp,
                conflictType: _determineConflictType(localOp, remoteOp),
              );
              
              conflicts.add(conflict);
              onConflictDetected?.call(conflict);
            }
          }
        }
      }
    }
    
    // حل التعارضات تلقائياً إذا كان مفعلاً
    if (config.autoResolveConflicts && conflicts.isNotEmpty) {
      await _resolveConflicts(conflicts);
    }
    
    print('🔍 تم اكتشاف ${conflicts.length} تعارض');
    return conflicts;
  }

  String _determineConflictType(SyncOperation local, SyncOperation remote) {
    final localIsDelete = local.operationType.name.contains('Delete');
    final remoteIsDelete = remote.operationType.name.contains('Delete');
    
    if (localIsDelete && remoteIsDelete) return 'DELETE_DELETE';
    if (localIsDelete) return 'DELETE_UPDATE';
    if (remoteIsDelete) return 'UPDATE_DELETE';
    return 'UPDATE_UPDATE';
  }

  Future<void> _resolveConflicts(List<SyncConflict> conflicts) async {
    for (final conflict in conflicts) {
      // محاولة دمج ذكي أولاً (3-Way Merge)
      if (conflict.conflictType == 'UPDATE_UPDATE') {
        final mergedPayload = _mergePayloads(conflict.localOperation, conflict.remoteOperation);
        if (mergedPayload != null) {
          conflict.resolvedData?.addAll(mergedPayload);
          conflict.resolvedData?.addAll({'winner': 'merged'});
          continue; // تم الحل بالدمج
        }
      }

      switch (config.conflictResolutionStrategy) {
        case 'LAST_WRITE_WINS':
          // تصحيح التوقيت المحلي للمقارنة العادلة
          final localTimestampAdjusted = conflict.localOperation.timestamp.add(_serverTimeOffset);
          
          // الأحدث يفوز
          if (localTimestampAdjusted.isAfter(conflict.remoteOperation.timestamp)) {
            conflict.resolvedData?.addAll({'winner': 'local'});
          } else {
            conflict.resolvedData?.addAll({'winner': 'remote'});
          }
          break;
          
        case 'FIRST_WRITE_WINS':
          final localTimestampAdjusted = conflict.localOperation.timestamp.add(_serverTimeOffset);
          if (localTimestampAdjusted.isBefore(conflict.remoteOperation.timestamp)) {
            conflict.resolvedData?.addAll({'winner': 'local'});
          } else {
            conflict.resolvedData?.addAll({'winner': 'remote'});
          }
          break;
          
        default:
          // ASK_USER - لا نحل تلقائياً
          break;
      }
      
      // حفظ التعارض في Drive للمراجعة
      await _saveConflict(conflict);
    }
  }

  Future<void> _saveConflict(SyncConflict conflict) async {
    try {
      final conflictsFolderId = await _ensureSubFolder(_conflictsFolderName);
      final content = jsonEncode(conflict.toJson());
      final bytes = utf8.encode(content);
      
      final tempFile = await _createTempFile('${conflict.conflictId}.json', bytes);
      final media = drive.Media(tempFile.openRead(), bytes.length);
      
      await _driveApi!.files.create(
        drive.File()
          ..name = '${conflict.conflictId}.json'
          ..parents = [conflictsFolderId],
        uploadMedia: media,
      );
      
      await tempFile.delete();
    } catch (e) {
      print('⚠️ خطأ في حفظ التعارض: $e');
    }
  }


  /// ═══════════════════════════════════════════════════════════════════════
  /// المرحلة 6: تطبيق العمليات الواردة
  /// ═══════════════════════════════════════════════════════════════════════
  Future<int> _applyIncomingOperations(List<SyncOperation> operations) async {
    if (operations.isEmpty) return 0;
    
    _updateStatus('جاري تطبيق ${operations.length} عملية...');
    int appliedCount = 0;
    
    final db = await _db.database;
    
    await db.transaction((txn) async {
      for (final op in operations) {
        try {
          await _applySingleOperation(txn, op);
          appliedCount++;
          
          // تحديث التقدم
          onProgress?.call(appliedCount / operations.length);
        } catch (e) {
          print('❌ فشل تطبيق العملية ${op.operationId}: $e');
          // في حالة الفشل، نتراجع عن كل شيء
          throw SyncException(
            type: SyncErrorType.rollbackRequired,
            message: 'فشل تطبيق العملية ${op.operationId}',
            details: {'operation_id': op.operationId, 'error': e.toString()},
            originalError: e,
          );
        }
      }
    });
    
    // إعادة حساب الأرصدة المتأثرة
    await _recalculateAffectedBalances(operations);
    
    print('✅ تم تطبيق $appliedCount عملية بنجاح');
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
    
    // تسجيل أن العملية تم تطبيقها
    await txn.insert('sync_applied_operations', {
      'operation_id': op.operationId,
      'applied_at': DateTime.now().toUtc().toIso8601String(),
      'device_id': op.deviceId,
    });
  }

  Future<void> _applyCustomerCreate(dynamic txn, SyncOperation op) async {
    final data = op.payloadAfter;
    
    // التحقق من عدم وجود العميل مسبقاً
    final existing = await txn.query(
      'customers',
      where: 'sync_uuid = ?',
      whereArgs: [op.entityUuid],
    );
    
    if (existing.isNotEmpty) {
      print('⚠️ العميل موجود مسبقاً: ${op.entityUuid}');
      return;
    }
    
    await txn.insert('customers', {
      ...data,
      'sync_uuid': op.entityUuid,
      'synced_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _applyCustomerUpdate(dynamic txn, SyncOperation op) async {
    final data = op.payloadAfter;
    
    await txn.update(
      'customers',
      {
        ...data,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'sync_uuid = ?',
      whereArgs: [op.entityUuid],
    );
  }

  Future<void> _applyCustomerDelete(dynamic txn, SyncOperation op) async {
    // Soft delete
    await txn.update(
      'customers',
      {
        'is_deleted': 1,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'sync_uuid = ?',
      whereArgs: [op.entityUuid],
    );
  }

  Future<void> _applyTransactionCreate(dynamic txn, SyncOperation op) async {
    final data = Map<String, dynamic>.from(op.payloadAfter);
    // 🔄 تصحيح المصدر: عند استلام معاملة من جهاز آخر، يجب ألا تكون "من إنشائي"
    data['is_created_by_me'] = 0;
    
    // التحقق من عدم وجود المعاملة مسبقاً
    final existing = await txn.query(
      'transactions',
      where: 'transaction_uuid = ?',
      whereArgs: [op.entityUuid],
    );
    
    if (existing.isNotEmpty) {
      print('⚠️ المعاملة موجودة مسبقاً: ${op.entityUuid}');
      return;
    }
    
    // البحث عن العميل بالـ UUID
    final customerUuid = op.customerUuid ?? data['customer_uuid'];
    if (customerUuid != null) {
      final customers = await txn.query(
        'customers',
        where: 'sync_uuid = ?',
        whereArgs: [customerUuid],
      );
      
      if (customers.isNotEmpty) {
        data['customer_id'] = customers.first['id'];
      }
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

    await txn.update(
      'transactions',
      {
        ...data,
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'transaction_uuid = ?',
      whereArgs: [op.entityUuid],
    );
  }

  Future<void> _applyTransactionDelete(dynamic txn, SyncOperation op) async {
    // Soft delete
    await txn.update(
      'transactions',
      {
        'is_deleted': 1,
        'deleted_at': DateTime.now().toUtc().toIso8601String(),
        'synced_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'transaction_uuid = ?',
      whereArgs: [op.entityUuid],
    );
  }

  Future<void> _recalculateAffectedBalances(List<SyncOperation> operations) async {
    // جمع معرفات العملاء المتأثرين
    final affectedCustomerUuids = <String>{};
    
    for (final op in operations) {
      if (op.entityType == 'transaction' && op.customerUuid != null) {
        affectedCustomerUuids.add(op.customerUuid!);
      }
    }
    
    // إعادة حساب رصيد كل عميل متأثر
    final db = await _db.database;
    for (final uuid in affectedCustomerUuids) {
      final customers = await db.query(
        'customers',
        where: 'sync_uuid = ?',
        whereArgs: [uuid],
      );
      
      if (customers.isNotEmpty) {
        final customerId = customers.first['id'] as int;
        await _db.recalculateAndApplyCustomerDebt(customerId);
        await _db.recalculateCustomerTransactionBalances(customerId);
      }
    }
  }


  /// ═══════════════════════════════════════════════════════════════════════
  /// المرحلة 7: رفع العمليات المحلية (مع Batching للأداء)
  /// ═══════════════════════════════════════════════════════════════════════
  Future<int> _uploadLocalOperations(
    List<SyncOperation> operations,
    int startGlobalSequence,
  ) async {
    if (operations.isEmpty) return 0;
    
    _updateStatus('جاري رفع ${operations.length} عملية...');
    
    final opsFolderId = await _ensureSubFolder(_operationsFolderName);
    int currentSequence = startGlobalSequence;
    
    // ═══════════════════════════════════════════════════════════════════
    // تحسين Batching: بدلاً من رفع كل عملية في ملف منفصل،
    // نجمعها في ملف batch واحد لتقليل طلبات الشبكة
    // ═══════════════════════════════════════════════════════════════════
    
    final batchOperations = <Map<String, dynamic>>[];
    
    for (final op in operations) {
      currentSequence++;
      final updatedOp = op.copyWith(globalSequence: currentSequence);
      batchOperations.add(updatedOp.toJson());
    }
    
    // إنشاء ملف الـ Batch
    final batchData = {
      'batch_id': 'batch_${DateTime.now().toUtc().millisecondsSinceEpoch}_$_deviceId',
      'device_id': _deviceId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'operations_count': operations.length,
      'start_sequence': startGlobalSequence + 1,
      'end_sequence': currentSequence,
      'operations': batchOperations,
    };
    
    final content = jsonEncode(batchData);
    
    // ═══════════════════════════════════════════════════════════════════
    // تحسين Compression: ضغط البيانات بـ GZIP
    // ═══════════════════════════════════════════════════════════════════
    final compressedBytes = gzip.encode(utf8.encode(content));
    final fileName = 'batch_${DateTime.now().toUtc().millisecondsSinceEpoch}_$_deviceId.json.gz';
    
    try {
      final tempFile = await _createTempFile(fileName, compressedBytes);
      final media = drive.Media(
        tempFile.openRead(), 
        compressedBytes.length,
        contentType: 'application/gzip',
      );
      
      await _driveApi!.files.create(
        drive.File()
          ..name = fileName
          ..parents = [opsFolderId],
        uploadMedia: media,
      );
      
      await tempFile.delete();
      
      // تحديث حالة العمليات محلياً
      final db = await _db.database;
      int seq = startGlobalSequence;
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
      
      onProgress?.call(1.0);
      
    } catch (e) {
      print('❌ فشل رفع الـ Batch: $e');
      throw SyncException(
        type: SyncErrorType.networkError,
        message: 'فشل رفع العمليات',
        originalError: e,
      );
    }
    
    // تحديث ملف الجهاز
    await _updateDeviceFile(currentSequence);
    
    print('✅ تم رفع ${operations.length} عملية في ملف batch واحد مضغوط');
    return operations.length;
  }

  Future<void> _updateDeviceFile(int localSequence) async {
    final devicesFolderId = await _ensureSubFolder(_devicesFolderName);
    
    final deviceData = {
      'device_id': _deviceId,
      'device_name': _deviceName,
      'schema_version': '2.0.0',
      'last_updated': DateTime.now().toUtc().toIso8601String(),
      'state': {
        'local_sequence': localSequence,
        'synced_up_to_global': localSequence,
        'pending_operations_count': 0,
      },
      'pending_operations': <Map<String, dynamic>>[],
      'local_checksums': {
        'customers': await _calculateCustomersChecksum(),
        'transactions': await _calculateTransactionsChecksum(),
      },
    };
    
    final content = jsonEncode(deviceData);
    final bytes = utf8.encode(content);
    final fileName = '$_deviceId.json';
    
    // البحث عن الملف الموجود
    final files = await _driveApi!.files.list(
      q: "name = '$fileName' and '$devicesFolderId' in parents and trashed = false",
      spaces: 'drive',
    );
    
    final tempFile = await _createTempFile(fileName, bytes);
    final media = drive.Media(tempFile.openRead(), bytes.length);
    
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
          ..parents = [devicesFolderId],
        uploadMedia: media,
      );
    }
    
    await tempFile.delete();
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// المرحلة 8: تحديث الفهرس
  /// ═══════════════════════════════════════════════════════════════════════
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
    
    // حساب checksums جديدة
    final customersChecksum = await _calculateCustomersChecksum();
    final transactionsChecksum = await _calculateTransactionsChecksum();
    
    final updatedEntities = {
      'customers': EntityState(
        name: 'customers',
        count: await _getCustomersCount(),
        lastModified: now,
        checksum: customersChecksum,
      ),
      'transactions': EntityState(
        name: 'transactions',
        count: await _getTransactionsCount(),
        lastModified: now,
        checksum: transactionsChecksum,
      ),
    };
    
    // حساب Merkle Root
    final merkleRoot = MerkleTree.calculateRoot([customersChecksum, transactionsChecksum]);
    
    // إنشاء manifest جديد
    var newManifest = SyncManifest(
      globalSequence: newGlobalSequence,
      lastModified: now,
      lastModifiedBy: _deviceId!,
      checksum: '', // سيتم حسابه
      devices: updatedDevices,
      entities: updatedEntities,
      merkleRoot: merkleRoot,
    );
    
    // حساب checksum للـ manifest
    final manifestJson = newManifest.toJson();
    manifestJson.remove('checksum');
    final checksum = SyncSecurity.calculateChecksum(manifestJson);
    
    newManifest = newManifest.copyWith(checksum: checksum);
    
    // رفع الـ manifest
    await _uploadManifest(newManifest);
  }

  Future<int> _getCustomersCount() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM customers WHERE is_deleted IS NULL OR is_deleted = 0');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<int> _getTransactionsCount() async {
    final db = await _db.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM transactions WHERE is_deleted IS NULL OR is_deleted = 0');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<void> _uploadManifest(SyncManifest manifest) async {
    final folderId = await _ensureSyncFolder();
    final content = jsonEncode(manifest.toJson());
    final bytes = utf8.encode(content);
    
    final files = await _driveApi!.files.list(
      q: "name = '$_manifestFileName' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
    );
    
    final tempFile = await _createTempFile(_manifestFileName, bytes);
    final media = drive.Media(tempFile.openRead(), bytes.length);
    
    if (files.files?.isNotEmpty ?? false) {
      await _driveApi!.files.update(
        drive.File()..name = _manifestFileName,
        files.files!.first.id!,
        uploadMedia: media,
      );
    } else {
      await _driveApi!.files.create(
        drive.File()
          ..name = _manifestFileName
          ..parents = [folderId],
        uploadMedia: media,
      );
    }
    
    await tempFile.delete();
  }


  /// ═══════════════════════════════════════════════════════════════════════
  /// المرحلة 9: إرسال التأكيدات
  /// ═══════════════════════════════════════════════════════════════════════
  Future<void> _sendAcknowledgments(List<SyncOperation> appliedOperations) async {
    if (appliedOperations.isEmpty) return;
    
    _updateStatus('جاري إرسال التأكيدات...');
    
    // تجميع العمليات حسب الجهاز المصدر
    final byDevice = <String, List<SyncOperation>>{};
    for (final op in appliedOperations) {
      byDevice.putIfAbsent(op.deviceId, () => []).add(op);
    }
    
    // تحديث ملفات العمليات بالتأكيدات
    final opsFolderId = await _ensureSubFolder(_operationsFolderName);
    
    for (final op in appliedOperations) {
      try {
        // قراءة ملف العملية
        final files = await _driveApi!.files.list(
          q: "name = '${op.operationId}.json' and '$opsFolderId' in parents and trashed = false",
          spaces: 'drive',
        );
        
        if (files.files?.isEmpty ?? true) continue;
        
        final fileId = files.files!.first.id!;
        final media = await _driveApi!.files.get(
          fileId,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as drive.Media;
        
        final bytes = <int>[];
        await for (final chunk in media.stream) {
          bytes.addAll(chunk);
        }
        
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        
        // إضافة التأكيد
        final acks = (json['acknowledgments'] as Map<String, dynamic>?) ?? {};
        acks[_deviceId!] = {
          'device_id': _deviceId,
          'received_at': DateTime.now().toUtc().toIso8601String(),
          'applied_at': DateTime.now().toUtc().toIso8601String(),
          'status': 'APPLIED',
        };
        json['acknowledgments'] = acks;
        
        // رفع الملف المحدث
        final updatedContent = jsonEncode(json);
        final updatedBytes = utf8.encode(updatedContent);
        final tempFile = await _createTempFile('${op.operationId}.json', updatedBytes);
        final uploadMedia = drive.Media(tempFile.openRead(), updatedBytes.length);
        
        await _driveApi!.files.update(
          drive.File()..name = '${op.operationId}.json',
          fileId,
          uploadMedia: uploadMedia,
        );
        
        await tempFile.delete();
      } catch (e) {
        print('⚠️ فشل إرسال تأكيد للعملية ${op.operationId}: $e');
      }
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// المرحلة 10: التنظيف
  /// ═══════════════════════════════════════════════════════════════════════
  Future<void> _cleanup(int newGlobalSequence) async {
    _updateStatus('جاري التنظيف...');
    
    // إنشاء snapshot إذا لزم الأمر
    if (newGlobalSequence > 0 && newGlobalSequence % config.snapshotEveryNOperations == 0) {
      await _createSnapshot(newGlobalSequence);
    }
    
    // حذف العمليات القديمة
    await _cleanupOldOperations();
    
    // حذف الملفات المؤقتة المحلية
    await _cleanupTempFiles();
  }

  Future<void> _createSnapshot(int version) async {
    try {
      final snapshotsFolderId = await _ensureSubFolder(_snapshotsFolderName);
      
      final db = await _db.database;
      final customers = await db.query('customers');
      final transactions = await db.query('transactions');
      
      final snapshot = {
        'version': version,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'created_by': _deviceId,
        'data': {
          'customers': customers,
          'transactions': transactions,
        },
        'checksums': {
          'customers': await _calculateCustomersChecksum(),
          'transactions': await _calculateTransactionsChecksum(),
        },
      };
      
      final content = jsonEncode(snapshot);
      final bytes = utf8.encode(content);
      final fileName = 'snapshot_v$version.json';
      
      final tempFile = await _createTempFile(fileName, bytes);
      final media = drive.Media(tempFile.openRead(), bytes.length);
      
      await _driveApi!.files.create(
        drive.File()
          ..name = fileName
          ..parents = [snapshotsFolderId],
        uploadMedia: media,
      );
      
      await tempFile.delete();
      print('📸 تم إنشاء snapshot للإصدار $version');
    } catch (e) {
      print('⚠️ فشل إنشاء snapshot: $e');
    }
  }

  Future<void> _cleanupOldOperations() async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: config.keepOperationsDays));
      final opsFolderId = await _ensureSubFolder(_operationsFolderName);
      
      final files = await _driveApi!.files.list(
        q: "'$opsFolderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, createdTime)',
      );
      
      for (final file in files.files ?? []) {
        final createdTime = file.createdTime;
        if (createdTime != null && createdTime.isBefore(cutoffDate)) {
          try {
            await _driveApi!.files.delete(file.id!);
            print('🗑️ تم حذف العملية القديمة: ${file.name}');
          } catch (e) {
            print('⚠️ فشل حذف ${file.name}: $e');
          }
        }
      }
    } catch (e) {
      print('⚠️ فشل تنظيف العمليات القديمة: $e');
    }
  }

  Future<void> _cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final syncTempDir = Directory('${tempDir.path}/sync_temp');
      if (await syncTempDir.exists()) {
        await syncTempDir.delete(recursive: true);
      }
    } catch (e) {
      print('⚠️ فشل تنظيف الملفات المؤقتة: $e');
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
      
      print('🧬 تم دمج عمليات التحديث بنجاح (Merge)');
      return merged;
    } catch (e) {
      print('⚠️ فشل الدمج الذكي: $e');
      return null;
    }
  }


  /// ═══════════════════════════════════════════════════════════════════════
  /// الدالة الرئيسية للمزامنة
  /// ═══════════════════════════════════════════════════════════════════════
  Future<SyncReport> performFullSync() async {
    if (!isReady) {
      throw SyncException(
        type: SyncErrorType.unknownError,
        message: 'محرك المزامنة غير جاهز. يرجى استدعاء initialize() أولاً',
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
    var conflictsDetected = 0;
    var conflictsResolved = 0;
    List<SyncConflict> unresolvedConflicts = [];
    String? localChecksum;
    String? remoteChecksum;
    
    try {
      // المرحلة 0: التحضير المحلي
      final localState = await _prepareLocalState();
      localChecksum = '${localState['checksums']['customers']}|${localState['checksums']['transactions']}';
      
      // المرحلة 1: الحصول على القفل
      final lockAcquired = await _acquireLock();
      if (!lockAcquired) {
        throw SyncException(
          type: SyncErrorType.lockAcquisitionFailed,
          message: 'فشل الحصول على القفل',
        );
      }
      
      try {
        // المرحلة 2: تنزيل الحالة البعيدة
        final remoteState = await _downloadRemoteState();
        final manifest = remoteState['manifest'] as SyncManifest;
        final newOperations = remoteState['new_operations'] as List<SyncOperation>;
        operationsDownloaded = newOperations.length;
        
        // المرحلة 3: التحقق والمصادقة
        await _verifyOperations(newOperations);
        
        // المرحلة 4 و 5: كشف وحل التعارضات
        final pendingOps = localState['pending_operations'] as List<SyncOperation>;
        final conflicts = await _detectAndResolveConflicts(pendingOps, newOperations);
        conflictsDetected = conflicts.length;
        conflictsResolved = conflicts.where((c) => c.resolution != null).length;
        unresolvedConflicts = conflicts.where((c) => c.resolution == null).toList();
        
        // المرحلة 6: تطبيق العمليات الواردة
        operationsApplied = await _applyIncomingOperations(newOperations);
        
        // المرحلة 7: رفع العمليات المحلية
        operationsUploaded = await _uploadLocalOperations(
          pendingOps,
          manifest.globalSequence,
        );
        
        // المرحلة 8: تحديث الفهرس
        final newGlobalSequence = manifest.globalSequence + operationsUploaded;
        await _updateManifest(manifest, newGlobalSequence);
        
        // المرحلة 9: إرسال التأكيدات
        await _sendAcknowledgments(newOperations);
        
        // المرحلة 10: التنظيف
        await _cleanup(newGlobalSequence);
        
        // المرحلة 11: التحقق النهائي
        final finalCustomersChecksum = await _calculateCustomersChecksum();
        final finalTransactionsChecksum = await _calculateTransactionsChecksum();
        localChecksum = '$finalCustomersChecksum|$finalTransactionsChecksum';
        
        // قراءة manifest المحدث للتحقق
        final updatedManifest = await _downloadManifest();
        remoteChecksum = '${updatedManifest.entities['customers']?.checksum}|${updatedManifest.entities['transactions']?.checksum}';
        
        final checksumsMatch = localChecksum == remoteChecksum;
        if (!checksumsMatch) {
          warnings.add('تحذير: checksums لا تتطابق بعد المزامنة');
        }
        
        _updateStatus('اكتملت المزامنة بنجاح ✅');
        
        final report = SyncReport(
          startTime: startTime,
          endTime: DateTime.now(),
          success: true,
          operationsDownloaded: operationsDownloaded,
          operationsUploaded: operationsUploaded,
          operationsApplied: operationsApplied,
          conflictsDetected: conflictsDetected,
          conflictsResolved: conflictsResolved,
          localChecksum: localChecksum,
          remoteChecksum: remoteChecksum,
          checksumsMatch: checksumsMatch,
          warnings: warnings,
          unresolvedConflicts: unresolvedConflicts,
        );
        
        onSyncComplete?.call(report);
        return report;
        
      } finally {
        // تحرير القفل دائماً
        await _releaseLock();
      }
      
    } on SyncException catch (e) {
      _updateStatus('فشلت المزامنة: ${e.message}');
      
      final report = SyncReport(
        startTime: startTime,
        endTime: DateTime.now(),
        success: false,
        errorMessage: e.message,
        errorType: e.type,
        operationsDownloaded: operationsDownloaded,
        operationsUploaded: operationsUploaded,
        operationsApplied: operationsApplied,
        conflictsDetected: conflictsDetected,
        conflictsResolved: conflictsResolved,
        warnings: warnings,
        unresolvedConflicts: unresolvedConflicts,
      );
      
      onSyncComplete?.call(report);
      return report;
      
    } catch (e) {
      _updateStatus('فشلت المزامنة: $e');
      
      final report = SyncReport(
        startTime: startTime,
        endTime: DateTime.now(),
        success: false,
        errorMessage: e.toString(),
        errorType: SyncErrorType.unknownError,
        warnings: warnings,
      );
      
      onSyncComplete?.call(report);
      return report;
      
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
    final parentId = await _ensureSyncFolder();
    
    final files = await _driveApi!.files.list(
      q: "name = '$folderName' and '$parentId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
    );
    
    if (files.files?.isNotEmpty ?? false) {
      return files.files!.first.id!;
    }
    
    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [parentId];
    
    final created = await _driveApi!.files.create(folder);
    return created.id!;
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

  /// إغلاق المحرك وتنظيف الموارد
  void dispose() {
    _stopHeartbeat();
    _httpClient?.close();
  }
}
