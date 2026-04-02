@echo off
:: Pre-process files for Claude Code
:: Usage: preprocess-for-claude.bat <file>

if "%~1"=="" (
    echo Usage: preprocess-for-claude.bat ^<file^>
    exit /b 1
)

set "file=%~1"
set "ext=%~x1"

if /i "%ext%"==".pdf" (
    pdftotext.exe -layout "%file%" "%~n1.txt"
    echo Converted to: %~n1.txt
) else if /i "%ext%"==".docx" (
    markitdown "%file%" > "%~n1.md"
    echo Converted to: %~n1.md
) else if /i "%ext%"==".xlsx" (
    markitdown "%file%" > "%~n1.md"
    echo Converted to: %~n1.md
) else if /i "%ext%"==".pptx" (
    markitdown "%file%" > "%~n1.md"
    echo Converted to: %~n1.md
) else if /i "%ext%"==".png" (
    magick.exe "%file%" -resize 2000x2000 -quality 85 "%~n1-optimized.png"
    echo Resized to: %~n1-optimized.png
) else if /i "%ext%"==".jpg" (
    magick.exe "%file%" -resize 2000x2000 -quality 85 "%~n1-optimized.jpg"
    echo Resized to: %~n1-optimized.jpg
) else if /i "%ext%"==".jpeg" (
    magick.exe "%file%" -resize 2000x2000 -quality 85 "%~n1-optimized.jpg"
    echo Resized to: %~n1-optimized.jpg
) else (
    echo Unknown file type: %ext%
    exit /b 1
)
