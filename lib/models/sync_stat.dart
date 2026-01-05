// lib/models/sync_stat.dart
// نموذج بيانات إحصائيات المزامنة

import 'package:flutter/foundation.dart';

/// نوع عملية المزامنة
enum SyncStatType {
  sent,     // تم التسليم (رفعتها أنت وتم تأكيد استلامها)
  received, // تم الاستلام (وصلت من جهاز آخر)
}

/// حالة عملية المزامنة
enum SyncStatStatus {
  success, // ناجحة
  failed,  // فاشلة
}

/// إحصائية مزامنة واحدة
class SyncStat {
  final String transactionId;
  final String customerName;
  final int customerId;
  final DateTime timestamp;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final SyncStatType type;
  final SyncStatStatus status;
  final String? errorMessage; // في حالة الفشل
  final int? retryCount; // عدد المحاولات (للعمليات الفاشلة)

  SyncStat({
    required this.transactionId,
    required this.customerName,
    required this.customerId,
    required this.timestamp,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    required this.type,
    required this.status,
    this.errorMessage,
    this.retryCount,
  });

  /// للطباعة
  String get typeLabel {
    switch (type) {
      case SyncStatType.sent:
        return 'تم التسليم';
      case SyncStatType.received:
        return 'تم الاستلام';
    }
  }

  /// للطباعة
  String get statusLabel {
    switch (status) {
      case SyncStatStatus.success:
        return 'ناجح';
      case SyncStatStatus.failed:
        return 'فاشل';
    }
  }

  /// أيقونة النوع
  String get typeIcon {
    switch (type) {
      case SyncStatType.sent:
        return '📤';
      case SyncStatType.received:
        return '📥';
    }
  }

  /// أيقونة الحالة
  String get statusIcon {
    switch (status) {
      case SyncStatStatus.success:
        return '✅';
      case SyncStatStatus.failed:
        return '❌';
    }
  }

  @override
  String toString() {
    return 'SyncStat{customer: $customerName, type: $typeLabel, status: $statusLabel, amount: $amount, time: $timestamp}';
  }
}

/// إحصائيات ملخصة
class SyncStatsSummary {
  final int totalSuccess;
  final int totalFailed;
  final int sentCount;
  final int receivedCount;
  final DateTime? oldestStat;
  final DateTime? newestStat;

  SyncStatsSummary({
    required this.totalSuccess,
    required this.totalFailed,
    required this.sentCount,
    required this.receivedCount,
    this.oldestStat,
    this.newestStat,
  });

  int get totalOperations => totalSuccess + totalFailed;
  double get successRate => totalOperations > 0
      ? (totalSuccess / totalOperations) * 100
      : 0.0;
}
