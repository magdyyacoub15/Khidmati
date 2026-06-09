@echo off
echo ==========================================
echo      Manger App - Local Web Debugging
echo ==========================================
echo 1. Launching App in Chrome...
echo (Make sure Chrome is installed)
echo.
call flutter run -d chrome
if %errorlevel% neq 0 (
    echo [ERROR] Failed to start. Try running 'flutter doctor'.
    pause
    exit /b %errorlevel%
)
pause
