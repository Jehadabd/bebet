// test/sync_harness/cloud.dart
// «سحابة Firestore وهمية» تعمل في الخيط الرئيسي للاختبار.
//
// تحاكي السلوك الذي يعتمد عليه كود المزامنة:
//   • set / set(merge) / update / delete — ذرية، مع serverTimestamp وdelete وincrement.
//   • قراءة مستند، استعلامات (== != < <= > >= in not-in array-contains)، ترتيب،
//     مؤشرات (startAfter…)، حدود، عدّ وجمع.
//   • معاملات (runTransaction) بتحقق متفائل من إصدار ما قُرئ، ودفعات (batch).
//   • مستمعون: لقطة أولى بكل المطابق (added)، ثم الفروق (added/modified/removed).
//   • انقطاع الإنترنت لكل جهاز: القراءات تفشل (unavailable)، الكتابات تنتظر حتى
//     العودة (كـ Firestore على سطح المكتب بلا persistence)، والمستمعون يصمتون ثم
//     يُرسل لهم الفرق عند العودة.

import 'dart:isolate';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'
    show Timestamp;

import 'protocol.dart';

class _Doc {
  Map<String, Object?> data;
  int version;
  _Doc(this.data, this.version);
}

class _Listener {
  final String id;
  final String device;
  final SendPort port;
  final String? docPath; // مستمع مستند
  final QuerySpec? query; // مستمع استعلام
  Map<String, int> lastSent = {}; // path → version (آخر ما أُرسل)
  List<String> lastOrder = [];
  bool dirty = false;
  bool sentOnce = false;
  final Set<String> pending = {}; // تغيّرت أثناء انقطاع الجهاز (مستمع بسيط)
  int total = 0; // عدد كل المطابق (للمستمع المحدود: هل بعد النافذة مستندات؟)
  _Listener(this.id, this.device, this.port, {this.docPath, this.query});

  /// استعلام بلا ترتيب ولا حدود ولا مؤشرات: تكفيه الفروق (ترتيبه بالمعرّف).
  bool get simple {
    final q = query;
    return q != null &&
        q.orderBy.isEmpty &&
        q.limit == null &&
        q.limitToLast == null &&
        q.startAt == null &&
        q.startAfter == null &&
        q.endAt == null &&
        q.endBefore == null;
  }

  /// استعلام بحدّ (limit) بلا مؤشرات: تُحدَّث «نافذته» بما تغيّر وحده.
  bool get windowed {
    final q = query;
    return q != null &&
        q.limit != null &&
        q.limitToLast == null &&
        q.startAt == null &&
        q.startAfter == null &&
        q.endAt == null &&
        q.endBefore == null;
  }
}

class CloudError implements Exception {
  final String code;
  final String message;
  CloudError(this.code, this.message);
  @override
  String toString() => 'CloudError($code: $message)';
}

class FakeCloud {
  final Map<String, _Doc> docs = {};
  final Map<String, Set<String>> _byColl = {}; // مجموعة ← مسارات مستنداتها
  final Map<String, bool> online = {};
  final Map<String, List<CloudRequest>> _queued = {};
  final Map<String, _Listener> _listeners = {};
  final ReceivePort _port = ReceivePort();
  int _ver = 0;
  int _lastMicros = 0;

  /// عدد الكتابات لكل مجموعة (للقياس: عواصف الكتابة).
  final Map<String, int> writesByCollection = {};
  int totalWrites = 0;
  DateTime lastWriteAt = DateTime.now();

  /// أخطاء غير متوقعة داخل السحابة (خلل في الأداة نفسها).
  final List<String> internalErrors = [];

  /// زمن المعالجة داخل السحابة لكل بند (للقياس: أين يذهب الوقت مع نمو البيانات).
  final Map<String, List<int>> costs = {}; // بند ← [عدد، مجموع µs، أقصى µs]
  final Stopwatch _clock = Stopwatch()..start();
  int busyMicros = 0; // كل وقت معالجة الطلبات (الإشعارات ضمنه)
  void _cost(String k, int t0) {
    final us = _clock.elapsedMicroseconds - t0;
    final e = costs[k] ??= [0, 0, 0];
    e[0]++;
    e[1] += us;
    if (us > e[2]) e[2] = us;
  }

