// lib/firebase_options.dart
// إعدادات Firebase للتطبيق
// تم إنشاؤها من google-services.json

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // إعدادات Android (من google-services.json)
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCpQ-XPAwh5D2O6Fr6dQy0_V2i8b9F8Qyg',
    appId: '1:269593160810:android:d8ad26bb9a35d4b5d42e13',
    messagingSenderId: '269593160810',
    projectId: 'debt-book-app-d7e74',
    storageBucket: 'debt-book-app-d7e74.firebasestorage.app',
  );

  // إعدادات Windows (نفس إعدادات Web)
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAkjRWpnT4MBop5DeJ8Rw8HPRl85oJop30',
    appId: '1:269593160810:web:843b889e7a4e8b62d42e13',
    messagingSenderId: '269593160810',
    projectId: 'debt-book-app-d7e74',
    storageBucket: 'debt-book-app-d7e74.firebasestorage.app',
    authDomain: 'debt-book-app-d7e74.firebaseapp.com',
    measurementId: 'G-FZPY0BR9SV',
  );

  // إعدادات Web
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAkjRWpnT4MBop5DeJ8Rw8HPRl85oJop30',
    appId: '1:269593160810:web:843b889e7a4e8b62d42e13',
    messagingSenderId: '269593160810',
    projectId: 'debt-book-app-d7e74',
    storageBucket: 'debt-book-app-d7e74.firebasestorage.app',
    authDomain: 'debt-book-app-d7e74.firebaseapp.com',
    measurementId: 'G-FZPY0BR9SV',
  );

  // إعدادات iOS (placeholder - تحتاج GoogleService-Info.plist)
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCpQ-XPAwh5D2O6Fr6dQy0_V2i8b9F8Qyg',
    appId: '1:269593160810:ios:debt_book_ios',
    messagingSenderId: '269593160810',
    projectId: 'debt-book-app-d7e74',
    storageBucket: 'debt-book-app-d7e74.firebasestorage.app',
    iosBundleId: 'com.example.debtBook',
  );

  // إعدادات macOS
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCpQ-XPAwh5D2O6Fr6dQy0_V2i8b9F8Qyg',
    appId: '1:269593160810:macos:debt_book_macos',
    messagingSenderId: '269593160810',
    projectId: 'debt-book-app-d7e74',
    storageBucket: 'debt-book-app-d7e74.firebasestorage.app',
    iosBundleId: 'com.example.debtBook',
  );

  // إعدادات Linux
  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyCpQ-XPAwh5D2O6Fr6dQy0_V2i8b9F8Qyg',
    appId: '1:269593160810:linux:debt_book_linux',
    messagingSenderId: '269593160810',
    projectId: 'debt-book-app-d7e74',
    storageBucket: 'debt-book-app-d7e74.firebasestorage.app',
  );
}
