// اختبار الحمل: ثلاثة أجهزة (ثلاثة مستخدمين) تعمل بالتوازي على كود التطبيق
// الحقيقي (قاعدة بيانات لكل جهاز + سحابة Firestore وهمية مشتركة).
//
// كل جهاز: 500 عميل، 500 فاتورة تُعدَّل كل منها 10 مرات بكل السيناريوهات
// (دين↔نقد، تسديد جزئي/كامل، بنود، خصم، أجور تحميل، أسعار، كميات، معلّقة ثم
// محفوظة، معلّقة للأبد، حذف)، و10 معاملات يدوية لكل عميل تُعدَّل وتُحوَّل.
// أنواع العملاء:
//   منفرد: ينشئه جهاز ويعمل عليه وحده؛ الباقون يستلمونه من المزامنة فقط.
//   مشترك: كل الأجهزة تضيف له معاملات وفواتير.
//   عند غيره: منشئه لا يضيف له شيئاً؛ معاملاته وفواتيره من الأجهزة الأخرى.
// مع انقطاع إنترنت وإعادة تشغيل أثناء العمل، ثم حذف عملاء، ثم إعادة تشغيل
// الجميع، ثم جهاز رابع ينضم ويسحب كل شيء.
//
// التحقق بعد كل مرحلة، على كل جهاز، مقابل «الحقيقة» التي يسجّلها الاختبار:
//   • رصيد كل عميل = مجموع معاملاته = الحقيقة.
//   • لكل عميل: مجموع ما أنشأه كل جهاز (معاملات + ديون فواتير) = الحقيقة.
//   • كل فاتورة: الإجمالي، المسدد، نوع الدفع، الحالة، البنود، ومساهمتها في الدفتر.
//   • لا فواتير زائدة، لا تكرار معاملات أو فواتير، لا صف بلا مصدر معروف،
//     ولا شيء عالق بانتظار الرفع.
//
//   flutter test test/sync_harness/load_test.dart
//   flutter test test/sync_harness/load_test.dart --dart-define=CUSTOMERS=60 --dart-define=INVOICES=60
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

const _nDevices = int.fromEnvironment('DEVICES', defaultValue: 3);
const _nCustomers = int.fromEnvironment('CUSTOMERS', defaultValue: 500); // لكل جهاز
const _nInvoices = int.fromEnvironment('INVOICES', defaultValue: 500); // لكل جهاز
const _invEdits = int.fromEnvironment('INV_EDITS', defaultValue: 10);
const _txPerCustomer = int.fromEnvironment('TXS', defaultValue: 10);
const _txEdits = int.fromEnvironment('TX_EDITS', defaultValue: 2);
const _custDeletes = int.fromEnvironment('DELETES', defaultValue: 5); // لكل جهاز
const _seed = int.fromEnvironment('SEED', defaultValue: 1);
const _join = bool.fromEnvironment('JOIN', defaultValue: true);
// حدّ زمني للاختبار كله: الحجم الكامل مع نقاط التحقق والسحب الكامل يطول
const _timeoutHours = int.fromEnvironment('TIMEOUT_H', defaultValue: 16);
// وتيرة كل جهاز: عملية كل PACE_MS على الأكثر (250 = 4 عمليات/ث، أسرع بكثير من
// أي مستخدم). التطبيق يحدّ الرفع بـ600 عملية/دقيقة و20000/ساعة لكل جهاز، وما
// زاد يُؤجَّل للدورة التالية؛ بلا وتيرة (نحو 100 عملية/ث) يبني الاختبار طابوراً
// لا يعيشه مستخدم حقيقي، ويبلغ حدّ الساعة فيتوقف الرفع حتى تمضي.
const _paceMs = int.fromEnvironment('PACE_MS', defaultValue: 250);

const _solo = 'منفرد';
const _shared = 'مشترك';
const _others = 'عند غيره';

class _Cust {
  final String uuid;
  final String creator;
  final String cat;
  final String name;
  _Cust(this.uuid, this.creator, this.cat, this.name);
}

/// حالة فاتورة كما يراها مالكها (ما سيُحفظ في التعديل التالي).
class _Inv {
  final String cust;
  List<List<double>> lines;
  double discount;
  double fee;
  String ptype;
  double paid;
  String status;
  final List<String> plan; // سيناريوهات التعديلات بالترتيب
  int done = 0;
  _Inv(this.cust, this.lines, this.discount, this.fee, this.ptype, this.paid, this.status,
      this.plan);

  double get items => lines.fold(0.0, (s, l) => s + l[0] * l[1]);
  double get total => items + fee - discount;
}

