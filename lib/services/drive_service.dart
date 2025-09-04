
// services/drive_service.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
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

  Future<bool> isSignedIn() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final isSignedIn = await _googleSignIn.isSignedIn();
        if (isSignedIn) {
          final account = await _googleSignIn.signInSilently();
          if (account == null) {
            await signOut();
            return false;
          }
        }
        return isSignedIn;
      } catch (_) {
        return false;
      }
    } else {
      final accessToken = await _storage.read(key: 'access_token');
      return accessToken != null;
    }
  }

  Future<bool> signIn() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) throw Exception('تم إلغاء تسجيل الدخول');
      final GoogleSignInAuthentication authData = await account.authentication;
      await _storage.write(key: 'access_token', value: authData.accessToken);
      await _storage.write(key: 'refresh_token', value: authData.idToken);
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
        await _storage.write(key: 'access_token', value: credentials.accessToken.data);
        await _storage.write(key: 'refresh_token', value: credentials.refreshToken ?? '');
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
      await _storage.delete(key: 'access_token');
      await _storage.delete(key: 'refresh_token');
    } catch (_) {}
  }

  Future<http.Client> _getAuthenticatedClient({bool forceRefresh = false}) async {
    final accessToken = await _storage.read(key: 'access_token');
    final refreshToken = await _storage.read(key: 'refresh_token');
    if (accessToken == null) throw Exception('لم يتم تسجيل الدخول');
    final credentials = auth.AccessCredentials(
      auth.AccessToken('Bearer', accessToken, DateTime.now().toUtc().add(const Duration(hours: 1))),
      refreshToken,
      _scopes,
    );
    if (forceRefresh && refreshToken != null) {
      final clientId = auth.ClientId(_clientIdString, _clientSecretString);
      final client = http.Client();
      try {
        final refreshed = await auth.refreshCredentials(clientId, credentials, client);
        await _storage.write(key: 'access_token', value: refreshed.accessToken.data);
        await _storage.write(key: 'refresh_token', value: refreshed.refreshToken ?? '');
        return auth.authenticatedClient(http.Client(), refreshed);
      } finally {
        client.close();
      }
    }
    return auth.authenticatedClient(http.Client(), credentials);
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
      if (e.toString().contains('invalid_token')) {
        final client = await _getAuthenticatedClient(forceRefresh: true);
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
      } else {
        throw Exception('فشل رفع الملف: $e');
      }
    }
  }

  Future<void> uploadDailyReport(File reportFile) async {
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
      if (files.length > 2) {
        for (int i = 2; i < files.length; i++) {
          final f = files[i];
          try {
            await driveApi.files.delete(f.id!);
          } catch (e) {
            debugPrint('Failed to delete old backup ${f.name}: $e');
          }
        }
      }
    } catch (e) {
      if (e.toString().contains('invalid_token')) {
        final client = await _getAuthenticatedClient(forceRefresh: true);
        final driveApi = drive.DriveApi(client);
        final macFolderId = await _getFolderId(specificName: await _getUniqueFolderName());
        final media = drive.Media(zipFile.openRead(), await zipFile.length(), contentType: 'application/zip');
        final driveFile = drive.File()
          ..name = zipFile.uri.pathSegments.last
          ..parents = [macFolderId!];
        await driveApi.files.create(driveFile, uploadMedia: media);

        final listRes = await driveApi.files.list(
          q: "'$macFolderId' in parents and mimeType != 'application/vnd.google-apps.folder' and trashed = false and name contains '.zip'",
          spaces: 'drive',
          $fields: 'files(id, name, createdTime)',
          orderBy: 'createdTime desc',
        );
        final files = listRes.files ?? [];
        if (files.length > 2) {
          for (int i = 2; i < files.length; i++) {
            final f = files[i];
            try {
              await driveApi.files.delete(f.id!);
            } catch (e) {
              debugPrint('Failed to delete old backup ${f.name}: $e');
            }
          }
        }
      } else {
        throw Exception('فشل رفع النسخة الاحتياطية: $e');
      }
    }
  }
}


