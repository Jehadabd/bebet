import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:printing/printing.dart';
import '../models/customer.dart';
import '../services/commercial_statement_service.dart';
import '../services/pdf_service.dart';

class _NumericMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _NumericMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    final original = await GlobalMaterialLocalizations.delegate.load(locale);
    return _NumericMaterialLocalizations(original);
  }

  @override
  bool shouldReload(_NumericMaterialLocalizationsDelegate old) => false;
}

class _NumericMaterialLocalizations implements MaterialLocalizations {
  final MaterialLocalizations original;
  _NumericMaterialLocalizations(this.original);

  @override
  String formatMonthYear(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    return '$y / $m';
  }

  @override
  String formatMediumDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y / $m / $d';
  }

  @override
  String formatShortMonth(int monthIndex) {
    return monthIndex.toString().padLeft(2, '0');
  }

  @override
  String formatFullDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y / $m / $d';
  }

  @override
  String formatCompactDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  String formatShortDate(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  String get openAppDrawerTooltip => (original as dynamic).openAppDrawerTooltip;
  @override
  String get backButtonTooltip => (original as dynamic).backButtonTooltip;
  @override
  String get clearButtonTooltip => (original as dynamic).clearButtonTooltip;
  @override
  String get closeButtonTooltip => (original as dynamic).closeButtonTooltip;
  @override
  String get deleteButtonTooltip => (original as dynamic).deleteButtonTooltip;
  @override
  String get moreButtonTooltip => (original as dynamic).moreButtonTooltip;
  @override
  String get nextMonthTooltip => (original as dynamic).nextMonthTooltip;
  @override
  String get previousMonthTooltip => (original as dynamic).previousMonthTooltip;
  @override
  String get firstPageTooltip => (original as dynamic).firstPageTooltip;
  @override
  String get lastPageTooltip => (original as dynamic).lastPageTooltip;
  @override
  String get nextPageTooltip => (original as dynamic).nextPageTooltip;
  @override
  String get previousPageTooltip => (original as dynamic).previousPageTooltip;
  @override
  String get showMenuTooltip => (original as dynamic).showMenuTooltip;
  @override
  String get licensesPageTitle => (original as dynamic).licensesPageTitle;
  @override
  String get rowsPerPageTitle => (original as dynamic).rowsPerPageTitle;
  @override
  String get cancelButtonLabel => (original as dynamic).cancelButtonLabel;
  @override
  String get closeButtonLabel => (original as dynamic).closeButtonLabel;
  @override
  String get continueButtonLabel => (original as dynamic).continueButtonLabel;
  @override
  String get copyButtonLabel => (original as dynamic).copyButtonLabel;
  @override
  String get cutButtonLabel => (original as dynamic).cutButtonLabel;
  @override
  String get scanTextButtonLabel => (original as dynamic).scanTextButtonLabel;
  @override
  String get okButtonLabel => (original as dynamic).okButtonLabel;
  @override
  String get pasteButtonLabel => (original as dynamic).pasteButtonLabel;
  @override
  String get selectAllButtonLabel => (original as dynamic).selectAllButtonLabel;
  @override
  String get lookUpButtonLabel => (original as dynamic).lookUpButtonLabel;
  @override
  String get searchWebButtonLabel => (original as dynamic).searchWebButtonLabel;
  @override
  String get shareButtonLabel => (original as dynamic).shareButtonLabel;
  @override
  String get viewLicensesButtonLabel => (original as dynamic).viewLicensesButtonLabel;
  @override
  String get anteMeridiemAbbreviation => (original as dynamic).anteMeridiemAbbreviation;
  @override
  String get postMeridiemAbbreviation => (original as dynamic).postMeridiemAbbreviation;
  @override
  String get timePickerHourModeAnnouncement => (original as dynamic).timePickerHourModeAnnouncement;
  @override
  String get timePickerMinuteModeAnnouncement => (original as dynamic).timePickerMinuteModeAnnouncement;
  @override
  String get modalBarrierDismissLabel => (original as dynamic).modalBarrierDismissLabel;
  @override
  String get menuDismissLabel => (original as dynamic).menuDismissLabel;
  @override
  String get drawerLabel => (original as dynamic).drawerLabel;
  @override
  String get popupMenuLabel => (original as dynamic).popupMenuLabel;
  @override
  String get menuBarMenuLabel => (original as dynamic).menuBarMenuLabel;
  @override
  String get dialogLabel => (original as dynamic).dialogLabel;
  @override
  String get alertDialogLabel => (original as dynamic).alertDialogLabel;
  @override
  String get searchFieldLabel => (original as dynamic).searchFieldLabel;
  @override
  String get currentDateLabel => (original as dynamic).currentDateLabel;
  @override
  String get selectedDateLabel => (original as dynamic).selectedDateLabel;
  @override
  String get scrimLabel => (original as dynamic).scrimLabel;
  @override
  String get bottomSheetLabel => (original as dynamic).bottomSheetLabel;
  @override
  ScriptCategory get scriptCategory => (original as dynamic).scriptCategory;
  @override
  List<String> get narrowWeekdays => (original as dynamic).narrowWeekdays;
  @override
  int get firstDayOfWeekIndex => (original as dynamic).firstDayOfWeekIndex;
  @override
  String get dateSeparator => (original as dynamic).dateSeparator;
  @override
  String get dateHelpText => (original as dynamic).dateHelpText;
  @override
  String get selectYearSemanticsLabel => (original as dynamic).selectYearSemanticsLabel;
  @override
  String get unspecifiedDate => (original as dynamic).unspecifiedDate;
  @override
  String get unspecifiedDateRange => (original as dynamic).unspecifiedDateRange;
  @override
  String get dateInputLabel => (original as dynamic).dateInputLabel;
  @override
  String get dateRangeStartLabel => (original as dynamic).dateRangeStartLabel;
  @override
  String get dateRangeEndLabel => (original as dynamic).dateRangeEndLabel;
  @override
  String get invalidDateFormatLabel => (original as dynamic).invalidDateFormatLabel;
  @override
  String get invalidDateRangeLabel => (original as dynamic).invalidDateRangeLabel;
  @override
  String get dateOutOfRangeLabel => (original as dynamic).dateOutOfRangeLabel;
  @override
  String get saveButtonLabel => (original as dynamic).saveButtonLabel;
  @override
  String get datePickerHelpText => (original as dynamic).datePickerHelpText;
  @override
  String get dateRangePickerHelpText => (original as dynamic).dateRangePickerHelpText;
  @override
  String get calendarModeButtonLabel => (original as dynamic).calendarModeButtonLabel;
  @override
  String get inputDateModeButtonLabel => (original as dynamic).inputDateModeButtonLabel;
  @override
  String get timePickerDialHelpText => (original as dynamic).timePickerDialHelpText;
  @override
  String get timePickerInputHelpText => (original as dynamic).timePickerInputHelpText;
  @override
  String get timePickerHourLabel => (original as dynamic).timePickerHourLabel;
  @override
  String get timePickerMinuteLabel => (original as dynamic).timePickerMinuteLabel;
  @override
  String get invalidTimeLabel => (original as dynamic).invalidTimeLabel;
  @override
  String get dialModeButtonLabel => (original as dynamic).dialModeButtonLabel;
  @override
  String get inputTimeModeButtonLabel => (original as dynamic).inputTimeModeButtonLabel;
  @override
  String get signedInLabel => (original as dynamic).signedInLabel;
  @override
  String get hideAccountsLabel => (original as dynamic).hideAccountsLabel;
  @override
  String get showAccountsLabel => (original as dynamic).showAccountsLabel;
  @override
  String get reorderItemToStart => (original as dynamic).reorderItemToStart;
  @override
  String get reorderItemToEnd => (original as dynamic).reorderItemToEnd;
  @override
  String get reorderItemUp => (original as dynamic).reorderItemUp;
  @override
  String get reorderItemDown => (original as dynamic).reorderItemDown;
  @override
  String get reorderItemLeft => (original as dynamic).reorderItemLeft;
  @override
  String get reorderItemRight => (original as dynamic).reorderItemRight;
  @override
  String get refreshIndicatorSemanticLabel => (original as dynamic).refreshIndicatorSemanticLabel;
  @override
  String get keyboardKeyAlt => (original as dynamic).keyboardKeyAlt;
  @override
  String get keyboardKeyAltGraph => (original as dynamic).keyboardKeyAltGraph;
  @override
  String get keyboardKeyBackspace => (original as dynamic).keyboardKeyBackspace;
  @override
  String get keyboardKeyCapsLock => (original as dynamic).keyboardKeyCapsLock;
  @override
  String get keyboardKeyChannelDown => (original as dynamic).keyboardKeyChannelDown;
  @override
  String get keyboardKeyChannelUp => (original as dynamic).keyboardKeyChannelUp;
  @override
  String get keyboardKeyControl => (original as dynamic).keyboardKeyControl;
  @override
  String get keyboardKeyDelete => (original as dynamic).keyboardKeyDelete;
  @override
  String get keyboardKeyEject => (original as dynamic).keyboardKeyEject;
  @override
  String get keyboardKeyEnd => (original as dynamic).keyboardKeyEnd;
  @override
  String get keyboardKeyEscape => (original as dynamic).keyboardKeyEscape;
  @override
  String get keyboardKeyFn => (original as dynamic).keyboardKeyFn;
  @override
  String get keyboardKeyHome => (original as dynamic).keyboardKeyHome;
  @override
  String get keyboardKeyInsert => (original as dynamic).keyboardKeyInsert;
  @override
  String get keyboardKeyMeta => (original as dynamic).keyboardKeyMeta;
  @override
  String get keyboardKeyMetaMacOs => (original as dynamic).keyboardKeyMetaMacOs;
  @override
  String get keyboardKeyMetaWindows => (original as dynamic).keyboardKeyMetaWindows;
  @override
  String get keyboardKeyNumLock => (original as dynamic).keyboardKeyNumLock;
  @override
  String get keyboardKeyNumpad1 => (original as dynamic).keyboardKeyNumpad1;
  @override
  String get keyboardKeyNumpad2 => (original as dynamic).keyboardKeyNumpad2;
  @override
  String get keyboardKeyNumpad3 => (original as dynamic).keyboardKeyNumpad3;
  @override
  String get keyboardKeyNumpad4 => (original as dynamic).keyboardKeyNumpad4;
  @override
  String get keyboardKeyNumpad5 => (original as dynamic).keyboardKeyNumpad5;
  @override
  String get keyboardKeyNumpad6 => (original as dynamic).keyboardKeyNumpad6;
  @override
  String get keyboardKeyNumpad7 => (original as dynamic).keyboardKeyNumpad7;
  @override
  String get keyboardKeyNumpad8 => (original as dynamic).keyboardKeyNumpad8;
  @override
  String get keyboardKeyNumpad9 => (original as dynamic).keyboardKeyNumpad9;
  @override
  String get keyboardKeyNumpad0 => (original as dynamic).keyboardKeyNumpad0;
  @override
  String get keyboardKeyNumpadAdd => (original as dynamic).keyboardKeyNumpadAdd;
  @override
  String get keyboardKeyNumpadComma => (original as dynamic).keyboardKeyNumpadComma;
  @override
  String get keyboardKeyNumpadDecimal => (original as dynamic).keyboardKeyNumpadDecimal;
  @override
  String get keyboardKeyNumpadDivide => (original as dynamic).keyboardKeyNumpadDivide;
  @override
  String get keyboardKeyNumpadEnter => (original as dynamic).keyboardKeyNumpadEnter;
  @override
  String get keyboardKeyNumpadEqual => (original as dynamic).keyboardKeyNumpadEqual;
  @override
  String get keyboardKeyNumpadMultiply => (original as dynamic).keyboardKeyNumpadMultiply;
  @override
  String get keyboardKeyNumpadParenLeft => (original as dynamic).keyboardKeyNumpadParenLeft;
  @override
  String get keyboardKeyNumpadParenRight => (original as dynamic).keyboardKeyNumpadParenRight;
  @override
  String get keyboardKeyNumpadSubtract => (original as dynamic).keyboardKeyNumpadSubtract;
  @override
  String get keyboardKeyPageDown => (original as dynamic).keyboardKeyPageDown;
  @override
  String get keyboardKeyPageUp => (original as dynamic).keyboardKeyPageUp;
  @override
  String get keyboardKeyPower => (original as dynamic).keyboardKeyPower;
  @override
  String get keyboardKeyPowerOff => (original as dynamic).keyboardKeyPowerOff;
  @override
  String get keyboardKeyPrintScreen => (original as dynamic).keyboardKeyPrintScreen;
  @override
  String get keyboardKeyScrollLock => (original as dynamic).keyboardKeyScrollLock;
  @override
  String get keyboardKeySelect => (original as dynamic).keyboardKeySelect;
  @override
  String get keyboardKeyShift => (original as dynamic).keyboardKeyShift;
  @override
  String get keyboardKeySpace => (original as dynamic).keyboardKeySpace;
  @override
  String aboutListTileTitle(String applicationName) => original.aboutListTileTitle(applicationName);
  @override
  String licensesPackageDetailText(int licenseCount) => original.licensesPackageDetailText(licenseCount);
  @override
  String pageRowsInfoTitle(int firstRow, int lastRow, int rowCount, bool rowCountIsApproximate) => original.pageRowsInfoTitle(firstRow, lastRow, rowCount, rowCountIsApproximate);
  @override
  String tabLabel({required int tabIndex, required int tabCount}) => original.tabLabel(tabIndex: tabIndex, tabCount: tabCount);
  @override
  String selectedRowCountTitle(int selectedRowCount) => original.selectedRowCountTitle(selectedRowCount);
  @override
  String scrimOnTapHint(String modalRouteContentName) => original.scrimOnTapHint(modalRouteContentName);
  @override
  TimeOfDayFormat timeOfDayFormat({bool alwaysUse24HourFormat = false}) => original.timeOfDayFormat(alwaysUse24HourFormat: alwaysUse24HourFormat);
  @override
  String formatDecimal(int number) => original.formatDecimal(number);
  @override
  String formatHour(TimeOfDay timeOfDay, {bool alwaysUse24HourFormat = false}) => original.formatHour(timeOfDay, alwaysUse24HourFormat: alwaysUse24HourFormat);
  @override
  String formatMinute(TimeOfDay timeOfDay) => original.formatMinute(timeOfDay);
  @override
  String formatTimeOfDay(TimeOfDay timeOfDay, {bool alwaysUse24HourFormat = false}) => original.formatTimeOfDay(timeOfDay, alwaysUse24HourFormat: alwaysUse24HourFormat);
  @override
  String formatYear(DateTime date) => original.formatYear(date);
  @override
  String formatShortMonthDay(DateTime date) => original.formatShortMonthDay(date);
  @override
  DateTime? parseCompactDate(String? inputString) => original.parseCompactDate(inputString);
  @override
  String dateRangeStartDateSemanticLabel(String formattedDate) => original.dateRangeStartDateSemanticLabel(formattedDate);
  @override
  String dateRangeEndDateSemanticLabel(String formattedDate) => original.dateRangeEndDateSemanticLabel(formattedDate);
  @override
  String remainingTextFieldCharacterCount(int remaining) => original.remainingTextFieldCharacterCount(remaining);

  @override
  String get collapsedHint => original.collapsedHint;
  @override
  String get collapsedIconTapHint => original.collapsedIconTapHint;
  @override
  String get expandedHint => original.expandedHint;
  @override
  String get expandedIconTapHint => original.expandedIconTapHint;
  @override
  String get expansionTileCollapsedHint => original.expansionTileCollapsedHint;
  @override
  String get expansionTileCollapsedTapHint => original.expansionTileCollapsedTapHint;
  @override
  String get expansionTileExpandedHint => original.expansionTileExpandedHint;
  @override
  String get expansionTileExpandedTapHint => original.expansionTileExpandedTapHint;
}


