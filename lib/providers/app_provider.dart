// providers/app_provider.dart
import 'dart:async' show unawaited;
import 'package:flutter/foundation.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../models/invoice.dart';
import '../models/invoice_item.dart';
import '../services/database_service.dart';
import '../services/drive_service.dart';
import '../services/pdf_service.dart';
import '../services/financial_audit_service.dart';
import '../services/telegram_backup_service.dart';
import '../services/settings_manager.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:async'; // 🛡️ لـ StreamSubscription
import 'package:archive/archive_io.dart';
import '../services/firebase_sync/firebase_sync_helper.dart'; // Import SyncHelper
import '../services/firebase_sync/firebase_sync_service.dart'; // 🗑️ شاهد حذف العميل
import '../models/account_statement_item.dart';

// أنواع ترتيب العملاء
enum CustomerSortType {
  alphabetical,      // أبجدي (الافتراضي)
  lastDebtAdded,     // آخر إضافة دين
  lastPayment,       // آخر تسديد
  lastTransaction,   // آخر معاملة (أي نوع)
  highestDebt,       // الأكبر مبلغاً
}

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
  CustomerSortType _currentSortType = CustomerSortType.alphabetical; // نوع الترتيب الحالي
  StreamSubscription? _syncSubscription; // 🛡️ لإدارة اشتراك المزامنة
  bool _isDisposed = false; // 🛡️ لمنع الكراش بعد dispose

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
  CustomerSortType get currentSortType => _currentSortType;

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
      // 1️⃣ العملاء أولاً — هذا كل ما تحتاجه شاشة سجل الديون لتُفتح فوراً.
      // (كان فحص Google Drive يُنتظر قبلهم فيؤخر الفتح ثوانٍ على الجوال).
      await _loadCustomers();

      // 2️⃣ الباقي في الخلفية: فحص Drive (استدعاء شبكة) ومجلد الصوتيات —
      // لا يعطّل الفتح، ونحدّث الواجهة عند جهوزية حالة Drive فقط.
      unawaited(() async {
        try {
          _isDriveSupported = _drive.isSupported;
          if (_isDriveSupported) {
            _isDriveSignedInSync = await _drive.isSignedIn();
            if (!_isDisposed) notifyListeners();
          }
          await ensureAudioNotesDirectory();
        } catch (e) {
          print('⚠️ AppProvider: خطأ خلفي في تهيئة Drive/الصوتيات: $e');
        }
      }());

      // 3️⃣ الاستماع لأحداث المزامنة (خفيف — يبقى متزامناً)
      _syncSubscription?.cancel(); // 🛡️ إلغاء الاشتراك القديم لتجنب التكرار
      _syncSubscription = FirebaseSyncHelper().syncEvents.listen((event) {
        if (_isDisposed) return; // 🛡️ تجنب العمل بعد الإغلاق
        print('🔔 AppProvider: New sync event: $event');
        // 🛡️ تغليف بـ try-catch لمنع الكراش التلقائي
        try {
          _loadCustomers(); // Reload to reflect changes
          if (_selectedCustomer != null && _selectedCustomer!.id != null) {
            loadCustomerTransactions(_selectedCustomer!.id!);
          }
        } catch (e) {
          print('⚠️ AppProvider: خطأ أثناء معالجة حدث المزامنة: $e');
        }
      }, onError: (error) {
        // 🛡️ التقاط أخطاء الـ Stream لمنع الكراش التلقائي
        print('⚠️ AppProvider: خطأ في stream المزامنة: $error');
      });
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool value) {
    if (_isDisposed) return; // 🛡️ تجنب الكراش بعد dispose
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true; // 🛡️ تعيين العلامة قبل الإلغاء
    _syncSubscription?.cancel();
    super.dispose();
  }

  // Customer operations
  Future<void> _loadCustomers() async {
    // استخدم قائمة سجل الديون: تظهر من لديهم دين أو لديهم معاملات
    _customers = await _db.getCustomersForDebtRegister();
    await _applySorting();
    _applySearchFilter();
  }

  // تطبيق الترتيب على قائمة العملاء
  Future<void> _applySorting() async {
    switch (_currentSortType) {
      case CustomerSortType.alphabetical:
        _customers.sort((a, b) => a.name.compareTo(b.name));
        break;
      case CustomerSortType.lastDebtAdded:
        // ترتيب حسب آخر إضافة دين
        final sortedIds = await _db.getCustomerIdsSortedByLastDebtAdded();
        _sortCustomersByIds(sortedIds);
        break;
      case CustomerSortType.lastPayment:
        // ترتيب حسب آخر تسديد
        final sortedIds = await _db.getCustomerIdsSortedByLastPayment();
        _sortCustomersByIds(sortedIds);
        break;
      case CustomerSortType.lastTransaction:
        // ترتيب حسب آخر معاملة (أي نوع)
        final sortedIds = await _db.getCustomerIdsSortedByLastTransaction();
        _sortCustomersByIds(sortedIds);
        break;
      case CustomerSortType.highestDebt:
        // ترتيب حسب أكبر مبلغ دين
        _customers.sort((a, b) => (b.currentTotalDebt ?? 0).compareTo(a.currentTotalDebt ?? 0));
        break;
    }
  }

  // ترتيب العملاء حسب قائمة IDs
  void _sortCustomersByIds(List<int> sortedIds) {
    final idToIndex = <int, int>{};
    for (int i = 0; i < sortedIds.length; i++) {
      idToIndex[sortedIds[i]] = i;
    }
    _customers.sort((a, b) {
      final indexA = idToIndex[a.id] ?? 999999;
      final indexB = idToIndex[b.id] ?? 999999;
      return indexA.compareTo(indexB);
    });
  }

  // تغيير نوع الترتيب
  Future<void> setSortType(CustomerSortType sortType) async {
    _currentSortType = sortType;
    await _applySorting();
    _applySearchFilter();
    notifyListeners();
  }

  // إعادة تعيين الترتيب للافتراضي (أبجدي)
  void resetSortType() {
    _currentSortType = CustomerSortType.alphabetical;
    _customers.sort((a, b) => a.name.compareTo(b.name));
    _applySearchFilter();
    notifyListeners();
  }

  Future<void> addCustomer(Customer customer) async {
    final id = await _db.insertCustomer(customer);
    final newCustomer = customer.copyWith(id: id);
    _customers.add(newCustomer);
    _applySearchFilter();
    notifyListeners();
  }

  /// [updateBalance] لا يُمرَّر true إلا عند اعتماد رصيد محسوب عمداً.
  /// الافتراضي false يمنع إعادة كتابة رصيد قديم من الذاكرة فوق الرصيد الصحيح.
  Future<void> updateCustomer(Customer customer,
      {bool updateBalance = false}) async {
    await _db.updateCustomer(customer, updateBalance: updateBalance);
    // 🛡️ نقرأ النسخة المحفوظة فعلاً من قاعدة البيانات بدل الاعتماد على الكائن
    // الممرَّر، حتى لا تعرض الواجهة رصيداً قديماً بعد تعديل الاسم أو العنوان.
    Customer refreshed = customer;
    if (customer.id != null) {
      refreshed = await _db.getCustomerById(customer.id!) ?? customer;
    }
    final index = _customers.indexWhere((c) => c.id == customer.id);
    if (index != -1) {
      _customers[index] = refreshed;
      if (_selectedCustomer?.id == customer.id) {
        _selectedCustomer = refreshed;
      }
      _applySearchFilter();
      notifyListeners();
    }
  }

  Future<void> deleteCustomer(int id) async {
    // 🗑️ الحذف يُرفع كشاهد (isDeleted) لتحذفه كل الأجهزة، ولا «يُبعث» عند
    // السحب الكامل التالي. أوفلاين؟ يُحفظ في طابور الإعادة ويُرفع لاحقاً.
    final existing = await _db.getCustomerById(id);
    final syncUuid = existing?.syncUuid;
    await _db.deleteCustomer(id);
    if (syncUuid != null && syncUuid.isNotEmpty) {
      unawaited(FirebaseSyncService().deleteCustomerFromFirebase(syncUuid));
    }
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

    // 🛡️ تحديث نسخة العميل المختار من قاعدة البيانات مع كل تحميل للمعاملات.
    // بدون هذا يبقى الرصيد في الذاكرة هو الذي كان وقت فتح الشاشة، فتُعرض
    // أرقام قديمة وتُرسل رسائل واتساب بدين غير صحيح.
    if (_selectedCustomer?.id == customerId) {
      final fresh = await _db.getCustomerById(customerId);
      if (fresh != null) {
        _selectedCustomer = fresh;
        final idx = _customers.indexWhere((c) => c.id == customerId);
        if (idx != -1) _customers[idx] = fresh;
      }
    }

    notifyListeners();
  }

  Future<void> addTransaction(DebtTransaction transaction) async {
    // 1. إدراج المعاملة (تقوم قاعدة البيانات بتحديث رصيد العميل والتحقق منه)
    final id = await _db.insertTransaction(transaction);
    
    // 2. إعادة تحميل العميل من قاعدة البيانات للحصول على الرصيد المحدث والموثق
    final updatedCustomer = await _db.getCustomerById(transaction.customerId);
    
    if (updatedCustomer != null) {
      // تحديث القائمة المحلية
      final index = _customers.indexWhere((c) => c.id == transaction.customerId);
      if (index != -1) {
        _customers[index] = updatedCustomer;
      }
      // تحديث العميل المحدد إذا كان هو نفسه
      if (_selectedCustomer?.id == transaction.customerId) {
        _selectedCustomer = updatedCustomer;
      }
    }

    // 3. إعادة تحميل المعاملات لعرض الأرصدة الصحيحة (قبل/بعد) التي حسبتها قاعدة البيانات
    await loadCustomerTransactions(transaction.customerId);

    // 4. تسجيل العملية في سجل التدقيق
    try {
      final auditService = FinancialAuditService();
      await auditService.logOperation(
        operationType: transaction.transactionType == 'manual_debt' 
            ? 'transaction_create' 
            : 'payment_create',
        entityType: 'customer',
        entityId: transaction.customerId,
        newValues: {
          'transaction_id': id,
          'amount': transaction.amountChanged,
          'type': transaction.transactionType,
          'balance_before': transaction.balanceBeforeTransaction,
          'balance_after': transaction.newBalanceAfterTransaction,
          'note': transaction.transactionNote,
        },
        notes: transaction.transactionType == 'manual_debt'
            ? 'إضافة دين يدوي بقيمة ${transaction.amountChanged}'
            : 'تسديد دين بقيمة ${transaction.amountChanged.abs()}',
      );
    } catch (e) {
      print('تحذير: فشل تسجيل التدقيق: $e');
    }

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
    // 🛡️ الكائن الممرَّر هنا هو دائماً نسخة من وقت فتح الشاشة (widget.customer)
    // ولم يكن يُقرأ من قاعدة البيانات إطلاقاً. نقرأ النسخة الحالية أولاً حتى
    // لا يُبنى أي رقم على رصيد قديم.
    _selectedCustomer = customer;
    if (customer.id != null) {
      final fresh = await _db.getCustomerById(customer.id!);
      if (fresh != null) _selectedCustomer = fresh;
    }
    await loadCustomerTransactions(customer.id!);
  }

  // رفع سجل الديون إلى Google Drive
  Future<void> uploadDebtRecord() async {
    if (!_isDriveSupported) {
      throw Exception('ميزة التقارير غير مدعومة على هذا النظام');
    }
    _setLoading(true);
    try {
      // جلب اسم الفرع من الإعدادات
      final settings = await SettingsManager.getAppSettings();
      final branchName = settings.branchName;
      
      // رفع جميع العملاء الذين عليهم دين بدلاً من العملاء المعدلين اليوم فقط
      final allCustomersWithDebt = _customers
          .where((customer) => customer.currentTotalDebt > 0)
          .toList();
      if (allCustomersWithDebt.isNotEmpty) {
        final reportFile = await _pdf.generateDailyReport(allCustomersWithDebt);
        await _drive.uploadDailyReport(reportFile, branchName: branchName);
      } else {
        // إذا لم يكن هناك عملاء عليهم دين، ارفع ملف فارغ أو رسالة
        final reportFile = await _pdf.generateDailyReport([]);
        await _drive.uploadDailyReport(reportFile, branchName: branchName);
      }
    } finally {
      _setLoading(false);
    }
  }

  // Flag to prevent concurrent syncs
  bool _isSyncing = false;

  // مزامنة الديون عبر Google Drive
  Future<void> syncDebts() async {
    if (!_isDriveSupported) {
      throw Exception('ميزة Google Drive غير مدعومة على هذا النظام');
    }
    
    // 1. Re-entrancy Guard
    if (_isSyncing) {
      print('SYNC: Sync already in progress, ignoring request.');
      return;
    }

    // 2. Connectivity Check
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isEmpty || result[0].rawAddress.isEmpty) {
        throw Exception('لا يوجد اتصال بالإنترنت. يرجى التحقق من الشبكة.');
      }
    } catch (_) {
      throw Exception('لا يوجد اتصال بالإنترنت. يرجى التحقق من الشبكة.');
    }

    _isSyncing = true;
    _setLoading(true);
    try {
      // 3. Ensure signed in
      final signed = await _drive.isSignedIn();
      if (!signed) {
        await _drive.signIn();
      }

      // 4. Delegate to DriveService strict logic
      print('SYNC: Starting robust sync via DriveService...');
      final result = await _drive.performFullSync();
      
      if (result['success'] == false) {
        throw Exception('Sync failed: ${result['error']}');
      }

      print('SYNC: Completed successfully. Uploaded: ${result['uploaded_count']}, Downloaded: ${result['downloaded_count']}');

      // 5. Refresh local state
      await _loadCustomers();
      if (_selectedCustomer != null) {
        await loadCustomerTransactions(_selectedCustomer!.id!);
      }
    } catch (e) {
      print('SYNC ERROR: $e');
      rethrow;
    } finally {
      _setLoading(false);
      _isSyncing = false;
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
      final audioPaths = await _db.getAllAudioNotePaths();

      // 2) إنشاء مجلد مؤقت ونسخ قاعدة البيانات بأمان
      onProgress?.call(0.15);
      final tempDir = await getTemporaryDirectory();
      final backupRoot = Directory('${tempDir.path}/backup_${DateTime.now().millisecondsSinceEpoch}');
      if (!await backupRoot.exists()) {
        await backupRoot.create(recursive: true);
      }
      // 🔒 نسخ احتياطي آمن مع WAL checkpoint + فحص سلامة
      final dbCopy = await _db.createSafeBackup('${backupRoot.path}/debt_book.db');

      final audioDir = Directory('${backupRoot.path}/audio');
      await audioDir.create(recursive: true);
      
      int copiedAudioFiles = 0;
      for (final p in audioPaths) {
        try {
          final f = File(p);
          File? sourceFile = f;
          if (!await f.exists()) {
            // البحث عن الملف في مجلدات أخرى محتملة
            final fileName = p.split(Platform.pathSeparator).last;
            
            // البحث في مجلد قاعدة البيانات الحالي أولاً
            final supportDir = await getApplicationSupportDirectory();
            final dbAudioDir = Directory('${supportDir.path}/audio_notes');
            final currentUserFile = File('${dbAudioDir.path}/$fileName');
            if (await currentUserFile.exists()) {
              sourceFile = currentUserFile;
            } else {
              // البحث في مجلد المستندات العام
              final publicDocs = Directory('${Platform.environment['PUBLIC'] ?? ''}\\Documents');
              if (await publicDocs.exists()) {
                final publicFile = File('${publicDocs.path}\\$fileName');
                if (await publicFile.exists()) {
                  sourceFile = publicFile;
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
            final sourceSize = await sourceFile.length();
            
            if (sourceSize > 0) {
              await sourceFile.copy(targetPath);
              final copiedFile = File(targetPath);
              final copiedSize = await copiedFile.length();
              if (copiedSize == sourceSize) {
                copiedAudioFiles++;
              }
            }
          }
        } catch (e) {
          // تجاهل أخطاء نسخ الملفات الصوتية
        }
      }
      
      // نسخ إضافي للملفات الصوتية من مجلد قاعدة البيانات الحالي
      if (copiedAudioFiles == 0) {
        try {
          final supportDir = await getApplicationSupportDirectory();
          final currentAudioDir = Directory('${supportDir.path}/audio_notes');
          if (await currentAudioDir.exists()) {
            final currentAudioFiles = await currentAudioDir.list().toList();
            for (final file in currentAudioFiles) {
              if (file is File) {
                final fileName = file.path.split(Platform.pathSeparator).last;
                final targetPath = '${audioDir.path}/$fileName';
                if (!await File(targetPath).exists()) {
                  await file.copy(targetPath);
                  copiedAudioFiles++;
                }
              }
            }
          }
        } catch (e) {
          // تجاهل الأخطاء
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
              }
            } catch (e) {
              // تجاهل الأخطاء
            }
          }
        } catch (e) {
          // تجاهل الأخطاء
        }
      }

      // 3) إنشاء ملف zip باسم التاريخ مع اسم الفرع
      onProgress?.call(0.45);
      final now = DateTime.now();
      final settings = await SettingsManager.getAppSettings();
      final branchName = settings.branchName;
      final zipName = '${branchName}_${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}.zip';
      final zipFile = File('${tempDir.path}/$zipName');
      final encoder = ZipFileEncoder();
      encoder.create(zipFile.path);
      encoder.addFile(dbCopy);
      
      if (await audioDir.exists()) {
        final audioFiles = await audioDir.list().toList();
        if (audioFiles.isNotEmpty) {
          encoder.addDirectory(audioDir);
        }
      }
      encoder.close();

      // 4) الرفع وسياسة الاحتفاظ
      onProgress?.call(0.75);
      await _drive.uploadBackupZipAndRetain(zipFile: zipFile, progress: (p) {
        onProgress?.call(0.75 + 0.15 * p.clamp(0.0, 1.0));
      });

      // 5) إرسال النسخة الاحتياطية إلى Telegram
      onProgress?.call(0.90);
      try {
        final telegramService = TelegramBackupService();
        await telegramService.loadSettings();
        if (telegramService.isConfigured) {
          final caption = '📦 نسخة احتياطية - $branchName - ${now.year}/${now.month}/${now.day} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
          await telegramService.sendDocument(file: zipFile, caption: caption);
          
          // --- إرسال سجل الديون PDF ---
          try {
            final allCustomers = await _db.getAllCustomers();
            final customersWithDebt = allCustomers.where((c) => (c.currentTotalDebt ?? 0) > 0).toList();
            final debtRegisterFile = await _db.generateMonthlyDebtsPdf(customersWithDebt, now.year, now.month);
            await telegramService.sendDocument(
              file: debtRegisterFile, 
              caption: '📅 سجل الديون - $branchName - ${now.year}/${now.month}/${now.day}'
            );
          } catch (e) {
            print('Error sending Debt Register: $e');
          }

          // --- إرسال كشوفات الحسابات PDF ---
          try {
            final allCustomers = await _db.getAllCustomers();
            final statementsBytes = await _pdf.generateAllCustomersAccountStatements(
              customers: allCustomers,
              getCustomerTransactions: (id) async {
                final transactions = await _db.getCustomerTransactions(id);
                return transactions.map<AccountStatementItem>((t) {
                  final item = AccountStatementItem(
                    date: t.transactionDate,
                    type: 'transaction',
                    description: t.transactionType == 'manual_debt' ? 'إضافة دين' : 'تسديد دين',
                    amount: t.amountChanged,
                    transaction: t,
                  );
                  item.balanceBefore = t.balanceBeforeTransaction ?? 0.0;
                  item.balanceAfter = t.newBalanceAfterTransaction ?? 0.0;
                  return item;
                }).toList();
              },
            );
            final tempDir = await getTemporaryDirectory();
            final statementsFile = File('${tempDir.path}/all_account_statements.pdf');
            await statementsFile.writeAsBytes(statementsBytes);
            await telegramService.sendDocument(
              file: statementsFile, 
              caption: '📑 كشوفات الحسابات - $branchName - ${now.year}/${now.month}/${now.day}'
            );
          } catch (e) {
            print('Error sending Account Statements: $e');
          }
        }
      } catch (e) {
        // لا نوقف العملية إذا فشل إرسال Telegram
        print('Error sending Telegram backup: $e');
      }

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
      }
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

}