class _Load {
  final Harness h;
  final Random rnd;
  final List<String> devs;
  final Map<String, _Cust> custs = {};
  final Map<String, List<String>> opErrors = {};
  final Map<String, int> retries = {};
  final Map<String, int> opsDone = {};
  final Map<String, Map<String, int>> kinds = {}; // جهاز ← سيناريو ← عدد
  final Map<String, int> invCreated = {};
  final Map<String, int> invDeleted = {};
  final Map<String, int> txCreated = {};
  final Map<String, int> txEdited = {};
  final Map<String, int> txConverted = {};
  final List<String> deletedCustomers = [];
  final Stopwatch sw = Stopwatch()..start();
  // قياس: زمن كل نوع عملية، ومجموع زمن عمليات كل جهاز، وانشغال السحابة
  final Map<String, List<int>> opTime = {}; // عملية ← [عدد، مجموع ms، أقصى ms]
  final Map<String, int> opMs = {};
  final Map<String, List<int>> _lastMark = {}; // جهاز ← [زمن ms، مجموع زمن عملياته، انشغال السحابة µs]

  // ── نقاط تحقق حسابي أثناء العمل: كل الأجهزة تتوقف معاً، تتزامن، ويُدقَّق كل
  // شيء مقابل الحقيقة، ثم تكمل. إن انقطع الاختبار بعدها (إعادة تشغيل الخادم)
  // يبقى ما تحقّق حتى آخر نقطة نتيجةً مثبتة.
  static const checkpointAt = [0.20, 0.40, 0.70, 0.95];
  final Map<int, int> _arrived = {};
  final Map<int, Completer<void>> _released = {};

  Future<void> checkpoint(int k) async {
    _arrived[k] = (_arrived[k] ?? 0) + 1;
    final done = _released[k] ??= Completer<void>();
    if (_arrived[k] == devs.length) {
      final label = '${(checkpointAt[k] * 100).round()}% من العمل';
      log('⏸️ نقطة تحقق عند $label: الأجهزة متوقفة للتدقيق');
      try {
        await verify('نقطة تحقق عند $label');
        await report();
      } finally {
        done.complete();
      }
    }
    await done.future;
  }

  _Load(this.h, this.rnd, this.devs);

  void log(String s) => print('[${(sw.elapsed.inSeconds / 60).toStringAsFixed(1)}د] $s');

  // ─────────────────────── أدوات ───────────────────────

  static const _debts = [1000.0, 2500.0, 5000.0, 12500.0, 25000.0, 100000.0, 250000.0, 750.5, 333.25];
  static const _pays = [-500.0, -1000.0, -2500.0, -10000.0, -50000.0, -125.5];
  static const _prices = [250.0, 1000.0, 1500.0, 2750.0, 12000.0, 125000.0, 99.5, 333.33];
  static const _qtys = [1.0, 2.0, 3.0, 5.0, 10.0, 0.5];

  T pick<T>(List<T> l) => l[rnd.nextInt(l.length)];

  bool _transient(Object e) {
    final s = e.toString();
    return s.contains('ممنوع') || s.contains('قفل') || s.contains('lock') || s.contains('Lock');
  }

  /// عملية مستخدم: إعادة المحاولة عند المنع المؤقت (مزامنة/مطابقة حية جارية).
  Future<T?> op<T>(String dev, String what, Future<T> Function() f) async {
    final t0 = sw.elapsedMilliseconds;
    try {
      for (var attempt = 0; attempt < 40; attempt++) {
        try {
          final v = await f();
          opsDone[dev] = (opsDone[dev] ?? 0) + 1;
          return v;
        } catch (e) {
          if (_transient(e) && attempt < 39) {
            retries[dev] = (retries[dev] ?? 0) + 1;
            await Future<void>.delayed(Duration(milliseconds: 200 + rnd.nextInt(400)));
            continue;
          }
          (opErrors[dev] ??= []).add('$what: ${e.toString().split('\n').first}');
          return null;
        }
      }
      return null;
    } finally {
      final ms = sw.elapsedMilliseconds - t0;
      final k = what.startsWith('فاتورة: إنشاء')
          ? 'فاتورة: إنشاء'
          : what.startsWith('فاتورة:')
              ? 'فاتورة: تعديل'
              : what;
      final e = opTime[k] ??= [0, 0, 0];
      e[0]++;
      e[1] += ms;
      if (ms > e[2]) e[2] = ms;
      opMs[dev] = (opMs[dev] ?? 0) + ms;
    }
  }

  void count(String dev, String kind) {
    final m = kinds[dev] ??= {};
    m[kind] = (m[kind] ?? 0) + 1;
  }

  // ─────────────────────── المرحلة 1: العملاء ───────────────────────

