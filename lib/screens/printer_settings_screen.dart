import 'package:flutter/material.dart';
import 'package:debt_book/models/printer_device.dart';
import 'package:debt_book/services/printing_service.dart';
import 'package:debt_book/services/settings_manager.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  final PrintingService _printingService = PrintingService();
  final SettingsManager _settingsManager = SettingsManager();

  PrinterDevice? _defaultPrinter;
  PrinterConnectionType _selectedConnectionType = PrinterConnectionType.system;
  List<PrinterDevice> _discoveredPrinters = [];
  bool _isLoading = false;
  String _wifiPrinterIp = ''; // For Wi-Fi printer input

  @override
  void initState() {
    super.initState();
    _loadDefaultPrinter();
  }

  Future<void> _loadDefaultPrinter() async {
    setState(() {
      _isLoading = true;
    });
    _defaultPrinter = await _settingsManager.getDefaultPrinter();
    if (_defaultPrinter != null) {
      _selectedConnectionType = _defaultPrinter!.connectionType;

      // If the default printer is a system/USB printer, try to find it among current system printers
      if (_defaultPrinter!.connectionType == PrinterConnectionType.system ||
          _defaultPrinter!.connectionType == PrinterConnectionType.usb) {
        final systemPrinters = await _printingService.findSystemPrinters();
        final foundPrinter = systemPrinters.firstWhere(
          (p) => p.name == _defaultPrinter!.name && p.address == _defaultPrinter!.address,
          orElse: () => _defaultPrinter!, // If not found, keep the existing default
        );
        _defaultPrinter = foundPrinter;
      }
    }
    setState(() {
      _isLoading = false;
    });
    _discoverPrinters(); // Discover printers based on the loaded type
  }

  Future<void> _discoverPrinters() async {
    setState(() {
      _isLoading = true;
      _discoveredPrinters.clear();
    });

    try {
      if (_selectedConnectionType == PrinterConnectionType.system || _selectedConnectionType == PrinterConnectionType.usb) {
        final printers = await _printingService.findSystemPrinters();
        setState(() {
          _discoveredPrinters = printers;
        });
      } else if (_selectedConnectionType == PrinterConnectionType.bluetooth) {
        // Ensure Bluetooth is enabled before discovering
        if (await PrintBluetoothThermal.bluetoothEnabled == false) {
          print('Bluetooth is off. Please turn on Bluetooth.');
          // TODO: Consider showing a user-friendly message or dialog to enable Bluetooth
          setState(() {
            _discoveredPrinters = [];
          });
          return;
        }

        final printers = await _printingService.findBluetoothPrinters();
        setState(() {
          _discoveredPrinters = printers;
        });
      }
      // Wi-Fi discovery is typically manual input, no active discovery here.
    } catch (e) {
      print('Error discovering printers: $e');
      // TODO: Show user feedback
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDefaultPrinter(PrinterDevice printer) async {
    await _settingsManager.saveDefaultPrinter(printer);
    setState(() {
      _defaultPrinter = printer;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم تعيين ${printer.name} كطابعة افتراضية.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات الطابعة'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<PrinterConnectionType>(
              value: _selectedConnectionType,
              decoration: const InputDecoration(
                labelText: 'نوع الاتصال',
                border: OutlineInputBorder(),
              ),
              items: PrinterConnectionType.values.map((type) {
                String typeText = '';
                switch (type) {
                  case PrinterConnectionType.system:
                    typeText = 'طابعات النظام';
                    break;
                  case PrinterConnectionType.wifi:
                    typeText = 'طابعات الواي فاي';
                    break;
                  case PrinterConnectionType.bluetooth:
                    typeText = 'طابعات البلوتوث';
                    break;
                  case PrinterConnectionType.usb:
                    typeText = 'طابعات USB (حرارية)';
                    break;
                }
                return DropdownMenuItem(
                  value: type,
                  child: Text(typeText),
                );
              }).toList(),
              onChanged: (type) {
                if (type != null) {
                  setState(() {
                    _selectedConnectionType = type;
                    _discoveredPrinters.clear(); // Clear old list
                    _wifiPrinterIp = ''; // Clear Wi-Fi input
                  });
                  _discoverPrinters(); // Re-discover based on new type
                }
              },
            ),
            const SizedBox(height: 20),
            Text(
              _defaultPrinter != null
                  ? 'الطابعة الافتراضية الحالية: ${_defaultPrinter!.name} (${_defaultPrinter!.connectionType.name}) '
                  : 'لم يتم تعيين طابعة افتراضية.',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const Divider(),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              Expanded(
                child: _buildPrinterDiscoverySection(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterDiscoverySection() {
    switch (_selectedConnectionType) {
      case PrinterConnectionType.system:
      case PrinterConnectionType.usb:
        return _buildSystemPrinterList();
      case PrinterConnectionType.wifi:
        return _buildWifiPrinterInput();
      case PrinterConnectionType.bluetooth:
        return _buildBluetoothPrinterList();
    }
  }

  Widget _buildSystemPrinterList() {
    if (_discoveredPrinters.isEmpty && !_isLoading) {
      return const Center(child: Text('لا توجد طابعات نظام متاحة.'));
    }
    return ListView.builder(
      itemCount: _discoveredPrinters.length,
      itemBuilder: (context, index) {
        final printer = _discoveredPrinters[index];
        return ListTile(
          title: Text(printer.name),
          subtitle: Text(printer.address),
          trailing: _defaultPrinter?.address == printer.address && _defaultPrinter?.connectionType == printer.connectionType
              ? const Icon(Icons.check_circle, color: Colors.green)
              : null,
          onTap: () => _selectDefaultPrinter(printer),
        );
      },
    );
  }

  Widget _buildWifiPrinterInput() {
    return Column(
      children: [
        TextFormField(
          decoration: const InputDecoration(
            labelText: 'عنوان IP للطابعة',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) {
            _wifiPrinterIp = value;
          },
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () async {
            if (_wifiPrinterIp.isNotEmpty) {
              final newPrinter = PrinterDevice(
                name: 'Wi-Fi Printer (${_wifiPrinterIp})',
                address: _wifiPrinterIp,
                connectionType: PrinterConnectionType.wifi,
              );
              await _selectDefaultPrinter(newPrinter);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('الرجاء إدخال عنوان IP للطابعة.')),
              );
            }
          },
          child: const Text('تعيين طابعة الواي فاي'),
        ),
      ],
    );
  }

  Widget _buildBluetoothPrinterList() {
    if (_discoveredPrinters.isEmpty && !_isLoading) {
      return const Center(child: Text('جاري البحث عن طابعات البلوتوث...'));
    }
    return ListView.builder(
      itemCount: _discoveredPrinters.length,
      itemBuilder: (context, index) {
        final printer = _discoveredPrinters[index];
        return ListTile(
          title: Text(printer.name),
          subtitle: Text(printer.address),
          trailing: _defaultPrinter?.address == printer.address && _defaultPrinter?.connectionType == printer.connectionType
              ? const Icon(Icons.check_circle, color: Colors.green)
              : null,
          onTap: () => _selectDefaultPrinter(printer),
        );
      },
    );
  }
}