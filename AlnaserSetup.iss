#define MyAppName "Alnaser"
#define MyAppVersion "1.0"
#define MyAppPublisher "Alnaser Company"
#define MyAppURL "https://www.alnaser.com/"
#define MyAppExeName "mysetup.exe"

[Setup]
; NOTE: The value of AppId uniquely identifies this application. Do not use the same AppId value in installers for other applications.
; (To generate a new GUID, click Tools | Generate GUID inside the IDE.)
AppId={{9F8425F8-360C-4257-86E5-DFAA3D9D4460}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=installer_output
OutputBaseFilename=AlnaserSetup
SetupIconFile=assets\icon\app_icon.ico
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "installer\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer\flutter_secure_storage_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer\pdfium.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer\printing_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent