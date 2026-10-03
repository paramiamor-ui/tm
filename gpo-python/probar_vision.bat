@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Arrastra capturas de pantalla (1920x1080) encima de este archivo para ver que detecta.
python vision.py %*
pause
