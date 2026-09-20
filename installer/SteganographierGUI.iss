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
DefaultGroupName=隐写者
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
; --- Appearance -----------------------------------------------------------------
; The artwork is the author's own, recovered from the v1.3.9 SFX material: a
; vertical 隐写者 wordmark with the author credit, black on white. The old
; installer's look was a white wizard with that wordmark down the left side, so
; this reproduces it rather than inventing a theme. Both PNGs are committed; the
; repository does not depend on that archive surviving.
;
; Light only, deliberately. Inno's "dynamic" appearance needs a separate asset per
; appearance, but the DynamicDark directives exist for exactly four settings -
; WizardImageBackColor, WizardStyleFile, WizardBackColor and WizardBackImageFile -
; and NOT for WizardImageFile or WizardSmallImageFile. A black wordmark therefore
; cannot adapt to a dark wizard, and following the system theme would render it
; invisible on a dark background.
;
; PNG for these two directives requires Inno Setup 6.6 or later, which is why the
; release workflow upgrades Inno Setup rather than only installing it when absent.
WizardStyle=modern
WizardImageFile=wizard-logo.png
WizardSmallImageFile=wizard-small.png
; Inno Setup 6 defaults DisableWelcomePage to yes, so without this the wizard opens
; on the licence page and the large image (the wordmark) is only ever seen on the
; final page. Measured against the compiled installer, not assumed.
DisableWelcomePage=no
; ShowLanguageDialog defaults to yes, which puts a "Select Language" dialog in front
; of every install. auto shows it only when the UI language matches none of the
; [Languages] entries, so a Chinese system goes straight in as Chinese and an English
; system as English, while any other system can still pick. LanguageDetectionMethod
; is already uilanguage by default and is stated for clarity: it matches the Windows
; UI language Microsoft recommends, not the regional locale.
ShowLanguageDialog=auto
LanguageDetectionMethod=uilanguage
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin

[Languages]
; Both .isl files declare a LanguageID ($0804 for Simplified Chinese, $0409 for
; English), which is what Setup matches against the user's UI language.
Name: "chinesesimp"; MessagesFile: "Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
; AppName is Latin, so the [name] / %1 placeholders would render the Chinese wizard
; with an English product name in the title bar and the welcome heading. Give the
; Chinese language its own wording; English keeps the stock Default.isl strings,
; which already read correctly.
chinesesimp.SetupWindowTitle=安装 - 隐写者
chinesesimp.WelcomeLabel1=欢迎使用 隐写者 安装向导

[CustomMessages]
; [Tasks] descriptions are literal text, so hard-coding them left the English
; wizard showing Chinese task names. Route them through CustomMessages instead, so
; each language supplies its own wording.
chinesesimp.StegAdditionalTasks=附加任务：
english.StegAdditionalTasks=Additional tasks:
chinesesimp.StegTaskContextMenu=安装右键菜单和 steg 命令（推荐）
english.StegTaskContextMenu=Install the right-click menu and the steg command (recommended)
chinesesimp.StegTaskDesktopIcon=创建桌面快捷方式
english.StegTaskDesktopIcon=Create a desktop shortcut

[Tasks]
; v1.3.9 installed the right-click menu and the steg command as part of setup and
; created the desktop shortcut unconditionally; both are default-on here so the
; install experience matches, while staying opt-out.
Name: "contextmenu"; Description: "{cm:StegTaskContextMenu}"; GroupDescription: "{cm:StegAdditionalTasks}"
Name: "desktopicon"; Description: "{cm:StegTaskDesktopIcon}"; GroupDescription: "{cm:StegAdditionalTasks}"

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
// v1.3.9 ran its SFX script commands in this order (per the authoring worksheet
// kept with the old packaging material):
//     02-解除隐写者右键菜单安装.bat   <- clear first
//     01-安装隐写者到右键菜单.bat     <- then install
//     explorer.exe .
// The clear-then-install ordering is restored here: it makes a reinstall
// idempotent and sweeps up leftovers written by older layouts (the uninstaller's
// key list covers the pre-1.3.10 names that this installer never creates). On a
// clean machine it is a no-op, because that script treats an absent key as
// success. Its failure is logged rather than fatal - it must not be able to block
// the installation.
//
// Neither step is a [Run] entry because [Run] ignores a non-zero exit code, which
// would let a failed registration pass silently. The folder is opened with
// ShellExec rather than a [Run] Parameters value so the path is passed as its own
// argument, with no quote-escaping to get wrong for an install path with spaces.
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  InstallRoot: String;
  Arguments: String;
  PowerShell: String;
begin
  if CurStep <> ssPostInstall then
    Exit;

  InstallRoot := ExpandConstant('{app}');
  PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');

  if WizardIsTaskSelected('contextmenu') then
  begin
    Arguments := '-NoProfile -ExecutionPolicy Bypass -File "' + InstallRoot +
                 '\Uninstall-ContextMenu.ps1" -InstallRoot "' + InstallRoot + '"';
    if (not Exec(PowerShell, Arguments, '', SW_HIDE, ewWaitUntilTerminated, ResultCode))
       or (ResultCode <> 0) then
      Log('Context-menu pre-clean exited with code ' + IntToStr(ResultCode) + '; continuing.');

    Arguments := '-NoProfile -ExecutionPolicy Bypass -File "' + InstallRoot +
                 '\Install-ContextMenu.ps1" -InstallRoot "' + InstallRoot + '"';
    if (not Exec(PowerShell, Arguments, '', SW_HIDE, ewWaitUntilTerminated, ResultCode))
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
