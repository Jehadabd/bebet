// lib/services/sync/sync_validation.dart
// خدمة التحقق من صحة البيانات للمزامنة

/// نتيجة التحقق
class ValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  
  ValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });
  
  factory ValidationResult.valid() => ValidationResult(isValid: true);
  
  factory ValidationResult.invalid(String error) => ValidationResult(
    isValid: false,
    errors: [error],
  );
}

/// خدمة التحقق من صحة البيانات
class SyncValidation {
  
  static ValidationResult validateCustomerData(Map<String, dynamic> data) {
    final errors = <String>[];
    final warnings = <String>[];
    
    if (!data.containsKey('name') && !data.containsKey('syncUuid')) {
      errors.add('بيانات العميل ناقصة');
    }
    
    final name = data['name']?.toString() ?? '';
    if (name.isEmpty) {
      errors.add('اسم العميل فارغ');
    } else if (name.length > 200) {
      errors.add('اسم العميل طويل جداً');
    } else if (_containsSqlInjection(name)) {
      errors.add('اسم العميل يحتوي على أحرف غير مسموحة');
    }
    
    final balance = data['currentTotalDebt'] ?? data['current_total_debt'];
    if (balance != null) {
      final balanceNum = _parseNumber(balance);
      if (balanceNum == null) {
        errors.add('قيمة الرصيد غير صالحة');
      } else if (balanceNum.abs() > 1000000000000) {
        errors.add('قيمة الرصيد غير منطقية');
      }
    }

    final syncUuid = data['syncUuid'] ?? data['sync_uuid'];
    if (syncUuid != null && !_isValidUuid(syncUuid.toString())) {
      errors.add('معرف المزامنة غير صالح');
    }
    
    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  static ValidationResult validateTransactionData(Map<String, dynamic> data) {
    final errors = <String>[];
    final warnings = <String>[];
    
    final customerSyncUuid = data['customerSyncUuid'] ?? data['customer_sync_uuid'];
    if (customerSyncUuid == null || customerSyncUuid.toString().isEmpty) {
      errors.add('المعاملة بدون معرف عميل');
    }
    
    final amount = data['amountChanged'] ?? data['amount_changed'];
    if (amount == null) {
      errors.add('المعاملة بدون مبلغ');
    } else {
      final amountNum = _parseNumber(amount);
      if (amountNum == null) {
        errors.add('قيمة المبلغ غير صالحة');
      } else if (amountNum.abs() > 1000000000000) {
        errors.add('قيمة المبلغ غير منطقية');
      }
    }
    
    final dateStr = data['transactionDate'] ?? data['transaction_date'];
    if (dateStr == null || dateStr.toString().isEmpty) {
      errors.add('المعاملة بدون تاريخ');
    } else {
      final date = DateTime.tryParse(dateStr.toString());
      if (date == null) {
        errors.add('تاريخ المعاملة غير صالح');
      } else if (date.isBefore(DateTime(2000))) {
        errors.add('تاريخ المعاملة قديم جداً');
      }
    }
    
    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }
  
  static ValidationResult validateFirebaseCustomerData(Map<String, dynamic> data) {
    return validateCustomerData(data);
  }
  
  static ValidationResult validateFirebaseTransactionData(Map<String, dynamic> data) {
    return validateTransactionData(data);
  }
  
  static bool _containsSqlInjection(String input) {
    if (input.contains("';--") || input.contains('";--')) return true;
    final dropPattern = RegExp(r';\s*(DROP|DELETE|UPDATE|INSERT)', caseSensitive: false);
    final unionPattern = RegExp(r'UNION\s+SELECT', caseSensitive: false);
    return dropPattern.hasMatch(input) || unionPattern.hasMatch(input);
  }
  
  static bool _isValidUuid(String uuid) {
    if (uuid.length != 36) return false;
    final parts = uuid.split('-');
    if (parts.length != 5) return false;
    if (parts[0].length != 8) return false;
    if (parts[1].length != 4) return false;
    if (parts[2].length != 4) return false;
    if (parts[3].length != 4) return false;
    if (parts[4].length != 12) return false;
    final hexPattern = RegExp(r'^[0-9a-fA-F]+$');
    return parts.every((part) => hexPattern.hasMatch(part));
  }
  
  static double? _parseNumber(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
  
  static String sanitizeString(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('<', '')
        .replaceAll('>', '')
        .trim();
  }
  
  static Map<String, dynamic> sanitizeMap(Map<String, dynamic> data) {
    final sanitized = <String, dynamic>{};
    for (final entry in data.entries) {
      if (entry.value is String) {
        sanitized[entry.key] = sanitizeString(entry.value as String);
      } else if (entry.value is Map<String, dynamic>) {
        sanitized[entry.key] = sanitizeMap(entry.value as Map<String, dynamic>);
      } else {
        sanitized[entry.key] = entry.value;
      }
    }
    return sanitized;
  }
}

class SyncRateLimiter {
  final int maxOperationsPerMinute;
  final int maxOperationsPerHour;
  final List<DateTime> _timestamps = [];
  
  SyncRateLimiter({
    this.maxOperationsPerMinute = 60,
    this.maxOperationsPerHour = 500,
  });
  
  bool canProceed() {
    _cleanup();
    final now = DateTime.now();
    final oneMinuteAgo = now.subtract(const Duration(minutes: 1));
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    final opsLastMinute = _timestamps.where((t) => t.isAfter(oneMinuteAgo)).length;
    final opsLastHour = _timestamps.where((t) => t.isAfter(oneHourAgo)).length;
    return opsLastMinute < maxOperationsPerMinute && opsLastHour < maxOperationsPerHour;
  }
  
  void recordOperation() {
    _timestamps.add(DateTime.now());
    _cleanup();
  }
  
  void _cleanup() {
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    _timestamps.removeWhere((t) => t.isBefore(oneHourAgo));
  }
  
  Duration? getWaitTime() {
    if (canProceed()) return null;
    return const Duration(seconds: 1);
  }
  
  void reset() => _timestamps.clear();
  
  int get operationsLastMinute {
    _cleanup();
    final oneMinuteAgo = DateTime.now().subtract(const Duration(minutes: 1));
    return _timestamps.where((t) => t.isAfter(oneMinuteAgo)).length;
  }
  
  int get operationsLastHour {
    _cleanup();
    final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));
    return _timestamps.where((t) => t.isAfter(oneHourAgo)).length;
  }
}
