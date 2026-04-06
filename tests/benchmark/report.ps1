#!/usr/bin/env pwsh
# Generate benchmark comparison report

$scriptDir = Split-Path -Parent $PSCommandPath
$benchmarkDir = Split-Path -Parent $scriptDir
$resultsDir = Join-Path $benchmarkDir "results"

if (!(Get-Command jq -ErrorAction SilentlyContinue)) {
    Write-Error "Error: jq required but not installed"
    exit 1
}

if (!(Test-Path $resultsDir)) {
    Write-Error "Error: Results directory not found: $resultsDir"
    exit 1
}

# Compute averages for a config
function Compute-ConfigStats {
    param([string]$Config)

    $files = Get-ChildItem -Path $resultsDir -Filter "$($Config)-run-*.json" -ErrorAction SilentlyContinue

    if (!$files) {
        return $null
    }

    $totalRuns = $files.Count
    $totalInput = 0
    $totalOutput = 0
    $totalCacheRead = 0
    $totalCacheWrite = 0
    $totalApiCalls = 0
    $totalCompaction = 0
    $totalCost = 0.0
    $totalDuration = 0.0

    foreach ($f in $files) {
        $json = Get-Content $f.FullName | ConvertFrom-Json
        $totalInput += $json.input_tokens
        $totalOutput += $json.output_tokens
        $totalCacheRead += $json.cache_read
        $totalCacheWrite += $json.cache_write
        $totalApiCalls += $json.api_calls
        $totalCompaction += $json.compaction_events
        $totalCost += $json.estimated_cost_usd
        $totalDuration += $json.duration_seconds
    }

    return @{
        config = $Config
        runs = $totalRuns
        avg_input_tokens = [math]::Round($totalInput / $totalRuns, 0)
        avg_output_tokens = [math]::Round($totalOutput / $totalRuns, 0)
        avg_cache_read = [math]::Round($totalCacheRead / $totalRuns, 0)
        avg_cache_write = [math]::Round($totalCacheWrite / $totalRuns, 0)
        avg_api_calls = [math]::Round($totalApiCalls / $totalRuns, 1)
        avg_compaction_events = [math]::Round($totalCompaction / $totalRuns, 1)
        avg_cost_usd = [math]::Round($totalCost / $totalRuns, 6)
        avg_duration_seconds = [math]::Round($totalDuration / $totalRuns, 1)
    }
}

# Calculate percent change
function Calc-PctChange {
    param([double]$Baseline, [double]$Value)

    if ($Baseline -eq 0) {
        return "N/A"
    }
    $pct = (($Value - $Baseline) / $Baseline) * 100
    return [math]::Round($pct, 1)
}

# Main
Write-Host "Claude Code Token Benchmark Report"
Write-Host "=================================="
Write-Host "Generated: $(Get-Date)"
Write-Host ""

$statsA = Compute-ConfigStats "config-a"
$statsB = Compute-ConfigStats "config-b"
$statsC = Compute-ConfigStats "config-c"
$statsD = Compute-ConfigStats "config-d"

if (!$statsA) {
    Write-Host "No results found. Run run-all.ps1 first."
    exit 1
}

$baseCost = $statsA.avg_cost_usd

# Print comparison table
Write-Host ""
$format = "{0,-15} {1,12} {2,12} {3,12} {4,15} {5,12}"
Write-Host ($format -f "Config", "Input Tok", "Output Tok", "API Calls", "Cost (`$)", "vs A %")
Write-Host ($format -f "---------------", "------------", "------------", "------------", "---------------", "------------")

foreach ($stats in @($statsA, $statsB, $statsC, $statsD)) {
    if (!$stats) { continue }

    $pctChange = Calc-PctChange $baseCost $stats.avg_cost_usd
    $pctStr = "$pctChange%"

    Write-Host ($format -f $stats.config,
        $stats.avg_input_tokens,
        $stats.avg_output_tokens,
        $stats.avg_api_calls,
        $stats.avg_cost_usd,
        $pctStr)
}

Write-Host ""
Write-Host "Detailed Stats:"
Write-Host "---------------"

foreach ($stats in @($statsA, $statsB, $statsC, $statsD)) {
    if (!$stats) { continue }
    Write-Host ""
    $stats | ConvertTo-Json -Depth 2
}
