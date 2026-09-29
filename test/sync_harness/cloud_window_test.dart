// اختبار «السحابة الوهمية» نفسها: المستمعون بحدّ (limit) تُحدَّث نوافذهم بما
// تغيّر وحده (بدل فرز المجموعة كلها مع كل كتابة). هنا نتأكد عشوائياً أن ما
// يصل كل مستمع — لقطةً وفروقاً — يطابق دائماً الحساب الكامل للاستعلام، وأن
// الفروق (added/modified/removed) تنقل اللقطة السابقة إلى الجديدة بالضبط.
//
//   flutter test test/sync_harness/cloud_window_test.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:collection';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'cloud.dart';
import 'protocol.dart';

class _Client {
  final FakeCloud cloud;
  final ReceivePort rp = ReceivePort();
  final Map<int, Completer<Object?>> _replies = {};
  final Map<String, void Function(ListenerEvent)> _listeners = {};
  var _id = 0;

  _Client(this.cloud) {
    rp.listen((m) {
      if (m is CloudReply) {
        final c = _replies.remove(m.id)!;
        if (m.errorCode != null) {
          c.completeError('${m.errorCode}: ${m.errorMessage}');
        } else {
          c.complete(m.value);
        }
      } else if (m is ListenerEvent) {
        _listeners[m.listenerId]!(m);
      }
    });
  }

  Future<Object?> call(String device, String op, Map<String, Object?> args) {
    final id = ++_id;
    final c = _replies[id] = Completer<Object?>();
    cloud.sendPort.send(CloudRequest(id, device, op, args, rp.sendPort));
    return c.future;
  }

  void onEvent(String id, void Function(ListenerEvent) f) => _listeners[id] = f;
}

/// ما يراه المستمع: كما يبنيه جهاز (remote_firestore.querySnapApply).
class _View {
  final String name;
  final QuerySpec spec;
  final SplayTreeMap<String, DocSnap> cur = SplayTreeMap();
  List<DocSnap> docs = const [];
  int events = 0, diffEvents = 0;
  final List<String> problems = [];
  _View(this.name, this.spec);

  void apply(ListenerEvent e) {
    events++;
    final old = {for (final d in docs) d.path: d.version};
    if (e.docs != null) {
      cur.clear();
      for (final d in e.docs!) {
        cur[d.path] = d;
      }
      docs = List.of(e.docs!);
    } else {
      diffEvents++;
      for (final c in e.changes) {
        if (c.type == 'removed') {
          cur.remove(c.doc.path);
        } else {
          cur[c.doc.path] = c.doc;
        }
      }
      docs = cur.values.toList();
    }
    // الفروق يجب أن تكون بالضبط ما بين اللقطتين (بعد اللقطة الأولى)
    if (events == 1) return;
    final now = {for (final d in docs) d.path: d.version};
    final want = <String>{
      for (final p in now.keys)
        if (!old.containsKey(p)) 'added $p' else if (old[p] != now[p]) 'modified $p',
      for (final p in old.keys)
        if (!now.containsKey(p)) 'removed $p',
    };
    final got = {for (final c in e.changes) '${c.type} ${c.doc.path}'};
    if (want.length != got.length || !want.containsAll(got)) {
      problems.add('$name: الفروق ${got.toList()..sort()} والصحيح ${want.toList()..sort()}');
    }
  }
}

