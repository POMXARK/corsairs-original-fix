@echo off
rem opens the settings window; the game is in Program Files, so the window asks for the administrator rights
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath cmd -ArgumentList '/c \"\"%~f0\"\"'"
  exit /b
)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0settings.ps1"
