// فاتورة دين حذفها مالكها بعد «بياناتي صحيحة» على جهاز آخر، ثم انضم جهاز
// جديد: كان يرث صف دينها يتيماً (نسخة الكشف أو مجموعة transactions)، لأن
// الفاتورة في bebet تُحذف نهائياً فلا يجدها ليتجاهل الصف (اختبار الفوضى 730).
// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Future<void> _expectSettled(Harness h, String cust, String stage) async {
  final errs = await h.settle();
  if (errs.isNotEmpty) {
    print('── $stage');
    print(errs.join('\n'));
    print(await h.explain(cust));
  }
  expect(errs, isEmpty, reason: stage);
}

void main() {
  test('فاتورة محذوفة بعد «بياناتي صحيحة»: الجهاز المنضم بعدها لا يرث دينها', () async {
    final h = Harness(seed: 11);
    try {
      await h.start(3);
      final c = (await h.addCustomer('D3', 'زبون الفاتورة المحذوفة'))!;
      await _expectSettled(h, c, 'بعد إضافة العميل');
      await h.addTx('D1', c, 50);
      final inv = (await h.saveInvoice('D3', c, 3000, 0, 'دين'))!;
      await _expectSettled(h, c, 'بعد حفظ الفاتورة');

      h.armored++;
      await h.d('D2').call('armoredPush', {'cust': c});
      await h.waitCloudQuiet(quiet: const Duration(seconds: 3));
      await _expectSettled(h, c, 'بعد «بياناتي صحيحة»');

      await h.deleteInvoice('D3', inv);
      await _expectSettled(h, c, 'بعد حذف الفاتورة');

      await h.joinNewDevice();
      await _expectSettled(h, c, 'جهاز انضم بعد الحذف');

      await h.restartAll(); // سحب كامل على كل الأجهزة
      await _expectSettled(h, c, 'بعد إعادة تشغيل الجميع');
      print('أخطاء غير ممسوكة: ${await h.deviceErrors()}');
    } finally {
      await h.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
