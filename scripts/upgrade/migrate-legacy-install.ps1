#requires -Version 5.1
<#
.SYNOPSIS
    将本机 v1.3.8.x 旧安装（WinRAR 自解压手放，无卸载项）升级为由官方 Inno 安装包管理的 v1.3.10。
.NOTES
    由仓库 docs/RELEASING.md「Upgrading a machine installed by the legacy SFX method」流程生成。
    运行方式：右键『以管理员身份运行』本 .cmd，或在提升的 PowerShell 中执行本 .ps1。
    每一步失败即停；旧程序目录只改名不删除，验证通过后可手动清理。
    前置快照已存在于 D:\Media\_archive\programfiles-runtime-snapshot-20260912（含 SHA256MANIFEST.txt）。
#>
$ErrorActionPreference = 'Stop'

# 宿主自愈：本机 PATH 含大量第三方目录，双击运行时若被非 System32 的 powershell.exe 劫持，
# 会出现 cmdlet 缺失等怪症。检测到即自动切换到权威宿主重新执行。
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    $authoritativeHost = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $currentHost = if ($PSHome) { Join-Path $PSHome 'powershell.exe' } else { '' }
    if ($currentHost -and (Test-Path -LiteralPath $authoritativeHost)) {
        $same = $false
        try { $same = (Resolve-Path $authoritativeHost).Path -ieq (Resolve-Path $currentHost).Path } catch {}
        if (-not $same) {
            Write-Warning "当前宿主 PSHome=$PSHome 非系统 PowerShell，切换权威宿主重跑……"
            & $authoritativeHost -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
            exit $LASTEXITCODE
        }
    }
}

# PSModulePath 自愈：从 pwsh7 等父进程继承的模块路径含不存在/不兼容目录时，5.1 的按需
# 自动加载会静默失效（Get-FileHash 等核心 cmdlet 消失）。以注册表权威值重建并过滤死路径。
$sysModules = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
$mpParts = @(
    (Get-ItemProperty 'HKCU:\Environment' -EA SilentlyContinue).PSModulePath,
    (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment' -EA SilentlyContinue).PSModulePath,
    $sysModules
) | Where-Object { $_ } | ForEach-Object { $_ -split ';' } | Where-Object { $_ -and (Test-Path $_) }
$env:PSModulePath = ($mpParts | Select-Object -Unique) -join ';'

# 核心 cmdlet 缺失时先显式加载模块，仍失败则给出可执行指引。
foreach ($needed in @('Get-FileHash', 'Start-Process', 'Rename-Item')) {
    if (-not (Get-Command $needed -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.PowerShell.Utility, Microsoft.PowerShell.Management -ErrorAction SilentlyContinue
    }
    if (-not (Get-Command $needed -ErrorAction SilentlyContinue)) {
        throw "缺少 cmdlet '$needed'（PSHome=$PSHome，PSModulePath=$env:PSModulePath）。请 Win+R 输入 powershell 回车打开系统 PowerShell，set-location 到本目录后运行 .\migrate-legacy-install.ps1（管理员）。"
    }
}

# robocopy 预解析绝对路径（32/64 位视图下裸名解析可能失败）
$RoboCopy = @(
    (Join-Path $env:SystemRoot 'System32\robocopy.exe'),
    (Join-Path $env:SystemRoot 'Sysnative\robocopy.exe'),
    (Join-Path $env:SystemRoot 'SysWOW64\robocopy.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $RoboCopy) { throw '找不到 robocopy.exe。' }

# robocopy 输出走 stdout，在 EAP=Stop 下统一经 cmd.exe 合并 stderr；退出码 0-7 为成功族。
function Invoke-RobocopyMirror {
    param([string]$Source, [string]$Destination)
    $out = & cmd.exe /c "`"$RoboCopy`" `"$Source`" `"$Destination`" /E /R:1 /W:1 /NFL /NDL /NP /NJH /NJS 2>&1"
    $code = $LASTEXITCODE
    if ($code -ge 8) { throw "robocopy '$Source' -> '$Destination' failed with exit $code : $(($out | Out-String).Trim())" }
    return $code
}

# ===== 可调参数 =====
$InstallDir   = 'C:\Program Files\SteganographierGUI'
$OldName      = 'C:\Program Files\SteganographierGUI.old-1382'
$SetupExe     = 'D:\Media\releases\SteganographierGUI_v1.3.10_installer.exe'
$SetupSha256  = 'c0b1ebcb05310863543f0e1751e42e20e2108038863ccb9831503678a1b3d1ba'
# context-menu 脚本所在仓库：由本脚本自身位置推导（scripts\upgrade\ → 仓库根），不硬编码个人路径。
$RepoRoot     = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'context-menu\Uninstall-ContextMenu.ps1'))) {
    throw "推导出的仓库根缺少 context-menu\Uninstall-ContextMenu.ps1：$RepoRoot。请将本脚本保留在仓库 scripts\upgrade\ 目录下运行。"
}
$Snapshot     = 'D:\Media\_archive\programfiles-runtime-snapshot-20260912\SteganographierGUI'

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '请以管理员身份运行本脚本。'
    }
}

