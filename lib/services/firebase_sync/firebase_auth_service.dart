// lib/services/firebase_sync/firebase_auth_service.dart
// خدمة المصادقة لـ Firebase - تستخدم REST API + Firebase Auth SDK
// يتم إنشاء حساب تلقائي فريد لكل جهاز

import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthService {
  static final FirebaseAuthService _instance = FirebaseAuthService._internal();
  factory FirebaseAuthService() => _instance;
  FirebaseAuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// الحصول على المستخدم الحالي
  User? get currentUser => _auth.currentUser;

  /// الحصول على UID الحالي
  String? get uid => _auth.currentUser?.uid;

  /// هل المستخدم مصادق عليه؟
  bool get isAuthenticated => _auth.currentUser != null;

  /// تسجيل الدخول المجهول (بسيط ومباشر)
  Future<String?> signInAnonymously() async {
    try {
      // التحقق مما إذا كان مسجلاً للدخول بالفعل
      if (_auth.currentUser != null) {
        print('✅ المستخدم مصادق عليه مسبقاً: ${_auth.currentUser!.uid}');
        return _auth.currentUser!.uid;
      }

      print('🔐 جاري تسجيل الدخول المجهول...');
      final userCredential = await _auth.signInAnonymously();
      
      if (userCredential.user != null) {
        print('✅ تم تسجيل الدخول بنجاح: ${userCredential.user!.uid}');
        return userCredential.user!.uid;
      }
      
      return null;
    } catch (e) {
      print('❌ خطأ في تسجيل الدخول المجهول: $e');
      return null;
    }
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
}

/// Singleton للوصول السهل
class FirebaseAuthInstance {
  static FirebaseAuthService? _instance;

  static FirebaseAuthService get() {
    _instance ??= FirebaseAuthService();
    return _instance!;
  }
}
