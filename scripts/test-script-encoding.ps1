# Every shipped PowerShell/batch script that contains non-ASCII text must be saved
# as UTF-8 WITH a BOM.
#
# Windows PowerShell 5.1 -- the host every .cmd shim in this repository launches --
# reads a BOM-less file as ANSI/CP936. Chinese menu labels then decode to mojibake
# and the script fails to parse outright. This is not hypothetical: it is how
# context-menu/Install-ContextMenu.ps1 and scripts/test-context-menu-path.ps1 were
# each broken once, and how the v1.3.9 label restoration was first committed
# unparsable. Editing tools that rewrite a file can drop the BOM silently, so the
# invariant is asserted here instead of trusted.
#
# This file itself is deliberately pure ASCII, so it never needs a BOM.
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $trackedFiles = & git ls-files
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed with exit code $LASTEXITCODE."
    }

    $failures = @()
    $checkedCount = 0
    foreach ($relativePath in $trackedFiles) {
        if ($relativePath -notmatch '\.(ps1|psm1|cmd|bat)$') { continue }
        $fullPath = Join-Path $repoRoot $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }

        $bytes = [IO.File]::ReadAllBytes($fullPath)
        $checkedCount++
        $hasBom = ($bytes.Length -ge 3 -and
                   $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $scanFrom = if ($hasBom) { 3 } else { 0 }
        $hasNonAscii = $false
        for ($index = $scanFrom; $index -lt $bytes.Length; $index++) {
            if ($bytes[$index] -gt 0x7F) { $hasNonAscii = $true; break }
        }

        if ($hasNonAscii -and -not $hasBom) {
            Write-Host ("  FAIL  {0}  (non-ASCII text, no UTF-8 BOM)" -f $relativePath)
            $failures += $relativePath
        }
    }

    if ($failures.Count -gt 0) {
        throw ("{0} script(s) contain non-ASCII text without a UTF-8 BOM and will not " +
               "parse under Windows PowerShell 5.1: {1}" -f $failures.Count, ($failures -join ', '))
    }

    Write-Host ("Script encoding test passed ({0} script(s) checked)." -f $checkedCount)
}
finally {
    Pop-Location
}
