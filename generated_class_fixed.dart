class _NumericMaterialLocalizations implements MaterialLocalizations {
  final MaterialLocalizations original;
  _NumericMaterialLocalizations(this.original);

  @override
  String formatMonthYear(DateTime date) {
    final m = date.month.toString().padLeft(2, '0');
    return '$m / ${date.year}';
  }

  @override
  String formatMediumDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d / $m / ${date.year}';
  }

  @override
  String formatShortMonth(int monthIndex) {
    return monthIndex.toString().padLeft(2, '0');
  }

  @override
  String formatFullDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d / $m / ${date.year}';
  }

  @override
  String formatCompactDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  @override
  String formatShortDate(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  @override
  String get openAppDrawerTooltip => original.openAppDrawerTooltip;
  @override
  String get backButtonTooltip => original.backButtonTooltip;
  @override
  String get clearButtonTooltip => original.clearButtonTooltip;
  @override
  String get closeButtonTooltip => original.closeButtonTooltip;
  @override
  String get deleteButtonTooltip => original.deleteButtonTooltip;
  @override
  String get moreButtonTooltip => original.moreButtonTooltip;
  @override
  String get nextMonthTooltip => original.nextMonthTooltip;
  @override
  String get previousMonthTooltip => original.previousMonthTooltip;
  @override
  String get firstPageTooltip => original.firstPageTooltip;
  @override
  String get lastPageTooltip => original.lastPageTooltip;
  @override
  String get nextPageTooltip => original.nextPageTooltip;
  @override
  String get previousPageTooltip => original.previousPageTooltip;
  @override
  String get showMenuTooltip => original.showMenuTooltip;
  @override
  String get licensesPageTitle => original.licensesPageTitle;
  @override
  String get rowsPerPageTitle => original.rowsPerPageTitle;
  @override
  String get cancelButtonLabel => original.cancelButtonLabel;
  @override
  String get closeButtonLabel => original.closeButtonLabel;
  @override
  String get continueButtonLabel => original.continueButtonLabel;
  @override
  String get copyButtonLabel => original.copyButtonLabel;
  @override
  String get cutButtonLabel => original.cutButtonLabel;
  @override
  String get scanTextButtonLabel => original.scanTextButtonLabel;
  @override
  String get okButtonLabel => original.okButtonLabel;
  @override
  String get pasteButtonLabel => original.pasteButtonLabel;
  @override
  String get selectAllButtonLabel => original.selectAllButtonLabel;
  @override
  String get lookUpButtonLabel => original.lookUpButtonLabel;
  @override
  String get searchWebButtonLabel => original.searchWebButtonLabel;
  @override
  String get shareButtonLabel => original.shareButtonLabel;
  @override
  String get viewLicensesButtonLabel => original.viewLicensesButtonLabel;
  @override
  String get anteMeridiemAbbreviation => original.anteMeridiemAbbreviation;
  @override
  String get postMeridiemAbbreviation => original.postMeridiemAbbreviation;
  @override
  String get timePickerHourModeAnnouncement => original.timePickerHourModeAnnouncement;
  @override
  String get timePickerMinuteModeAnnouncement => original.timePickerMinuteModeAnnouncement;
  @override
  String get modalBarrierDismissLabel => original.modalBarrierDismissLabel;
  @override
  String get menuDismissLabel => original.menuDismissLabel;
  @override
  String get drawerLabel => original.drawerLabel;
  @override
  String get popupMenuLabel => original.popupMenuLabel;
  @override
  String get menuBarMenuLabel => original.menuBarMenuLabel;
  @override
  String get dialogLabel => original.dialogLabel;
  @override
  String get alertDialogLabel => original.alertDialogLabel;
  @override
  String get searchFieldLabel => original.searchFieldLabel;
  @override
  String get currentDateLabel => original.currentDateLabel;
  @override
  String get selectedDateLabel => original.selectedDateLabel;
  @override
  String get scrimLabel => original.scrimLabel;
  @override
  String get bottomSheetLabel => original.bottomSheetLabel;
  @override
  ScriptCategory get scriptCategory => original.scriptCategory;
  @override
  List<String> get narrowWeekdays => original.narrowWeekdays;
  @override
  int get firstDayOfWeekIndex => original.firstDayOfWeekIndex;
  @override
  String get dateSeparator => original.dateSeparator;
  @override
  String get dateHelpText => original.dateHelpText;
  @override
  String get selectYearSemanticsLabel => original.selectYearSemanticsLabel;
  @override
  String get unspecifiedDate => original.unspecifiedDate;
  @override
  String get unspecifiedDateRange => original.unspecifiedDateRange;
  @override
  String get dateInputLabel => original.dateInputLabel;
  @override
  String get dateRangeStartLabel => original.dateRangeStartLabel;
  @override
  String get dateRangeEndLabel => original.dateRangeEndLabel;
  @override
  String get invalidDateFormatLabel => original.invalidDateFormatLabel;
  @override
  String get invalidDateRangeLabel => original.invalidDateRangeLabel;
  @override
  String get dateOutOfRangeLabel => original.dateOutOfRangeLabel;
  @override
  String get saveButtonLabel => original.saveButtonLabel;
  @override
  String get datePickerHelpText => original.datePickerHelpText;
  @override
  String get dateRangePickerHelpText => original.dateRangePickerHelpText;
  @override
  String get calendarModeButtonLabel => original.calendarModeButtonLabel;
  @override
  String get inputDateModeButtonLabel => original.inputDateModeButtonLabel;
  @override
  String get timePickerDialHelpText => original.timePickerDialHelpText;
  @override
  String get timePickerInputHelpText => original.timePickerInputHelpText;
  @override
  String get timePickerHourLabel => original.timePickerHourLabel;
  @override
  String get timePickerMinuteLabel => original.timePickerMinuteLabel;
  @override
  String get invalidTimeLabel => original.invalidTimeLabel;
  @override
  String get dialModeButtonLabel => original.dialModeButtonLabel;
  @override
  String get inputTimeModeButtonLabel => original.inputTimeModeButtonLabel;
  @override
  String get signedInLabel => original.signedInLabel;
  @override
  String get hideAccountsLabel => original.hideAccountsLabel;
  @override
  String get showAccountsLabel => original.showAccountsLabel;
  @override
  String get reorderItemToStart => original.reorderItemToStart;
  @override
  String get reorderItemToEnd => original.reorderItemToEnd;
  @override
  String get reorderItemUp => original.reorderItemUp;
  @override
  String get reorderItemDown => original.reorderItemDown;
  @override
  String get reorderItemLeft => original.reorderItemLeft;
  @override
  String get reorderItemRight => original.reorderItemRight;
  @override
  String get refreshIndicatorSemanticLabel => original.refreshIndicatorSemanticLabel;
  @override
  String get keyboardKeyAlt => original.keyboardKeyAlt;
  @override
  String get keyboardKeyAltGraph => original.keyboardKeyAltGraph;
  @override
  String get keyboardKeyBackspace => original.keyboardKeyBackspace;
  @override
  String get keyboardKeyCapsLock => original.keyboardKeyCapsLock;
  @override
  String get keyboardKeyChannelDown => original.keyboardKeyChannelDown;
  @override
  String get keyboardKeyChannelUp => original.keyboardKeyChannelUp;
  @override
  String get keyboardKeyControl => original.keyboardKeyControl;
  @override
  String get keyboardKeyDelete => original.keyboardKeyDelete;
  @override
  String get keyboardKeyEject => original.keyboardKeyEject;
  @override
  String get keyboardKeyEnd => original.keyboardKeyEnd;
  @override
  String get keyboardKeyEscape => original.keyboardKeyEscape;
  @override
  String get keyboardKeyFn => original.keyboardKeyFn;
  @override
  String get keyboardKeyHome => original.keyboardKeyHome;
  @override
  String get keyboardKeyInsert => original.keyboardKeyInsert;
  @override
  String get keyboardKeyMeta => original.keyboardKeyMeta;
  @override
  String get keyboardKeyMetaMacOs => original.keyboardKeyMetaMacOs;
  @override
  String get keyboardKeyMetaWindows => original.keyboardKeyMetaWindows;
  @override
  String get keyboardKeyNumLock => original.keyboardKeyNumLock;
  @override
  String get keyboardKeyNumpad1 => original.keyboardKeyNumpad1;
  @override
  String get keyboardKeyNumpad2 => original.keyboardKeyNumpad2;
  @override
  String get keyboardKeyNumpad3 => original.keyboardKeyNumpad3;
  @override
  String get keyboardKeyNumpad4 => original.keyboardKeyNumpad4;
  @override
  String get keyboardKeyNumpad5 => original.keyboardKeyNumpad5;
  @override
  String get keyboardKeyNumpad6 => original.keyboardKeyNumpad6;
  @override
  String get keyboardKeyNumpad7 => original.keyboardKeyNumpad7;
  @override
  String get keyboardKeyNumpad8 => original.keyboardKeyNumpad8;
  @override
  String get keyboardKeyNumpad9 => original.keyboardKeyNumpad9;
  @override
  String get keyboardKeyNumpad0 => original.keyboardKeyNumpad0;
  @override
  String get keyboardKeyNumpadAdd => original.keyboardKeyNumpadAdd;
  @override
  String get keyboardKeyNumpadComma => original.keyboardKeyNumpadComma;
  @override
  String get keyboardKeyNumpadDecimal => original.keyboardKeyNumpadDecimal;
  @override
  String get keyboardKeyNumpadDivide => original.keyboardKeyNumpadDivide;
  @override
  String get keyboardKeyNumpadEnter => original.keyboardKeyNumpadEnter;
  @override
  String get keyboardKeyNumpadEqual => original.keyboardKeyNumpadEqual;
  @override
  String get keyboardKeyNumpadMultiply => original.keyboardKeyNumpadMultiply;
  @override
  String get keyboardKeyNumpadParenLeft => original.keyboardKeyNumpadParenLeft;
  @override
  String get keyboardKeyNumpadParenRight => original.keyboardKeyNumpadParenRight;
  @override
  String get keyboardKeyNumpadSubtract => original.keyboardKeyNumpadSubtract;
  @override
  String get keyboardKeyPageDown => original.keyboardKeyPageDown;
  @override
  String get keyboardKeyPageUp => original.keyboardKeyPageUp;
  @override
  String get keyboardKeyPower => original.keyboardKeyPower;
  @override
  String get keyboardKeyPowerOff => original.keyboardKeyPowerOff;
  @override
  String get keyboardKeyPrintScreen => original.keyboardKeyPrintScreen;
  @override
  String get keyboardKeyScrollLock => original.keyboardKeyScrollLock;
  @override
  String get keyboardKeySelect => original.keyboardKeySelect;
  @override
  String get keyboardKeyShift => original.keyboardKeyShift;
  @override
  String get keyboardKeySpace => original.keyboardKeySpace;
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
  String get expandedHint => original.expandedHint;
  @override
  String get expansionTileCollapsedHint => original.expansionTileCollapsedHint;
  @override
  String get expansionTileCollapsedTapHint => original.expansionTileCollapsedTapHint;
  @override
  String get expansionTileExpandedHint => original.expansionTileExpandedHint;
  @override
  String get expansionTileExpandedTapHint => original.expansionTileExpandedTapHint;
}
