
// services/drive_service.dart
import 'dart:io';
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

class DriveService {
  static final DriveService _instance = DriveService._internal();
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      drive.DriveApi.driveFileScope,
    ],
  );
  final _storage = const FlutterSecureStorage();

  // OAuth 2.0 Desktop credentials
  String get _clientIdString => dotenv.env['GOOGLE_CLIENT_ID'] ?? '';
  String get _clientSecretString => dotenv.env['GOOGLE_CLIENT_SECRET'] ?? '';
  String get _redirectUrlString => dotenv.env['GOOGLE_REDIRECT_URL'] ?? 'http://localhost';
  final _scopes = [drive.DriveApi.driveFileScope, 'email', 'profile'];

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
      return result.files!.first.id;
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
          ..parents = [folderId!];
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

  Future<void> uploadDailyReport(File reportFile) async {
    try {
      final client = await _getAuthenticatedClient();
      final driveApi = drive.DriveApi(client);
      final folderId = await _getFolderId();
      final existingFiles = await driveApi.files.list(
        q: "name = 'سجل الديون.pdf' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
      );
      if (existingFiles.files?.isNotEmpty ?? false) {
        final fileId = existingFiles.files!.first.id;
        final media = drive.Media(reportFile.openRead(), await reportFile.length());
        await driveApi.files.update(
          drive.File()..name = 'سجل الديون.pdf',
          fileId!,
          uploadMedia: media,
        );
      } else {
        final driveFile = drive.File()
          ..name = 'سجل الديون.pdf'
          ..parents = [folderId!];
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