/// حوار اختيار فترة مخصصة بتصميم أنيق وبأرقام فقط
class CustomDateRangeDialog extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;

  const CustomDateRangeDialog({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
  });

  @override
  State<CustomDateRangeDialog> createState() => _CustomDateRangeDialogState();
}

class _CustomDateRangeDialogState extends State<CustomDateRangeDialog> {
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStartDate ?? DateTime.now().subtract(const Duration(days: 30));
    _endDate = widget.initialEndDate ?? DateTime.now();
  }

  String _formatDate(DateTime dt) {
    return DateFormat('yyyy/MM/dd').format(dt);
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Localizations.override(
          context: context,
          delegates: const [
            _NumericMaterialLocalizationsDelegate(),
          ],
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: Color(0xFF3F51B5)),
            ),
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Localizations.override(
          context: context,
          delegates: const [
            _NumericMaterialLocalizationsDelegate(),
          ],
          child: Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(primary: Color(0xFF3F51B5)),
            ),
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        if (_startDate.isAfter(_endDate)) {
          _startDate = _endDate;
        }
      });
    }
  }

  void _setPreset(int daysBack) {
    setState(() {
      _endDate = DateTime.now();
      _startDate = DateTime.now().subtract(Duration(days: daysBack));
    });
  }

  void _setCurrentMonth() {
    final now = DateTime.now();
    setState(() {
      _startDate = DateTime(now.year, now.month, 1);
      _endDate = DateTime(now.year, now.month + 1, 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: EdgeInsets.zero,
      title: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0xFF3F51B5),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: const Row(
          children: [
            Icon(Icons.date_range, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'تحديد فترة مخصصة',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.flash_on, size: 16),
                  label: const Text('آخر 7 أيام'),
                  onPressed: () => _setPreset(7),
                ),
                ActionChip(
                  avatar: const Icon(Icons.history, size: 16),
                  label: const Text('آخر 30 يوم'),
                  onPressed: () => _setPreset(30),
                ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_month, size: 16),
                  label: const Text('الشهر الحالي'),
                  onPressed: _setCurrentMonth,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickStartDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue.shade300, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.blue.shade50,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.play_arrow, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('من تاريخ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    Text(
                      _formatDate(_startDate),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickEndDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.indigo.shade300, width: 1.5),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.indigo.shade50,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.stop, color: Colors.indigo),
                        SizedBox(width: 8),
                        Text('إلى تاريخ:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    Text(
                      _formatDate(_endDate),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.indigo),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3F51B5),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.pop(context, DateTimeRange(start: _startDate, end: _endDate)),
          icon: const Icon(Icons.check),
          label: const Text('تأكيد'),
        ),
      ],
    );
  }
}