  Future<void> createCustomers(String dev) async {
    final cats = [_solo, _shared, _others];
    for (var i = 0; i < _nCustomers; i++) {
      final name = 'عميل $dev-${(i + 1).toString().padLeft(3, '0')}';
      final u = await op(dev, 'addCustomer', () => h.addCustomer(dev, name));
      if (u != null) custs[u] = _Cust(u, dev, cats[i % 3], name);
    }
  }

  // ─────────────────────── المرحلة 2: العمل اليومي ───────────────────────

  /// من يضيف لهذا العميل معاملات/فواتير.
  List<String> actors(_Cust c) {
    if (c.cat == _solo) return [c.creator];
    if (c.cat == _shared) return devs;
    return devs.where((d) => d != c.creator).toList();
  }

  List<String> invoicePlan(String kind) {
    const all = [
      'بند جديد', 'حذف بند', 'إلى نقد', 'إلى دين', 'تسديد جزئي',
      'تسديد كامل', 'خصم', 'أجور تحميل', 'تغيير الأسعار', 'تغيير الكميات',
    ];
    final plan = <String>[];
    if (kind == 'معلّقة ثم محفوظة') {
      plan.addAll(['تعديل وهي معلّقة', 'حفظ المعلّقة']);
    } else if (kind == 'معلّقة للأبد') {
      while (plan.length < _invEdits) {
        plan.add('تعديل وهي معلّقة');
      }
      return plan;
    }
    final rest = [...all]..shuffle(rnd);
    while (plan.length < _invEdits) {
      plan.add(rest[plan.length % rest.length]);
    }
    return plan.take(_invEdits).toList();
  }

  List<List<double>> randomLines() =>
      [for (var k = 0; k < 1 + rnd.nextInt(4); k++) [pick(_qtys), pick(_prices)]];

  /// يطبّق سيناريو التعديل على حالة الفاتورة (حالة صالحة دائماً كما في الشاشة).
  void mutate(_Inv v, String kind) {
    switch (kind) {
      case 'بند جديد':
        v.lines.add([pick(_qtys), pick(_prices)]);
      case 'حذف بند':
        if (v.lines.length > 1) {
          v.lines.removeAt(rnd.nextInt(v.lines.length));
        } else {
          v.lines[0][0] = v.lines[0][0] > 1 ? v.lines[0][0] - 1 : 0.5;
        }
      case 'إلى نقد':
        v.ptype = 'نقد';
      case 'إلى دين':
        v.ptype = 'دين';
        v.paid = 0;
      case 'تسديد جزئي':
        v.ptype = 'دين';
        v.paid = (v.total * pick([0.25, 0.5, 0.75])).floorToDouble() + pick([0.0, 0.5]);
      case 'تسديد كامل':
        v.ptype = 'دين';
        v.paid = v.total;
      case 'خصم':
        v.discount = pick([0.0, 250.0, 1000.0, 99.5, 0.99]);
      case 'أجور تحميل':
        v.fee = pick([0.0, 500.0, 2000.0, 7500.0]);
      case 'تغيير الأسعار':
        for (final l in v.lines) {
          l[1] = pick(_prices);
        }
      case 'تغيير الكميات':
        for (final l in v.lines) {
          l[0] = pick(_qtys);
        }
      case 'تعديل وهي معلّقة':
        v.lines = randomLines();
        v.paid = rnd.nextBool() ? 0 : (v.items * 0.5).floorToDouble();
      case 'حفظ المعلّقة':
        v.status = 'محفوظة';
    }
    // قيود الشاشة: الخصم أقل من الإجمالي، والمسدد بين صفر والإجمالي، والنقد مسدد بالكامل
    if (v.discount >= v.items + v.fee) v.discount = 0;
    if (v.ptype == 'نقد') {
      v.paid = v.total;
    } else if (v.paid > v.total) {
      v.paid = v.total;
    } else if (v.paid < 0) {
      v.paid = 0;
    }
  }

  Future<String?> saveInvoice(String dev, _Inv v, String? uuid, String kind) async {
    final r = await op(dev, 'فاتورة: $kind', () async {
      final m = (await h.d(dev).call('saveInvoiceX', {
        'cust': v.cust,
        'inv': uuid,
        'lines': v.lines,
        'discount': v.discount,
        'fee': v.fee,
        'ptype': v.ptype,
        'paid': v.paid,
        'status': v.status,
      }) as Map)
          .cast<String, Object?>();
      return m;
    });
    if (r == null) return null;
    final u = r['uuid'] as String;
    final prev = h.truth.invoices[u];
    final ti = TruthInvoice(v.cust, dev, v.total, v.paid, v.ptype, v.status);
    if (prev != null) ti.voidedFor = {...prev.voidedFor};
    h.truth.invoices[u] = ti;
    final savedTotal = (r['total'] as num).toDouble();
    if ((savedTotal - v.total).abs() > 0.01) {
      (opErrors[dev] ??= []).add('فاتورة $u: الإجمالي المحفوظ $savedTotal والمتوقع ${v.total}');
    }
    count(dev, kind);
    return u;
  }

