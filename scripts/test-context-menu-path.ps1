$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("SteganographierGUI-!Tool Space-" + [guid]::NewGuid().ToString("N"))

try {
    New-Item -ItemType Directory -Path $testRoot, (Join-Path $testRoot "tools"), (Join-Path $testRoot "modules"), (Join-Path $testRoot "context-menu") | Out-Null
    # Mirror the shipped layout: entry points at the root, implementation under
    # context-menu\. A fixture that flattened them would not exercise the relative
    # path the entry scripts actually use.
    Copy-Item -LiteralPath (Join-Path $repoRoot "context-menu\01-安装隐写者到右键菜单.cmd") -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot "context-menu\02-移除隐写者右键菜单.cmd") -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $repoRoot "context-menu\Install-ContextMenu.ps1") -Destination (Join-Path $testRoot "context-menu")
    Copy-Item -LiteralPath (Join-Path $repoRoot "context-menu\RegistryWrite.ps1") -Destination (Join-Path $testRoot "context-menu")
    Copy-Item -LiteralPath (Join-Path $repoRoot "context-menu\Uninstall-ContextMenu.ps1") -Destination (Join-Path $testRoot "context-menu")
    Copy-Item -LiteralPath (Join-Path $repoRoot "tools\launch_from_selection.ps1") -Destination (Join-Path $testRoot "tools")
    foreach ($relativePath in @("SteganographierGUI.exe", "tools\hash_modifier.exe", "modules\favicon.ico", "modules\favicon_hash_modifier.ico")) {
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
    if ($output -notmatch "!Tool Space") {
        throw "The exclamation mark or space was lost from the install path.`n$output"
    }
    # v1.3.9 shipped these entries in Chinese and the PowerShell rewrite silently
    # switched them to English. Pin the wording so it cannot drift again unnoticed.
    foreach ($expectedLabel in @(
        "隐写为MP4文件(无密码)",
        "解除隐写(根据密码本)",
        "批量解除隐写(打开GUI)",
        "修改文件/文件夹哈希值",
        "打开哈希修改器GUI",
        "打开隐写者GUI"
    )) {
        if ($output -notmatch [regex]::Escape($expectedLabel)) {
            throw "Dry-run output is missing the v1.3.9 menu label '$expectedLabel'.`n$output"
        }
    }

    $uninstaller = Join-Path $testRoot "02-移除隐写者右键菜单.cmd"
    $uninstallOutput = (& cmd.exe /d /c "`"$uninstaller`" -WhatIf" 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Context-menu uninstall dry run failed with exit code $LASTEXITCODE.`n$uninstallOutput"
    }
    if ($uninstallOutput -notmatch [regex]::Escape($testRoot) -or $uninstallOutput -notmatch "!Tool Space") {
        throw "The uninstall dry run did not preserve the install path.`n$uninstallOutput"
    }

    Write-Host "Context-menu path test passed: $testRoot"
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
