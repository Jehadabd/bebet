enum PrinterConnectionType { system, wifi, bluetooth, usb }

class PrinterDevice {
  final String name; // اسم الطابعة (e.g., "HP LaserJet", "Kitchen Printer")
  final String address; // العنوان (اسم نظام التشغيل, IP, MAC address)
  final PrinterConnectionType connectionType;
  final String? productId;
  final String? vendorId;

  PrinterDevice({
    required this.name,
    required this.address,
    required this.connectionType,
    this.productId,
    this.vendorId,
  });

  // دوال لتحويل النموذج من وإلى JSON لحفظه بسهولة
  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'connectionType': connectionType.name,
    'productId': productId,
    'vendorId': vendorId,
  };

  factory PrinterDevice.fromJson(Map<String, dynamic> json) => PrinterDevice(
    name: json['name'],
    address: json['address'],
    connectionType: PrinterConnectionType.values.byName(json['connectionType']),
    productId: json['productId'],
    vendorId: json['vendorId'],
  );
} 