  Future<void> worker(String dev, Map<String, List<String>> txPlan, List<String> invPlan) async {
    final txQueue = [...?txPlan[dev]]..shuffle(rnd);
    final invQueue = [...invPlan]..shuffle(rnd);
    final txEdits = <String, int>{}; // معاملة ← تعديلات متبقية
    final invs = <String, _Inv>{}; // فاتورة ← حالتها
    final total = txQueue.length * (1 + _txEdits) + invQueue.length * (1 + _invEdits);
    var steps = 0;
    final offlineAt = {total * 25 ~/ 100, total * 60 ~/ 100, total * 85 ~/ 100};
    final restartAt = total ~/ 2;
    var offlineLeft = 0;
    const creations = [
      'دين محفوظة', 'دين محفوظة', 'دين محفوظة', 'دين محفوظة', 'دين محفوظة', 'دين محفوظة',
      'دين محفوظة', 'نقد محفوظة', 'نقد محفوظة', 'معلّقة ثم محفوظة',
    ];
    var created = 0;
    var nextAt = 0; // موعد الخطوة التالية (ms) — بلا تعويض بدفعة بعد توقف

    while (true) {
      final pendingInvEdits = invs.entries.where((e) => e.value.done < e.value.plan.length).toList();
      final pendingTxEdits = txEdits.entries.where((e) => e.value > 0).toList();
      final w = [
        txQueue.length.toDouble(),
        pendingTxEdits.length.toDouble(),
        invQueue.length.toDouble(),
        pendingInvEdits.length.toDouble() * 2,
      ];
      final sum = w.fold(0.0, (a, b) => a + b);
      if (sum == 0) break;
      if (_paceMs > 0) {
        final now = sw.elapsedMilliseconds;
        if (nextAt > now) await Future<void>.delayed(Duration(milliseconds: nextAt - now));
        nextAt = max(nextAt, sw.elapsedMilliseconds) + _paceMs;
      }
      steps++;
      for (var k = 0; k < checkpointAt.length; k++) {
        if (steps == (total * checkpointAt[k]).floor()) {
          await checkpoint(k);
          // التدقيق يوصل كل الأجهزة؛ من كان في انقطاع يكمل انقطاعه
          if (offlineLeft > 0) await h.setOnline(dev, false);
        }
      }
      if (steps % 1000 == 0) {
        final now = [sw.elapsedMilliseconds, opMs[dev] ?? 0, h.cloud.busyMicros];
        final last = _lastMark[dev] ?? [0, 0, 0];
        _lastMark[dev] = now;
        final wall = max(1, now[0] - last[0]);
        log('$dev: $steps/$total عملية (أخطاء ${opErrors[dev]?.length ?? 0}، إعادات ${retries[dev] ?? 0}، '
            'متوسط العملية ${(now[1] - last[1]) ~/ 1000}ms، انشغال السحابة '
            '${((now[2] - last[2]) / 10 / wall).round()}%)');
      }
      // 📴 انقطاع الإنترنت أثناء العمل، ثم عودته
      if (offlineAt.contains(steps)) {
        await h.setOnline(dev, false);
        offlineLeft = 150;
        log('$dev: انقطع الإنترنت');
      } else if (offlineLeft > 0 && --offlineLeft == 0) {
        await h.setOnline(dev, true);
        log('$dev: عاد الإنترنت');
      }
      // 🔁 إغلاق التطبيق وفتحه في منتصف العمل
      if (steps == restartAt) {
        log('$dev: إعادة تشغيل التطبيق');
        await h.restart(dev);
      }
      // 👁️ المستخدم يفتح سجل عميل أحياناً (يشغّل شبكة أمان الحارس)
      if (rnd.nextDouble() < 0.03 && custs.isNotEmpty) {
        final c = custs.values.elementAt(rnd.nextInt(custs.length));
        await op(dev, 'عرض عميل', () => h.d(dev).call('viewCustomer', {'cust': c.uuid}));
      }

      var x = rnd.nextDouble() * sum;
      if ((x -= w[0]) < 0) {
        // ➕ معاملة يدوية جديدة (دين أو تسديد)
        final cu = txQueue.removeLast();
        final amount = rnd.nextDouble() < 0.6 ? pick(_debts) : pick(_pays);
        final tu = await op(dev, 'إضافة معاملة', () => h.addTx(dev, cu, amount));
        if (tu != null) {
          txEdits[tu] = _txEdits;
          txCreated[dev] = (txCreated[dev] ?? 0) + 1;
        }
      } else if ((x -= w[1]) < 0) {
        // ✏️ تعديل معاملة: مبلغ جديد، أو تحويل دين↔تسديد
        final e = pendingTxEdits[rnd.nextInt(pendingTxEdits.length)];
        txEdits[e.key] = e.value - 1;
        final t = h.truth.txs[e.key];
        if (t == null || t.deleted) continue;
        if (rnd.nextDouble() < 0.4) {
          final ok = await op(dev, 'تحويل معاملة', () async {
            await h.convertTx(dev, e.key);
            return true;
          });
          if (ok == true) txConverted[dev] = (txConverted[dev] ?? 0) + 1;
        } else {
          final mag = pick(_debts).abs();
          final ok = await op(dev, 'تعديل معاملة', () async {
            await h.editTx(dev, e.key, t.amount < 0 ? -mag : mag);
            return true;
          });
          if (ok == true) txEdited[dev] = (txEdited[dev] ?? 0) + 1;
        }
      } else if ((x -= w[2]) < 0) {
        // 🧾 فاتورة جديدة
        final cu = invQueue.removeLast();
        final kind = created % 50 == 49 ? 'معلّقة للأبد' : creations[created % creations.length];
        created++;
        final v = _Inv(cu, randomLines(), rnd.nextDouble() < 0.3 ? 250 : 0,
            rnd.nextDouble() < 0.3 ? 500 : 0, kind.startsWith('نقد') ? 'نقد' : 'دين', 0,
            kind.startsWith('معلّقة') ? 'معلقة' : 'محفوظة', invoicePlan(kind));
        mutate(v, 'بلا تغيير');
        if (v.ptype == 'دين' && rnd.nextDouble() < 0.3) v.paid = (v.total * 0.4).floorToDouble();
        final u = await saveInvoice(dev, v, null, 'إنشاء: $kind');
        if (u != null) {
          invs[u] = v;
          invCreated[dev] = (invCreated[dev] ?? 0) + 1;
        }
      } else {
        // 🔧 تعديل فاتورة (كل فاتورة تُعدَّل بخطتها كاملة)
        final e = pendingInvEdits[rnd.nextInt(pendingInvEdits.length)];
        final v = e.value;
        final kind = v.plan[v.done];
        v.done++;
        final before = [
          [for (final l in v.lines) [...l]], v.discount, v.fee, v.ptype, v.paid, v.status
        ];
        mutate(v, kind);
        final u = await saveInvoice(dev, v, e.key, kind);
        if (u == null) {
          // فشل الحفظ: الحالة تبقى كما كانت
          v.lines = (before[0] as List).cast<List<double>>();
          v.discount = before[1] as double;
          v.fee = before[2] as double;
          v.ptype = before[3] as String;
          v.paid = before[4] as double;
          v.status = before[5] as String;
        }
      }
    }
    if (offlineLeft > 0) await h.setOnline(dev, true);

    // 🗑️ حذف بعض الفواتير (3٪) من مالكها
    final own = invs.keys.toList()..shuffle(rnd);
    for (final u in own.take((own.length * 3 / 100).ceil())) {
      final ok = await op(dev, 'حذف فاتورة', () async {
        final before = h.deletedInvoices;
        await h.deleteInvoice(dev, u);
        return h.deletedInvoices > before;
      });
      if (ok == true) invDeleted[dev] = (invDeleted[dev] ?? 0) + 1;
    }
    log('$dev: انتهى ($steps عملية)');
  }

