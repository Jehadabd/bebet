// screens/printer_settings_screen.dart
import 'package:flutter/material.dart';
import 'dart:async'; // Required for StreamSubscription
import 'package:alnaser/models/printer_device.dart';
import 'package:alnaser/services/printing_service.dart';
import 'package:alnaser/services/settings_manager.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:flutter_nsd/flutter_nsd.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:alnaser/services/printing_service_platform_io.dart'; // Import the platform-specific service getter

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  late final PrintingService _printingService; // Changed to late final
  final SettingsManager _settingsManager = SettingsManager();
  final FlutterNsd _flutterNsd = FlutterNsd();
  StreamSubscription<NsdServiceInfo>? _nsdSubscription;

  PrinterDevice? _defaultPrinter;
  PrinterConnectionType _selectedConnectionType = PrinterConnectionType.system;
  List<PrinterDevice> _discoveredPrinters = [];
  bool _isLoading = false;
  String _wifiPrinterIp = ''; // For Wi-Fi printer input

  @override
  void initState() {
    super.initState();
    _printingService = getPlatformPrintingService(); // Initialize using the getter
    _loadDefaultPrinter();
    _initNsdListener();
  }

  void _initNsdListener() {
    try {
      _nsdSubscription = _flutterNsd.stream.listen((nsdServiceInfo) {
        if (mounted && _selectedConnectionType == PrinterConnectionType.wifi) {
          if (nsdServiceInfo.hostname != null && nsdServiceInfo.hostname!.isNotEmpty && nsdServiceInfo.port != null) {
            // Only add if it's a new printer or an update to an existing one
            final newPrinter = PrinterDevice(
              name: nsdServiceInfo.name ?? 'Unknown Wi-Fi Printer',
              address: nsdServiceInfo.hostname!,
              connectionType: PrinterConnectionType.wifi,
              port: nsdServiceInfo.port,
            );
            setState(() {
              // Check if printer with this IP already exists to avoid duplicates
              if (!_discoveredPrinters.any((p) => p.address == newPrinter.address)) {
                _discoveredPrinters.add(newPrinter);
              } else {
                // Update existing printer details if needed
                final index = _discoveredPrinters.indexWhere((p) => p.address == newPrinter.address);
                if (index != -1) {
                  _discoveredPrinters[index] = newPrinter;
                }
              }
              _discoveredPrinters.sort((a, b) => a.name.compareTo(b.name));
            });
          }
        }
      }, onError: (e) {
        print('Error during NSD discovery stream: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ في اكتشاف طابعات الواي فاي: $e')),
          );
        }
      });
    } catch (e) {
      print('Error initializing NSD listener: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تهيئة خدمة اكتشاف الواي فاي: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nsdSubscription?.cancel();
    _flutterNsd.stopDiscovery();
    super.dispose();
  }

  Future<void> _loadDefaultPrinter() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
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
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
    _discoverPrinters(); // Discover printers based on the loaded type
  }

  Future<bool> _requestBluetoothPermissions() async {
    // اطلب أذونات البلوتوث والموقع
    final bluetoothStatus = await Permission.bluetooth.request();
    final locationStatus = await Permission.locationWhenInUse.request();
    if (bluetoothStatus.isGranted && locationStatus.isGranted) {
      return true;
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يجب منح أذونات البلوتوث والموقع لاكتشاف الطابعات.')),
        );
      }
      return false;
    }
  }

  Future<void> _discoverPrinters() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _discoveredPrinters.clear();
      });
    }

    try {
      if (_selectedConnectionType == PrinterConnectionType.system || _selectedConnectionType == PrinterConnectionType.usb) {
        final printers = await _printingService.findSystemPrinters();
        if (mounted) {
          setState(() {
            _discoveredPrinters = printers;
          });
        }
      } else if (_selectedConnectionType == PrinterConnectionType.bluetooth) {
        if (!Platform.isAndroid) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('اكتشاف طابعات البلوتوث متاح فقط على أندرويد.')),
          );
          return;
        }
        // اطلب الأذونات فقط على أندرويد
        final hasPermissions = await _requestBluetoothPermissions();
        if (!hasPermissions) {
          if (mounted) {
            setState(() {
              _discoveredPrinters = [];
              _isLoading = false;
            });
          }
          return;
        }
        // تأكد من تشغيل البلوتوث
        if (await PrintBluetoothThermal.bluetoothEnabled == false) {
          print('Bluetooth is off. Please turn on Bluetooth.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('الرجاء تشغيل البلوتوث لاكتشاف الطابعات.')),
            );
            setState(() {
              _discoveredPrinters = [];
              _isLoading = false;
            });
          }
          return;
        }
        try {
          final printers = await _printingService.findBluetoothPrinters();
          if (mounted) {
            setState(() {
              _discoveredPrinters = printers;
            });
          }
        } catch (e) {
          print('Error discovering Bluetooth printers: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('خطأ في اكتشاف طابعات البلوتوث: $e')),
            );
          }
        }
      } else if (_selectedConnectionType == PrinterConnectionType.wifi) {
        // يمكن دعم الواي فاي على المنصات التي تدعمه فقط
        // إذا كان هناك كود خاص بمنصة معينة، أضف شرط Platform هنا أيضًا
        try {
          await _flutterNsd.discoverServices('_printer._tcp'.padRight(16, '.'));
          // The listener will populate _discoveredPrinters
        } catch (e) {
          print('Error starting Wi-Fi discovery: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('خطأ في بدء اكتشاف طابعات الواي فاي: $e')),
            );
          }
        }
      }
    } catch (e) {
      print('Error discovering printers: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء اكتشاف الطابعات: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _selectDefaultPrinter(PrinterDevice printer) async {
    try {
      await _settingsManager.saveDefaultPrinter(printer);
      if (mounted) {
        setState(() {
          _defaultPrinter = printer;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تعيين ${printer.name} كطابعة افتراضية.')),
      );
    } catch (e) {
      print('Error setting default printer: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تعيين الطابعة الافتراضية: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // تحديد أنواع الاتصال المتاحة حسب النظام
    List<PrinterConnectionType> availableTypes;
    if (Platform.isWindows) {
      availableTypes = [PrinterConnectionType.system, PrinterConnectionType.usb];
    } else if (Platform.isAndroid) {
      availableTypes = PrinterConnectionType.values;
    } else {
      // لأنظمة أخرى (مثلاً macOS أو Linux)، يمكنك تخصيص الخيارات لاحقاً
      availableTypes = [PrinterConnectionType.system];
    }
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
              value: availableTypes.contains(_selectedConnectionType) ? _selectedConnectionType : availableTypes.first,
              decoration: const InputDecoration(
                labelText: 'نوع الاتصال',
                border: OutlineInputBorder(),
              ),
              items: availableTypes.map((type) {
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
                  if (mounted) {
                    setState(() {
                      _selectedConnectionType = type;
                      _discoveredPrinters.clear(); // Clear old list
                      _wifiPrinterIp = ''; // Clear Wi-Fi input
                    });
                  }
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
        return _buildWifiPrinterList();
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

  Widget _buildWifiPrinterList() {
    if (_discoveredPrinters.isEmpty && !_isLoading) {
      return const Center(child: Text('جاري البحث عن طابعات الواي فاي...'));
    }
    return ListView.builder(
      itemCount: _discoveredPrinters.length,
      itemBuilder: (context, index) {
        final printer = _discoveredPrinters[index];
        return ListTile(
          title: Text(printer.name),
          subtitle: Text('${printer.address}:${printer.port}'),
          trailing: _defaultPrinter?.address == printer.address && _defaultPrinter?.connectionType == printer.connectionType && _defaultPrinter?.port == printer.port
              ? const Icon(Icons.check_circle, color: Colors.green)
              : null,
          onTap: () => _selectDefaultPrinter(printer),
        );
      },
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