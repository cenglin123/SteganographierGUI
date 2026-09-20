# Pure/parse-only tests for the registry deletion guardrail.
#
# HARD CONSTRAINT: this suite must never touch the real registry. It does not create,
# delete, read or write any registry key, and it never invokes reg.exe. Every branch is
# exercised through injected delete invokers and injected existence probes.
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "context-menu\RegistryDeleteSafety.ps1")

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function New-QueuedProbe {
    param([bool[]]$Answers)
    $state = @{ Index = 0; Answers = $Answers }
    return {
        param($Path)
        $position = [math]::Min($state.Index, $state.Answers.Count - 1)
        $state.Index++
        return [bool]$state.Answers[$position]
    }.GetNewClosure()
}

function Invoke-ExpectThrow {
    param([scriptblock]$Action)
    try {
        & $Action | Out-Null
    } catch {
        return $_.Exception.Message
    }
    return $null
}

# --- 1. Out-of-scope targets must be rejected BEFORE any delete invoker runs -----------
$script:invokerRan = $false
function Assert-RejectedWithoutInvocation {
    param([string]$Key, [string]$ExpectedPattern)
    $script:invokerRan = $false
    $message = Invoke-ExpectThrow {
        Remove-RegistryKeyTolerant -Key $Key -DeleteInvoker {
            param($Target)
            $script:invokerRan = $true
            [pscustomobject]@{ ExitCode = 0; Output = "unexpected invocation: $Target" }
        }
    }
    Assert-True (-not $script:invokerRan) "the delete invoker ran for rejected key '$Key'"
    Assert-True ([bool]$message) "rejected key '$Key' did not throw"
    # Rejecting for the WRONG reason is not the same as being defended: a key that only
    # misses the allowlist would still be deletable if someone later added it there.
    if ($ExpectedPattern) {
        Assert-True ($message -match $ExpectedPattern) "key '$Key' was rejected, but not by the expected guard (wanted /$ExpectedPattern/): $message"
    }
}

$criticalAndBroad = @(
    'HKLM\SOFTWARE\Microsoft\Windows NT',
    'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion',
    'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon',
    'hklm/software/microsoft/windows nt/currentversion/',
    'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\\',
    'HKLM\SOFTWARE\Microsoft',
    'HKLM\SOFTWARE',
    'HKLM\SYSTEM\CurrentControlSet',
    'HKLM\SYSTEM\CurrentControlSet\Services',
    'HKLM\SYSTEM\'
)
foreach ($criticalPath in $criticalAndBroad) {
    Assert-RejectedWithoutInvocation -Key $criticalPath -ExpectedPattern 'critical system root'
}
Assert-RejectedWithoutInvocation -Key 'HKCU\Software\Not-An-Approved-Delete-Target' -ExpectedPattern 'explicit allowlist'
Assert-RejectedWithoutInvocation -Key 'HKCU' -ExpectedPattern 'Unsupported or overly broad'

# --- 2. Allowlist integrity: it must stay a minimal set of leaf keys -------------------
$targets = @($script:ApprovedRegistryDeleteTargets)
Assert-True ($targets.Count -ge 1) "the allowlist is empty"
Assert-True ($targets.Count -le 40) "the allowlist grew beyond the reviewed ceiling of 40 entries"
Assert-True (@($targets | Select-Object -Unique).Count -eq $targets.Count) "the allowlist contains duplicate entries"

