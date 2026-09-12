[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
)

$ErrorActionPreference = "Stop"
$installDirectory = [IO.Path]::GetFullPath($InstallRoot).TrimEnd("\")
$toolsDirectory = Join-Path $installDirectory "tools"
$program = Get-ChildItem -LiteralPath $installDirectory -Filter "SteganographierGUI*.exe" -File |
    Select-Object -First 1

if (-not $program) {
    throw "SteganographierGUI executable was not found in '$installDirectory'."
}

$hashModifier = Join-Path $toolsDirectory "hash_modifier.exe"
$selectionLauncher = Join-Path $toolsDirectory "launch_from_selection.ps1"
$icon = Join-Path $installDirectory "modules\favicon.ico"
foreach ($requiredFile in @($hashModifier, $selectionLauncher, $icon)) {
    if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
        throw "Required context-menu file is missing: $requiredFile"
    }
}

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-RegistryString {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $arguments = @("add", $Key)
    if ($Name) {
        $arguments += @("/v", $Name)
    } else {
        $arguments += "/ve"
    }
    $arguments += @("/t", "REG_SZ", "/d", $Value, "/f")

    if ($PSCmdlet.ShouldProcess($Key, "Set registry value '$Name' to '$Value'")) {
        # cmd.exe wrapper: on PS 5.1 an outer ErrorActionPreference='Stop' promotes any
        # captured native stderr (2>$null / 2>&1) to a terminating NativeCommandError;
        # merging into stdout inside cmd avoids that. Also fixes bare reg.exe resolution
        # under the 32-bit file-system redirector.
        $argLine = ($arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
        $output = & cmd.exe /c "reg $argLine 2>&1"
        if ($LASTEXITCODE -ne 0) {
            throw "reg.exe failed for '$Key' with exit code $LASTEXITCODE : $(($output | Out-String).Trim())"
        }
    }
}

if (-not $WhatIfPreference -and -not (Test-Administrator)) {
    throw "Run this script as administrator."
}

$programPath = $program.FullName
$stegLauncher = Join-Path $toolsDirectory "steg.cmd"
$launcherContent = "@echo off`r`n`"%~dp0..\$($program.Name)`" %*`r`n"
if ($PSCmdlet.ShouldProcess($stegLauncher, "Create command launcher")) {
    [IO.File]::WriteAllText($stegLauncher, $launcherContent, (New-Object Text.ASCIIEncoding))
}

$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$pathEntries = @($machinePath -split ";" | Where-Object { $_.Trim() })
$normalizedTools = $toolsDirectory.TrimEnd("\")
$pathExists = $pathEntries | Where-Object {
    ([Environment]::ExpandEnvironmentVariables($_.Trim().Trim('"')).TrimEnd("\")) -ieq $normalizedTools
}
if (-not $pathExists -and $PSCmdlet.ShouldProcess($toolsDirectory, "Add tools directory to the machine PATH")) {
    $newMachinePath = (@($pathEntries) + $toolsDirectory) -join ";"
    # SetEnvironmentVariable writes REG_SZ and silently downgrades a REG_EXPAND_SZ Path.
    # Preserve the original value kind (and %VAR% tokens) by writing the key directly.
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $kind = (Get-Item $key).GetValueKind('Path')
    Set-ItemProperty -LiteralPath $key -Name Path -Value $newMachinePath -Type $kind
    & cmd.exe /c 'rundll32.exe user32.dll,UpdatePerUserSystemParameters 1,True >nul 2>&1' | Out-Null
}

$commandStore = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell"
$fileMenu = "HKCR\*\shell\Steganographier"
$directoryMenu = "HKCR\Directory\shell\Steganographier"
$backgroundMenu = "HKCR\Directory\Background\shell\openSteganographier"

Set-RegistryString -Key $fileMenu -Name "MUIVerb" -Value "Steganographier" -WhatIf:$WhatIfPreference
Set-RegistryString -Key $fileMenu -Name "SubCommands" -Value "hideMp4;hideMkv;revealFileCLI;revealFileGUI;modifyHash;openHashModifier" -WhatIf:$WhatIfPreference
Set-RegistryString -Key $fileMenu -Name "Icon" -Value $programPath -WhatIf:$WhatIfPreference
Set-RegistryString -Key $directoryMenu -Name "MUIVerb" -Value "Steganographier" -WhatIf:$WhatIfPreference
Set-RegistryString -Key $directoryMenu -Name "SubCommands" -Value "hideMp4;hideMkv;revealDir;modifyHash;openHashModifier" -WhatIf:$WhatIfPreference
Set-RegistryString -Key $directoryMenu -Name "Icon" -Value $programPath -WhatIf:$WhatIfPreference

$commands = @(
    @{ Name = "hideMp4"; Label = "Hide as MP4"; Command = ('"{0}" -i "%1" -o "%1_hidden.mp4" -t mp4' -f $programPath) },
    @{ Name = "hideMkv"; Label = "Hide as MKV"; Command = ('"{0}" -i "%1" -o "%1_hidden.mkv" -t mkv' -f $programPath) },
    @{ Name = "revealFileCLI"; Label = "Reveal file"; Command = ('"{0}" -i "%1" -r' -f $programPath) },
    @{ Name = "revealFileGUI"; Label = "Reveal selected files in GUI"; Command = ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" "%1"' -f $selectionLauncher) },
    @{ Name = "revealDir"; Label = "Reveal directory"; Command = ('"{0}" -i "%1" -rd -rdgui' -f $programPath) },
    @{ Name = "modifyHash"; Label = "Modify file hash"; Command = ('"{0}" "%1"' -f $hashModifier); Icon = $icon },
    @{ Name = "openHashModifier"; Label = "Open hash modifier"; Command = ('"{0}" --gui' -f $hashModifier); Icon = $icon }
)

foreach ($definition in $commands) {
    $commandKey = "$commandStore\$($definition.Name)"
    Set-RegistryString -Key $commandKey -Value $definition.Label -WhatIf:$WhatIfPreference
    if ($definition.Icon) {
        Set-RegistryString -Key $commandKey -Name "Icon" -Value $definition.Icon -WhatIf:$WhatIfPreference
    }
    Set-RegistryString -Key "$commandKey\command" -Value $definition.Command -WhatIf:$WhatIfPreference
}

Set-RegistryString -Key $backgroundMenu -Value "Open SteganographierGUI" -WhatIf:$WhatIfPreference
Set-RegistryString -Key $backgroundMenu -Name "Icon" -Value $programPath -WhatIf:$WhatIfPreference
Set-RegistryString -Key "$backgroundMenu\command" -Value ('"{0}"' -f $programPath) -WhatIf:$WhatIfPreference

Write-Host "Context menu configured for: $programPath"
Write-Host "Open a new terminal before using the steg command."
