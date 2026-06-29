# توثيق تفصيلي جدًا لميزة نقاط المؤسسين

> هذا الملف يشرح **دورة التنفيذ الحقيقية من الكود** عند:
> - حفظ فاتورة جديدة
> - فتح فاتورة والتعديل عليها ثم حفظ التعديل
> - إضافة/تسديد دين راجع وتأثيره على نقاط المؤسس
>
> مع تضمين **الدوال نفسها (كود Dart)** وشرحها بالعربية.

---

## 1) الفكرة الأساسية للميزة

- يوجد إعداد عام: **عدد النقاط لكل 100,000** في `GeneralSettingsScreen`.
- عند إنشاء فاتورة، يتم أخذ هذا الإعداد كقيمة افتراضية لحقل معدل النقاط في شاشة الفاتورة.
- يمكن تغيير المعدل لكل فاتورة يدويًا، ثم يُحفظ داخل الفاتورة نفسها (`points_rate`).
- عند الحفظ:
  - يتم حساب نقاط المؤسس من إجمالي الفاتورة ومعدلها.
  - يتم تسجيل النقاط في `installer_points`.
  - يتم تحديث مجموع نقاط المؤسس `installers.total_points`.
- عند تعديل نفس الفاتورة:
  - لا يضيف دائمًا نقاط جديدة؛ بل يحسب الفرق بين النقاط القديمة والجديدة (`diff`).
- عند تسديد راجع:
  - يتم خصم نقاط من المؤسس حسب **معدل الفاتورة نفسها** وليس الإعداد العام.

---

## 2) أين يبدأ الاستدعاء؟ (زر حفظ الفاتورة)

في `CreateInvoiceScreen` زر الحفظ:

```dart
if (widget.settlementForInvoice == null)
  ElevatedButton.icon(
    onPressed: isSaving ? null : saveInvoice,
    icon: const Icon(Icons.save),
    label: const Text('حفظ الفاتورة'),
  )
```

### ماذا يعني هذا؟
- عند الضغط على زر **حفظ الفاتورة** يتم استدعاء `saveInvoice()` مباشرة.
- `saveInvoice()` موجودة داخل `InvoiceActionsMixin` في ملف `invoice_actions.dart`.
- هذه هي نقطة الانطلاق الرئيسية لدورة الحفظ.

---

## 3) دورة فتح فاتورة موجودة للتعديل

عند فتح الشاشة في وضع تعديل، `initState()` في `CreateInvoiceScreen` يقوم بتحميل بيانات الفاتورة الحالية ومنها معدل النقاط:

```dart
if (invoiceToManage != null) {
  customerNameController.text = invoiceToManage!.customerName;
  customerPhoneController.text = invoiceToManage!.customerPhone ?? '';
  customerAddressController.text = invoiceToManage!.customerAddress ?? '';
  installerNameController.text = invoiceToManage!.installerName ?? '';
  selectedDate = invoiceToManage!.invoiceDate;
  paymentType = invoiceToManage!.paymentType;
  _totalAmountController.text = formatNumber(invoiceToManage!.totalAmount);
  paidAmountController.text = formatNumber(invoiceToManage!.amountPaidOnInvoice);
  discount = invoiceToManage!.discount;
  discountController.text = formatNumber(discount);

  // تحميل معدل النقاط من الفاتورة الموجودة
  _installerPointsRate = invoiceToManage!.pointsRate;
  _installerPointsRateController.text = _installerPointsRate.toString();

  noteController.text = invoiceToManage!.notes ?? '';
  _loadInvoiceItems();
}
```

### شرح وظيفي
- النظام **لا يرجع للإعداد العام** هنا.
- بل يحمل `pointsRate` من نفس الفاتورة القديمة.
- هذا مهم جدًا لأنه يثبت أن كل فاتورة لها معدل نقاط مستقل محفوظ معها.

---

## 4) دورة الفاتورة الجديدة (تحميل المعدل الافتراضي)

إذا كانت الفاتورة جديدة (`existingInvoice == null`) يتم تحميل الإعداد العام:

```dart
Future<void> _loadDefaultPointsRate() async {
  try {
    final settings = await SettingsManager.getAppSettings();
    setState(() {
      _installerPointsRate = settings.pointsPerHundredThousand;
      _installerPointsRateController.text = _installerPointsRate.toString();
      _autoScrollEnabled = settings.autoScrollInvoice;
    });
  } catch (e) {
    print('Error loading default points rate: $e');
    _installerPointsRateController.text = '1.0';
  }
}
```