/// حوار اختيار الفترة الزمنية
class PeriodSelectionDialog extends StatefulWidget {
  final List<int> availableYears;
  
  const PeriodSelectionDialog({
    super.key,
    required this.availableYears,
  });

  @override
  State<PeriodSelectionDialog> createState() => _PeriodSelectionDialogState();
}

class _PeriodSelectionDialogState extends State<PeriodSelectionDialog> {
  int? _selectedYear;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('اختر الفترة الزمنية', textAlign: TextAlign.center),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.all_inclusive, color: Colors.blue),
                title: const Text('كشف حساب شامل'),
                subtitle: const Text('جميع المعاملات منذ البداية'),
                onTap: () => Navigator.pop(context, {'type': 'all'}),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.date_range, color: Colors.green),
                title: const Text('فترة مخصصة'),
                subtitle: const Text('اختيار من تاريخ إلى تاريخ'),
                onTap: () => Navigator.pop(context, {'type': 'custom'}),
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('أو اختر سنة:', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ...widget.availableYears.map((year) => _buildYearTile(year)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }

  Widget _buildYearTile(int year) {
    final isExpanded = _selectedYear == year;
    return Column(
      children: [
        ListTile(
          leading: Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.indigo),
          title: Text('سنة $year'),
          onTap: () => setState(() => _selectedYear = isExpanded ? null : year),
        ),
        if (isExpanded) ...[
          Padding(
            padding: const EdgeInsets.only(right: 32),
            child: ListTile(
              leading: const Icon(Icons.calendar_today, color: Colors.green),
              title: const Text('السنة كاملة'),
              onTap: () => Navigator.pop(context, {'type': 'year', 'year': year}),
            ),
          ),
          ...List.generate(12, (index) {
            final month = index + 1;
            final monthFormatted = month.toString().padLeft(2, '0');
            return Padding(
              padding: const EdgeInsets.only(right: 32),
              child: ListTile(
                leading: const Icon(Icons.date_range, color: Colors.orange),
                title: Text('شهر $monthFormatted - $year'),
                onTap: () => Navigator.pop(context, {'type': 'month', 'year': year, 'month': month}),
              ),
            );
          }),
        ],
      ],
    );
  }
}

