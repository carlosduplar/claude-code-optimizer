#requires -Version 7.0
# write-guard: Secret detection for Write/Edit tools
# Blocks writes containing suspected secrets with fail-closed pattern

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

# For Edit tool, check old/new strings
if ($toolName -in @('Edit','MultiEdit')) {
  $content = "$($payload.tool_input.oldString) $($payload.tool_input.newString)"
}

if (-not $content) { exit 0 }

# Secret detection patterns
$secretPatterns = @(
  '(?i)password\s*=\s*["'''][^"''"\n]{4,}["''']'
  '(?i)passwd\s*=\s*["'''][^"''"\n]{4,}["''']'
  '(?i)api[_-]?key\s*=\s*["'''][^"''"\n]{8,}["''']'
  '(?i)apikey\s*=\s*["'''][^"''"\n]{8,}["''']'
  '(?i)secret[_-]?key\s*=\s*["'''][^"''"\n]{8,}["''']'
  '(?i)secret\s*=\s*["'''][^"''"\n]{8,}["''']'
  '(?i)auth[_-]?token\s*=\s*["'''][^"''"\n]{8,}["''']'
  '(?i)access[_-]?token\s*=\s*["'''][^"''"\n]{8,}["''']'
  '(?i)token\s*=\s*["'''][^"''"\n]{8,}["''']'
  '(?i)private[_-]?key\s*=\s*["'''][^"''"\n]{8,}["''']'
  '-----BEGIN (RSA |DSA |EC |OPENSSH )?PRIVATE KEY-----'
  '(?i)aws[_-]?access[_-]?key[_-]?id\s*=\s*["'''][^"''"\n]{8,}["''']'
  '(?i)aws[_-]?secret[_-]?access[_-]?key\s*=\s*["'''][^"''"\n]{8,}["''']'
  'AKIA[0-9A-Z]{16}'
  '(?i)github[_-]?token\s*=\s*["'''][^"''"\n]{8,}["''']'
  '(?i)slack[_-]?token\s*=\s*["'''][^"''"\n]{8,}["''']'
  'xox[baprs]-[0-9a-zA-Z]{10,48}'
  '(?i)database[_-]?url\s*=\s*["'''][^"''"\n]{8,}["''']'
  '(?i)connection[_-]?string\s*=\s*["'''][^"''"\n]{8,}["''']'
)

foreach ($pattern in $secretPatterns) {
  if ($content -match $pattern) {
    [Console]::Error.WriteLine('BLOCKED: suspected secret detected in write content (pattern: credential)')
    [Console]::Error.WriteLine('If this is intentional, write to .env.example or use placeholder values')
    exit 2
  }
}

exit 0
