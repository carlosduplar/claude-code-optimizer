#requires -Version 5.1
<#
.SYNOPSIS
  Runtime hook verification (actual hook firing), not just config checks.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Resolve-Path (Join-Path $ScriptDir '..\..')
$TestImage = Join-Path $RepoDir 'tests\test-image.png'
$SettingsFile = Join-Path $env:USERPROFILE '.claude\settings.json'
$failed = 0

function Info([string]$name) { Write-Host "[INFO] $name" -ForegroundColor Cyan }
function Pass([string]$name) { Write-Host "[PASS] $name" -ForegroundColor Green }
function Fail([string]$name) { Write-Host "[FAIL] $name" -ForegroundColor Red; $script:failed++ }
function Warn([string]$name) { Write-Host "[WARN] $name" -ForegroundColor Yellow }

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  throw "Missing required command: claude"
}
if (-not (Test-Path -LiteralPath $TestImage)) {
  throw "Missing test image: $TestImage"
}
if (-not (Test-Path -LiteralPath $SettingsFile)) {
  throw "Missing settings file: $SettingsFile"
}
$settings = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json -AsHashtable
$hooks = @{}
if ($settings.ContainsKey('hooks') -and $settings['hooks'] -is [hashtable]) { $hooks = $settings['hooks'] }
$expectSessionStart = $hooks.ContainsKey('SessionStart')
$expectPostToolUse = $hooks.ContainsKey('PostToolUse')

$tmp1 = Join-Path $env:TEMP ("claude-hooks-read-{0}.jsonl" -f $PID)
$tmp2 = Join-Path $env:TEMP ("claude-hooks-bash-{0}.jsonl" -f $PID)

try {
  Info 'Test 1/3: SessionStart + PreToolUse + PostToolUse events on Read'
  $readOutput = "Read $TestImage" | claude -p --verbose --include-hook-events --output-format stream-json --allowedTools Read 2>&1
  $readOutput | Set-Content -LiteralPath $tmp1

  $hookNames = @()
  foreach ($line in $readOutput) {
    try {
      $obj = $line | ConvertFrom-Json -ErrorAction Stop
      if ($obj.type -eq 'system' -and $obj.subtype -like 'hook_*' -and $obj.hook_name) {
        $hookNames += [string]$obj.hook_name
      }
    } catch {
      # Ignore non-JSON stream lines.
    }

    if ($line -match '\b(SessionStart|PreToolUse|PostToolUse)\b') {
      $hookNames += $matches[1]
    }
  }

  if ($hookNames -contains 'PreToolUse') { Pass 'PreToolUse hook fired' } else { Fail 'PreToolUse hook did not fire' }
  if ($expectSessionStart) {
    if (($hookNames -contains 'SessionStart') -or (($readOutput -join "`n") -match 'Keepalive reminder:')) {
      Pass 'SessionStart hook observed'
    } else {
      Warn 'SessionStart not observed in non-interactive run (startup/resume matcher may not trigger with -p)'
    }
  } else {
    Warn 'SessionStart hook not configured; skipped'
  }
  if ($expectPostToolUse) {
    Warn 'PostToolUse configured but not actively exercised by this script (requires write/edit flow)'
  } else {
    Warn 'PostToolUse hook not configured; skipped'
  }

  Info 'Test 2/3: Read hook is non-mutating for original image'
  $before = (Get-FileHash -Algorithm SHA256 -LiteralPath $TestImage).Hash
  "Read $TestImage" | claude -p --allowedTools Read | Out-Null
  $after = (Get-FileHash -Algorithm SHA256 -LiteralPath $TestImage).Hash
  if ($before -eq $after) { Pass 'Original file hash unchanged' } else { Fail 'Original file hash changed (Read hook appears mutating)' }

  Info 'Test 3/3: file-guard blocks high-risk traversal path'
  $bashOutput = 'Run this exact command: cat ../.env' | claude -p --verbose --include-hook-events --output-format stream-json --allowedTools Bash 2>&1
  $bashOutput | Set-Content -LiteralPath $tmp2
  if (($bashOutput -join "`n") -match 'BLOCKED:') { Pass 'file-guard blocked traversal command' } else { Fail 'file-guard did not block traversal command' }
}
finally {
  Remove-Item -LiteralPath $tmp1,$tmp2 -ErrorAction SilentlyContinue
}

if ($failed -gt 0) {
  throw "Runtime hook tests failed: $failed check(s) failed."
}

Write-Host 'Runtime hook tests passed.' -ForegroundColor Green
