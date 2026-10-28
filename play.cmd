@echo off
rem the game with F8 (screenshot), F9 (video) and the FPS log; PresentMon needs the rights of an administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath cmd -ArgumentList '/c \"\"%~f0\" %~1 %~2\"'"
  exit /b
)
cd /d "%~dp0.."
set MODE=normal
if /i "%~1"=="lowlag" set MODE=lowlag
set EXTRA=
if /i "%~2"=="nokeys" set EXTRA=-NoKeyRepeat
if /i "%~2"=="nofine" set EXTRA=-NoFineTick
if /i "%~2"=="none" set EXTRA=-NoKeyRepeat -NoFineTick
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0profile.ps1" -GameDir "%CD%" -Mode %MODE%
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0capture.ps1" -GameDir "%CD%" -ShowFps %EXTRA%
start "" /d "%CD%" ENGINE.exe
