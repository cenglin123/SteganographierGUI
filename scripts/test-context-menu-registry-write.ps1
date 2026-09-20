# Round-trip test for the context-menu registry writer.
#
# Why this exists: the older path test only ever ran the installer with -WhatIf,
# which makes ShouldProcess skip reg.exe entirely. It therefore passed while the
# shipped v1.3.10 writer failed to register a single command on *every* install
# path. This test dot-sources the very file the installer uses
# (context-menu/RegistryWrite.ps1) and demands that what reg.exe stores is
# character-for-character what was requested.
#
# Only HKCU scratch keys are touched, so no administrator rights are needed and
# nothing outside this test's own tree is modified.
param(
    [switch]$SkipHostMatrix
)

$ErrorActionPreference = "Stop"

Write-Host ("host: {0} {1}" -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion)

# The installer is launched by a .cmd shim as `powershell.exe` (Windows PowerShell
# 5.1), and 5.1 marshals native arguments differently from PowerShell 7: the
# v1.3.10 defect reproduces ONLY on 5.1. Asserting on both hosts stops a single-host
# run - and a pwsh-only CI job - from reporting false confidence.
$runningOnWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
if (-not $SkipHostMatrix -and $runningOnWindows -and $PSVersionTable.PSVersion.Major -ne 5) {
    $windowsPowerShellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $windowsPowerShellPath -PathType Leaf)) {
        throw "Windows PowerShell 5.1 is needed to assert production behaviour, but '$windowsPowerShellPath' is missing."
    }
    Write-Host "Running production-host (Windows PowerShell 5.1) assertions..."
    & $windowsPowerShellPath -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -SkipHostMatrix
    if ($LASTEXITCODE -ne 0) {
        throw "Assertions failed under Windows PowerShell 5.1 (exit code $LASTEXITCODE)."
    }
    Write-Host "Windows PowerShell 5.1 assertions passed."
    Write-Host ""
}

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "context-menu\RegistryWrite.ps1")

$scratchRoot = "HKCU\Software\SteganographierGUI-RegWriteTest-" + [guid]::NewGuid().ToString("N")

function Get-StoredValue {
    param([string]$Key, [string]$Name)
    $item = Get-Item -LiteralPath ("Registry::" + $Key) -ErrorAction SilentlyContinue
    if (-not $item) { return "<key missing>" }
    if ($Name) {
        if ($item.GetValueNames() -notcontains $Name) { return "<value missing>" }
        return [string]$item.GetValue($Name)
    }
    return [string]$item.GetValue("")
}

# Only characters that are legal in a Windows directory name, so every case is an
# install root a user could actually choose. Regressions here are reachable.
# (| < > : " / \ ? * cannot appear in a path and are deliberately absent.)
$installRoots = @(
    @{ Label = "plain";                 Root = 'C:\SteganographierGUI' },
    @{ Label = "spaces (reported)";     Root = 'D:\Program Files\SteganographierGUI' },
    @{ Label = "ampersand";             Root = 'D:\Program Files\A & B\SteganographierGUI' },
    @{ Label = "caret";                 Root = 'D:\Program Files\A ^ B\SteganographierGUI' },
    @{ Label = "percent";               Root = 'D:\Program Files\100% legit\SteganographierGUI' },
    @{ Label = "exclamation";           Root = 'D:\Program Files\Steg!Test\SteganographierGUI' },
    @{ Label = "parentheses";           Root = 'D:\Program Files\App (x64)\SteganographierGUI' },
    @{ Label = "semicolon";             Root = 'D:\Program Files\A; B\SteganographierGUI' },
    @{ Label = "single quote";          Root = "D:\Program Files\It's here\SteganographierGUI" },
    @{ Label = "brackets";              Root = 'D:\Program Files\[beta]\SteganographierGUI' },
    @{ Label = "hash plus equals comma";Root = 'D:\Program Files\A#B+C=D,E\SteganographierGUI' },
    @{ Label = "dollar at tilde";       Root = 'D:\Program Files\$env@host~1\SteganographierGUI' },
    @{ Label = "CJK + spaces";          Root = 'D:\Program Files\隐写 者\SteganographierGUI' }
)

$failures = @()
$checkedValues = 0

try {
    Write-Host ("{0,-22} {1,-10} {2}" -f "install root", "value", "round-trip")
    Write-Host ("-" * 62)

    foreach ($case in $installRoots) {
        $programPath = Join-Path $case.Root "SteganographierGUI.exe"
        $hashModifier = Join-Path $case.Root "tools\hash_modifier.exe"

        # The three shapes the installer actually writes.
        $shapes = @(
            @{ Name = "";           Label = "default"; Value = ('"{0}" -i "%1" -o "%1_hidden.mp4" -t mp4' -f $programPath) },
            @{ Name = "Icon";       Label = "Icon";    Value = $programPath },
            @{ Name = "";           Label = "hash";    Value = ('"{0}" "%1"' -f $hashModifier) }
        )

        foreach ($shape in $shapes) {
            $checkedValues++
            $targetKey = "$scratchRoot\" + ($case.Label -replace '[^A-Za-z0-9]', '_') + "_" + $shape.Label

            if ($shape.Name) {
                Set-RegistryString -Key $targetKey -Name $shape.Name -Value $shape.Value
            } else {
                Set-RegistryString -Key $targetKey -Value $shape.Value
            }

            $storedValue = Get-StoredValue -Key $targetKey -Name $shape.Name
            if ($storedValue -ceq $shape.Value) {
                Write-Host ("{0,-22} {1,-10} ok" -f $case.Label, $shape.Label)
            } else {
                Write-Host ("{0,-22} {1,-10} MISMATCH" -f $case.Label, $shape.Label)
                Write-Host ("     requested: {0}" -f $shape.Value)
                Write-Host ("     stored   : {0}" -f $storedValue)
                $failures += "$($case.Label)/$($shape.Label)"
            }
        }
    }

    # -WhatIf must not write anything at all.
    $whatIfKey = "$scratchRoot\whatif_probe"
    Set-RegistryString -Key $whatIfKey -Value "probe" -WhatIf
    if ((Get-StoredValue -Key $whatIfKey -Name "") -ne "<key missing>") {
        $failures += "WhatIf wrote a value"
        Write-Host "WhatIf probe: FAILED (a value was written)"
    } else {
        Write-Host "WhatIf probe: ok (nothing written)"
    }
}
finally {
    & cmd.exe /c "reg delete `"$scratchRoot`" /f >nul 2>&1" | Out-Null
    $scratchRemoved = -not (Test-Path -LiteralPath ("Registry::" + $scratchRoot))
    Write-Host ""
    Write-Host ("scratch tree removed: {0}" -f $scratchRemoved)
    if (-not $scratchRemoved) { $failures += "scratch tree not removed" }
}

Write-Host ("checked {0} values across {1} install roots" -f $checkedValues, $installRoots.Count)
if ($failures.Count -gt 0) {
    Write-Host ("FAILED: {0}" -f ($failures -join ', '))
    exit 1
}
Write-Host "Context-menu registry write test passed."
exit 0
