// test/sync_harness/device.dart
// «جهاز وهمي»: خيط منفصل يشغّل كود التطبيق الحقيقي (DatabaseService،
// AppProvider، FirebaseSyncService…) بقاعدة SQLite حقيقية خاصة به، وإعدادات
// خاصة، ومنصات وهمية. ينفّذ أوامر الاختبار عبر نفس الدوال التي تستدعيها الشاشات.

// ignore_for_file: avoid_print, implementation_imports

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:alnaser/models/customer.dart';
import 'package:alnaser/models/invoice.dart';
import 'package:alnaser/models/invoice_item.dart';
import 'package:alnaser/models/transaction.dart';
import 'package:alnaser/providers/app_provider.dart';
import 'package:alnaser/services/database_service.dart';
import 'package:alnaser/services/firebase_sync/armored_reconciliation_service.dart';
import 'package:alnaser/services/firebase_sync/smart_pipe_cleanup_service.dart';
import 'package:alnaser/services/firebase_sync/firebase_sync_service.dart';
import 'package:alnaser/services/firebase_sync/invoice_sync_service.dart';
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/src/mixin/factory.dart' show buildDatabaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi/src/isolate.dart' show SqfliteIsolate;
import 'package:sqflite_common_ffi/src/method_call.dart' show FfiMethodCall;

import 'fake_platforms.dart';
import 'protocol.dart';
import 'remote_firestore.dart';

const _fileLog = bool.fromEnvironment('DEVLOG');

/// نقطة دخول خيط الجهاز.
void deviceMain(DeviceBoot boot) {
  final logs = <String>[];
  final errors = <String>[];
  runZonedGuarded(
    () => _run(boot, logs, errors),
    (e, st) {
      // أسطر كود التطبيق أولاً (package:alnaser): تدلّ على موضع الخطأ
      final lines = st.toString().split('\n');
      final app = lines.where((l) => l.contains('package:alnaser')).take(8).toList();
      errors.add('$e\n${(app.isNotEmpty ? app : lines.take(8)).join('\n')}');
    },
    zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
      if (_fileLog) {
        try {
          File('${boot.dir}${Platform.pathSeparator}device.log')
              .writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
        } catch (_) {}
      }
      logs.add(line);
      if (logs.length > 4000) logs.removeRange(0, 1000);
    }),
  );
}

Future<void> _run(DeviceBoot boot, List<String> logs, List<String> errors) async {
  Directory(boot.dir).createSync(recursive: true);

  // ── المنصات الوهمية ──
  // SQLite عبر خادم مشترك: مكتبة SQLite في بيئة اختبار ويندوز تُفسد اتصالات
  // خيط إذا استخدمها خيط آخر في الوقت نفسه. خادم واحد = خيط واحد يلمس SQLite.
  final sqliteServer = SqfliteIsolate(sendPort: boot.sqlite);
  databaseFactory = buildDatabaseFactory(
    tag: 'harness',
    invokeMethod: (String method, [Object? arguments]) =>
        sqliteServer.handle(FfiMethodCall(method, arguments)),
  );
  PathProviderPlatform.instance = FakePathProvider(boot.dir);
  SharedPreferences.setMockInitialValues(boot.prefs);
  FlutterSecureStorage.setMockInitialValues(Map<String, String>.from(boot.secure));
  FirebasePlatform.instance = FakeFirebaseCore();
  FirebaseAuthPlatform.instance = FakeAuth('uid-${boot.name}');
  final link = CloudLink(boot.name, boot.cloud);
  FirebaseFirestorePlatform.instance = RemoteFirestore(link);
  FieldValueFactoryPlatform.instance = RemoteFieldValueFactory();
  final connectivity = FakeConnectivity(boot.online);
  ConnectivityPlatform.instance = connectivity;

  final cmdPort = ReceivePort();
  boot.controller.send(cmdPort.sendPort);

  await for (final msg in cmdPort) {
    if (msg is! DeviceCommand) continue;
    try {
      final v = await _exec(msg, connectivity, logs, errors);
      boot.controller.send(DeviceReply(msg.id, v));
      if (msg.op == 'shutdown') {
        link.close();
        cmdPort.close();
        // يُجمِّد المتحكّم هذا الخيط (لا إغلاق للقاعدة ولا إنهاء قد يُسقط SQLite)
      }
    } catch (e, st) {
      boot.controller.send(DeviceReply(
          msg.id, null, '$e\n${st.toString().split('\n').take(10).join('\n')}'));
    }
  }
}

