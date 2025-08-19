
class Installer {
  final int? id;
  final String name;
  final double totalBilledAmount;

  Installer({
    this.id,
    required this.name,
    this.totalBilledAmount = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'total_billed_amount': totalBilledAmount,
    };
  }

  factory Installer.fromMap(Map<String, dynamic> map) {
    return Installer(
      id: map['id'] as int?,
      name: map['name'] as String,
      totalBilledAmount: (map['total_billed_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Installer copyWith({
    int? id,
    String? name,
    double? totalBilledAmount,
  }) {
    return Installer(
      id: id ?? this.id,
      name: name ?? this.name,
      totalBilledAmount: totalBilledAmount ?? this.totalBilledAmount,
    );
  }
} 