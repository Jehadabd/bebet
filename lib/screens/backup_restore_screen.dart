import 'package:flutter/material.dart';
import '../services/local_backup_service.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isLoading = false;
  String _statusMessage = '';

  Future<void> _handleBackup() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري تحضير النسخة الاحتياطية...';
    });

    try {
      final success = await LocalBackupService.backupDatabase();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تصدير النسخة الاحتياطية بنجاح!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل التصدير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
        });
      }
    }
  }

  Future<void> _handleRestore() async {
    // عرض تحذير قبل الاستعادة
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحذير هام جداً ⚠️'),
        content: const Text(
          'استعادة نسخة احتياطية سيؤدي إلى مسح جميع البيانات الحالية في هذا الجهاز واستبدالها بالبيانات الموجودة في الملف.\n\nهل أنت متأكد من رغبتك في المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم، استعادة الآن', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري استيراد قاعدة البيانات...';
    });

    try {
      final success = await LocalBackupService.restoreDatabase();
      if (success) {
        // إظهار رسالة النجاح ثم إغلاق التطبيق
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false, // يمنع إغلاق النافذة
          builder: (context) => AlertDialog(
            title: const Text('نجاح باهر! ✅'),
            content: const Text(
              'تم استعادة البيانات بالكامل بنجاح.\n\nسيتم الآن إغلاق التطبيق برمجياً لتنظيف الذاكرة. يرجى إعادة فتحه من القائمة الرئيسية.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  LocalBackupService.restartApp();
                },
                child: const Text('إغلاق التطبيق الآن'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الاستيراد: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('النسخ الاحتياطي والاستعادة'),
        backgroundColor: Colors.blueAccent,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.security, size: 80, color: Colors.blueAccent),
                const SizedBox(height: 16),
                const Text(
                  'مركز حماية البيانات',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'من هنا يمكنك أخذ نسخة احتياطية لبياناتك بالكامل وإرسالها إلى تيليجرام، أو استعادة نسخة سابقة في حال ضياع الجهاز.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 40),
                
                // زر التصدير
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_file, size: 28),
                  label: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('إنشاء نسخة احتياطية (تصدير)', style: TextStyle(fontSize: 18)),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _handleBackup,
                ),
                
                const SizedBox(height: 24),
                
                // زر الاستيراد
                ElevatedButton.icon(
                  icon: const Icon(Icons.download, size: 28),
                  label: const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('استعادة قاعدة البيانات (استيراد)', style: TextStyle(fontSize: 18)),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _handleRestore,
                ),
              ],
            ),
          ),
          
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_statusMessage, style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
