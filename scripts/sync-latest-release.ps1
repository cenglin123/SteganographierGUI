param(
    [Parameter(Mandatory = $true)]
    [string]$DestinationRoot,
    [string]$Repository = "cenglin123/SteganographierGUI"
)

$ErrorActionPreference = "Stop"
$headers = @{ "User-Agent" = "SteganographierGUI-release-sync" }
$release = Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$Repository/releases/latest"
$tag = [string]$release.tag_name
if ($tag -notmatch '^v\d+\.\d+\.\d+$') {
    throw "Latest release has an unexpected tag: '$tag'."
}

$destination = [IO.Path]::GetFullPath($DestinationRoot)
$releasesRoot = Join-Path $destination "releases"
$finalDirectory = Join-Path $releasesRoot $tag
if (Test-Path -LiteralPath $finalDirectory) {
    Write-Host "$tag is already mirrored at $finalDirectory."
    exit 0
}

$temporaryDirectory = Join-Path $destination ".download-$tag"
if (Test-Path -LiteralPath $temporaryDirectory) {
    Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
}
New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

try {
    $wantedAssets = $release.assets | Where-Object { $_.name -match '\.(zip|exe)$' -or $_.name -eq 'SHA256SUMS.txt' }
    foreach ($asset in $wantedAssets) {
        Invoke-WebRequest -Headers $headers -Uri $asset.browser_download_url -OutFile (Join-Path $temporaryDirectory $asset.name)
    }

    $checksumPath = Join-Path $temporaryDirectory "SHA256SUMS.txt"
    if (-not (Test-Path -LiteralPath $checksumPath)) {
        throw "Release $tag does not include SHA256SUMS.txt."
    }
    $verifiedNames = @{}
    foreach ($line in Get-Content -Encoding UTF8 $checksumPath) {
        if ($line -notmatch '^([0-9a-fA-F]{64})\s{2}(.+)$') {
            throw "Invalid checksum line: $line"
        }
        $expectedHash = $Matches[1].ToLowerInvariant()
        $assetPath = Join-Path $temporaryDirectory $Matches[2]
        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $assetPath).Hash.ToLowerInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Checksum mismatch for $($Matches[2])."
        }
        $verifiedNames[$Matches[2]] = $true
    }
    foreach ($asset in $wantedAssets | Where-Object { $_.name -ne 'SHA256SUMS.txt' }) {
        if (-not $verifiedNames.ContainsKey([string]$asset.name)) {
            throw "Release asset is not covered by SHA256SUMS.txt: $($asset.name)"
        }
    }

    New-Item -ItemType Directory -Path $releasesRoot -Force | Out-Null
    Move-Item -LiteralPath $temporaryDirectory -Destination $finalDirectory
    [IO.File]::WriteAllText((Join-Path $destination "CURRENT"), "$tag`n", (New-Object Text.UTF8Encoding($false)))
    Write-Host "Mirrored $tag to $finalDirectory."
}
catch {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
    throw
}
