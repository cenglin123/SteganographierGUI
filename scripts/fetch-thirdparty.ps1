# Fetch the pinned third-party companion tool into the release stage.
#
# docs/THIRD-PARTY-DOWNKYI.md requires that a bundled DownKyi be a real build
# input: pinned version, SHA256 verified, licence files preserved. Historically
# the folder was stuffed into the stage by hand before publishing, which is the
# "local directory as build input" pattern RELEASING.md forbids, and is why the
# tool disappeared from releases once packaging became fully automated.
#
# The payload (~75 MB expanded) is deliberately NOT tracked by git; it is cached
# under .thirdparty-cache/ (gitignored) and copied into the stage on each build.
#
# The only non-ASCII in this file is the vendored folder name, which has to match
# what users of the older builds already have on disk.
param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationDirectory,
    [string]$CacheDirectory
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $CacheDirectory) {
    $CacheDirectory = Join-Path $repoRoot ".thirdparty-cache"
}

$sevenZip = Join-Path $repoRoot "tools\7z.exe"
if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
    throw "tools\7z.exe is required to unpack the vendored archives but was not found."
}

# Pinned sources. The SHA256 values were computed from the official GitHub release
# assets; DownKyi's zip is corroborated by 35 of its 36 files being byte-identical
# to the copy that shipped with v1.3.9 (the exception is noted in
# docs/THIRD-PARTY-DOWNKYI.md). Update all fields together on any bump.
# ArchiveName stays ASCII so the cache path never depends on the console code page.
$packages = @(
    @{
        FolderName  = "B站视频下载工具-DownKyi-1.6.1"
        ArchiveName = "DownKyi-1.6.1.zip"
        ExpandName  = "DownKyi-1.6.1-expanded"
        Url         = "https://github.com/leiurayer/downkyi/releases/download/v1.6.1/DownKyi-1.6.1.zip"
        SizeBytes   = 32204639
        Sha256      = "d809c230c9dd9ab18a7cbafc413db2d93eca25e45c4df5fa6aaad3f253015986"
        # Upstream licence/attribution files that must survive into the release.
        MustKeep    = @("aria2_COPYING.txt", "FFmpeg_LICENSE.txt")
    }
)

if (-not (Test-Path -LiteralPath $CacheDirectory)) {
    New-Item -ItemType Directory -Path $CacheDirectory | Out-Null
}
if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
    throw "Destination directory does not exist: $DestinationDirectory"
}

foreach ($package in $packages) {
    $archivePath = Join-Path $CacheDirectory $package.ArchiveName
    $expandPath = Join-Path $CacheDirectory $package.ExpandName

    # --- download only when absent; a cached file is still verified below ---
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        Write-Host ("Downloading {0} ..." -f $package.ArchiveName)
        $savedProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            Invoke-WebRequest -Uri $package.Url -OutFile $archivePath -UseBasicParsing
        }
        finally {
            $ProgressPreference = $savedProgressPreference
        }
    }

    # --- verify size and hash on every run, cached or freshly downloaded ---
    $actualSize = (Get-Item -LiteralPath $archivePath).Length
    if ($actualSize -ne $package.SizeBytes) {
        throw ("Size mismatch for {0}: expected {1} bytes, found {2}. Delete '{3}' and retry." -f `
               $package.ArchiveName, $package.SizeBytes, $actualSize, $archivePath)
    }
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash.ToLowerInvariant()
    if ($actualHash -ne $package.Sha256) {
        throw ("SHA256 mismatch for {0}: expected {1}, found {2}. Refusing to vendor an unverified archive." -f `
               $package.ArchiveName, $package.Sha256, $actualHash)
    }
    Write-Host ("Verified {0} ({1} bytes, sha256 {2}...)" -f `
                $package.ArchiveName, $actualSize, $actualHash.Substring(0, 16))

    # --- expand with 7z: Expand-Archive mangles this archive's non-ASCII entry
    # name because the zip does not set the UTF-8 name flag ---
    if (Test-Path -LiteralPath $expandPath) {
        Remove-Item -LiteralPath $expandPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $expandPath | Out-Null
    & $sevenZip x $archivePath ("-o" + $expandPath) -y -aoa | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "7z.exe failed to unpack '$archivePath' with exit code $LASTEXITCODE."
    }

    # --- copy into the stage ---
    $targetPath = Join-Path $DestinationDirectory $package.FolderName
    if (Test-Path -LiteralPath $targetPath) {
        Remove-Item -LiteralPath $targetPath -Recurse -Force
    }
    Copy-Item -LiteralPath $expandPath -Destination $targetPath -Recurse -Force

    # --- the licence files must have survived ---
    foreach ($mustKeep in $package.MustKeep) {
        $keptPath = Join-Path $targetPath $mustKeep
        if (-not (Test-Path -LiteralPath $keptPath -PathType Leaf)) {
            throw "Required licence file was not unpacked: $mustKeep"
        }
    }
    $copiedCount = (Get-ChildItem -LiteralPath $targetPath -Recurse -File).Count
    Write-Host ("Staged {0} -> {1} ({2} files, licences preserved)" -f `
                $package.FolderName, $targetPath, $copiedCount)
}

Write-Host "Third-party inputs staged."
