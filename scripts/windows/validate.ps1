#requires -Version 5.1
<#
.SYNOPSIS
  Validate optimizer state from ~/.claude/settings.json only.
#>

[CmdletBinding()]
param(
  [ValidateSet('official','tuned')]
  [string]$Profile,

  [ValidateSet('standard','max')]
  [string]$Privacy,

  [switch]$ExpectUnsafe
)

$ErrorActionPreference = 'Stop'
$SettingsFile = Join-Path $env:USERPROFILE '.claude\settings.json'
$failed = 0

function Pass([string]$name) { Write-Host "[PASS] $name" -ForegroundColor Green }
function Fail([string]$name) { Write-Host "[FAIL] $name" -ForegroundColor Red; $script:failed++ }
function Check([string]$name, [bool]$condition) { if ($condition) { Pass $name } else { Fail $name } }

if (-not (Test-Path -LiteralPath $SettingsFile)) {
  throw "Missing $SettingsFile"
}

$settings = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json -AsHashtable
$permissions = @{}
if ($settings.ContainsKey('permissions') -and $settings['permissions'] -is [hashtable]) { $permissions = $settings['permissions'] }
$hooks = @{}
if ($settings.ContainsKey('hooks') -and $settings['hooks'] -is [hashtable]) { $hooks = $settings['hooks'] }
$envMap = @{}
if ($settings.ContainsKey('env') -and $settings['env'] -is [hashtable]) { $envMap = $settings['env'] }

Check 'schema' ($settings.ContainsKey('$schema'))
Check 'env_is_object' ($settings['env'] -is [hashtable])
Check 'hooks_pretooluse' ($hooks.ContainsKey('PreToolUse'))
Check 'hooks_sessionstart' ($hooks.ContainsKey('SessionStart'))
Check 'permissions_deny' ($permissions.ContainsKey('deny'))
Check 'has_disable_telemetry' ($envMap.ContainsKey('DISABLE_TELEMETRY') -and $envMap['DISABLE_TELEMETRY'] -eq '1')

if ($PSBoundParameters.ContainsKey('Privacy')) {
  if ($Privacy -eq 'max') {
    Check 'has_max_privacy_flag' ($envMap.ContainsKey('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC') -and $envMap['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] -eq '1')
  } else {
    Check 'has_max_privacy_flag' (-not $envMap.ContainsKey('CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'))
  }
}

if ($PSBoundParameters.ContainsKey('Profile')) {
  if ($Profile -eq 'tuned') {
    Check 'has_tuned_key' ($envMap.ContainsKey('CLAUDE_CODE_DISABLE_AUTO_MEMORY'))
  } else {
    Check 'has_tuned_key' (-not $envMap.ContainsKey('CLAUDE_CODE_DISABLE_AUTO_MEMORY'))
  }
}

$unsafeAllowPresent = $permissions.ContainsKey('allow') -and $permissions['allow'].Count -gt 0
if ($ExpectUnsafe) {
  Check 'unsafe_allow_present' $unsafeAllowPresent
} else {
  Check 'unsafe_allow_present' (-not $unsafeAllowPresent)
}

$preToolUseJson = $hooks['PreToolUse'] | ConvertTo-Json -Depth 10
Check 'pretooluse hook configured' ($preToolUseJson -match 'pretooluse')

if ($failed -gt 0) {
  throw "Validation failed: $failed checks failed."
}

Write-Host 'Validation passed.' -ForegroundColor Green
