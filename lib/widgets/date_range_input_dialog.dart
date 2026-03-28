// widgets/date_range_input_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// نافذة إدخال نطاق تاريخ مخصصة
Future<DateTimeRange?> showDateRangeInputDialog({
  required BuildContext context,
  required DateTime initialStart,
  required DateTime initialEnd,
  Color accentColor = const Color(0xFF2196F3),
}) async {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (context) => _DateRangeInputDialog(
      initialStart: initialStart,
      initialEnd: initialEnd,
      accentColor: accentColor,
    ),
  );
}

class _DateRangeInputDialog extends StatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;
  final Color accentColor;
  const _DateRangeInputDialog({
    required this.initialStart,
    required this.initialEnd,
    required this.accentColor,
  });
  @override
  State<_DateRangeInputDialog> createState() => _DateRangeInputDialogState();
}

class _DateRangeInputDialogState extends State<_DateRangeInputDialog> {
  final _startDayCtrl   = TextEditingController();
  final _startMonthCtrl = TextEditingController();
  final _startYearCtrl  = TextEditingController();
  final _endDayCtrl     = TextEditingController();
  final _endMonthCtrl   = TextEditingController();
  final _endYearCtrl    = TextEditingController();

  final _startDayFocus   = FocusNode();
  final _startMonthFocus = FocusNode();
  final _startYearFocus  = FocusNode();
  final _endDayFocus     = FocusNode();
  final _endMonthFocus   = FocusNode();
  final _endYearFocus    = FocusNode();

  String? _errorMsg;

