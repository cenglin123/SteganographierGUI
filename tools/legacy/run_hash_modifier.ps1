param([string]$FilePath)

$hashModifierPath = Join-Path $PSScriptRoot "hash_modifier.exe"

function Show-Notification {
    param ([string]$Title, [string]$Message)
    Add-Type -AssemblyName System.Windows.Forms
    $global:balmsg = New-Object System.Windows.Forms.NotifyIcon
    $path = (Get-Process -id $pid).Path
    $balmsg.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
    $balmsg.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    $balmsg.BalloonTipText = $Message
    $balmsg.BalloonTipTitle = $Title
    $balmsg.Visible = $true
    $balmsg.ShowBalloonTip(5000)
}

try {
    $logPath = Join-Path $PSScriptRoot "hash_modifier_log.txt"
    $output = & $hashModifierPath $FilePath 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $log = "执行时间: $(Get-Date)`n"
    $log += "命令: $hashModifierPath $FilePath`n"
    $log += "退出代码: $exitCode`n"
    $log += "输出:`n$output`n"
    $log += "--------------------------------------------------`n"
    $log | Out-File -Append -FilePath $logPath
    if ($exitCode -eq 0 -and $output -match "Modified file hash^|Hash modification completed") {
        Show-Notification -Title "哈希值修改" -Message "操作已成功完成。文件哈希值已修改。"
    } else {
        Show-Notification -Title "哈希值修改" -Message "操作可能未成功完成。请检查日志文件了解详情。"
    }
} catch {
    $errorMessage = $_.Exception.Message
    Show-Notification -Title "哈希值修改" -Message "发生错误。详细信息已记录到日志文件。"
    "错误: $errorMessage" | Out-File -Append -FilePath $logPath
}
