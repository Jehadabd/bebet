// screens/edit_invoices_screen.dart
// screens/edit_invoices_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/invoice.dart';
import 'create_invoice_screen.dart';
import 'package:intl/intl.dart'; // Import for NumberFormat

class EditInvoicesScreen extends StatefulWidget {
  const EditInvoicesScreen({super.key});

  @override
  State<EditInvoicesScreen> createState() => _EditInvoicesScreenState();
}

class _EditInvoicesScreenState extends State<EditInvoicesScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  String _searchName = '';
  String _searchId = '';
  List<Invoice> _filteredInvoices = [];
  List<Invoice> _allInvoices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchInvoices();
    _nameController.addListener(_onNameChanged);
    _idController.addListener(_onIdChanged);
  }

  void _fetchInvoices() async {
    setState(() => _loading = true);
    // Ensure `listen: false` when calling provider methods in initState or async methods
    final provider = Provider.of<AppProvider>(context, listen: false);
    final invoices = await provider.getAllInvoices();
    setState(() {
      _allInvoices = invoices;
      _applyFilters();
      _loading = false;
    });
  }

  void _onNameChanged() {
    setState(() {
      _searchName = _nameController.text.trim();
      _applyFilters();
    });
  }

  void _onIdChanged() {
    setState(() {
      _searchId = _idController.text.trim();
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Invoice> filtered = _allInvoices;
    if (_searchName.isNotEmpty) {
      filtered = filtered
          .where((inv) => inv.customerName
              .toLowerCase()
              .contains(_searchName.toLowerCase()))
          .toList();
    }
    if (_searchId.isNotEmpty) {
      final id = int.tryParse(_searchId);
      if (id != null) {
        filtered = filtered.where((inv) => inv.id == id).toList();
      }
    }
    _filteredInvoices = filtered;
  }

  @override
  void dispose() {
    _nameController
        .removeListener(_onNameChanged); // Remove listeners before disposing
    _idController
        .removeListener(_onIdChanged); // Remove listeners before disposing
    _nameController.dispose();
    _idController.dispose();
    super.dispose();
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
        // Define input field decoration theme
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            // Default border style
            borderRadius: BorderRadius.circular(10.0), // Rounded corners
            borderSide:
                BorderSide(color: Colors.grey[400]!), // Light grey border
          ),
          enabledBorder: OutlineInputBorder(
            // Border when enabled and not focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder(
            // Border when focused
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
                color: primaryColor, width: 2.0), // Primary color, thicker
          ),
          errorBorder: OutlineInputBorder(
            // Border when in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
                color: errorColor, width: 2.0), // Error color, thicker
          ),
          focusedErrorBorder: OutlineInputBorder(
            // Border when focused and in error state
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(color: errorColor, width: 2.0),
          ),
          labelStyle: TextStyle(
              color: Colors.grey[700], fontSize: 15.0), // Label text style
          hintStyle: TextStyle(
              color: Colors.grey[500], fontSize: 14.0), // Hint text style
          contentPadding: const EdgeInsets.symmetric(
              vertical: 16.0, horizontal: 16.0), // Inner padding
          filled: true, // Enable fill color
          fillColor: lightBackgroundColor, // Light background for fields
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
          title: const Text('تعديل القوائم (الفواتير)'),
          // The title style is now managed by appBarTheme.titleTextStyle
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(
                  color:
                      Color(0xFF3F51B5), // Explicitly set color for indicator
                ),
              )
            : Padding(
                padding:
                    const EdgeInsets.all(24.0), // Increased overall padding
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            // Changed from TextField to TextFormField for consistency
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: 'بحث باسم العميل',
                              prefixIcon: Icon(Icons.person_search,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary), // Themed icon
                            ),
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge, // Themed text style
                          ),
                        ),
                        const SizedBox(width: 16), // Increased spacing
                        Expanded(
                          child: TextFormField(
                            // Changed from TextField to TextFormField for consistency
                            controller: _idController,
                            decoration: InputDecoration(
                              labelText: 'بحث برقم الفاتورة',
                              prefixIcon: Icon(
                                  Icons.confirmation_number_outlined,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary), // Themed icon
                            ),
                            keyboardType: TextInputType.number,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge, // Themed text style
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24), // Increased spacing
                    Expanded(
                      child: _filteredInvoices.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد قوائم مطابقة',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                        color: Colors
                                            .grey[600]), // Themed text style
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  vertical:
                                      12.0), // Padding for the list itself
                              itemCount: _filteredInvoices.length,
                              itemBuilder: (context, index) {
                                final invoice = _filteredInvoices[index];
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
                                      'التاريخ: ${DateFormat('yyyy/MM/dd').format(invoice.invoiceDate)}', // Consistent date format
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              color: Colors.grey[
                                                  700]), // Themed text style
                                    ),
                                    trailing: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${formatCurrency(invoice.totalAmount)} دينار', // Formatted currency
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary, // Primary color for amount
                                              ),
                                        ),
                                        Text(
                                          invoice.status == 'معلقة'
                                              ? 'معلقة'
                                              : 'محفوظة',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: invoice.status == 'معلقة'
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .error
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .tertiary, // Themed status color
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              CreateInvoiceScreen(
                                            existingInvoice: invoice,
                                            isViewOnly:
                                                invoice.status == 'محفوظة',
                                          ),
                                        ),
                                      ).then((_) {
                                        // Refresh invoices when returning from CreateInvoiceScreen
                                        _fetchInvoices();
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
