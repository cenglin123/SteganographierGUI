param([string[]]$Paths)

$ErrorActionPreference = "Stop"
$installDirectory = Split-Path -Parent $PSScriptRoot
$program = Get-ChildItem -LiteralPath $installDirectory -Filter "SteganographierGUI*.exe" -File |
    Select-Object -First 1
if (-not $program) {
    throw "SteganographierGUI executable was not found in '$installDirectory'."
}

$selection = New-Object System.Collections.Generic.List[string]
foreach ($path in $Paths) {
    if ($path) {
        $selection.Add($path)
    }
}

if ($selection.Count -eq 0) {
    $shell = New-Object -ComObject Shell.Application
    foreach ($window in $shell.Windows()) {
        try {
            foreach ($item in $window.Document.SelectedItems()) {
                if ($item.Path) {
                    $selection.Add([string]$item.Path)
                }
            }
        } catch {
            continue
        }
    }
}

if ($selection.Count -eq 0) {
    Start-Process -FilePath $program.FullName
    exit 0
}

$quotedPaths = $selection | Select-Object -Unique | ForEach-Object {
    '"{0}"' -f ($_ -replace '"', '\"')
}
Start-Process -FilePath $program.FullName -ArgumentList ("-rb " + ($quotedPaths -join " "))
