#requires -Version 7.0
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
  Remove-Item -LiteralPath (Join-Path $HooksDir 'posttooluse.ps1') -ErrorAction SilentlyContinue
  if (-not $AutoFormat) {
    Remove-Item -LiteralPath (Join-Path $HooksDir 'post-edit-format.ps1') -ErrorAction SilentlyContinue
  }

  # Copy external hooks from script directory
  $ScriptHooksDir = Join-Path $PSScriptRoot 'hooks'
  if (Test-Path -LiteralPath $ScriptHooksDir) {
    Get-ChildItem -LiteralPath $ScriptHooksDir -Filter '*.ps1' | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination $HooksDir -Force
    }
  }

  $preToolUse = @'
param()
$ErrorActionPreference = 'Stop'
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$toolName = $payload.tool_name
$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.filePath }

if ($toolName -ne 'Read' -or -not $filePath -or -not (Test-Path -LiteralPath $filePath)) { exit 0 }

Get-ChildItem $env:TEMP -Filter 'claude-read-*' -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddHours(-1) } |
  Remove-Item -Force -ErrorAction SilentlyContinue

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

function Test-ProtectedPath([string]$value) {
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
  if (Test-ProtectedPath $filePath) {
    [Console]::Error.WriteLine("BLOCKED: path '$filePath' matches protected pattern")
    exit 2
  }
  if (IsOutsideProject $filePath) {
    [Console]::Error.WriteLine("BLOCKED: write/edit outside workspace is blocked: '$filePath'")
    exit 2
  }
}

if ($toolName -eq 'Bash' -and (Test-ProtectedPath $command)) {
  [Console]::Error.WriteLine('BLOCKED: bash command references protected path/pattern')
  exit 2
}

if ($toolName -eq 'Bash' -and $command -match '^\s*(cat|head|tail|grep|rg|find|Get-Content|type|Select-String|sls)\b') {
  if ($command -match '(^|\s)\.\.[\\/]+') {
    [Console]::Error.WriteLine('BLOCKED: path traversal is blocked for high-risk read commands')
    exit 2
  }
  $pathMatches = [regex]::Matches($command, '(~?[\\/][^ ;|&]+|\.{1,2}[\\/][^ ;|&]+)')
  foreach ($m in $pathMatches) {
    if (IsOutsideProject $m.Value) {
      [Console]::Error.WriteLine("BLOCKED: high-risk read command target outside workspace: '$($m.Value)'")
      exit 2
    }
  }
}

exit 0
'@

  $sessionStartReminder = @'
param()
$ErrorActionPreference = 'SilentlyContinue'
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$source = $payload.source
$cwd = $payload.cwd
if ($cwd) { Set-Location -LiteralPath $cwd -ErrorAction SilentlyContinue }

$parts = @("Session: $source")

if (Test-Path 'package.json') {
  $pkg = Get-Content 'package.json' -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
  $name = if ($pkg -and $pkg.name) { $pkg.name } else { 'project' }
  $parts += "$name (Node.js)"
} elseif (Test-Path 'pyproject.toml') {
  $parts += 'Python project'
} elseif (Test-Path 'Cargo.toml') {
  $parts += 'Rust project'
} elseif (Test-Path 'go.mod') {
  $parts += 'Go project'
}

$branch = git branch --show-current 2>$null
if ($branch) {
  $changes = (git status --short 2>$null | Measure-Object -Line).Lines
  if ($changes -gt 0) {
    $parts += "branch: $branch ($changes uncommitted)"
  } else {
    $parts += "branch: $branch"
  }
}

$parts += 'Keepalive: if >5m idle, run /loop'

@{ hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = ($parts -join ' | ') } } | ConvertTo-Json -Compress
exit 0
'@

  $postToolUseFailure = @'
param()
$ErrorActionPreference = 'Stop'
$LOG_DIR = Join-Path $env:USERPROFILE '.claude\logs\errors'
New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null

$DATE = Get-Date -Format 'yyyy-MM-dd'
$LOG_FILE = Join-Path $LOG_DIR "$DATE.log"

