import 'package:sqflite/sqflite.dart';

class Customer {
  final int? id;
  final String name;
  final String? phone;
  final double currentTotalDebt;
  final String? generalNote;
  final DateTime createdAt;
  final DateTime lastModifiedAt;

  Customer({
    this.id,
    required this.name,
    this.phone,
    this.currentTotalDebt = 0.0,
    this.generalNote,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        lastModifiedAt = lastModifiedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'current_total_debt': currentTotalDebt,
      'general_note': generalNote,
      'created_at': createdAt.toIso8601String(),
      'last_modified_at': lastModifiedAt.toIso8601String(),
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as int,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      currentTotalDebt: map['current_total_debt'] as double,
      generalNote: map['general_note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastModifiedAt: DateTime.parse(map['last_modified_at'] as String),
    );
  }

  Customer copyWith({
    int? id,
    String? name,
    String? phone,
    double? currentTotalDebt,
    String? generalNote,
    DateTime? createdAt,
    DateTime? lastModifiedAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      currentTotalDebt: currentTotalDebt ?? this.currentTotalDebt,
      generalNote: generalNote ?? this.generalNote,
      createdAt: createdAt ?? this.createdAt,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
    );
  }
} 