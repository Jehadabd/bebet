// lib/widgets/report_source_filter_button.dart
import 'package:flutter/material.dart';
import '../services/reports_service.dart';

/// 🔎 زر فلتر مصدر بيانات التقارير: (الكل / هذا الجهاز فقط / من المزامنة فقط).
///
/// يُوضع في شريط شاشات التقارير. عند التغيير يحفظ الاختيار (يبقى بين الجلسات
/// وعبر كل شاشات التقارير لأنه static في ReportsService) ثم يستدعي
/// [onChanged] لإعادة تحميل التقرير بالفلتر الجديد.
class ReportSourceFilterButton extends StatelessWidget {
  final VoidCallback? onChanged;
  const ReportSourceFilterButton({super.key, this.onChanged});

  static const Map<String, String> _labels = {
    'all': 'كل المبيعات',
    'this_device': 'هذا الجهاز فقط',
    'sync': 'من المزامنة فقط',
  };

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.filter_alt_outlined),
      tooltip: 'مصدر بيانات التقرير',
      onSelected: (value) async {
        await ReportsService.setSourceFilter(value);
        onChanged?.call();
      },
      itemBuilder: (context) => [
        for (final entry in _labels.entries)
          PopupMenuItem(
            value: entry.key,
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: ReportsService.reportSourceFilter == entry.key
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                const SizedBox(width: 6),
                Text(entry.value),
              ],
            ),
          ),
      ],
    );
  }
}
