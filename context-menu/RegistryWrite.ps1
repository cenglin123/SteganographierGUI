# Registry value writer shared by the context-menu installer and its tests.
# Dot-sourced by Install-ContextMenu.ps1 so the exact shipping code can be
# exercised against scratch keys by scripts/test-context-menu-registry-write.ps1.
#
# Why the value is handed to reg.exe as a finished, verbatim command line:
#
#   * `& reg.exe @argumentArray` (what v1.3.10 shipped) leaves the marshalling to
#     PowerShell. Windows PowerShell 5.1 quotes an argument that contains spaces
#     but does NOT escape embedded double quotes, so a command value such as
#       "D:\Program Files\...\SteganographierGUI.exe" -i "%1" -o "%1_hidden.mp4" -t mp4
#     reached reg.exe as `""D:\Program Files\...exe" -i "%1" ..."` -> reg.exe
#     answered "ERROR: Invalid syntax." The archive still installed steg.cmd and
#     updated PATH first, so it failed midway leaving a half-registered menu.
#
#   * Routing through `cmd.exe /c "reg <argline>"` fixes that case, but cmd
#     re-parses the line and the backslash escapes reg.exe needs ('\"') desync
#     cmd's own quote tracking, so values containing cmd metacharacters
#     (& | ^ < >) are split or silently mangled.
#
# Handing the finished command line straight to CreateProcess avoids both parsers:
# cmd never sees it, and reg.exe applies the documented \" escaping itself.
# Verified against paths containing spaces, & | ^ % ! ( ) and non-ASCII text.

function Get-RegExePath {
    # CommandStore is read by 64-bit Explorer, so the 64-bit reg.exe must be used
    # even when this script is started from a 32-bit PowerShell: there System32 is
    # redirected to SysWOW64 and HKLM\SOFTWARE writes would land in WOW6432Node.
    if ([Environment]::Is64BitProcess) {
        return (Join-Path $env:SystemRoot 'System32\reg.exe')
    }
    $sysnativePath = Join-Path $env:SystemRoot 'Sysnative\reg.exe'
    if (Test-Path -LiteralPath $sysnativePath -PathType Leaf) {
        return $sysnativePath
    }
    return (Join-Path $env:SystemRoot 'System32\reg.exe')
}

function Build-RegAddCommandLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $argumentList = @("add", $Key)
    if ($Name) {
        $argumentList += @("/v", $Name)
    } else {
        $argumentList += "/ve"
    }
    $argumentList += @("/t", "REG_SZ", "/d", $Value, "/f")

    return (($argumentList | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' ')
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

    if (-not $PSCmdlet.ShouldProcess($Key, "Set registry value '$Name' to '$Value'")) {
        return
    }

    $processInfo = New-Object Diagnostics.ProcessStartInfo
    $processInfo.FileName = Get-RegExePath
    $processInfo.Arguments = Build-RegAddCommandLine -Key $Key -Name $Name -Value $Value
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true

    # reg.exe writes a single short line, far below the pipe buffer, so reading
    # stdout then stderr cannot deadlock here.
    $childProcess = [Diagnostics.Process]::Start($processInfo)
    $standardOutput = $childProcess.StandardOutput.ReadToEnd()
    $standardError = $childProcess.StandardError.ReadToEnd()
    $childProcess.WaitForExit()

    if ($childProcess.ExitCode -ne 0) {
        $detailText = (@($standardOutput, $standardError) |
            Where-Object { $_ } | Out-String).Trim()
        throw "reg.exe failed for '$Key' with exit code $($childProcess.ExitCode) : $detailText"
    }
}