# Rotate if > 1MB
if (Test-Path -LiteralPath $LOG_FILE) {
  $size = (Get-Item -LiteralPath $LOG_FILE).Length
  if ($size -gt 1048576) {
    $ts = Get-Date -Format 'HHmmss'
    Move-Item -LiteralPath $LOG_FILE -Destination (Join-Path $LOG_DIR "$DATE-$ts.log") -Force
  }
}

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$toolName = $payload.tool_name
$errorMsg = $payload.error

$TIMESTAMP = Get-Date -Format 'o'
"[$TIMESTAMP] [$toolName] $errorMsg" | Out-File -FilePath $LOG_FILE -Encoding utf8 -Append

exit 0
'@

  $bashGuard = @'
param()
$ErrorActionPreference = 'Stop'

trap {
  [Console]::Error.WriteLine('BLOCKED: bash-guard validation error (fail-closed)')
  exit 1
}

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$toolName = $payload.tool_name
$command = $payload.tool_input.command

if ($toolName -ne 'Bash' -or -not $command) { exit 0 }

# Dangerous command patterns
$denyPatterns = @(
  '^\s*sudo\b'
  '\brm\s+-rf\s+/\s*$'
  '\brm\s+-rf\s+/\*\s*$'
  '\beval\s+'
  '\bcurl\s+.*\|.*\b(bash|sh)\b'
  '\bwget\s+.*\|.*\b(bash|sh)\b'
  '\bcurl\s+.*\|.*\b(bash|sh)\s*-\s*c\b'
  '\s*>\s*/dev/sda\s*$'
  ':\(\)\s*\{\s*:\|:&\s*\};\s*:'
  '\bdd\s+if=.*of=/dev/sd[a-z]'
  '\bmkfs\.[a-z]+\s+/dev/sd[a-z][0-9]*'
  '\b>:\(\)\{\s*:\|:&\s*\};\s*:'
)

foreach ($pattern in $denyPatterns) {
  if ($command -match $pattern) {
    [Console]::Error.WriteLine("BLOCKED: command matches dangerous pattern: $pattern")
    exit 2
  }
}

exit 0
'@

  $writeGuard = @'
param()
$ErrorActionPreference = 'Stop'

trap {
  [Console]::Error.WriteLine('BLOCKED: write-guard validation error (fail-closed)')
  exit 1
}

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$toolName = $payload.tool_name
$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.filePath }

if ($toolName -notin @('Write','Edit','MultiEdit')) { exit 0 }
if (-not $filePath) { exit 0 }

# Allow safe files (examples, tests, fixtures)
$allowedPatterns = @(
  '\.env\.example$'
  '\.env\.sample$'
  '\.env\.template$'
  '\.env\.local\.example$'
  '\.test\.[a-z]+$'
  '\.spec\.[a-z]+$'
  '_test\.[a-z]+$'
  '_spec\.[a-z]+$'
  'test/'
  'tests/'
  '__tests__/'
  'fixtures/'
  'examples/'
  '\.md$'
)

foreach ($pattern in $allowedPatterns) {
  if ($filePath -match $pattern) { exit 0 }
}

# Get content for Write tool
$content = ''
if ($toolName -eq 'Write') {
  $content = $payload.tool_input.content
}

# For Edit/MultiEdit tools, check old/new strings
if ($toolName -eq 'Edit') {
  $content = "$($payload.tool_input.old_string) $($payload.tool_input.new_string)"
}
if ($toolName -eq 'MultiEdit') {
  $content = ($payload.tool_input.edits | ForEach-Object { "$($_.old_string) $($_.new_string)" }) -join ' '
}

if (-not $content) { exit 0 }

