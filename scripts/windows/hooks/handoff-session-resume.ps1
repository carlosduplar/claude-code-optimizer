#requires -Version 7.0
# handoff-session-resume: Auto-inlines handoff-context.md on compact/resume
# Emits hookSpecificOutput with handoff content as additionalContext
# No Read-tool round trip needed

param()
$ErrorActionPreference = 'SilentlyContinue'

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$cwd = $payload.cwd
if ($cwd) { Set-Location -LiteralPath $cwd -ErrorAction SilentlyContinue }

$handoffFile = Join-Path $cwd 'docs\handoff-context.md'

if (Test-Path -LiteralPath $handoffFile) {
  $content = Get-Content -LiteralPath $handoffFile -Raw -ErrorAction SilentlyContinue
  if ($content) {
    @{
      hookSpecificOutput = @{
        hookEventName = 'SessionStart'
        additionalContext = "Previous session handoff context:`n`n$content"
      }
    } | ConvertTo-Json -Compress
  }
}

exit 0
