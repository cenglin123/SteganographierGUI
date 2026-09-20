param(
    [Parameter(Mandatory = $true)]
    [string]$StageDirectory,
    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion
)

$ErrorActionPreference = "Stop"
$stage = (Resolve-Path -LiteralPath $StageDirectory).Path
$requiredFiles = @(
    "SteganographierGUI.exe",
    "VERSION",
    "01-安装隐写者到右键菜单.cmd",
    "02-移除隐写者右键菜单.cmd",
    # Entry points at the root (as v1.3.9 had them), implementation grouped under
    # context-menu\.
    "context-menu\Install-ContextMenu.ps1",
    "context-menu\Uninstall-ContextMenu.ps1",
    "context-menu\RegistryWrite.ps1",
    "context-menu\RegistryDeleteSafety.ps1",
    "InstallElevated.cmd",
    # PyInstaller 6 keeps the bundled runtime in _internal\; the tkinterdnd2 data
    # files collected by the spec land there too.
    "_internal\tkinterdnd2\tkdnd\win64\libtkdnd2.9.2.dll",
    "modules\favicon.ico",
    "modules\PW.txt",
    "tools\7z.exe",
    "tools\mkvmerge.exe",
    "tools\mkvextract.exe",
    "tools\mkvinfo.exe",
    "tools\hash_modifier.exe",
    "tools\captcha_generator.exe",
    "tools\launch_from_selection.ps1"
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $stage $relativePath) -PathType Leaf)) {
        throw "Packaged file is missing: $relativePath"
    }
}
if (-not (Get-ChildItem -LiteralPath (Join-Path $stage "cover_video") -Filter "*.mp4" -File)) {
    throw "The package must contain at least one MP4 cover video."
}

# Vendored companion tool. Its contents are fetched at build time rather than
# tracked by git, so both the folder and the upstream licence files it must carry
# are asserted here; a silent fetch failure would otherwise ship a package that
# merely lost the tool. See docs/THIRD-PARTY-DOWNKYI.md.
$companionFolder = Join-Path $stage "B站视频下载工具-DownKyi-1.6.1"
if (-not (Test-Path -LiteralPath $companionFolder -PathType Container)) {
    throw "Packaged companion tool folder is missing: B站视频下载工具-DownKyi-1.6.1"
}
foreach ($licenceName in @("aria2_COPYING.txt", "FFmpeg_LICENSE.txt")) {
    if (-not (Test-Path -LiteralPath (Join-Path $companionFolder $licenceName) -PathType Leaf)) {
        throw "Packaged companion tool is missing its licence file: $licenceName"
    }
}
if ((Get-Content -Raw -Encoding UTF8 (Join-Path $stage "VERSION")).Trim() -ne $ExpectedVersion) {
    throw "Packaged VERSION does not match '$ExpectedVersion'."
}

# Inno's [Files] section skips hidden files, so a hidden item anywhere in the stage
# is silently dropped from the installer - and if that item is _internal\, the
# installed program cannot start. v1.3.9 shipped _internal with the hidden attribute,
# which worked only because it was delivered by a RAR SFX; measured by installing a
# build with the attribute set and confirming the executable would not run.
$hiddenItems = @(Get-ChildItem -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Attributes -band [IO.FileAttributes]::Hidden })
if ($hiddenItems.Count -gt 0) {
    $sample = ($hiddenItems | Select-Object -First 5 | ForEach-Object { $_.FullName }) -join '; '
    throw "The stage contains $($hiddenItems.Count) hidden item(s), which the installer would omit: $sample"
}

$process = Start-Process -FilePath (Join-Path $stage "SteganographierGUI.exe") -ArgumentList "--version" -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Packaged executable version smoke test failed with exit code $($process.ExitCode)."
}

Write-Host "Packaged application smoke test passed for v$ExpectedVersion."
