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
    [Environment]::SetEnvironmentVariable("Path", ($remainingEntries -join ";"), "Machine")
}

$stegLauncher = Join-Path $toolsDirectory "steg.cmd"
if ((Test-Path -LiteralPath $stegLauncher) -and $PSCmdlet.ShouldProcess($stegLauncher, "Delete command launcher")) {
    Remove-Item -LiteralPath $stegLauncher -Force
}

Write-Host "SteganographierGUI context-menu entries were removed."
