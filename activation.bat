@echo off
setlocal

:: Check if already running as Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: --- Admin-required commands start here ---
cd /d "%~dp0"
echo Running with administrator privileges.
powershell.exe -executionpolicy bypass -file ./LaptopTest.ps1

echo "PDF is saved in the Desktop. Review the PDF and make necessary changes, then send it to printer."
pause