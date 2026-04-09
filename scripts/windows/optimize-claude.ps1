#requires -Version 5.1
<#
.SYNOPSIS
  Claude Code optimizer (official baseline + tuned overlay)
#>

[CmdletBinding()]
param(
  [ValidateSet('official','tuned')]
  [string]$Profile = 'tuned',

  [ValidateSet('standard','max')]
  [string]$Privacy = 'max',

  [switch]$UnsafeAutoApprove,
  [switch]$AutoFormat,
  [switch]$DryRun,
  [switch]$SkipDeps,
  [switch]$Verify
)

$ErrorActionPreference = 'Stop'

function Write-Info([string]$m) { Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Ok([string]$m) { Write-Host "[OK] $m" -ForegroundColor Green }
function Write-Warn([string]$m) { Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err([string]$m) { Write-Host "[ERROR] $m" -ForegroundColor Red }

$ClaudeDir = Join-Path $env:USERPROFILE '.claude'
$SettingsFile = Join-Path $ClaudeDir 'settings.json'
$HooksDir = Join-Path $ClaudeDir 'hooks'

function Test-Dependencies {
  if ($SkipDeps) { return }
  $missing = @()
  if (-not (Get-Command python -ErrorAction SilentlyContinue) -and -not (Get-Command python3 -ErrorAction SilentlyContinue)) {
    $missing += 'python'
  }
  if ($missing.Count -gt 0) {
    throw "Missing required dependencies: $($missing -join ', ')"
  }
}

function Write-Hooks {
  if ($DryRun) {
    Write-Info "[dry-run] would write hooks under $HooksDir"
    return
  }

  New-Item -ItemType Directory -Force -Path $HooksDir | Out-Null

  $preToolUse = @'
param()
$ErrorActionPreference = 'Stop'
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$toolName = $payload.tool_name
$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.filePath }

if ($toolName -ne 'Read' -or -not $filePath -or -not (Test-Path -LiteralPath $filePath)) { exit 0 }

$ext = [IO.Path]::GetExtension($filePath).TrimStart('.').ToLowerInvariant()
$base = Join-Path $env:TEMP ("claude-read-{0}-{1}" -f [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(), $PID)

function Emit-Redirect([string]$target, [string]$note) {
  $obj = @{
    hookSpecificOutput = @{
      hookEventName = 'PreToolUse'
      permissionDecision = 'allow'
      updatedInput = @{ file_path = $target }
      additionalContext = $note
    }
  }
  $obj | ConvertTo-Json -Depth 10 -Compress | Write-Output
  exit 0
}

switch ($ext) {
  { $_ -in @('png','jpg','jpeg','webp','gif','bmp','tif','tiff') } {
    $magick = Get-Command magick -ErrorAction SilentlyContinue
    if ($magick) {
      $out = "$base.$ext"
      & $magick.Source $filePath -resize '2000x2000>' -quality '85' $out 2>$null
      if (Test-Path -LiteralPath $out) {
        Emit-Redirect -target $out -note 'Read hook used non-mutating optimized image copy.'
      }
    }
  }
  'pdf' {
    $pdftotext = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($pdftotext) {
      $out = "$base.txt"
      & $pdftotext.Source -layout $filePath $out 2>$null
      if ((Test-Path -LiteralPath $out) -and (Get-Item -LiteralPath $out).Length -gt 0) {
        Emit-Redirect -target $out -note 'Read hook used non-mutating extracted PDF text copy.'
      }
    }
  }
  { $_ -in @('doc','docx','xls','xlsx','ppt','pptx') } {
    $markitdown = Get-Command markitdown -ErrorAction SilentlyContinue
    if ($markitdown) {
      $out = "$base.md"
      & $markitdown.Source $filePath 2>$null | Out-File -FilePath $out -Encoding utf8
      if ((Test-Path -LiteralPath $out) -and (Get-Item -LiteralPath $out).Length -gt 0) {
        Emit-Redirect -target $out -note 'Read hook used non-mutating markitdown extraction copy.'
      }
    }
  }
}

exit 0
'@

  $fileGuard = @'
param()
$ErrorActionPreference = 'Stop'
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$toolName = $payload.tool_name
$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.filePath }
$command = $payload.tool_input.command
$cwd = $payload.cwd
$projectDir = $env:CLAUDE_PROJECT_DIR
if (-not $projectDir) { $projectDir = $cwd }
if (-not $projectDir) { $projectDir = (Get-Location).Path }
$projectDir = [IO.Path]::GetFullPath($projectDir)

$patterns = @(
  '\.env$', '\.env\.', '\.git\\|\.git/', '\.ssh\\|\.ssh/', 'id_rsa', 'id_ed25519', '\.pem$', '\.key$', 'credentials\.json$', 'secrets\.'
)

function Matches([string]$value) {
  if (-not $value) { return $false }
  foreach ($p in $patterns) {
    if ($value -match $p) { return $true }
  }
  return $false
}

function IsOutsideProject([string]$pathValue) {
  if (-not $pathValue) { return $false }
  $candidate = $pathValue.Replace('~', $env:USERPROFILE)
  try {
    $resolved = [IO.Path]::GetFullPath($candidate)
    return (-not ($resolved -eq $projectDir -or $resolved.StartsWith($projectDir + [IO.Path]::DirectorySeparatorChar)))
  } catch {
    return $false
  }
}

if ($toolName -in @('Write','Edit','MultiEdit')) {
  if (Matches $filePath) {
    [Console]::Error.WriteLine("BLOCKED: path '$filePath' matches protected pattern")
    exit 2
  }
  if (IsOutsideProject $filePath) {
    [Console]::Error.WriteLine("BLOCKED: write/edit outside workspace is blocked: '$filePath'")
    exit 2
  }
}

if ($toolName -eq 'Bash' -and (Matches $command)) {
  [Console]::Error.WriteLine('BLOCKED: bash command references protected path/pattern')
  exit 2
}

if ($toolName -eq 'Bash' -and $command -match '^\s*(cat|head|tail|grep|rg|find|Get-Content|type|Select-String|sls)\b') {
  if ($command -match '(^|\s)\.\.[\\/]+') {
    [Console]::Error.WriteLine('BLOCKED: path traversal is blocked for high-risk read commands')
    exit 2
  }
  $matches = [regex]::Matches($command, '(~?[\\/][^ ;|&]+|\.{1,2}[\\/][^ ;|&]+)')
  foreach ($m in $matches) {
    if (IsOutsideProject $m.Value) {
      [Console]::Error.WriteLine("BLOCKED: high-risk read command target outside workspace: '$($m.Value)'")
      exit 2
    }
  }
}

exit 0
'@

  $postToolUse = @'
param()
# Intentionally lightweight; no fake cache keepalive behavior.
exit 0
'@

  $sessionStartReminder = @'
param()
Write-Output 'Keepalive reminder: if you expect >5m idle periods, run /loop manually.'
exit 0
'@

  $hooks = @{
    'pretooluse.ps1' = $preToolUse
    'file-guard.ps1' = $fileGuard
    'posttooluse.ps1' = $postToolUse
    'session-start-reminder.ps1' = $sessionStartReminder
  }

  if ($AutoFormat) {
    $hooks['post-edit-format.ps1'] = @'
param()
$ErrorActionPreference = 'SilentlyContinue'
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.filePath }
if (-not $filePath -or -not (Test-Path -LiteralPath $filePath)) { exit 0 }
$ext = [IO.Path]::GetExtension($filePath).TrimStart('.').ToLowerInvariant()
switch ($ext) {
  { $_ -in @('js','jsx','ts','tsx','json','css','scss','less','html','htm','md','markdown','yaml','yml') } {
    $prettier = Get-Command prettier -ErrorAction SilentlyContinue
    if ($prettier) { & $prettier.Source --write $filePath 2>$null }
  }
  'py' {
    $black = Get-Command black -ErrorAction SilentlyContinue
    if ($black) { & $black.Source --quiet $filePath 2>$null }
    else {
      $autopep8 = Get-Command autopep8 -ErrorAction SilentlyContinue
      if ($autopep8) { & $autopep8.Source --in-place $filePath 2>$null }
    }
  }
}
exit 0
'@
  }

  foreach ($name in $hooks.Keys) {
    Set-Content -Path (Join-Path $HooksDir $name) -Value $hooks[$name] -Encoding utf8
  }

  Write-Ok 'Hook scripts updated'
}

