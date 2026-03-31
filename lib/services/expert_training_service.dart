// lib/services/expert_training_service.dart
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database_service.dart'; // لجلب البيانات الأصلية

/// يدير قاعدة البيانات المنفصلة الخاصة بالذكاء الخبير
class ExpertKnowledgeDatabase {
  static ExpertKnowledgeDatabase? _instance;
  static Database? _database;

  ExpertKnowledgeDatabase._();

  static ExpertKnowledgeDatabase get instance {
    _instance ??= ExpertKnowledgeDatabase._();
    return _instance!;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {

    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'expert_knowledge.db');

    print('🧠 Expert Knowledge DB path: $path');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // جدول العلاقات الإحصائية
        await db.execute('''
          CREATE TABLE expert_product_relations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id_a INTEGER NOT NULL,
            product_id_b INTEGER NOT NULL,
            product_name_a TEXT NOT NULL,
            product_name_b TEXT NOT NULL,
            support INTEGER NOT NULL,
            confidence REAL NOT NULL,
            lift REAL NOT NULL,
            relation_type TEXT NOT NULL, -- 'positive' or 'negative'
            UNIQUE(product_id_a, product_id_b)
          )
        ''');

        // جدول الترتيب (السلاسل الزمنية للفاتورة / Markov Chain)
        await db.execute('''
          CREATE TABLE expert_product_sequences (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            from_product_name TEXT NOT NULL,
            to_product_name TEXT NOT NULL,
            sequence_count INTEGER NOT NULL,
            probability REAL NOT NULL,
            UNIQUE(from_product_name, to_product_name)
          )
        ''');

        // جدول الفوقيات (Metadata) للتدريب
        await db.execute('''
          CREATE TABLE training_metadata (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            last_trained_at TEXT NOT NULL,
            invoices_analyzed INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL
          )
        ''');
        
        // 🔄 جدول التعلم التدريجي: عداد الفواتير الإجمالي
        await db.execute('''
          CREATE TABLE IF NOT EXISTS expert_invoice_counter (
            id INTEGER PRIMARY KEY DEFAULT 1,
            total_invoices INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.rawInsert(
          'INSERT OR IGNORE INTO expert_invoice_counter (id, total_invoices) VALUES (1, 0)'
        );
        
        // 🔄 جدول التعلم التدريجي: عدد ظهور كل منتج في الفواتير
        await db.execute('''
          CREATE TABLE IF NOT EXISTS product_global_support (
            product_name TEXT PRIMARY KEY,
            support_count INTEGER NOT NULL DEFAULT 1
          )
        ''');
      },
    );
  }
}

/// خدمة التدريب الشامل والمستقلة
class ExpertTrainingService {
  static ExpertTrainingService? _instance;

  ExpertTrainingService._();

  static ExpertTrainingService get instance {
    _instance ??= ExpertTrainingService._();
    return _instance!;
  }

  /// تنفيذ دورة التدريب الشاملة بضغطة زر
  Future<void> trainGlobalRelations({
    required Function(double progress, String status) onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();
    onProgress(0.01, 'جاري الاتصال بقاعدة البيانات الأصلية...');
    
    // 1. جلب البيانات من القاعدة الأساسية
    final mainDb = await DatabaseService().database;
    final expertDb = await ExpertKnowledgeDatabase.instance.database;
    
    // مسح البيانات القديمة لإعادة التدريب من الصفر (تعلم حديث)
    await expertDb.delete('expert_product_relations');
    await expertDb.delete('expert_product_sequences');

    // 2. سحب الفواتير الصالحة
    onProgress(0.05, 'جاري جلب الفواتير المعتمدة...');
    final invoices = await mainDb.rawQuery('''
      SELECT id 
      FROM invoices 
      WHERE status != 'معلقة'
    ''');
    
    final int totalInvoices = invoices.length;
    if (totalInvoices == 0) {
      onProgress(1.0, 'لا توجد فواتير كافية للتدريب.');
      return;
    }

    // القواميس الإحصائية
    final Map<String, int> productSupport = {};
    final Map<String, Map<String, int>> pairSupport = {};
    final Map<String, Map<String, int>> sequences = {}; // from -> to -> count

    onProgress(0.1, 'جاري مسح الأصناف واكتشاف الأنماط...');
    int processed = 0;

    for (final inv in invoices) {
      final invoiceId = inv['id'];
      
      final items = await mainDb.rawQuery('''
        SELECT product_id, product_name 
        FROM invoice_items 
        WHERE invoice_id = ? 
        ORDER BY id ASC
      ''', [invoiceId]);

      if (items.length < 2) {
        processed++;
        continue;
      }

      final List<String> pNames = items.map((i) => i['product_name'].toString()).toList();
      final List<int> pIds = items.map((i) => (i['product_id'] as int?) ?? 0).toList();

      // حساب Support الفردي 
      final Set<String> uniqueInvoiceProducts = pNames.toSet();
      for (final p in uniqueInvoiceProducts) {
        productSupport[p] = (productSupport[p] ?? 0) + 1;
      }

      // حساب الروابط والتتابع الموزون بالمسافة (Distance-Weighted Sequencing)
      for (int i = 0; i < pNames.length; i++) {
        final p1 = pNames[i];
        
        for (int j = i + 1; j < pNames.length; j++) {
          final p2 = pNames[j];
          if (p1 == p2) continue; // تخطي نفس المنتج

          // 1. تتبع التتابع الموزون بالمسافة
          int distance = j - i;
          int points = 0;
          if (distance == 1) points = 10;
          else if (distance == 2) points = 5;
          else if (distance == 3) points = 2;
          else points = 1;

          sequences[p1] ??= {};
          sequences[p1]![p2] = (sequences[p1]![p2] ?? 0) + points;

          // 2. حساب التقاطعات (التبديل لا يهم للـ Lift)
          final String pA = p1.compareTo(p2) < 0 ? p1 : p2;
          final String pB = p1.compareTo(p2) < 0 ? p2 : p1;

          pairSupport[pA] ??= {};
          pairSupport[pA]![pB] = (pairSupport[pA]![pB] ?? 0) + 1;
        }
      }

      processed++;
      if (processed % 100 == 0) {
        onProgress(0.1 + (0.5 * (processed / totalInvoices)), 'تحليل فاتورة $processed من $totalInvoices');
      }
    }

    onProgress(0.65, 'جاري تطبيق خوارزميات الرفع والثقة (Confidence & Lift)...');
    
    // 3. بناء قوانين الذكاء الخبير وتسجيلها
    Batch batch = expertDb.batch();
    int ruleCount = 0;

    for (final pA in pairSupport.keys) {
      for (final pB in pairSupport[pA]!.keys) {
        final sharedSupport = pairSupport[pA]![pB]!;
        
        // منع تسجيل العلاقات النادرة جداً (صدفة قوية) إلا لو كان الرفع يثبت العكس
        // Support Threshold
        if (sharedSupport < 3 && totalInvoices > 50) continue; 

        final sA = productSupport[pA]!;
        final sB = productSupport[pB]!;

        // Confidence: A -> B
        final confAB = sharedSupport / sA;
        // Confidence: B -> A
        final confBA = sharedSupport / sB;
        final maxConf = confAB > confBA ? confAB : confBA;

        // Lift
        // P(A&B) / (P(A) * P(B))
        double lift = (sharedSupport * totalInvoices) / (sA * sB);

        String relationType = 'neutral';
        if (lift >= 1.2) {
          relationType = 'positive';
        } else if (lift <= 0.8) {
          relationType = 'negative';
        }

        // حفظ القانون (نعتبر معرفات المنتجات صورية هنا، نعتمد على الأسماء)
        batch.insert('expert_product_relations', {
          'product_id_a': pA.hashCode,
          'product_id_b': pB.hashCode,
          'product_name_a': pA,
          'product_name_b': pB,
          'support': sharedSupport,
          'confidence': maxConf,
          'lift': lift,
          'relation_type': relationType,
        });
        ruleCount++;
        
        // تنفيذ جزئي لتجنب تجاوز حجم الحزمة
        if (ruleCount % 500 == 0) {
          await batch.commit(noResult: true);
          batch = expertDb.batch();
        }
      }
    }
    await batch.commit(noResult: true);

    onProgress(0.85, 'جاري بناء خريطة التتابع (Sequences Logic)...');
    // 4. بناء تتابعات السلاسل
    batch = expertDb.batch();
    for (final pFrom in sequences.keys) {
      int totalTransitions = sequences[pFrom]!.values.fold(0, (sum, count) => sum + count);
      for (final pTo in sequences[pFrom]!.keys) {
        final count = sequences[pFrom]![pTo]!;
        if (count < 2 && totalInvoices > 50) continue; // تجاهل التتابعات النادرة

        final prob = count / totalTransitions;
        
        batch.insert('expert_product_sequences', {
          'from_product_name': pFrom,
          'to_product_name': pTo,
          'sequence_count': count,
          'probability': prob,
        });
      }
    }
    await batch.commit(noResult: true);

    // تسجيل الفوقيات
    await expertDb.insert('training_metadata', {
      'last_trained_at': DateTime.now().toIso8601String(),
      'invoices_analyzed': totalInvoices,
      'duration_ms': stopwatch.elapsedMilliseconds,
    });

    stopwatch.stop();
    onProgress(1.0, 'اكتمل التدريب الشامل بنجاح!');
  }

  /// جلب العلاقات الشاملة المخبأة الخاصة بمجموعة منتجات لتسريع التوقع اللحظي
  Future<Map<String, Map<String, double>>> getGlobalLiftsForNames(List<String> names) async {
    final expertDb = await ExpertKnowledgeDatabase.instance.database;
    if (names.isEmpty) return {};

    final placeholders = List.filled(names.length, '?').join(',');
    final args = [...names, ...names];

    final results = await expertDb.rawQuery('''
      SELECT product_name_a, product_name_b, lift 
      FROM expert_product_relations
      WHERE product_name_a IN ($placeholders) OR product_name_b IN ($placeholders)
    ''', args);

    final Map<String, Map<String, double>> cache = {};
    for (final row in results) {
      final pA = row['product_name_a'] as String;
      final pB = row['product_name_b'] as String;
      final lift = row['lift'] as double;
      
      cache[pA] ??= {};
      cache[pA]![pB] = lift;
      
      cache[pB] ??= {};
      cache[pB]![pA] = lift;
    }
    return cache;
  }

  /// جلب التتابع الخبير لتنظيم الفاتورة أخيراً (قائمة بأقوى التتابعات)
  Future<Map<String, List<String>>> getGlobalSequences() async {
    final expertDb = await ExpertKnowledgeDatabase.instance.database;
    // نأخذ أقوى المسارات الاحتمالية لكل منتج
    final results = await expertDb.rawQuery('''
      SELECT from_product_name, to_product_name
      FROM expert_product_sequences
      WHERE probability > 0.05
      ORDER BY probability DESC
    ''');
    
    final Map<String, List<String>> nextMap = {};
    for (final row in results) {
      final f = row['from_product_name'] as String;
      final t = row['to_product_name'] as String;
      nextMap[f] ??= [];
      nextMap[f]!.add(t);
    }
    return nextMap;
  }

  // ════════════════════════════════════════════════════════════════════════
  // 🔄 التدريب التدريجي — يُضيف على البيانات الموجودة دون مسح
  // ════════════════════════════════════════════════════════════════════════

  /// ضمان وجود جداول التعلم التدريجي (تهجين تلقائي)
  Future<void> _ensureIncrementalTablesExist(dynamic expertDb) async {
    await expertDb.execute('''
      CREATE TABLE IF NOT EXISTS expert_invoice_counter (
        id INTEGER PRIMARY KEY DEFAULT 1,
        total_invoices INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await expertDb.rawInsert(
      'INSERT OR IGNORE INTO expert_invoice_counter (id, total_invoices) VALUES (1, 0)'
    );
    await expertDb.execute('''
      CREATE TABLE IF NOT EXISTS product_global_support (
        product_name TEXT PRIMARY KEY,
        support_count INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  /// 🔄 التدريب التدريجي على فاتورة واحدة فقط
  /// يُضيف على البيانات الموجودة بدلاً من إعادة بناء الكل — خفيف وسريع جداً
  Future<void> learnFromSingleInvoice(int invoiceId) async {
    print('🔄 [Expert] تدريب تدريجي على الفاتورة: $invoiceId');
    
    final mainDb = await DatabaseService().database;
    final expertDb = await ExpertKnowledgeDatabase.instance.database;
    
    // ضمان وجود الجداول
    await _ensureIncrementalTablesExist(expertDb);
    
    // 1. جلب أصناف الفاتورة
    final items = await mainDb.rawQuery('''
      SELECT product_name
      FROM invoice_items
      WHERE invoice_id = ?
      ORDER BY id ASC
    ''', [invoiceId]);
    
    if (items.length < 2) {
      print('🔄 [Expert] فاتورة $invoiceId لا تحتوي على صنفين أو أكثر — تخطّى');
      return;
    }
    
    final pNames = items.map((i) => i['product_name'].toString()).toList();
    
    // 2. زيادة عداد الفواتير الإجمالي
    await expertDb.rawUpdate(
      'UPDATE expert_invoice_counter SET total_invoices = total_invoices + 1 WHERE id = 1'
    );
    final counterRow = await expertDb.rawQuery(
      'SELECT total_invoices FROM expert_invoice_counter WHERE id = 1'
    );
    final totalInvoices = (counterRow.first['total_invoices'] as int? ?? 1);
    
    // 3. تحديث support كل منتج (UPSERT)
    final uniqueProducts = pNames.toSet();
    for (final p in uniqueProducts) {
      await expertDb.rawInsert('''
        INSERT INTO product_global_support (product_name, support_count)
        VALUES (?, 1)
        ON CONFLICT(product_name) DO UPDATE SET support_count = support_count + 1
      ''', [p]);
    }
    
    // جلب جميع قيم المنتجات لحساب lift
    final supportRows = await expertDb.rawQuery(
      'SELECT product_name, support_count FROM product_global_support'
    );
    final Map<String, int> productSupport = {
      for (final r in supportRows)
        r['product_name'] as String: r['support_count'] as int
    };
    
    // 4. تحديث أزواج المنتجات (UPSERT ثم إعادة حساب lift)
    for (int i = 0; i < pNames.length; i++) {
      for (int j = i + 1; j < pNames.length; j++) {
        // فرز ألفبائياً لضمان UNIQUE
        final pA = pNames[i].compareTo(pNames[j]) < 0 ? pNames[i] : pNames[j];
        final pB = pNames[i].compareTo(pNames[j]) < 0 ? pNames[j] : pNames[i];
        
        // UPSERT: زِد pair support
        await expertDb.rawInsert('''
          INSERT INTO expert_product_relations
            (product_id_a, product_id_b, product_name_a, product_name_b, support, confidence, lift, relation_type)
          VALUES (?, ?, ?, ?, 1, 0.0, 0.0, 'neutral')
          ON CONFLICT(product_id_a, product_id_b) DO UPDATE SET support = support + 1
        ''', [pA.hashCode, pB.hashCode, pA, pB]);
        
        // جلب القيمة المحدثة وأعد حساب confidence و lift
        final pairRow = await expertDb.rawQuery('''
          SELECT support FROM expert_product_relations
          WHERE product_name_a = ? AND product_name_b = ?
        ''', [pA, pB]);
        if (pairRow.isEmpty) continue;
        
        final pairSupport = pairRow.first['support'] as int;
        final sA = productSupport[pA] ?? 1;
        final sB = productSupport[pB] ?? 1;
        final maxConf = pairSupport / (sA < sB ? sA : sB);
        final lift = (pairSupport * totalInvoices) / (sA * sB);
        
        String relType = 'neutral';
        if (lift >= 1.2) relType = 'positive';
        else if (lift <= 0.8) relType = 'negative';
        
        await expertDb.rawUpdate('''
          UPDATE expert_product_relations
          SET confidence = ?, lift = ?, relation_type = ?
          WHERE product_name_a = ? AND product_name_b = ?
        ''', [maxConf, lift, relType, pA, pB]);
      }
    }
    
    // 5. تحديث التتابعات (UPSERT)
    final Set<String> affectedFroms = {};
    for (int i = 0; i < pNames.length - 1; i++) {
      final from = pNames[i];
      final to = pNames[i + 1];
      if (from == to) continue;
      
      await expertDb.rawInsert('''
        INSERT INTO expert_product_sequences (from_product_name, to_product_name, sequence_count, probability)
        VALUES (?, ?, 1, 0.0)
        ON CONFLICT(from_product_name, to_product_name) DO UPDATE SET sequence_count = sequence_count + 1
      ''', [from, to]);
      affectedFroms.add(from);
    }
    
    // 6. إعادة حساب الاحتمالٚات للمنتجات المتأثرة فقط
    for (final fromProduct in affectedFroms) {
      final totalRow = await expertDb.rawQuery('''
        SELECT COALESCE(SUM(sequence_count), 0) as total
        FROM expert_product_sequences
        WHERE from_product_name = ?
      ''', [fromProduct]);
      final total = (totalRow.first['total'] as num?)?.toInt() ?? 0;
      if (total == 0) continue;
      
      await expertDb.rawUpdate('''
        UPDATE expert_product_sequences
        SET probability = CAST(sequence_count AS REAL) / ?
        WHERE from_product_name = ?
      ''', [total, fromProduct]);
    }
    
    print('✅ [Expert] اكتمل التدريب التدريجي للفاتورة $invoiceId (${pNames.length} أصناف، إجمالي الفواتير: $totalInvoices)');
  }
}