function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

Assert-Admin

# --- 0. 校验安装包哈希 ---
Step '校验官方安装包 SHA-256'
if (-not (Test-Path -LiteralPath $SetupExe)) {
    throw "安装包不存在：$SetupExe（可能又被 Defender 拦截；确认 D:\Media\releases 在排除列表中后重新下载）"
}
if ((Get-FileHash -LiteralPath $SetupExe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $SetupSha256) {
    throw "安装包哈希与 GitHub Release v1.3.10 的 SHA256SUMS.txt 不符：$SetupExe"
}

# --- 1. 二次备份运行时用户数据（即便已有整目录快照，也再拉一份最新的） ---
Step '备份 PW.txt / config.json / logs 到时间戳目录'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bak = Join-Path (Split-Path -Parent $Snapshot) "runtime-latest-$stamp"
foreach ($item in @('modules\PW.txt', 'config.json')) {
    $src = Join-Path $InstallDir $item
    if (Test-Path -LiteralPath $src) {
        $dst = Join-Path $bak $item
        New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
}
if (Test-Path -LiteralPath (Join-Path $InstallDir 'logs')) {
    $null = Invoke-RobocopyMirror (Join-Path $InstallDir 'logs') (Join-Path $bak 'logs')
}
Write-Host "    备份位置：$bak"

# --- 2. 卸旧右键菜单（趁文件还在，Uninstall 脚本能完整清 PATH/steg.cmd） ---
Step '运行 Uninstall-ContextMenu.ps1（旧注册表清理）'
& (Join-Path $RepoRoot 'context-menu\Uninstall-ContextMenu.ps1') -InstallRoot $InstallDir

# --- 3. 清理卸载脚本覆盖不到的残留（HKCR 双根 + WOW CommandStore + 悬空关联） ---
Step '清理注册表残留'
$extraKeys = @(
    # 旧体系悬空 ProgID / 扩展名关联（任何现行脚本都不管，评审 R3-F5）
    'HKLM\SOFTWARE\Classes\SteganographierFile',
    'HKLM\SOFTWARE\Classes\.steg',
    'HKCU\Software\Classes\SteganographierFile',
    'HKCU\Software\Classes\.steg',
    # 旧自解压 bat 曾写过的假卸载项（如存在）
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SteganographierGUI',
    # WOW64 视图孤儿 CommandStore（Install/Uninstall 均不覆盖此视图）
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\hideMp4',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\hideMkv',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\modifyHash',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\openHashModifier',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\reveal',
    # 老命名遗留（本机实测存在，现行 Uninstall 清单没有它）
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealFile',
    # HKCR 联合视图写入可能分裂到 HKCU 镜像，一并清掉；随后 Install 以 HKLM 权威重建
    'HKCU\Software\Classes\*\shell\Steganographier',
    'HKCU\Software\Classes\Directory\shell\Steganographier',
    'HKCU\Software\Classes\Directory\Background\shell\openSteganographier',
    # HKLM 主菜单键显式删一遍（Uninstall 走 HKCR 通配符，行为随 UAC 配置漂移）
    'HKLM\SOFTWARE\Classes\*\shell\Steganographier',
    'HKLM\SOFTWARE\Classes\Directory\shell\Steganographier',
    'HKLM\SOFTWARE\Classes\Directory\Background\shell\openSteganographier'
)
# 原生 stderr 陷阱：PS 5.1 在外层 EAP=Stop 下，任何对原生命令 stderr 的捕获（2>$null、
# 2>&1、2>file）都会升级为终止性异常。统一经 cmd.exe 内部把 stderr 合并进 stdout 规避。
$RegExe = Join-Path $env:SystemRoot 'System32\reg.exe'
if (-not (Test-Path -LiteralPath $RegExe)) { throw '找不到 reg.exe。' }

foreach ($k in $extraKeys) {
    $leaf = ($k -split '\\')[-1]
    $parentLeaf = ($k -split '\\')[-2]
    $view = if ($k -match 'WOW6432Node') {'wow'} else {'x64'}
    & cmd.exe /c "`"$RegExe`" export `"$k`" `"$bak\reg-backup-$view-$parentLeaf--$leaf.reg`" /y >nul 2>&1" | Out-Null
    $exported = $LASTEXITCODE -eq 0
    $delOut = & cmd.exe /c "`"$RegExe`" delete `"$k`" /f 2>&1"
    $code = $LASTEXITCODE
    $text = ($delOut | Out-String)
    # reg.exe exit 1 有歧义（"找不到键"与真错误同为 1），以合并后的文本判定：
    if ($text -match 'unable to find|找不到') {
        $status = 'absent/skip'
    } elseif ($code -eq 0) {
        $status = 'deleted'
    } elseif ($exported) {
        throw "reg delete failed for '$k' (exit $code): $text"
    } else {
        $status = 'absent/skip'
    }
    Write-Host ("    {0} : {1}" -f $k, $status)
    $global:LASTEXITCODE = 0
}

# --- 4. 修 User PATH（Uninstall 只管 Machine PATH） ---
Step '从 User PATH 移除旧 tools 目录'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $kept = @($userPath -split ';' | Where-Object { $_.Trim().Trim('"').TrimEnd('\') -ine (Join-Path $InstallDir 'tools') })
    $newVal = $kept -join ';'
    if ($newVal -ne $userPath) {
        # 必须走 PowerShell 直写注册表：cmd.exe 会把值里的 %VAR% 先展开再传给 reg.exe，
        # 破坏 REG_EXPAND_SZ 语义。Set-ItemProperty 指定 ExpandString 类型可保真。
        Set-ItemProperty -LiteralPath 'HKCU:\Environment' -Name Path -Value $newVal -Type ExpandString
        $check = (Get-Item 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
        if ($check -cne $newVal) { throw 'User PATH 写入后校验不一致。' }
        Write-Host '    User PATH 已更新（保持 REG_EXPAND_SZ 类型）'
    } else { Write-Host '    User PATH 无需改动' }
}

# --- 5. 旧目录改名让位 ---
Step "重命名旧安装目录 -> $OldName"
if (Test-Path -LiteralPath $OldName) { throw "$OldName 已存在，先手工处理它再重跑。" }
if (Test-Path -LiteralPath $InstallDir) { Rename-Item -LiteralPath $InstallDir -NewName (Split-Path -Leaf $OldName) }

# --- 6. 静默全新安装 ---
Step '运行官方 v1.3.10 安装包（静默）'
if (-not (Test-Path -LiteralPath $SetupExe)) { throw "安装包不存在：$SetupExe" }
$p = Start-Process -FilePath $SetupExe -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait -PassThru
if ($p.ExitCode -ne 0) {
    # 回滚：把旧目录改回去，保证机器可用
    if ((Test-Path -LiteralPath $OldName) -and -not (Test-Path -LiteralPath $InstallDir)) {
        Rename-Item -LiteralPath $OldName -NewName (Split-Path -Leaf $InstallDir)
        Write-Warning 'installer 失败，已自动把旧目录改回原位（右键菜单尚未恢复，可重跑本脚本）。'
    }
    throw "installer 退出码 $($p.ExitCode)。"
}

# --- 7. 迁移运行时用户数据（安装包里的是占位符，必须覆盖回去） ---
Step '迁移 PW.txt / config.json / logs 到新安装'
foreach ($item in @('modules\PW.txt', 'config.json')) {
    $src = Join-Path $bak $item
    if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $item) -Force; Write-Host "    restored: $item" }
}
if (Test-Path -LiteralPath (Join-Path $bak 'logs')) {
    $null = Invoke-RobocopyMirror (Join-Path $bak 'logs') (Join-Path $InstallDir 'logs')
    Write-Host '    restored: logs\'
}

# --- 8. 重装右键菜单（新路径、新 exe 名） ---
Step '运行 Install-ContextMenu.ps1'
& (Join-Path $RepoRoot 'context-menu\Install-ContextMenu.ps1') -InstallRoot $InstallDir

# --- 8b. 刷新 Explorer，让新右键菜单立即生效（HKCR shell 变更默认要重启才可见） ---
Stop-Process -Name explorer -Force -EA SilentlyContinue   # Explorer 自动重启，任务栏会闪一下

# --- 9. 修快捷方式指向新 exe ---
Step '修正桌面/开始菜单快捷方式'
$wsh = New-Object -ComObject WScript.Shell
$links = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) '隐写者.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\SteganographierGUI.lnk')
)
foreach ($lnk in $links) {
    if (Test-Path -LiteralPath $lnk) {
        $sc = $wsh.CreateShortcut($lnk)
        $sc.TargetPath = Join-Path $InstallDir 'SteganographierGUI.exe'
        $sc.WorkingDirectory = $InstallDir
        $sc.IconLocation = (Join-Path $InstallDir 'modules\favicon.ico')
        $sc.Save(); Write-Host "    fixed: $lnk"
    }
}