### شرح وظيفي
- يجلب `AppSettings` من التخزين.
- يضع `pointsPerHundredThousand` داخل `_installerPointsRate`.
- هذه فقط قيمة بداية، ويمكن للمستخدم تعديلها في الشاشة قبل الحفظ.

---

## 5) كود حفظ الفاتورة (القلب الرئيسي)

هذه أهم دالة في الدورة: `saveInvoice()` في `invoice_actions.dart`.

## 5.1 مقطع البداية والتحقق

```dart
Future<Invoice?> saveInvoice({bool printAfterSave = false}) async {
  cancelLiveDebtTimer();

  if (isSaving) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('جاري الحفظ بالفعل...'),
      backgroundColor: Colors.orange,
    ));
    return null;
  }

  if (!formKey.currentState!.validate()) return null;

  setState(() {
    isSaving = true;
  });

  try {
    final bool isNewInvoice = invoiceToManage == null;

    final preValidation = _validateInvoiceDataBeforeSave();
    if (!preValidation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ في البيانات: ${preValidation.errorMessage}'),
        backgroundColor: Colors.red,
      ));
      setState(() => isSaving = false);
      return null;
    }
```

### ماذا يحدث هنا؟
- يوقف مزامنة الدين الحي.
- يمنع الحفظ المكرر إذا عملية حفظ شغالة.
- يفحص صحة النموذج.
- يحدد هل الفاتورة جديدة أم تعديل.
- ينفذ تحقق مالي أولي قبل الدخول للمعاملة.

## 5.2 إنشاء الفاتورة وحفظ `pointsRate`

```dart
Invoice invoice = Invoice(
  id: invoiceToManage?.id,
  customerName: customerNameController.text,
  customerPhone: normalizedPhoneForInvoice,
  customerAddress: customerAddressController.text,
  installerName: installerNameController.text.isEmpty
      ? null
      : installerNameController.text,
  invoiceDate: selectedDate,
  paymentType: paymentType,
  totalAmount: totalAmount,
  discount: discount,
  amountPaidOnInvoice: paid,
  loadingFee: loadingFee,
  createdAt: invoiceToManage?.createdAt ?? DateTime.now(),
  lastModifiedAt: DateTime.now(),
  customerId: customer?.id,
  status: newStatus,
  isLocked: false,
  notes: noteController.text.trim().isNotEmpty ? noteController.text.trim() : null,
  pointsRate: installerPointsRate, // حفظ معدل النقاط مع الفاتورة
);
```

### ماذا يعني سطر `pointsRate: installerPointsRate`؟
- هذا أهم سطر بالميزة.
- يربط معدل النقاط بالفاتورة نفسها.
- لاحقًا عند الراجع يتم استخدام هذا المعدل المخزن في الفاتورة.

## 5.3 تحديث نقاط المؤسس بعد حفظ الفاتورة

```dart
if (savedInvoice != null &&
    savedInvoice!.installerName != null &&
    savedInvoice!.installerName!.isNotEmpty) {
  try {
    final double pointsRate = installerPointsRate;

    await db.updateInstallerPointsFromInvoice(
      savedInvoice!.id!,
      savedInvoice!.installerName!,
      savedInvoice!.totalAmount,
      pointsPerHundredThousand: pointsRate,
    );

    final installer = await db.getInstallerByName(savedInvoice!.installerName!);
    if (installer != null && installer.id != null) {
      await db.updateInstallerBilledAmount(installer.id!);
    }
  } catch (e) {
    print('Error updating installer points/amount: $e');
  }
}
```

### شرح الدورة هنا
- إذا الفاتورة فيها اسم مؤسس:
  1. يستدعي `updateInstallerPointsFromInvoice` لحساب/تعديل نقاط هذه الفاتورة.
  2. يستدعي `updateInstallerBilledAmount` لتحديث إجمالي مبالغ فواتير هذا المؤسس.

---

## 6) الدالة الفعلية لحساب/تعديل النقاط من الفاتورة

الدالة: `DatabaseService.updateInstallerPointsFromInvoice(...)`

