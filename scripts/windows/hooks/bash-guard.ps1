#requires -Version 7.0
# bash-guard: Zero-trust security hook for Bash tool
# Blocks dangerous commands with fail-closed pattern

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