# Secret detection patterns
$secretPatterns = @(
  '(?i)password\s*=\s*["''][^"''"\n]{4,}["'']'
  '(?i)passwd\s*=\s*["''][^"''"\n]{4,}["'']'
  '(?i)api[_-]?key\s*=\s*["''][^"''"\n]{8,}["'']'
  '(?i)apikey\s*=\s*["''][^"''"\n]{8,}["'']'
  '(?i)secret[_-]?key\s*=\s*["''][^"''"\n]{8,}["'']'
  '(?i)secret\s*=\s*["''][^"''"\n]{8,}["'']'
  '(?i)auth[_-]?token\s*=\s*["''][^"''"\n]{8,}["'']'
  '(?i)access[_-]?token\s*=\s*["''][^"''"\n]{8,}["'']'
  '(?i)token\s*=\s*["''][^"''"\n]{8,}["'']'
  '(?i)private[_-]?key\s*=\s*["''][^"''"\n]{8,}["'']'
  '-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----'
  '(?i)aws[_-]?access[_-]?key[_-]?id\s*=\s*["''][^"''"\n]{8,}["'']'
  '(?i)aws[_-]?secret[_-]?access[_-]?key\s*=\s*["''][^"''"\n]{8,}["'']'
  'AKIA[0-9A-Z]{16}'
  '(?i)github[_-]?token\s*=\s*["''][^"''"\n]{8,}["'']'
  '(?i)slack[_-]?token\s*=\s*["''][^"''"\n]{8,}["'']'
  'xox[baprs]-[0-9a-zA-Z]{10,48}'
  '(?i)database[_-]?url\s*=\s*["''][^"''"\n]{8,}["'']'
  '(?i)connection[_-]?string\s*=\s*["''][^"''"\n]{8,}["'']'
)

foreach ($pattern in $secretPatterns) {
  if ($content -match $pattern) {
    [Console]::Error.WriteLine('BLOCKED: suspected secret detected in write content (pattern: credential)')
    [Console]::Error.WriteLine('If this is intentional, write to .env.example or use placeholder values')
    exit 2
  }
}

exit 0
'@

  $notifyHook = @'
