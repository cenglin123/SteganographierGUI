# Stage the vendored third-party companion tool into the release stage.
#
# Authority: the user adjusted this DownKyi build themselves, so the copy that
# shipped inside the v1.3.9 installer is the reference - not the upstream GitHub
# release. 35 of its 36 files are byte-identical to upstream v1.6.1; the single
# exception (DownKyi.Core.dll, the user's own build) is tracked in git under
# vendor\downkyi-1.6.1\overrides\. That keeps the irreplaceable part in the
# repository as the single source of truth, while the 75 MB of publicly
# reproducible files are reproduced from a pinned, hash-verified archive instead
# of being committed.
#
# The acceptance gate is vendor\downkyi-1.6.1\MANIFEST.csv: every staged file is
# checked against the approved build's size and SHA256, and an unexpected file
# fails the build. "We fetched the right zip" is not the claim being made; "the
# staged tree is byte-identical to the build the author approved" is.
#
# The payload is never tracked by git; it is cached under .thirdparty-cache\
# (gitignored) and copied into the stage on each build.
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

# Pinned sources. Update all fields together on any bump; the manifest is what
# actually constrains the result, so a bumped upstream archive that no longer
# reproduces the approved build will fail rather than ship silently.
# ArchiveName stays ASCII so the cache path never depends on the console code page.
$packages = @(
    @{
        FolderName  = "B站视频下载工具-DownKyi-1.6.1"
        ArchiveName = "DownKyi-1.6.1.zip"
        ExpandName  = "DownKyi-1.6.1-expanded"
        Url         = "https://github.com/leiurayer/downkyi/releases/download/v1.6.1/DownKyi-1.6.1.zip"
        SizeBytes   = 32204639
        Sha256      = "d809c230c9dd9ab18a7cbafc413db2d93eca25e45c4df5fa6aaad3f253015986"
        # Tracked authority: per-file overrides plus the expected end state.
        VendorDir   = "vendor\downkyi-1.6.1"
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

function Get-RelativePath {
    param([string]$Root, [string]$FullPath)
    return ($FullPath.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/')
}

foreach ($package in $packages) {
    $archivePath = Join-Path $CacheDirectory $package.ArchiveName
    $expandPath = Join-Path $CacheDirectory $package.ExpandName
    $vendorPath = Join-Path $repoRoot $package.VendorDir
    $manifestPath = Join-Path $vendorPath "MANIFEST.csv"
    $overridePath = Join-Path $vendorPath "overrides"

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "The tracked manifest is missing: $manifestPath"
    }

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
        throw ("SHA256 mismatch for {0}: expected {1}, found {2}. Refusing to stage an unverified archive." -f `
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

    # --- apply the tracked overrides on top of the upstream tree ---
    $appliedOverrides = 0
    if (Test-Path -LiteralPath $overridePath -PathType Container) {
        foreach ($overrideFile in Get-ChildItem -LiteralPath $overridePath -Recurse -File) {
            $relative = Get-RelativePath -Root $overridePath -FullPath $overrideFile.FullName
            $overrideTarget = Join-Path $expandPath ($relative -replace '/', '\')
            $overrideParent = Split-Path -Parent $overrideTarget
            if (-not (Test-Path -LiteralPath $overrideParent)) {
                New-Item -ItemType Directory -Path $overrideParent -Force | Out-Null
            }
            Copy-Item -LiteralPath $overrideFile.FullName -Destination $overrideTarget -Force
            $appliedOverrides++
            Write-Host ("Applied tracked override: {0}" -f $relative)
        }
    }

    # --- copy the assembled tree into the stage ---
    $targetPath = Join-Path $DestinationDirectory $package.FolderName
    if (Test-Path -LiteralPath $targetPath) {
        Remove-Item -LiteralPath $targetPath -Recurse -Force
    }
    Copy-Item -LiteralPath $expandPath -Destination $targetPath -Recurse -Force

    # --- acceptance gate: the staged tree must equal the approved build ---
    $expected = @(Import-Csv -LiteralPath $manifestPath)
    if ($expected.Count -eq 0) {
        throw "The tracked manifest has no rows: $manifestPath"
    }
    $expectedByPath = @{}
    foreach ($row in $expected) {
        $expectedByPath[$row.relative_path] = $row
    }

    $stagedFiles = @{}
    foreach ($stagedFile in Get-ChildItem -LiteralPath $targetPath -Recurse -File) {
        $stagedFiles[(Get-RelativePath -Root $targetPath -FullPath $stagedFile.FullName)] = $stagedFile
    }

    $problems = @()
    foreach ($relative in $expectedByPath.Keys) {
        if (-not $stagedFiles.ContainsKey($relative)) {
            $problems += "missing: $relative"
            continue
        }
        $stagedFile = $stagedFiles[$relative]
        $row = $expectedByPath[$relative]
        if ($stagedFile.Length -ne [int64]$row.size_bytes) {
            $problems += ("size: {0} (staged {1}, approved {2})" -f `
                          $relative, $stagedFile.Length, $row.size_bytes)
            continue
        }
        $stagedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $stagedFile.FullName).Hash.ToLowerInvariant()
        if ($stagedHash -ne $row.sha256) {
            $problems += "sha256: $relative"
        }
    }
    foreach ($relative in $stagedFiles.Keys) {
        if (-not $expectedByPath.ContainsKey($relative)) {
            $problems += "unexpected: $relative"
        }
    }

    if ($problems.Count -gt 0) {
        throw ("Staged {0} does not match the approved build ({1} problem(s)):`n  {2}" -f `
               $package.FolderName, $problems.Count, ($problems -join "`n  "))
    }

    foreach ($mustKeep in $package.MustKeep) {
        if (-not (Test-Path -LiteralPath (Join-Path $targetPath $mustKeep) -PathType Leaf)) {
            throw "Required licence file was not staged: $mustKeep"
        }
    }

    Write-Host ("Staged {0}: {1} files, {2} tracked override(s), all match the approved v1.3.9 build" -f `
                $package.FolderName, $stagedFiles.Count, $appliedOverrides)
}

Write-Host "Third-party inputs staged."
