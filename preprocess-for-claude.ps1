# Pre-process files for Claude Code
# Usage: .\preprocess-for-claude.ps1 <file> [-OutputPath <path>]

param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,

    [string]$OutputPath,

    [switch]$Batch
)

function Process-File {
    param([string]$Path)

    $file = Get-Item $Path
    $ext = $file.Extension.ToLower()
    $base = $file.BaseName

    if (-not $OutputPath) {
        $OutputPath = $file.DirectoryName
    }

    switch ($ext) {
        ".pdf" {
            $output = Join-Path $OutputPath "$base.txt"
            Write-Host "Converting PDF to text: $output" -ForegroundColor Green
            & pdftotext.exe -layout $file.FullName $output
        }
        ".docx" {
            $output = Join-Path $OutputPath "$base.md"
            Write-Host "Converting DOCX to Markdown: $output" -ForegroundColor Green
            & markitdown $file.FullName > $output
        }
        ".xlsx" {
            $output = Join-Path $OutputPath "$base.md"
            Write-Host "Converting XLSX to Markdown: $output" -ForegroundColor Green
            & markitdown $file.FullName > $output
        }
        ".pptx" {
            $output = Join-Path $OutputPath "$base.md"
            Write-Host "Converting PPTX to Markdown: $output" -ForegroundColor Green
            & markitdown $file.FullName > $output
        }
        ".png" {
            $output = Join-Path $OutputPath "$base-optimized.png"
            Write-Host "Resizing PNG: $output" -ForegroundColor Green
            & magick.exe $file.FullName -resize 2000x2000 -quality 85 $output
        }
        ".jpg" {
            $output = Join-Path $OutputPath "$base-optimized.jpg"
            Write-Host "Resizing JPEG: $output" -ForegroundColor Green
            & magick.exe $file.FullName -resize 2000x2000 -quality 85 $output
        }
        ".jpeg" {
            $output = Join-Path $OutputPath "$base-optimized.jpg"
            Write-Host "Resizing JPEG: $output" -ForegroundColor Green
            & magick.exe $file.FullName -resize 2000x2000 -quality 85 $output
        }
        default {
            Write-Warning "Unknown file type: $ext"
        }
    }
}

if ($Batch) {
    # Process all supported files in directory
    $files = Get-ChildItem -File | Where-Object {
        $_.Extension -match '\.(pdf|docx|xlsx|pptx|png|jpg|jpeg)$'
    }
    foreach ($file in $files) {
        Process-File -Path $file.FullName
    }
} else {
    Process-File -Path $FilePath
}
