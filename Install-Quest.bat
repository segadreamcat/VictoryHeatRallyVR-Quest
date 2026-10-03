@echo off
rem Double-click to build and install Victory Heat Rally VR on your Quest (see README.md first).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Quest.ps1" %*
pause
