@echo off
set "SRC=%~dp0Launch PanicButton.vbs"
set "DEST=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Launch PanicButton.vbs"
copy /Y "%SRC%" "%DEST%" >nul
echo Panic Button will now start automatically every time you log in.
echo (Run "Disable Autostart.bat" to undo this.)
pause