```dart
Future<void> updateInstallerPointsFromInvoice(
  int invoiceId,
  String installerName,
  double invoiceTotal, {
  double? customPoints,
  double pointsPerHundredThousand = 1.0,
}) async {
  if (installerName.trim().isEmpty) return;

  final db = await database;

  final List<Map<String, dynamic>> installers = await db.query(
    'installers',
    where: 'name = ?',
    whereArgs: [installerName],
  );

  if (installers.isEmpty) return;

  final int installerId = installers.first['id'] as int;

  final double newPoints =
      customPoints ?? (invoiceTotal / 100000.0) * pointsPerHundredThousand;

  await db.transaction((txn) async {
    final List<Map<String, dynamic>> existingPoints = await txn.query(
      'installer_points',
      where: 'invoice_id = ?',
      whereArgs: [invoiceId],
    );

    if (existingPoints.isNotEmpty) {
      final double oldPoints = (existingPoints.first['points'] as num).toDouble();
      final double diff = MoneyCalculator.subtract(newPoints, oldPoints);

      if (diff.abs() > 0.001) {
        await txn.update(
          'installer_points',
          {
            'points': newPoints,
            'reason': 'فاتورة رقم $invoiceId (تعديل)',
          },
          where: 'invoice_id = ?',
          whereArgs: [invoiceId],
        );

        final List<Map<String, dynamic>> inst = await txn.query(
          'installers',
          columns: ['total_points'],
          where: 'id = ?',
          whereArgs: [installerId],
        );

        double currentTotal = (inst.first['total_points'] as num?)?.toDouble() ?? 0.0;
        await txn.update(
          'installers',
          {'total_points': currentTotal + diff},
          where: 'id = ?',
          whereArgs: [installerId],
        );
      }
    } else {
      await txn.insert('installer_points', {
        'installer_id': installerId,
        'invoice_id': invoiceId,
        'points': newPoints,
        'reason': 'فاتورة رقم $invoiceId',
        'created_at': DateTime.now().toIso8601String(),
      });

      final List<Map<String, dynamic>> inst = await txn.query(
        'installers',
        columns: ['total_points'],
        where: 'id = ?',
        whereArgs: [installerId],
      );

      double currentTotal = (inst.first['total_points'] as num?)?.toDouble() ?? 0.0;
      await txn.update(
        'installers',
        {'total_points': currentTotal + newPoints},
        where: 'id = ?',
        whereArgs: [installerId],
      );
    }
  });
}
```

## 6.1 شرح تفصيلي لما سبق

- **الخطوة 1**: يتأكد أن اسم المؤسس موجود.
- **الخطوة 2**: يجلب المؤسس من جدول `installers`.
- **الخطوة 3**: يحسب النقاط الجديدة:

\[
\text{newPoints} = \left(\frac{\text{invoiceTotal}}{100000}\right) \times \text{pointsPerHundredThousand}
\]

- **الخطوة 4**: يفحص هل للفاتورة سجل سابق في `installer_points`:
  - إذا نعم (وضع تعديل):
    - يحسب `diff = newPoints - oldPoints`
    - يحدث سجل الفاتورة في `installer_points`
    - يحدث `installers.total_points` بإضافة `diff`
  - إذا لا (وضع إنشاء):
    - يضيف سجل نقاط جديد
    - يزيد المجموع بـ `newPoints`

### معنى الخصم عند التعديل
- إذا `newPoints` أقل من `oldPoints` → يكون `diff` سالب.
- إضافة `diff` السالب إلى `total_points` = **خصم نقاط تلقائي**.

---

## 7) فتح الفاتورة ثم حفظ التعديل: ماذا يحدث بالضبط؟

### التسلسل التنفيذي
1. تفتح فاتورة موجودة → `initState` يحمل `invoiceToManage.pointsRate`.
2. المستخدم يغير أصناف/مبالغ/المعدل/المؤسس.
3. يضغط حفظ → `saveInvoice()`.
4. تحفظ الفاتورة في جدول `invoices` بنفس `id` (تحديث).
5. بعد اكتمال الحفظ، تستدعى `updateInstallerPointsFromInvoice` لنفس `invoice_id`.
6. الدالة تقارن بين النقاط القديمة والجديدة وتعدل `installer_points` و`installers.total_points` بالفرق فقط.

### النتيجة
- النظام لا يكرر النقاط بشكل خاطئ عند التعديل.
- بل يعمل تسوية دقيقة على الفرق.

---

## 8) دورة "تسديد راجع" وخصم النقاط

الدالة الرئيسية في الشاشة: `_saveTransaction()` داخل `add_transaction_screen.dart`.

