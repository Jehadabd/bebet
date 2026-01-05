// lib/services/firebase_sync/device_snapshot_service.dart
// خدمة إدارة ملفات Device Snapshot لنظام أمان المزامنة 100%

import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import '../database_service.dart';
import 'firebase_sync_config.dart';

/// خدمة إدارة ملفات Device Snapshot على Firebase
/// كل جهاز لديه ملف خاص به يحتوي على:
/// - إجمالي الديون
/// - أرصدة جميع العملاء
/// - آخر 10 عمليات
/// - checksums للتحقق السريع
class DeviceSnapshotService {
  static DeviceSnapshotService? _instance;
  static DeviceSnapshotService get instance {
    _instance ??= DeviceSnapshotService._();
    return _instance!;
  }
  
  DeviceSnapshotService._();
  
  final DatabaseService _db = DatabaseService();
  FirebaseFirestore? _firestore;
  String? _deviceId;
  String? _groupId;
  String? _deviceName;
  DateTime? _onlineSince;
  bool _isInitialized = false;
  
  // Stream للتحديثات من أجهزة أخرى
  StreamSubscription? _remoteSnapshotSubscription;
  final _remoteSnapshotController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get remoteSnapshotStream => _remoteSnapshotController.stream;
  
  /// تهيئة الخدمة
  Future<void> initialize({
    required FirebaseFirestore firestore,
    required String deviceId,
    required String groupId,
    String? deviceName,
  }) async {
    _firestore = firestore;
    _deviceId = deviceId;
    _groupId = groupId;
    _deviceName = deviceName ?? 'جهاز غير مسمى';
    _onlineSince = DateTime.now().toUtc();
    _isInitialized = true;
    
    // بدء الاستماع لتحديثات الأجهزة الأخرى
    _startListeningToRemoteSnapshots();
    
    // تحديث الـ snapshot مباشرة
    await updateSnapshot();
    
    print('✅ تم تهيئة DeviceSnapshotService');
  }
  
  /// إيقاف الخدمة
  void dispose() {
    _remoteSnapshotSubscription?.cancel();
    _remoteSnapshotController.close();
    _isInitialized = false;
    _onlineSince = null;
  }
  
  /// تحديث وقت الاتصال (عند انقطاع الإنترنت وعودته)
  void resetOnlineSince() {
    _onlineSince = DateTime.now().toUtc();
    print('🔄 تم تصفير وقت الاتصال: $_onlineSince');
  }
  
  /// الحصول على وقت الاتصال
  DateTime? get onlineSince => _onlineSince;
  
  /// حساب مدة الاتصال بالثواني
  int get connectionDurationSeconds {
    if (_onlineSince == null) return 0;
    return DateTime.now().toUtc().difference(_onlineSince!).inSeconds;
  }
  
  /// هل مر 15 دقيقة على الاتصال؟
  bool get hasBeenOnlineFor15Minutes => connectionDurationSeconds >= 900; // 15 * 60
  
  /// تطبيع اسم العميل (إزالة الفواصل والمسافات الزائدة)
  String normalizeCustomerName(String name) {
    return name
        .trim()
        .replaceAll(',', '')
        .replaceAll('،', '') // فاصلة عربية
        .replaceAll('\t', ' ')
        .replaceAll(RegExp(r'\s+'), ' '); // مسافات متعددة → مسافة واحدة
  }
  
