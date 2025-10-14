// providers/app_provider.dart
import 'package:flutter/foundation.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../services/database_service.dart';
import '../services/drive_service.dart';
import '../services/pdf_service.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';

class AppProvider with ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final DriveService _drive = DriveService();
  final PdfService _pdf = PdfService();

  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  Customer? _selectedCustomer;
  List<DebtTransaction> _customerTransactions = [];
  bool _isLoading = false;
  String _searchQuery = '';
  bool _isDriveSupported = false;
  bool _isDriveSignedInSync = false;
  bool _autoCreateCustomerOnSync = true; // إنشاء العميل تلقائياً عند المزامنة إذا لم يكن موجوداً

  // Temporary invoice state for preserving unsaved invoice data
  String _tempCustomerName = '';
  String _tempCustomerPhone = '';
  String _tempCustomerAddress = '';
  String _tempInstallerName = '';
  DateTime _tempInvoiceDate = DateTime.now();
  String _tempPaymentType = 'نقد';
  double _tempDiscount = 0.0;
  String _tempPaidAmount = '0.00';
  List<InvoiceItem> _tempInvoiceItems = [];
  bool _hasTempInvoiceData = false;

  // Getters
  List<Customer> get customers => _filteredCustomers;
  Customer? get selectedCustomer => _selectedCustomer;
  List<DebtTransaction> get customerTransactions => _customerTransactions;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  bool get isDriveSupported => _isDriveSupported;
  bool get isDriveSignedInSync => _isDriveSignedInSync;
  bool get autoCreateCustomerOnSync => _autoCreateCustomerOnSync;

  // Temporary invoice getters
  String get tempCustomerName => _tempCustomerName;
  String get tempCustomerPhone => _tempCustomerPhone;
  String get tempCustomerAddress => _tempCustomerAddress;
  String get tempInstallerName => _tempInstallerName;
  DateTime get tempInvoiceDate => _tempInvoiceDate;
  String get tempPaymentType => _tempPaymentType;
  double get tempDiscount => _tempDiscount;
  String get tempPaidAmount => _tempPaidAmount;
  List<InvoiceItem> get tempInvoiceItems =>
      List.unmodifiable(_tempInvoiceItems);
  bool get hasTempInvoiceData => _hasTempInvoiceData;

  // Initialize the app
  Future<void> initialize() async {
    _setLoading(true);
    try {
      _isDriveSupported = _drive.isSupported;
      if (_isDriveSupported) {
        _isDriveSignedInSync = await _drive.isSignedIn();
      }
      await _loadCustomers();
      await ensureAudioNotesDirectory();
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // Customer operations
  Future<void> _loadCustomers() async {
    // استخدم قائمة سجل الديون: تظهر من لديهم دين أو لديهم معاملات
    _customers = await _db.getCustomersForDebtRegister();
    _customers.sort((a, b) => a.name.compareTo(b.name));
    _applySearchFilter();
  }

  Future<void> addCustomer(Customer customer) async {
    final id = await _db.insertCustomer(customer);
    final newCustomer = customer.copyWith(id: id);
    _customers.add(newCustomer);
    _applySearchFilter();
    notifyListeners();
  }

  Future<void> updateCustomer(Customer customer) async {
    await _db.updateCustomer(customer);
    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index != -1) {
      _customers[index] = customer;
      if (_selectedCustomer?.id == customer.id) {
        _selectedCustomer = customer;
      }
      _applySearchFilter();
      notifyListeners();
    }
  }

  Future<void> deleteCustomer(int id) async {
    await _db.deleteCustomer(id);
    _customers.removeWhere((c) => c.id == id);
    if (_selectedCustomer?.id == id) {
      _selectedCustomer = null;
      _customerTransactions = [];
    }
    _applySearchFilter();
    notifyListeners();
  }

  // Transaction operations
  Future<void> loadCustomerTransactions(int customerId) async {
    _customerTransactions = await _db.getCustomerTransactions(customerId);
    notifyListeners();
  }

  Future<void> addTransaction(DebtTransaction transaction) async {
    final id = await _db.insertTransaction(transaction);
    final newTransaction = transaction.copyWith(id: id);
    _customerTransactions.insert(0, newTransaction);

    // Update customer's total debt
    final customer =
        _customers.firstWhere((c) => c.id == transaction.customerId);
    final updatedCustomer = customer.copyWith(
      currentTotalDebt: transaction.newBalanceAfterTransaction,
      lastModifiedAt: DateTime.now(),
    );
    await updateCustomer(updatedCustomer);

    notifyListeners();
  }

  Future<void> updateTransaction(DebtTransaction transaction) async {
    // Only manual transactions (not linked to invoice) are supported here
    final updatedCustomer = await _db.updateManualTransaction(transaction);

    // Update local customer list/state
    final customerIndex = _customers.indexWhere((c) => c.id == updatedCustomer.id);
    if (customerIndex != -1) {
      _customers[customerIndex] = updatedCustomer;
    }
    if (_selectedCustomer?.id == updatedCustomer.id) {
      _selectedCustomer = updatedCustomer;
    }

    // Refresh transactions list for this customer
    await loadCustomerTransactions(updatedCustomer.id!);
    _applySearchFilter();
    notifyListeners();
  }

  // Search functionality
  void setSearchQuery(String query) {
    _searchQuery = query;
    _applySearchFilter();
  }

  void _applySearchFilter() {
    if (_searchQuery.isEmpty) {
      _filteredCustomers = List.from(_customers);
    } else {
      _filteredCustomers = _customers
          .where((customer) =>
              customer.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    notifyListeners();
  }

  // Customer selection
  Future<void> selectCustomer(Customer customer) async {
    _selectedCustomer = customer;
    await loadCustomerTransactions(customer.id!);
  }

  // رفع سجل الديون إلى Google Drive
  Future<void> uploadDebtRecord() async {
    if (!_isDriveSupported) {
      throw Exception('ميزة التقارير غير مدعومة على هذا النظام');
    }
    _setLoading(true);
    try {
      // رفع جميع العملاء الذين عليهم دين بدلاً من العملاء المعدلين اليوم فقط
      final allCustomersWithDebt = _customers
          .where((customer) => customer.currentTotalDebt > 0)
          .toList();
      if (allCustomersWithDebt.isNotEmpty) {
        final reportFile = await _pdf.generateDailyReport(allCustomersWithDebt);
        await _drive.uploadDailyReport(reportFile);
      } else {
        // إذا لم يكن هناك عملاء عليهم دين، ارفع ملف فارغ أو رسالة
        final reportFile = await _pdf.generateDailyReport([]);
        await _drive.uploadDailyReport(reportFile);
      }
    } finally {
      _setLoading(false);
    }
  }

  // مزامنة الديون عبر Google Drive
  Future<void> syncDebts() async {
    if (!_isDriveSupported) {
      throw Exception('ميزة Google Drive غير مدعومة على هذا النظام');
    }
    _setLoading(true);
    try {
      // 1) تأكد من تسجيل الدخول
      final signed = await _drive.isSignedIn();
      if (!signed) {
        await _drive.signIn();
      }

      // 2) تجهيز مسارات المزامنة
      final syncFolderId = await _drive.ensureSyncFolder();
      final ownFileName = await _drive.getOwnDeviceJsonName();
      print('SYNC: syncFolderId=' + syncFolderId + ', ownFileName=' + ownFileName);

      // 3) تحميل ملفنا الحالي (أو البدء بفارغ)
      Map<String, dynamic> ownJson = await _drive.readDeviceJson(syncFolderId, ownFileName);
      if (ownJson.isEmpty) ownJson = {};
      print('SYNC: loaded own JSON with customer keys: ' + ownJson.keys.length.toString());

      // 4) رفع معاملاتنا غير المرفوعة
      final toUpload = await _db.getTransactionsToUpload();
      print('SYNC: transactions to upload count = ' + toUpload.length.toString());
      if (toUpload.isNotEmpty) {
        for (final tx in toUpload) {
          // احصل على اسم العميل بطريقة موثوقة من قاعدة البيانات عند الحاجة
          Customer? customer;
          try {
            customer = _customers.firstWhere((c) => c.id == tx.customerId);
          } catch (_) {
            customer = await _db.getCustomerById(tx.customerId);
          }
          if (customer == null) {
            print('SYNC WARN: لم يتم العثور على اسم عميل للمعاملة ${tx.id}, سيتم تجاهل رفعها لتجنب UNKNOWN');
            continue;
          }
          final key = (customer.name).replaceAll(RegExp(r'[\s,]'), '');
          ownJson[key] ??= { 'transactions': [], 'displayName': customer.name };
          // تأكد من حفظ displayName إن لم يكن موجوداً
          if (ownJson[key] is Map && (ownJson[key]['displayName'] == null || (ownJson[key]['displayName'] as String).isEmpty)) {
            ownJson[key]['displayName'] = customer.name;
          }
          String? uuid = tx.transactionUuid;
          if (uuid == null || uuid.isEmpty) {
            uuid = _generateUuid();
            await _db.setTransactionUuidById(tx.id!, uuid);
          }
          ownJson[key]['transactions'].add({
            'transactionId': uuid,
            'date': tx.transactionDate.toIso8601String(),
            'amount': tx.amountChanged,
            'type': tx.amountChanged < 0 ? 'debt_payment' : 'debt_addition',
            'isRead': false,
            'description': tx.description ?? "من الفرع الثاني",
          });
        }
        // تنظيف المعاملات المقروءة في ملفنا
        ownJson.updateAll((_, v) {
          if (v is Map && v['transactions'] is List) {
            v['transactions'] = (v['transactions'] as List).where((t) => (t['isRead'] ?? false) == false).toList();
          }
          return v;
        });
        await _drive.writeDeviceJson(syncFolderId, ownFileName, ownJson);
        await _db.markTransactionsUploaded(
          toUpload.map((t) => t.transactionUuid ?? '').where((s) => s.isNotEmpty).toList(),
        );
        print('SYNC: uploaded own JSON and marked ' + toUpload.length.toString() + ' as uploaded');
      }

      // 5) قراءة ملفات الأجهزة الأخرى
      final allFiles = await _drive.listDeviceJsons(syncFolderId);
      print('SYNC: found ' + allFiles.length.toString() + ' JSON files in sync folder');
      for (final f in allFiles) { print('SYNC: file -> ' + (f.name ?? '')); }
      for (final f in allFiles) {
        final name = f.name ?? '';
        if (name == ownFileName) continue;
        print('SYNC: processing other device file ' + name);
        final content = await _drive.readDeviceJson(syncFolderId, name);
        if (content.isEmpty) { print('SYNC: file ' + name + ' has empty or invalid JSON'); continue; }
        print('SYNC: file ' + name + ' top-level keys count = ' + content.keys.length.toString());
        final firstKeys = content.keys.take(5).toList();
        print('SYNC: first keys: ' + firstKeys.join(', '));
        // Debug preview: print up to five customers and first five transactions from other device JSON
        try {
          print('=== معاينة ملف جهاز آخر: ' + name + ' ===');
          int printedCustomers = 0;
          for (final entry in content.entries) {
            if (printedCustomers >= 5) break;
            final customerKey = entry.key;
            final obj = entry.value;
            if (obj is Map && obj['transactions'] is List) {
              final txs = (obj['transactions'] as List);
              print('- عميل: ' + customerKey + ' | عدد المعاملات: ' + txs.length.toString());
              final preview = txs.take(5);
              for (final t in preview) {
                final id = t['transactionId'];
                final date = t['date'];
                final amount = t['amount'];
                final type = t['type'];
                final isRead = t['isRead'];
                print('  • id=' + (id?.toString() ?? '') + ' | date=' + (date?.toString() ?? '') + ' | amount=' + (amount?.toString() ?? '') + ' | type=' + (type?.toString() ?? '') + ' | isRead=' + (isRead?.toString() ?? ''));
              }
              printedCustomers++;
            }
          }
          print('=== نهاية المعاينة ===');
        } catch (e) {
          print('فشل طباعة المعاينة لملف ' + name + ': ' + e.toString());
        }
        bool changed = false;
        for (final entry in content.entries) {
          final normName = entry.key.replaceAll(RegExp(r'[\s,]'), '');
          final obj = entry.value;
          if (obj is! Map) continue;
          final txs = (obj['transactions'] as List?) ?? [];
          // حاول مطابقة العميل محليًا
          Customer? local;
          try {
            local = _customers.firstWhere(
              (c) => c.name.replaceAll(RegExp(r'[\s,]'), '') == normName,
            );
          } catch (_) {
            local = null;
          }
          if (local == null) {
            if (_autoCreateCustomerOnSync) {
              // أنشئ العميل تلقائياً ثم طبّق المعاملات
              final createdName = (obj['displayName'] as String?)?.trim().isNotEmpty == true
                  ? (obj['displayName'] as String)
                  : entry.key.toString();
              try {
                final newId = await _db.insertCustomer(
                  Customer(name: createdName, currentTotalDebt: 0.0),
                );
                local = Customer(id: newId, name: createdName, currentTotalDebt: 0.0);
                _customers.add(local!);
                _applySearchFilter();
                print('SYNC: تم إنشاء عميل جديد أثناء المزامنة: ' + createdName + ' (id=' + newId.toString() + ')');
              } catch (e) {
                print('SYNC: فشل إنشاء عميل جديد ' + createdName + ': ' + e.toString());
                continue;
              }
            } else {
              print('SYNC: تجاهل عميل غير موجود محلياً: ' + entry.key.toString());
              continue;
            }
          }
          for (final t in txs) {
            final isRead = (t['isRead'] ?? false) == true;
            if (isRead) continue;
            final String type = (t['type'] ?? 'debt_addition') as String;
            final double amount = ((t['amount'] as num?) ?? 0).toDouble();
            final double signedAmount = type == 'debt_payment' ? -amount.abs() : amount.abs();
            final String? txId = t['transactionId'] as String?;
            final String? desc = t['description'] as String?;
            final DateTime occurred = DateTime.tryParse(t['date'] ?? '') ?? DateTime.now();
            // أدرج محليًا إذا لم تكن موجودة
            try {
              await _db.insertExternalTransactionAndApply(
                customerId: local.id!,
                amount: signedAmount,
                type: type.toUpperCase(),
                note: 'من مزامنة جهاز آخر',
                description: desc ?? 'إضافة من الكمبيوتر الثاني',
                transactionUuid: txId,
                occurredAt: occurred,
              );
            } catch (_) {}
            // علّم كمقروءة
            t['isRead'] = true;
            changed = true;
          }
        }
        if (changed) {
          await _drive.writeDeviceJson(syncFolderId, name, content);
        }
      }

      // 6) إعادة تحميل الحالة لعرض الأرصدة المحدثة
      await _loadCustomers();
      if (_selectedCustomer != null) {
        await loadCustomerTransactions(_selectedCustomer!.id!);
      }
    } finally {
      _setLoading(false);
    }
  }

  String _generateUuid() {
    // بديل بسيط لمنشئ UUID لتجنب إضافة تبعية الآن
    final now = DateTime.now().microsecondsSinceEpoch;
    final rand = (now ^ now.hashCode).abs();
    return 'tx_${now}_$rand';
  }

  // رفع ملف قاعدة البيانات إلى Google Drive داخل مجلد باسم MAC
  Future<void> uploadDatabaseToDrive({ValueChanged<double>? onProgress}) async {
    if (!_isDriveSupported) {
      throw Exception('ميزة Google Drive غير مدعومة على هذا النظام');
    }
    _setLoading(true);
    try {
      // 1) تحضير المحتوى المطلوب: قاعدة البيانات + جميع ملفات الصوت
      onProgress?.call(0.05);
      final dbFile = await _db.getDatabaseFile();
      final audioPaths = await _db.getAllAudioNotePaths();
      
      print('DEBUG: Found ${audioPaths.length} audio paths:');
      for (final path in audioPaths) {
        print('DEBUG: Audio path: $path');
      }

      // 2) إنشاء مجلد مؤقت ونسخ قاعدة البيانات وجمع الصوتيات
      onProgress?.call(0.15);
      final tempDir = await getTemporaryDirectory();
      final backupRoot = Directory('${tempDir.path}/backup_${DateTime.now().millisecondsSinceEpoch}');
      if (!await backupRoot.exists()) {
        await backupRoot.create(recursive: true);
      }
      final dbCopy = File('${backupRoot.path}/debt_book.db');
      await dbCopy.writeAsBytes(await dbFile.readAsBytes(), flush: true);

      final audioDir = Directory('${backupRoot.path}/audio');
      await audioDir.create(recursive: true);
      
      int copiedAudioFiles = 0;
      for (final p in audioPaths) {
        try {
          final f = File(p);
          print('DEBUG: Checking audio file: $p, exists: ${await f.exists()}');
          
          File? sourceFile = f;
          if (!await f.exists()) {
            // البحث عن الملف في مجلدات أخرى محتملة
            final fileName = p.split(Platform.pathSeparator).last;
            print('DEBUG: File not found at original path, searching for: $fileName');
            
            // البحث في مجلد قاعدة البيانات الحالي أولاً
            final supportDir = await getApplicationSupportDirectory();
            final dbAudioDir = Directory('${supportDir.path}/audio_notes');
            final currentUserFile = File('${dbAudioDir.path}/$fileName');
            if (await currentUserFile.exists()) {
              sourceFile = currentUserFile;
              print('DEBUG: Found file in database directory: ${currentUserFile.path}');
            } else {
              // البحث في مجلد المستندات العام
              final publicDocs = Directory('${Platform.environment['PUBLIC'] ?? ''}\\Documents');
              if (await publicDocs.exists()) {
                final publicFile = File('${publicDocs.path}\\$fileName');
                if (await publicFile.exists()) {
                  sourceFile = publicFile;
                  print('DEBUG: Found file in public documents: ${publicFile.path}');
                }
              }
              
              // البحث في مجلد المستندات للمستخدمين الآخرين
              final usersDir = Directory('C:\\Users');
              if (await usersDir.exists()) {
                await for (final userDir in usersDir.list()) {
                  if (userDir is Directory) {
                    final userDocs = Directory('${userDir.path}\\Documents');
                    if (await userDocs.exists()) {
                      final userFile = File('${userDocs.path}\\$fileName');
                      if (await userFile.exists()) {
                        sourceFile = userFile;
                        print('DEBUG: Found file in user documents: ${userFile.path}');
                        break;
                      }
                    }
                  }
                }
              }
            }
          }
          
          if (sourceFile != null && await sourceFile.exists()) {
            final fileName = sourceFile.path.split(Platform.pathSeparator).last;
            final targetPath = '${audioDir.path}/$fileName';
            
            // التأكد من أن الملف المصدر قابل للقراءة
            final sourceSize = await sourceFile.length();
            print('DEBUG: Source file size: $sourceSize bytes');
            
            if (sourceSize > 0) {
              await sourceFile.copy(targetPath);
              final copiedFile = File(targetPath);
              final copiedSize = await copiedFile.length();
              print('DEBUG: Copied file size: $copiedSize bytes');
              
              if (copiedSize == sourceSize) {
                copiedAudioFiles++;
                print('DEBUG: Successfully copied audio file to: $targetPath');
              } else {
                print('DEBUG: File size mismatch! Source: $sourceSize, Copied: $copiedSize');
              }
            } else {
              print('DEBUG: Source file is empty, skipping: $p');
            }
          } else {
            print('DEBUG: Audio file not found anywhere: $p');
          }
        } catch (e) {
          print('DEBUG: Error copying audio file $p: $e');
        }
      }
      print('DEBUG: Total audio files copied: $copiedAudioFiles');
      
      // نسخ إضافي للملفات الصوتية من مجلد قاعدة البيانات الحالي
      if (copiedAudioFiles == 0) {
        try {
          final supportDir = await getApplicationSupportDirectory();
          final currentAudioDir = Directory('${supportDir.path}/audio_notes');
          if (await currentAudioDir.exists()) {
            final currentAudioFiles = await currentAudioDir.list().toList();
            print('DEBUG: Found ${currentAudioFiles.length} audio files in current database directory');
            
            for (final file in currentAudioFiles) {
              if (file is File) {
                final fileName = file.path.split(Platform.pathSeparator).last;
                final targetPath = '${audioDir.path}/$fileName';
                if (!await File(targetPath).exists()) {
                  await file.copy(targetPath);
                  copiedAudioFiles++;
                  print('DEBUG: Copied audio file from current database directory: $fileName');
                }
              }
            }
          }
        } catch (e) {
          print('DEBUG: Error copying from current database directory: $e');
        }
      }
      
      // نسخ إضافي للملفات الصوتية في مجلد قاعدة البيانات للنسخ الاحتياطية
      if (copiedAudioFiles > 0) {
        try {
          final supportDir = await getApplicationSupportDirectory();
          final backupAudioDir = Directory('${supportDir.path}/audio_backup');
          await backupAudioDir.create(recursive: true);
          
          for (final p in audioPaths) {
            try {
              final f = File(p);
              if (await f.exists()) {
                final base = p.split(Platform.pathSeparator).last;
                final backupPath = '${backupAudioDir.path}/$base';
                await f.copy(backupPath);
                print('DEBUG: Created backup audio file: $backupPath');
              }
            } catch (e) {
              print('DEBUG: Error creating backup audio file: $e');
            }
          }
        } catch (e) {
          print('DEBUG: Error creating audio backup directory: $e');
        }
      }

      // 3) إنشاء ملف zip باسم التاريخ yyyy-MM-dd.zip
      onProgress?.call(0.45);
      final now = DateTime.now();
      final zipName = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}.zip';
      final zipFile = File('${tempDir.path}/$zipName');
      final encoder = ZipFileEncoder();
      encoder.create(zipFile.path);
      encoder.addFile(dbCopy);
      print('DEBUG: Added database file to ZIP: ${dbCopy.path}');
      
      if (await audioDir.exists()) {
        final audioFiles = await audioDir.list().toList();
        print('DEBUG: Audio directory exists with ${audioFiles.length} files');
        for (final file in audioFiles) {
          print('DEBUG: Audio file in directory: ${file.path}');
        }
        if (audioFiles.isNotEmpty) {
          encoder.addDirectory(audioDir);
          print('DEBUG: Added audio directory to ZIP with ${audioFiles.length} files');
        } else {
          print('DEBUG: Audio directory is empty, not adding to ZIP');
        }
      } else {
        print('DEBUG: Audio directory does not exist');
      }
      encoder.close();
      print('DEBUG: ZIP file created: ${zipFile.path}');

      // 4) الرفع وسياسة الاحتفاظ
      onProgress?.call(0.75);
      await _drive.uploadBackupZipAndRetain(zipFile: zipFile, progress: (p) {
        onProgress?.call(0.75 + 0.2 * p.clamp(0.0, 1.0));
      });

      onProgress?.call(1.0);
    } finally {
      _setLoading(false);
    }
  }

  // Google Drive authentication
  Future<bool> isDriveSignedIn() async {
    if (!_isDriveSupported) return false;
    _isDriveSignedInSync = await _drive.isSignedIn();
    notifyListeners();
    return _isDriveSignedInSync;
  }

  Future<void> signInToDrive() async {
    if (!_isDriveSupported) {
      throw Exception('تسجيل الدخول غير مدعوم على هذا النظام');
    }
    await _drive.signIn();
    _isDriveSignedInSync = await _drive.isSignedIn();
    notifyListeners();
  }

  Future<void> signOutFromDrive() async {
    if (!_isDriveSupported) return;
    await _drive.signOut();
    _isDriveSignedInSync = false;
    notifyListeners();
  }

  Future<List<Invoice>> getAllInvoices() async {
    return await _db.getAllInvoices();
  }

  // New method to update an invoice and notify listeners
  Future<void> updateInvoice(Invoice invoice) async {
    await _db.updateInvoice(invoice);
    // Consider how you want to update local state if necessary,
    // e.g., if invoices are cached in AppProvider.
    // For now, simply notifying listeners will trigger a re-fetch in consuming widgets.
    notifyListeners();
  }

  // Temporary invoice state management methods
  void saveTempInvoiceData({
    required String customerName,
    required String customerPhone,
    required String customerAddress,
    required String installerName,
    required DateTime invoiceDate,
    required String paymentType,
    required double discount,
    required String paidAmount,
    required List<InvoiceItem> invoiceItems,
  }) {
    print(
        'DEBUG: AppProvider - Saving temp data with ${invoiceItems.length} items');
    for (int i = 0; i < invoiceItems.length; i++) {
      print(
          'DEBUG: AppProvider - Item $i: ${invoiceItems[i].productName} - ${invoiceItems[i].itemTotal}');
    }
    _tempCustomerName = customerName;
    _tempCustomerPhone = customerPhone;
    _tempCustomerAddress = customerAddress;
    _tempInstallerName = installerName;
    _tempInvoiceDate = invoiceDate;
    _tempPaymentType = paymentType;
    _tempDiscount = discount;
    _tempPaidAmount = paidAmount;
    _tempInvoiceItems = List.from(invoiceItems);
    _hasTempInvoiceData = true;
    print(
        'DEBUG: AppProvider - Temp data saved. Items count: ${_tempInvoiceItems.length}');
    notifyListeners();
  }

  void clearTempInvoiceData() {
    _tempCustomerName = '';
    _tempCustomerPhone = '';
    _tempCustomerAddress = '';
    _tempInstallerName = '';
    _tempInvoiceDate = DateTime.now();
    _tempPaymentType = 'نقد';
    _tempDiscount = 0.0;
    _tempPaidAmount = '0.00';
    _tempInvoiceItems.clear();
    _hasTempInvoiceData = false;
    notifyListeners();
  }

  void updateTempInvoiceItems(List<InvoiceItem> items) {
    print(
        'DEBUG: AppProvider - Updating temp invoice items. Count: ${items.length}');
    for (int i = 0; i < items.length; i++) {
      print(
          'DEBUG: AppProvider - Update Item $i: ${items[i].productName} - ${items[i].itemTotal}');
    }
    _tempInvoiceItems = List.from(items);
    _hasTempInvoiceData = true;
    print(
        'DEBUG: AppProvider - Updated temp items. New count: ${_tempInvoiceItems.length}');
    notifyListeners();
  }

  // New method to update temp data with all fields
  void updateTempData({
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? installerName,
    DateTime? invoiceDate,
    String? paymentType,
    double? discount,
    String? paidAmount,
    List<InvoiceItem>? invoiceItems,
  }) {
    if (customerName != null) _tempCustomerName = customerName;
    if (customerPhone != null) _tempCustomerPhone = customerPhone;
    if (customerAddress != null) _tempCustomerAddress = customerAddress;
    if (installerName != null) _tempInstallerName = installerName;
    if (invoiceDate != null) _tempInvoiceDate = invoiceDate;
    if (paymentType != null) _tempPaymentType = paymentType;
    if (discount != null) _tempDiscount = discount;
    if (paidAmount != null) _tempPaidAmount = paidAmount;
    if (invoiceItems != null) {
      print(
          'DEBUG: AppProvider - Updating temp data with ${invoiceItems.length} items');
      _tempInvoiceItems = List.from(invoiceItems);
    }
    _hasTempInvoiceData = true;
    notifyListeners();
  }

  // إنشاء مجلد الملفات الصوتية في نفس مجلد قاعدة البيانات
  Future<void> ensureAudioNotesDirectory() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final audioDir = Directory('${supportDir.path}/audio_notes');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
        print('DEBUG: Created audio notes directory: ${audioDir.path}');
      }
    } catch (e) {
      print('DEBUG: Error creating audio notes directory: $e');
    }
  }

}
