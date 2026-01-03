// lib/services/firebase_sync/firebase_auth_service.dart
// خدمة المصادقة لـ Firebase - تستخدم REST API + Firebase Auth SDK
// يتم إنشاء حساب تلقائي فريد لكل جهاز

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FirebaseAuthService {
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();
  factory FirebaseAuthService() => _instance;
  FirebaseAuthService._internal();

  // Firebase Browser API Key (no restrictions)
  static const String _apiKey = 'AIzaSyAkjRWpnT4MBop5DeJ8Rw8HPRl85oJop30';

  // مفاتيح التخزين
  static const String _emailKey = 'firebase_device_email';
  static const String _passwordKey = 'firebase_device_password';
  static const String _uidKey = 'firebase_device_uid';

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// الحصول على المستخدم الحالي
  User? get currentUser => _auth.currentUser;

  /// الحصول على UID الحالي
  String? get uid => _auth.currentUser?.uid;

  /// هل المستخدم مصادق عليه؟
  bool get isAuthenticated => _auth.currentUser != null;

  /// تسجيل الدخول التلقائي (Email/Password)
  Future<String?> signInAnonymously() async {
    try {
      // التحقق من وجود مستخدم حالي في Firebase Auth SDK
      if (_auth.currentUser != null) {
        print('✅ المستخدم مصادق عليه مسبقاً: ${_auth.currentUser!.uid}');
        return _auth.currentUser!.uid;
      }

      final prefs = await SharedPreferences.getInstance();

      // محاولة تسجيل الدخول بالحساب المحفوظ
      final savedEmail = prefs.getString(_emailKey);
      final savedPassword = prefs.getString(_passwordKey);

      if (savedEmail != null && savedPassword != null) {
        print('🔄 محاولة تسجيل الدخول بالحساب المحفوظ...');
        try {
          // استخدام REST API للحصول على Token
          final restResult =
              await _signInWithEmailREST(savedEmail, savedPassword);
          if (restResult != null) {
            // تسجيل الدخول في Firebase Auth SDK باستخدام Custom Token
            await _signInWithCustomToken(restResult['idToken']!);
            if (_auth.currentUser != null) {
              print('✅ تم تسجيل الدخول: ${_auth.currentUser!.uid}');
              return _auth.currentUser!.uid;
            }
          }
        } catch (e) {
          print('⚠️ فشل تسجيل الدخول بالحساب المحفوظ: $e');
        }
      }

      // إنشاء حساب جديد تلقائياً
      print('🔐 جاري إنشاء حساب جديد للجهاز...');
      final credentials = await _generateDeviceCredentials();

      // محاولة إنشاء حساب جديد عبر REST API
      var restResult =
          await _createAccountREST(credentials['email']!, credentials['password']!);

      if (restResult == null) {
        // ربما الحساب موجود، محاولة تسجيل الدخول
        print('📧 محاولة تسجيل الدخول بالحساب...');
        restResult =
            await _signInWithEmailREST(credentials['email']!, credentials['password']!);
      }

      if (restResult != null) {
        // حفظ بيانات الاعتماد
        await _saveCredentials(
          credentials['email']!,
          credentials['password']!,
          restResult['uid']!,
        );

        // تسجيل الدخول في Firebase Auth SDK
        await _signInWithCustomToken(restResult['idToken']!);

        if (_auth.currentUser != null) {
          print('✅ تم المصادقة بنجاح: ${_auth.currentUser!.uid}');
          return _auth.currentUser!.uid;
        }
      }

      return null;
    } catch (e) {
      print('❌ خطأ في المصادقة: $e');
      return null;
    }
  }

  /// تسجيل الدخول باستخدام Custom Token في Firebase Auth SDK
  Future<void> _signInWithCustomToken(String idToken) async {
    try {
      print('🔑 محاولة تسجيل الدخول باستخدام Custom Token المباشر...');
      await _auth.signInWithCustomToken(idToken);
      print('✅ نجح تسجيل الدخول باستخدام Custom Token المباشر');
      return;
    } catch (tokenError) {
      print('⚠️ فشل تسجيل الدخول المباشر بالتوكن: $tokenError');
      print('🔄 الرجوع لمحاولة البريد/الكلمة...');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString(_emailKey);
      final password = prefs.getString(_passwordKey);

      if (email != null && password != null) {
        try {
          // المحاولة باستخدام signInWithCredential - الأكثر استقراراً على ويندوز
          final credential = EmailAuthProvider.credential(email: email, password: password);
          await _auth.signInWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'user-not-found') {
            await _auth.createUserWithEmailAndPassword(
              email: email,
              password: password,
            );
          } else if (e.code == 'unknown-error') {
            print('⚠️ اكتشاف خطأ غير معروف - محاولة إعادة المحاولة...');
            await _auth.signOut();
            await Future.delayed(const Duration(seconds: 1));
            // محاولة أخيرة بالبريد والكلمة مباشرة
            await _auth.signInWithEmailAndPassword(email: email, password: password);
          } else {
            rethrow;
          }
        }
      }
    } catch (e) {
      print('⚠️ خطأ في تسجيل الدخول SDK: $e');
    }
  }

  /// إنشاء حساب جديد عبر REST API
  Future<Map<String, String>?> _createAccountREST(
      String email, String password) async {
    try {
      final url =
          'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'uid': data['localId'],
          'idToken': data['idToken'],
          'refreshToken': data['refreshToken'],
        };
      } else {
        final error = jsonDecode(response.body);
        final errorCode = error['error']?['message'] ?? 'UNKNOWN';
        if (errorCode != 'EMAIL_EXISTS') {
          print('⚠️ خطأ إنشاء الحساب: $errorCode');
        }
        return null;
      }
    } catch (e) {
      print('❌ خطأ في الاتصال: $e');
      return null;
    }
  }

  /// تسجيل الدخول عبر REST API
  Future<Map<String, String>?> _signInWithEmailREST(
      String email, String password) async {
    try {
      final url =
          'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$_apiKey';

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'returnSecureToken': true,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'uid': data['localId'],
          'idToken': data['idToken'],
          'refreshToken': data['refreshToken'],
        };
      } else {
        final error = jsonDecode(response.body);
        final errorCode = error['error']?['message'] ?? 'UNKNOWN';
        print('⚠️ خطأ تسجيل الدخول REST: $errorCode');
        return null;
      }
    } catch (e) {
      print('❌ خطأ في الاتصال: $e');
      return null;
    }
  }

  /// توليد بيانات اعتماد فريدة للجهاز
  Future<Map<String, String>> _generateDeviceCredentials() async {
    final prefs = await SharedPreferences.getInstance();

    // التحقق من وجود بيانات محفوظة
    final savedEmail = prefs.getString(_emailKey);
    final savedPassword = prefs.getString(_passwordKey);

    if (savedEmail != null && savedPassword != null) {
      return {'email': savedEmail, 'password': savedPassword};
    }

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final combined = '$timestamp-${base64Url.encode(bytes)}';
    final deviceId =
        sha256.convert(utf8.encode(combined)).toString().substring(0, 16);

    final email = 'device_$deviceId@debtbook.app';
    final salt = 'DebtBook2024SecureSalt';
    final password =
        sha256.convert(utf8.encode('$deviceId$salt')).toString().substring(0, 24);

    return {'email': email, 'password': password};
  }

  /// حفظ بيانات الاعتماد
  Future<void> _saveCredentials(
      String email, String password, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email);
    await prefs.setString(_passwordKey, password);
    await prefs.setString(_uidKey, uid);
  }

  /// تسجيل الخروج
  Future<void> signOut() async {
    try {
      await _auth.signOut();
      print('✅ تم تسجيل الخروج');
    } catch (e) {
      print('❌ خطأ في تسجيل الخروج: $e');
    }
  }

  /// مسح بيانات الاعتماد
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_passwordKey);
    await prefs.remove(_uidKey);
    await signOut();
    print('🗑️ تم مسح بيانات الاعتماد');
  }

  /// Stream لمراقبة تغييرات حالة المصادقة
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// التحقق من صلاحية الجلسة وتجديدها إذا لزم
  Future<bool> refreshSessionIfNeeded() async {
    if (_auth.currentUser == null) {
      final uid = await signInAnonymously();
      return uid != null;
    }
    return true;
  }

  /// معلومات التشخيص
  Future<Map<String, dynamic>> getAuthInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'isAuthenticated': isAuthenticated,
      'uid': uid,
      'sdkUser': _auth.currentUser?.uid,
      'savedEmail': prefs.getString(_emailKey),
    };
  }
}

/// Singleton للوصول السهل
class FirebaseAuthInstance {
  static FirebaseAuthService? _instance;

  static FirebaseAuthService get() {
    _instance ??= FirebaseAuthService();
    return _instance!;
  }
}