void main() {
  test('نوافذ المستمعين المحدودة تطابق الحساب الكامل دائماً', () async {
    for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
      final rnd = Random(seed);
      final cloud = FakeCloud();
      final client = _Client(cloud);
      const coll = 'items';
      FieldPathSpec f(String n) => [n];
      final specs = <String, QuerySpec>{
        'بمرشّح وحدّ (ترتيب بالمعرّف)': QuerySpec(collection: coll, where: [
          [f('s'), '==', 'A']
        ], limit: 5),
        'بحدّ فقط': const QuerySpec(collection: coll, limit: 7),
        'ترتيب تنازلي بحقل وحدّ': QuerySpec(collection: coll, orderBy: [
          [f('t'), true]
        ], limit: 4),
        'مرشّح in وترتيب تصاعدي وحدّ': QuerySpec(collection: coll, where: [
          [f('s'), 'in', ['A', 'B']]
        ], orderBy: [
          [f('t'), false]
        ], limit: 6),
        'مؤشر وحدّ': QuerySpec(collection: coll, orderBy: [
          [f('t'), false]
        ], startAfter: [10], limit: 3),
        'آخر عدد': QuerySpec(collection: coll, orderBy: [
          [f('t'), false]
        ], limitToLast: 3),
        'بسيط بمرشّح': QuerySpec(collection: coll, where: [
          [f('s'), '==', 'B']
        ]),
        'حدّ كبير': QuerySpec(collection: coll, where: [
          [f('s'), '!=', 'C']
        ], limit: 1000),
      };
      final views = <_View>[];
      var lid = 0;
      for (final e in specs.entries) {
        final v = _View(e.key, e.value);
        views.add(v);
        final id = 'L${++lid}';
        client.onEvent(id, v.apply);
        await client.call('T', 'listen', {'id': id, 'query': e.value});
      }

      Map<String, Object?> randomData() => {
            's': ['A', 'B', 'C'][rnd.nextInt(3)],
            if (rnd.nextDouble() < 0.85) 't': rnd.nextInt(40),
            'n': rnd.nextInt(1000),
          };
      String randomPath() => '$coll/d${rnd.nextInt(45).toString().padLeft(2, '0')}';

      var offline = false;
      for (var step = 0; step < 900; step++) {
        // انقطاع جهاز المستمعين أحياناً ثم عودته (لقطة كاملة عند العودة)
        if (rnd.nextDouble() < 0.02) {
          offline = !offline;
          cloud.setOnline('T', !offline);
        }
        final n = rnd.nextDouble() < 0.2 ? 2 + rnd.nextInt(3) : 1;
        final ops = <WriteOp>[];
        for (var k = 0; k < n; k++) {
          final p = randomPath();
          final r = rnd.nextDouble();
          if (r < 0.45) {
            ops.add(WriteOp('set', p, data: randomData()));
          } else if (r < 0.6) {
            ops.add(WriteOp('set', p, data: {'t': rnd.nextInt(40)}, merge: true));
          } else if (r < 0.8 && cloud.docs.containsKey(p) && !ops.any((o) => o.path == p)) {
            ops.add(WriteOp('update', p,
                updates: rnd.nextBool() ? {'s': ['A', 'B', 'C'][rnd.nextInt(3)]} : {'n': rnd.nextInt(9)}));
          } else {
            ops.add(WriteOp('delete', p));
          }
        }
        await client.call('W', 'write', {'ops': ops});
        if (offline) continue;
        for (final v in views) {
          final want = (await client.call('W', 'query', {'spec': v.spec}) as List).cast<DocSnap>();
          final got = v.docs;
          final a = [for (final d in got) '${d.path}@${d.version}'];
          final b = [for (final d in want) '${d.path}@${d.version}'];
          if (a.join(',') != b.join(',')) {
            v.problems.add('seed=$seed خطوة $step ${v.name}: عند المستمع $a والصحيح $b');
          }
        }
        final bad = [for (final v in views) ...v.problems];
        if (bad.isNotEmpty) fail(bad.take(5).join('\n'));
      }
      if (offline) cloud.setOnline('T', true);
      print('seed=$seed: ${[for (final v in views) '${v.name}=${v.events} (فروق ${v.diffEvents})'].join('، ')}');
      final how = cloud.costs.keys.where((k) => k.contains('إشعار')).toList()..sort();
      print('   طرق الإشعار: ${how.map((k) => '${k.trim()}×${cloud.costs[k]![0]}').join('، ')}');
      client.rp.close();
      cloud.close();
    }
  });
}