  final _today = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startDayCtrl.text   = _pad(widget.initialStart.day);
    _startMonthCtrl.text = _pad(widget.initialStart.month);
    _startYearCtrl.text  = widget.initialStart.year.toString();
    _endDayCtrl.text     = _pad(widget.initialEnd.day);
    _endMonthCtrl.text   = _pad(widget.initialEnd.month);
    _endYearCtrl.text    = widget.initialEnd.year.toString();
  }

  @override
  void dispose() {
    for (final c in [_startDayCtrl,_startMonthCtrl,_startYearCtrl,_endDayCtrl,_endMonthCtrl,_endYearCtrl]) c.dispose();
    for (final f in [_startDayFocus,_startMonthFocus,_startYearFocus,_endDayFocus,_endMonthFocus,_endYearFocus]) f.dispose();
    super.dispose();
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  // ─── منطق اليوم ──────────────────────────────────────────
  void _onDayChanged(String val, TextEditingController ctrl, FocusNode nextFocus) {
    setState(() => _errorMsg = null);
    final n = int.tryParse(val);
    if (n == null || val.isEmpty) return;

    if (val.length == 2) {
      if (n < 1 || n > 31) {
        // ارفض الرقم الثاني
        ctrl.text = val[0];
        ctrl.selection = TextSelection.collapsed(offset: 1);
        setState(() => _errorMsg = 'اليوم يجب أن يكون بين 1 و 31');
        return;
      }
      nextFocus.requestFocus();
    } else if (val.length == 1) {
      // رقم > 3 يعني يوم أحادي صالح (4-9) → انتقل فوراً
      if (n > 3) nextFocus.requestFocus();
    }
  }

  // ─── منطق الشهر ──────────────────────────────────────────
  void _onMonthChanged(
    String val,
    TextEditingController ctrl,
    FocusNode nextFocus,
    bool isStartDate,
  ) {
    setState(() => _errorMsg = null);
    final n = int.tryParse(val);
    if (n == null || val.isEmpty) return;

    if (val.length == 2) {
      if (n < 1 || n > 12) {
        ctrl.text = val[0];
        ctrl.selection = TextSelection.collapsed(offset: 1);
        setState(() => _errorMsg = 'الشهر يجب أن يكون بين 1 و 12');
        return;
      }
      // إذا كان تاريخ بدء وسنته = السنة الحالية → تحقق من الشهر
      if (isStartDate) {
        final y = int.tryParse(_startYearCtrl.text) ?? 0;
        if (y == _today.year && n > _today.month) {
          ctrl.text = val[0];
          ctrl.selection = TextSelection.collapsed(offset: 1);
          setState(() => _errorMsg = 'شهر البدء لا يمكن أن يكون بعد الشهر الحالي (${_today.month})');
          return;
        }
      }
      nextFocus.requestFocus();
    } else if (val.length == 1) {
      // رقم > 1 → شهر أحادي (2-9) → تحقق ثم انتقل
      if (n > 1) {
        if (isStartDate) {
          final y = int.tryParse(_startYearCtrl.text) ?? 0;
          if (y == _today.year && n > _today.month) {
            ctrl.text = '';
            setState(() => _errorMsg = 'شهر البدء لا يمكن أن يكون بعد الشهر الحالي (${_today.month})');
            return;
          }
        }
        nextFocus.requestFocus();
      }
    }
  }

  // ─── منطق السنة ──────────────────────────────────────────
  void _onStartYearChanged(String val) {
    setState(() => _errorMsg = null);
    if (val.length < 4) return;
    final y = int.tryParse(val) ?? 0;
    if (y > _today.year) {
      _startYearCtrl.text = _today.year.toString();
      _startYearCtrl.selection = TextSelection.collapsed(offset: 4);
      setState(() => _errorMsg = 'سنة البدء لا يمكن أن تتجاوز السنة الحالية (${_today.year})');
      return;
    }
    FocusScope.of(context).unfocus();
  }

  void _onEndYearChanged(String val) {
    setState(() => _errorMsg = null);
    if (val.length == 4) FocusScope.of(context).unfocus();
  }

  // ─── تأكيد ────────────────────────────────────────────────
  void _confirm() {
    final start = _parseDate(_startDayCtrl, _startMonthCtrl, _startYearCtrl);
    final end   = _parseDate(_endDayCtrl, _endMonthCtrl, _endYearCtrl);

    if (start == null) { setState(() => _errorMsg = 'تاريخ البدء غير صالح'); return; }
    if (end == null)   { setState(() => _errorMsg = 'تاريخ الانتهاء غير صالح'); return; }
    if (start.isAfter(DateTime(_today.year, _today.month, _today.day))) {
      setState(() => _errorMsg = 'تاريخ البدء لا يمكن أن يكون بعد اليوم'); return;
    }
    if (start.isAfter(end)) {
      setState(() => _errorMsg = 'تاريخ البدء يجب أن يكون قبل تاريخ الانتهاء'); return;
    }
    Navigator.of(context).pop(DateTimeRange(start: start, end: end));
  }

  DateTime? _parseDate(TextEditingController d, TextEditingController m, TextEditingController y) {
    final day   = int.tryParse(d.text.trim()) ?? 0;
    final month = int.tryParse(m.text.trim()) ?? 0;
    final year  = int.tryParse(y.text.trim()) ?? 0;
    if (day < 1 || day > 31 || month < 1 || month > 12 || year < 2000 || year > 2100) return null;
    try { return DateTime(year, month, day); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accentColor;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(Icons.date_range_rounded, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Text('اختيار الفترة الزمنية',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const SizedBox(height: 20),

            // ── تاريخ البدء ──
            _label('تاريخ البدء', Icons.play_arrow_rounded, Colors.green[700]!),
            const SizedBox(height: 8),
            _dateRow(
              dayCtrl: _startDayCtrl,   dayFocus: _startDayFocus,
              monthCtrl: _startMonthCtrl, monthFocus: _startMonthFocus,
              yearCtrl: _startYearCtrl,   yearFocus: _startYearFocus,
              onDay:   (v) => _onDayChanged(v, _startDayCtrl, _startMonthFocus),
              onMonth: (v) => _onMonthChanged(v, _startMonthCtrl, _startYearFocus, true),
              onYear:  _onStartYearChanged,
              color: color,
            ),
            const SizedBox(height: 16),

            // ── تاريخ الانتهاء ──
            _label('تاريخ الانتهاء', Icons.stop_rounded, Colors.red[700]!),
            const SizedBox(height: 8),
            _dateRow(
              dayCtrl: _endDayCtrl,   dayFocus: _endDayFocus,
              monthCtrl: _endMonthCtrl, monthFocus: _endMonthFocus,
              yearCtrl: _endYearCtrl,   yearFocus: _endYearFocus,
              onDay:   (v) => _onDayChanged(v, _endDayCtrl, _endMonthFocus),
              onMonth: (v) => _onMonthChanged(v, _endMonthCtrl, _endYearFocus, false),
              onYear:  _onEndYearChanged,
              color: color,
            ),

            // ── رسالة الخطأ ──
            if (_errorMsg != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey[300]!),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                    ),
                    child: const Text('تأكيد', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }

  Widget _dateRow({
    required TextEditingController dayCtrl,
    required TextEditingController monthCtrl,
    required TextEditingController yearCtrl,
    required FocusNode dayFocus,
    required FocusNode monthFocus,
    required FocusNode yearFocus,
    required Function(String) onDay,
    required Function(String) onMonth,
    required Function(String) onYear,
    required Color color,
  }) {
    return Row(
      children: [
        Expanded(flex: 2, child: _field(dayCtrl,   dayFocus,   'يوم',  2, onDay,   color)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('/', style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.bold))),
        Expanded(flex: 2, child: _field(monthCtrl, monthFocus, 'شهر',  2, onMonth, color)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('/', style: TextStyle(fontSize: 20, color: color, fontWeight: FontWeight.bold))),
        Expanded(flex: 3, child: _field(yearCtrl,  yearFocus,  'سنة',  4, onYear,  color)),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    FocusNode focus,
    String hint,
    int maxLen,
    Function(String) onChanged,
    Color color,
  ) {
    return TextField(
      controller: ctrl,
      focusNode: focus,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: maxLen,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _ArabicToEnglishFormatter(),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }
}

/// يحول الأرقام العربية إلى إنجليزية
class _ArabicToEnglishFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue nv) {
    final converted = nv.text
      .replaceAll('٠','0').replaceAll('١','1').replaceAll('٢','2')
      .replaceAll('٣','3').replaceAll('٤','4').replaceAll('٥','5')
      .replaceAll('٦','6').replaceAll('٧','7').replaceAll('٨','8')
      .replaceAll('٩','9');
    return nv.copyWith(text: converted);
  }
}