function Get-RenderedSettings {
  $envVars = @{
    DISABLE_TELEMETRY = '1'
  }

  if ($Privacy -eq 'max') {
    $envVars['CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'] = '1'
  }

  if ($Profile -eq 'tuned') {
    $envVars['BASH_MAX_OUTPUT_LENGTH'] = '10000'
    $envVars['CLAUDE_CODE_AUTO_COMPACT_WINDOW'] = '180000'
    $envVars['CLAUDE_AUTOCOMPACT_PCT_OVERRIDE'] = '80'
    $envVars['CLAUDE_CODE_DISABLE_AUTO_MEMORY'] = '1'
    $envVars['ENABLE_CLAUDE_CODE_SM_COMPACT'] = 'true'
    $envVars['DISABLE_INTERLEAVED_THINKING'] = 'true'
    $envVars['CLAUDE_CODE_DISABLE_ADVISOR_TOOL'] = 'true'
    $envVars['CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS'] = 'true'
    $envVars['CLAUDE_CODE_DISABLE_POLICY_SKILLS'] = 'true'
    $envVars['OTEL_LOG_USER_PROMPTS'] = '0'
    $envVars['OTEL_LOG_TOOL_DETAILS'] = '0'
  }

  $settings = @{
    '$schema' = 'https://json.schemastore.org/claude-code-settings.json'
    attribution = @{ commit = ''; pr = '' }
    env = $envVars
    permissions = @{
      allow = @(
        'Bash(ls *)','Bash(ll *)','Bash(dir *)',
        'Bash(Get-ChildItem *)','Bash(gci *)',
        'Bash(pwd)','Bash(Get-Location)','Bash(gl)',
        'Bash(which *)','Bash(where *)','Bash(Get-Command *)','Bash(gcm *)',
        'Bash(git status*)','Bash(git log*)','Bash(git diff*)','Bash(git branch*)','Bash(git stash list*)',
        'Bash(npm list*)','Bash(pip list*)','Bash(pip show*)','Bash(pip freeze*)','Bash(Get-Package*)',
        'Bash(*--version)','Bash(* -v)','Bash(*--help*)'
      )
      deny = @(
        'Read(./.env)',
        'Read(./.env.*)',
        'Read(./secrets/**)',
        'Edit(./.env)',
        'Edit(./.env.*)',
        'Edit(./secrets/**)'
      )
    }
    hooks = @{
      PreToolUse = @(
        @{
          matcher = 'Read'
          hooks = @(@{ type = 'command'; shell = 'powershell'; command = "& '$HooksDir\pretooluse.ps1'"; timeout = 30 })
        },
        @{
          matcher = 'Write|Edit|MultiEdit|Bash'
          hooks = @(@{ type = 'command'; shell = 'powershell'; command = "& '$HooksDir\file-guard.ps1'"; timeout = 10 })
        }
      )
      PostToolUse = @(
        @{
          matcher = '*'
          hooks = @(@{ type = 'command'; shell = 'powershell'; command = "& '$HooksDir\posttooluse.ps1'"; timeout = 5 })
        }
      )
      SessionStart = @(
        @{
          matcher = 'startup|resume'
          hooks = @(@{ type = 'command'; shell = 'powershell'; command = "& '$HooksDir\session-start-reminder.ps1'"; timeout = 5 })
        }
      )
    }
  }

  if ($AutoFormat) {
    $settings.hooks.PostToolUse += @{
      matcher = 'Write|Edit|MultiEdit'
      hooks = @(@{ type = 'command'; shell = 'powershell'; command = "& '$HooksDir\post-edit-format.ps1'"; timeout = 30 })
    }
  }

  if ($UnsafeAutoApprove) {
    $settings.permissions.allow += @(
      'Bash(find *)','Bash(grep *)','Bash(rg *)',
      'Bash(cat *)','Bash(head *)','Bash(tail *)','Bash(wc *)','Bash(sort *)',
      'Bash(uniq *)','Bash(echo *)',
      'Bash(git show*)','Bash(git remote*)','Bash(git stash list*)','Bash(git config*)',
      'Bash(npm run*)'
    )
    $settings.permissions.allow = @($settings.permissions.allow | Select-Object -Unique)
  }

  return $settings
}

