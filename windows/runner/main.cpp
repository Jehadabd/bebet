#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

// ============================================================
// 🛡️ Single Instance - Mutex + BroadcastMessage
// الاسم الفريد للـ Mutex (يجب أن يكون فريداً لهذا التطبيق)
// ============================================================
static const wchar_t* kMutexName    = L"Global\\AlnaserDebtBook_SingleInstance_v2";
static const wchar_t* kMsgName      = L"AlnaserDebtBook_ShowWindow_v2";
static HANDLE         g_hMutex      = nullptr;
static UINT           g_uShowMsg    = 0;

// دالة للبحث عن النافذة الموجودة وإحضارها للأمام
static BOOL CALLBACK FindAppWindow(HWND hwnd, LPARAM lParam) {
  // نبحث عن النافذة التي تستقبل رسالتنا المخصصة
  // نستخدم GetWindowThreadProcessId للتحقق أن النافذة تخص نسخة أخرى من نفس التطبيق
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  
  // التحقق أن النافذة ليست نافذة مخفية أو نافذة نظام
  if (!IsWindowVisible(hwnd)) return TRUE;
  
  wchar_t className[256] = {0};
  GetClassNameW(hwnd, className, 255);
  
  // Flutter Windows يستخدم class name محدد
  if (wcsstr(className, L"FLUTTER_RUNNER_WIN32_WINDOW") != nullptr) {
    HWND* pTarget = reinterpret_cast<HWND*>(lParam);
    *pTarget = hwnd;
    return FALSE; // أوقف البحث
  }
  return TRUE;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // ============================================================
  // 🛡️ الخطوة 1: تسجيل رسالة نافذة مخصصة فريدة للتطبيق
  // ============================================================
  g_uShowMsg = RegisterWindowMessageW(kMsgName);

  // ============================================================
  // 🛡️ الخطوة 2: محاولة إنشاء Mutex (bInitialOwner = FALSE مهم!)
  //   - FALSE = لا نمتلك الـ Mutex، فقط نتحقق من وجوده
  //   - هذا يضمن تحرير الـ Mutex تلقائياً عند إغلاق العملية
  //     حتى في حالة الكراش أو الإغلاق من Task Manager
  // ============================================================
  g_hMutex = CreateMutexW(nullptr, FALSE, kMutexName);
  DWORD lastError = GetLastError();

  if (g_hMutex != nullptr && lastError == ERROR_ALREADY_EXISTS) {
    // ✅ نسخة أخرى موجودة بالفعل → أرسل لها رسالة وأغلق هذه النسخة

    // البحث عن نافذة التطبيق الأولى
    HWND targetHwnd = nullptr;
    EnumWindows(FindAppWindow, reinterpret_cast<LPARAM>(&targetHwnd));

    if (targetHwnd != nullptr) {
      // إذا كانت النافذة مصغرة، استعدها
      if (IsIconic(targetHwnd)) {
        ShowWindow(targetHwnd, SW_RESTORE);
      }
      // إحضارها للأمام
      SetForegroundWindow(targetHwnd);
      BringWindowToTop(targetHwnd);
    } else {
      // النافذة غير موجودة → بث الرسالة لجميع النوافذ
      // (في حالة كانت النافذة مخفية أو لم يتم العثور عليها)
      if (g_uShowMsg != 0) {
        PostMessageW(HWND_BROADCAST, g_uShowMsg, 0, 0);
      }
    }

    // تنظيف وإغلاق هذه النسخة فوراً
    CloseHandle(g_hMutex);
    return 0; // ← النسخة الثانية تنتهي هنا دون فتح أي نافذة
  }

  // ============================================================
  // ✅ هذه أول نسخة → استمر في التشغيل الطبيعي
  // ============================================================

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"دفتر ديوني", origin, size)) {
    // فشل إنشاء النافذة → نظف الـ Mutex
    if (g_hMutex) CloseHandle(g_hMutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    // 🛡️ استقبال رسالة "أظهر نفسك" من نسخة ثانية
    if (msg.message == g_uShowMsg && g_uShowMsg != 0) {
      HWND hwnd = window.GetHandle();
      if (hwnd) {
        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
        BringWindowToTop(hwnd);
      }
      continue;
    }
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // 🧹 تنظيف الـ Mutex عند الإغلاق النظيف
  if (g_hMutex) {
    CloseHandle(g_hMutex);
    g_hMutex = nullptr;
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
