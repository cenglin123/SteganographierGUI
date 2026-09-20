param(
    [string]$ExpectedVersion,
    [string]$Tag
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $repoRoot "VERSION"
$version = (Get-Content -Raw -Encoding UTF8 $versionPath).Trim()

if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "VERSION must use semantic version form x.y.z; found '$version'."
}
if ($ExpectedVersion -and $ExpectedVersion -ne $version) {
    throw "Expected version '$ExpectedVersion' but VERSION contains '$version'."
}
if ($Tag -and $Tag -ne "v$version") {
    throw "Tag '$Tag' does not match VERSION '$version'."
}

$requiredPaths = @(
    "Steganographier.py",
    "SteganographierGUI.spec",
    "requirements.txt",
    "requirements-build.txt",
    "context-menu/01-安装隐写者到右键菜单.cmd",
    "context-menu/02-移除隐写者右键菜单.cmd",
    "context-menu/Install-ContextMenu.ps1",
    "context-menu/Uninstall-ContextMenu.ps1",
    "modules/favicon.ico",
    "modules/PW.txt",
    "installer/SteganographierGUI.iss",
    "installer/Languages/ChineseSimplified.isl",
    "tools/7z.exe",
    "tools/mkvmerge.exe",
    "tools/mkvextract.exe",
    "tools/mkvinfo.exe",
    "tools/hash_modifier.exe",
    "tools/captcha_generator.exe",
    "tools/launch_from_selection.ps1",
    "cover_video"
)
foreach ($relativePath in $requiredPaths) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath))) {
        throw "Required release path is missing: $relativePath"
    }
}

# --- 占位密码本身份判定 -------------------------------------------------------
# modules/PW.txt 必须是「已知占位文件」：以精确字节（首选）或 SHA-256 判定。
# 严禁按文件大小判定——真实密码本与占位文件都可能很短，大小不构成身份。
# 未知内容一律拒绝（fail closed）：它可能是真实密码本，绝不能进入构建产物。
$placeholderPwBytes  = [byte[]](0x0D, 0x0A)
$placeholderPwSha256 = "7eb70257593da06f682a3ddda54a9d260d4fc514f645237f5ca74b08f8da61a6"
$pwPath = Join-Path $repoRoot "modules/PW.txt"
$pwBytes = [IO.File]::ReadAllBytes($pwPath)
$pwBytesMatch = $pwBytes.Length -eq $placeholderPwBytes.Length
if ($pwBytesMatch) {
    for ($pwIndex = 0; $pwIndex -lt $placeholderPwBytes.Length; $pwIndex++) {
        if ($pwBytes[$pwIndex] -ne $placeholderPwBytes[$pwIndex]) {
            $pwBytesMatch = $false
            break
        }
    }
}
$pwHash = (Get-FileHash -LiteralPath $pwPath -Algorithm SHA256).Hash.ToLowerInvariant()
if (-not $pwBytesMatch -and $pwHash -ne $placeholderPwSha256) {
    throw ("modules/PW.txt is not the known placeholder. Expected exact bytes 0D 0A or SHA-256 {0}; found SHA-256 {1} ({2} bytes). Refusing to continue: unknown content may be a real password book. This decision is based on exact content, never on file size." -f $placeholderPwSha256, $pwHash, $pwBytes.Length)
}

Push-Location $repoRoot
try {
    $reportedVersion = (& python .\Steganographier.py --version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Steganographier.py --version failed with exit code $LASTEXITCODE."
    }
    if ($reportedVersion -notmatch [regex]::Escape($version)) {
        throw "Application reported '$reportedVersion', expected version '$version'."
    }

    if ($Tag) {
        # Release tags must be annotated and their tree must carry a matching VERSION.
        # Legacy lightweight tags (all before v1.3.10) are grandfathered; see docs/RELEASING.md.
        $tagType = (git cat-file -t $Tag 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or -not $tagType) {
            throw "Tag '$Tag' does not exist locally; fetch it or create it with 'git tag -a'."
        }
        if ($tagType -ne 'tag') {
            throw "Tag '$Tag' is lightweight ('$tagType'); release tags must be annotated."
        }
        $taggedVersion = (git show "${Tag}:VERSION" 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $taggedVersion -ne $version) {
            throw "VERSION inside tag '$Tag' is '$taggedVersion', expected '$version'."
        }
    }
}
finally {
    Pop-Location
}

Write-Host "Release inputs validated for v$version."
