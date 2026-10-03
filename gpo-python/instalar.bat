@echo off
chcp 65001 >nul
echo === Instalando lo necesario para el macro de GPO ===
python --version || (echo. & echo No encuentro Python. Instalalo desde python.org marcando "Add python.exe to PATH". & pause & exit /b)
python -m pip install --upgrade pip
python -m pip install -r "%~dp0requirements.txt"
echo.
echo === Lector de texto (opcional: contador y compras) ===
python -m pip install winocr || echo No se pudo instalar winocr: el macro funcionara, pero sin leer el contador ni comprar.
echo.
echo Listo. Ahora abre iniciar.bat
pause
