// widgets/formatters.dart
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ThousandSeparatorInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat('#,##0', 'en_US');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Allow empty
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Keep only digits
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue(text: '');
    }

    // Parse to int and format
    final int value = int.parse(digitsOnly);
    final String newText = _formatter.format(value);

    // Calculate new cursor position from the right end
    final int selectionFromRight = newValue.text.length - newValue.selection.end;
    final int newSelectionIndex = newText.length - selectionFromRight;
    final int clampedSelectionIndex = newSelectionIndex.clamp(0, newText.length);

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: clampedSelectionIndex),
    );
  }
}