  /// تحديث الـ Snapshot على Firebase
  /// يُستدعى بعد كل عملية (إضافة دين/تسديد/تعديل/حذف)
  Future<void> updateSnapshot() async {
    if (!_isInitialized || _firestore == null || _groupId == null || _deviceId == null) {
      return;
    }
    
    try {
      final db = await _db.database;
      
      // 1. جلب جميع العملاء مع أرصدتهم
      final customers = await db.query(
        'customers',
        columns: ['name', 'current_total_debt', 'sync_uuid'],
        where: 'is_deleted IS NULL OR is_deleted = 0',
      );
      
      // 2. حساب الإحصائيات
      double totalDebts = 0;
      final customerBalances = <String, double>{};
      final customersList = <String>[]; // لحساب checksum
      
      for (final customer in customers) {
        final name = normalizeCustomerName(customer['name'] as String? ?? '');
        final balance = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;
        
        if (name.isNotEmpty) {
          customerBalances[name] = balance;
          customersList.add(name);
          totalDebts += balance;
        }
      }
      
      // 3. جلب عدد عمليات الإضافة والتسديد
      final debtOpsResult = await db.rawQuery('''
        SELECT COUNT(*) as count FROM transactions 
        WHERE (is_deleted IS NULL OR is_deleted = 0)
        AND amount_changed > 0
      ''');
      final paymentOpsResult = await db.rawQuery('''
        SELECT COUNT(*) as count FROM transactions 
        WHERE (is_deleted IS NULL OR is_deleted = 0)
        AND amount_changed < 0
      ''');
      
      final totalDebtOperations = (debtOpsResult.first['count'] as int?) ?? 0;
      final totalPaymentOperations = (paymentOpsResult.first['count'] as int?) ?? 0;
      
      // 4. جلب آخر 10 معاملات
      final lastTransactions = await db.rawQuery('''
        SELECT t.amount_changed, t.transaction_date, t.transaction_type, c.name as customer_name
        FROM transactions t
        LEFT JOIN customers c ON t.customer_id = c.id
        WHERE (t.is_deleted IS NULL OR t.is_deleted = 0)
        ORDER BY t.created_at DESC
        LIMIT 10
      ''');
      
      final lastOperations = lastTransactions.map((tx) {
        return {
          'customer': normalizeCustomerName(tx['customer_name'] as String? ?? ''),
          'type': (tx['amount_changed'] as num? ?? 0) >= 0 ? 'debt' : 'payment',
          'amount': (tx['amount_changed'] as num?)?.toDouble().abs() ?? 0,
          'time': tx['transaction_date'],
        };
      }).toList();
      
      // 5. حساب checksums
      customersList.sort(); // ترتيب أبجدي للاتساق
      final customersListChecksum = _calculateChecksum(customersList.join('|'));
      
      final balancesData = customerBalances.entries
          .map((e) => '${e.key}:${e.value}')
          .toList()
        ..sort();
      final balancesChecksum = _calculateChecksum(balancesData.join('|'));
      
      // 6. رفع الـ Snapshot إلى Firebase
      final snapshot = {
        'deviceId': _deviceId,
        'deviceName': _deviceName,
        'onlineSince': _onlineSince?.toIso8601String(),
        'lastUpdatedAt': DateTime.now().toUtc().toIso8601String(),
        'totalDebts': totalDebts,
        'customersCount': customers.length,
        'totalDebtOperations': totalDebtOperations,
        'totalPaymentOperations': totalPaymentOperations,
        'customersListChecksum': customersListChecksum,
        'balancesChecksum': balancesChecksum,
        'customerBalances': customerBalances,
        'lastOperations': lastOperations,
      };
      
      await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('device_snapshots')
          .doc(_deviceId)
          .set(snapshot, SetOptions(merge: true));
      
      print('📸 تم تحديث Device Snapshot: إجمالي الديون = $totalDebts');
      
    } catch (e) {
      print('❌ خطأ في تحديث Snapshot: $e');
    }
  }
  
  /// حساب checksum SHA-256
  String _calculateChecksum(String data) {
    final bytes = utf8.encode(data);
    return sha256.convert(bytes).toString().substring(0, 16); // أول 16 حرف
  }
  
  /// جلب Snapshot لجهاز معين
  Future<Map<String, dynamic>?> getDeviceSnapshot(String deviceId) async {
    if (!_isInitialized || _firestore == null || _groupId == null) {
      return null;
    }
    
    try {
      final doc = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('device_snapshots')
          .doc(deviceId)
          .get();
      
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      print('❌ خطأ في جلب Snapshot للجهاز $deviceId: $e');
      return null;
    }
  }
  
  /// جلب جميع Snapshots للأجهزة الأخرى
  Future<List<Map<String, dynamic>>> getAllRemoteSnapshots() async {
    if (!_isInitialized || _firestore == null || _groupId == null) {
      return [];
    }
    
    try {
      final querySnapshot = await _firestore!
          .collection('sync_groups')
          .doc(_groupId)
          .collection('device_snapshots')
          .get();
      
      return querySnapshot.docs
          .where((doc) => doc.id != _deviceId) // استبعاد الجهاز الحالي
          .map((doc) => doc.data())
          .toList();
    } catch (e) {
      print('❌ خطأ في جلب Snapshots: $e');
      return [];
    }
  }
  
