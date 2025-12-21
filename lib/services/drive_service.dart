
// services/drive_service.dart
import 'dart:io';
import 'dart:convert';
import 'dart:convert'; // Added for jsonEncode and jsonDecode
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'database_service.dart';
import '../models/transaction.dart';
import '../models/customer.dart'; // 🔄 Import Customer model

class DriveService {
  static final DriveService _instance = DriveService._internal();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      // نحتاج صلاحية رؤية جميع الملفات بما فيها التي رُفعت يدوياً من الويب
      drive.DriveApi.driveScope,
    ],
  );
  final _storage = const FlutterSecureStorage();

  // OAuth 2.0 Desktop credentials
  String get _clientIdString => dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
  String get _clientSecretString => dotenv.env['GOOGLE_CLIENT_SECRET'] ?? '';
  String get _redirectUrlString => dotenv.env['GOOGLE_REDIRECT_URL'] ?? 'http://localhost';
  // نطاقات OAuth لسطح المكتب
  final _scopes = [drive.DriveApi.driveScope, 'email', 'profile'];

  factory DriveService() => _instance;
  DriveService._internal();

  bool get isSupported => true;

  // مفاتيح التخزين للمصداقية الكاملة
  static const _kCredAccessToken = 'access_token';
  static const _kCredRefreshToken = 'refresh_token';
  static const _kCredExpiry = 'access_token_expiry_iso8601';
  static const _kCredTokenType = 'access_token_type';
  static const _kCredScopes = 'oauth_scopes_csv';

  Future<void> _saveCredentials(auth.AccessCredentials credentials) async {
    await _storage.write(key: _kCredAccessToken, value: credentials.accessToken.data);
    await _storage.write(key: _kCredTokenType, value: credentials.accessToken.type);
    await _storage.write(key: _kCredExpiry, value: credentials.accessToken.expiry.toUtc().toIso8601String());
    await _storage.write(key: _kCredRefreshToken, value: credentials.refreshToken ?? '');
    await _storage.write(key: _kCredScopes, value: credentials.scopes.join(','));
  }

  Future<auth.AccessCredentials?> _loadCredentials() async {
    final at = await _storage.read(key: _kCredAccessToken);
    final rt = await _storage.read(key: _kCredRefreshToken);
    final tp = await _storage.read(key: _kCredTokenType);
    final ex = await _storage.read(key: _kCredExpiry);
    final sc = await _storage.read(key: _kCredScopes);
    if (at == null || tp == null || ex == null || sc == null) {
      // توافق قديم: حاول قراءة المفاتيح القديمة فقط إذا كانت موجودة
      final legacyAt = await _storage.read(key: 'access_token');
      final legacyRt = await _storage.read(key: 'refresh_token');
      if (legacyAt != null) {
        return auth.AccessCredentials(
          auth.AccessToken('Bearer', legacyAt, DateTime.now().toUtc().add(const Duration(minutes: 55))),
          legacyRt,
          _scopes,
        );
      }
      return null;
    }
    return auth.AccessCredentials(
      auth.AccessToken(tp, at, DateTime.tryParse(ex) ?? DateTime.now().toUtc().add(const Duration(minutes: 55))),
      (rt == null || rt.isEmpty) ? null : rt,
      sc.split(',').where((e) => e.trim().isNotEmpty).toList(),
    );
  }

  Future<void> _clearCredentials() async {
    await _storage.delete(key: _kCredAccessToken);
    await _storage.delete(key: _kCredRefreshToken);
    await _storage.delete(key: _kCredExpiry);
    await _storage.delete(key: _kCredTokenType);
    await _storage.delete(key: _kCredScopes);
  }

  Future<bool> isSignedIn() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        // Prefer silent sign-in; do not clear tokens on failure.
        final account = await _googleSignIn.signInSilently();
        if (account != null) return true;
        // Fallback to current sign-in state
        return await _googleSignIn.isSignedIn();
      } catch (_) {
        return false;
      }
    } else {
      // على سطح المكتب: اعتبر المستخدم "مسجلاً" طالما لدينا بيانات اعتماد محفوظة محلياً
      // حتى لو انتهت صلاحيتها على خوادم جوجل. سنطلب إعادة تسجيل الدخول فقط عند محاولة إجراء يتطلب الشبكة.
      final creds = await _loadCredentials();
      return creds != null;
    }
  }

  Future<bool> signIn() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) throw Exception('تم إلغاء تسجيل الدخول');
      // On mobile, build an authenticated client directly from GoogleSignIn
      final client = await _getAuthenticatedClient();
      final driveApi = drive.DriveApi(client);
      await driveApi.files.list(pageSize: 1);
      return true;
    } else {
      final clientId = auth.ClientId(_clientIdString, _clientSecretString);
      final client = http.Client();
      try {
        final credentials = await auth.obtainAccessCredentialsViaUserConsent(
          clientId,
          _scopes,
          client,
          (String url) async {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              throw 'Could not launch $url';
            }
          },
        );
        await _saveCredentials(credentials);
        final driveApi = drive.DriveApi(auth.authenticatedClient(client, credentials));
        await driveApi.files.list(pageSize: 1);
        return true;
      } finally {
        client.close();
      }
    }
  }

  Future<void> signOut() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _googleSignIn.signOut();
      }
      await _clearCredentials();
    } catch (_) {}
  }

  // دالة مساعدة لإظهار رسائل واضحة للمستخدم
  String _getUserFriendlyMessage(String error) {
    if (error.contains('invalid_token')) {
      return 'انتهت صلاحية التوكن. جاري إعادة تسجيل الدخول تلقائياً...';
    } else if (error.contains('انتهت صلاحية التوكن')) {
      return 'انتهت صلاحية التوكن. يرجى إعادة تسجيل الدخول يدوياً من الإعدادات';
    } else if (error.contains('network')) {
      return 'مشكلة في الاتصال بالإنترنت. يرجى التحقق من الاتصال والمحاولة مرة أخرى';
    } else if (error.contains('quota')) {
      return 'تم تجاوز الحد المسموح من Google Drive. يرجى المحاولة لاحقاً';
    } else {
      return 'حدث خطأ غير متوقع: $error';
    }
  }

  /// الحصول على HTTP Client مصادق للاستخدام الخارجي (مثل SyncEngine)
  Future<http.Client> getAuthenticatedHttpClient({bool forceRefresh = false}) async {
    return _getAuthenticatedClient(forceRefresh: forceRefresh);
  }

  Future<http.Client> _getAuthenticatedClient({bool forceRefresh = false}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final authClient = await _googleSignIn.authenticatedClient();
      if (authClient == null) {
        throw Exception('لم يتم تسجيل الدخول');
      }
      return authClient;
    }

    final loaded = await _loadCredentials();
    if (loaded == null) {
      throw Exception('لم يتم تسجيل الدخول');
    }

    // تأكد من أن الصلاحيات تحتوي على driveScope الكامل لرؤية الملفات المرفوعة يدوياً
    if (!loaded.scopes.contains(drive.DriveApi.driveScope)) {
      await _clearCredentials();
      throw Exception('تم تحديث صلاحيات Google Drive، يرجى إعادة تسجيل الدخول للسماح بالوصول الكامل');
    }

    // إذا كانت الصلاحية ستنتهي قريباً أو طُلب تحديث قسري، قم بالتحديث
    final willExpireSoon = DateTime.now().toUtc().isAfter(loaded.accessToken.expiry.subtract(const Duration(minutes: 5)));
    if ((forceRefresh || willExpireSoon) && (loaded.refreshToken != null && loaded.refreshToken!.isNotEmpty)) {
      try {
        final clientId = auth.ClientId(_clientIdString, _clientSecretString);
        final client = http.Client();
        try {
          final refreshed = await auth.refreshCredentials(clientId, loaded, client);
          await _saveCredentials(refreshed);
          return auth.authenticatedClient(http.Client(), refreshed);
        } finally {
          client.close();
        }
      } on Exception catch (e) {
        print('فشل تجديد التوكن، يتطلب إعادة تسجيل الدخول يدوياً: $e');
        throw Exception('انتهت صلاحية التوكن. يرجى إعادة تسجيل الدخول يدوياً من الإعدادات');
      }
    }

    return auth.authenticatedClient(http.Client(), loaded);
  }

  // يولد معرف جهاز ثابت نسبياً بالاعتماد على BSSID للواي فاي وعنوان/معرّف بديل
  // ثم يستخدمه كبادئة لمعّرف المعاملة لتجنّب التصادم بين الأجهزة بدون إنترنت.
  Future<String> _getStableDeviceIdPrefix() async {
    try {
      final info = NetworkInfo();
      final wifiMac = await info.getWifiBSSID();
      final btMac = await info.getWifiIP(); // بديل للبلوتوث حيث لا تتوفر API موحدة
      final wifiPart = (wifiMac ?? 'unknownWifi').replaceAll(':', '-').toUpperCase();
      final btPart = (btMac ?? 'unknownBt').replaceAll(':', '-').toUpperCase();
      return '${wifiPart}-${btPart}';
    } catch (_) {
      return 'UNKNOWNWIFI-UNKNOWNBT';
    }
  }

  String _randomBase36(int length) {
    final rand = Random.secure();
    const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
    final buf = StringBuffer();
    for (int i = 0; i < length; i++) {
      buf.write(chars[rand.nextInt(chars.length)]);
    }
    return buf.toString();
  }

  // يبني transactionUuid بالشكل: WIFI-BT:epochMillis-rand
  Future<String> generateTransactionUuid() async {
    final prefix = await _getStableDeviceIdPrefix();
    final epoch = DateTime.now().toUtc().millisecondsSinceEpoch;
    final rand = _randomBase36(10);
    return '$prefix:$epoch-$rand';
  }

  Future<String> _getUniqueFolderName() async {
    try {
      final info = NetworkInfo();
      final wifi = await info.getWifiBSSID();
      final bluetooth = await info.getWifiIP();
      final wifiPart = (wifi ?? 'unknownWifi').replaceAll(':', '').trim();
      final btPart = (bluetooth ?? 'unknownBt').replaceAll(':', '').trim();
      return '${wifiPart}_${btPart}';
    } catch (_) {
      return 'تقارير دفتر ديوني';
    }
  }

  Future<String?> _getFolderId({String? specificName}) async {
    final client = await _getAuthenticatedClient();
    final driveApi = drive.DriveApi(client);
    final folderName = specificName ?? 'تقارير دفتر ديوني';
    final result = await driveApi.files.list(
      q: "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
    );
    if (result.files?.isNotEmpty ?? false) {
      return result.files!.first.id; // Could be null, caller must handle
    }
    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final createdFolder = await driveApi.files.create(folder);
    return createdFolder.id;
  }

  Future<void> uploadFile(File file, String fileName) async {
    try {
      final client = await _getAuthenticatedClient();
      final driveApi = drive.DriveApi(client);
    final folderId = await _getFolderId(specificName: await _getUniqueFolderName());
    if (folderId == null) throw Exception('فشل إنشاء مجلد التقارير');
      final existingFiles = await driveApi.files.list(
        q: "name = '$fileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );
      if (existingFiles.files?.isNotEmpty ?? false) {
        final fileId = existingFiles.files!.first.id;
        final media = drive.Media(file.openRead(), await file.length());
        await driveApi.files.update(
          drive.File()..name = fileName,
          fileId!,
          uploadMedia: media,
        );
      } else {
        final driveFile = drive.File()
          ..name = fileName
          ..parents = [folderId];
        final media = drive.Media(file.openRead(), await file.length());
        await driveApi.files.create(
          driveFile,
          uploadMedia: media,
        );
      }
    } catch (e) {
      if (e.toString().contains('invalid_token') || e.toString().contains('انتهت صلاحية التوكن')) {
        print('انتهت صلاحية التوكن، يتطلب إعادة تسجيل الدخول يدوياً...');
        throw Exception(_getUserFriendlyMessage(e.toString()));
      } else {
        throw Exception('فشل رفع الملف: $e');
      }
    }
  }

  Future<void> uploadDailyReport(File reportFile, {String? branchName}) async {
    try {
      final client = await _getAuthenticatedClient();
      final driveApi = drive.DriveApi(client);
      final folderId = await _getFolderId();
      if (folderId == null) throw Exception('فشل الوصول لمجلد التقارير');
      
      // اسم الملف يتضمن اسم الفرع
      final fileName = branchName != null && branchName.isNotEmpty
          ? 'سجل الديون_$branchName.pdf'
          : 'سجل الديون.pdf';
      
      final existingFiles = await driveApi.files.list(
        q: "name = '$fileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );
      if (existingFiles.files?.isNotEmpty ?? false) {
        final fileId = existingFiles.files!.first.id;
        final media = drive.Media(reportFile.openRead(), await reportFile.length());
        await driveApi.files.update(
          drive.File()..name = fileName,
          fileId!,
          uploadMedia: media,
        );
      } else {
        final driveFile = drive.File()
          ..name = fileName
          ..parents = [folderId];
        final media = drive.Media(reportFile.openRead(), await reportFile.length());
        await driveApi.files.create(
          driveFile,
          uploadMedia: media,
        );
      }
    } catch (e) {
      if (e.toString().contains('invalid_token') || e.toString().contains('انتهت صلاحية التوكن')) {
        print('انتهت صلاحية التوكن، يتطلب إعادة تسجيل الدخول يدوياً...');
        throw Exception(_getUserFriendlyMessage(e.toString()));
      } else {
        throw Exception('فشل رفع سجل الديون: $e');
      }
    }
  }

  // رفع نسخة مضغوطة باسم تاريخ اليوم داخل مجلد MAC مع الإبقاء على آخر نسختين فقط
  Future<void> uploadBackupZipAndRetain({
    required File zipFile,
    ValueChanged<double>? progress,
  }) async {
    try {
      final client = await _getAuthenticatedClient();
      final driveApi = drive.DriveApi(client);
      final macFolderId = await _getFolderId(specificName: await _getUniqueFolderName());
      final media = drive.Media(zipFile.openRead(), await zipFile.length(), contentType: 'application/zip');
      final driveFile = drive.File()
        ..name = zipFile.uri.pathSegments.last
        ..parents = [macFolderId!];
      await driveApi.files.create(driveFile, uploadMedia: media);
      progress?.call(1.0);

      final listRes = await driveApi.files.list(
        q: "'$macFolderId' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed = false and name contains '.zip'",
        spaces: 'drive',
        $fields: 'files(id, name, createdTime)',
        orderBy: 'createdTime desc',
      );
      final files = listRes.files ?? [];
      // حذف النسخ القديمة والنسخ ذات الاسم القديم (yyyy-MM-dd.zip)
      // الإبقاء فقط على أحدث 3 نسخ باسم التوقيت الكامل
      final isLegacy = RegExp(r'^\d{4}-\d{2}-\d{2}\.zip$');
      int kept = 0;
      for (int i = 0; i < files.length; i++) {
        final f = files[i];
        final name = f.name ?? '';
        final isTimestamped = RegExp(r'^\d{4}-\d{2}-\d{2}_[0-2]\d-[0-5]\d-[0-5]\d\.zip$').hasMatch(name);
        final shouldDelete = isLegacy.hasMatch(name) || (isTimestamped ? kept >= 3 : false);
        if (isTimestamped) kept++;
        if (shouldDelete) {
          try {
            await driveApi.files.delete(f.id!);
          } catch (e) {
            debugPrint('Failed to delete old backup ${f.name}: $e');
          }
        }
      }
    } catch (e) {
      if (e.toString().contains('invalid_token') || e.toString().contains('انتهت صلاحية التوكن')) {
        print('انتهت صلاحية التوكن، يتطلب إعادة تسجيل الدخول يدوياً...');
        throw Exception(_getUserFriendlyMessage(e.toString()));
      } else {
        throw Exception('فشل رفع النسخة الاحتياطية: $e');
      }
    }
  }
}

// امتدادات للمزامنة
extension DriveSyncExtension on DriveService {
  static const String syncFolderName = 'مزامنة';

  Future<String> _getDeviceJsonName() async {
    try {
      final info = NetworkInfo();
      final wifiMac = await info.getWifiBSSID();
      final btMac = await info.getWifiIP(); // ملاحظة: لا توجد API موحدة للبلوتوث على كل المنصات
      final wifiPart = (wifiMac ?? 'unknownWifi').replaceAll(':', '-').toUpperCase();
      final btPart = (btMac ?? 'unknownBt').replaceAll(':', '-').toUpperCase();
      return '${wifiPart}_${btPart}.json';
    } catch (_) {
      return 'UNKNOWN_DEVICE.json';
    }
  }

  Future<String> _ensureSyncFolderId() async {
    final client = await _getAuthenticatedClient();
    final driveApi = drive.DriveApi(client);
    final list = await driveApi.files.list(
      q: "name = '$syncFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
    );
    if ((list.files?.isNotEmpty ?? false)) {
      final id = list.files!.first.id;
      if (id == null) {
        // If ID is null (very unlikely), we can't use this folder.
        // It's safer to throw or try to create a new one, but let's throw friendly error.
        throw Exception('مجلد المزامنة موجود ولكن بدون معرف. يرجى حذفه من Google Drive وإعادة المحاولة.');
      }
      return id;
    }
    final folder = drive.File()
      ..name = syncFolderName
      ..mimeType = 'application/vnd.google-apps.folder';
    final created = await driveApi.files.create(folder);
    if (created.id == null) {
      throw Exception('فشل إنشاء مجلد المزامنة (ID is null).');
    }
    return created.id!;
  }

  Future<Map<String, dynamic>> _readJsonFileByName(String folderId, String fileName) async {
    final client = await _getAuthenticatedClient();
    final driveApi = drive.DriveApi(client);
    final res = await driveApi.files.list(
      q: "name = '$fileName' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
    );
    if ((res.files?.isEmpty ?? true)) return {};
    final fileId = res.files!.first.id!;
    final media = await driveApi.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return {};
    return _safeDecodeUtf8Json(bytes);
  }

  Map<String, dynamic> _safeDecodeUtf8Json(List<int> bytes) {
    try {
      final s = utf8.decode(bytes);
      final m = jsonDecode(s);
      if (m is Map<String, dynamic>) return m;
      debugPrint('SYNC JSON: decoded non-map root, ignoring');
      return {};
    } catch (e) {
      debugPrint('SYNC JSON: failed to decode JSON: ' + e.toString());
      return {};
    }
  }

  Future<void> _writeJsonFileByName(String folderId, String fileName, Map<String, dynamic> content) async {
    final client = await _getAuthenticatedClient();
    final driveApi = drive.DriveApi(client);
    final bytes = utf8.encode(jsonEncode(content));
    final tmp = await File('${Directory.systemTemp.path}/$fileName').create(recursive: true);
    await tmp.writeAsBytes(bytes, flush: true);
    final result = await driveApi.files.list(
      q: "name = '$fileName' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
    );
    if (result.files?.isNotEmpty ?? false) {
      final fileId = result.files!.first.id!;
      final media = drive.Media(tmp.openRead(), await tmp.length(), contentType: 'application/json');
      await driveApi.files.update(drive.File()..name = fileName, fileId, uploadMedia: media);
    } else {
      final f = drive.File()
        ..name = fileName
        ..parents = [folderId];
      final media = drive.Media(tmp.openRead(), await tmp.length(), contentType: 'application/json');
      await driveApi.files.create(f, uploadMedia: media);
    }
    try { await tmp.delete(); } catch (_) {}
  }

  Future<List<drive.File>> _listAllDeviceJsonFiles(String folderId) async {
    final client = await _getAuthenticatedClient();
    final driveApi = drive.DriveApi(client);
    final res = await driveApi.files.list(
      q: "'$folderId' in parents and trashed = false and mimeType != 'application/vnd.google-apps.folder' and name contains '.json'",
      spaces: 'drive',
      $fields: 'files(id, name, modifiedTime)',
    );
    return res.files ?? [];
  }

  Future<List<drive.File>> _listAllDeviceJsonFilesFromAnySyncFolder() async {
    final client = await _getAuthenticatedClient();
    final driveApi = drive.DriveApi(client);
    // ابحث عن جميع المجلدات باسم "مزامنة" ثم اجمع كل ملفات .json منها
    final folders = await driveApi.files.list(
      q: "name = '$syncFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name)'
    );
    final List<drive.File> all = [];
    for (final f in (folders.files ?? [])) {
      final fid = f.id;
      if (fid == null) continue;
      final res = await driveApi.files.list(
        q: "'$fid' in parents and trashed = false and mimeType != 'application/vnd.google-apps.folder' and name contains '.json'",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime)'
      );
      all.addAll(res.files ?? []);
    }
    return all;
  }

  // واجهات عالية المستوى
  Future<String> ensureSyncFolder() => _ensureSyncFolderId();
  Future<String> getOwnDeviceJsonName() => _getDeviceJsonName();
  Future<Map<String, dynamic>> readDeviceJson(String folderId, String fileName) => _readJsonFileByName(folderId, fileName);
  Future<void> writeDeviceJson(String folderId, String fileName, Map<String, dynamic> content) => _writeJsonFileByName(folderId, fileName, content);
  Future<List<drive.File>> listDeviceJsons(String folderId) => _listAllDeviceJsonFilesFromAnySyncFolder();

  // فحص وجود ملف المزامنة على Drive وحالة محتواه
  Future<Map<String, dynamic>> getSyncFileStatus() async {
    try {
      final folderId = await _ensureSyncFolderId();
      final deviceId = await _getStableDeviceIdPrefix();
      final fileName = '${deviceId}.json';
      
      final client = await _getAuthenticatedClient();
      final driveApi = drive.DriveApi(client);
      final files = await driveApi.files.list(
        q: "name = '$fileName' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );
      
      if (files.files?.isEmpty ?? true) {
        return {'exists': false, 'is_empty': false};
      }
      
      // فحص محتوى الملف
      final fileData = await _readJsonFileByName(folderId, fileName);
      final isEmpty = fileData['transactions']?.isEmpty ?? true;
      
      return {
        'exists': true,
        'is_empty': isEmpty,
        'status': fileData['status'] ?? 'normal'
      };
    } catch (e) {
      print('Error checking sync file status: $e');
      return {'exists': false, 'is_empty': false};
    }
  }

  // نظام المزامنة المحسن - يتحقق من وجود الملف على Drive وحالة محتواه
  Future<Map<String, dynamic>> getTransactionsToSync() async {
    final db = DatabaseService();
    
    // فحص حالة ملف المزامنة على Drive
    final fileStatus = await getSyncFileStatus();
    final fileExists = fileStatus['exists'] as bool;
    final fileIsEmpty = fileStatus['is_empty'] as bool;
    
    print('SYNC: File exists: $fileExists, is empty: $fileIsEmpty');
    
    // إذا لم يوجد الملف على Drive، نعيد تعيين حالة isUploaded
    if (!fileExists) {
      await resetUploadStatusForMissingFile();
    }
    
    final transactions = await db.getTransactionsForSync(); // 🔄 Use new method name
    
    // 🔄 الحصول على العملاء للمزامنة
    final customersToSync = await db.getCustomersToSync();
    
    // فلترة المعاملات بناءً على حالة الملف
    final transactionsToSync = transactions.where((t) {
      if (t['transaction_uuid'] == null) return false;
      
      // إذا لم يوجد الملف على Drive، نرفع جميع المعاملات
      if (!fileExists) {
        return true;
      }
      
      // إذا كان الملف فارغاً، لا نرفع أي معاملة
      if (fileIsEmpty) {
        return false;
      }
      
      // إذا وجد الملف وليس فارغاً، نرفع فقط التي لم يتم قراءتها من أجهزة أخرى
      // ولكن نرفع المعاملات التي أنشأناها نحن حتى لو تم قراءتها
      final isUploaded = (t['is_uploaded'] as int?) == 1;
      final isReadByOthers = (t['is_read_by_others'] as int?) == 1;
      final isCreatedByMe = (t['is_created_by_me'] as int?) == 1;
      
      return isUploaded && (!isReadByOthers || isCreatedByMe);
    }).toList();
    
    print('SYNC: Transactions to sync: ${transactionsToSync.length}');
    print('SYNC: Customers to sync: ${customersToSync.length}');
    
    return {
      'transactions': transactionsToSync, // هي بالفعل Maps الآن
      'customers': customersToSync.map((c) => c.toMap()).toList(), // 🔄 إضافة العملاء
      'device_id': await _getStableDeviceIdPrefix(),
      'sync_timestamp': DateTime.now().toUtc().toIso8601String(),
      'file_exists_on_drive': fileExists,
      'file_is_empty': fileIsEmpty,
    };
  }

  // تحديث حالة القراءة للمعاملات بعد قراءتها من جهاز آخر
  Future<void> markTransactionsAsRead(List<String> transactionUuids) async {
    if (transactionUuids.isEmpty) return;
    final db = DatabaseService();
    final placeholders = List.filled(transactionUuids.length, '?').join(',');
    await db.database.then((db) => db.rawUpdate(
      'UPDATE transactions SET is_read_by_others = 1 WHERE transaction_uuid IN ($placeholders)',
      transactionUuids,
    ));
  }

  // إعادة تعيين حالة isUploaded للمعاملات عند عدم وجود الملف على Drive
  Future<void> resetUploadStatusForMissingFile() async {
    final db = DatabaseService();
    await db.database.then((db) => db.rawUpdate(
      'UPDATE transactions SET is_uploaded = 0 WHERE is_uploaded = 1',
    ));
    print('SYNC: Reset upload status for all transactions due to missing file on Drive');
  }

  // نظام Heartbeat للتحقق من سلامة المزامنة
  Future<void> updateSyncHeartbeat() async {
    final folderId = await _ensureSyncFolderId();
    final deviceId = await _getStableDeviceIdPrefix();
    final heartbeatData = {
      'device_id': deviceId,
      'last_sync': DateTime.now().toUtc().toIso8601String(),
      'version': '1.0',
    };
    await _writeJsonFileByName(folderId, '${deviceId}_heartbeat.json', heartbeatData);
  }

  Future<Map<String, dynamic>?> getLastSyncHeartbeat() async {
    final folderId = await _ensureSyncFolderId();
    final deviceId = await _getStableDeviceIdPrefix();
    return await _readJsonFileByName(folderId, '${deviceId}_heartbeat.json');
  }


  // نظام Transaction Receipt - الحل الأكثر موثوقية
  // عند قراءة معاملة من جهاز آخر، نرسل إيصال تأكيد
  Future<void> sendTransactionReceipts(List<String> transactionUuids, String fromDeviceId) async {
    if (transactionUuids.isEmpty) return;
    
    final folderId = await _ensureSyncFolderId();
    final deviceId = await _getStableDeviceIdPrefix();
    final receiptData = {
      'from_device': deviceId,
      'to_device': fromDeviceId,
      'transaction_uuids': transactionUuids,
      'receipt_timestamp': DateTime.now().toUtc().toIso8601String(),
      'type': 'transaction_receipt',
    };
    
    final receiptFileName = '${deviceId}_receipt_${DateTime.now().millisecondsSinceEpoch}.json';
    await _writeJsonFileByName(folderId, receiptFileName, receiptData);
  }

  // معالجة الإيصالات الواردة وتحديث حالة المعاملات
  Future<void> processIncomingReceipts() async {
    final folderId = await _ensureSyncFolderId();
    final deviceId = await _getStableDeviceIdPrefix();
    
    // البحث عن الإيصالات الموجهة لهذا الجهاز
    final client = await _getAuthenticatedClient();
    final driveApi = drive.DriveApi(client);
    final receipts = await driveApi.files.list(
      q: "'$folderId' in parents and trashed = false and name contains 'receipt' and name contains '$deviceId'",
      spaces: 'drive',
    );
    
    for (final receiptFile in receipts.files ?? []) {
      try {
        final receiptData = await _readJsonFileByName(folderId, receiptFile.name!);
        if (receiptData['to_device'] == deviceId && receiptData['transaction_uuids'] != null) {
          final uuids = List<String>.from(receiptData['transaction_uuids']);
          await markTransactionsAsRead(uuids);
          
          // حذف الإيصال بعد معالجته
          await driveApi.files.delete(receiptFile.id!);
        }
      } catch (e) {
        print('Error processing receipt ${receiptFile.name}: $e');
      }
    }
  }

  // مزامنة شاملة مع نظام الإيصالات
  Future<Map<String, dynamic>> performFullSync() async {
    try {
      // 1. معالجة الإيصالات الواردة أولاً
      await processIncomingReceipts();
      
      // 2. الحصول على المعاملات المراد مزامنتها (مع فحص وجود الملف)
      final syncData = await getTransactionsToSync();
      
      // 3. رفع المعاملات الجديدة (أو ملف فارغ إذا لم توجد معاملات)
      final folderId = await _ensureSyncFolderId();
      final deviceId = await _getStableDeviceIdPrefix();
      final fileName = '${deviceId}.json';
      
      if (syncData['transactions'].isEmpty) {
        // إذا لم توجد معاملات، نرفع ملف فارغ
        final emptyData = {
          'transactions': <Map<String, dynamic>>[],
          'device_id': deviceId,
          'sync_timestamp': DateTime.now().toUtc().toIso8601String(),
          'file_exists_on_drive': true,
          'status': 'empty'
        };
        await _writeJsonFileByName(folderId, fileName, emptyData);
        print('SYNC: Uploading empty file - no transactions to sync');
      } else {
        await _writeJsonFileByName(folderId, fileName, syncData);
        print('SYNC: Uploading ${syncData['transactions'].length} transactions and ${syncData['customers'].length} customers');
        
        // 🔄 بعد الرفع الناجح، نحدث حالة العملاء
        if (syncData['customers'] != null) {
          final customersList = syncData['customers'] as List;
          final uuids = customersList.map((c) => c['sync_uuid'] as String?).whereType<String>().toList();
          final db = DatabaseService(); 
          await db.markCustomersAsSynced(uuids);
        }
      }
      
      // 4. تحديث Heartbeat
      await updateSyncHeartbeat();
      
      // 5. قراءة المعاملات من الأجهزة الأخرى
      final db = DatabaseService(); // نحتاج DB هنا لإدراج العملاء
      final otherDevices = await _listAllDeviceJsonFilesFromAnySyncFolder();
      final List<String> readTransactionUuids = [];
      
      for (final deviceFile in otherDevices) {
        if (deviceFile.name!.contains(deviceId)) continue; // تجاهل ملفاتنا
        

        try {
            final deviceData = await _readJsonFileByName(folderId, deviceFile.name!);
            
            // 🔄 1. معالجة العملاء أولاً (لضمان وجودهم قبل إضافة الديون)
            if (deviceData['customers'] != null) {
              final customers = List<Map<String, dynamic>>.from(deviceData['customers']);
              for (final cData in customers) {
               try {
                  await db.insertImportedCustomer(Customer.fromMap(cData));
               } catch (e) {
                 print('SYNC ERROR processing customer: $e');
               }
              }
              print('SYNC: Processed ${customers.length} imported customers');
            }

            // 2. معالجة المعاملات
            if (deviceData['transactions'] != null) {
              final transactions = List<Map<String, dynamic>>.from(deviceData['transactions']);
              for (final tx in transactions) {
                final uuid = tx['transaction_uuid'] as String?;
                if (uuid != null) {
                  readTransactionUuids.add(uuid);
                  // إدراج المعاملة في قاعدة البيانات المحلية
                  await _insertTransactionFromSync(tx);
                }
              }
            }
        } catch (e) {
          print('Error reading device file ${deviceFile.name}: $e');
        }
      }
      
      // 6. إرسال إيصالات للمعاملات المقروءة
      if (readTransactionUuids.isNotEmpty) {
        final otherDeviceIds = otherDevices
            .where((f) => !f.name!.contains(deviceId))
            .map((f) => f.name!.split('_')[0])
            .toSet();
        
        for (final otherDeviceId in otherDeviceIds) {
          await sendTransactionReceipts(readTransactionUuids, otherDeviceId);
        }
      }
      
      // 7. تحديث حالة المعاملات المقروءة بدلاً من حذفها
      if (readTransactionUuids.isNotEmpty) {
        await _markTransactionsAsReadFromSync(readTransactionUuids);
      }
      
      return {
        'success': true,
        'uploaded_count': syncData['transactions'].length,
        'downloaded_count': readTransactionUuids.length,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
    }
  }

  // إدراج معاملة من المزامنة في قاعدة البيانات المحلية
  // ✅ تم إصلاح: إعادة حساب رصيد العميل بعد إدراج المعاملة
  // 🔄 تم إضافة: آلية إعادة المحاولة (Retry) لتفادي قفل قاعدة البيانات
  Future<void> _insertTransactionFromSync(Map<String, dynamic> txData, {int retryCount = 0}) async {
    const int maxRetries = 3;
    try {
      final db = DatabaseService();

      
      // 🔄 تصحيح معرف العميل باستخدام UUID للتأكد من ربط الدين بالشخص الصحيح
      if (txData['customer_sync_uuid'] != null) {
        final localCustomerId = await db.findCustomerIdBySyncUuid(txData['customer_sync_uuid']);
        if (localCustomerId != null) {
          txData['customer_id'] = localCustomerId;
        } else {
           print('SYNC WARNING: Customer UUID ${txData['customer_sync_uuid']} not found locally even after import.');
           // يمكن هنا إضافة منطق استرجاع (Fallback) أو تخطي
        }
      }
      
      final transaction = DebtTransaction.fromMap(txData);
    
    // التحقق من وجود المعاملة محلياً
    final existing = await db.database.then((d) => d.query(
      'transactions',
      where: 'transaction_uuid = ?',
      whereArgs: [transaction.transactionUuid],
    ));
    
    if (existing.isEmpty) {
      try {
        // 1. إدراج المعاملة الجديدة
        await db.insertDebtTransaction(transaction);
        
        // 2. ✅ إعادة حساب رصيد العميل من جميع المعاملات
        await db.recalculateAndApplyCustomerDebt(transaction.customerId);
        
        // 3. ✅ إعادة حساب أرصدة المعاملات (قبل/بعد) للترتيب الصحيح
        await db.recalculateCustomerTransactionBalances(transaction.customerId);
        
        print('SYNC: تم إدراج معاملة وتحديث رصيد العميل ${transaction.customerId}');
      } catch (e) {
        print('SYNC ERROR: فشل إدراج معاملة من المزامنة: $e');
        rethrow;
      }
    }
    } catch (e) {
      // 🔄 محاولة إعادة المحاولة عند قفل قاعدة البيانات
      if (retryCount < maxRetries && e.toString().toLowerCase().contains('database is locked')) {
        print('SYNC: Database locked, retrying insert in 500ms... (Attempt ${retryCount + 1})');
        await Future.delayed(const Duration(milliseconds: 500));
        await _insertTransactionFromSync(txData, retryCount: retryCount + 1);
      } else {
        rethrow;
      }
    }
  }

  // تحديث حالة المعاملات المقروءة بدلاً من حذفها
  Future<void> _markTransactionsAsReadFromSync(List<String> transactionUuids) async {
    if (transactionUuids.isEmpty) return;
    
    final db = DatabaseService();
    final placeholders = List.filled(transactionUuids.length, '?').join(',');
    
    // تحديث حالة المعاملات المقروءة بدلاً من حذفها
    final updatedCount = await db.database.then((db) => db.rawUpdate(
      'UPDATE transactions SET is_read_by_others = 1 WHERE transaction_uuid IN ($placeholders)',
      transactionUuids,
    ));
    
    print('SYNC: Marked $updatedCount transactions as read from sync');
  }
}


