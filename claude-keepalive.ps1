#requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Prompt Cache Keepalive Script

.DESCRIPTION
    Prevents 5-minute cache TTL expiration by sending periodic no-op messages.
    The Anthropic API has a 5-minute TTL on prompt cache entries.
    After 5 minutes of inactivity, cache is evicted and costs increase 10x.
    For 200K context: $0.60 -> $6.00 per request

.PARAMETER Interval
    Seconds between keepalive messages (default: 240 = 4 minutes)

.PARAMETER WindowTitle
    Window title to search for (default: "claude")

.EXAMPLE
    .\claude-keepalive.ps1
    Start keepalive with default settings

.EXAMPLE
    .\claude-keepalive.ps1 -Interval 180
    Send keepalive every 3 minutes
#>

[CmdletBinding()]
param(
    [int]$Interval = 240,
    [string]$WindowTitle = "claude"
)

$script:Running = $true

function Send-Keepalive {
    param([string]$Title)

    # Find window with title containing "claude"
    $hwnd = $null
    Get-Process | Where-Object { $_.MainWindowTitle -match $Title } | ForEach-Object {
        $hwnd = $_.MainWindowHandle
    }

    if (-not $hwnd) {
        Write-Warning "No window with title containing '$Title' found"
        return $false
    }

    try {
        # Use Windows API to send keys
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);
}
"@

        # Bring window to foreground
        [WinAPI]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 100

        # Send comment (no-op)
        $timestamp = Get-Date -Format "HHmmss"
        $keys = "# keepalive $timestamp"

        # Use WScript.Shell for sending keys
        $shell = New-Object -ComObject WScript.Shell
        $shell.SendKeys($keys)
        Start-Sleep -Milliseconds 100
        $shell.SendKeys("{ENTER}")
        Start-Sleep -Milliseconds 500
        $shell.SendKeys("^c")  # Ctrl+C to cancel

        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Sent keepalive" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to send keepalive: $_"
        return $false
    }
}

# Cleanup handler
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $script:Running = $false
    Write-Host "`n[Keepalive] Stopping..." -ForegroundColor Yellow
}

Write-Host "Claude Code Prompt Cache Keepalive" -ForegroundColor Cyan
Write-Host "Interval: $Interval seconds (4 minutes)" -ForegroundColor Cyan
Write-Host "Target window title: $WindowTitle" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Yellow

while ($script:Running) {
    Send-Keepalive -Title $WindowTitle
    Start-Sleep -Seconds $Interval
}
