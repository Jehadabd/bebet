// providers/app_provider.dart
import 'package:flutter/foundation.dart';
import '../models/customer.dart';
import '../models/transaction.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';
import '../services/drive_service.dart';
import '../services/pdf_service.dart';

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

  // Getters
  List<Customer> get customers => _filteredCustomers;
  Customer? get selectedCustomer => _selectedCustomer;
  List<DebtTransaction> get customerTransactions => _customerTransactions;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  bool get isDriveSupported => _isDriveSupported;
  bool get isDriveSignedInSync => _isDriveSignedInSync;

  // Initialize the app
  Future<void> initialize() async {
    _setLoading(true);
    try {
      _isDriveSupported = _drive.isSupported;
      if (_isDriveSupported) {
        _isDriveSignedInSync = await _drive.isSignedIn();
      }
      await _loadCustomers();
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
    final customer = _customers.firstWhere((c) => c.id == transaction.customerId);
    final updatedCustomer = customer.copyWith(
      currentTotalDebt: transaction.newBalanceAfterTransaction,
      lastModifiedAt: DateTime.now(),
    );
    await updateCustomer(updatedCustomer);
    
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

  // Daily report generation and upload
  Future<void> generateAndUploadDailyReport() async {
    if (!_isDriveSupported) {
      throw Exception('ميزة التقارير غير مدعومة على هذا النظام');
    }
    _setLoading(true);
    try {
      final modifiedCustomers = await _db.getCustomersModifiedToday();
      if (modifiedCustomers.isNotEmpty) {
        final reportFile = await _pdf.generateDailyReport(modifiedCustomers);
        await _drive.uploadDailyReport(reportFile);
      }
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
} 