$criticalRoots = @(
    'HKLM\SOFTWARE\Microsoft\Windows NT',
    'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT',
    'HKLM\SYSTEM\CurrentControlSet'
)
foreach ($target in $targets) {
    $normalizedTarget = ConvertTo-NormalizedRegistryKey -Key $target
    Assert-True ($normalizedTarget -ieq $target) "allowlist entry is not in normalized form: '$target' -> '$normalizedTarget'"

    $segments = @($normalizedTarget -split '\\')
    Assert-True ($segments.Count -ge 4) "allowlist entry is not a leaf key (fewer than 4 segments): '$normalizedTarget'"
    Assert-True ($segments[0] -match '^(?i:HKLM|HKCU|HKCR|HKU|HKCC)$') "allowlist entry has an unsupported root: '$normalizedTarget'"

    foreach ($criticalRoot in $criticalRoots) {
        $overlaps = $normalizedTarget -ieq $criticalRoot -or
            $normalizedTarget.StartsWith($criticalRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $criticalRoot.StartsWith($normalizedTarget + '\', [StringComparison]::OrdinalIgnoreCase)
        Assert-True (-not $overlaps) "allowlist entry overlaps critical root '$criticalRoot': '$normalizedTarget'"
    }
}

# A leaf-key set contains no entry that is an ancestor or descendant of another entry:
# otherwise one approval would silently cover a whole subtree.
for ($outer = 0; $outer -lt $targets.Count; $outer++) {
    for ($inner = $outer + 1; $inner -lt $targets.Count; $inner++) {
        $left = ConvertTo-NormalizedRegistryKey -Key $targets[$outer]
        $right = ConvertTo-NormalizedRegistryKey -Key $targets[$inner]
        $nested = $left.StartsWith($right + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $right.StartsWith($left + '\', [StringComparison]::OrdinalIgnoreCase)
        Assert-True (-not $nested) "allowlist is not a leaf set: '$left' and '$right' are nested"
    }
}

# --- 3. Normalization and provider path are stable and case-insensitive ----------------
foreach ($target in $targets) {
    $normalizedOnce = ConvertTo-NormalizedRegistryKey -Key $target
    $normalizedTwice = ConvertTo-NormalizedRegistryKey -Key $normalizedOnce
    Assert-True ($normalizedOnce -ieq $normalizedTwice) "normalization is not idempotent for '$target'"
    Assert-True ((Assert-RegistryDeleteTargetSafe -Key $target) -ieq $target) "an approved target was rejected or altered: '$target'"
}
Assert-True ((ConvertTo-RegistryProviderPath -Key 'HKLM\SOFTWARE\SteganographierExample') -eq 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\SteganographierExample') "HKLM provider path is wrong"
Assert-True ((ConvertTo-RegistryProviderPath -Key 'hkey_current_user\Software\SteganographierExample') -eq 'Registry::HKEY_CURRENT_USER\Software\SteganographierExample') "HKCU provider path is wrong"
Assert-True ((ConvertTo-NormalizedRegistryKey -Key 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\SteganographierExample\') -ieq 'HKLM\SOFTWARE\SteganographierExample') "Registry:: prefix was not normalized away"

# --- 4. State machine, driven entirely by injected probes ------------------------------
$absentKey = 'HKCU\Software\SteganographierGUI-Test-absent'
$script:invokerRan = $false
$absentResult = Remove-RegistryKeyTolerant -Key $absentKey -ExistenceProbe (New-QueuedProbe -Answers @($false)) -DeleteInvoker {
    param($Target)
    $script:invokerRan = $true
    [pscustomobject]@{ ExitCode = 0; Output = "unexpected invocation: $Target" }
}
Assert-True ($absentResult -eq 'absent') "an already absent key did not return 'absent'"
Assert-True (-not $script:invokerRan) "the delete invoker ran for an already absent key"

$deletedKey = 'HKCU\Software\SteganographierGUI-Test-deleted'
$deletedResult = Remove-RegistryKeyTolerant -Key $deletedKey -ExistenceProbe (New-QueuedProbe -Answers @($true, $false)) -DeleteInvoker {
    param($Target)
    [pscustomobject]@{ ExitCode = 0; Output = '' }
}
Assert-True ($deletedResult -eq 'deleted') "a successful deletion was not reported as 'deleted'"

$stillThereKey = 'HKCU\Software\SteganographierGUI-Test-still-there'
$stillThereMessage = Invoke-ExpectThrow {
    Remove-RegistryKeyTolerant -Key $stillThereKey -ExistenceProbe (New-QueuedProbe -Answers @($true, $true)) -DeleteInvoker {
        param($Target)
        [pscustomobject]@{ ExitCode = 0; Output = '' }
    }
}
Assert-True ([bool]$stillThereMessage) "exit code 0 with the target still present did not throw"
Assert-True ($stillThereMessage -match 'still exists') "the exit-0-but-present failure was not described: $stillThereMessage"

$failedKey = 'HKCU\Software\SteganographierGUI-Test-failed'
$failedMessage = Invoke-ExpectThrow {
    Remove-RegistryKeyTolerant -Key $failedKey -ExistenceProbe (New-QueuedProbe -Answers @($true, $true)) -DeleteInvoker {
        param($Target)
        [pscustomobject]@{ ExitCode = 1; Output = 'simulated failure after a partial change' }
    }
}
Assert-True ([bool]$failedMessage) "a failed deletion did not throw"
Assert-True ($failedMessage -match 'Contents may have changed') "a failed deletion did not warn that contents may have changed: $failedMessage"
Assert-True ($failedMessage -notmatch '(?i)absent/skip|no change|unchanged') "a failed deletion incorrectly claimed that nothing changed: $failedMessage"

$threwKey = 'HKCU\Software\SteganographierGUI-Test-threw'
$threwMessage = Invoke-ExpectThrow {
    Remove-RegistryKeyTolerant -Key $threwKey -ExistenceProbe (New-QueuedProbe -Answers @($true, $true)) -DeleteInvoker {
        param($Target)
        throw 'simulated invoker explosion'
    }
}
Assert-True ([bool]$threwMessage) "an invoker that threw did not propagate a failure"
Assert-True ($threwMessage -match 'Contents may have changed') "an invoker that threw did not warn that contents may have changed: $threwMessage"

# --- 5. Every key the uninstaller deletes must already be approved ---------------------
# Pure parse: extract the key arrays each consumer declares and require the allowlist to be
# EXACTLY their union. Minimality has two halves: a key that is deleted but not approved
# fails at runtime, and a key that is approved but never deleted is unnecessary attack
# surface. Structural "leaf set" checks alone cannot catch either kind of drift.
function Get-DeclaredKeyArray {
    param([string]$Path, [string]$AnchorPattern, [string]$What)
    Assert-True (Test-Path -LiteralPath $Path) "expected consumer script is missing: $Path"
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $block = [regex]::Match($text, $AnchorPattern)
    Assert-True ($block.Success) "could not locate the $What key array in $(Split-Path $Path -Leaf)"
    return @([regex]::Matches($block.Groups[1].Value, '["'']([^"'']+)["'']') | ForEach-Object { $_.Groups[1].Value })
}

$uninstallPath = Join-Path $repoRoot "context-menu\Uninstall-ContextMenu.ps1"
$uninstallText = Get-Content -LiteralPath $uninstallPath -Raw -Encoding UTF8
$uninstallerKeys = Get-DeclaredKeyArray -Path $uninstallPath -AnchorPattern '(?s)\$keys\s*=\s*@\((.*?)\)' -What 'uninstaller'
$migrationKeys = Get-DeclaredKeyArray -Path (Join-Path $repoRoot "scripts\upgrade\migrate-legacy-install.ps1") -AnchorPattern '(?s)\$extraKeys\s*=\s*@\((.*?)\)' -What 'migration'
$declaredKeys = @(@($uninstallerKeys + $migrationKeys) | Sort-Object -Unique)
Assert-True ($uninstallerKeys.Count -ge 1) "the uninstaller deletes no keys (the parse found none)"
Assert-True ($declaredKeys.Count -ge 1) "the consumers declare no registry keys at all"

foreach ($neededKey in $declaredKeys) {
    $isApproved = @($script:ApprovedRegistryDeleteTargets | Where-Object { $_ -ieq $neededKey }).Count -gt 0
    Assert-True $isApproved "a consumer deletes '$neededKey', which the allowlist does not approve"
}
foreach ($approvedKey in $script:ApprovedRegistryDeleteTargets) {
    $isUsed = @($declaredKeys | Where-Object { $_ -ieq $approvedKey }).Count -gt 0
    Assert-True $isUsed "the allowlist approves '$approvedKey', which no consumer deletes - remove it or justify it explicitly"
}

# The uninstaller must actually route through the guardrail rather than calling reg.exe.
Assert-True ($uninstallText -notmatch '(?m)^\s*&\s*reg\.exe\s+delete') "Uninstall-ContextMenu.ps1 still calls reg.exe delete directly"
Assert-True ($uninstallText -match 'Remove-RegistryKeyTolerant') "Uninstall-ContextMenu.ps1 does not call the guarded deletion helper"

Write-Host "Registry deletion safety tests passed (pure/parse-only; no registry access)."