param()
$ErrorActionPreference = 'SilentlyContinue'
$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$msg = $payload.message
if (-not $msg) { exit 0 }
try {
  $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
  $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
  $escaped = [System.Security.SecurityElement]::Escape($msg)
  $xml.LoadXml("<toast><visual><binding template=`"ToastText01`"><text id=`"1`">$escaped</text></binding></visual></toast>")
  $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Windows PowerShell').Show($toast)
} catch { }
exit 0
'@

  $hooks = @{
    'pretooluse.ps1' = $preToolUse
    'file-guard.ps1' = $fileGuard
    'session-start-reminder.ps1' = $sessionStartReminder
    'posttoolusefailure.ps1' = $postToolUseFailure
    'bash-guard.ps1' = $bashGuard
    'write-guard.ps1' = $writeGuard
    'notify.ps1' = $notifyHook
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

function Get-DefaultAllowPatterns {
  return @(
    'Bash(ls *)','Bash(ll *)','Bash(dir *)',
    'Bash(Get-ChildItem *)','Bash(gci *)',
    'Bash(pwd)','Bash(Get-Location)','Bash(gl)',
    'Bash(which *)','Bash(where *)','Bash(Get-Command *)','Bash(gcm *)',
    'Bash(git status*)','Bash(git log*)','Bash(git diff*)','Bash(git branch*)','Bash(git stash list*)','Bash(git remote*)','Bash(git config*)',
    'Bash(npm list*)','Bash(pip list*)','Bash(pip show*)','Bash(pip freeze*)','Bash(Get-Package*)',
    'Bash(*--version)','Bash(* -v)','Bash(*--help*)'
  )
}

function Get-UnsafeAllowPatterns {
  return @(
    'Bash(find *)','Bash(grep *)','Bash(rg *)',
    'Bash(cat *)','Bash(head *)','Bash(tail *)','Bash(wc *)','Bash(sort *)',
    'Bash(uniq *)','Bash(git show*)','Bash(npm run*)'
  )
}

function Get-LegacyManagedAllowPatterns {
  return @(
    'Bash(find . -*)',
    'Bash(echo *)','Bash(printenv *)','Bash(env | *)',
    'Bash(ps *)','Bash(top -n *)','Bash(htop -n *)',
    'Bash(curl -I *)','Bash(curl --head *)','Bash(ping -c *)','Bash(nslookup *)','Bash(dig *)',
    'Bash(mkdir *)','Bash(rmdir *)','Bash(touch *)','Bash(mv *)','Bash(cp *)',
    'Bash(make *)','Bash(cmake *)','Bash(npm run *)','Bash(yarn *)','Bash(pnpm *)',
    'Bash(tsc *)','Bash(eslint *)','Bash(prettier *)','Bash(ruff *)','Bash(black *)',
    'Bash(docker ps *)','Bash(docker images *)','Bash(docker-compose ps *)'
  )
}

function Get-ManagedEnvKeys {
  return @(
    'DISABLE_TELEMETRY',
    'CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC',
    'BASH_MAX_OUTPUT_LENGTH',
    'CLAUDE_CODE_AUTO_COMPACT_WINDOW',
    'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE',
    'CLAUDE_CODE_DISABLE_AUTO_MEMORY',
    'ENABLE_CLAUDE_CODE_SM_COMPACT',
    'DISABLE_INTERLEAVED_THINKING',
    'CLAUDE_CODE_DISABLE_ADVISOR_TOOL',
    'CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS',
    'CLAUDE_CODE_DISABLE_POLICY_SKILLS',
    'OTEL_LOG_USER_PROMPTS',
    'OTEL_LOG_TOOL_DETAILS',
    'MAX_MCP_OUTPUT_TOKENS',
    'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'
  )
}

function Get-ManagedDenyPatterns {
  return @(
    'Read(./.env)',
    'Read(./.env.*)',
    'Read(./secrets/**)',
    'Edit(./.env)',
    'Edit(./.env.*)',
    'Edit(./secrets/**)'
  )
}

function Get-ManagedHookKeys {
  return @('PreToolUse','SessionStart','PostToolUse','PostToolUseFailure','Notification')
}

function Get-HashtableOrEmpty([object]$Value) {
  if ($Value -is [hashtable]) {
    return $Value
  }

  return @{}
}

function Get-ArrayOrEmpty([object]$Value) {
  if ($Value -is [array]) {
    return $Value
  }

  return @()
}

function Get-UniqueStringArray([object[]]$Values) {
  return @(
    $Values |
      Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_) } |
      Select-Object -Unique
  )
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
    $envVars['MAX_MCP_OUTPUT_TOKENS'] = '25000'
    $envVars['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1'
  }

  $settings = @{
    '$schema' = 'https://json.schemastore.org/claude-code-settings.json'
    attribution = @{ commit = ''; pr = '' }
    env = $envVars
    permissions = @{
      allow = @(Get-DefaultAllowPatterns)
      deny = @(Get-ManagedDenyPatterns)
    }
    hooks = @{
      PreToolUse = @(
        @{
          matcher = 'Read'
          hooks = @(@{ type = 'command'; shell = 'powershell'; command = '& (Join-Path $env:USERPROFILE ''.claude\hooks\pretooluse.ps1'')'; timeout = 30 })
        }
        @{
          matcher = 'Write|Edit|MultiEdit|Bash'
          hooks = @(
            @{ type = 'command'; shell = 'powershell'; command = '& (Join-Path $env:USERPROFILE ''.claude\hooks\file-guard.ps1'')'; timeout = 10 }
            @{ type = 'command'; shell = 'powershell'; command = '& (Join-Path $env:USERPROFILE ''.claude\hooks\bash-guard.ps1'')'; timeout = 5 }
            @{ type = 'command'; shell = 'powershell'; command = '& (Join-Path $env:USERPROFILE ''.claude\hooks\write-guard.ps1'')'; timeout = 5 }
          )
        }
      )
      SessionStart = @(
        @{
          matcher = 'startup|resume|compact'
          hooks = @(@{ type = 'command'; shell = 'powershell'; command = '& (Join-Path $env:USERPROFILE ''.claude\hooks\session-start-reminder.ps1'')'; timeout = 5 })
        }
      )
      PostToolUseFailure = @(
        @{
          matcher = '*'
          hooks = @(@{ type = 'command'; shell = 'powershell'; command = '& (Join-Path $env:USERPROFILE ''.claude\hooks\posttoolusefailure.ps1'')'; timeout = 5 })
        }
      )
      Notification = @(
        @{
          matcher = '*'
          hooks = @(@{ type = 'command'; shell = 'powershell'; command = '& (Join-Path $env:USERPROFILE ''.claude\hooks\notify.ps1'')'; timeout = 15 })
        }
      )
    }
  }

  if ($AutoFormat) {
    if (-not $settings.hooks.ContainsKey('PostToolUse')) {
      $settings.hooks['PostToolUse'] = @()
    }
    $settings.hooks.PostToolUse += @{
      matcher = 'Write|Edit|MultiEdit'
      hooks = @(@{ type = 'command'; shell = 'powershell'; command = '& (Join-Path $env:USERPROFILE ''.claude\hooks\post-edit-format.ps1'')'; timeout = 30 })
    }
  }

  if ($UnsafeAutoApprove) {
    $settings.permissions.allow += @(Get-UnsafeAllowPatterns)
    $settings.permissions.allow = @($settings.permissions.allow | Select-Object -Unique)
  }

  return $settings
}

