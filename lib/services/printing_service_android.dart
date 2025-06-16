import 'dart:async';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_esc_pos_network/flutter_esc_pos_network.dart';

class PrintingService {
  final SettingsManager _settingsManager = SettingsManager();

  // Helper method to request Bluetooth permissions
  Future<bool> _requestBluetoothPermissions() async {
    // Request Bluetooth and Bluetooth connect permissions
    var bluetoothPermission = await Permission.bluetooth.request();
    var bluetoothConnectPermission = await Permission.bluetoothConnect.request();
    var bluetoothScanPermission = await Permission.bluetoothScan.request();

    return bluetoothPermission.isGranted &&
        bluetoothConnectPermission.isGranted &&
        bluetoothScanPermission.isGranted;
  }

  // Method to get the default printer from settings
  Future<PrinterDevice?> getDefaultPrinter() async {
    return await _settingsManager.getDefaultPrinter();
  }

  // --- Wi-Fi/LAN Printers ---
  Future<void> printWithWifiPrinter(String ipAddress, List<int> commands, {int port = 9100}) async {
    final printer = PrinterNetworkManager(ipAddress, port: port);
    final PosPrintResult res = await printer.connect();

    if (res == PosPrintResult.success) {
      await printer.printTicket(commands);
      printer.disconnect();
    } else {
      print('Error connecting to Wi-Fi printer: $res');
      // TODO: Handle connection error
    }
  }

  // --- Bluetooth Printers ---
  Future<List<PrinterDevice>> findBluetoothPrinters() async {
    if (!await _requestBluetoothPermissions()) {
      return [];
    }

    if (await PrintBluetoothThermal.bluetoothEnabled == false) {
      print('Bluetooth is off. Please turn on Bluetooth.');
      return [];
    }

    try {
      final List<BluetoothInfo> listResult = await PrintBluetoothThermal.pairedBluetooths;
      return listResult.where((b) => b.macAdress != null && b.macAdress.isNotEmpty).map((b) => PrinterDevice(
        name: b.name.isNotEmpty ? b.name : 'Unknown Device',
        address: b.macAdress!,
        connectionType: PrinterConnectionType.bluetooth,
      )).toList();
    } catch (e) {
      print('Error finding Bluetooth printers: $e');
      // Optionally, you could throw a custom exception or log to a crash reporting service
      return [];
    }
  }

  Future<void> printWithBluetoothPrinter(String macAddress, List<int> commands) async {
    if (!await _requestBluetoothPermissions()) {
      print('Cannot print: Bluetooth permissions not granted.');
      return;
    }

    if (await PrintBluetoothThermal.bluetoothEnabled == false) {
      print('Cannot print: Bluetooth is off. Please turn on Bluetooth.');
      return;
    }

    final bool connectResult = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);

    if (connectResult) {
      await PrintBluetoothThermal.writeBytes(commands);
      await PrintBluetoothThermal.disconnect;
    } else {
      print('Error connecting to Bluetooth printer: $macAddress');
    }
  }

  Future<void> printData(Uint8List dataToPrint, {List<int>? escPosCommands, PrinterDevice? printerDevice}) async {
    final defaultPrinter = printerDevice ?? await _settingsManager.getDefaultPrinter();
    if (defaultPrinter == null) {
      print('No default printer set.');
      return;
    }

    switch (defaultPrinter.connectionType) {
      case PrinterConnectionType.wifi:
        if (escPosCommands != null) {
          await printWithWifiPrinter(defaultPrinter.address, escPosCommands, port: defaultPrinter.port ?? 9100);
        } else {
          print('ESC/POS commands are required for Wi-Fi printer.');
        }
        break;
      case PrinterConnectionType.bluetooth:
        if (escPosCommands != null) {
          await printWithBluetoothPrinter(defaultPrinter.address, escPosCommands);
        } else {
          print('ESC/POS commands are required for Bluetooth printer.');
        }
        break;
      default:
        print('Unsupported printer type for Android.');
        break;
    }
  }
} 