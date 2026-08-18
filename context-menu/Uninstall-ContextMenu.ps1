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
        & reg.exe delete $key /f 2>$null | Out-Null
        if ($LASTEXITCODE -notin @(0, 1)) {
            throw "reg.exe failed for '$key' with exit code $LASTEXITCODE."
        }
    }
}

$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$normalizedTools = $toolsDirectory.TrimEnd("\")
$remainingEntries = @($machinePath -split ";" | Where-Object {
    $entry = $_.Trim()
    $entry -and ([Environment]::ExpandEnvironmentVariables($entry.Trim('"')).TrimEnd("\")) -ine $normalizedTools
})
if ($PSCmdlet.ShouldProcess($toolsDirectory, "Remove tools directory from the machine PATH")) {
    [Environment]::SetEnvironmentVariable("Path", ($remainingEntries -join ";"), "Machine")
}

$stegLauncher = Join-Path $toolsDirectory "steg.cmd"
if ((Test-Path -LiteralPath $stegLauncher) -and $PSCmdlet.ShouldProcess($stegLauncher, "Delete command launcher")) {
    Remove-Item -LiteralPath $stegLauncher -Force
}

Write-Host "SteganographierGUI context-menu entries were removed."
