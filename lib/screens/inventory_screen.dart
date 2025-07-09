// screens/inventory_screen.dart
// screens/inventory_screen.dart
import 'package:flutter/material.dart';
import '../services/database_service.dart'; // Assumed DatabaseService exists
import 'package:intl/intl.dart'; // For formatting dates and currency

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final DatabaseService _db = DatabaseService();
  Map<String, MonthlySalesSummary> _monthlySummaries = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMonthlySummaries();
  }

  Future<void> _loadMonthlySummaries() async {
    setState(() => _isLoading = true);
    try {
      final summaries = await _db.getMonthlySalesSummary();
      setState(() {
        _monthlySummaries = summaries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل ملخص المبيعات: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  // Helper to format currency consistently
  String formatCurrency(num value) {
    return NumberFormat('0.00', 'ar_IQ').format(
        value); // Always two decimal places, with Iraqi Dinar symbol or relevant
  }
  // If you prefer just the number without symbol, use 'en_US' locale
  // String formatNumberTwoDecimals(num value) {
  //   return NumberFormat('0.00', 'en_US').format(value);
  // }

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
    final Color warningColor =
        Colors.orange[700]!; // Orange for warning/returns

    // Sort months in descending order (most recent first)
    final sortedMonthYears = _monthlySummaries.keys.toList();
    sortedMonthYears.sort((a, b) {
      // Ensure month is zero-padded for parsing
      final aDate = DateTime.parse(
          '${a.split('-')[0]}-${a.split('-')[1].padLeft(2, '0')}-01');
      final bDate = DateTime.parse(
          '${b.split('-')[0]}-${b.split('-')[1].padLeft(2, '0')}-01');
      return bDate.compareTo(aDate);
    });

    final now = DateTime.now();

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
          headlineMedium: TextStyle(
              fontSize: 24.0,
              fontWeight: FontWeight.bold,
              color: primaryColor), // For main amounts
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
        // Define ListTile theme (if any are used here or in future updates)
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
          title: const Text('الجرد'),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color:
                      Color(0xFF3F51B5), // Explicitly set color for indicator
                ),
              )
            : _monthlySummaries.isEmpty
                ? Center(
                    child: Text(
                      'لا توجد بيانات مبيعات متاحة.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(
                        24.0), // Consistent padding for the list
                    itemCount: sortedMonthYears.length,
                    itemBuilder: (context, index) {
                      final monthYear = sortedMonthYears[index];
                      final summary = _monthlySummaries[monthYear]!;

                      final date = DateTime.parse(
                          '${monthYear.split('-')[0]}-${monthYear.split('-')[1].padLeft(2, '0')}-01');
                      final monthName = DateFormat.yMMMM('ar').format(date);
                      final isCurrentMonth =
                          date.year == now.year && date.month == now.month;

                      return Card(
                        margin: const EdgeInsets.only(
                            bottom: 20.0), // Spacing between cards
                        child: Padding(
                          padding: const EdgeInsets.all(
                              20.0), // Increased internal padding
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    monthName,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  if (isCurrentMonth) ...[
                                    const SizedBox(width: 8),
                                    Icon(Icons.calendar_today,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondary,
                                        size: 20),
                                    const SizedBox(width: 4),
                                    Text(
                                      'الشهر الحالي',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .secondary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                              const Divider(
                                  height: 24, thickness: 1.0), // Themed divider
                              _buildSummaryRow('إجمالي المبيعات:',
                                  summary.totalSales, context),
                              _buildSummaryRow('إجمالي الراجع:',
                                  summary.totalReturns, context,
                                  valueColor:
                                      warningColor), // Orange for returns
                              _buildSummaryRow(
                                  'صافي الأرباح:', summary.netProfit, context,
                                  isBold: true), // Bold for net profit
                              const Divider(
                                  height: 24,
                                  thickness:
                                      0.5), // Lighter divider for sub-sections
                              _buildSummaryRow(
                                  'البيع بالنقد:', summary.cashSales, context),
                              _buildSummaryRow('البيع بالدين:',
                                  summary.creditSales, context),
                              _buildSummaryRow('تسديد الديون:',
                                  summary.totalDebtPayments, context,
                                  valueColor:
                                      successColor), // Green for debt payments
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }

  // Helper widget for consistent summary rows
  Widget _buildSummaryRow(String label, num value, BuildContext context,
      {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 4.0), // Spacing between rows
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                ),
          ),
          Text(
            '${formatCurrency(value)} دينار عراقي', // Consistent currency formatting
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: valueColor ??
                      Theme.of(context)
                          .colorScheme
                          .onSurface, // Apply custom color or default
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                ),
          ),
        ],
      ),
    );
  }
}
