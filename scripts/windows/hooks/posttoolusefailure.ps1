#requires -Version 7.0
# PostToolUseFailure: Log errors with 1MB rotation

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
    Move-Item -LiteralPath $LOG_FILE -Destination (Join-Path $LOG_DIR "$DATE-1.log") -Force
  }
}

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
$toolName = $payload.tool_name
$errorMsg = $payload.error

$TIMESTAMP = Get-Date -Format 'o'
"[$TIMESTAMP] [$toolName] $errorMsg" | Out-File -FilePath $LOG_FILE -Encoding utf8 -Append

exit 0
