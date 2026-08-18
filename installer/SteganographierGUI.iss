#ifndef AppVersion
  #error AppVersion must be supplied with /DAppVersion=x.y.z
#endif
#ifndef SourceDir
  #error SourceDir must be supplied with /DSourceDir=path
#endif
#ifndef OutputDir
  #error OutputDir must be supplied with /DOutputDir=path
#endif

[Setup]
AppId={{A0FB723F-11EF-48D9-917F-2F763B681B11}
AppName=SteganographierGUI
AppVersion={#AppVersion}
AppPublisher=cenglin123
AppPublisherURL=https://github.com/cenglin123/SteganographierGUI
AppSupportURL=https://github.com/cenglin123/SteganographierGUI/issues
DefaultDirName={autopf}\SteganographierGUI
DefaultGroupName=SteganographierGUI
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=SteganographierGUI_v{#AppVersion}_installer
SetupIconFile=..\modules\favicon.ico
UninstallDisplayIcon={app}\modules\favicon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\SteganographierGUI"; Filename: "{app}\SteganographierGUI.exe"
Name: "{autodesktop}\SteganographierGUI"; Filename: "{app}\SteganographierGUI.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\SteganographierGUI.exe"; Description: "启动 SteganographierGUI"; Flags: nowait postinstall skipifsilent
