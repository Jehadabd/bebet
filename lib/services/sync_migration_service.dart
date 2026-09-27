// lib/services/sync_migration_service.dart
//
// 🅑 Migration V4: تحويل sync_uuid للمعاملات إلى UUID v4 نقي.
//
// السبب:
//   - النمط القديم "name_amount_yyyymmdd_hhmmss" يتصادم (نرى `_1`, `_2` في اللوج).
//   - يسرّب اسم العميل والمبلغ في Firestore Document ID.
//   - يفشل مع الحروف العربية والرموز.
//   - غير متسق مع نظام UUID v4 للعملاء.
//
// الحل:
//   1) نسخة احتياطية قبل البدء (debt_book_backup_v4_{ts}.db).
//   2) قراءة كل معاملة sync_uuid بالنمط القديم.
//   3) توليد UUID v4 جديد.
//   4) تحديث ذرّي (transaction) في SQLite لكل الجداول المرتبطة:
//        - transactions (sync_uuid, transaction_uuid) + old_sync_uuid.
//        - sync_coordination (sync_uuid, entity_uuid إن وُجد).
//        - sync_retry_queue (sync_uuid).
//        - sync_wal (sync_uuid).
//        - transaction_acks (transaction_sync_uuid).
//   5) في Firestore: نسخ الحقل إلى مستند جديد + تحقق قراءة عكسية + حذف القديم.
//   6) بث لحظي إلى SyncEventBus.
//   7) Idempotent — يستأنف من حيث توقف؛ العلامة `v4_uuid_migration_done`.

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import 'sync/sync_security.dart';
import 'firebase_sync/sync_event_bus.dart';

class SyncMigrationService {
  final DatabaseService _db = DatabaseService();

