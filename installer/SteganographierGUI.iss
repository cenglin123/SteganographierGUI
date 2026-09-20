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
; Restore the wizard pages the v1.3.9 RAR SFX carried in its script
; (License=/Text=/TextDone=). Paths are relative to this script's directory,
; matching SetupIconFile above. The three files are build inputs only and are
; not copied into {app}.
LicenseFile=EULA.txt
InfoBeforeFile=BeforeInstall.txt
InfoAfterFile=AfterInstall.txt
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
; v1.3.9 installed the right-click menu and the steg command as part of setup and
; created the desktop shortcut unconditionally; both are default-on here so the
; install experience matches, while staying opt-out.
Name: "contextmenu"; Description: "安装右键菜单和 steg 命令（推荐）"; GroupDescription: "附加任务："
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; v1.3.9 named both shortcuts 隐写者 and used modules\favicon.ico. Its Shortcut=
; lines pointed at a 隐写者.exe that was never shipped, so those shortcuts were
; broken; the target here is the real executable.
Name: "{group}\隐写者"; Filename: "{app}\SteganographierGUI.exe"; IconFilename: "{app}\modules\favicon.ico"
Name: "{autodesktop}\隐写者"; Filename: "{app}\SteganographierGUI.exe"; IconFilename: "{app}\modules\favicon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\SteganographierGUI.exe"; Description: "启动 SteganographierGUI"; Flags: nowait postinstall skipifsilent

[Code]
// v1.3.9 ran InstallElevated.cmd from its SFX script, so registering the
// right-click menu and the steg command was part of installing, and then opened
// the install folder (Setup=explorer.exe .). Both are restored here.
//
// The menu step is not a [Run] entry because [Run] ignores a non-zero exit code,
// which would let a failed registration pass silently. The folder is opened with
// ShellExec rather than a [Run] Parameters value so the path is passed as its own
// argument, with no quote-escaping to get wrong for an install path with spaces.
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  InstallRoot: String;
  Arguments: String;
begin
  if CurStep <> ssPostInstall then
    Exit;

  InstallRoot := ExpandConstant('{app}');

  if WizardIsTaskSelected('contextmenu') then
  begin
    Arguments := '-NoProfile -ExecutionPolicy Bypass -File "' + InstallRoot +
                 '\Install-ContextMenu.ps1" -InstallRoot "' + InstallRoot + '"';

    if (not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
                 Arguments, '', SW_HIDE, ewWaitUntilTerminated, ResultCode))
       or (ResultCode <> 0) then
    begin
      MsgBox('右键菜单安装失败（退出码 ' + IntToStr(ResultCode) + '）。' + #13#10 + #13#10 +
             '程序本体已安装完成，稍后可在程序目录手动运行' + #13#10 +
             '01-安装隐写者到右键菜单.cmd 重新安装右键菜单。',
             mbError, MB_OK);
    end;
  end;

  ShellExec('open', InstallRoot, '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;
