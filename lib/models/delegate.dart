class Delegate {
  int? id;
  int supplierId;
  String name;
  String? phoneNumber;
  String? notes;
  DateTime createdAt;

  Delegate({
    this.id,
    required this.supplierId,
    required this.name,
    this.phoneNumber,
    this.notes,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'supplier_id': supplierId,
      'name': name,
      'phone_number': phoneNumber,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Delegate.fromMap(Map<String, dynamic> map) {
    return Delegate(
      id: map['id'],
      supplierId: map['supplier_id'],
      name: map['name'],
      phoneNumber: map['phone_number'],
      notes: map['notes'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}
