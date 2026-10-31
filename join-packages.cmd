@echo off
setlocal
cd /d "%~dp0"
copy /b /y "goldilocks-monitor-portable.zip.001"+"goldilocks-monitor-portable.zip.002" "goldilocks-monitor-portable.zip" >nul
if errorlevel 1 exit /b 1
powershell -NoProfile -Command "$expected=(Get-Content -LiteralPath 'goldilocks-monitor-portable.zip.sha256').Split(' ')[0]; if ((Get-FileHash -Algorithm SHA256 -LiteralPath 'goldilocks-monitor-portable.zip').Hash.ToLower() -ne $expected) { Write-Error 'Checksum mismatch'; exit 1 }"
if errorlevel 1 exit /b 1
echo Verified: goldilocks-monitor-portable.zip
pause
