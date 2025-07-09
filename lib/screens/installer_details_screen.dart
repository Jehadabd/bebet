// screens/installer_details_screen.dart
import 'package:flutter/material.dart';
// import 'package:provider/provider.dart'; // Not directly used in this snippet's logic, but good practice for full app context
// import '../providers/app_provider.dart'; // Not directly used here
import '../models/installer.dart';
import '../models/invoice.dart';
import '../services/database_service.dart';
import 'package:intl/intl.dart'; // For currency formatting
// import 'create_invoice_screen.dart'; // If navigation to invoice details is enabled later

class InstallerDetailsScreen extends StatefulWidget {
  final Installer installer;

  const InstallerDetailsScreen({
    super.key,
    required this.installer,
  });

  @override
  State<InstallerDetailsScreen> createState() => _InstallerDetailsScreenState();
}

class _InstallerDetailsScreenState extends State<InstallerDetailsScreen> {
  final DatabaseService _db = DatabaseService();
  List<Invoice> _invoices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() => _isLoading = true);
    try {
      final invoices = await _db.getInvoicesByInstaller(widget.installer.name);
      setState(() {
        _invoices = invoices;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل الفواتير: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // Helper to format currency consistently
  String formatCurrency(num value) {
    return NumberFormat('0.00', 'en_US')
        .format(value); // Always two decimal places
  }

  @override
  Widget build(BuildContext context) {
    // Define the consistent theme colors for the screen
    final Color primaryColor = const Color(0xFF3F51B5); // Indigo 700
    final Color accentColor =
        const Color(0xFF8C9EFF); // Light Indigo Accent (Indigo A200)
    final Color textColor =
        const Color(0xFF212121); // Dark grey for general text
    final Color lightBackgroundColor =
        const Color(0xFFF8F8F8); // Very light grey for text field fill
    final Color successColor = Colors.green[600]!; // Green for success messages
    final Color errorColor = Colors.red[700]!; // Red for error messages

    return Theme(
      data: ThemeData(
        // Define color scheme for light theme
        colorScheme: ColorScheme.light(
          primary: primaryColor,
          onPrimary: Colors.white, // Text/icons on primary color
          secondary: accentColor,
          onSecondary: Colors.black, // Text/icons on secondary color
          surface: Colors.white, // Card/sheet background
          onSurface: textColor, // Text/icons on surface
          background: Colors.white, // Scaffold background
          onBackground: textColor, // Text/icons on background
          error: errorColor,
          onError: Colors.white, // Text/icons on error color
          tertiary: successColor, // Custom color for success, used in SnackBars
        ),
        // Define typography (font family and text styles)
        fontFamily: 'Roboto', // Modern, clean font
        textTheme: TextTheme(
          titleLarge: TextStyle(
              fontSize: 22.0,
              fontWeight: FontWeight.bold,
              color: Colors.white), // AppBar title
          titleMedium: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w600,
              color: textColor), // Section titles
          bodyLarge:
              TextStyle(fontSize: 16.0, color: textColor), // General body text
          bodyMedium:
              TextStyle(fontSize: 14.0, color: textColor), // Smaller body text
          labelLarge: TextStyle(
              fontSize: 16.0,
              color: Colors.white,
              fontWeight: FontWeight.w600), // Button text
          labelMedium: TextStyle(
              fontSize: 14.0, color: Colors.grey[600]), // Input field labels
          bodySmall: TextStyle(
              fontSize: 12.0, color: Colors.grey[700]), // Hint text / captions
        ),
        // Define AppBar theme
        appBarTheme: AppBarTheme(
          backgroundColor: primaryColor, // AppBar background color
          foregroundColor: Colors.white, // AppBar text/icon color
          centerTitle: true, // Center title
          elevation: 4, // Shadow elevation
          titleTextStyle: TextStyle(
            // Title text style (inherits from TextTheme.titleLarge)
            fontSize: 24.0,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        // Define Card theme
        cardTheme: CardThemeData(
          elevation: 3, // Consistent shadow for cards
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(12.0), // Rounded corners for cards
          ),
          margin: EdgeInsets
              .zero, // Reset default card margin to manage it manually
        ),
        // Define ListTile theme
        listTileTheme: ListTileThemeData(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          tileColor: Colors.transparent, // Default transparent
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        ),
        // Define TextButton theme (if any are used in future updates)
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            textStyle: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w600),
          ),
        ),
        // Define IconButton theme (if any are used in future updates)
        iconTheme: IconThemeData(color: Colors.grey[700], size: 24.0),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.installer.name),
          // The title style is now managed by appBarTheme.titleTextStyle
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0), // Consistent padding
              child: Card(
                // Card theme applied from ThemeData
                child: Padding(
                  padding:
                      const EdgeInsets.all(20.0), // Increased internal padding
                  child: Column(
                    children: [
                      Text(
                        'إجمالي المبلغ المفوتر',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary, // Primary color for heading
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 12), // Increased spacing
                      Text(
                        '${formatCurrency(widget.installer.totalBilledAmount)} دينار عراقي', // Formatted currency
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary, // Primary color for the amount
                              fontWeight: FontWeight.bold, // Make it bold
                              fontSize: 28, // Larger font size for emphasis
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24.0, vertical: 12.0), // Consistent padding
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'الفواتير المرتبطة',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(
                            0xFF3F51B5), // Explicitly set color for indicator
                      ),
                    )
                  : _invoices.isEmpty
                      ? Center(
                          child: Text('لا توجد فواتير مرتبطة',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(color: Colors.grey[600])),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: 12.0), // Padding for the list itself
                          itemCount: _invoices.length,
                          itemBuilder: (context, index) {
                            final invoice = _invoices[index];
                            return Card(
                              // Card theme applied from ThemeData
                              margin: const EdgeInsets.only(
                                  bottom: 12.0), // Spacing between cards
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20.0,
                                    vertical:
                                        12.0), // Increased internal padding for ListTile
                                title: Text(
                                  invoice.customerName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      ),
                                ),
                                subtitle: Text(
                                  'التاريخ: ${DateFormat('yyyy/MM/dd').format(invoice.invoiceDate)}\n' // Consistent date format
                                  'المبلغ: ${formatCurrency(invoice.totalAmount)} دينار عراقي', // Formatted currency
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                          color: Colors
                                              .grey[700]), // Themed text style
                                ),
                                trailing: Icon(Icons.receipt_long,
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                    size: 28), // Themed icon
                                onTap: () {
                                  // TODO: Navigate to invoice details - Keep this TODO for now
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'الانتقال لتفاصيل الفاتورة رقم ${invoice.id}'),
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .tertiary),
                                  );
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
