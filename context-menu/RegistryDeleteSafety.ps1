$script:ApprovedRegistryDeleteTargets = @(
    'HKCR\*\shell\Steganographier',
    'HKCR\Directory\shell\Steganographier',
    'HKCR\Directory\Background\shell\openSteganographier',
    'HKLM\SOFTWARE\Classes\SteganographierFile',
    'HKLM\SOFTWARE\Classes\.steg',
    'HKCU\Software\Classes\SteganographierFile',
    'HKCU\Software\Classes\.steg',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SteganographierGUI',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\hideMp4',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\hideMkv',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\modifyHash',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\openHashModifier',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\reveal',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\hideMp4',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\hideMkv',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealFileCLI',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealFileGUI',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealDir',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\modifyHash',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\openHashModifier',
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\revealFile',
    'HKCU\Software\Classes\*\shell\Steganographier',
    'HKCU\Software\Classes\Directory\shell\Steganographier',
    'HKCU\Software\Classes\Directory\Background\shell\openSteganographier',
    'HKLM\SOFTWARE\Classes\*\shell\Steganographier',
    'HKLM\SOFTWARE\Classes\Directory\shell\Steganographier',
    'HKLM\SOFTWARE\Classes\Directory\Background\shell\openSteganographier'
)

function ConvertTo-NormalizedRegistryKey {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    $path = $Key.Trim().Replace('/', '\').TrimEnd('\')
    $path = $path -replace '^(?i:Registry::)', ''
    $rootAliases = @{
        'HKEY_LOCAL_MACHINE' = 'HKLM'
        'HKEY_CURRENT_USER' = 'HKCU'
        'HKEY_CLASSES_ROOT' = 'HKCR'
        'HKEY_USERS' = 'HKU'
        'HKEY_CURRENT_CONFIG' = 'HKCC'
    }
    foreach ($longName in $rootAliases.Keys) {
        if ($path -imatch ('^' + [regex]::Escape($longName) + '(?=\\|$)')) {
            $path = $rootAliases[$longName] + $path.Substring($longName.Length)
            break
        }
    }
    $path = $path -replace '^(?i:(HKLM|HKCU|HKCR|HKU|HKCC)):(?=\\|$)', '$1'
    $segments = @($path -split '\\+' | Where-Object { $_.Length -gt 0 })
    if ($segments.Count -lt 2 -or $segments[0] -notmatch '^(?i:HKLM|HKCU|HKCR|HKU|HKCC)$') {
        throw "Unsupported or overly broad registry key '$Key'."
    }
    return ($segments -join '\')
}

function ConvertTo-RegistryProviderPath {
    param([Parameter(Mandatory = $true)][string]$Key)

    $normalized = ConvertTo-NormalizedRegistryKey -Key $Key
    $parts = $normalized -split '\\', 2
    $rootNames = @{
        'HKLM' = 'HKEY_LOCAL_MACHINE'
        'HKCU' = 'HKEY_CURRENT_USER'
        'HKCR' = 'HKEY_CLASSES_ROOT'
        'HKU' = 'HKEY_USERS'
        'HKCC' = 'HKEY_CURRENT_CONFIG'
    }
    return "Registry::$($rootNames[$parts[0].ToUpperInvariant()])\$($parts[1])"
}

function Assert-RegistryDeleteTargetSafe {
    param([Parameter(Mandatory = $true)][string]$Key)

    $normalized = ConvertTo-NormalizedRegistryKey -Key $Key
    $criticalRoots = @(
        'HKLM\SOFTWARE\Microsoft\Windows NT',
        'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT',
        'HKLM\SYSTEM\CurrentControlSet'
    )
    foreach ($criticalRoot in $criticalRoots) {
        if ($normalized -ieq $criticalRoot -or
            $normalized.StartsWith($criticalRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $criticalRoot.StartsWith($normalized + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing registry deletion at or around critical system root '$normalized'."
        }
    }

    $approved = @($script:ApprovedRegistryDeleteTargets | Where-Object { $_ -ieq $normalized }).Count -gt 0
    $testTarget = $normalized -match '^(?i:HKCU\\Software\\SteganographierGUI-Test-[^\\]+)(?:\\.*)?$'
    if (-not $approved -and -not $testTarget) {
        throw "Refusing registry deletion outside the explicit allowlist: '$normalized'."
    }
    return $normalized
}

function Remove-RegistryKeyTolerant {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [scriptblock]$DeleteInvoker,
        [scriptblock]$ExistenceProbe
    )

    $normalized = Assert-RegistryDeleteTargetSafe -Key $Key
    $providerPath = ConvertTo-RegistryProviderPath -Key $normalized

    # Existence is probed through an injectable scriptblock so the safety tests can exercise
    # every branch (present / absent / deleted / failed) without touching the real registry.
    if (-not $ExistenceProbe) {
        $ExistenceProbe = { param($Path) Test-Path -LiteralPath $Path }
    }
    if (-not (& $ExistenceProbe $providerPath)) {
        return 'absent'
    }

    if (-not $DeleteInvoker) {
        $DeleteInvoker = {
            param($Target)
            $regExe = Join-Path $env:SystemRoot 'System32\reg.exe'
            if (-not (Test-Path -LiteralPath $regExe -PathType Leaf)) {
                throw "reg.exe was not found at '$regExe'."
            }
            $output = & cmd.exe /d /c "`"$regExe`" delete `"$Target`" /f 2>&1"
            [pscustomobject]@{
                ExitCode = $LASTEXITCODE
                Output = ($output | Out-String).Trim()
            }
        }
    }

    try {
        $commandResult = & $DeleteInvoker $normalized
    }
    catch {
        $afterThrow = & $ExistenceProbe $providerPath
        throw "Registry deletion command threw for '$normalized'. Target existed before; exists after: $afterThrow. Contents may have changed. $($_.Exception.Message)"
    }

    $existsAfter = & $ExistenceProbe $providerPath
    if ($commandResult.ExitCode -eq 0 -and -not $existsAfter) {
        return 'deleted'
    }
    if ($commandResult.ExitCode -eq 0) {
        throw "reg.exe reported success for '$normalized', but the target still exists."
    }
    throw "reg.exe failed for '$normalized' with exit code $($commandResult.ExitCode). Target existed before; exists after: $existsAfter. Contents may have changed. Output: $($commandResult.Output)"
}