  // ─────────────────────── التحقق ───────────────────────

  Map<String, double> truthByCreator() {
    final m = <String, double>{};
    void add(String cust, String who, double v) {
      final k = '$cust|$who';
      m[k] = (m[k] ?? 0) + v;
    }

    h.truth.txs.forEach((u, t) {
      if (!t.deleted) add(t.cust, t.owner, t.amount);
    });
    h.truth.invoices.forEach((u, i) {
      final c = i.contribution;
      if (c != 0) add(i.cust, i.creator, c);
    });
    return m;
  }

  Future<List<String>> audit(String stage) async {
    final errs = <String>[];
    final want = truthByCreator();
    for (final dev in h.devices.keys.toList()) {
      final a = (await h.d(dev).call('audit', const {}, const Duration(minutes: 10)) as Map)
          .cast<String, Object?>();
      if ((a['dupTx'] as int) != 0) errs.add('$dev: ${a['dupTx']} معاملة مكررة');
      if ((a['dupInv'] as int) != 0) errs.add('$dev: ${a['dupInv']} فاتورة مكررة');

      // مجموع كل جهاز منشئ لكل عميل
      final got = <String, double>{};
      var unknown = 0;
      String? unknownEx;
      for (final r in (a['rows'] as List).cast<List>()) {
        final u = r[0] as String?;
        final cs = r[1] as String?;
        final amt = r[2] as double;
        final inv = r[3] as String?;
        String? who;
        if (inv != null && inv.isNotEmpty) {
          who = h.truth.invoices[inv]?.creator;
        } else if (u != null) {
          who = h.truth.txs[u]?.owner;
        }
        if (who == null) {
          if (amt.abs() > 0.009) {
            unknown++;
            unknownEx ??= '$u مبلغ=$amt فاتورة=$inv نوع=${r[4]}';
          }
          continue;
        }
        final k = '$cs|$who';
        got[k] = (got[k] ?? 0) + amt;
      }
      if (unknown > 0) errs.add('$dev: $unknown صف فعّال بلا مصدر معروف، مثل $unknownEx');
      var bad = 0;
      String? badEx;
      for (final k in {...want.keys, ...got.keys}) {
        final diff = (want[k] ?? 0) - (got[k] ?? 0);
        if (diff.abs() > 0.01) {
          bad++;
          final parts = k.split('|');
          badEx ??= '${custs[parts[0]]?.name ?? parts[0]} من ${parts[1]}: '
              'على الجهاز ${got[k] ?? 0} والصحيح ${want[k] ?? 0}';
        }
      }
      if (bad > 0) errs.add('$dev: $bad مجموع (عميل × جهاز منشئ) مختلف، مثل $badEx');

      // الفواتير
      final devInv = <String, List>{
        for (final r in (a['invoices'] as List).cast<List>()) r[0] as String: r
      };
      var invBad = 0;
      String? invEx;
      h.truth.invoices.forEach((u, t) {
        final r = devInv.remove(u);
        String? why;
        if (r == null) {
          why = 'غائبة';
        } else if (r[1] != t.cust) {
          why = 'عميلها ${r[1]} والصحيح ${t.cust}';
        } else if (((r[2] as double) - t.total).abs() > 0.01) {
          why = 'الإجمالي ${r[2]} والصحيح ${t.total}';
        } else if (((r[3] as double) - t.paid).abs() > 0.01) {
          why = 'المسدد ${r[3]} والصحيح ${t.paid}';
        } else if (r[4] != t.ptype) {
          why = 'نوع الدفع ${r[4]} والصحيح ${t.ptype}';
        } else if (r[5] != t.status) {
          why = 'الحالة ${r[5]} والصحيح ${t.status}';
        } else if (((r[8] as double) + (r[7] as double) - (r[6] as double) - t.total).abs() > 0.01) {
          why = 'البنود ${r[8]} + التحميل ${r[7]} − الخصم ${r[6]} ≠ الإجمالي ${t.total}';
        } else if (((r[9] as double) - t.contribution).abs() > 0.01) {
          why = 'دينها في الدفتر ${r[9]} والصحيح ${t.contribution}';
        } else if (r[13] == 0) {
          // فاتورة مستلمة: السنتات تُحسب عند الاستلام ويجب ألا تنجرف عن المبلغ
          int c(double v) => (v * 100).round();
          if (r[10] != c(t.total)) {
            why = 'سنتات الإجمالي ${r[10]} والصحيح ${c(t.total)}';
          } else if (r[11] != c(r[6] as double)) {
            why = 'سنتات الخصم ${r[11]} والصحيح ${c(r[6] as double)}';
          } else if (r[12] != c(t.paid)) {
            why = 'سنتات المسدد ${r[12]} والصحيح ${c(t.paid)}';
          } else if ((r[14] as int) != 0) {
            why = '${r[14]} بند سنتاته لا تطابق مبلغه';
          }
        }
        if (why != null) {
          invBad++;
          invEx ??= '$u: $why';
        }
      });
      if (invBad > 0) errs.add('$dev: $invBad فاتورة مختلفة، مثل $invEx');
      if (devInv.isNotEmpty) {
        errs.add('$dev: ${devInv.length} فاتورة زائدة (محذوفة عادت؟) مثل ${devInv.keys.first}');
      }
    }
    return errs;
  }

