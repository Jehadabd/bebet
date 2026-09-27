// lib/screens/invoice_audit_screen.dart
import 'package:flutter/material.dart';
import '../services/firebase_sync/invoice_verifier_service.dart';
import '../services/firebase_sync/invoice_resolution_service.dart';
import '../services/firebase_sync/invoice_snapshot_service.dart';
import '../services/invoice_settings_service.dart';

class InvoiceAuditScreen extends StatefulWidget {
  const InvoiceAuditScreen({super.key});

  @override
  State<InvoiceAuditScreen> createState() => _InvoiceAuditScreenState();
}

class _InvoiceAuditScreenState extends State<InvoiceAuditScreen> {
  bool _isVerifying = false;
  bool _isForcingSync = false;
  List<InvoiceDiscrepancy> _discrepancies = [];
  String? _statusMessage;
  int _totalMismatches = 0;

  @override
  void initState() {
    super.initState();
    // التحقق التلقائي عند فتح الشاشة إذا أردنا، أو انتظار ضغط المستخدم
    _runVerification();
  }

  Future<void> _runVerification() async {
    setState(() {
      _isVerifying = true;
      _statusMessage = 'جاري التقاط حالة الفواتير...';
      _discrepancies = [];
      _totalMismatches = 0;
    });

    try {
      // رفع اللقطة الحالية ليراها الآخرون
      await InvoiceSnapshotService().uploadSnapshot();

      setState(() {
        _statusMessage = 'جاري مقارنة الفواتير مع الأجهزة الأخرى...';
      });

      final verifier = InvoiceVerifierService();
      final results = await verifier.verifyAll();

      int mismatches = 0;
      List<InvoiceDiscrepancy> activeDiscrepancies = [];
      
      for (var d in results) {
        if (d.hasMismatch) {
          mismatches++;
          activeDiscrepancies.add(d);
        }
      }

      setState(() {
        _discrepancies = activeDiscrepancies;
        _totalMismatches = mismatches;
        _statusMessage = mismatches == 0
            ? '✅ التدقيق سليم: فواتيرك متطابقة مع جميع الأجهزة'
            : '⚠️ تم العثور على اختلاف في الفواتير مع $mismatches جهاز!';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ فشل التحقق: $e';
      });
    } finally {
      setState(() {
        _isVerifying = false;
      });
    }
  }

  Future<void> _forceSync() async {
    // تأكيد أخير
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 30),
            SizedBox(width: 8),
            Text('هل أنت متأكد؟'),
          ],
        ),
        content: const Text(
          'أنت على وشك فرض فواتير هذا الجهاز (الحاسوب الصحيح) على جميع الأجهزة الأخرى.\n\nهذا يعني أن الأجهزة الأخرى ستقوم بتحميل فواتير هذا الجهاز لتتطابق معه تماماً.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم، أنا الحاسوب الصحيح (موافق)'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isForcingSync = true;
      _statusMessage = 'جاري فرض المزامنة...';
    });

    try {
      final resolutionService = InvoiceResolutionService();
      
      // إذا كان هناك فواتير معينة ناقصة، يمكن تحديدها. لكن لضمان المطابقة الكاملة، سنرفع جميع الفواتير من هذا الجهاز أو الفواتير الناقصة فقط.
      // نستخدم المكنسة لرفع الفواتير التي لم ترفع.
      
      // سنجمع جميع الـ UUIDs التي فيها خلل (ناقصة أو قديمة عند الآخرين)
      Set<String> uuidsToForce = {};
      for (var d in _discrepancies) {
        uuidsToForce.addAll(d.missingInvoiceUuids);
        uuidsToForce.addAll(d.outdatedInvoiceUuids);
      }

      if (uuidsToForce.isEmpty) {
         // إذا لم يحدد التدقيق الفواتير بدقة، سنقوم بفرض كل الفواتير كخيار آمن
         await resolutionService.forceSyncAllInvoices();
      } else {
         await resolutionService.forceSyncInvoices(uuidsToForce.toList());
      }
      
      // بعد رفعها، نحدث اللقطة الخاصة بنا
      await InvoiceSnapshotService().uploadSnapshot();
      
      // إعادة التدقيق للتأكد من زوال الخطأ
      await _runVerification();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم تعميم بيانات هذا الحاسوب على الأجهزة الأخرى بنجاح.'), backgroundColor: Colors.green),
        );
      }

    } catch (e) {
       setState(() {
        _statusMessage = '❌ فشل فرض المزامنة: $e';
      });
    } finally {
      setState(() {
        _isForcingSync = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مطابقة الفواتير (Invoice Audit)'),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Status Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(Icons.receipt_long, size: 60, color: Colors.teal),
                      const SizedBox(height: 16),
                      const Text(
                        'مطابقة وحل تعارض الفواتير',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'يقوم هذا النظام بمقارنة فواتير هذا الجهاز مع الأجهزة الأخرى. إذا وجدت اختلافاً، يمكنك فرض بيانات "الحاسوب الصحيح" على بقية الأجهزة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      
                      if (_isVerifying || _isForcingSync)
                        Column(
                          children: [
                            const CircularProgressIndicator(color: Colors.teal),
                            const SizedBox(height: 16),
                            Text(_statusMessage ?? 'يرجى الانتظار...', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        )
                      else
                        Column(
                          children: [
                            if (_statusMessage != null)
                               Container(
                                 padding: const EdgeInsets.all(12),
                                 decoration: BoxDecoration(
                                   color: _totalMismatches == 0 ? Colors.green[50] : Colors.red[50],
                                   borderRadius: BorderRadius.circular(8),
                                   border: Border.all(
                                     color: _totalMismatches == 0 ? Colors.green : Colors.red,
                                   ),
                                 ),
                                 child: Text(
                                   _statusMessage!,
                                   style: TextStyle(
                                     color: _totalMismatches == 0 ? Colors.green[800] : Colors.red[800],
                                     fontWeight: FontWeight.bold,
                                   ),
                                   textAlign: TextAlign.center,
                                 ),
                               ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _runVerification,
                                  icon: const Icon(Icons.sync),
                                  label: const Text('إعادة الفحص'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Results List & Resolution Button
              if (!_isVerifying && !_isForcingSync && _totalMismatches > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '⚠️ الأجهزة التي لا تتطابق بياناتها مع بياناتك:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _discrepancies.length,
                          itemBuilder: (context, index) {
                            final d = _discrepancies[index];
                            return Card(
                              color: Colors.red[50],
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.computer, color: Colors.red),
                                title: Text('جهاز رقم: ${d.deviceId}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  'ينقصه ${d.missingInvoiceUuids.length} فاتورة، ولديه ${d.outdatedInvoiceUuids.length} فاتورة قديمة',
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      
                      // زر الفرض
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        child: ElevatedButton.icon(
                          onPressed: _forceSync,
                          icon: const Icon(Icons.upload_file, size: 28),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'فرض بيانات هذا الجهاز على البقية',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'ملاحظة: اضغط هذا الزر فقط إذا كنت تجلس على (الحاسوب الصحيح).',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              else if (!_isVerifying && !_isForcingSync && _totalMismatches == 0)
                 Expanded(
                   child: Center(
                     child: Column(
                       mainAxisAlignment: MainAxisAlignment.center,
                       children: const [
                         Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                         SizedBox(height: 16),
                         Text(
                           'فواتيرك متطابقة تماماً مع جميع الأجهزة الأخرى.',
                           textAlign: TextAlign.center,
                           style: TextStyle(fontSize: 16, color: Colors.grey),
                         ),
                       ],
                     ),
                   ),
                 ),
            ],
          ),
        ),
      ),
    );
  }
}
