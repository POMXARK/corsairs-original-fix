@echo off
rem the game with F8 (screenshot), F9 (video) and the FPS log; PresentMon needs the rights of an administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath cmd -ArgumentList '/c \"\"%~f0\"\"'"
  exit /b
)
cd /d "%~dp0.."
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0capture.ps1" -GameDir "%CD%"
start "" /d "%CD%" ENGINE.exe