function Merge-Hashtable([hashtable]$Base, [hashtable]$Incoming) {
  $merged = @{}
  foreach ($k in $Base.Keys) { $merged[$k] = $Base[$k] }
  foreach ($k in $Incoming.Keys) {
    if ($merged.ContainsKey($k) -and $merged[$k] -is [hashtable] -and $Incoming[$k] -is [hashtable]) {
      $merged[$k] = Merge-Hashtable -Base $merged[$k] -Incoming $Incoming[$k]
    } else {
      $merged[$k] = $Incoming[$k]
    }
  }
  return $merged
}

function Write-Settings {
  $rendered = Get-RenderedSettings

  if ($DryRun) {
    $rendered | ConvertTo-Json -Depth 20
    return
  }

  New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null

  if (Test-Path -LiteralPath $SettingsFile) {
    $existing = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json -AsHashtable
    $merged = Merge-Hashtable -Base $existing -Incoming $rendered
    $merged | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $SettingsFile -Encoding utf8
  } else {
    $rendered | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $SettingsFile -Encoding utf8
  }

  Write-Ok "Updated $SettingsFile"
}

function Verify-Settings {
  if (-not (Test-Path -LiteralPath $SettingsFile)) {
    throw "Missing $SettingsFile"
  }

  $s = Get-Content -LiteralPath $SettingsFile -Raw | ConvertFrom-Json -AsHashtable
  $checks = @(
    @{ Name = 'schema'; Pass = $s.ContainsKey('$schema') },
    @{ Name = 'env'; Pass = $s['env'] -is [hashtable] },
    @{ Name = 'hooks.PreToolUse'; Pass = $s['hooks'].ContainsKey('PreToolUse') },
    @{ Name = 'hooks.SessionStart'; Pass = $s['hooks'].ContainsKey('SessionStart') },
    @{ Name = 'permissions.deny'; Pass = $s['permissions'].ContainsKey('deny') }
  )

  $failed = 0
  foreach ($c in $checks) {
    if ($c.Pass) { Write-Host "[PASS] $($c.Name)" -ForegroundColor Green }
    else { Write-Host "[FAIL] $($c.Name)" -ForegroundColor Red; $failed++ }
  }

  if ($failed -gt 0) { throw "Verification failed" }
}

try {
  if ($Verify) {
    Verify-Settings
    exit 0
  }

  Test-Dependencies
  Write-Hooks
  Write-Settings
  if ($UnsafeAutoApprove) {
    Write-Warn 'Unsafe auto-approve is enabled. This broad allowlist is high-risk.'
  }
  if (-not $DryRun) { Verify-Settings }
  Write-Ok "Done. Profile=$Profile, privacy=$Privacy, settings=$SettingsFile"
} catch {
  Write-Err $_
  exit 1
}
