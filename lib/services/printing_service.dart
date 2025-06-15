import 'dart:async'; // For Completer
import 'dart:typed_data';
import 'dart:ffi'; // Core FFI types
import 'package:ffi/ffi.dart'; // FFI utility functions and extension methods
import 'package:pdf/pdf.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart'; // Changed to esc_pos_utils_plus
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart'; // Keep for Bluetooth
import 'package:debt_book/models/printer_device.dart';
import 'package:debt_book/services/settings_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_esc_pos_network/flutter_esc_pos_network.dart'; // New import for Wi-Fi/LAN printing
import 'package:win32/win32.dart'; // Import for Windows API calls

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
  Future<void> printWithWifiPrinter(String ipAddress, List<int> commands) async {
    final printer = PrinterNetworkManager(ipAddress, port: 9100);
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

    final List<BluetoothInfo> listResult = await PrintBluetoothThermal.pairedBluetooths;
    return listResult.map((b) => PrinterDevice(
      name: b.name.isNotEmpty ? b.name : 'Unknown Device',
      address: b.macAdress,
      connectionType: PrinterConnectionType.bluetooth,
    )).toList();
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
      case PrinterConnectionType.system:
      case PrinterConnectionType.usb:
        try {
          final printerName = defaultPrinter.name.toNativeUtf16();
          final hPrinter = calloc<HANDLE>();

          if (OpenPrinter(printerName, hPrinter, nullptr) != 0) {
            final docInfo = calloc<DOC_INFO_1>()
              ..ref.pDocName = 'Invoice'.toNativeUtf16()
              ..ref.pOutputFile = nullptr
              ..ref.pDatatype = 'RAW'.toNativeUtf16();

            final dwJob = StartDocPrinter(hPrinter.value, 1, docInfo);
            if (dwJob > 0) {
              final pBytesWritten = calloc<DWORD>();
              final pBytes = calloc<BYTE>(dataToPrint.length);
              for (var i = 0; i < dataToPrint.length; i++) {
                pBytes[i] = dataToPrint[i];
              }

              if (WritePrinter(hPrinter.value, pBytes, dataToPrint.length, pBytesWritten) != 0) {
                EndDocPrinter(hPrinter.value);
                print('Successfully printed to system printer: ${defaultPrinter.name}');
              } else {
                print('Error writing to printer: ${GetLastError()}');
              }
              free(pBytes);
              free(pBytesWritten);
            } else {
              print('Error starting document on printer: ${GetLastError()}');
            }
            ClosePrinter(hPrinter.value);
            free(docInfo.ref.pDocName);
            free(docInfo.ref.pDatatype);
            free(docInfo);
          } else {
            print('Error opening printer: ${GetLastError()}');
          }
          free(printerName);
          free(hPrinter);
        } catch (e) {
          print('Exception during system printing: $e');
        }
        break;
      case PrinterConnectionType.wifi:
        if (escPosCommands != null) {
          await printWithWifiPrinter(defaultPrinter.address, escPosCommands);
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
    }
  }

  // --- System Printers (Windows) ---
  Future<List<PrinterDevice>> findSystemPrinters() async {
    final List<PrinterDevice> printers = [];
    Pointer<DWORD> pcbNeeded = calloc<DWORD>();
    Pointer<DWORD> pcReturned = calloc<DWORD>();
    Pointer<PRINTER_INFO_4> pPrinterEnum = nullptr;

    try {
      // First call to get the size of the buffer needed
      EnumPrinters(
        PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS,
        nullptr,
        4, // Level 4 for PRINTER_INFO_4
        nullptr,
        0,
        pcbNeeded,
        pcReturned,
      );

      if (pcbNeeded.value > 0) {
        // Allocate buffer with the required size
        pPrinterEnum = calloc<PRINTER_INFO_4>(pcbNeeded.value ~/ sizeOf<PRINTER_INFO_4>());

        // Second call to get the actual printer data
        if (EnumPrinters(
          PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS,
          nullptr,
          4,
          pPrinterEnum.cast(),
          pcbNeeded.value,
          pcbNeeded,
          pcReturned,
        ) != 0) {
          for (int i = 0; i < pcReturned.value; i++) {
            final printerInfo = pPrinterEnum.elementAt(i).ref;
            final name = printerInfo.pPrinterName.toDartString();
            // For system printers, the address might not be directly available or meaningful
            // We can use the name as the identifier for now.
            printers.add(PrinterDevice(
              name: name,
              address: name, // Using name as address for system printers
              connectionType: PrinterConnectionType.system,
            ));
          }
        }
      }
    } catch (e) {
      print('Error enumerating system printers: $e');
    } finally {
      free(pcbNeeded);
      free(pcReturned);
      if (pPrinterEnum != nullptr) {
        free(pPrinterEnum);
      }
    }
    return printers;
  }
} 