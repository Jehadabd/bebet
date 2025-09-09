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
    _customers = await _db.getAllCustomers();
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
      final zipName = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.zip';
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
