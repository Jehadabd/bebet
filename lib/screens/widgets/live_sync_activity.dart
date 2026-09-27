// lib/screens/widgets/live_sync_activity.dart
//
// 🩺 + 📊 + 📜 مكوّنات الواجهة الحية:
//   - LiveFirebaseHealthCard: بطاقة صحة Firebase (قراءة/كتابة/زمن الاستجابة)
//   - LiveSyncProgressBar: شريط تقدّم حقيقي مبني على أحداث Bus
//   - LiveSyncActivityLog: سجل أحداث المزامنة بأسلوب التيرمينال (لحظي)
//
// كلها Stateful وتشترك مباشرةً في SyncEventBus و FirebaseHealthMonitor.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/firebase_sync/sync_event_bus.dart';
import '../../services/firebase_sync/firebase_health_monitor.dart';

/// ═══════════════════════════════════════════════════════════════════════════
/// 🩺 بطاقة صحة Firebase (قراءة/كتابة/زمن استجابة)
/// ═══════════════════════════════════════════════════════════════════════════
class LiveFirebaseHealthCard extends StatefulWidget {
  const LiveFirebaseHealthCard({super.key});

  @override
  State<LiveFirebaseHealthCard> createState() => _LiveFirebaseHealthCardState();
}

class _LiveFirebaseHealthCardState extends State<LiveFirebaseHealthCard> {
  StreamSubscription<FirebaseHealthResult>? _sub;
  FirebaseHealthResult _current =
      FirebaseHealthMonitor.instance.lastResult;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseHealthMonitor.instance.healthStream.listen((result) {
      if (mounted) setState(() => _current = result);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _current;
    final color = _colorForState(r.state);
    final icon = _iconForState(r.state);
    final label = r.shortLabel;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('صحة Firebase',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      Text(
                        label,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                            fontSize: 15),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'فحص الآن',
                  onPressed: () =>
                      FirebaseHealthMonitor.instance.checkNow(source: 'user'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip('شبكة', r.hasNetwork),
                _chip('مصادقة', r.isAuthenticated),
                _chip('قراءة', r.canRead),
                _chip('كتابة', r.canWrite),
                _chip('تحقق nonce', r.nonceMatched),
              ],
            ),
            if (r.latency != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.speed, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text('زمن الاستجابة: ${r.latency!.inMilliseconds}ms',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                  const Spacer(),
                  Text(
                    'آخر فحص: ${_formatTime(r.checkedAt)}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
            if (r.errorDetails != null) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  r.errorDetails!,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.red, fontFamily: 'monospace'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool ok) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel,
              size: 12, color: ok ? Colors.green : Colors.red),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: ok ? Colors.green.shade800 : Colors.red.shade800)),
        ],
      ),
    );
  }

  static Color _colorForState(FirebaseHealthState s) {
    switch (s) {
      case FirebaseHealthState.healthy:
        return Colors.green;
      case FirebaseHealthState.checking:
      case FirebaseHealthState.unknown:
        return Colors.grey;
      default:
        return Colors.red;
    }
  }

  static IconData _iconForState(FirebaseHealthState s) {
    switch (s) {
      case FirebaseHealthState.healthy:
        return Icons.cloud_done;
      case FirebaseHealthState.checking:
      case FirebaseHealthState.unknown:
        return Icons.cloud_sync;
      default:
        return Icons.cloud_off;
    }
  }

  static String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

/// ═══════════════════════════════════════════════════════════════════════════
/// 📊 شريط تقدّم حقيقي مبني على SyncProgressSnapshot
/// ═══════════════════════════════════════════════════════════════════════════
class LiveSyncProgressBar extends StatefulWidget {
  final EdgeInsetsGeometry padding;
  const LiveSyncProgressBar({super.key, this.padding = const EdgeInsets.all(12)});

  @override
  State<LiveSyncProgressBar> createState() => _LiveSyncProgressBarState();
}

class _LiveSyncProgressBarState extends State<LiveSyncProgressBar> {
  StreamSubscription<SyncProgressSnapshot>? _sub;
  SyncProgressSnapshot _snapshot = SyncEventBus.instance.currentProgress;

