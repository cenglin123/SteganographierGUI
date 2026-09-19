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
Name: "chinesesimp"; MessagesFile: "Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: unchecked

[Files]
; 程序文件：升级时覆盖（ignoreversion）。
; 用户数据绝不覆盖：modules\PW.txt 是真实密码本，config.json / logs 是运行时用户数据。
; 详见 AGENTS.md「Deployment Rules」与 docs/RELEASING.md。
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "config.json,logs\*,modules\PW.txt"; Flags: ignoreversion recursesubdirs createallsubdirs
; 占位密码本只在「目标尚不存在」时安装，且永不随卸载删除——避免升级覆盖真实密码本。
Source: "{#SourceDir}\modules\PW.txt"; DestDir: "{app}\modules"; Flags: onlyifdoesntexist uninsneveruninstall

[Icons]
Name: "{group}\SteganographierGUI"; Filename: "{app}\SteganographierGUI.exe"
Name: "{autodesktop}\SteganographierGUI"; Filename: "{app}\SteganographierGUI.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\SteganographierGUI.exe"; Description: "启动 SteganographierGUI"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; 卸载前先清理右键菜单注册项与 PATH 条目，避免残留（原 .iss 缺此段，卸载后会留注册表垃圾）。
; 实际删除统一走 context-menu\RegistryDeleteSafety.ps1：仅显式允许列表内的键可删，
; 且关键系统根（如 ...\Windows NT\CurrentVersion）一律拒绝。
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\context-menu\Uninstall-ContextMenu.ps1"" -InstallRoot ""{app}"""; Flags: runhidden; RunOnceId: "RemoveContextMenu"