  static String _label(CloudRequest r) {
    final a = r.args;
    switch (r.op) {
      case 'get':
        return 'get ${_parent(a['path'] as String)}';
      case 'query':
      case 'agg':
        return '${r.op} ${(a['spec'] as QuerySpec).collection}';
      case 'write':
        final ops = (a['ops'] as List).cast<WriteOp>();
        return 'write ${ops.isEmpty ? '' : _parent(ops.first.path)}${ops.length > 1 ? ' ×n' : ''}';
    }
    return r.op;
  }

  SendPort get sendPort => _port.sendPort;

  FakeCloud() {
    _port.listen(_onMessage);
  }

  void close() => _port.close();

  // ───────────────────────── الشبكة ─────────────────────────

  void setOnline(String device, bool value) {
    online[device] = value;
    if (!value) return;
    final q = _queued.remove(device) ?? const [];
    for (final r in q) {
      _handle(r);
    }
    for (final l in _listeners.values.toList()) {
      if (l.device != device || !l.dirty) continue;
      if (l.simple && l.sentOnce) {
        l.dirty = false;
        final p = {...l.pending};
        l.pending.clear();
        _flushChanges(l, p);
      } else {
        _flush(l);
      }
    }
  }

  bool _isOnline(String device) => online[device] ?? true;

  /// يُسقط مستمعي جهاز (عند إعادة تشغيله أو إغلاقه).
  void dropDevice(String device) {
    _listeners.removeWhere((_, l) => l.device == device);
    _queued.remove(device);
  }

  // ───────────────────────── الرسائل ─────────────────────────

  void _onMessage(dynamic msg) {
    if (msg is! CloudRequest) return;
    final isWrite = msg.op == 'write' && (msg.args['pre'] == null);
    if (!_isOnline(msg.device)) {
      if (isWrite) {
        // كتابة بلا persistence: تنتظر حتى يعود الاتصال
        _queued.putIfAbsent(msg.device, () => []).add(msg);
        return;
      }
      if (msg.op != 'unlisten' && msg.op != 'listen') {
        msg.replyTo.send(CloudReply(msg.id, null, 'unavailable',
            'The service is currently unavailable (client offline).'));
        return;
      }
    }
    _handle(msg);
  }

  void _handle(CloudRequest r) {
    final t0 = _clock.elapsedMicroseconds;
    try {
      final value = _dispatch(r);
      r.replyTo.send(CloudReply(r.id, value));
    } on CloudError catch (e) {
      r.replyTo.send(CloudReply(r.id, null, e.code, e.message));
    } catch (e, st) {
      internalErrors.add('${r.op}: $e\n$st');
      r.replyTo.send(CloudReply(r.id, null, 'internal', '$e'));
    } finally {
      busyMicros += _clock.elapsedMicroseconds - t0;
      _cost(_label(r), t0);
    }
  }

  Object? _dispatch(CloudRequest r) {
    final a = r.args;
    switch (r.op) {
      case 'get':
        return _snap(a['path'] as String);
      case 'query':
        return _runQuery(a['spec'] as QuerySpec);
      case 'agg':
        return _aggregate(a['spec'] as QuerySpec, (a['aggs'] as List).cast<List<Object?>>());
      case 'write':
        _write((a['ops'] as List).cast<WriteOp>(),
            (a['pre'] as Map?)?.cast<String, int>());
        return null;
      case 'listen':
        final l = _Listener(a['id'] as String, r.device, r.replyTo,
            docPath: a['doc'] as String?, query: a['query'] as QuerySpec?);
        _listeners[l.id] = l;
        if (_isOnline(r.device)) {
          _flush(l, initial: true);
        } else {
          l.dirty = true; // بلا persistence: لا لقطة حتى يعود الاتصال
        }
        return null;
      case 'unlisten':
        _listeners.remove(a['id'] as String);
        return null;
    }
    throw CloudError('unimplemented', 'op ${r.op}');
  }

  // ───────────────────────── القراءة ─────────────────────────

  DocSnap _snap(String path) {
    final d = docs[path];
    return d == null ? DocSnap(path, null, 0) : DocSnap(path, _deepCopy(d.data), d.version);
  }