```dart
Future<void> _saveTransaction() async {
  if (_formKey.currentState!.validate()) {
    final amount = double.parse(_amountController.text.replaceAll(',', ''));
    final amountChanged = _isDebt ? amount : -amount;

    final balanceBefore = widget.customer.currentTotalDebt;
    final newBalance = MoneyCalculator.add(balanceBefore, amountChanged);

    final transaction = DebtTransaction(
      customerId: widget.customer.id!,
      amountChanged: amountChanged,
      balanceBeforeTransaction: balanceBefore,
      newBalanceAfterTransaction: newBalance,
      transactionNote: _noteController.text.isEmpty ? null : _noteController.text,
      transactionType: _isDebt ? 'manual_debt' : 'manual_payment',
      createdAt: DateTime.now(),
      transactionDate: DateTime.now(),
      audioNotePath: _audioNotePath,
      transactionUuid: await DriveService().generateTransactionUuid(),
    );

    await context.read<AppProvider>().addTransaction(transaction);

    // إذا كان التسديد راجع
    if (!_isDebt && _isReturn) {
      final db = DatabaseService();
      final dbInstance = await db.database;
      final txResult = await dbInstance.rawQuery(
        'SELECT id FROM transactions WHERE customer_id = ? ORDER BY id DESC LIMIT 1',
        [widget.customer.id],
      );
      final lastTxId = txResult.isNotEmpty ? (txResult.first['id'] as int) : null;

      await db.insertReturn(
        transactionId: lastTxId,
        customerId: widget.customer.id!,
        amount: amount,
        note: _noteController.text.isEmpty ? null : _noteController.text,
      );

      final selectedInvoiceIds = _selectedInvoices.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      for (var invoiceId in selectedInvoiceIds) {
        final paymentAmount = _invoicePaymentAmounts[invoiceId] ?? 0.0;
        if (paymentAmount > 0) {
          await db.deductPointsForReturnedPayment(
            invoiceId: invoiceId,
            paymentAmount: paymentAmount,
            reason: 'تسديد راجع من ${widget.customer.name} - معاملة #$lastTxId',
          );
        }
      }
    }
  }
}
```

## 8.1 ماذا يحدث بالتحديد؟
- يسجل المعاملة المالية أولًا (دين/تسديد).
- إذا كانت العملية تسديد ومعلّمة كـ راجع:
  - يسجل حدث الراجع في جدول المرفوعات (`insertReturn`).
  - يمر على الفواتير المختارة لهذا الراجع.
  - لكل فاتورة: يستدعي `deductPointsForReturnedPayment` لخصم نقاط المؤسس.

---

## 9) دالة خصم النقاط للراجع حسب معدل الفاتورة

```dart
Future<void> deductPointsForReturnedPayment({
  required int invoiceId,
  required double paymentAmount,
  required String reason,
}) async {
  final db = await database;

  try {
    final List<Map<String, dynamic>> invoiceMaps = await db.query(
      'invoices',
      columns: ['installer_name', 'points_rate', 'total_amount'],
      where: 'id = ?',
      whereArgs: [invoiceId],
    );

    if (invoiceMaps.isEmpty) return;

    final String? installerName = invoiceMaps.first['installer_name'] as String?;
    final double pointsRate = (invoiceMaps.first['points_rate'] as num?)?.toDouble() ?? 1.0;

    if (installerName == null || installerName.isEmpty) return;

    final List<Map<String, dynamic>> installers = await db.query(
      'installers',
      where: 'name = ?',
      whereArgs: [installerName],
    );

    if (installers.isEmpty) return;

    final int installerId = installers.first['id'] as int;

    // points = (paymentAmount / 100,000) * pointsRate
    final double pointsToDeduct = (paymentAmount / 100000.0) * pointsRate;

    if (pointsToDeduct <= 0) return;

    await deductInstallerPoints(
      installerId,
      pointsToDeduct,
      reason,
    );
  } catch (e) {
    print('❌ Error deducting points for returned payment: $e');
  }
}
```

### شرح مهم جدًا
- هذه الدالة تستخدم `points_rate` من الفاتورة نفسها.
- لا تستخدم إعدادات التطبيق العامة.
- المعادلة:

\[
\text{pointsToDeduct} = \left(\frac{\text{paymentAmount}}{100000}\right) \times \text{pointsRate(invoice)}
\]

- بعدها تستدعي `deductInstallerPoints` لتنفيذ الخصم الفعلي.

---

## 10) كيف يتم الخصم الفعلي من رصيد المؤسس؟

الدالة: `deductInstallerPoints(...)`