  @override
  void initState() {
    super.initState();
    _sub = SyncEventBus.instance.progressStream.listen((s) {
      if (mounted) setState(() => _snapshot = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _snapshot;
    final progress = s.progress;
    final hasProgress = s.currentIndex != null && s.totalItems != null;

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.currentMessage ?? 'لا توجد عملية جارية',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasProgress) ...[
                const SizedBox(width: 8),
                Text(
                  '${s.currentIndex}/${s.totalItems}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '${((progress ?? 0) * 100).toInt()}%',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.deepOrange,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.deepOrange),
            ),
          ),
          if (s.errorCount > 0 || s.warningCount > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (s.errorCount > 0)
                  _countBadge(s.errorCount, Colors.red, Icons.error),
                if (s.errorCount > 0 && s.warningCount > 0)
                  const SizedBox(width: 6),
                if (s.warningCount > 0)
                  _countBadge(s.warningCount, Colors.orange, Icons.warning),
                const Spacer(),
                Text(
                  'إجمالي الأحداث: ${s.totalEvents}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _countBadge(int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 2),
          Text('$count',
              style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

/// ═══════════════════════════════════════════════════════════════════════════
/// 📜 سجل أحداث حيّ (مثل التيرمينال بالضبط)
/// ═══════════════════════════════════════════════════════════════════════════
class LiveSyncActivityLog extends StatefulWidget {
  final double height;
  final int maxEvents;
  final bool showFilters;

  const LiveSyncActivityLog({
    super.key,
    this.height = 320,
    this.maxEvents = 200,
    this.showFilters = true,
  });

  @override
  State<LiveSyncActivityLog> createState() => _LiveSyncActivityLogState();
}

class _LiveSyncActivityLogState extends State<LiveSyncActivityLog> {
  StreamSubscription<SyncEvent>? _sub;
  final List<SyncEvent> _events = [];

  // فلاتر
  bool _showDebug = false; // افتراضياً نخفي الـ debug (كثير جداً)
  bool _showInfo = true;
  bool _showSuccess = true;
  bool _showWarning = true;
  bool _showError = true;
  bool _autoScroll = true;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _events.addAll(SyncEventBus.instance.recentEvents);
    _sub = SyncEventBus.instance.stream.listen((e) {
      if (!mounted) return;
      setState(() {
        _events.add(e);
        while (_events.length > widget.maxEvents) {
          _events.removeAt(0);
        }
      });
      if (_autoScroll) _scrollToBottom();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  bool _shouldShow(SyncEvent e) {
    switch (e.level) {
      case SyncEventLevel.debug:
        return _showDebug;
      case SyncEventLevel.info:
        return _showInfo;
      case SyncEventLevel.success:
        return _showSuccess;
      case SyncEventLevel.warning:
        return _showWarning;
      case SyncEventLevel.error:
        return _showError;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _events.where(_shouldShow).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal, size: 18),
                const SizedBox(width: 6),
                const Text('السجل الحيّ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('${visible.length}/${_events.length}',
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(width: 8),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  icon: Icon(_autoScroll
                      ? Icons.vertical_align_bottom
                      : Icons.vertical_align_center),
                  tooltip: _autoScroll ? 'إيقاف التمرير التلقائي' : 'تشغيل التمرير التلقائي',
                  onPressed: () =>
                      setState(() => _autoScroll = !_autoScroll),
                  iconSize: 18,
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  icon: const Icon(Icons.copy),
                  tooltip: 'نسخ السجل',
                  iconSize: 18,
                  onPressed: () async {
                    final text =
                        SyncEventBus.instance.exportAsText(maxLines: 200);
                    await Clipboard.setData(ClipboardData(text: text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('تم نسخ السجل إلى الحافظة')),
                      );
                    }
                  },
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'مسح السجل المعروض',
                  iconSize: 18,
                  onPressed: () {
                    setState(() => _events.clear());
                  },
                ),
              ],
            ),
            if (widget.showFilters)
              SizedBox(
                height: 30,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _filterChip('نجاح', Colors.green, _showSuccess,
                        (v) => setState(() => _showSuccess = v)),
                    _filterChip('معلومات', Colors.blue, _showInfo,
                        (v) => setState(() => _showInfo = v)),
                    _filterChip('تحذير', Colors.orange, _showWarning,
                        (v) => setState(() => _showWarning = v)),
                    _filterChip('خطأ', Colors.red, _showError,
                        (v) => setState(() => _showError = v)),
                    _filterChip('تشخيصي', Colors.grey, _showDebug,
                        (v) => setState(() => _showDebug = v)),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: ListView.builder(
                controller: _scroll,
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final e = visible[i];
                  return _EventLine(event: e);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, Color color, bool selected,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: FilterChip(
        label: Text(label,
            style:
                TextStyle(fontSize: 10, color: selected ? Colors.white : color)),
        selected: selected,
        onSelected: onChanged,
        selectedColor: color,
        checkmarkColor: Colors.white,
        backgroundColor: color.withOpacity(0.1),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 2),
      ),
    );
  }
}

/// خط واحد داخل السجل — يشبه سطر التيرمينال
class _EventLine extends StatelessWidget {
  final SyncEvent event;
  const _EventLine({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = _colorForLevel(event.level);
    final t = event.timestamp;
    final ts =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    final indicator = _indicatorForLevel(event.level);
    final hasProgress =
        event.currentIndex != null && event.totalItems != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.white70),
          children: [
            TextSpan(
                text: '$ts ',
                style: const TextStyle(color: Colors.white38)),
            TextSpan(text: '$indicator  ', style: TextStyle(color: color)),
            TextSpan(text: event.message, style: TextStyle(color: color)),
            if (hasProgress)
              TextSpan(
                text: '  (${event.currentIndex}/${event.totalItems})',
                style: const TextStyle(color: Colors.white54),
              ),
          ],
        ),
      ),
    );
  }

  static Color _colorForLevel(SyncEventLevel level) {
    switch (level) {
      case SyncEventLevel.debug:
        return Colors.white38;
      case SyncEventLevel.info:
        return Colors.lightBlueAccent;
      case SyncEventLevel.success:
        return Colors.greenAccent;
      case SyncEventLevel.warning:
        return Colors.orangeAccent;
      case SyncEventLevel.error:
        return Colors.redAccent;
    }
  }

  static String _indicatorForLevel(SyncEventLevel level) {
    switch (level) {
      case SyncEventLevel.debug:
        return '·';
      case SyncEventLevel.info:
        return 'ℹ️';
      case SyncEventLevel.success:
        return '✅';
      case SyncEventLevel.warning:
        return '⚠️';
      case SyncEventLevel.error:
        return '❌';
    }
  }
}
