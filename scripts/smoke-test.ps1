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
    "Install-ContextMenu.ps1",
    "Uninstall-ContextMenu.ps1",
    "RegistryWrite.ps1",
    "InstallElevated.cmd",
    "tkinterdnd2\tkdnd\win64\libtkdnd2.9.2.dll",
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

$process = Start-Process -FilePath (Join-Path $stage "SteganographierGUI.exe") -ArgumentList "--version" -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Packaged executable version smoke test failed with exit code $($process.ExitCode)."
}

Write-Host "Packaged application smoke test passed for v$ExpectedVersion."
