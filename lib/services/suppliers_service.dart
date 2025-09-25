import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/supplier.dart';
import 'database_service.dart';

class SuppliersService {
  SuppliersService();

  Future<Database> get _db async => await DatabaseService().database;

  Future<void> ensureTables() async {
    final db = await _db;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_name TEXT NOT NULL,
        tax_number TEXT,
        phone_number TEXT,
        email_address TEXT,
        address TEXT,
        opening_balance REAL NOT NULL DEFAULT 0.0,
        current_balance REAL NOT NULL DEFAULT 0.0,
        total_purchases REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        last_modified_at TEXT NOT NULL,
        notes TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        invoice_number TEXT,
        invoice_date TEXT NOT NULL,
        total_amount REAL NOT NULL,
        discount REAL NOT NULL DEFAULT 0.0,
        amount_paid REAL NOT NULL DEFAULT 0.0,
        currency TEXT NOT NULL DEFAULT 'IQD',
        status TEXT NOT NULL DEFAULT 'آجل',
        payment_type TEXT NOT NULL DEFAULT 'دين',
        created_at TEXT NOT NULL,
        last_modified_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');

    // Ensure migration for older databases: add missing columns
    try {
      final cols = await db.rawQuery('PRAGMA table_info(supplier_invoices);');
      final hasPaymentType = cols.any((c) => (c['name'] == 'payment_type'));
      if (!hasPaymentType) {
        await db.execute(
            "ALTER TABLE supplier_invoices ADD COLUMN payment_type TEXT NOT NULL DEFAULT 'دين';");
      }
      final hasAmountPaid = cols.any((c) => (c['name'] == 'amount_paid'));
      if (!hasAmountPaid) {
        await db.execute(
            'ALTER TABLE supplier_invoices ADD COLUMN amount_paid REAL NOT NULL DEFAULT 0.0;');
      }
    } catch (_) {}
    // Migration for suppliers.total_purchases
    try {
      final colsSup = await db.rawQuery('PRAGMA table_info(suppliers);');
      final hasTotalPurchases = colsSup.any((c) => (c['name'] == 'total_purchases'));
      if (!hasTotalPurchases) {
        await db.execute('ALTER TABLE suppliers ADD COLUMN total_purchases REAL NOT NULL DEFAULT 0.0;');
      }
    } catch (_) {}
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER NOT NULL,
        receipt_number TEXT,
        receipt_date TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_method TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_type TEXT NOT NULL,
        owner_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        file_type TEXT NOT NULL,
        extracted_text TEXT,
        extraction_confidence REAL,
        uploaded_at TEXT NOT NULL
      )
    ''');
  }

  Future<List<Supplier>> getAllSuppliers() async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query('suppliers', orderBy: 'company_name COLLATE NOCASE');
    return rows.map((e) => Supplier.fromMap(e)).toList();
  }

  Future<int> insertSupplier(Supplier supplier) async {
    await ensureTables();
    final db = await _db;
    supplier.lastModifiedAt = DateTime.now();
    return await db.insert('suppliers', supplier.toMap());
  }

  Future<int> insertSupplierInvoice(SupplierInvoice invoice) async {
    await ensureTables();
    final db = await _db;
    final id = await db.insert('supplier_invoices', invoice.toMap());
    // احسب تأثير الفاتورة على الرصيد
    final double remaining = (invoice.totalAmount - invoice.amountPaid);
    final double delta = invoice.paymentType == 'نقد' ? 0.0 : (remaining > 0 ? remaining : 0.0);
    // اطبع الرصيد قبل/بعد للتشخيص
    try {
      final beforeRow = await db.query('suppliers', columns: ['current_balance','total_purchases'], where: 'id = ?', whereArgs: [invoice.supplierId], limit: 1);
      final double before = beforeRow.isNotEmpty ? ((beforeRow.first['current_balance'] as num?)?.toDouble() ?? 0.0) : 0.0;
      final double after = before + delta;
      print('DEBUG BALANCE (Invoice): supplier=${invoice.supplierId} total=${invoice.totalAmount} paid=${invoice.amountPaid} type=${invoice.paymentType} delta=$delta before=$before after=$after');
    } catch (_) {}
    // حدّث الرصيد والمشتريات الإجمالية (المشتريات تزيد دائماً بقيمة الفاتورة)
    await db.rawUpdate(
      'UPDATE suppliers SET current_balance = current_balance + ?, total_purchases = total_purchases + ?, last_modified_at = ? WHERE id = ?',
      [delta, invoice.totalAmount, DateTime.now().toIso8601String(), invoice.supplierId],
    );
    return id;
  }

  Future<int> insertSupplierReceipt(SupplierReceipt receipt) async {
    await ensureTables();
    final db = await _db;
    final id = await db.insert('supplier_receipts', receipt.toMap());
    // اطبع الرصيد قبل/بعد للتشخيص
    try {
      final beforeRow = await db.query('suppliers', columns: ['current_balance'], where: 'id = ?', whereArgs: [receipt.supplierId], limit: 1);
      final double before = beforeRow.isNotEmpty ? ((beforeRow.first['current_balance'] as num?)?.toDouble() ?? 0.0) : 0.0;
      final double delta = -receipt.amount;
      final double after = before + delta;
      print('DEBUG BALANCE (Receipt): supplier=${receipt.supplierId} amount=${receipt.amount} delta=$delta before=$before after=$after');
    } catch (_) {}
    await db.rawUpdate(
      'UPDATE suppliers SET current_balance = current_balance - ? , last_modified_at = ? WHERE id = ?',
      [receipt.amount, DateTime.now().toIso8601String(), receipt.supplierId],
    );
    return id;
  }

  Future<int> insertAttachment(Attachment attachment) async {
    await ensureTables();
    final db = await _db;
    return await db.insert('attachments', attachment.toMap());
  }

  Future<String> saveAttachmentFile({required List<int> bytes, required String extension}) async {
    final dir = await getApplicationSupportDirectory();
    final attachmentsDir = Directory(p.join(dir.path, 'attachments'));
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }
    final fileName = 'att_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final filePath = p.join(attachmentsDir.path, fileName);
    final file = File(filePath);
    await file.writeAsBytes(bytes, flush: true);
    return filePath;
  }

  Future<List<SupplierInvoice>> getInvoicesBySupplier(int supplierId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query('supplier_invoices',
        where: 'supplier_id = ?', whereArgs: [supplierId], orderBy: 'invoice_date DESC');
    return rows.map((e) => SupplierInvoice.fromMap(e)).toList();
  }

  Future<List<SupplierReceipt>> getReceiptsBySupplier(int supplierId) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query('supplier_receipts',
        where: 'supplier_id = ?', whereArgs: [supplierId], orderBy: 'receipt_date DESC');
    return rows.map((e) => SupplierReceipt.fromMap(e)).toList();
  }

  Future<List<Attachment>> getAttachmentsForSupplier(int supplierId) async {
    await ensureTables();
    final db = await _db;
    // مرفقات مرتبطة بالمورد مباشرة أو بعملياته
    final invoiceIds = await db.query('supplier_invoices',
        columns: ['id'], where: 'supplier_id = ?', whereArgs: [supplierId]);
    final receiptIds = await db.query('supplier_receipts',
        columns: ['id'], where: 'supplier_id = ?', whereArgs: [supplierId]);
    final invIds = invoiceIds.map((e) => e['id'] as int).toList();
    final recIds = receiptIds.map((e) => e['id'] as int).toList();

    final List<Map<String, Object?>> rows = [];
    if (invIds.isNotEmpty) {
      final inPlaceholders = List.filled(invIds.length, '?').join(',');
      final r = await db.rawQuery(
          'SELECT * FROM attachments WHERE owner_type = "SupplierInvoice" AND owner_id IN ($inPlaceholders)',
          invIds);
      rows.addAll(r);
    }
    if (recIds.isNotEmpty) {
      final inPlaceholders = List.filled(recIds.length, '?').join(',');
      final r = await db.rawQuery(
          'SELECT * FROM attachments WHERE owner_type = "SupplierReceipt" AND owner_id IN ($inPlaceholders)',
          recIds);
      rows.addAll(r);
    }
    return rows.map((e) => Attachment.fromMap(e)).toList();
  }

  Future<List<Attachment>> getAttachmentsForOwner({
    required String ownerType,
    required int ownerId,
  }) async {
    await ensureTables();
    final db = await _db;
    final rows = await db.query('attachments',
        where: 'owner_type = ? AND owner_id = ?',
        whereArgs: [ownerType, ownerId],
        orderBy: 'uploaded_at DESC');
    return rows.map((e) => Attachment.fromMap(e)).toList();
  }
}


