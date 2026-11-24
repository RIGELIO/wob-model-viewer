@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Register-FileTypes.ps1"
if errorlevel 1 pause
