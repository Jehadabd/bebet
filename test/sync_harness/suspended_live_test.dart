// الفاتورة المعلّقة لا تساهم في الدين حتى تُحفظ (كما في المرجع)، وصفوف
// «التعديل الحي» التي كتبها الإصدار السابق تُلغى بشاهد حذف يتزامن.
// كان الحفظ النهائي يحذفها حذفاً نهائياً فتعود من السحابة: دين مضاعف على
// كل الأجهزة (2000 بدل 1000).
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Future<void> _run(String title,
    Future<void> Function(Harness h, String cust) body) async {
  final h = Harness(seed: 7);
  try {
    await h.start(2);
    final c = await h.addCustomer('D1', 'زبون $title');
    expect(c, isNotNull);
    await body(h, c!);
    print('أخطاء غير ممسوكة: ${await h.deviceErrors()}');
  } finally {
    await h.dispose();
  }
}

Future<void> _expectSettled(Harness h, String cust, String stage) async {
  final errs = await h.settle();
  if (errs.isNotEmpty) {
    print('── $stage');
    print(errs.join('\n'));
    print(await h.explain(cust));
  }
  expect(errs, isEmpty, reason: stage);
}

Future<String> _finalize(Harness h, String cust, int id) async {
  final uuid = await h.d('D1').call('finalizeSuspended', {'id': id}) as String;
  h.truth.invoices[uuid] = TruthInvoice(cust, 'D1', 1000, 0, 'دين', 'محفوظة');
  return uuid;
}

void main() {
  const t = Timeout(Duration(minutes: 10));

  test('معلّقة بلا دين حتى تُحفظ، ثم دينها على الجهازين', () async {
    await _run('المعلّقة', (h, c) async {
      final id = await h.d('D1').call('liveSuspended', {'cust': c, 'total': 1000.0}) as int;
      await _expectSettled(h, c, 'أثناء التعليق: الرصيد صفر على الجهازين');
      await _finalize(h, c, id);
      await _expectSettled(h, c, 'بعد الحفظ: 1000 على الجهازين');
    });
  }, timeout: t);

  test('صف تعديل حي قديم ثم حفظ نهائي: لا دين مضاعف', () async {
    await _run('الصف القديم', (h, c) async {
      final id = await h.d('D1').call('liveSuspended',
          {'cust': c, 'total': 1000.0, 'legacy': true}) as int;
      await h.settle(rounds: 1); // الصف القديم يُرفع كما كان يحدث قبل التحديث
      await _finalize(h, c, id);
      await _expectSettled(h, c, 'بعد الحفظ: 1000 على الجهازين');
    });
  }, timeout: t);

  test('صف تعديل حي قديم ثم تحديث التطبيق: يُلغى على الجهازين', () async {
    await _run('التحديث', (h, c) async {
      final id = await h.d('D1').call('liveSuspended',
          {'cust': c, 'total': 1000.0, 'legacy': true}) as int;
      await h.settle(rounds: 1);
      await h.restart('D1'); // أول تشغيل بعد التحديث
      await _expectSettled(h, c, 'بعد التحديث: الفاتورة معلّقة فالرصيد صفر');
      await h.joinNewDevice(); // جهاز جديد يستلم الحزمة وشاهد الحذف
      await _expectSettled(h, c, 'جهاز جديد: الرصيد صفر');
      await _finalize(h, c, id);
      await _expectSettled(h, c, 'بعد الحفظ: 1000 على الجهازين');
    });
  }, timeout: t);
}