  static String _parent(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static String _id(String path) => path.substring(path.lastIndexOf('/') + 1);

  List<DocSnap> _runQuery(QuerySpec q) {
    final paths = _matchPaths(q);
    return [for (final p in paths) _snap(p)];
  }

  /// شروط الاستعلام بلا المؤشرات والحدود: المرشّحات، ووجود حقول الترتيب.
  bool _qualifies(QuerySpec q, String path, Map<String, Object?> data) {
    for (final w in q.where) {
      if (!_matches(path, data, w[0] as FieldPathSpec, w[1] as String, w[2])) return false;
    }
    for (final o in q.orderBy) {
      final f = o[0] as FieldPathSpec;
      if (!_isDocId(f) && !_has(data, f)) return false; // orderBy يستبعد من لا يملك الحقل
    }
    return true;
  }

  static List<List<Object?>> _orders(QuerySpec q) {
    final orders = <List<Object?>>[...q.orderBy];
    if (orders.isEmpty || !_isDocId(orders.last[0] as FieldPathSpec)) {
      final dir = orders.isEmpty ? false : orders.last[1] as bool;
      orders.add([const ['__name__'], dir]);
    }
    return orders;
  }

  int Function(String, String) _comparator(List<List<Object?>> orders) => (a, b) {
        for (final o in orders) {
          final f = o[0] as FieldPathSpec;
          final desc = o[1] as bool;
          final va = _isDocId(f) ? _id(a) : _get(docs[a]!.data, f);
          final vb = _isDocId(f) ? _id(b) : _get(docs[b]!.data, f);
          final c = _cmp(va, vb);
          if (c != 0) return desc ? -c : c;
        }
        return 0;
      };

  List<String> _matchPaths(QuerySpec q) => _limited(q, _sortedMatches(q));

  /// كل المطابق مرتّباً وبعد المؤشرات، قبل الحدود.
  List<String> _sortedMatches(QuerySpec q) {
    final out = <String>[
      for (final path in _byColl[q.collection] ?? const <String>{})
        if (_qualifies(q, path, docs[path]!.data)) path
    ];
    final orders = _orders(q);
    out.sort(_comparator(orders));

    int cmpCursor(String path, List<Object?> cursor) {
      for (var i = 0; i < cursor.length && i < orders.length; i++) {
        final f = orders[i][0] as FieldPathSpec;
        final desc = orders[i][1] as bool;
        final v = _isDocId(f) ? _id(path) : _get(docs[path]!.data, f);
        var cv = cursor[i];
        if (_isDocId(f) && cv is String && cv.contains('/')) cv = _id(cv);
        final c = _cmp(v, cv);
        if (c != 0) return desc ? -c : c;
      }
      return 0;
    }

    var res = out;
    if (q.startAt != null) res = res.where((p) => cmpCursor(p, q.startAt!) >= 0).toList();
    if (q.startAfter != null) res = res.where((p) => cmpCursor(p, q.startAfter!) > 0).toList();
    if (q.endAt != null) res = res.where((p) => cmpCursor(p, q.endAt!) <= 0).toList();
    if (q.endBefore != null) res = res.where((p) => cmpCursor(p, q.endBefore!) < 0).toList();
    return res;
  }

  static List<String> _limited(QuerySpec q, List<String> res) {
    if (q.limit != null && res.length > q.limit!) res = res.sublist(0, q.limit!);
    if (q.limitToLast != null && res.length > q.limitToLast!) {
      res = res.sublist(res.length - q.limitToLast!);
    }
    return res;
  }

  Map<String, Object?> _aggregate(QuerySpec q, List<List<Object?>> aggs) {
    final paths = _matchPaths(QuerySpec(collection: q.collection, where: q.where));
    final out = <String, Object?>{'count': paths.length};
    for (final a in aggs) {
      final kind = a[0] as String;
      if (kind == 'count') continue;
      final field = (a[1] as String).split('.');
      num sum = 0;
      var n = 0;
      for (final p in paths) {
        final v = _get(docs[p]!.data, field);
        if (v is num) {
          sum += v;
          n++;
        }
      }
      out['$kind:${a[1]}'] = kind == 'sum' ? sum.toDouble() : (n == 0 ? null : sum / n);
    }
    return out;
  }

  // ───────────────────────── الكتابة ─────────────────────────

  Timestamp _serverNow() {
    var m = DateTime.now().microsecondsSinceEpoch;
    if (m <= _lastMicros) m = _lastMicros + 1;
    _lastMicros = m;
    return Timestamp.fromMicrosecondsSinceEpoch(m);
  }

  void _write(List<WriteOp> ops, Map<String, int>? pre) {
    // تحقق متفائل للمعاملات: ما قُرئ لم يتغير
    if (pre != null) {
      pre.forEach((path, ver) {
        final cur = docs[path]?.version ?? 0;
        if (cur != ver) {
          throw CloudError('aborted', 'Transaction conflict on $path');
        }
      });
    }
    // تحقق مسبق: update يتطلب وجود المستند (كل العملية تفشل ذرياً)
    final exists = <String, bool>{};
    for (final op in ops) {
      if (op.kind == 'update' && (exists[op.path] ?? docs.containsKey(op.path)) != true) {
        throw CloudError('not-found', 'No document to update: ${op.path}');
      }
      if (op.kind == 'set') exists[op.path] = true;
      if (op.kind == 'delete') exists[op.path] = false;
    }
    final now = _serverNow();
    final changed = <String>{};
    final before = <String, Map<String, Object?>?>{}; // حالة كل مستند قبل هذه الكتابة
    for (final op in ops) {
      before.putIfAbsent(op.path, () => docs[op.path]?.data);
      switch (op.kind) {
        case 'set':
          final prev = docs[op.path];
          Map<String, Object?> data;
          if (prev != null && (op.merge || op.mergeFields != null)) {
            data = _deepCopy(prev.data);
            if (op.mergeFields != null) {
              for (final f in op.mergeFields!) {
                final v = _get(op.data!, f);
                _setPath(data, f, v, now, prev: _get(prev.data, f));
              }
            } else {
              _mergeInto(data, op.data!, now);
            }
          } else {
            data = {};
            _mergeInto(data, op.data!, now);
          }
          docs[op.path] = _Doc(data, ++_ver);
          _index(op.path, true);
          break;
        case 'update':
          final data = _deepCopy(docs[op.path]!.data);
          op.updates!.forEach((k, v) {
            final f = k.split('\u0000');
            _setPath(data, f, v, now, prev: _get(data, f));
          });
          docs[op.path] = _Doc(data, ++_ver);
          _index(op.path, true);
          break;
        case 'delete':
          docs.remove(op.path);
          _index(op.path, false);
          break;
      }
      changed.add(op.path);
      final coll = _parent(op.path);
      writesByCollection[coll] = (writesByCollection[coll] ?? 0) + 1;
      totalWrites++;
    }
    lastWriteAt = DateTime.now();
    _notify(changed, before);
  }

  void _index(String path, bool present) {
    final c = _parent(path);
    if (present) {
      (_byColl[c] ??= <String>{}).add(path);
    } else {
      _byColl[c]?.remove(path);
    }
  }

  void _mergeInto(Map<String, Object?> target, Map<String, Object?> src, Timestamp now) {
    src.forEach((k, v) {
      if (v is FV) {
        final r = _resolveFV(v, target[k], now);
        if (identical(r, _deleteMarker)) {
          target.remove(k);
        } else {
          target[k] = r;
        }
      } else if (v is Map) {
        final existing = target[k];
        final child = existing is Map
            ? Map<String, Object?>.from(existing)
            : <String, Object?>{};
        _mergeInto(child, v.cast<String, Object?>(), now);
        target[k] = child;
      } else {
        target[k] = _resolve(v, now);
      }
    });
  }

  static final Object _deleteMarker = Object();

  Object? _resolveFV(FV v, Object? prev, Timestamp now) {
    switch (v.kind) {
      case 'serverTimestamp':
        return now;
      case 'delete':
        return _deleteMarker;
      case 'increment':
        final n = v.arg as num;
        return prev is num ? prev + n : n;
      case 'arrayUnion':
        final list = prev is List ? List<Object?>.from(prev) : <Object?>[];
        for (final e in (v.arg as List)) {
          if (!list.any((x) => _eq(x, e))) list.add(e);
        }
        return list;
      case 'arrayRemove':
        final list = prev is List ? List<Object?>.from(prev) : <Object?>[];
        list.removeWhere((x) => (v.arg as List).any((e) => _eq(x, e)));
        return list;
    }
    throw CloudError('invalid-argument', 'Unknown FieldValue ${v.kind}');
  }

  Object? _resolve(Object? v, Timestamp now) {
    if (v is FV) return _resolveFV(v, null, now);
    if (v is DateTime) return Timestamp.fromDate(v);
    if (v is Map) {
      final m = <String, Object?>{};
      _mergeInto(m, v.cast<String, Object?>(), now);
      return m;
    }
    if (v is List) return [for (final e in v) _resolve(e, now)];
    return v;
  }

  void _setPath(Map<String, Object?> data, FieldPathSpec f, Object? v, Timestamp now,
      {Object? prev}) {
    Map<String, Object?> cur = data;
    for (var i = 0; i < f.length - 1; i++) {
      final next = cur[f[i]];
      final child = next is Map ? Map<String, Object?>.from(next) : <String, Object?>{};
      cur[f[i]] = child;
      cur = child;
    }
    final last = f.last;
    final r = v is FV ? _resolveFV(v, prev, now) : _resolve(v, now);
    if (identical(r, _deleteMarker)) {
      cur.remove(last);
    } else {
      cur[last] = r;
    }
  }

  // ───────────────────────── المستمعون ─────────────────────────

  void _notify(Set<String> changed, Map<String, Map<String, Object?>?> before) {
    for (final l in _listeners.values.toList()) {
      final rel = l.docPath != null
          ? (changed.contains(l.docPath) ? {l.docPath!} : const <String>{})
          : changed.where((p) => _parent(p) == l.query!.collection).toSet();
      if (rel.isEmpty) continue;
      if (!_isOnline(l.device)) {
        l.dirty = true;
        if (l.simple) l.pending.addAll(rel);
        continue;
      }
      final t0 = _clock.elapsedMicroseconds;
      final String how;
      if (l.docPath != null) {
        _flush(l);
        how = 'مستند';
      } else if (l.simple && l.sentOnce) {
        _flushChanges(l, rel);
        how = 'فرق';
      } else if (l.windowed && l.sentOnce) {
        how = _flushWindow(l, rel, before) ? 'نافذة' : 'نافذة ثم كامل';
      } else if (l.sentOnce && _unaffected(l, rel)) {
        how = 'لا يمسّه';
      } else {
        _flush(l);
        how = 'كامل';
      }
      _cost('  ↳ إشعار ${l.docPath != null ? '' : l.query!.collection} $how', t0);
    }
  }

  /// لا شيء مما تغيّر كان في النتيجة ولا صار يطابق الآن: النتيجة لا تتغير
  /// (حذف مستند خارج النافذة لا يغيّرها، مع الحدود والمؤشرات).
  bool _unaffected(_Listener l, Set<String> rel) {
    for (final p in rel) {
      if (l.lastSent.containsKey(p)) return false;
      final d = docs[p];
      if (d != null && _qualifies(l.query!, p, d.data)) return false;
    }
    return true;
  }

  /// مستمع بحدّ بلا مؤشرات: تُحدَّث النافذة (أول limit مستنداً بالترتيب) بما
  /// تغيّر وحده، دون فرز المجموعة كلها مع كل كتابة. إن نقصت النافذة وبعدها
  /// مستندات لا نعرف أيّها التالي، يُعاد الحساب كاملاً (يرجع false).
  /// الترتيب بالمعرّف (بلا orderBy): تُرسل الفروق وحدها كالمستمع البسيط؛
  /// الترتيب بحقل: تُرسل النافذة كاملة (صغيرة) ليبقى ترتيبها كما في Firestore.
  bool _flushWindow(_Listener l, Set<String> rel, Map<String, Map<String, Object?>?> before) {
    final q = l.query!;
    final lim = q.limit!;
    final cmp = _comparator(_orders(q));
    final win = List<String>.of(l.lastOrder);
    var beyond = l.total - win.length; // مطابقة خارج النافذة (بعدها)
    var touched = false;
    // 1) إخراج كل ما تغيّر بحالته السابقة
    for (final p in rel) {
      if (l.lastSent.containsKey(p)) {
        win.remove(p);
        touched = true;
      } else {
        final b = before[p];
        if (b != null && _qualifies(q, p, b)) beyond--;
      }
    }
    // 2) إدخال ما يطابق بحالته الجديدة في موضعه
    for (final p in rel) {
      final d = docs[p];
      if (d == null || !_qualifies(q, p, d.data)) continue;
      var lo = 0, hi = win.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (cmp(win[mid], p) < 0) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      if (lo < win.length || (win.length < lim && beyond == 0)) {
        win.insert(lo, p);
        touched = true;
        if (win.length > lim) {
          win.removeLast();
          beyond++;
        }
      } else if (win.length >= lim) {
        beyond++; // بعد نافذة ممتلئة
      } else {
        _flush(l);
        return false;
      }
    }
    if (win.length < lim && beyond > 0) {
      _flush(l);
      return false;
    }
    l.total = win.length + beyond;
    if (!touched) return true;
    // 3) الفروق مقابل آخر ما أُرسل
    final ordered = q.orderBy.isNotEmpty;
    final oldIndex = ordered
        ? {for (var i = 0; i < l.lastOrder.length; i++) l.lastOrder[i]: i}
        : const <String, int>{};
    final now = {for (final p in win) p: docs[p]!.version};
    final changes = <DocChangeMsg>[];
    for (var i = 0; i < win.length; i++) {
      final p = win[i];
      final was = l.lastSent[p];
      if (was == null) {
        changes.add(DocChangeMsg('added', -1, ordered ? i : -1, _snap(p)));
      } else if (was != now[p]) {
        changes.add(DocChangeMsg('modified', oldIndex[p] ?? -1, ordered ? i : -1, _snap(p)));
      }
    }
    for (final p in l.lastSent.keys) {
      if (!now.containsKey(p)) {
        changes.add(DocChangeMsg('removed', oldIndex[p] ?? -1, -1, DocSnap(p, null, 0)));
      }
    }
    l.lastOrder = win;
    l.lastSent = now;
    if (changes.isEmpty) return true;
    l.port.send(ListenerEvent(l.id, ordered ? [for (final p in win) _snap(p)] : null, changes));
    return true;
  }

  /// الفروق وحدها لمستمع بسيط: ما تغيّر من المستندات المعنيّة فقط.
  void _flushChanges(_Listener l, Set<String> paths) {
    final q = l.query!;
    final changes = <DocChangeMsg>[];
    for (final p in paths) {
      final d = docs[p];
      final match = d != null &&
          q.where.every((w) =>
              _matches(p, d.data, w[0] as FieldPathSpec, w[1] as String, w[2]));
      final before = l.lastSent[p];
      if (match) {
        if (before == null) {
          changes.add(DocChangeMsg('added', -1, -1, _snap(p)));
        } else if (before != d.version) {
          changes.add(DocChangeMsg('modified', -1, -1, _snap(p)));
        } else {
          continue;
        }
        l.lastSent[p] = d.version;
      } else if (before != null) {
        changes.add(DocChangeMsg('removed', -1, -1, DocSnap(p, null, 0)));
        l.lastSent.remove(p);
      }
    }
    if (changes.isEmpty) return;
    l.port.send(ListenerEvent(l.id, null, changes));
  }

  void _flush(_Listener l, {bool initial = false}) {
    l.dirty = false;
    l.pending.clear();
    if (l.docPath != null) {
      final s = _snap(l.docPath!);
      final prevVer = l.lastSent[l.docPath!];
      if (!initial && l.sentOnce && prevVer == s.version) return;
      l.sentOnce = true;
      l.lastSent = {l.docPath!: s.version};
      l.port.send(ListenerEvent(l.id, [s], const []));
      return;
    }
    final sorted = _sortedMatches(l.query!);
    final paths = _limited(l.query!, sorted);
    l.total = sorted.length;
    final now = {for (final p in paths) p: docs[p]!.version};
    final changes = <DocChangeMsg>[];
    final oldIndex = {for (var i = 0; i < l.lastOrder.length; i++) l.lastOrder[i]: i};
    for (var i = 0; i < paths.length; i++) {
      final p = paths[i];
      final before = l.lastSent[p];
      if (before == null) {
        changes.add(DocChangeMsg('added', -1, i, _snap(p)));
      } else if (before != now[p]) {
        changes.add(DocChangeMsg('modified', oldIndex[p] ?? -1, i, _snap(p)));
      }
    }
    for (final p in l.lastSent.keys) {
      if (!now.containsKey(p)) {
        changes.add(DocChangeMsg('removed', oldIndex[p] ?? -1, -1, DocSnap(p, null, 0)));
      }
    }
    if (!initial && l.sentOnce && changes.isEmpty) return;
    l.sentOnce = true;
    l.lastSent = now;
    l.lastOrder = paths;
    l.port.send(ListenerEvent(l.id, [for (final p in paths) _snap(p)], changes));
  }

  // ───────────────────────── القيم ─────────────────────────

  static bool _isDocId(FieldPathSpec f) => f.length == 1 && f[0] == '__name__';

  static bool _has(Map<String, Object?> data, FieldPathSpec f) {
    Object? cur = data;
    for (final c in f) {
      if (cur is! Map || !cur.containsKey(c)) return false;
      cur = cur[c];
    }
    return true;
  }

  static Object? _get(Map<String, Object?> data, FieldPathSpec f) {
    Object? cur = data;
    for (final c in f) {
      if (cur is! Map) return null;
      cur = cur[c];
    }
    return cur;
  }

  bool _matches(String path, Map<String, Object?> data, FieldPathSpec f, String op, Object? value) {
    final has = _isDocId(f) || _has(data, f);
    final v = _isDocId(f) ? _id(path) : _get(data, f);
    if (_isDocId(f) && value is String && value.contains('/')) value = _id(value);
    switch (op) {
      case '==':
        return has && _eq(v, value);
      case '!=':
        return has && v != null && !_eq(v, value);
      case '<':
        return has && _sameKind(v, value) && _cmp(v, value) < 0;
      case '<=':
        return has && _sameKind(v, value) && _cmp(v, value) <= 0;
      case '>':
        return has && _sameKind(v, value) && _cmp(v, value) > 0;
      case '>=':
        return has && _sameKind(v, value) && _cmp(v, value) >= 0;
      case 'in':
        return has && (value as List).any((e) => _eq(v, e));
      case 'not-in':
        return has && v != null && !(value as List).any((e) => _eq(v, e));
      case 'array-contains':
        return has && v is List && v.any((e) => _eq(e, value));
      case 'array-contains-any':
        return has && v is List && v.any((e) => (value as List).any((x) => _eq(e, x)));
    }
    throw CloudError('invalid-argument', 'Unsupported operator $op');
  }

  static int _rank(Object? v) {
    if (v == null) return 0;
    if (v is bool) return 1;
    if (v is num) return 2;
    if (v is Timestamp || v is DateTime) return 3;
    if (v is String) return 4;
    if (v is List) return 6;
    if (v is Map) return 7;
    return 8;
  }

  static bool _sameKind(Object? a, Object? b) => _rank(a) == _rank(b);

  static int _micros(Object v) => v is Timestamp
      ? v.seconds * 1000000 + v.nanoseconds ~/ 1000
      : (v as DateTime).microsecondsSinceEpoch;

  static int _cmp(Object? a, Object? b) {
    final ra = _rank(a), rb = _rank(b);
    if (ra != rb) return ra.compareTo(rb);
    if (a == null) return 0;
    if (a is bool) return (a ? 1 : 0).compareTo((b as bool) ? 1 : 0);
    if (a is num) return a.compareTo(b as num);
    if (ra == 3) return _micros(a).compareTo(_micros(b!));
    if (a is String) return a.compareTo(b as String);
    return 0;
  }

  static bool _eq(Object? a, Object? b) {
    if (a is num && b is num) return a == b;
    if (_rank(a) == 3 && _rank(b) == 3) return _micros(a!) == _micros(b!);
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_eq(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_eq(a[k], b[k])) return false;
      }
      return true;
    }
    return a == b;
  }

  static Map<String, Object?> _deepCopy(Map<String, Object?> m) {
    Object? copy(Object? v) {
      if (v is Map) return {for (final e in v.entries) e.key as String: copy(e.value)};
      if (v is List) return [for (final e in v) copy(e)];
      return v;
    }

    return {for (final e in m.entries) e.key: copy(e.value)};
  }

  // ───────────────────────── للفحص ─────────────────────────

  Map<String, Map<String, Object?>> collection(String name) => {
        for (final p in _byColl[name] ?? const <String>{}) _id(p): _deepCopy(docs[p]!.data)
      };

  void clearCollection(String name) {
    final paths = (_byColl[name] ?? const <String>{}).toList();
    final before = <String, Map<String, Object?>?>{};
    for (final p in paths) {
      before[p] = docs.remove(p)?.data;
      _index(p, false);
    }
    _notify(paths.toSet(), before);
  }
}
