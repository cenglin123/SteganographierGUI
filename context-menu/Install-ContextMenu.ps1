[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
)

$ErrorActionPreference = "Stop"
$installDirectory = [IO.Path]::GetFullPath($InstallRoot).TrimEnd("\")
$toolsDirectory = Join-Path $installDirectory "tools"
$program = Get-ChildItem -LiteralPath $installDirectory -Filter "SteganographierGUI*.exe" -File |
    Select-Object -First 1

if (-not $program) {
    throw "SteganographierGUI executable was not found in '$installDirectory'."
}

$hashModifier = Join-Path $toolsDirectory "hash_modifier.exe"
$selectionLauncher = Join-Path $toolsDirectory "launch_from_selection.ps1"
$icon = Join-Path $installDirectory "modules\favicon.ico"
# v1.3.9 gave the two hash entries their own icon; the file is still shipped but
# had stopped being referenced, so the menu showed the generic application icon.
$hashIcon = Join-Path $installDirectory "modules\favicon_hash_modifier.ico"
foreach ($requiredFile in @($hashModifier, $selectionLauncher, $icon, $hashIcon)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required context-menu file is missing: $requiredFile"
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# v1.3.9 broadcast WM_SETTINGCHANGE so already-running shells and Explorer pick the
# new PATH up; the vendor-specific `rundll32 user32.dll,UpdatePerUserSystemParameters`
# that replaced it does not, so a machine PATH edit stayed invisible until reboot or
# re-login. Restored here (and duplicated in Uninstall-ContextMenu.ps1, matching how
# Test-Administrator is already shared between the two).
function Send-EnvironmentChangeBroadcast {
    if (-not ([System.Management.Automation.PSTypeName]'NativeMethods').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class NativeMethods {
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, int Msg, UIntPtr wParam,
        string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
"@
    }
    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1A
    $SMTO_ABORTIFHUNG = 0x0002
    $result = [IntPtr]::Zero
    $null = [NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE,
        [UIntPtr]::Zero, 'Environment', $SMTO_ABORTIFHUNG, 5000, [ref]$result)
}

# Set-RegistryString lives in RegistryWrite.ps1 so the shipping implementation can
# be dot-sourced and round-trip tested against scratch keys instead of being
# re-implemented (a copy can drift, and did: the v1.3.10 form broke on every path).
. (Join-Path $PSScriptRoot "RegistryWrite.ps1")

if (-not $WhatIfPreference -and -not (Test-Administrator)) {
    throw "Run this script as administrator."
}

$programPath = $program.FullName
$stegLauncher = Join-Path $toolsDirectory "steg.cmd"
$launcherContent = "@echo off`r`n`"%~dp0..\$($program.Name)`" %*`r`n"
if ($PSCmdlet.ShouldProcess($stegLauncher, "Create command launcher")) {
    [IO.File]::WriteAllText($stegLauncher, $launcherContent, (New-Object Text.ASCIIEncoding))
}

$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$pathEntries = @($machinePath -split ";" | Where-Object { $_.Trim() })
$normalizedTools = $toolsDirectory.TrimEnd("\")
$pathExists = $pathEntries | Where-Object {
    ([Environment]::ExpandEnvironmentVariables($_.Trim().Trim('"')).TrimEnd("\")) -ieq $normalizedTools
}
if (-not $pathExists -and $PSCmdlet.ShouldProcess($toolsDirectory, "Add tools directory to the machine PATH")) {
    $newMachinePath = (@($pathEntries) + $toolsDirectory) -join ";"
    # SetEnvironmentVariable writes REG_SZ and silently downgrades a REG_EXPAND_SZ Path.
    # Preserve the original value kind (and %VAR% tokens) by writing the key directly.
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $kind = (Get-Item $key).GetValueKind('Path')
    Set-ItemProperty -LiteralPath $key -Name Path -Value $newMachinePath -Type $kind
    Send-EnvironmentChangeBroadcast
}

$commandStore = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell"
$fileMenu = "HKCR\*\shell\Steganographier"
$directoryMenu = "HKCR\Directory\shell\Steganographier"
$backgroundMenu = "HKCR\Directory\Background\shell\openSteganographier"

Set-RegistryString -Key $fileMenu -Name "MUIVerb" -Value "Steganographier" -WhatIf:$WhatIfPreference
Set-RegistryString -Key $fileMenu -Name "SubCommands" -Value "hideMp4;hideMkv;revealFileCLI;revealFileGUI;modifyHash;openHashModifier" -WhatIf:$WhatIfPreference
Set-RegistryString -Key $fileMenu -Name "Icon" -Value $programPath -WhatIf:$WhatIfPreference
Set-RegistryString -Key $directoryMenu -Name "MUIVerb" -Value "Steganographier" -WhatIf:$WhatIfPreference
Set-RegistryString -Key $directoryMenu -Name "SubCommands" -Value "hideMp4;hideMkv;revealDir;modifyHash;openHashModifier" -WhatIf:$WhatIfPreference
Set-RegistryString -Key $directoryMenu -Name "Icon" -Value $programPath -WhatIf:$WhatIfPreference

$commands = @(
    @{ Name = "hideMp4"; Label = "隐写为MP4文件(无密码)"; Command = ('"{0}" -i "%1" -o "%1_hidden.mp4" -t mp4' -f $programPath) },
    @{ Name = "hideMkv"; Label = "隐写为MKV文件(无密码)"; Command = ('"{0}" -i "%1" -o "%1_hidden.mkv" -t mkv' -f $programPath) },
    @{ Name = "revealFileCLI"; Label = "解除隐写(根据密码本)"; Command = ('"{0}" -i "%1" -r' -f $programPath) },
    @{ Name = "revealFileGUI"; Label = "批量解除隐写(打开GUI)"; Command = ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" "%1"' -f $selectionLauncher) },
    @{ Name = "revealDir"; Label = "解除此文件夹下所有隐写(批量)"; Command = ('"{0}" -i "%1" -rd -rdgui' -f $programPath) },
    @{ Name = "modifyHash"; Label = "修改文件/文件夹哈希值"; Command = ('"{0}" "%1"' -f $hashModifier); Icon = $hashIcon },
    @{ Name = "openHashModifier"; Label = "打开哈希修改器GUI"; Command = ('"{0}" --gui' -f $hashModifier); Icon = $hashIcon }
)

foreach ($definition in $commands) {
    $commandKey = "$commandStore\$($definition.Name)"
    Set-RegistryString -Key $commandKey -Value $definition.Label -WhatIf:$WhatIfPreference
    if ($definition.Icon) {
        Set-RegistryString -Key $commandKey -Name "Icon" -Value $definition.Icon -WhatIf:$WhatIfPreference
    }
    Set-RegistryString -Key "$commandKey\command" -Value $definition.Command -WhatIf:$WhatIfPreference
}

Set-RegistryString -Key $backgroundMenu -Value "打开隐写者GUI" -WhatIf:$WhatIfPreference
Set-RegistryString -Key $backgroundMenu -Name "Icon" -Value $programPath -WhatIf:$WhatIfPreference
Set-RegistryString -Key "$backgroundMenu\command" -Value ('"{0}"' -f $programPath) -WhatIf:$WhatIfPreference

Write-Host "Context menu configured for: $programPath"
Write-Host "Open a new terminal before using the steg command."