  Future<void> verify(String stage) async {
    final t0 = sw.elapsed.inSeconds;
    var errs = await h.settle(rounds: 15);
    errs = [...errs, ...await audit(stage)];
    final uncaught = await h.deviceErrors();
    log('✔︎ تحقق «$stage»: ${errs.isEmpty ? 'مطابق تماماً' : '${errs.length} خلل'} '
        '(${sw.elapsed.inSeconds - t0}ث، أخطاء غير ممسوكة ${uncaught.length})');
    if (errs.isNotEmpty) {
      for (final e in errs.take(15)) {
        print('   ❌ $e');
      }
      // شرح أول عميل مختلف
      for (final e in errs) {
        final m = RegExp(r'(عميل D\d+-\d+)').firstMatch(e);
        if (m == null) continue;
        final c = custs.values.where((c) => c.name == m.group(1)).firstOrNull;
        if (c != null) print(await h.explain(c.uuid));
        break;
      }
    }
    for (final e in uncaught.take(3)) {
      print('   ⚠️ غير ممسوك: ${e.split('\n').first}');
    }
    expect(errs, isEmpty, reason: stage);
  }

  // ─────────────────────── التقرير ───────────────────────

  String money(double v) {
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
    final parts = s.split('.');
    final b = StringBuffer();
    for (var i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) b.write(',');
      b.write(parts[0][i]);
    }
    return '${neg ? '-' : ''}$b${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  Future<void> report() async {
    final t = h.truth;
    print('\n══════════════ تقرير اختبار الحمل ══════════════');
    print('المدة: ${(sw.elapsed.inSeconds / 60).toStringAsFixed(1)} دقيقة، '
        'كتابات سحابية: ${h.cloud.totalWrites}');
    for (final dev in devs) {
      final txs = t.txs.values.where((x) => x.owner == dev);
      final invs = t.invoices.values.where((i) => i.creator == dev);
      final saved = invs.where((i) => i.status == 'محفوظة');
      print('── $dev: عملاء ${custs.values.where((c) => c.creator == dev).length}، '
          'معاملات يدوية ${txCreated[dev] ?? 0} (عُدّلت ${txEdited[dev] ?? 0}، حُوّلت ${txConverted[dev] ?? 0})، '
          'فواتير ${invCreated[dev] ?? 0} (حُذفت ${invDeleted[dev] ?? 0})، '
          'عمليات ${opsDone[dev] ?? 0}، إعادات بسبب منع مؤقت ${retries[dev] ?? 0}');
      print('   صافي معاملاته اليدوية: ${money(txs.where((x) => !x.deleted).fold(0.0, (s, x) => s + x.amount))}'
          ' | مبيعات فواتيره المحفوظة: ${money(saved.fold(0.0, (s, i) => s + i.total))}'
          ' | ديون فواتيره: ${money(invs.fold(0.0, (s, i) => s + i.contribution))}');
      final k = kinds[dev] ?? const {};
      print('   سيناريوهات الفواتير: ${k.entries.map((e) => '${e.key}=${e.value}').join('، ')}');
      for (final e in (opErrors[dev] ?? const []).take(5)) {
        print('   ⚠️ رفض/خطأ عملية: $e');
      }
      if ((opErrors[dev]?.length ?? 0) > 5) print('   … و${opErrors[dev]!.length - 5} أخرى');
    }
    for (final cat in [_solo, _shared, _others]) {
      final cs = custs.values.where((c) => c.cat == cat);
      print('── عملاء «$cat»: ${cs.length}، مجموع أرصدتهم الصحيح '
          '${money(cs.fold(0.0, (s, c) => s + t.balance(c.uuid)))}');
    }
    final grand = custs.keys.fold(0.0, (s, u) => s + t.balance(u));
    print('── مجموع ديون كل العملاء الصحيح: ${money(grand)}');
    for (final dev in h.devices.keys) {
      final st = (await h.d(dev).call('state', const {}, Harness.stateTimeout) as Map)
          .cast<String, Object?>();
      final sum = (st['customers'] as List)
          .cast<Map>()
          .where((c) => (c['del'] ?? 0) == 0)
          .fold(0.0, (s, c) => s + (c['debt'] as double));
      print('   على $dev: ${money(sum)} ${(sum - grand).abs() <= 0.01 ? '✓' : '✗'}');
    }
    // أمثلة: عميل من كل نوع مع تفصيل ما أنشأه كل جهاز
    final want = truthByCreator();
    for (final cat in [_solo, _shared, _others]) {
      final c = custs.values.where((c) => c.cat == cat && !deletedCustomers.contains(c.uuid)).firstOrNull;
      if (c == null) continue;
      final parts = [
        for (final d in devs)
          if ((want['${c.uuid}|$d'] ?? 0) != 0) '$d: ${money(want['${c.uuid}|$d']!)}'
      ];
      print('   مثال «$cat» ${c.name} (أنشأه ${c.creator}): ${parts.join('، ')} '
          '= ${money(t.balance(c.uuid))}');
    }
    print('── أبطأ العمليات (العدد، المتوسط، الأقصى):');
    for (final e in (opTime.entries.toList()..sort((a, b) => b.value[1].compareTo(a.value[1]))).take(10)) {
      print('   ${e.key}: ${e.value[0]}× متوسط ${e.value[1] ~/ max(1, e.value[0])}ms أقصى ${e.value[2]}ms');
    }
    print('── أثقل البنود في السحابة الوهمية (العدد، المجموع، الأقصى) — انشغالها الكلي '
        '${(h.cloud.busyMicros / 1e6).round()}ث من ${sw.elapsed.inSeconds}ث:');
    for (final e in (h.cloud.costs.entries.toList()..sort((a, b) => b.value[1].compareTo(a.value[1]))).take(16)) {
      print('   ${e.key}: ${e.value[0]}× ${(e.value[1] / 1e6).toStringAsFixed(1)}ث '
          '(أقصى ${(e.value[2] / 1000).round()}ms)');
    }
    print('═══════════════════════════════════════════════\n');
  }
}

