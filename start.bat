@echo off
cd /d "%~dp0"

:: Re-launch minimized if not already
if not "%MINIMIZED%"=="1" (
    set MINIMIZED=1
    start /min "" "%~f0"
    exit
)

:: Try virtual environment first
if exist ".venv\Scripts\python.exe" (
    echo Starting with .venv...
    ".venv\Scripts\python.exe" app.py
    goto :end
)

:: Fall back to system Python
where python >nul 2>&1
if %ERRORLEVEL% == 0 (
    echo Starting with system Python...
    python app.py
    goto :end
)

where python3 >nul 2>&1
if %ERRORLEVEL% == 0 (
    echo Starting with python3...
    python3 app.py
    goto :end
)

echo ERROR: Python tidak ditemukan. Install Python 3.10+ dari https://python.org
pause
exit /b 1

:end
pause
