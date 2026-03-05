// lib/screens/financial_audit_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/firebase_sync/cross_device_verifier.dart';
import '../services/firebase_sync/device_snapshot_service.dart';
import '../services/firebase_sync/discrepancy_resolution_service.dart';

class FinancialAuditScreen extends StatefulWidget {
  const FinancialAuditScreen({super.key});

  @override
  State<FinancialAuditScreen> createState() => _FinancialAuditScreenState();
}

class _FinancialAuditScreenState extends State<FinancialAuditScreen> {
  bool _isVerifying = false;
  VerificationReport? _lastReport;
  String? _statusMessage;

  Future<void> _runVerification() async {
    setState(() {
      _isVerifying = true;
      _statusMessage = 'جاري إعداد لقطة الجهاز...';
      _lastReport = null;
    });

    try {
      // 1. رفع لقطة الجهاز الحالية أولاً
      final snapshotService = DeviceSnapshotService();
      await snapshotService.uploadSnapshot();

      setState(() {
        _statusMessage = 'جاري جلب بيانات الأجهزة الأخرى...';
      });

      // 2. تشغيل التحقق
      final verifier = CrossDeviceVerifier();
      final report = await verifier.runVerification();

      setState(() {
        _lastReport = report;
        _statusMessage = report.totalDiscrepancies == 0
            ? '✅ التدقيق سليم: البيانات متطابقة مع الأجهزة الأخرى'
            : '⚠️ تم العثور على اختلافات!';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Audit'),
        backgroundColor: Colors.indigo,
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
                    const Icon(Icons.security, size: 60, color: Colors.indigo),
                    const SizedBox(height: 16),
                    const Text(
                      'التدقيق المالي المتبادل',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'يقوم هذا النظام بمقارنة إجمالي الديون المسجلة في هذا الجهاز مع ما قامت الأجهزة الأخرى بتسجيله فعلياً، لضمان عدم ضياع أي بيانات.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 24),
                    if (_isVerifying)
                      Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(_statusMessage ?? 'جاري التحقق...'),
                        ],
                      )
                    else
                      Column(
                        children: [
                          if (_statusMessage != null)
                             Container(
                               padding: const EdgeInsets.all(12),
                               decoration: BoxDecoration(
                                 color: _lastReport?.totalDiscrepancies == 0 ? Colors.green[50] : Colors.red[50],
                                 borderRadius: BorderRadius.circular(8),
                                 border: Border.all(
                                   color: _lastReport?.totalDiscrepancies == 0 ? Colors.green : Colors.red,
                                 ),
                               ),
                               child: Text(
                                 _statusMessage!,
                                 style: TextStyle(
                                   color: _lastReport?.totalDiscrepancies == 0 ? Colors.green[800] : Colors.red[800],
                                   fontWeight: FontWeight.bold,
                                 ),
                               ),
                             ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _runVerification,
                            icon: const Icon(Icons.sync_lock),
                            label: const Text('بدء التدقيق اليدوي الآن'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Results List
            if (_lastReport != null && _lastReport!.discrepancies.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '⚠️ الفروقات المكتشفة:',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _lastReport!.discrepancies.length,
                        itemBuilder: (context, index) {
                          final discrepancy = _lastReport!.discrepancies[index];
                          final diff = discrepancy.difference;
                          return Card(
                            color: Colors.red[50],
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const Icon(Icons.warning, color: Colors.red),
                              title: Text(discrepancy.customerName),
                              subtitle: Text(
                                'الجهاز الآخر يدعي: ${discrepancy.remoteClaimedAmount}\nالمسجل لدينا: ${discrepancy.localReceivedAmount}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${diff > 0 ? "+" : ""}${diff.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                                ],
                              ),
                              onTap: () => _resolveDiscrepancy(discrepancy),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              )
            else if (_lastReport != null)
               Expanded(
                 child: Center(
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       const Icon(Icons.check_circle_outline, size: 80, color: Colors.green),
                       const SizedBox(height: 16),
                       Text(
                         'تم فحص ${_lastReport!.totalCustomersChecked} عميل\nجميع البيانات متطابقة تماماً',
                         textAlign: TextAlign.center,
                         style: const TextStyle(fontSize: 16, color: Colors.grey),
                       ),
                     ],
                   ),
                 ),
               ),
          ],
        ),
      ),
    );
  }

  // 🛡️ معالجة الفروقات (مطابق لمنطق CustomerDetailsScreen)
  Future<void> _resolveDiscrepancy(VerificationDiscrepancy discrepancy) async {
    // 1. إظهار مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final service = DiscrepancyResolutionService();
      
      // تحليل العميل باستخدام الـ SyncUUID الموجود في تقرير الفروقات
      // نحتاج الرصيد السحابي وهو موجود بالفعل في التقرير (remoteClaimedAmount)
      
      final assessment = await service.analyzeCustomer(
        discrepancy.customerSyncUuid,
        discrepancy.localReceivedAmount,
        discrepancy.remoteClaimedAmount
      );
      
      if (mounted) Navigator.pop(context); // إخفاء التحميل

      if (!mounted) return;

      if (assessment.type == ResolutionType.none) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('البيانات تبدو سليمة الآن (ربما تم تحديثها)')));
      } else {
        // عرض خيارات الإصلاح
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(children: [Icon(Icons.build_circle, color: Colors.orange), SizedBox(width: 8), Text('معالجة الخلل')]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('العميل: ${discrepancy.customerName}'),
                const SizedBox(height: 8),
                Text(assessment.message),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: Column(
                    children: [
                      Text('محلي: ${discrepancy.localReceivedAmount}'),
                      Text('سحابي: ${discrepancy.remoteClaimedAmount}'),
                      Text('الفرق: ${assessment.discrepancyAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء', style: TextStyle(color: Colors.grey))),
              
              if (assessment.type == ResolutionType.restoreMissing)
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _executeRestoration(service, assessment.missingTransactionUuids);
                  }, 
                  icon: const Icon(Icons.cloud_download),
                  label: Text('استعادة ${assessment.missingTransactionUuids.length} معاملة مفقودة'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                ),
                
              if (assessment.type == ResolutionType.manualCorrection || assessment.type == ResolutionType.restoreMissing)
                 TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                     await _executeManualCorrection(service, discrepancy.customerSyncUuid, assessment.discrepancyAmount);
                  },
                  child: const Text('تصحيح الرصيد يدوياً (Fallback)'),
                ),
            ],
          ),
        );
      }

    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<void> _executeRestoration(DiscrepancyResolutionService service, List<String> uuids) async {
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
      
      final count = await service.restoreMissingTransactions(uuids);
      
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم استعادة $count معاملة بنجاح ✅')));
         // إعادة تشغيل التحقق لتحديث القائمة
         _runVerification();
      }
  }

  Future<void> _executeManualCorrection(DiscrepancyResolutionService service, String customerUuid, double amount) async {
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));
      
      await service.createCorrectionTransaction(customerUuid, amount);
      
      if (mounted) Navigator.pop(context);
      
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تصحيح الرصيد ✅')));
         // إعادة تشغيل التحقق لتحديث القائمة
         _runVerification();
      }
  }
}