Future<int?> _customerId(String uuid) async {
  final db = await DatabaseService().database;
  final r = await db.query('customers',
      columns: ['id'], where: 'sync_uuid = ?', whereArgs: [uuid], limit: 1);
  return r.isEmpty ? null : r.first['id'] as int;
}

Future<Map<String, Object?>?> _txRow(String uuid) async {
  final db = await DatabaseService().database;
  final r = await db.query('transactions',
      where: 'transaction_uuid = ?', whereArgs: [uuid], limit: 1);
  return r.isEmpty ? null : r.first;
}

Future<Object?> _exec(DeviceCommand c, FakeConnectivity connectivity, List<String> logs,
    List<String> errors) async {
  final a = c.args;
  switch (c.op) {
    case 'init':
      return await FirebaseSyncService().initialize();

    case 'addCustomer':
      final name = a['name'] as String;
      await AppProvider().addCustomer(Customer(name: name, phone: a['phone'] as String?));
      final db = await DatabaseService().database;
      final r = await db.query('customers',
          columns: ['sync_uuid'],
          where: 'name = ? AND (is_created_by_me = 1 OR is_created_by_me IS NULL)',
          whereArgs: [name],
          orderBy: 'id DESC',
          limit: 1);
      return r.isEmpty ? null : r.first['sync_uuid'];

    case 'addTx':
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) throw StateError('customer not on device');
      final amount = (a['amount'] as num).toDouble();
      final marker = a['marker'] as String;
      await AppProvider().addTransaction(DebtTransaction(
        customerId: cid,
        amountChanged: amount,
        transactionType: amount >= 0 ? 'manual_debt' : 'manual_payment',
        transactionNote: marker,
      ));
      final db = await DatabaseService().database;
      final r = await db.query('transactions',
          columns: ['transaction_uuid'],
          where: 'customer_id = ? AND transaction_note = ? AND is_created_by_me = 1',
          whereArgs: [cid, marker],
          orderBy: 'id DESC',
          limit: 1);
      return r.isEmpty ? null : r.first['transaction_uuid'];

    case 'editTx':
      final row = await _txRow(a['tx'] as String);
      if (row == null) throw StateError('tx not on device');
      final t = DebtTransaction.fromMap(row);
      final amount = (a['amount'] as num).toDouble();
      // شاشة العميل: db.updateTransaction(updated)
      await DatabaseService().updateTransaction(t.copyWith(amountChanged: amount));
      return true;

    case 'convertTx':
      final row = await _txRow(a['tx'] as String);
      if (row == null) throw StateError('tx not on device');
      await DatabaseService().convertTransactionType(row['id'] as int);
      // التحويل يقلب ما يراه المستخدم على هذا الجهاز (قد يكون قديماً إن كان
      // الجهاز يلحق بالمجموعة بعد استعادة نسخة): الحقيقة تأخذ الناتج الفعلي.
      final after = await _txRow(a['tx'] as String);
      return {
        'amount': (after?['amount_changed'] as num?)?.toDouble(),
        'type': after?['transaction_type'],
      };

    case 'deleteCustomer':
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) throw StateError('customer not on device');
      final db = await DatabaseService().database;
      // ما حذفه التطبيق فعلاً = المحذوف بعد الحذف ناقص المحذوف قبله. قائمة
      // «النشط قبل الحذف» كانت تفوّت معاملة وصلت بين الاستعلام والحذف —
      // والتطبيق يحذفها (كانت موجودة لحظة الحذف) فتختلف الحقيقة عنه.
      Future<Map<String, String?>> deleted() async {
        final r = await db.query('transactions',
            columns: ['transaction_uuid', 'invoice_sync_uuid'],
            where: 'customer_id = ? AND is_deleted = 1 AND transaction_uuid IS NOT NULL',
            whereArgs: [cid]);
        return {
          for (final x in r) x['transaction_uuid'] as String: x['invoice_sync_uuid'] as String?
        };
      }
      final before = await deleted();
      await AppProvider().deleteCustomer(cid);
      final after = await deleted();
      final newly = after.keys.where((u) => !before.containsKey(u)).toList();
      final invs = {
        for (final u in newly)
          if ((after[u] ?? '').isNotEmpty) after[u]!
      };
      return {'txs': newly, 'invs': invs.toList()};

    case 'addProduct':
      throw UnsupportedError('bebet harness: addProduct غير مدعوم');

    case 'products':
      return const <Object?>[]; // لا دفتر مخزون في bebet

    case 'adjustStock':
      throw UnsupportedError('bebet harness: adjustStock غير مدعوم');

    case 'purchase':
      throw UnsupportedError('bebet harness: purchase غير مدعوم');

    case 'legacyStock':
      throw UnsupportedError('bebet harness: legacyStock غير مدعوم');

    case 'invoiceDetail':
      final db = await DatabaseService().database;
      final inv = await db.rawQuery('''
        SELECT i.*, c.sync_uuid AS cust_uuid FROM invoices i
        LEFT JOIN customers c ON c.id = i.customer_id WHERE i.invoice_uuid = ?''', [a['inv']]);
      if (inv.isEmpty) return null;
      final items = await db.query('invoice_items',
          where: 'invoice_id = ?', whereArgs: [inv.first['id']], orderBy: 'id');
      final txs = await db.rawQuery('''
        SELECT t.amount_changed AS amount, t.is_deleted AS del, t.transaction_type AS type,
               c.sync_uuid AS cust FROM transactions t
        LEFT JOIN customers c ON c.id = t.customer_id
        WHERE t.invoice_sync_uuid = ?''', [a['inv']]);
      return {'invoice': inv.first, 'items': items, 'txs': txs};

    case 'stockDetail':
      throw UnsupportedError('bebet harness: stockDetail غير مدعوم');

    case 'viewCustomer':
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) return false;
      await DatabaseService().getGroupedCustomerTransactions(cid);
      return true;

    case 'saveInvoice':
      // حفظ الفاتورة في bebet مرتبط بالشاشة (InvoiceActionsMixin)، فنمرّ بدوال
      // DatabaseService الحقيقية التي تستدعيها: insertInvoice/updateInvoice
      // (ختم النسخة) + البنود + الحارس المحاسبي (يكتب أثر الدين مرتبطاً بالفاتورة
      // ويرفع نسختها) ثم الرفع الفوري للحزمة. العميل لا يتغيّر عند التعديل.
      final dbs = DatabaseService();
      final db = await dbs.database;
      final cr = await db.query('customers',
          where: 'sync_uuid = ?', whereArgs: [a['cust']], limit: 1);
      if (cr.isEmpty) throw StateError('customer not on device');
      final cust = cr.first;
      final total = (a['total'] as num).toDouble();
      final ptype = a['ptype'] as String;
      final paid = (a['paid'] as num).toDouble();
      final now = DateTime.now();
      final invUuid = a['inv'] as String?;
      int invoiceId;
      InvoiceItem itemFor(int id) => InvoiceItem(
            invoiceId: id,
            productName: 'صنف اختبار',
            unit: 'قطعة',
            unitPrice: total,
            quantityIndividual: 1,
            appliedPrice: total,
            itemTotal: total,
            saleType: 'قطعة',
          );
      if (invUuid == null) {
        invoiceId = await dbs.insertInvoice(Invoice(
          customerName: cust['name'] as String,
          customerPhone: (cust['phone'] as String?) ?? '',
          customerAddress: (cust['address'] as String?) ?? '',
          installerName: '',
          invoiceDate: now,
          paymentType: ptype,
          totalAmount: total,
          amountPaidOnInvoice: paid,
          createdAt: now,
          lastModifiedAt: now,
          customerId: cust['id'] as int,
          status: 'محفوظة',
        ));
        await dbs.insertInvoiceItem(itemFor(invoiceId));
        await dbs.reconcileInvoiceDebt(invoiceId, reason: 'حفظ فاتورة (اختبار)');
      } else {
        final ir = await db.query('invoices',
            where: 'invoice_uuid = ?', whereArgs: [invUuid], limit: 1);
        if (ir.isEmpty) throw StateError('invoice not on device');
        final existing = Invoice.fromMap(ir.first);
        invoiceId = existing.id!;
        // كما في invoice_actions: تنظيف صفوف «التعديل الحي» القديمة قبل الحفظ،
        // والحفظ يجعل الفاتورة المعلّقة محفوظة.
        await dbs.deleteLiveDebtTransactions(invoiceId);
        await db.delete('invoice_items', where: 'invoice_id = ?', whereArgs: [invoiceId]);
        await dbs.insertInvoiceItem(itemFor(invoiceId));
        await dbs.updateInvoice(existing.copyWith(
          totalAmount: total,
          amountPaidOnInvoice: paid,
          paymentType: ptype,
          status: 'محفوظة',
          lastModifiedAt: now,
        ));
      }
      final saved = await db.query('invoices',
          columns: ['invoice_uuid', 'amount_paid_on_invoice'],
          where: 'id = ?', whereArgs: [invoiceId], limit: 1);
      final savedUuid = saved.first['invoice_uuid'] as String;
      unawaited(InvoiceSyncService().syncInvoiceBundleNow(savedUuid).catchError((e) {
        print('⚠️ الرفع الفوري تأجّل: $e');
        return false;
      }));
      return {
        'ok': true,
        'uuid': savedUuid,
        'cust': a['cust'],
        'paid': (saved.first['amount_paid_on_invoice'] as num?)?.toDouble() ?? paid,
      };

    case 'deleteInvoice':
      final db = await DatabaseService().database;
      final ir = await db.query('invoices',
          columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
      if (ir.isEmpty) throw StateError('invoice not on device');
      final n = await DatabaseService().deleteInvoice(ir.first['id'] as int);
      return n > 0;

    case 'invoiceExists':
      final db = await DatabaseService().database;
      final ir = await db.query('invoices',
          columns: ['id'], where: 'invoice_uuid = ?', whereArgs: [a['inv']], limit: 1);
      return ir.isNotEmpty;

    case 'ownInvoices':
      final db = await DatabaseService().database;
      final r = await db.rawQuery(
          'SELECT i.invoice_uuid AS u, c.sync_uuid AS cs, i.total_amount AS total, '
          'i.payment_type AS pt FROM invoices i JOIN customers c ON c.id = i.customer_id '
          'WHERE i.is_created_by_me = 1 '
          'AND (i.is_deleted IS NULL OR i.is_deleted = 0) '
          'AND (c.is_deleted IS NULL OR c.is_deleted = 0) AND i.invoice_uuid IS NOT NULL');
      return [
        for (final x in r) [x['u'], x['cs'], (x['total'] as num?)?.toDouble(), x['pt']]
      ];

    case 'custDetail':
      final db = await DatabaseService().database;
      final cid = await _customerId(a['cust'] as String);
      if (cid == null) return {'missing': true};
      final invs = await db.rawQuery(
          'SELECT invoice_uuid, total_amount, amount_paid_on_invoice, payment_type, status, '
          'version, is_synced, is_created_by_me, is_deleted, restored_mark FROM invoices '
          'WHERE customer_id = ?',
          [cid]);
      final txs = await db.rawQuery(
          'SELECT transaction_uuid, amount_changed, transaction_type, is_deleted, '
          'is_created_by_me, is_uploaded, invoice_sync_uuid, invoice_id FROM transactions '
          'WHERE customer_id = ? ORDER BY id',
          [cid]);
      return {'invoices': invs, 'txs': txs};

    case 'liveSuspended':
      // فاتورة معلّقة مفتوحة في الشاشة (دين) + «التعديل الحي» الذي تستدعيه
      // الشاشة عند كل تغيير (_syncLiveDebt → setInvoiceDebtContribution).
      final dbs = DatabaseService();
      final db = await dbs.database;
      final cr = await db.query('customers',
          where: 'sync_uuid = ?', whereArgs: [a['cust']], limit: 1);
      if (cr.isEmpty) throw StateError('customer not on device');
      final cust = cr.first;
      final total = (a['total'] as num).toDouble();
      final now = DateTime.now();
      final invoiceId = await dbs.insertInvoice(Invoice(
        customerName: cust['name'] as String,
        customerPhone: (cust['phone'] as String?) ?? '',
        customerAddress: (cust['address'] as String?) ?? '',
        installerName: '',
        invoiceDate: now,
        paymentType: 'دين',
        totalAmount: total,
        amountPaidOnInvoice: 0,
        createdAt: now,
        lastModifiedAt: now,
        customerId: cust['id'] as int,
        status: 'معلقة',
      ));
      await dbs.insertInvoiceItem(InvoiceItem(
        invoiceId: invoiceId,
        productName: 'صنف اختبار',
        unit: 'قطعة',
        unitPrice: total,
        quantityIndividual: 1,
        appliedPrice: total,
        itemTotal: total,
        saleType: 'قطعة',
      ));
      await dbs.setInvoiceDebtContribution(
        invoiceId: invoiceId,
        customerId: cust['id'] as int,
        newContribution: total,
        note: 'تعديل حي لمساهمة فاتورة #$invoiceId',
      );
      if (a['legacy'] == true) {
        // صف «تعديل حي» كما كتبه الإصدار السابق (قبل التحديث)
        final u = 'tx_legacy_live_${cust['id']}_$invoiceId';
        await db.insert('transactions', {
          'customer_id': cust['id'],
          'transaction_date': now.toIso8601String(),
          'amount_changed': total,
          'transaction_note': 'تعديل حي لمساهمة فاتورة #$invoiceId',
          'transaction_type': 'invoice_live_update',
          'description': 'Live delta applied to match invoice contribution',
          'invoice_id': invoiceId,
          'created_at': now.toIso8601String(),
          'transaction_uuid': u,
          'sync_uuid': u,
        });
        await db.rawUpdate(
            'UPDATE customers SET current_total_debt = current_total_debt + ? WHERE id = ?',
            [total, cust['id']]);
      }
      return invoiceId;

    case 'finalizeSuspended':
      // الحفظ النهائي كما في invoice_actions: تنظيف صفوف التعديل الحي ثم الحفظ
      // بحالة «محفوظة» فيكتب الحارس دين الفاتورة، ثم رفع الحزمة.
      final dbs = DatabaseService();
      final db = await dbs.database;
      final id = a['id'] as int;
      await dbs.deleteLiveDebtTransactions(id);
      final ir = await db.query('invoices', where: 'id = ?', whereArgs: [id], limit: 1);
      final existing = Invoice.fromMap(ir.first);
      await dbs.updateInvoice(existing.copyWith(
        status: 'محفوظة',
        lastModifiedAt: DateTime.now(),
      ));
      await dbs.reconcileInvoiceDebt(id, reason: 'حفظ فاتورة معلّقة (اختبار)');
      final saved = await db.query('invoices',
          columns: ['invoice_uuid'], where: 'id = ?', whereArgs: [id], limit: 1);
      final uuid = saved.first['invoice_uuid'] as String;
      await InvoiceSyncService().syncInvoiceBundleNow(uuid).catchError((e) => false);
      return uuid;

    case 'suspendInvoice':
      // InvoiceSuspendService.suspendInvoice (بلا التحقق من نموذج الواجهة)،
      // ثم «التعديل الحي» الذي تستدعيه الشاشة (لم يعد يكتب شيئاً).
      final dbs = DatabaseService();
      final db = await dbs.database;
      final cr = await db.query('customers',
          where: 'sync_uuid = ?', whereArgs: [a['cust']], limit: 1);
      if (cr.isEmpty) throw StateError('customer not on device');
      final cust = cr.first;
      final total = (a['total'] as num).toDouble();
      final now = DateTime.now();
      final invoiceId = await dbs.insertInvoice(Invoice(
        customerName: cust['name'] as String,
        customerPhone: (cust['phone'] as String?) ?? '',
        customerAddress: (cust['address'] as String?) ?? '',
        installerName: '',
        invoiceDate: now,
        paymentType: a['ptype'] as String,
        totalAmount: total,
        amountPaidOnInvoice: (a['paid'] as num).toDouble(),
        createdAt: now,
        lastModifiedAt: now,
        customerId: cust['id'] as int,
        status: 'معلقة',
      ));
      await dbs.insertInvoiceItem(InvoiceItem(
        invoiceId: invoiceId,
        productName: 'صنف اختبار',
        unit: 'قطعة',
        unitPrice: total,
        quantityIndividual: 1,
        appliedPrice: total,
        itemTotal: total,
        saleType: 'قطعة',
      ));
      await dbs.setInvoiceDebtContribution(
        invoiceId: invoiceId,
        customerId: cust['id'] as int,
        newContribution: total,
      );
      final ir = await db.rawQuery(
          'SELECT i.invoice_uuid AS u, c.sync_uuid AS cs FROM invoices i '
          'LEFT JOIN customers c ON c.id = i.customer_id WHERE i.id = ?',
          [invoiceId]);
      return {'uuid': ir.first['u'], 'cust': ir.first['cs']};

    case 'pendingOwnWork':
      final db = await DatabaseService().database;
      final tx = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM transactions WHERE (is_uploaded = 0 OR is_uploaded IS NULL) '
          'AND ((is_created_by_me = 1 OR is_created_by_me IS NULL) OR is_deleted = 1) '
          'AND transaction_uuid IS NOT NULL');
      final inv = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM invoices WHERE (is_synced = 0 OR is_synced IS NULL) '
          'AND (is_created_by_me = 1 OR is_created_by_me IS NULL)');
      final cu = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM customers WHERE tombstoned IN (2, 3) OR '
          '((is_created_by_me = 1 OR is_created_by_me IS NULL) AND sync_uuid IS NOT NULL '
          'AND (synced_at IS NULL OR last_modified_at > synced_at))');
      return (tx.first['n'] as int) + (inv.first['n'] as int) + (cu.first['n'] as int);

    case 'backup':
      final db = await DatabaseService().database;
      final target = (a['path'] as String).replaceAll("'", "''");
      await db.execute("VACUUM INTO '$target'");
      return true;

    case 'smartPipe':
      final r = await SmartPipeCleanupService().runManualCleanup();
      return r.deletedTransactions + r.deletedInvoices;

    case 'armoredPush':
      // «بياناتي صحيحة» — لا ننتظرها (تنتظر ردود الأجهزة حتى 90 ثانية)
      unawaited(ArmoredReconciliationService()
          .pushMyTruthForCustomer(a['cust'] as String)
          .catchError((e) {
        print('⚠️ مطابقة: $e');
        return false;
      }));
      return true;

    case 'setOnline':
      connectivity.setOnline(a['online'] as bool);
      return true;

    case 'kick':
      await FirebaseSyncService().debugRunBackgroundCycle();
      await FirebaseSyncService().performFullCatchUp();
      return true;

    case 'visibleCustomers':
      final db = await DatabaseService().database;
      final r = await db.query('customers',
          columns: ['sync_uuid'],
          where: "(is_deleted IS NULL OR is_deleted = 0) AND sync_uuid IS NOT NULL AND sync_uuid != ''");
      return [for (final x in r) x['sync_uuid'] as String];

    case 'ownManualTxs':
      final db = await DatabaseService().database;
      final r = await db.query('transactions',
          columns: ['transaction_uuid', 'transaction_type', 'amount_changed'],
          where: "is_created_by_me = 1 AND (is_deleted IS NULL OR is_deleted = 0) "
              "AND invoice_id IS NULL AND transaction_type IN ('manual_debt','manual_payment') "
              "AND transaction_uuid IS NOT NULL");
      return [
        for (final x in r)
          [x['transaction_uuid'], x['transaction_type'], (x['amount_changed'] as num).toDouble()]
      ];

    case 'state':
      final db = await DatabaseService().database;
      final customers = await db.rawQuery('''
        SELECT c.sync_uuid AS uuid, c.name AS name, c.current_total_debt AS debt,
               c.is_deleted AS del, c.tombstoned AS tomb, c.is_created_by_me AS mine,
               (SELECT COALESCE(SUM(t.amount_changed), 0) FROM transactions t
                 WHERE t.customer_id = c.id AND (t.is_deleted IS NULL OR t.is_deleted = 0)) AS sum,
               (SELECT COUNT(*) FROM transactions t
                 WHERE t.customer_id = c.id AND (t.is_deleted IS NULL OR t.is_deleted = 0)) AS cnt
        FROM customers c
      ''');
      final pending = await db.rawQuery('''
        SELECT COUNT(*) AS n FROM transactions
        WHERE (is_uploaded = 0 OR is_uploaded IS NULL)
          AND ((is_created_by_me = 1 OR is_created_by_me IS NULL) OR is_deleted = 1)
          AND transaction_uuid IS NOT NULL
      ''');
      final txs = await db.rawQuery('''
        SELECT t.transaction_uuid AS uuid, c.sync_uuid AS cust, t.amount_changed AS amount,
               t.is_deleted AS del, t.is_created_by_me AS mine, t.is_uploaded AS up,
               t.invoice_sync_uuid AS inv
        FROM transactions t LEFT JOIN customers c ON c.id = t.customer_id
      ''');
      return {
        'customers': [
          for (final r in customers)
            {
              'uuid': r['uuid'],
              'name': r['name'],
              'debt': (r['debt'] as num?)?.toDouble() ?? 0.0,
              'sum': (r['sum'] as num?)?.toDouble() ?? 0.0,
              'cnt': r['cnt'],
              'del': r['del'],
              'tomb': r['tomb'],
              'mine': r['mine'],
            }
        ],
        'txs': [
          for (final r in txs)
            {
              'uuid': r['uuid'],
              'cust': r['cust'],
              'amount': (r['amount'] as num?)?.toDouble() ?? 0.0,
              'del': r['del'],
              'mine': r['mine'],
              'up': r['up'],
              'inv': r['inv'],
            }
        ],
        'pending': pending.first['n'],
        'products': const <String, Object?>{}, // لا دفتر مخزون في bebet
        'recovering': FirebaseSyncService().isRecovering,
        'bootstrapping': FirebaseSyncService().debugBootstrapping,
        'errors': errors.length,
      };

    case 'logs':
      final n = (a['n'] as int?) ?? 200;
      return logs.length <= n ? List<String>.from(logs) : logs.sublist(logs.length - n);

    case 'errors':
      return List<String>.from(errors);

    case 'shutdown':
      print('[harness] shutdown: prefs');
      final prefs = await SharedPreferences.getInstance();
      final prefMap = <String, Object>{};
      for (final k in prefs.getKeys()) {
        final v = prefs.get(k);
        if (v != null) prefMap[k] = v is List ? List<String>.from(v) : v;
      }
      print('[harness] shutdown: secure');
      final secure = await const FlutterSecureStorage().readAll();
      // إعادة التشغيل = قتل مفاجئ للعملية: لا dispose ولا إغلاق للقاعدة
      // (إغلاقها بينما كود المزامنة يعمل عليها يُسقط SQLite الأصلية).
      // نسخة متسقة لحظية من القاعدة = ما كان محفوظاً على القرص لحظة القتل.
      final copyTo = a['copyTo'] as String?;
      if (copyTo != null) {
        final db = await DatabaseService().database;
        final target = copyTo.replaceAll("'", "''");
        await db.execute("VACUUM INTO '$target'");
      }
      return {'prefs': prefMap, 'secure': secure};
  }
  throw UnsupportedError('unknown command ${c.op}');
}