void main() {
  test('اختبار الحمل: $_nDevices أجهزة × ($_nCustomers عميل + $_nInvoices فاتورة × $_invEdits تعديلات)',
      () async {
    final h = Harness(seed: _seed)
      ..perDeviceSqlite = const bool.fromEnvironment('PER_DEVICE_SQLITE', defaultValue: true);
    final devs = [for (var i = 1; i <= _nDevices; i++) 'D$i'];
    final L = _Load(h, Random(_seed), devs);
    var failed = true;
    try {
      await h.start(_nDevices);
      L.log('بدأت $_nDevices أجهزة');

      // 1) العملاء
      await Future.wait([for (final d in devs) L.createCustomers(d)]);
      L.log('أُنشئ ${L.custs.length} عميل');
      await L.verify('بعد إنشاء العملاء');

      // خطة المعاملات: 10 لكل عميل موزعة على من يعمل عليه
      final txPlan = <String, List<String>>{};
      for (final c in L.custs.values) {
        final who = L.actors(c);
        if (who.isEmpty) continue;
        for (var k = 0; k < _txPerCustomer; k++) {
          (txPlan[who[k % who.length]] ??= []).add(c.uuid);
        }
      }
      // خطة الفواتير: كل جهاز يختار عملاءه المسموح له بهم
      final invPlan = <String, List<String>>{};
      for (final d in devs) {
        final allowed = L.custs.values.where((c) => L.actors(c).contains(d)).toList();
        if (allowed.isEmpty) continue;
        invPlan[d] = [
          for (var k = 0; k < _nInvoices; k++) allowed[L.rnd.nextInt(allowed.length)].uuid
        ];
      }

      // 2) العمل اليومي بالتوازي
      // خلل في نقطة تحقق يوقف الاختبار فوراً (لا ساعات عمل فوق بيانات مختلفة)
      await Future.wait([for (final d in devs) L.worker(d, txPlan, invPlan[d] ?? const [])],
          eagerError: true);
      await L.verify('بعد العمل اليومي');
      await L.report();
      if (const bool.fromEnvironment('SQLSTATS')) {
        for (final d in devs) {
          print('── أثقل جمل SQL على $d (العدد، مجموع ms، أقصى ms):');
          for (final r in (await h.d(d).call('sqlStats', {'n': 15}) as List).cast<List>()) {
            print('   ${r[1]}× ${r[2]}ms (أقصى ${r[3]}ms) ${r[0]}');
          }
        }
      }

      // 3) حذف عملاء (من كل نوع)
      if (_custDeletes > 0) {
        for (final d in devs) {
          final vis = L.custs.values.where((c) => !L.deletedCustomers.contains(c.uuid)).toList()
            ..shuffle(L.rnd);
          for (final c in vis.take(_custDeletes)) {
            final ok = await L.op(d, 'حذف عميل', () async {
              await h.deleteCustomer(d, c.uuid);
              return true;
            });
            if (ok == true) L.deletedCustomers.add(c.uuid);
          }
        }
        await L.verify('بعد حذف ${L.deletedCustomers.length} عميل');
      }

      // 4) إغلاق كل التطبيقات وفتحها
      await h.restartAll();
      await L.verify('بعد إعادة تشغيل كل الأجهزة');

      // 5) جهاز جديد ينضم ويسحب كل شيء
      if (_join) {
        await h.joinNewDevice();
        await L.verify('جهاز جديد انضم وسحب كل شيء');
      }
      await L.report();
      failed = false;
    } finally {
      await h.dispose(keepFiles: failed);
    }
  }, timeout: const Timeout(Duration(hours: _timeoutHours)));
}