  /// الاستماع لتحديثات الأجهزة الأخرى
  void _startListeningToRemoteSnapshots() {
    if (_firestore == null || _groupId == null) return;
    
    _remoteSnapshotSubscription = _firestore!
        .collection('sync_groups')
        .doc(_groupId)
        .collection('device_snapshots')
        .snapshots()
        .listen((querySnapshot) {
      for (final change in querySnapshot.docChanges) {
        if (change.doc.id != _deviceId && change.doc.exists) {
          _remoteSnapshotController.add(change.doc.data()!);
        }
      }
    });
  }
  
  /// مقارنة Snapshot المحلي مع جهاز آخر
  /// يُرجع قائمة الاختلافات
  Future<List<BalanceMismatch>> compareWithRemoteDevice(String remoteDeviceId) async {
    final mismatches = <BalanceMismatch>[];
    
    final remoteSnapshot = await getDeviceSnapshot(remoteDeviceId);
    if (remoteSnapshot == null) {
      print('⚠️ لا يوجد Snapshot للجهاز: $remoteDeviceId');
      return mismatches;
    }
    
    // جلب البيانات المحلية
    final db = await _db.database;
    final customers = await db.query(
      'customers',
      columns: ['name', 'current_total_debt', 'sync_uuid'],
      where: 'is_deleted IS NULL OR is_deleted = 0',
    );
    
    final localBalances = <String, double>{};
    for (final customer in customers) {
      final name = normalizeCustomerName(customer['name'] as String? ?? '');
      final balance = (customer['current_total_debt'] as num?)?.toDouble() ?? 0.0;
      if (name.isNotEmpty) {
        localBalances[name] = balance;
      }
    }
    
    // جلب أرصدة الجهاز الآخر
    final remoteBalances = Map<String, dynamic>.from(
      remoteSnapshot['customerBalances'] ?? {},
    );
    
    // مقارنة الأرصدة
    final allCustomers = {...localBalances.keys, ...remoteBalances.keys};
    
    for (final customerName in allCustomers) {
      final localBalance = localBalances[customerName] ?? 0.0;
      final remoteBalance = (remoteBalances[customerName] as num?)?.toDouble() ?? 0.0;
      
      // مقارنة مع هامش خطأ صغير (0.01)
      if ((localBalance - remoteBalance).abs() > 0.01) {
        mismatches.add(BalanceMismatch(
          customerName: customerName,
          localBalance: localBalance,
          remoteBalance: remoteBalance,
          difference: (localBalance - remoteBalance).abs(),
          remoteDeviceId: remoteDeviceId,
          remoteDeviceName: remoteSnapshot['deviceName'] as String? ?? 'جهاز غير معروف',
        ));
      }
    }
    
    return mismatches;
  }
  
  /// جلب إجمالي الديون للجهاز الحالي
  Future<double> getLocalTotalDebts() async {
    final db = await _db.database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(current_total_debt), 0) as total
      FROM customers
      WHERE is_deleted IS NULL OR is_deleted = 0
    ''');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }
  
  /// التحقق من تطابق الإجماليات السريع
  Future<bool> quickTotalCheck(String remoteDeviceId) async {
    final remoteSnapshot = await getDeviceSnapshot(remoteDeviceId);
    if (remoteSnapshot == null) return true; // لا يوجد جهاز للمقارنة
    
    final localTotal = await getLocalTotalDebts();
    final remoteTotal = (remoteSnapshot['totalDebts'] as num?)?.toDouble() ?? 0.0;
    
    return (localTotal - remoteTotal).abs() < 0.01;
  }
}

/// نموذج اختلاف الرصيد
class BalanceMismatch {
  final String customerName;
  final double localBalance;
  final double remoteBalance;
  final double difference;
  final String remoteDeviceId;
  final String remoteDeviceName;
  
  BalanceMismatch({
    required this.customerName,
    required this.localBalance,
    required this.remoteBalance,
    required this.difference,
    required this.remoteDeviceId,
    required this.remoteDeviceName,
  });
  
  @override
  String toString() {
    return 'BalanceMismatch(customer: $customerName, local: $localBalance, remote: $remoteBalance, diff: $difference)';
  }
}