# --- 10. 冒烟验证 ---
Step '冒烟验证'
$newExe = Join-Path $InstallDir 'SteganographierGUI.exe'
if (-not (Test-Path -LiteralPath $newExe)) { throw '新主程序不存在！' }
$ver = (& cmd.exe /c "`"$newExe`" --version 2>&1" | Out-String).Trim()
Write-Host "    exe --version => $ver"
if ($ver -notmatch '1\.3\.10') { throw '版本输出不含 1.3.10' }
$pwSize = (Get-Item -LiteralPath (Join-Path $InstallDir 'modules\PW.txt')).Length
if ($pwSize -lt 1000) { throw "PW.txt 疑似被占位符覆盖（仅 $pwSize 字节）！检查第 7 步。" }
Write-Host "    PW.txt = $pwSize 字节（真密码本完好）"
$uninsKey = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall' | ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object { $_.DisplayName -like '*Steganographier*' }
if (-not $uninsKey) { throw '控制面板卸载项缺失——installer 未正常登记？' }
Write-Host "    卸载项存在：$($uninsKey.DisplayVersion)"

Step '全部完成。'
Write-Host @"
后续人工动作：
  1. 打开资源管理器实测右键菜单（文件/文件夹空白处），确认 hide/reveal/hash 各项可用；
  2. 新开一个终端试 'steg --help'（PATH 刷新需要新进程）；
  3. 一切正常后，删除回退点：Remove-Item '$OldName' -Recurse -Force
"@ -ForegroundColor Yellow