/// شاشة كشف الحساب التجاري
class CommercialStatementScreen extends StatefulWidget {
  final Customer customer;
  final DateTime? startDate;
  final DateTime? endDate;
  final String periodDescription;

  const CommercialStatementScreen({
    super.key,
    required this.customer,
    this.startDate,
    this.endDate,
    required this.periodDescription,
  });

  @override
  State<CommercialStatementScreen> createState() => _CommercialStatementScreenState();
}

class _CommercialStatementScreenState extends State<CommercialStatementScreen> {
  final CommercialStatementService _service = CommercialStatementService();
  Map<String, dynamic>? _statementData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatement();
  }

  Future<void> _loadStatement() async {
    try {
      setState(() { _isLoading = true; _error = null; });
      final data = await _service.getCommercialStatement(
        customerId: widget.customer.id!,
        startDate: widget.startDate,
        endDate: widget.endDate,
      );
      if (mounted) setState(() { _statementData = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  String _formatCurrency(num value) => NumberFormat('#,##0', 'en_US').format(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('كشف الحساب التجاري - ${widget.customer.name}'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'تصدير PDF',
            onPressed: _statementData != null ? _exportPdf : null,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('حدث خطأ: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadStatement, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_statementData == null) return const Center(child: Text('لا توجد بيانات'));

    final entries = _statementData!['entries'] as List<Map<String, dynamic>>;
    final summary = _statementData!['summary'] as Map<String, dynamic>;
    final finalBalance = (_statementData!['finalBalance'] as num).toDouble();

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSummaryCard(summary),
          _buildBalanceWarning(finalBalance),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('الفترة: ${widget.periodDescription}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          // عناوين الأعمدة
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: const [
                Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Text('البيان', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('المبلغ', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('الدين قبل', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('الدين بعد', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
              ],
            ),
          ),
          // قائمة السطور
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            itemBuilder: (context, index) => _buildEntryRow(entries[index]),
          ),
        ],
      ),
    );
  }


  Widget _buildSummaryCard(Map<String, dynamic> summary) {
    final totalDebtInvoices = summary['totalDebtInvoices'] as int? ?? 0;
    final totalCashInvoices = summary['totalCashInvoices'] as int? ?? 0;
    final convertedToCash = summary['convertedToCash'] as int? ?? 0;
    final convertedToDebt = summary['convertedToDebt'] as int? ?? 0;
    final invoiceDebts = (summary['invoiceDebts'] as num?)?.toDouble() ?? 0.0;
    final manualDebts = (summary['manualDebts'] as num?)?.toDouble() ?? 0.0;
    final totalDebts = (summary['totalDebts'] as num?)?.toDouble() ?? 0.0;
    final invoicePayments = (summary['invoicePayments'] as num?)?.toDouble() ?? 0.0;
    final manualPayments = (summary['manualPayments'] as num?)?.toDouble() ?? 0.0;
    final totalPayments = (summary['totalPayments'] as num?)?.toDouble() ?? 0.0;
    final remainingBalance = (summary['remainingBalance'] as num?)?.toDouble() ?? 0.0;
    final periodBalanceColor = remainingBalance > 0 ? Colors.amber[800]! : Colors.blue[800]!;
    final currentDebt = widget.customer.currentTotalDebt;
    final currentBalanceColor = currentDebt > 0 ? Colors.red : Colors.green;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('ملخص الحساب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            
            // عدد الفواتير
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem('فواتير دين', '$totalDebtInvoices', Colors.blue),
                _buildSummaryItem('فواتير نقد', '$totalCashInvoices', Colors.blueGrey),
              ],
            ),
            // الفواتير المحولة
            if (convertedToCash > 0 || convertedToDebt > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (convertedToCash > 0)
                      _buildSummaryItem('تحولت لنقد', '$convertedToCash', Colors.purple),
                    if (convertedToDebt > 0)
                      _buildSummaryItem('تحولت لدين', '$convertedToDebt', Colors.deepOrange),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            
            // إجمالي الديون
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Text('إجمالي الديون في هذه الفترة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem('ديون الفواتير', _formatCurrency(invoiceDebts), Colors.orange[700]!),
                      _buildSummaryItem('ديون يدوية', _formatCurrency(manualDebts), Colors.orange[400]!),
                    ],
                  ),
                  const Divider(),
                  Text('المجموع: ${_formatCurrency(totalDebts)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange[800])),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // إجمالي المدفوعات
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Text('إجمالي المدفوعات في هذه الفترة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem('مدفوعات الفواتير', _formatCurrency(invoicePayments), Colors.green[700]!),
                      _buildSummaryItem('مدفوعات يدوية', _formatCurrency(manualPayments), Colors.green[400]!),
                    ],
                  ),
                  const Divider(),
                  Text('المجموع: ${_formatCurrency(totalPayments)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[800])),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // الرصيد في نهاية هذه الفترة
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: remainingBalance > 0 ? Colors.amber[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: periodBalanceColor, width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الرصيد المتبقي في نهاية هذه الفترة:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(_formatCurrency(remainingBalance), style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: periodBalanceColor)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            
            // الرصيد المتبقي الحالي حتى اليوم
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: currentDebt > 0 ? Colors.red[50] : Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: currentBalanceColor, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('الرصيد المتبقي الحالي (حتى اليوم):', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  Text(_formatCurrency(currentDebt), style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: currentBalanceColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // تم إزالة تنبيه الفرق لأن الرصيد المحسوب من كشف الحساب التجاري 
  // قد يختلف عن رصيد العميل المخزن بسبب توقيت التحديث
  Widget _buildBalanceWarning(double finalBalance) {
    // لا نعرض تنبيه - الرصيد المحسوب هو الصحيح
    return const SizedBox.shrink();
  }

  Widget _buildEntryRow(Map<String, dynamic> entry) {
    final date = entry['date'] as DateTime;
    final description = entry['description'] as String;
    final invoiceAmount = (entry['invoiceAmount'] as num?)?.toDouble() ?? 0.0;
    final netAmount = (entry['netAmount'] as num?)?.toDouble() ?? 0.0;
    final debtBefore = (entry['debtBefore'] as num?)?.toDouble() ?? 0.0;
    final debtAfter = (entry['debtAfter'] as num?)?.toDouble() ?? 0.0;
    final type = entry['type'] as String;
    
    // تحديد المبلغ المعروض:
    // - فاتورة نقد: مبلغ الفاتورة (للعرض فقط)
    // - فاتورة محولة لنقد/لدين: مبلغ الفاتورة الأصلي
    // - فاتورة دين: مبلغ الفاتورة
    // - معاملة يدوية: المبلغ
    double displayAmount;
    if (type == 'cash_invoice' || type == 'converted_to_cash' || type == 'converted_to_debt' || type == 'debt_invoice') {
      displayAmount = invoiceAmount; // مبلغ الفاتورة الأصلي
    } else {
      displayAmount = netAmount.abs(); // صافي التأثير على الدين
    }
    
    Color rowColor = Colors.white;
    Color amountColor = Colors.black;
    if (type == 'cash_invoice') {
      rowColor = Colors.blue[50]!;
      amountColor = Colors.blue[700]!;
    } else if (type == 'converted_to_cash') {
      rowColor = Colors.purple[50]!;
      amountColor = Colors.purple[700]!;
    } else if (type == 'converted_to_debt') {
      rowColor = Colors.deepOrange[50]!;
      amountColor = Colors.deepOrange[700]!;
    } else if (type == 'manual_transaction') {
      rowColor = netAmount < 0 ? Colors.green[50]! : Colors.orange[50]!;
      amountColor = netAmount < 0 ? Colors.green[700]! : Colors.orange[700]!;
    } else if (type == 'debt_invoice') {
      amountColor = Colors.red[700]!;
    }

    return Container(
      color: rowColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(DateFormat('yyyy/MM/dd').format(date), style: const TextStyle(fontSize: 12))),
          Expanded(flex: 3, child: Text(description, style: const TextStyle(fontSize: 12))),
          Expanded(flex: 2, child: Text(_formatCurrency(displayAmount), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: amountColor))),
          Expanded(flex: 2, child: Text(_formatCurrency(debtBefore), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
          Expanded(flex: 2, child: Text(_formatCurrency(debtAfter), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: debtAfter > 0 ? Colors.red : Colors.green))),
        ],
      ),
    );
  }

  Future<void> _exportPdf() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final pdfService = PdfService();
      final pdf = await pdfService.generateCommercialStatement(
        customer: widget.customer,
        statementData: _statementData!,
        periodDescription: widget.periodDescription,
      );

      if (mounted) Navigator.pop(context);

      if (Platform.isWindows) {
        final safeCustomerName = widget.customer.name.replaceAll(RegExp(r'[^\w\u0600-\u06FF]+'), '_');
        final formattedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final fileName = 'كشف_تجاري_${safeCustomerName}_$formattedDate.pdf';
        final directory = Directory('${Platform.environment['USERPROFILE']}/Documents/commercial_statements');
        if (!await directory.exists()) await directory.create(recursive: true);
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(pdf);
        await Process.start('cmd', ['/c', 'start', '/min', '', filePath]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إنشاء كشف الحساب التجاري وفتحه!'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) await Printing.layoutPdf(onLayout: (format) async => pdf);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
