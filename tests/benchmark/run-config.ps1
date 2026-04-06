#!/usr/bin/env pwsh
# Run benchmark for specific config
# Usage: run-config.ps1 <config_name> <run_number>

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigName,

    [Parameter(Mandatory=$true)]
    [int]$RunNumber
)

# Verify claude --print
$claudeHelp = claude --help 2>$null
if ($LASTEXITCODE -ne 0 -or $claudeHelp -notmatch "--print") {
    Write-Error "Error: claude --print not available"
    exit 1
}

# Get script directory
$scriptDir = Split-Path -Parent $PSCommandPath
$benchmarkDir = Split-Path -Parent $scriptDir
$corpusDir = Join-Path $benchmarkDir "corpus"
$resultsDir = Join-Path $benchmarkDir "results"
$promptsFile = Join-Path $benchmarkDir "prompts.txt"

New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null

# Clear tool-results cache
$cacheDir = Join-Path $HOME ".claude" "projects"
if (Test-Path $cacheDir) {
    Get-ChildItem -Path $cacheDir -Directory -Filter "*corpus*" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# Clear session memory
$sessionMem = Join-Path $cacheDir "corpus" "session-memory.jsonl"
if (Test-Path $sessionMem) {
    Remove-Item $sessionMem -Force -ErrorAction SilentlyContinue
}

# Run all prompts
$runStart = Get-Date

Get-Content $promptsFile | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }

    $prompt = $_
    Write-Host "Running: $prompt"

    Push-Location $corpusDir
    claude --print $prompt 2>$null | Out-Null
    Pop-Location
}

$runEnd = Get-Date
$runDuration = ($runEnd - $runStart).TotalSeconds

# Find newest transcript
$transcriptDir = Join-Path $HOME ".claude" "projects"
$newestTranscript = $null
$newestTime = [DateTime]::MinValue

Get-ChildItem -Path $transcriptDir -Filter "session-memory.jsonl" -Recurse | ForEach-Object {
    if ($_.LastWriteTime -gt $newestTime) {
        $newestTime = $_.LastWriteTime
        $newestTranscript = $_.FullName
    }
}

if (-not $newestTranscript) {
    Write-Error "No transcript found after run"
    exit 1
}

# Parse session
$parseScript = Join-Path $scriptDir "parse-session.ps1"
$result = & $parseScript -TranscriptPath $newestTranscript | ConvertFrom-Json

# Add metadata
$result | Add-Member -NotePropertyName "config" -NotePropertyValue $ConfigName -Force
$result | Add-Member -NotePropertyName "run_number" -NotePropertyValue $RunNumber -Force
$result | Add-Member -NotePropertyName "duration_seconds" -NotePropertyValue ([math]::Round($runDuration, 2)) -Force
$result | Add-Member -NotePropertyName "timestamp" -NotePropertyValue (Get-Date -Format "o") -Force

# Save result
$outputFile = Join-Path $resultsDir "$($ConfigName)-run-$($RunNumber).json"
$result | ConvertTo-Json -Depth 2 | Set-Content $outputFile

Write-Host "Config $ConfigName run $RunNumber complete: $outputFile"
Write-Host "Duration: $([math]::Round($runDuration, 1))s"
