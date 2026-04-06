#!/usr/bin/env pwsh
# Parse Claude session transcript and extract token metrics
# Usage: parse-session.ps1 <transcript_path>

param(
    [Parameter(Mandatory=$true)]
    [string]$TranscriptPath
)

# Verify jq
if (!(Get-Command jq -ErrorAction SilentlyContinue)) {
    Write-Error "Error: jq required but not installed"
    exit 1
}

if (!(Test-Path $TranscriptPath)) {
    Write-Error "Error: Transcript not found: $TranscriptPath"
    exit 1
}

# Initialize counters
$inputTokens = 0
$outputTokens = 0
$cacheRead = 0
$cacheWrite = 0
$apiCalls = 0
$compactionEvents = 0

# Parse JSONL transcript
Get-Content $TranscriptPath | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }

    $line = $_

    # Check for usage data
    try {
        $json = $line | ConvertFrom-Json -ErrorAction Stop

        if ($json.usage) {
            $apiCalls++
            $inputTokens += $json.usage.input_tokens
            $outputTokens += $json.usage.output_tokens

            if ($json.usage.cache_read_tokens) {
                $cacheRead += $json.usage.cache_read_tokens
            }
            if ($json.usage.cache_write_tokens) {
                $cacheWrite += $json.usage.cache_write_tokens
            }
        }

        if ($json.type -eq "compaction") {
            $compactionEvents++
        }

        if ($json.message -and $json.message -match "compaction") {
            $compactionEvents++
        }
    } catch {
        # Skip malformed lines
    }
}

# Calculate cost
$cost = ($inputTokens * 0.000003) +
       ($cacheWrite * 0.00000375) +
       ($cacheRead * 0.0000003) +
       ($outputTokens * 0.000015)

# Output JSON
@{
    input_tokens = $inputTokens
    output_tokens = $outputTokens
    cache_read = $cacheRead
    cache_write = $cacheWrite
    api_calls = $apiCalls
    compaction_events = $compactionEvents
    estimated_cost_usd = [math]::Round($cost, 6)
} | ConvertTo-Json -Depth 1
