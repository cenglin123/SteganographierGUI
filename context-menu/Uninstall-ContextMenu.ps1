[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
)

$ErrorActionPreference = "Stop"
$installDirectory = [IO.Path]::GetFullPath($InstallRoot).TrimEnd("\")
$toolsDirectory = Join-Path $installDirectory "tools"
. (Join-Path $PSScriptRoot "RegistryDeleteSafety.ps1")

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $WhatIfPreference -and -not (Test-Administrator)) {
    throw "Run this script as administrator."
}

$keys = @(
    "HKCR\*\shell\Steganographier",
    "HKCR\Directory\shell\Steganographier",
    "HKCR\Directory\Background\shell\openSteganographier",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\hideMp4",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\hideMkv",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealFileCLI",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealFileGUI",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealDir",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\modifyHash",
    "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\openHashModifier"
)
foreach ($key in $keys) {
    if ($PSCmdlet.ShouldProcess($key, "Delete registry key")) {
        # Guarded deletion: the explicit allowlist and the critical-root refusal live in
        # RegistryDeleteSafety.ps1; an absent key is an expected, idempotent state.
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
    & cmd.exe /c 'rundll32.exe user32.dll,UpdatePerUserSystemParameters 1,True >nul 2>&1' | Out-Null
}

$stegLauncher = Join-Path $toolsDirectory "steg.cmd"
if ((Test-Path -LiteralPath $stegLauncher) -and $PSCmdlet.ShouldProcess($stegLauncher, "Delete command launcher")) {
    Remove-Item -LiteralPath $stegLauncher -Force
}

Write-Host "SteganographierGUI context-menu entries were removed."
