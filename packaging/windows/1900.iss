#define MyAppName "1900"
#define MyAppPublisher "1900 Project"
#define MyAppVersion "0.001A"
#define MyAppExeName "wwo-p0-demo.exe"

[Setup]
AppId={{A77A76ED-71DE-4CA8-884C-1900001A0001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\1900
DefaultGroupName=1900
DisableProgramGroupPage=yes
OutputDir=..\..\builds\installer
OutputBaseFilename=1900-Prototype-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}
VersionInfoVersion=0.0.1.0
VersionInfoProductName=1900
VersionInfoDescription=1900 Prototype Installer

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\..\builds\windows\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\1900"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\1900"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 1900"; Flags: nowait postinstall skipifsilent
