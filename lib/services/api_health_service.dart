// services/api_health_service.dart
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// خدمة اختبار صحة Gemini API Keys وترتيبها حسب السرعة
/// تعمل في الخلفية بدون إزعاج المستخدم
class ApiHealthService {
  static final ApiHealthService _instance = ApiHealthService._internal();
  factory ApiHealthService() => _instance;
  ApiHealthService._internal();

  // ترتيب مفاتيح Gemini حسب السرعة
  final Map<String, int> _keyRanking = {};
  
  // المفتاح النشط حالياً
  int _activeKeyIndex = 0;
  
  // مراقب الاتصال
  StreamSubscription? _connectivitySubscription;
  
  Map<String, int> get keyRanking => _keyRanking;
  int get activeKeyIndex => _activeKeyIndex;

  /// بدء مراقبة الاتصال والاختبار
  void startMonitoring() {
    // اختبار فوري عند البدء
    _testIfConnected();
    
    // مراقبة تغيرات الاتصال
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        // تم الاتصال بالإنترنت
        print('🌐 تم الاتصال بالإنترنت - بدء اختبار API Keys...');
        _testAllGeminiKeys();
      }
    });
  }

  /// إيقاف المراقبة
  void stopMonitoring() {
    _connectivitySubscription?.cancel();
  }

  /// اختبار إذا كان متصلاً
  Future<void> _testIfConnected() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isNotEmpty && results.first != ConnectivityResult.none) {
        print('🌐 الإنترنت متصل - بدء اختبار API Keys...');
        await _testAllGeminiKeys();
      } else {
        print('⚠️ لا يوجد إنترنت - سيتم الاختبار عند الاتصال');
      }
    } catch (e) {
      print('⚠️ خطأ في فحص الاتصال: $e');
    }
  }

  /// اختبار جميع مفاتيح Gemini وترتيبها
  Future<void> _testAllGeminiKeys() async {
    final keys = [
      {'name': 'gemini_1', 'key': dotenv.env['GEMINI_API_KEY'] ?? ''},
      {'name': 'gemini_2', 'key': dotenv.env['GEMINI_API_KEY_2'] ?? ''},
      {'name': 'gemini_3', 'key': dotenv.env['GEMINI_API_KEY_3'] ?? ''},
      {'name': 'gemini_4', 'key': dotenv.env['GEMINI_API_KEY_4'] ?? ''},
    ];

    final results = <String, int>{};

    for (final keyInfo in keys) {
      final name = keyInfo['name'] as String;
      final key = keyInfo['key'] as String;
      
      if (key.isEmpty) continue;
      
      final speed = await _testGeminiKey(key);
      if (speed > 0) {
        results[name] = speed;
        print('✅ $name: ${speed}ms');
      } else {
        print('❌ $name: فشل');
      }
    }

    // ترتيب حسب السرعة
    final sorted = results.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    _keyRanking.clear();
    for (int i = 0; i < sorted.length; i++) {
      _keyRanking[sorted[i].key] = i + 1;
    }

    // تحديد الأسرع
    if (sorted.isNotEmpty) {
      final bestKey = sorted.first.key;
      _activeKeyIndex = int.parse(bestKey.split('_')[1]) - 1;
      print('🏆 أفضل مفتاح Gemini: ${sorted.first.key} (${sorted.first.value}ms)');
    }

    // حفظ الترتيب
    await _saveRanking();
  }

  /// اختبار مفتاح Gemini
  Future<int> _testGeminiKey(String apiKey) async {
    try {
      final stopwatch = Stopwatch()..start();
      
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': 'ping'}]}],
          'generationConfig': {'maxOutputTokens': 1},
        }),
      ).timeout(const Duration(seconds: 10));

      stopwatch.stop();
      
      if (response.statusCode == 200) {
        return stopwatch.elapsedMilliseconds;
      }
      return -1;
    } catch (e) {
      return -1;
    }
  }

  /// حفظ الترتيب
  Future<void> _saveRanking() async {
    // يمكن حفظه في SharedPreferences
  }

  /// الحصول على أفضل مفتاح
  String? getBestKey() {
    switch (_activeKeyIndex) {
      case 0:
        return dotenv.env['GEMINI_API_KEY'];
      case 1:
        return dotenv.env['GEMINI_API_KEY_2'];
      case 2:
        return dotenv.env['GEMINI_API_KEY_3'];
      case 3:
        return dotenv.env['GEMINI_API_KEY_4'];
      default:
        return dotenv.env['GEMINI_API_KEY'];
    }
  }

  /// الحصول على فهرس المفتاح النشط (0, 1, 2)
  int getActiveKeyIndex() => _activeKeyIndex;
}
