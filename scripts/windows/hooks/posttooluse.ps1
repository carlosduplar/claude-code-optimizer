#requires -Version 7.0
# PostToolUse: Deterministic formatting after Write/Edit

param()
$ErrorActionPreference = 'SilentlyContinue'

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$toolName = $payload.tool_name
$filePath = $payload.tool_input.file_path
if (-not $filePath) { $filePath = $payload.tool_input.filePath }

# Only process Write/Edit tools
if ($toolName -notin @('Write','Edit','MultiEdit')) { exit 0 }
if (-not $filePath -or -not (Test-Path -LiteralPath $filePath)) { exit 0 }

$ext = [IO.Path]::GetExtension($filePath).TrimStart('.').ToLowerInvariant()

# Non-blocking: format if tools available, ignore errors
switch ($ext) {
  'py' {
    $ruff = Get-Command ruff -ErrorAction SilentlyContinue
    if ($ruff) { & $ruff.Source format $filePath 2>$null }
    else {
      $black = Get-Command black -ErrorAction SilentlyContinue
      if ($black) { & $black.Source --quiet $filePath 2>$null }
    }
  }
  { $_ -in @('js','jsx','ts','tsx','json','jsonc','css','scss','less','html','htm','md','markdown','yaml','yml') } {
    $prettier = Get-Command prettier -ErrorAction SilentlyContinue
    if ($prettier) { & $prettier.Source --write $filePath 2>$null }
  }
}

exit 0
