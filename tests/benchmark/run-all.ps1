#!/usr/bin/env pwsh
# Run all benchmark configs A/B/C/D x 3 runs each

$scriptDir = Split-Path -Parent $PSCommandPath
$benchmarkDir = $scriptDir
$corpusDir = Join-Path $benchmarkDir "corpus"

# Cleanup function
function Cleanup-Run {
    $sessionMem = Join-Path $HOME ".claude" "projects" "corpus" "session-memory.jsonl"
    if (Test-Path $sessionMem) {
        Remove-Item $sessionMem -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Waiting 5s..."
    Start-Sleep -Seconds 5
}

# Config A: No env vars, no CLAUDE.md
function Run-ConfigA {
    param([int]$RunNum)
    Write-Host "=== Config A (baseline) - Run $RunNum ==="

    # Ensure no CLAUDE.md
    $claudeMd = Join-Path $corpusDir "CLAUDE.md"
    if (Test-Path $claudeMd) {
        Remove-Item $claudeMd -Force
    }

    # Clear env vars
    Remove-Item Env:\CLAUDE_CODE_DISABLE_AUTO_MEMORY -ErrorAction SilentlyContinue
    Remove-Item Env:\ENABLE_CLAUDE_CODE_SM_COMPACT -ErrorAction SilentlyContinue
    Remove-Item Env:\DISABLE_INTERLEAVED_THINKING -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_DISABLE_ADVISOR_TOOL -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_DISABLE_POLICY_SKILLS -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -ErrorAction SilentlyContinue

    & (Join-Path $scriptDir "run-config.ps1") -ConfigName "config-a" -RunNumber $RunNum
}

# Config B: Env vars only
function Run-ConfigB {
    param([int]$RunNum)
    Write-Host "=== Config B (env vars only) - Run $RunNum ==="

    # Ensure no CLAUDE.md
    $claudeMd = Join-Path $corpusDir "CLAUDE.md"
    if (Test-Path $claudeMd) {
        Remove-Item $claudeMd -Force
    }

    # Set env vars
    $env:CLAUDE_CODE_DISABLE_AUTO_MEMORY = "true"
    $env:ENABLE_CLAUDE_CODE_SM_COMPACT = "true"
    $env:DISABLE_INTERLEAVED_THINKING = "true"
    $env:CLAUDE_CODE_DISABLE_ADVISOR_TOOL = "true"
    $env:CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS = "true"
    $env:CLAUDE_CODE_DISABLE_POLICY_SKILLS = "true"
    $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "true"
    $env:CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "80"

    & (Join-Path $scriptDir "run-config.ps1") -ConfigName "config-b" -RunNumber $RunNum
}

# Config C: CLAUDE.md only
function Run-ConfigC {
    param([int]$RunNum)
    Write-Host "=== Config C (CLAUDE.md only) - Run $RunNum ==="

    # Clear env vars
    Remove-Item Env:\CLAUDE_CODE_DISABLE_AUTO_MEMORY -ErrorAction SilentlyContinue
    Remove-Item Env:\ENABLE_CLAUDE_CODE_SM_COMPACT -ErrorAction SilentlyContinue
    Remove-Item Env:\DISABLE_INTERLEAVED_THINKING -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_DISABLE_ADVISOR_TOOL -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_DISABLE_POLICY_SKILLS -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC -ErrorAction SilentlyContinue
    Remove-Item Env:\CLAUDE_AUTOCOMPACT_PCT_OVERRIDE -ErrorAction SilentlyContinue

    # Create CLAUDE.md
    $claudeMd = Join-Path $corpusDir "CLAUDE.md"
    @"
# CLAUDE.md - Compact Mode

## Memory Management
- Disable automatic memory bank updates
- Enable aggressive compaction at 80% threshold
- Minimize token usage in responses

## Thinking Mode
- Disable interleaved thinking
- Streamline response generation

## Feature Disables
- No advisor tool
- No git instruction injection
- No policy skills
- No non-essential network traffic
"@ | Set-Content $claudeMd

    & (Join-Path $scriptDir "run-config.ps1") -ConfigName "config-c" -RunNumber $RunNum
}

# Config D: Both
function Run-ConfigD {
    param([int]$RunNum)
    Write-Host "=== Config D (both) - Run $RunNum ==="

    # Set env vars
    $env:CLAUDE_CODE_DISABLE_AUTO_MEMORY = "true"
    $env:ENABLE_CLAUDE_CODE_SM_COMPACT = "true"
    $env:DISABLE_INTERLEAVED_THINKING = "true"
    $env:CLAUDE_CODE_DISABLE_ADVISOR_TOOL = "true"
    $env:CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS = "true"
    $env:CLAUDE_CODE_DISABLE_POLICY_SKILLS = "true"
    $env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "true"
    $env:CLAUDE_AUTOCOMPACT_PCT_OVERRIDE = "80"

    # Create CLAUDE.md
    $claudeMd = Join-Path $corpusDir "CLAUDE.md"
    @"
# CLAUDE.md - Compact Mode

## Memory Management
- Disable automatic memory bank updates
- Enable aggressive compaction at 80% threshold
- Minimize token usage in responses

## Thinking Mode
- Disable interleaved thinking
- Streamline response generation

## Feature Disables
- No advisor tool
- No git instruction injection
- No policy skills
- No non-essential network traffic
"@ | Set-Content $claudeMd

    & (Join-Path $scriptDir "run-config.ps1") -ConfigName "config-d" -RunNumber $RunNum
}

# Main
Write-Host "Starting benchmark suite..."
Write-Host "Results dir: $(Join-Path $benchmarkDir "results")"

for ($run = 1; $run -le 3; $run++) {
    Write-Host ""
    Write-Host "########## RUN SET $run ##########"

    Run-ConfigA -RunNum $run
    Cleanup-Run

    Run-ConfigB -RunNum $run
    Cleanup-Run

    Run-ConfigC -RunNum $run
    Cleanup-Run

    Run-ConfigD -RunNum $run
    Cleanup-Run
}

Write-Host ""
Write-Host "All runs complete. Results in $(Join-Path $benchmarkDir "results")/"