```dart
Future<void> deductInstallerPoints(int installerId, double points, String reason) async {
  final db = await database;
  await db.transaction((txn) async {
    await txn.insert('installer_points', {
      'installer_id': installerId,
      'invoice_id': null,
      'points': -points, // قيمة سالبة = خصم
      'reason': reason,
      'created_at': DateTime.now().toIso8601String(),
    });

    final List<Map<String, dynamic>> installerMaps = await txn.query(
      'installers',
      columns: ['total_points'],
      where: 'id = ?',
      whereArgs: [installerId],
    );

    if (installerMaps.isNotEmpty) {
      double currentPoints = (installerMaps.first['total_points'] as num?)?.toDouble() ?? 0.0;
      double newTotal = MoneyCalculator.subtract(currentPoints, points);

      await txn.update(
        'installers',
        {'total_points': newTotal},
        where: 'id = ?',
        whereArgs: [installerId],
      );
    }
  });
}
```

### شرح
- يسجل حركة نقاط سالبة في `installer_points`.
- ثم يحدّث المجموع النهائي في `installers.total_points` بالطرح.

---

## 11) مسار إضافة دين عادي (ليس راجع)

في `_saveTransaction()`:
- إذا `_isDebt = true`:
  - ينشئ `DebtTransaction` بـ `amountChanged = +amount`.
  - يستدعي `AppProvider.addTransaction(transaction)`.

الدالة `AppProvider.addTransaction`:

```dart
Future<void> addTransaction(DebtTransaction transaction) async {
  final id = await _db.insertTransaction(transaction);
  final updatedCustomer = await _db.getCustomerById(transaction.customerId);

  if (updatedCustomer != null) {
    final index = _customers.indexWhere((c) => c.id == transaction.customerId);
    if (index != -1) {
      _customers[index] = updatedCustomer;
    }
    if (_selectedCustomer?.id == transaction.customerId) {
      _selectedCustomer = updatedCustomer;
    }
  }

  await loadCustomerTransactions(transaction.customerId);
  notifyListeners();
}
```

### علاقة هذا بالنقاط
- إضافة الدين اليدوي بحد ذاته لا يضيف نقاط مؤسس.
- النقاط ترتبط أساسًا بدورة حفظ الفاتورة أو خصم الراجع.

---

## 12) المعادلات النهائية المعتمدة في النظام

- احتساب نقاط فاتورة:

\[
\text{Points} = \frac{\text{Invoice Total}}{100000} \times \text{Rate}
\]

- فرق النقاط عند تعديل فاتورة:

\[
\text{Diff} = \text{NewPoints} - \text{OldPoints}
\]

- تحديث مجموع نقاط المؤسس في التعديل:

\[
\text{TotalPoints}_{new} = \text{TotalPoints}_{current} + \text{Diff}
\]

- خصم نقاط تسديد راجع:

\[
\text{DeductedPoints} = \frac{\text{ReturnedPayment}}{100000} \times \text{Invoice.pointsRate}
\]

---

## 13) ملاحظات دقيقة مهمة

1. `showPointsConfirmationOnSave` موجود في `AppSettings` لكن لا يوجد له مسار تنفيذ فعلي في حفظ الفاتورة حاليًا.
2. إذا لم يوجد اسم مؤسس في الفاتورة، فلن يتم تحديث نقاط.
3. عند تعديل نفس الفاتورة، المعالجة قائمة على `invoice_id` داخل `installer_points` لذلك تمنع تكرار احتساب غير صحيح.
4. خصم الراجع يستخدم معدل الفاتورة التاريخي، وهذا يحافظ على عدالة الحساب حتى لو تغيّر الإعداد العام لاحقًا.

---

## 14) خريطة دورة الاستدعاء (مختصرة)

### حفظ فاتورة
1. `CreateInvoiceScreen` زر حفظ → `saveInvoice()`
2. `InvoiceActionsMixin.saveInvoice()`
3. حفظ/تحديث `invoices` مع `points_rate`
4. `DatabaseService.updateInstallerPointsFromInvoice(...)`
5. تحديث `installer_points` + `installers.total_points`
6. `updateInstallerBilledAmount(...)`

### فتح فاتورة وتعديلها ثم حفظ
1. `initState()` يحمل `invoiceToManage.pointsRate`
2. المستخدم يعدل
3. `saveInvoice()`
4. `updateInstallerPointsFromInvoice()`
5. حساب `diff` وتعديل المجموع بالفرق

### تسديد راجع
1. `AddTransactionScreen._saveTransaction()`
2. `AppProvider.addTransaction(...)`
3. إذا `_isReturn=true`: `insertReturn(...)`
4. لكل فاتورة مختارة: `deductPointsForReturnedPayment(...)`
5. داخليًا: `deductInstallerPoints(...)`

---

هذا التوثيق مبني على الكود الفعلي الحالي، وهدفه أن يكون مرجعًا تفصيليًا للمناقشة والفهم التشغيلي الكامل للميزة.