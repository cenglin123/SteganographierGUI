# Every shipped script must be readable by the interpreter that actually runs it.
#
# Windows PowerShell 5.1 -- the host every .cmd shim in this repository launches --
# reads a BOM-less file as ANSI/CP936. Chinese text then decodes to mojibake and a
# script fails to parse outright. This is not hypothetical: it is how
# context-menu/Install-ContextMenu.ps1 and scripts/test-context-menu-path.ps1 were
# each broken once, and how the v1.3.9 label restoration was first committed
# unparsable. Editing tools that rewrite a file can drop the BOM silently, so the
# invariant is asserted here instead of trusted:
#
#   .ps1 / .psm1  ->  must carry a UTF-8 BOM if they contain non-ASCII text
#   .cmd / .bat   ->  must be pure ASCII and CRLF-terminated
#
# Batch files are the opposite case: cmd.exe reads them through the console code
# page, so non-ASCII content means something different per machine, and a UTF-8 BOM
# makes the first line unparsable. Keeping them ASCII-only is the only portable
# choice, which is why context-menu/01-*.cmd is located by pattern rather than by
# its Chinese name. cmd.exe also mis-parses LF-only batch files around labels and
# '^' line continuations, so CRLF is required rather than merely conventional.
#
# This file itself is deliberately pure ASCII, so it never needs a BOM.
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    # Enumerated from the filesystem rather than `git ls-files`, because git quotes
    # paths containing non-ASCII bytes (e.g. "context-menu/01-\345\256\211...cmd").
    # Those quoted strings fail Test-Path and were silently skipped, which meant the
    # two most important launchers were never checked at all.
    $scanRoots = @("context-menu", "installer", "scripts", "tools")
    $scriptExtensions = @(".ps1", ".psm1", ".cmd", ".bat")
    $excludedNames = @("__pycache__", "node_modules", ".git")

    $scriptFiles = @()
    foreach ($scanRoot in $scanRoots) {
        $scanPath = Join-Path $repoRoot $scanRoot
        if (-not (Test-Path -LiteralPath $scanPath -PathType Container)) { continue }
        $scriptFiles += Get-ChildItem -LiteralPath $scanPath -Recurse -File -Force |
            Where-Object {
                $scriptExtensions -contains $_.Extension.ToLowerInvariant() -and
                -not ($_.FullName -split '[\\/]' | Where-Object { $excludedNames -contains $_ })
            }
    }

    if ($scriptFiles.Count -eq 0) {
        throw "No scripts were found to check; the scan roots are wrong."
    }

    $failures = @()
    $checkedCount = 0
    foreach ($file in $scriptFiles) {
        $fullPath = $file.FullName
        $relativePath = $fullPath.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'

        $bytes = [IO.File]::ReadAllBytes($fullPath)
        $checkedCount++
        $hasBom = ($bytes.Length -ge 3 -and
                   $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $scanFrom = if ($hasBom) { 3 } else { 0 }
        $hasNonAscii = $false
        for ($index = $scanFrom; $index -lt $bytes.Length; $index++) {
            if ($bytes[$index] -gt 0x7F) { $hasNonAscii = $true; break }
        }

        $isBatch = $relativePath -match '\.(cmd|bat)$'
        if ($isBatch) {
            $bareLineFeeds = 0
            for ($index = $scanFrom; $index -lt $bytes.Length; $index++) {
                if ($bytes[$index] -eq 0x0A -and ($index -eq 0 -or $bytes[$index - 1] -ne 0x0D)) {
                    $bareLineFeeds++
                }
            }
            if ($hasNonAscii) {
                Write-Host ("  FAIL  {0}  (batch file must be pure ASCII)" -f $relativePath)
                $failures += $relativePath
            }
            if ($bareLineFeeds -gt 0) {
                Write-Host ("  FAIL  {0}  ({1} bare LF line ending(s); batch files need CRLF)" -f `
                            $relativePath, $bareLineFeeds)
                $failures += $relativePath
            }
        }
        elseif ($hasNonAscii -and -not $hasBom) {
            Write-Host ("  FAIL  {0}  (non-ASCII text, no UTF-8 BOM)" -f $relativePath)
            $failures += $relativePath
        }
    }

    # Inno displays these files at run time (the licence page and the two
    # information pages). Since Inno Setup 6.3 these may be UTF-8 with or without a
    # BOM, so a BOM is NOT strictly required - this rule is a convention, chosen
    # because an explicit BOM cannot be misread and the repo is otherwise UTF-8.
    # CRLF is required: the text is rendered in a memo control.
    $innoPageFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "installer") -File -Filter "*.txt" -ErrorAction SilentlyContinue)
    if ($innoPageFiles.Count -eq 0) {
        throw "No installer text pages were found to check."
    }
    foreach ($pageFile in $innoPageFiles) {
        $pageBytes = [IO.File]::ReadAllBytes($pageFile.FullName)
        $checkedCount++
        $pageRelative = $pageFile.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $pageHasBom = ($pageBytes.Length -ge 3 -and
                       $pageBytes[0] -eq 0xEF -and $pageBytes[1] -eq 0xBB -and $pageBytes[2] -eq 0xBF)
        if (-not $pageHasBom) {
            Write-Host ("  FAIL  {0}  (installer text page needs a UTF-8 BOM)" -f $pageRelative)
            $failures += $pageRelative
        }
        $pageBareLf = 0
        for ($index = 0; $index -lt $pageBytes.Length; $index++) {
            if ($pageBytes[$index] -eq 0x0A -and ($index -eq 0 -or $pageBytes[$index - 1] -ne 0x0D)) {
                $pageBareLf++
            }
        }
        if ($pageBareLf -gt 0) {
            Write-Host ("  FAIL  {0}  ({1} bare LF line ending(s); installer pages need CRLF)" -f `
                        $pageRelative, $pageBareLf)
            $failures += $pageRelative
        }
    }

    if ($failures.Count -gt 0) {
        throw ("{0} script(s) would not run correctly on their target host: {1}" -f `
               $failures.Count, ($failures -join ', '))
    }

    Write-Host ("Script encoding test passed ({0} script(s) checked)." -f $checkedCount)
}
finally {
    Pop-Location
}
