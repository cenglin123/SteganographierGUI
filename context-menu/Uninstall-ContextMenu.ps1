[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
)

$ErrorActionPreference = "Stop"
$installDirectory = [IO.Path]::GetFullPath($InstallRoot).TrimEnd("\")
$toolsDirectory = Join-Path $installDirectory "tools"

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# See the matching comment in Install-ContextMenu.ps1: v1.3.9 broadcast
# WM_SETTINGCHANGE, which actually refreshes PATH for running shells; the
# rundll32 replacement that followed it does not.
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

if (-not $WhatIfPreference -and -not (Test-Administrator)) {
    throw "Run this script as administrator."
}

# Delete one registry key tolerantly: absent key is success, any other failure throws.
# Why the cmd.exe wrapper: on Windows PowerShell 5.1, ANY capture of native stderr
# (2>$null, 2>&1, 2>file) under an outer ErrorActionPreference='Stop' is promoted to a
# terminating NativeCommandError. Merging stderr into stdout inside cmd (/c "... 2>&1")
# keeps it on the stdout stream and out of harm's way. Verified empirically 2026-09-12.
# NOTE: reg.exe returns exit 1 for BOTH "key not found" and real failures, so the merged
# text decides: only the localized "not found" message counts as absent; access denied or
# anything else still throws.
function Remove-RegistryKeyTolerant {
    param([string]$Key)
    $output = & cmd.exe /c "reg delete `"$Key`" /f 2>&1"
    $code = $LASTEXITCODE
    $text = ($output | Out-String)
    if ($text -match 'unable to find|找不到') { return 'absent' }
    if ($code -eq 0) { return 'deleted' }
    throw "reg.exe failed for '$Key' with exit code $code : $text"
}

$keys = @(
    "HKCR\*\shell\Steganographier",
    "HKCR\Directory\shell\Steganographier",
    "HKCR\Directory\Background\shell\openSteganographier",
    # Legacy names that the v1.3.9 uninstaller removed but this list had dropped,
    # leaving orphans behind when upgrading from a pre-1.3.10 install.
    "HKCR\Directory\Background\shell\SteganographierAndHashModifier",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\hideMp4",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\hideMkv",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealFileCLI",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealFileGUI",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealDir",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\modifyHash",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\openHashModifier",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\reveal",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\openSteganographier"
)
foreach ($key in $keys) {
    if ($PSCmdlet.ShouldProcess($key, "Delete registry key")) {
        # Absent keys are an expected state (idempotent uninstall); only real failures throw.
        # Surface the result so a run is auditable without guessing from exit codes.
        $result = Remove-RegistryKeyTolerant -Key $key
        Write-Host ("  reg: {0,-95} {1}" -f $key, $result)
    }
}

$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$normalizedTools = $toolsDirectory.TrimEnd("\")
$remainingEntries = @($machinePath -split ";" | Where-Object {
    $entry = $_.Trim()
    $entry -and ([Environment]::ExpandEnvironmentVariables($entry.Trim('"')).TrimEnd("\")) -ine $normalizedTools
})
if ($PSCmdlet.ShouldProcess($toolsDirectory, "Remove tools directory from the machine PATH")) {
    # SetEnvironmentVariable writes REG_SZ and silently downgrades a REG_EXPAND_SZ Path.
    # Preserve the original value kind (and %VAR% tokens) by writing the key directly.
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $kind = (Get-Item $key).GetValueKind('Path')
    Set-ItemProperty -LiteralPath $key -Name Path -Value ($remainingEntries -join ";") -Type $kind
    Send-EnvironmentChangeBroadcast
}

$stegLauncher = Join-Path $toolsDirectory "steg.cmd"
if ((Test-Path -LiteralPath $stegLauncher) -and $PSCmdlet.ShouldProcess($stegLauncher, "Delete command launcher")) {
    Remove-Item -LiteralPath $stegLauncher -Force
}

Write-Host "SteganographierGUI context-menu entries were removed."
