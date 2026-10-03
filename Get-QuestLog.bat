@echo off
rem Run with the headset plugged in, right after a problem. Saves the game's logs into logs\ for a bug report.
cd /d "%~dp0"
if not exist logs mkdir logs
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
if not exist "%ADB%" set ADB=%~dp0tools\platform-tools\adb.exe
if not exist "%ADB%" set ADB=adb
"%ADB%" pull /sdcard/Android/data/com.segadreamcat.vhrquest/files/vhrq-log.txt logs\vhrq-log.txt
"%ADB%" pull /sdcard/Android/data/com.segadreamcat.vhrquest/files/vhrq-log-previous.txt logs\vhrq-log-previous.txt
"%ADB%" logcat -d -t 20000 > logs\system-log.txt
echo Saved to the logs folder. Attach vhrq-log.txt (and vhrq-log-previous.txt after a crash) to your bug report.
pause
