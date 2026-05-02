@echo off
echo ============================================
echo   N-Bus Power Flow - Run All Tests
echo ============================================
echo.

set ROOT=%~dp0

echo [1/2] Running pytest ^(85 unit tests^)...
echo.
cd /d %ROOT%
python -m pytest tests/ -v
set PYTEST_RESULT=%ERRORLEVEL%

echo.
echo [2/2] Running Playwright E2E ^(54 tests^)...
echo.
cd /d %ROOT%frontend
set PW_OUTPUT=%TEMP%\nbus-pw-output-%RANDOM%-%RANDOM%
set PLAYWRIGHT_BACKEND_PORT=8001
set PLAYWRIGHT_FRONTEND_PORT=3000
set PLAYWRIGHT_REUSE_BACKEND=1
set PLAYWRIGHT_REUSE_FRONTEND=1
set NEXT_PUBLIC_API_URL=http://127.0.0.1:%PLAYWRIGHT_BACKEND_PORT%
npx playwright test --reporter=list --output="%PW_OUTPUT%"
set PLAYWRIGHT_RESULT=%ERRORLEVEL%

echo.
echo ============================================
if %PYTEST_RESULT%==0 (echo   pytest:     PASSED) else (echo   pytest:     FAILED)
if %PLAYWRIGHT_RESULT%==0 (echo   Playwright: PASSED) else (echo   Playwright: FAILED)
echo ============================================