function Merge-Settings([hashtable]$Existing, [hashtable]$Rendered) {
  $merged = @{}
  foreach ($key in $Existing.Keys) {
    $merged[$key] = $Existing[$key]
  }

  foreach ($key in $Rendered.Keys) {
    switch ($key) {
      'env' {
        $existingEnv = Get-HashtableOrEmpty $Existing['env']
        $managedEnvKeys = Get-ManagedEnvKeys
        $envMap = @{}
        foreach ($envKey in $existingEnv.Keys) {
          if ($envKey -notin $managedEnvKeys) {
            $envMap[$envKey] = $existingEnv[$envKey]
          }
        }
        foreach ($envKey in $Rendered['env'].Keys) {
          $envMap[$envKey] = $Rendered['env'][$envKey]
        }
        $merged['env'] = $envMap
      }
      'permissions' {
        $existingPermissions = Get-HashtableOrEmpty $Existing['permissions']
        $permissions = @{}
        foreach ($permKey in $existingPermissions.Keys) {
          if ($permKey -notin @('allow','deny')) {
            $permissions[$permKey] = $existingPermissions[$permKey]
          }
        }

        $managedAllowPatterns = Get-UniqueStringArray (@(Get-ArrayOrEmpty $Rendered['permissions']['allow']) + @(Get-UnsafeAllowPatterns) + @(Get-LegacyManagedAllowPatterns))
        $preservedAllow = @()
        foreach ($entry in (Get-ArrayOrEmpty $existingPermissions['allow'])) {
          if (($entry -is [string]) -and ($entry -notin $managedAllowPatterns)) {
            $preservedAllow += $entry
          }
        }
        $permissions['allow'] = Get-UniqueStringArray (@($preservedAllow) + @(Get-ArrayOrEmpty $Rendered['permissions']['allow']))

        $managedDenyPatterns = Get-ManagedDenyPatterns
        $preservedDeny = @()
        foreach ($entry in (Get-ArrayOrEmpty $existingPermissions['deny'])) {
          if (($entry -is [string]) -and ($entry -notin $managedDenyPatterns)) {
            $preservedDeny += $entry
          }
        }
        $permissions['deny'] = Get-UniqueStringArray (@($preservedDeny) + @(Get-ArrayOrEmpty $Rendered['permissions']['deny']))
        $merged['permissions'] = $permissions
      }
      'hooks' {
        $existingHooks = Get-HashtableOrEmpty $Existing['hooks']
        $hooks = @{}
        $managedHookKeys = Get-ManagedHookKeys
        foreach ($hookKey in $existingHooks.Keys) {
          if ($hookKey -notin $managedHookKeys) {
            $hooks[$hookKey] = $existingHooks[$hookKey]
          }
        }
        foreach ($hookKey in $Rendered['hooks'].Keys) {
          $hooks[$hookKey] = $Rendered['hooks'][$hookKey]
        }
        $merged['hooks'] = $hooks
      }
      default {
        $merged[$key] = $Rendered[$key]
      }
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
    $merged = Merge-Settings -Existing $existing -Rendered $rendered
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
