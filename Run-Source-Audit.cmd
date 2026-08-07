@echo off
setlocal
cd /d "%~dp0"

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Invoke-AuditAndPublish.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo Audit failed with exit code %EXIT_CODE%.
    echo Review the error above. No Workshop source folders were committed.
) else (
    echo Audit workflow completed successfully.
)

echo.
pause
exit /b %EXIT_CODE%
