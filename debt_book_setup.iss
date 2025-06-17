[Setup]
AppName=Debt Book
AppVersion=1.0
DefaultDirName={autopf}\Debt Book
DefaultGroupName=Debt Book
UninstallDisplayIcon={app}\debt_book.exe
Compression=lzma
SolidCompression=yes
OutputDir=installer_output
OutputBaseFilename=DebtBookSetup
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "build\windows\x64\runner\Release\debt_book.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Debt Book"; Filename: "{app}\debt_book.exe"
Name: "{autodesktop}\Debt Book"; Filename: "{app}\debt_book.exe"; Tasks: "desktopicon"

[Run]
Filename: "{app}\debt_book.exe"; Description: "{cm:LaunchProgram,Debt Book}"; Flags: nowait postinstall skipifsilent

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked 