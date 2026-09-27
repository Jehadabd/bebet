import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'database_service.dart';

class LocalBackupService {
  
  /// تصدير قاعدة البيانات (النسخ الاحتياطي)
  static Future<bool> backupDatabase() async {
    try {
      // 🛡️ الملف الحي هو ما يفتحه التطبيق فعلاً (مجلد دعم التطبيق)، لا مسار
      // getDatabasesPath القديم. النسخة تُؤخذ بعد دمج WAL وتُفحص سلامتها.
      final tmpDir = await Directory.systemTemp.createTemp('debt_book_export');
      final dbFile = await DatabaseService()
          .createSafeBackup(join(tmpDir.path, 'debt_book_backup.db'));

      // في أندرويد و iOS يفضل استخدام share_plus لمشاركتها لتطبيقات مثل تيليجرام
      // في الويندوز ستعمل كحفظ في الجهاز إذا كان مدعوماً
      if (Platform.isAndroid || Platform.isIOS) {
        final result = await Share.shareXFiles(
          [XFile(dbFile.path, name: 'debt_book_backup.db')],
          text: 'نسخة احتياطية من قاعدة بيانات ديوني',
        );
        return result.status == ShareResultStatus.success || result.status == ShareResultStatus.dismissed;
      } else {
        // للويندوز أو المنصات الأخرى
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'حفظ النسخة الاحتياطية',
          fileName: 'debt_book_backup.db',
          type: FileType.custom,
          allowedExtensions: ['db'],
        );

        if (outputFile != null) {
          await dbFile.copy(outputFile);
          return true;
        }
      }
      return false;
    } catch (e) {
      print('❌ خطأ في النسخ الاحتياطي: $e');
      throw Exception('فشل النسخ الاحتياطي: $e');
    }
  }

  /// استيراد قاعدة البيانات (الاستعادة)
  static Future<bool> restoreDatabase() async {
    try {
      // 1. اختيار الملف
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Any بدلاً من custom لتجاوز مشاكل الأندرويد في اختيار الملفات
        dialogTitle: 'اختر ملف قاعدة البيانات (debt_book.db)',
      );

      if (result != null && result.files.single.path != null) {
        final selectedFilePath = result.files.single.path!;
        final selectedFile = File(selectedFilePath);

        // التحقق من أن الملف تم اختياره
        if (!await selectedFile.exists()) {
          throw Exception('الملف المختار غير موجود');
        }

        // 2. إغلاق قاعدة البيانات الحالية بشكل آمن
        await DatabaseService().closeDatabase();

        // 3. مسار قاعدة البيانات الذي يفتحه التطبيق فعلاً
        final currentDbPath = await DatabaseService().getDatabaseFilePath();
        final currentDbFile = File(currentDbPath);

        // 4. استبدال الملف
        // نحذف القديم (إن وجد) ومعه ملفات WAL/SHM كي لا تُطبَّق على الملف الجديد
        if (await currentDbFile.exists()) {
          await currentDbFile.delete();
        }
        for (final suffix in ['-wal', '-shm']) {
          final f = File('$currentDbPath$suffix');
          if (await f.exists()) {
            await f.delete();
          }
        }
        
        // ننسخ الجديد مكانه
        await selectedFile.copy(currentDbPath);

        // 🛡️ وضع الاستعادة: لا رفع حتى تُقارن النسخة بالسحابة، فلا تُفرض
        // بيانات قديمة على الأجهزة الأخرى.
        await DatabaseService.flagDatabaseRestored();

        print('✅ تم استعادة قاعدة البيانات بنجاح في المسار المخفي!');
        return true;
      }
      return false;
    } catch (e) {
      print('❌ خطأ في استعادة قاعدة البيانات: $e');
      throw Exception('فشل الاستعادة: $e');
    }
  }

  /// إغلاق التطبيق برمجياً لتنظيف الذاكرة بعد الاستعادة
  static void restartApp() {
    if (Platform.isAndroid || Platform.isIOS) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
  }
}