  /// ⛔ [مُهجَّرة] هجرة V3 (deterministic SHA-256) — تُبقى للتوافق مع الأجهزة القديمة.
  ///     لا يُدعى تلقائياً بعد الآن — V4 يحلّ محلّها.
  @Deprecated('استُبدلت بـ migrateToUuidV4 (UUID v4 نقي). '
      'الاستدعاء التلقائي عبر autoMigrateIfNeeded يُشغّل V4 حالياً.')
  Future<void> migrateToDeterministicUuids() async {
    // ignore: avoid_print
    print('⛔ V3 migration deprecated — استخدم V4');
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// 🚀 Migration V4 — UUID v4 نقي للمعاملات
  /// ═══════════════════════════════════════════════════════════════════════
  Future<V4MigrationResult> migrateToUuidV4({
    FirebaseFirestore? firestore,
  }) async {
    final sw = Stopwatch()..start();
    syncBus.info(SyncPhase.migration, '🅑 بدء Migration V4 (UUID v4 للمعاملات)');

    // 1️⃣ نسخة احتياطية قبل أي تعديل
    String? backupPath;
    try {
      backupPath = await _createBackup();
      syncBus.success(SyncPhase.migration, '📦 نسخة احتياطية جاهزة: $backupPath');
    } catch (e) {
      syncBus.warning(SyncPhase.migration,
          'تعذّر إنشاء النسخة الاحتياطية ($e) — نتوقف قبل التعديل');
      return V4MigrationResult(
        success: false,
        totalCandidates: 0,
        migratedLocal: 0,
        migratedFirestore: 0,
        failed: 0,
        elapsed: sw.elapsed,
        backupPath: null,
        errorMessage: 'فشل إنشاء نسخة احتياطية: $e',
      );
    }

    final db = await _db.database;

    // 2️⃣ اكتشاف المعاملات المرشحة (نمط قديم = ليس UUID v4)
    final candidates = await db.query(
      'transactions',
      columns: ['id', 'sync_uuid', 'transaction_uuid', 'customer_id'],
      where: 'sync_uuid IS NOT NULL AND sync_uuid != ""',
    );
    final oldStyle = candidates.where((row) {
      final u = row['sync_uuid'] as String?;
      return u != null && !_looksLikeUuidV4(u);
    }).toList();

    if (oldStyle.isEmpty) {
      syncBus.success(SyncPhase.migration,
          '✅ لا توجد معاملات بنمط قديم — Migration V4 غير مطلوب');
      return V4MigrationResult(
        success: true,
        totalCandidates: 0,
        migratedLocal: 0,
        migratedFirestore: 0,
        failed: 0,
        elapsed: sw.elapsed,
        backupPath: backupPath,
      );
    }

    syncBus.beginOverall(
      phase: SyncPhase.migration,
      total: oldStyle.length,
      message: 'تحويل ${oldStyle.length} معاملة إلى UUID v4',
    );

    int okLocal = 0;
    int okFirestore = 0;
    int failed = 0;

    // 3️⃣ لكل معاملة: توليد UUID جديد + تحديث SQLite ذرّي + محاولة تحديث Firestore
    for (int i = 0; i < oldStyle.length; i++) {
      final row = oldStyle[i];
      final id = row['id'] as int;
      final oldUuid = row['sync_uuid'] as String;
      final newUuid = SyncSecurity.generateUuid();

      syncBus.updateOverall(
        current: i + 1,
        message: 'تحويل معاملة #$id: $oldUuid → $newUuid',
      );

      try {
        // ✅ تحديث SQLite في معاملة واحدة ذرّية
        await db.transaction((txn) async {
          await txn.update(
            'transactions',
            {
              'sync_uuid': newUuid,
              'transaction_uuid': newUuid,
              'old_sync_uuid': oldUuid,
              'is_uploaded': 0, // نُعيد الرفع بالمعرّف الجديد
            },
            where: 'id = ?',
            whereArgs: [id],
          );

          // sync_coordination — الجدول قد يحتوي أعمدة sync_uuid أو entity_uuid حسب الإصدار
          await _safeUpdateBySyncUuid(
              txn, 'sync_coordination', oldUuid, newUuid);

          // sync_retry_queue
          await _safeUpdateBySyncUuid(
              txn, 'sync_retry_queue', oldUuid, newUuid);

          // sync_wal (id قد يعتمد على sync_uuid، نُحدّث فقط عمود sync_uuid)
          await _safeUpdateBySyncUuid(txn, 'sync_wal', oldUuid, newUuid);

          // transaction_acks (transaction_sync_uuid)
          try {
            await txn.update(
              'transaction_acks',
              {'transaction_sync_uuid': newUuid},
              where: 'transaction_sync_uuid = ?',
              whereArgs: [oldUuid],
            );
          } catch (_) {
            // الجدول قد لا يوجد على بعض الأجهزة — نتجاهل
          }
        });
        okLocal++;

        // ✅ محاولة نقل المستند في Firestore (اختياري — إن فشل، Watchdog سيُعيد الرفع بالـUUID الجديد)
        final fs = firestore ?? FirebaseFirestore.instance;
        final ok = await _migrateFirestoreDoc(fs, oldUuid, newUuid);
        if (ok) {
          okFirestore++;
        }
      } catch (e) {
        failed++;
        syncBus.error(SyncPhase.migration,
            'فشل تحويل المعاملة #$id ($oldUuid): $e',
            entityUuid: oldUuid, entityType: 'transaction');
      }
    }

    // 4️⃣ الملخص
    final summary =
        'اكتمل Migration V4: SQLite=$okLocal/${oldStyle.length}، Firestore=$okFirestore، فاشل=$failed';
    syncBus.endOverall(
      message: summary,
      level: failed == 0 ? SyncEventLevel.success : SyncEventLevel.warning,
    );

    return V4MigrationResult(
      success: failed == 0,
      totalCandidates: oldStyle.length,
      migratedLocal: okLocal,
      migratedFirestore: okFirestore,
      failed: failed,
      elapsed: sw.elapsed,
      backupPath: backupPath,
    );
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// المساعدات الداخلية
  /// ═══════════════════════════════════════════════════════════════════════

  /// UUID v4 canonical: xxxxxxxx-xxxx-4xxx-[89ab]xxx-xxxxxxxxxxxx
  static final RegExp _uuidV4Pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false);

  bool _looksLikeUuidV4(String s) => _uuidV4Pattern.hasMatch(s);

  /// تحديث آمن لعمود sync_uuid إن كان الجدول والعمود موجودَين
  Future<void> _safeUpdateBySyncUuid(
      DatabaseExecutor txn, String table, String oldUuid, String newUuid) async {
    try {
      final info = await txn.rawQuery('PRAGMA table_info($table)');
      final hasCol = info.any((c) => c['name'] == 'sync_uuid');
      if (!hasCol) return;
      await txn.update(
        table,
        {'sync_uuid': newUuid},
        where: 'sync_uuid = ?',
        whereArgs: [oldUuid],
      );
    } catch (_) {
      // الجدول قد لا يوجد أو نسخة قديمة — نتجاهل بأمان
    }
  }

  /// نسخة احتياطية لقاعدة SQLite قبل Migration V4
  Future<String> _createBackup() async {
    final dbPath = await _db.databasePath;
    final dir = p.dirname(dbPath);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final backup = p.join(dir, 'debt_book_backup_v4_$ts.db');
    // نسخة ملف
    await File(dbPath).copy(backup);
    return backup;
  }

  /// نقل مستند Firestore من UUID القديم إلى الجديد مع تحقق قراءة عكسية
  Future<bool> _migrateFirestoreDoc(
      FirebaseFirestore fs, String oldUuid, String newUuid) async {
    try {
      final oldRef = fs.collection('transactions').doc(oldUuid);
      final oldSnap =
          await oldRef.get(const GetOptions(source: Source.server));
      if (!oldSnap.exists) {
        // لا مستند بعيد بهذا الاسم — لا شيء للنقل (Watchdog سيرفع بالمعرّف الجديد لاحقاً)
        syncBus.debug(SyncPhase.migration,
            'المستند $oldUuid غير موجود على Firestore — تخطي النقل');
        return true;
      }

      final data = Map<String, dynamic>.from(oldSnap.data() ?? {});
      data['syncUuid'] = newUuid;
      data['old_sync_uuid'] = oldUuid;
      data['migratedToV4At'] = FieldValue.serverTimestamp();

      final newRef = fs.collection('transactions').doc(newUuid);
      await newRef.set(data);

      // تحقق قراءة عكسية — تأكد أن المستند الجديد كُتب فعلاً على السيرفر
      final verify =
          await newRef.get(const GetOptions(source: Source.server));
      if (!verify.exists) {
        syncBus.warning(SyncPhase.migration,
            'تحقق فشل بعد كتابة $newUuid — نُبقي المستند القديم');
        return false;
      }

      // حذف المستند القديم بعد تأكيد الكتابة الجديدة
      await oldRef.delete();
      syncBus.success(SyncPhase.migration,
          '☁️ Firestore: $oldUuid → $newUuid');
      return true;
    } on FirebaseException catch (e) {
      syncBus.warning(SyncPhase.migration,
          'خطأ Firestore عند نقل $oldUuid: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      syncBus.warning(SyncPhase.migration,
          'استثناء عند نقل $oldUuid: $e');
      return false;
    }
  }

  /// ═══════════════════════════════════════════════════════════════════════
  /// التشغيل التلقائي عند بدء التطبيق
  /// ═══════════════════════════════════════════════════════════════════════

  static const _v4DoneFlag = 'v4_uuid_migration_done';
  static const _v4LastAttempt = 'v4_uuid_migration_last_attempt';

  /// يُستدعى مرة واحدة عند بدء التطبيق (بعد تهيئة Firebase).
  /// - Idempotent: يستأنف تلقائياً حتى النجاح الكامل.
  /// - يقفز إن كانت العلامة مسجّلة.
  static Future<void> autoMigrateIfNeeded() async {
    final storage = GetStorage();
    final bool done = storage.read(_v4DoneFlag) ?? false;
    if (done) {
      syncBus.debug(SyncPhase.migration,
          '⏭️ Migration V4 اكتمل مسبقاً — تخطي');
      return;
    }

    final lastAttempt = storage.read(_v4LastAttempt) as String?;
    if (lastAttempt != null) {
      syncBus.info(SyncPhase.migration,
          '↻ استئناف Migration V4 (المحاولة السابقة: $lastAttempt)');
    }
    await storage.write(_v4LastAttempt, DateTime.now().toIso8601String());

    final service = SyncMigrationService();
    final result = await service.migrateToUuidV4();

    if (result.success ||
        (result.totalCandidates > 0 && result.failed == 0)) {
      await storage.write(_v4DoneFlag, true);
      syncBus.success(SyncPhase.migration,
          '💾 تم تسجيل اكتمال Migration V4 (${result.migratedLocal}/${result.totalCandidates} + Firestore=${result.migratedFirestore})');
    } else {
      syncBus.warning(SyncPhase.migration,
          '⏸️ Migration V4 لم يكتمل — سيُستأنف عند التشغيل التالي');
    }
  }
}

/// نتيجة تفصيلية لـ Migration V4
class V4MigrationResult {
  final bool success;
  final int totalCandidates;
  final int migratedLocal;
  final int migratedFirestore;
  final int failed;
  final Duration elapsed;
  final String? backupPath;
  final String? errorMessage;

  const V4MigrationResult({
    required this.success,
    required this.totalCandidates,
    required this.migratedLocal,
    required this.migratedFirestore,
    required this.failed,
    required this.elapsed,
    this.backupPath,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() => {
        'success': success,
        'totalCandidates': totalCandidates,
        'migratedLocal': migratedLocal,
        'migratedFirestore': migratedFirestore,
        'failed': failed,
        'elapsedSeconds': elapsed.inSeconds,
        if (backupPath != null) 'backupPath': backupPath,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  @override
  String toString() => jsonEncode(toMap());
}
