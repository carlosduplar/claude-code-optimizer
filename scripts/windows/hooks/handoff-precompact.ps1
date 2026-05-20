#requires -Version 7.0
# handoff-precompact: Synthesizes structured handoff context before compaction
# Uses claude -p --bare to avoid nested hook cascade
# Always exits 0 so compact proceeds regardless of outcome

param()
$ErrorActionPreference = 'Stop'

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$cwd = $payload.cwd
$transcriptPath = $payload.transcript_path

if (-not $cwd) { $cwd = (Get-Location).Path }
$handoffFile = Join-Path $cwd 'docs\handoff-context.md'

$timeoutSeconds = 60
$fallbackMaxBytes = 50000

function Write-Handoff([string]$content) {
  $dir = Join-Path $cwd 'docs'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Set-Content -LiteralPath $handoffFile -Value $content -Encoding utf8
}

try {
  if (-not $transcriptPath -or -not (Test-Path -LiteralPath $transcriptPath)) {
    exit 0
  }

  $transcriptBytes = [System.IO.File]::ReadAllBytes($transcriptPath)
  $tailBytes = $transcriptBytes
  if ($transcriptBytes.Length -gt $fallbackMaxBytes) {
    $tailBytes = $transcriptBytes[($transcriptBytes.Length - $fallbackMaxBytes)..($transcriptBytes.Length - 1)]
  }
  $tailText = [System.Text.Encoding]::UTF8.GetString($tailBytes)

  $prompt = @"
You are synthesizing a handoff context summary from a Claude Code session transcript.
Extract the following information as a structured Markdown document.
If a field cannot be determined, write "Unknown".

Format the output as Markdown with these sections:

## Session Started
ISO 8601 timestamp from transcript.

## Task
One sentence overall goal.

## Completed Tasks
Bullet list of concrete things finished.

## Current State
In-flight work, files modified, what works/broken.

## Constraints
Bullet list of user rules, ruled-out approaches and why.

## Files Touched
Table: path | status (created/modified/deleted) | summary

## Issues Discovered
Bullet list of bugs/gotchas and workarounds.

## Open Questions
Bullet list of unresolved decisions.

## Next Steps
Numbered ordered list of specific actions. next_steps[0] = literally first action.

## Resume Prompt
One paragraph a user can paste into a fresh session to continue.

Transcript tail (last 50KB):
$tailText
"@

  $job = Start-Job -ScriptBlock {
    param($promptText)
    $env:CLAUDE_CODE_DISABLE_AUTO_MEMORY = '1'
    $env:CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS = '1'
    $env:CLAUDE_CODE_DISABLE_POLICY_SKILLS = '1'
    claude -p --bare --model claude-sonnet-4-6 $promptText 2>$null
  } -ArgumentList $prompt

  $completed = Wait-Job $job -Timeout $timeoutSeconds

  if ($completed -and $completed.State -eq 'Completed') {
    $result = Receive-Job $job
    if ($result -and $result.Trim().Length -gt 0) {
      Write-Handoff $result
    } else {
      Write-Fallback
    }
  } else {
    Write-Fallback
  }

  Remove-Job $job -Force
} catch {
  Write-Fallback
}

function Write-Fallback {
  $tail = ''
  if ($transcriptPath -and (Test-Path -LiteralPath $transcriptPath)) {
    $raw = Get-Content -LiteralPath $transcriptPath -Raw -ErrorAction SilentlyContinue
    if ($raw) {
      $start = [Math]::Max(0, $raw.Length - $fallbackMaxBytes)
      $tail = $raw.Substring($start)
    }
  }
  $fallback = "# HANDOFF_AUTO_PARTIAL`n`nHandoff synthesis failed. Raw transcript tail:`n`n`$`$`$`n$tail`n`$`$`$`n"
  Write-Handoff $fallback
}

exit 0
