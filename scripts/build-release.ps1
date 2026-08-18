param(
    [string]$ExpectedVersion,
    [switch]$BuildInstaller
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$version = (Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "VERSION")).Trim()
if (-not $ExpectedVersion) {
    $ExpectedVersion = $version
}

Push-Location $repoRoot
try {
    & .\scripts\validate-release.ps1 -ExpectedVersion $ExpectedVersion

    foreach ($relativePath in @("build", "dist", "artifacts")) {
        $generatedPath = Join-Path $repoRoot $relativePath
        if (Test-Path -LiteralPath $generatedPath) {
            Remove-Item -LiteralPath $generatedPath -Recurse -Force
        }
    }
    New-Item -ItemType Directory -Path "build", "artifacts" | Out-Null

    $parts = $version.Split('.')
    $versionTuple = "$($parts[0]), $($parts[1]), $($parts[2]), 0"
    $versionInfo = @"
VSVersionInfo(
  ffi=FixedFileInfo(filevers=($versionTuple), prodvers=($versionTuple), mask=0x3f, flags=0x0, OS=0x4, fileType=0x1, subtype=0x0, date=(0, 0)),
  kids=[
    StringFileInfo([StringTable('080404b0', [
      StringStruct('CompanyName', 'cenglin123'),
      StringStruct('FileDescription', 'SteganographierGUI'),
      StringStruct('FileVersion', '$version'),
      StringStruct('ProductName', 'SteganographierGUI'),
      StringStruct('ProductVersion', '$version'),
      StringStruct('OriginalFilename', 'SteganographierGUI.exe')
    ])]),
    VarFileInfo([VarStruct('Translation', [2052, 1200])])
  ]
)
"@
    [IO.File]::WriteAllText((Join-Path $repoRoot "build\version_info.txt"), $versionInfo, (New-Object Text.UTF8Encoding($false)))

    & python -m PyInstaller --clean --noconfirm .\SteganographierGUI.spec
    if ($LASTEXITCODE -ne 0) {
        throw "PyInstaller failed with exit code $LASTEXITCODE."
    }

    $stageName = "SteganographierGUI_v${version}"
    $stage = Join-Path $repoRoot "artifacts\$stageName"
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item -Path ".\dist\SteganographierGUI\*" -Destination $stage -Recurse -Force
    foreach ($directory in @("modules", "tools", "cover_video")) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $directory) -Destination $stage -Recurse -Force
    }
    Copy-Item -Path ".\context-menu\*" -Destination $stage -Force
    Copy-Item -LiteralPath ".\README.md" -Destination (Join-Path $stage "README.md")
    Copy-Item -LiteralPath ".\LICENSE" -Destination (Join-Path $stage "LICENSE")
    [IO.File]::WriteAllText((Join-Path $stage "VERSION"), "$version`n", (New-Object Text.UTF8Encoding($false)))

    $commit = (git rev-parse HEAD).Trim()
    $manifest = [ordered]@{
        version = $version
        commit = $commit
        created_at_utc = [DateTime]::UtcNow.ToString("o")
        python = (& python --version 2>&1 | Out-String).Trim()
        pyinstaller = (& python -m PyInstaller --version 2>&1 | Out-String).Trim()
    }
    $manifest | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $stage "build-manifest.json")

    & .\scripts\smoke-test.ps1 -StageDirectory $stage -ExpectedVersion $version

    $portablePath = Join-Path $repoRoot "artifacts\SteganographierGUI_v${version}_portable.zip"
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $portablePath -CompressionLevel Optimal

    if ($BuildInstaller) {
        $isccCandidates = @(
            "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
            "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
        )
        $iscc = $isccCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $iscc) {
            throw "Inno Setup 6 compiler (ISCC.exe) was not found."
        }
        & $iscc "/DAppVersion=$version" "/DSourceDir=$stage" "/DOutputDir=$(Join-Path $repoRoot 'artifacts')" ".\installer\SteganographierGUI.iss"
        if ($LASTEXITCODE -ne 0) {
            throw "Inno Setup failed with exit code $LASTEXITCODE."
        }
    }

    $releaseFiles = Get-ChildItem -LiteralPath ".\artifacts" -File | Where-Object { $_.Extension -in @(".zip", ".exe") }
    $checksumLines = foreach ($file in $releaseFiles) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        "$hash  $($file.Name)"
    }
    [IO.File]::WriteAllLines((Join-Path $repoRoot "artifacts\SHA256SUMS.txt"), $checksumLines, (New-Object Text.UTF8Encoding($false)))

    Write-Host "Release artifacts created in $(Join-Path $repoRoot 'artifacts')."
}
finally {
    Pop-Location
}
