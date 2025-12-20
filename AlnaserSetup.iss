#define MyAppName "Alnaser"
#define MyAppVersion "1.0"
#define MyAppPublisher "Alnaser Company"
#define MyAppURL "https://www.alnaser.com/"
#define MyAppExeName "debt_book.exe"

[Setup]
; NOTE: The value of AppId uniquely identifies this application. Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
AppId={{9F8425F8-360C-4257-86E5-DFAA3D9D4460}
AppName=Alnaser
AppVersion=1.0
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\Alnaser
DefaultGroupName=Alnaser
UninstallDisplayIcon={app}\debt_book.exe
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=installer_output
OutputBaseFilename=AlnaserSetup
SetupIconFile=assets\icon\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Visual C++ Redistributable - يتم تثبيته تلقائياً إذا لم يكن موجوداً
Source: "installer\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

; ملفات التطبيق
Source: "build\windows\x64\runner\Release\debt_book.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Alnaser"; Filename: "{app}\debt_book.exe"
Name: "{autodesktop}\Alnaser"; Filename: "{app}\debt_book.exe"; Tasks: desktopicon

[Run]
; تثبيت Visual C++ Runtime أولاً (بصمت - لن يظهر للمستخدم إلا إذا احتاج)
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "جاري تثبيت المتطلبات الأساسية..."; Flags: waituntilterminated

; تشغيل التطبيق بعد التثبيت
Filename: "{app}\debt_book.exe"; Description: "{cm:LaunchProgram,Alnaser}"; Flags: nowait postinstall skipifsilent
