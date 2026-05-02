@echo off
echo ============================================
echo   N-Bus Power Flow - Start All Services
echo ============================================
echo.

set ROOT=%~dp0

echo [0/3] Clearing ports 8000, 3000...
FOR /F "tokens=5" %%a IN ('netstat -aon ^| findstr :8000') DO taskkill /F /PID %%a >nul 2>&1
FOR /F "tokens=5" %%a IN ('netstat -aon ^| findstr :3000') DO taskkill /F /PID %%a >nul 2>&1
echo.

echo [1/3] Starting Backend (port 8000) with reload...
start "N-Bus Backend" cmd /c "cd /d %ROOT%backend && python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"

echo [2/3] Cleaning .next cache...
if exist "%ROOT%frontend\.next" rmdir /s /q "%ROOT%frontend\.next"

echo [3/3] Starting Frontend (port 3000)...
start "N-Bus Frontend" cmd /c "cd /d %ROOT%frontend && npm run dev"

echo.
echo Done. Open http://localhost:3000 in your browser.
echo.
echo Press any key to stop both services...
pause >nul

taskkill /FI "WINDOWTITLE eq N-Bus Backend*" /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq N-Bus Frontend*" /F >nul 2>&1
echo Services stopped.
