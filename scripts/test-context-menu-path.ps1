$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("SteganographierGUI-!Tool-" + [guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Path $testRoot, (Join-Path $testRoot "tools"), (Join-Path $testRoot "modules") | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot "context-menu\01-安装隐写者到右键菜单.cmd") -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot "context-menu\02-移除隐写者右键菜单.cmd") -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot "context-menu\Install-ContextMenu.ps1") -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot "context-menu\Uninstall-ContextMenu.ps1") -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot "tools\launch_from_selection.ps1") -Destination (Join-Path $testRoot "tools")
    foreach ($relativePath in @("SteganographierGUI.exe", "tools\hash_modifier.exe", "modules\favicon.ico")) {
        New-Item -ItemType File -Path (Join-Path $testRoot $relativePath) | Out-Null
    }

    $launcher = Join-Path $testRoot "01-安装隐写者到右键菜单.cmd"
    $output = (& cmd.exe /d /c "`"$launcher`" -WhatIf" 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Context-menu dry run failed with exit code $LASTEXITCODE.`n$output"
    }
    if ($output -notmatch [regex]::Escape($testRoot)) {
        throw "Dry-run output did not preserve the install path.`n$output"
    }
    if ($output -notmatch "!Tool") {
        throw "The exclamation mark was lost from the install path.`n$output"
    }

    $uninstaller = Join-Path $testRoot "02-移除隐写者右键菜单.cmd"
    $uninstallOutput = (& cmd.exe /d /c "`"$uninstaller`" -WhatIf" 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Context-menu uninstall dry run failed with exit code $LASTEXITCODE.`n$uninstallOutput"
    }
    if ($uninstallOutput -notmatch [regex]::Escape($testRoot) -or $uninstallOutput -notmatch "!Tool") {
        throw "The uninstall dry run did not preserve the install path.`n$uninstallOutput"
    }

    Write-Host "Context-menu path test passed: $testRoot"
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
