// lib/services/firebase_sync/live_match_service.dart
//
// مطابقة حية بين الأجهزة المتصلة — لا بين الجهاز والسحابة.
//
// الشرط: جهاز آخر متصل (نبضة حيّة) + موافقته على جلسة المطابقة.
// كل جهاز ينشر أرصدته المحلية الحالية عبر Firestore snapshots، والآخر
// يقارن: ديون/عدد معاملات هذا الجهاز ↔ ديون/عدد معاملات الجهاز الآخر.
//
// قاعدة حديدية: طابور إعادة الرفع لا يقبل إلا معاملات أنشأها هذا الجهاز.

import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/uuid_helper.dart';
import '../database_service.dart';
import '../database/core/database_helpers.dart';
import '../sync/sync_security.dart';
import 'firebase_sync_service.dart';
import 'reconciliation_service.dart' show ReconciliationService;

/// طلب مطابقة حية وارد من جهاز آخر.
class LiveMatchRequest {
  final String sessionId;
  final String initiatorId;
  final String initiatorName;
  final DateTime expiresAt;
  final int invitedCount;

  LiveMatchRequest({
    required this.sessionId,
    required this.initiatorId,
    required this.initiatorName,
    required this.expiresAt,
    required this.invitedCount,
  });

  Duration get remaining {
    final left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

/// صف مطابقة لعميل واحد: هذا الجهاز ↔ جهاز نظير متصل.
class LiveCustomerMatch {
  final String customerSyncUuid;
  final String customerName;
  final int localCustomerId;

  final double localDebt;
  final int localTxCount;
  final double localTxSum;

  final double peerDebt;
  final int peerTxCount;
  final double peerTxSum;
  final String peerDeviceName;

  final List<QueuedOwnedTx> ownedProblems;

  LiveCustomerMatch({
    required this.customerSyncUuid,
    required this.customerName,
    required this.localCustomerId,
    required this.localDebt,
    required this.localTxCount,
    required this.localTxSum,
    required this.peerDebt,
    required this.peerTxCount,
    required this.peerTxSum,
    required this.peerDeviceName,
    this.ownedProblems = const [],
  });

  bool get countsMatch => localTxCount == peerTxCount;
  bool get debtMatch => (localDebt - peerDebt).abs() <= 0.01;
  bool get txSumsMatch => (localTxSum - peerTxSum).abs() <= 0.01;
  bool get localConsistent => (localDebt - localTxSum).abs() <= 0.01;

  bool get isMatch => countsMatch && debtMatch && localConsistent;

  bool get hasOwnedProblems => ownedProblems.isNotEmpty;
  double get debtDifference => localDebt - peerDebt;

  List<String> get mismatchReasons {
    final r = <String>[];
    if (!countsMatch) {
      r.add('عدد المعاملات: هنا $localTxCount ≠ $peerDeviceName $peerTxCount');
    }
    if (!debtMatch) {
      r.add(
          'الدين: هنا ${localDebt.toStringAsFixed(0)} ≠ $peerDeviceName ${peerDebt.toStringAsFixed(0)}');
    }
    if (!localConsistent) {
      r.add('الرصيد المحلي لا يساوي مجموع معاملاته');
    }
    if (!txSumsMatch && countsMatch) {
      r.add('مجموع المعاملات يختلف رغم تساوي العدد');
    }
    return r;
  }
}

class QueuedOwnedTx {
  final String syncUuid;
  final String customerSyncUuid;
  final String customerName;
  final double amount;
  final String reason;

  QueuedOwnedTx({
    required this.syncUuid,
    required this.customerSyncUuid,
    required this.customerName,
    required this.amount,
    required this.reason,
  });
}

class LiveMatchSnapshot {
  final DateTime at;
  final double localTotalDebt;
  final double localTotalCredit;
  final int localCustomerCount;

  /// إجمالي ديون الجهاز النظير (نفس معادلة الملخص المالي).
  final double peerTotalDebt;
  final int peerCustomerCount;
  final String? peerDeviceName;
  final String? peerDeviceId;

  final List<LiveCustomerMatch> customers;
  final List<QueuedOwnedTx> uploadQueue;

  /// هل جلسة المطابقة الحية نشطة مع جهاز متصل؟
  final bool sessionActive;
  final bool peerStreamReady;
  final int onlineDeviceCount;
  final List<Map<String, dynamic>> onlineDevices;
  final String? statusMessage;
  final String? sessionId;
  final String sessionStatus;

  LiveMatchSnapshot({
    required this.at,
    required this.localTotalDebt,
    required this.localTotalCredit,
    required this.localCustomerCount,
    required this.peerTotalDebt,
    required this.peerCustomerCount,
    required this.peerDeviceName,
    required this.peerDeviceId,
    required this.customers,
    required this.uploadQueue,
    required this.sessionActive,
    required this.peerStreamReady,
    required this.onlineDeviceCount,
    required this.onlineDevices,
    this.statusMessage,
    this.sessionId,
    this.sessionStatus = '',
  });

  List<LiveCustomerMatch> get mismatches =>
      customers.where((c) => !c.isMatch).toList();

  int get otherDeviceCount =>
      onlineDevices.where((d) => d['isCurrentDevice'] != true).length;
}

class _PeerCustomer {
  final String name;
  final double debt;
  final int txCount;
  final double txSum;

  _PeerCustomer({
    required this.name,
    required this.debt,
    required this.txCount,
    required this.txSum,
  });
}

class _PeerState {
  final String deviceId;
  final String deviceName;
  final double totalDebt;
  final DateTime updatedAt;
  final Map<String, _PeerCustomer> customers;

  _PeerState({
    required this.deviceId,
    required this.deviceName,
    required this.totalDebt,
    required this.updatedAt,
    required this.customers,
  });
}

class LiveMatchService {
  static final LiveMatchService _instance = LiveMatchService._internal();
  factory LiveMatchService() => _instance;
  LiveMatchService._internal();

  static const String _sessionsCol = 'live_match_sessions';
  static const String _peerStateCol = 'live_peer_state';
  static const Duration _inviteWindow = Duration(minutes: 2);
  static const Duration _peerFreshness = Duration(seconds: 45);

  final DatabaseService _db = DatabaseService();
  final FirebaseSyncService _sync = FirebaseSyncService();
  final ReconciliationService _devices = ReconciliationService();

  StreamSubscription<QuerySnapshot>? _sessionsSub;
  /// 📡 مستمع لكل جهاز مشارك (لا جهاز واحد): المطابقة بين كل الأجهزة.
  final Map<String, StreamSubscription<DocumentSnapshot>> _peerSubs = {};
  Timer? _publishTimer;
  Timer? _localRefreshTimer;

  String? _activeSessionId;
  String _sessionStatus = '';
  final Set<String> _handledSessions = {};

  /// آخر حالة منشورة من كل جهاز مشارك.
  final Map<String, _PeerState> _peers = {};
  /// كل الأجهزة المشاركة في الجلسة عدا هذا الجهاز.
  List<String> _peerIds = const [];

  /// أجهزة ذات بثّ حيّ حديث (خلال مهلة الحداثة).
  List<_PeerState> get _freshPeers => _peers.values
      .where((p) => _sync.now.difference(p.updatedAt) <= _peerFreshness)
      .toList();

  final Map<String, QueuedOwnedTx> _queue = {};

  final _snapshotController = StreamController<LiveMatchSnapshot>.broadcast();
  final _requestController = StreamController<LiveMatchRequest>.broadcast();
  final _showMatchScreenController = StreamController<String>.broadcast();
  final _peerNotificationController = StreamController<String>.broadcast();

  Stream<LiveMatchSnapshot> get snapshots => _snapshotController.stream;
  Stream<LiveMatchRequest> get onRequest => _requestController.stream;
  Stream<String> get onMatchScreenRequested => _showMatchScreenController.stream;
  Stream<String> get onPeerNotification => _peerNotificationController.stream;

  LiveMatchSnapshot? _last;
  LiveMatchSnapshot? get last => _last;

  bool get sessionActive =>
      _activeSessionId != null && _sessionStatus == 'active';

  FirebaseFirestore? get _fs => _sync.firestore;
  String? get _myId => _sync.deviceId;

  StreamSubscription<QuerySnapshot>? _commandsSub;

  /// يبدأ الاستماع لطلبات الجلسات فقط — لا مقارنة بلا جهاز متصل موافق.
  void start() {
    final fs = _fs;
    if (fs == null) {
      unawaited(_emitIdle('المزامنة غير مفعّلة'));
      return;
    }
    if (_sessionsSub != null) return;

    _sessionsSub = fs
        .collection(_sessionsCol)
        .where('status', whereIn: ['requesting', 'active'])
        .snapshots()
        .listen(_onSessions, onError: (e) => print('❌ جلسات المطابقة الحية: $e'));

    _startCommandsListener();

    _localRefreshTimer?.cancel();
    _localRefreshTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => recompute());

    unawaited(recompute());
    print('📡 جاهز لطلبات المطابقة الحية بين الأجهزة');
  }

  void stop() {
    _sessionsSub?.cancel();
    for (final sub in _peerSubs.values) {
      sub.cancel();
    }
    _peerSubs.clear();
    _commandsSub?.cancel();
    _publishTimer?.cancel();
    _localRefreshTimer?.cancel();
    _sessionsSub = null;
    _commandsSub = null;
    _publishTimer = null;
    _localRefreshTimer = null;
  }

  /// قائمة الأجهزة الحاضرة — نفس المصدر للعدّ وللزر وللقائمة (لا قوائم منفصلة).
  Future<List<Map<String, dynamic>>> getOnlineDevices() async {
    // 1) الكاش اللحظي من مستمع المزامنة (الأدق وهو حيّ أصلاً).
    final live = _sync.liveDevices;
    if (live.isNotEmpty) {
      final filtered = <Map<String, dynamic>>[];
      for (final d in live) {
        final isCurrent = d['isCurrentDevice'] == true;
        final isOnline = d['isOnline'] == true || d['isRealtimeSyncActive'] == true;
        if (!isCurrent && !isOnline) continue;
        filtered.add({
          'deviceId': d['deviceId'] ?? '',
          'deviceName': d['deviceName'] ?? 'جهاز غير معروف',
          'isCurrentDevice': isCurrent,
          'platform': d['platform'],
        });
      }
      // تأكد أن الجهاز الحالي موجود حتى لو تأخرت نَبضته لحظة.
      final myId = _myId;
      if (myId != null &&
          !filtered.any((d) => d['deviceId'] == myId)) {
        filtered.insert(0, {
          'deviceId': myId,
          'deviceName': 'هذا الجهاز',
          'isCurrentDevice': true,
        });
      }
      if (filtered.isNotEmpty) return filtered;
    }

    // 2) احتياط: قراءة مباشرة من مجموعة devices.
    return _devices.getOnlineDevices();
  }

  /// يبدأ طلب مطابقة حية: يدعو كل الأجهزة الحاضرة، ولا تُفعَّل المقارنة
  /// إلا بعد موافقتهم ووجود بث حيّ من جهاز نظير.
  Future<String> requestLiveMatch() async {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null) {
      throw Exception('المزامنة غير مفعّلة');
    }

    final online = await getOnlineDevices();
    final others =
        online.where((d) => d['isCurrentDevice'] != true).toList();
    if (others.isEmpty) {
      throw Exception(
          'لا يوجد جهاز آخر متصل الآن. المطابقة الحية تحتاج جهازاً متصلاً.');
    }

    final invited = online.map((d) => d['deviceId'] as String).toList();
    if (!invited.contains(myId)) invited.add(myId);

    String myName = 'هذا الجهاز';
    for (final d in online) {
      if (d['deviceId'] == myId) myName = d['deviceName'] as String? ?? myName;
    }

    final now = DateTime.now();
    final sessionId =
        'live_${now.millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    await fs.collection(_sessionsCol).doc(sessionId).set({
      'sessionId': sessionId,
      'initiatorId': myId,
      'initiatorName': myName,
      'createdAt': now.toIso8601String(),
      'expiresAt': now.add(_inviteWindow).toIso8601String(),
      'status': 'requesting',
      'invited': invited,
      'responses': {myId: 'accepted'},
    });

    _activeSessionId = sessionId;
    _sessionStatus = 'requesting';
    _handledSessions.add('req_$sessionId');
    _handledSessions.add('accepted_$sessionId');
    await recompute();
    return sessionId;
  }

  Future<void> respond(String sessionId, {required bool accept}) async {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null) return;

    // 🛡️ رفض جهاز واحد يستثنيه هو فقط؛ المطابقة تكمل بين الموافقين.
    await fs.collection(_sessionsCol).doc(sessionId).update({
      'responses.$myId': accept ? 'accepted' : 'rejected',
    });
    if (!accept) {
      await evaluateSession(sessionId);
    }

    if (accept) {
      _activeSessionId = sessionId;
      _sessionStatus = 'requesting';
      _handledSessions.add('req_$sessionId');
      _handledSessions.add('accepted_$sessionId');
      _showMatchScreenController.add(sessionId);
      await recompute();
      // تفعيل الجلسة فوراً إن وافق الجميع، دون انتظار مؤقت الجهاز البادئ.
      await evaluateSession(sessionId);
    }
  }

  /// يراجع الجلسة: عند موافقة الجميع تُفعَّل، وعند انتهاء المهلة تُلغى.
  Future<String> evaluateSession(String sessionId) async {
    final fs = _fs;
    if (fs == null) return 'expired';

    final ref = fs.collection(_sessionsCol).doc(sessionId);
    final snap = await ref.get();
    if (!snap.exists) return 'expired';

    final data = snap.data()!;
    final status = data['status'] as String? ?? '';
    if (status != 'requesting') return status;

    final invited = List<String>.from(data['invited'] as List? ?? []);
    final responses =
        Map<String, dynamic>.from(data['responses'] as Map? ?? {});
    final expiresAt =
        DateTime.tryParse(data['expiresAt'] as String? ?? '') ?? DateTime.now();

    // 🧮 المشاركون = كل من وافق. الجلسة تبدأ حين يردّ الجميع أو تنتهي المهلة،
    // بشرط وجود جهازين موافقين على الأقل (المُبادِر + جهاز آخر).
    final accepted =
        invited.where((id) => responses[id] == 'accepted').toList();
    final pending = invited.where((id) => !responses.containsKey(id)).toList();
    final expired = DateTime.now().isAfter(expiresAt);

    if (pending.isEmpty || expired) {
      if (accepted.length >= 2) {
        await ref.update({'status': 'active', 'participants': accepted});
        if (accepted.contains(_myId)) {
          _sessionStatus = 'active';
          await _enterActiveSession(sessionId, accepted);
        }
        return 'active';
      }
      final st = expired ? 'expired' : 'cancelled';
      await ref.update({'status': st});
      _sessionStatus = st;
      return st;
    }

    return 'requesting';
  }

  Future<void> endSession() async {
    final fs = _fs;
    final sessionId = _activeSessionId;
    if (fs != null && sessionId != null) {
      try {
        await fs.collection(_sessionsCol).doc(sessionId).update({
          'status': 'ended',
        });
      } catch (_) {}
    }
    await _leaveActiveSession();
    await recompute();
  }

  void _onSessions(QuerySnapshot snapshot) {
    final myId = _myId;
    if (myId == null) return;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) continue;

      final sessionId = doc.id;
      final status = data['status'] as String?;
      final invited = List<String>.from(data['invited'] as List? ?? []);
      if (!invited.contains(myId)) continue;

      final initiatorId = data['initiatorId'] as String?;
      final expiresAt =
          DateTime.tryParse(data['expiresAt'] as String? ?? '') ?? DateTime.now();

      if (status == 'requesting') {
        final responses =
            Map<String, dynamic>.from(data['responses'] as Map? ?? {});
        if (initiatorId == myId) continue;
        if (responses.containsKey(myId)) continue;
        if (DateTime.now().isAfter(expiresAt)) continue;
        if (!_handledSessions.add('req_$sessionId')) continue;

        _requestController.add(LiveMatchRequest(
          sessionId: sessionId,
          initiatorId: initiatorId ?? '',
          initiatorName: data['initiatorName'] as String? ?? 'جهاز آخر',
          expiresAt: expiresAt,
          invitedCount: invited.length,
        ));
      } else if (status == 'active') {
        // (لا فحص لمهلة الدعوة هنا: الجلسة قد تُفعَّل لحظة انتهاء المهلة)
        final participants =
            List<String>.from(data['participants'] as List? ?? invited);
        if (!participants.contains(myId)) continue; // رفضتُ ⇒ لستُ مشاركاً
        if (_activeSessionId == sessionId && _sessionStatus == 'active') {
          continue;
        }
        if (!_handledSessions.add('run_$sessionId')) continue;
        _activeSessionId = sessionId;
        _sessionStatus = 'active';
        unawaited(_enterActiveSession(sessionId, participants));
      } else if (status == 'cancelled' ||
          status == 'expired' ||
          status == 'ended') {
        if (_activeSessionId == sessionId) {
          unawaited(_leaveActiveSession());
        }
      }
    }
  }

  Future<void> _enterActiveSession(
      String sessionId, List<String> invited) async {
    final myId = _myId;
    if (myId == null) return;

    _activeSessionId = sessionId;
    _sessionStatus = 'active';

    // 📡 كل الأجهزة المشاركة نظراء (كان: أول جهاز فقط).
    _peerIds = invited.where((id) => id != myId && id.isNotEmpty).toList();
    if (_peerIds.isEmpty) {
      await _emitIdle('لا يوجد جهاز نظير في الجلسة');
      return;
    }

    await _publishLocalState();
    _publishTimer?.cancel();
    _publishTimer = Timer.periodic(
        const Duration(seconds: 3), (_) => _publishLocalState());

    for (final sub in _peerSubs.values) {
      await sub.cancel();
    }
    _peerSubs.clear();
    _peers.clear();
    for (final pid in _peerIds) {
      _peerSubs[pid] = _fs!
          .collection(_peerStateCol)
          .doc(pid)
          .snapshots()
          .listen((doc) => _onPeerState(pid, doc),
              onError: (e) => print('❌ بث النظير $pid: $e'));
    }

    // إظهار شاشة المطابقة فقط إذا تم بدء الجلسة أو قبولها محلياً في هذا التطبيق
    if (_handledSessions.contains('accepted_$sessionId') && !_showMatchScreenController.isClosed) {
      _showMatchScreenController.add(sessionId);
    }

    await recompute();
  }

  Future<void> _leaveActiveSession() async {
    _publishTimer?.cancel();
    _publishTimer = null;
    for (final sub in _peerSubs.values) {
      await sub.cancel();
    }
    _peerSubs.clear();
    _peers.clear();
    _peerIds = const [];
    _activeSessionId = null;
    _sessionStatus = '';

    // 🧹 امسح حالتنا المنشورة والأوامر المؤقتة حتى تظل مجلدات السحابة ناصعة ونظيفة
    final fs = _fs;
    final myId = _myId;
    if (fs != null && myId != null) {
      try {
        await fs.collection(_peerStateCol).doc(myId).delete();
      } catch (_) {}

      try {
        final pendingCmds = await fs.collection('live_match_commands').where('targetDeviceId', isEqualTo: myId).get();
        for (final doc in pendingCmds.docs) {
          await doc.reference.delete();
        }
      } catch (_) {}
    }
  }

  void _onPeerState(String peerId, DocumentSnapshot doc) {
    if (!doc.exists) {
      _peers.remove(peerId);
      unawaited(recompute());
      return;
    }
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return;

    final updatedAt =
        DateTime.tryParse(data['updatedAt'] as String? ?? '') ?? DateTime.now();
    // نبضة قديمة = الجهاز انقطع عن النشر.
    if (_sync.now.difference(updatedAt) > _peerFreshness) {
      _peers.remove(peerId);
      unawaited(recompute());
      return;
    }

    final raw =
        Map<String, dynamic>.from(data['customers'] as Map? ?? {});
    final customers = <String, _PeerCustomer>{};
    raw.forEach((uuid, v) {
      final m = Map<String, dynamic>.from(v as Map);
      customers[uuid] = _PeerCustomer(
        name: m['name'] as String? ?? '',
        debt: (m['debt'] as num?)?.toDouble() ?? 0.0,
        txCount: (m['txCount'] as num?)?.toInt() ?? 0,
        txSum: (m['txSum'] as num?)?.toDouble() ?? 0.0,
      );
    });

    _peers[peerId] = _PeerState(
      deviceId: data['deviceId'] as String? ?? doc.id,
      deviceName: data['deviceName'] as String? ?? 'جهاز آخر',
      totalDebt: (data['totalDebt'] as num?)?.toDouble() ?? 0.0,
      updatedAt: updatedAt,
      customers: customers,
    );
    unawaited(recompute());
  }

  /// ينشر الأرصدة المحلية الحالية للجهاز النظير عبر بث حيّ.
  Future<void> _publishLocalState() async {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null || !sessionActive) return;

    try {
      final local = await _readLocalCustomers();
      String myName = 'هذا الجهاز';
      final online = await getOnlineDevices();
      for (final d in online) {
        if (d['deviceId'] == myId) {
          myName = d['deviceName'] as String? ?? myName;
        }
      }

      final customersMap = <String, dynamic>{};
      for (final c in local.customers) {
        customersMap[c.syncUuid] = {
          'name': c.name,
          'debt': c.debt,
          'txCount': c.txCount,
          'txSum': c.txSum,
        };
      }

      await fs.collection(_peerStateCol).doc(myId).set({
        'deviceId': myId,
        'deviceName': myName,
        'totalDebt': local.totalDebt,
        'totalCredit': local.totalCredit,
        'customerCount': local.customers.length,
        'updatedAt': DateTime.now().toIso8601String(),
        'sessionId': _activeSessionId,
        'customers': customersMap,
      });
    } catch (e) {
      print('⚠️ فشل نشر حالة المطابقة الحية: $e');
    }
  }

  Future<({
    double totalDebt,
    double totalCredit,
    List<
        ({
          String syncUuid,
          String name,
          int id,
          double debt,
          int txCount,
          double txSum
        })> customers
  })> _readLocalCustomers() async {
    final db = await _db.database;

    final debtRow = await db.rawQuery('''
      SELECT COALESCE(SUM(current_total_debt), 0) AS total
      FROM customers
      WHERE current_total_debt > 0
        AND (is_deleted IS NULL OR is_deleted = 0)
    ''');
    final creditRow = await db.rawQuery('''
      SELECT COALESCE(SUM(ABS(current_total_debt)), 0) AS total
      FROM customers
      WHERE current_total_debt < 0
        AND (is_deleted IS NULL OR is_deleted = 0)
    ''');

    final rows = await db.rawQuery('''
      SELECT c.id AS id,
             c.name AS name,
             c.sync_uuid AS uuid,
             c.current_total_debt AS debt,
             COUNT(t.id) AS cnt,
             COALESCE(SUM(t.amount_changed), 0) AS total
      FROM customers c
      LEFT JOIN transactions t
             ON t.customer_id = c.id
            AND (t.is_deleted IS NULL OR t.is_deleted = 0)
      WHERE c.sync_uuid IS NOT NULL
        AND (c.is_deleted IS NULL OR c.is_deleted = 0)
      GROUP BY c.id
      ORDER BY c.name COLLATE NOCASE ASC
    ''');

    final customers = rows
        .map((r) => (
              syncUuid: r['uuid'] as String,
              name: r['name'] as String? ?? 'غير معروف',
              id: r['id'] as int,
              debt: (r['debt'] as num?)?.toDouble() ?? 0.0,
              txCount: (r['cnt'] as num?)?.toInt() ?? 0,
              txSum: (r['total'] as num?)?.toDouble() ?? 0.0,
            ))
        .toList();

    return (
      totalDebt: (debtRow.first['total'] as num?)?.toDouble() ?? 0.0,
      totalCredit: (creditRow.first['total'] as num?)?.toDouble() ?? 0.0,
      customers: customers,
    );
  }

  Future<void> _emitIdle(String message) async {
    final online = await getOnlineDevices();
    final local = await _readLocalCustomers();
    final snap = LiveMatchSnapshot(
      at: DateTime.now(),
      localTotalDebt: local.totalDebt,
      localTotalCredit: local.totalCredit,
      localCustomerCount: local.customers.length,
      peerTotalDebt: 0,
      peerCustomerCount: 0,
      peerDeviceName: null,
      peerDeviceId: null,
      customers: const [],
      uploadQueue: _queue.values.toList(),
      sessionActive: false,
      peerStreamReady: false,
      onlineDeviceCount: online.length,
      onlineDevices: online,
      statusMessage: message,
      sessionId: _activeSessionId,
      sessionStatus: _sessionStatus,
    );
    _last = snap;
    if (!_snapshotController.isClosed) _snapshotController.add(snap);
  }

  Future<LiveMatchSnapshot> recompute() async {
    final online = await getOnlineDevices();
    final others =
        online.where((d) => d['isCurrentDevice'] != true).length;

    final peers = _freshPeers;
    if (!sessionActive || peers.isEmpty) {
      String msg;
      if (_sessionStatus == 'requesting') {
        msg = 'بانتظار موافقة الأجهزة المتصلة...';
      } else if (others == 0) {
        msg =
            'لا يوجد جهاز آخر متصل. المطابقة الحية لا تعمل إلا بين أجهزة متصلة.';
      } else if (!sessionActive) {
        msg =
            'اضغط «طلب مطابقة حية» لدعوة $others جهاز متصل. المقارنة مع الأجهزة الأخرى لا مع السحابة.';
      } else {
        msg = 'بانتظار بث حيّ من الأجهزة المشاركة...';
      }
      await _emitIdle(msg);
      return _last!;
    }

    final local = await _readLocalCustomers();
    final db = await _db.database;

    // معاملات هذا الجهاز — للطابور فقط عند الفحص.
    final ownedRows = await db.rawQuery('''
      SELECT t.sync_uuid AS uuid,
             t.amount_changed AS amount,
             c.sync_uuid AS customer_uuid,
             c.name AS customer_name,
             t.is_uploaded AS uploaded
      FROM transactions t
      JOIN customers c ON c.id = t.customer_id
      WHERE t.sync_uuid IS NOT NULL
        AND (t.is_deleted IS NULL OR t.is_deleted = 0)
        AND (t.is_created_by_me IS NULL OR t.is_created_by_me = 1)
        AND (c.is_deleted IS NULL OR c.is_deleted = 0)
    ''');
    final ownedByCustomer = <String, List<Map<String, dynamic>>>{};
    for (final row in ownedRows) {
      final cu = row['customer_uuid'] as String?;
      if (cu == null || cu.isEmpty) continue;
      ownedByCustomer.putIfAbsent(cu, () => []).add(row);
    }

    // 🛡️ المطابقة بمعرّف المزامنة لا بالاسم: عميلان مختلفان بنفس الاسم
    // كانا يُدمجان في صف واحد فيختفي دين أحدهما من الشاشة.
    final localByUuid = {for (final c in local.customers) c.syncUuid: c};
    final allUuids = <String>{
      ...localByUuid.keys,
      for (final p in peers) ...p.customers.keys,
    };

    final matches = <LiveCustomerMatch>[];
    for (final uuid in allUuids) {
      final loc = localByUuid[uuid];
      final localDebt = loc?.debt ?? 0.0;
      final localCount = loc?.txCount ?? 0;
      final localSum = loc?.txSum ?? 0.0;

      // 🧮 مقارنة مع كل جهاز مشارك؛ يُعرض الأشد اختلافاً ويُذكر عدد المختلفين.
      _PeerState? worst;
      _PeerCustomer? worstC;
      double worstDiff = -1;
      int disagreeing = 0;
      for (final p in peers) {
        final pc = p.customers[uuid];
        final pDebt = pc?.debt ?? 0.0;
        final pCount = pc?.txCount ?? 0;
        final differs =
            (pDebt - localDebt).abs() > 0.01 || pCount != localCount;
        if (differs) disagreeing++;
        final d = (pDebt - localDebt).abs() + (pCount != localCount ? 0.001 : 0);
        if (d > worstDiff) {
          worstDiff = d;
          worst = p;
          worstC = pc;
        }
      }
      String? anyPeerName;
      for (final p in peers) {
        final n = p.customers[uuid]?.name;
        if (n != null && n.isNotEmpty) {
          anyPeerName = n;
          break;
        }
      }
      final name = loc?.name ?? worstC?.name ?? anyPeerName ?? 'غير معروف';
      final peerDebt = worstC?.debt ?? 0.0;
      final peerCount = worstC?.txCount ?? 0;
      final peerSum = worstC?.txSum ?? 0.0;
      final peerLabel = disagreeing > 1
          ? '${worst?.deviceName ?? 'جهاز آخر'} (+${disagreeing - 1} أجهزة مختلفة)'
          : (worst?.deviceName ?? 'جهاز آخر');

      final debtDiffers = disagreeing > 0;
      final localDrift = (localDebt - localSum).abs() > 0.01;

      final problems = <QueuedOwnedTx>[];
      if ((debtDiffers || localDrift) && uuid.isNotEmpty) {
        for (final owned in ownedByCustomer[uuid] ?? const []) {
          final uploaded = ((owned['uploaded'] as num?)?.toInt() ?? 0) == 1;
          final txUuid = owned['uuid'] as String;
          final amount = (owned['amount'] as num?)?.toDouble() ?? 0.0;
          if (!uploaded) {
            problems.add(QueuedOwnedTx(
              syncUuid: txUuid,
              customerSyncUuid: uuid,
              customerName: name,
              amount: amount,
              reason: 'غير مرفوعة — قد تكون سبب الفرق مع $peerLabel',
            ));
          } else if (localCount > peerCount) {
            problems.add(QueuedOwnedTx(
              syncUuid: txUuid,
              customerSyncUuid: uuid,
              customerName: name,
              amount: amount,
              reason: 'مرشّحة لإعادة الرفع — عددنا أكبر من $peerLabel',
            ));
          }
        }
      }

      matches.add(LiveCustomerMatch(
        customerSyncUuid: uuid,
        customerName: name,
        localCustomerId: loc?.id ?? 0,
        localDebt: localDebt,
        localTxCount: localCount,
        localTxSum: localSum,
        peerDebt: peerDebt,
        peerTxCount: peerCount,
        peerTxSum: peerSum,
        peerDeviceName: peerLabel,
        ownedProblems: problems,
      ));
    }

    matches.sort((a, b) {
      if (a.isMatch != b.isMatch) return a.isMatch ? 1 : -1;
      return b.debtDifference.abs().compareTo(a.debtDifference.abs());
    });

    final mismatchCount = matches.where((m) => !m.isMatch).length;
    // للعنوان: الجهاز الأبعد إجمالياً عن هذا الجهاز
    peers.sort((a, b) => (b.totalDebt - local.totalDebt)
        .abs()
        .compareTo((a.totalDebt - local.totalDebt).abs()));
    final headline = peers.first;
    final peersLabel = peers.length == 1
        ? headline.deviceName
        : '${peers.length} أجهزة (الأبعد: ${headline.deviceName})';
    final snap = LiveMatchSnapshot(
      at: DateTime.now(),
      localTotalDebt: local.totalDebt,
      localTotalCredit: local.totalCredit,
      localCustomerCount: local.customers.length,
      peerTotalDebt: headline.totalDebt,
      peerCustomerCount: headline.customers.length,
      peerDeviceName: peersLabel,
      peerDeviceId: headline.deviceId,
      customers: matches,
      uploadQueue: _queue.values.toList(),
      sessionActive: true,
      peerStreamReady: true,
      onlineDeviceCount: online.length,
      onlineDevices: online,
      statusMessage:
          'مطابقة حية مع $peersLabel · $mismatchCount عميل غير متطابق',
      sessionId: _activeSessionId,
      sessionStatus: _sessionStatus,
    );

    _last = snap;
    if (!_snapshotController.isClosed) _snapshotController.add(snap);
    return snap;
  }

  /// فحص فقط: يملأ طابور إعادة الرفع — لا يغيّر أرصدة ولا يحذف معاملات.
  Future<int> inspectAndQueueMismatches() async {
    if (!sessionActive) return 0;
    // 🔒 حديد: الفحص لا يستدعي recalculate ولا أي تعديل محلي.
    DatabaseService.blockTransactionDeletes = true;
    try {
      final snap = await recompute();
      int added = 0;
      for (final c in snap.mismatches) {
        for (final p in c.ownedProblems) {
          if (!_queue.containsKey(p.syncUuid)) {
            _queue[p.syncUuid] = p;
            added++;
          }
        }
      }
      await recompute();
      return added;
    } finally {
      DatabaseService.blockTransactionDeletes = false;
    }
  }

  Future<int> inspectCustomer(String customerSyncUuid) async {
    if (!sessionActive) return 0;
    final snap = await recompute();
    LiveCustomerMatch? c;
    for (final x in snap.customers) {
      if (x.customerSyncUuid == customerSyncUuid) {
        c = x;
        break;
      }
    }
    if (c == null) return 0;
    int added = 0;
    for (final p in c.ownedProblems) {
      if (!_queue.containsKey(p.syncUuid)) {
        _queue[p.syncUuid] = p;
        added++;
      }
    }
    await recompute();
    return added;
  }

  void clearQueue() {
    _queue.clear();
    unawaited(recompute());
  }

  Future<({int ok, int failed, int skipped})> forceUploadQueue({
    void Function(int done, int total, String msg)? onProgress,
  }) async {
    DatabaseService.blockTransactionDeletes = true;
    try {
      final items = _queue.values.toList();
      int ok = 0, failed = 0, skipped = 0;
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        onProgress?.call(i + 1, items.length, item.customerName);
        try {
          final success =
              await _sync.forceReuploadOwnedTransaction(item.syncUuid);
          if (success) {
            ok++;
            _queue.remove(item.syncUuid);
          } else {
            final db = await _db.database;
            final row = await db.query(
              'transactions',
              columns: ['is_created_by_me'],
              where: 'sync_uuid = ?',
              whereArgs: [item.syncUuid],
              limit: 1,
            );
            if (row.isNotEmpty &&
                (row.first['is_created_by_me'] as num?)?.toInt() == 0) {
              skipped++;
              _queue.remove(item.syncUuid);
            } else {
              failed++;
            }
          }
        } catch (_) {
          failed++;
        }
      }
      await _publishLocalState();
      await recompute();
      return (ok: ok, failed: failed, skipped: skipped);
    } finally {
      DatabaseService.blockTransactionDeletes = false;
    }
  }

  /// رفع كل العملاء + كل معاملات هذا الجهاز مجدداً (حتى المرفوعة مسبقاً).
  /// لا يحذف شيئاً — يتجاوز is_uploaded ويعيد الكتابة على السحابة فقط.
  Future<Map<String, dynamic>> forceReuploadAllCustomersAndOwnedTxs({
    void Function(int done, int total, String msg)? onProgress,
  }) async {
    final result = await _sync.repairAndSyncAllTransactions(
      onProgress: onProgress,
    );
    await _publishLocalState();
    await recompute();
    return result;
  }

  /// عندما يكون النظير هو الصحيح: **لا معاملات تصحيحية**.
  ///
  /// المعاملة التصحيحية كانت تُرفع كمعاملة عادية فتصل لكل الأجهزة — ومنها
  /// الجهاز الصحيح نفسه — فيصبح الجميع خاطئاً بمقدار الفرق. الآن: نطلب من
  /// كل الأجهزة المشاركة إعادة رفع معاملاتها لهذا العميل، ثم نسحب معاملاته
  /// من السحابة بمعرّفاتها عبر مسار الاستقبال الإدمبوتنت نفسه.
  /// يُرجع عدد العملاء الذين عولجوا.
  Future<int> addCorrectiveTransactionsForPeerTruth() async {
    if (!sessionActive) return 0;
    final snap = await recompute();
    return _pullPeerTruthFor(snap.mismatches
        .where((c) => c.customerSyncUuid.isNotEmpty)
        .map((c) => c.customerSyncUuid)
        .toSet());
  }

  /// نفس ما سبق لعملاء محددين.
  Future<int> addCorrectiveTransactionsForSelectedPeerTruth(Set<String> selectedUuids) async {
    if (!sessionActive || selectedUuids.isEmpty) return 0;
    return _pullPeerTruthFor(selectedUuids);
  }

  Future<int> _pullPeerTruthFor(Set<String> customerUuids) async {
    final fs = _fs;
    if (fs == null || customerUuids.isEmpty) return 0;
    // 1) اطلب من المالكين إعادة رفع معاملاتهم لهؤلاء العملاء
    await requestPeerToUploadCustomers(customerUuids);
    // 2) مهلة قصيرة لوصول الرفع، ثم سحب كامل لمعاملات كل عميل من السحابة
    await Future.delayed(const Duration(seconds: 6));
    int done = 0;
    for (final cu in customerUuids) {
      try {
        final snap = await fs
            .collection('transactions')
            .where('customerSyncUuid', isEqualTo: cu)
            .get(const GetOptions(source: Source.server));
        for (final d in snap.docs) {
          await _sync.applyRemoteTransaction(d.id, d.data());
        }
        done++;
      } catch (e) {
        print('⚠️ [LiveMatch] تعذّر سحب معاملات العميل $cu: $e');
      }
    }
    await _publishLocalState();
    await recompute();
    return done;
  }

  /// إعادة رفع واعتماد بيانات هذا الجهاز لعملاء محددين:
  /// يتم إعادة بث بيانات العملاء المحددين ومعاملاتهم إلى Firebase فوراً
  Future<void> forceUploadSelectedCustomers(Set<String> selectedUuids, {void Function(int done, int total, String msg)? onProgress}) async {
    if (selectedUuids.isEmpty) return;
    int done = 0;
    final total = selectedUuids.length;
    for (final uuid in selectedUuids) {
      done++;
      onProgress?.call(done, total, 'جاري رفع بيانات العميل $done/$total...');
      await inspectCustomer(uuid);
      await notifyPeerOfPushedCustomer(uuid);
    }
    await forceUploadQueue(onProgress: (d, t, name) {
      onProgress?.call(d, t, 'جاري بث المعاملات $d/$t ($name)...');
    });
    await _publishLocalState();
    await recompute();
  }

  /// 📡 الاستماع للأوامر الواردة حياً من الأجهزة الأخرى بخصوص التحديث المباشر للعملاء
  void _startCommandsListener() {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null || _commandsSub != null) return;

    _commandsSub = fs
        .collection('live_match_commands')
        .where('targetDeviceId', isEqualTo: myId)
        .snapshots()
        .listen((snapshot) async {
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data == null) continue;
          final command = data['command'] as String?;
          final customerSyncUuid = data['customerSyncUuid'] as String?;
          final senderDeviceId = data['senderDeviceId'] as String?;

          if (customerSyncUuid == null) continue;

          if (command == 'request_customer_data' || command == 'reupload_customer') {
            print('📩 [LiveMatchService] الجهاز ($senderDeviceId) يطلب رفع معاملات العميل $customerSyncUuid...');
            await reuploadLocalCustomerTransactionsToPeer(customerSyncUuid, targetPeerId: senderDeviceId);
            unawaited(change.doc.reference.delete());
          } else if (command == 'push_customer_notify') {
            final db = await _db.database;
            final cust = await db.query('customers', columns: ['name'], where: 'sync_uuid = ?', whereArgs: [customerSyncUuid], limit: 1);
            final name = cust.isNotEmpty ? cust.first['name'] as String : 'العميل';
            _peerNotificationController.add('📲 جاري تنزيل ومطابقة معاملات «$name» المرفوعة من الجهاز الآخر...');
            
            // انتظار المزامنة لتطبيق البيانات ثم تحديث حالة المطابقة للمقابلة
            await Future.delayed(const Duration(seconds: 2));
            await _publishLocalState();
            await recompute();
            unawaited(change.doc.reference.delete());
          }
        }
      }
    }, onError: (e) => print('⚠️ [LiveMatchService] خطأ استماع أوامر المطابقة: $e'));
  }

  /// 📤 إرسال طلب للجهاز الآخر لإعادة رفع معاملات عملاء محددين لكون بياناته هي الصحيحة
  Future<void> requestPeerToUploadCustomers(Set<String> customerSyncUuids) async {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null || _peerIds.isEmpty || customerSyncUuids.isEmpty) return;

    for (final peerId in _peerIds) {
      for (final uuid in customerSyncUuids) {
        final docId = 'cmd_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
        await fs.collection('live_match_commands').doc(docId).set({
          'command': 'request_customer_data',
          'targetDeviceId': peerId,
          'senderDeviceId': myId,
          'customerSyncUuid': uuid,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    }
  }

  /// 📤 إخطار الجهاز الآخر أننا قمنا برفع بيانات عميل صحيحة ليقوم بتنزيلها ومطابقتها
  Future<void> notifyPeerOfPushedCustomer(String customerSyncUuid) async {
    final fs = _fs;
    final myId = _myId;
    if (fs == null || myId == null || _peerIds.isEmpty) return;

    for (final peerId in _peerIds) {
      final docId = 'cmd_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
      await fs.collection('live_match_commands').doc(docId).set({
        'command': 'push_customer_notify',
        'targetDeviceId': peerId,
        'senderDeviceId': myId,
        'customerSyncUuid': customerSyncUuid,
        'createdAt': DateTime.now().toIso8601String(),
      });
    }
  }

  /// 🔄 إعادة رفع معاملات عميل محدد من SQLite إلى Firebase استجابة لطلب الجهاز النظير
  Future<void> reuploadLocalCustomerTransactionsToPeer(String customerSyncUuid, {String? targetPeerId}) async {
    try {
      final db = await _db.database;
      final cust = await db.query('customers', columns: ['id', 'name'], where: 'sync_uuid = ?', whereArgs: [customerSyncUuid], limit: 1);
      if (cust.isEmpty) return;
      final customerId = cust.first['id'] as int;
      final customerName = cust.first['name'] as String? ?? 'العميل';

      _peerNotificationController.add('📲 جاري رفع معاملات العميل «$customerName» بناءً على طلب الجهاز الآخر...');

      // 🛡️ معاملاتي فقط — تصفير is_uploaded لمعاملات أجهزة أخرى كان يُعلّقها
      // كـ«غير مرفوعة» للأبد. وبدل رفع شامل لكل العملاء نرفع هذا العميل وحده.
      final owned = await db.query(
        'transactions',
        columns: ['sync_uuid'],
        where: 'customer_id = ? AND sync_uuid IS NOT NULL '
            'AND (is_created_by_me = 1 OR is_created_by_me IS NULL)',
        whereArgs: [customerId],
      );
      for (final row in owned) {
        final u = row['sync_uuid'] as String?;
        if (u == null || u.isEmpty) continue;
        await _sync.forceReuploadOwnedTransaction(u);
      }
      await notifyPeerOfPushedCustomer(customerSyncUuid);
      await _publishLocalState();
      await recompute();
      print('✅ [LiveMatchService] تم بث معاملات العميل ($customerName) للجهاز النظير بنجاح!');
    } catch (e) {
      print('❌ [LiveMatchService] خطأ في إعادة بث معاملات العميل للجهاز النظير: $e');
    }
  }

  void dispose() {
    stop();
  }
}
