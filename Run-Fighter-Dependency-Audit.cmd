@echo off
setlocal
cd /d "%~dp0"

echo Tracing TIE/LN and X-wing dependencies...
echo This reads local source files but does not copy Workshop assets.
echo.

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Invoke-FighterDependencyAuditAndPublish.ps1"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo Fighter dependency audit failed with exit code %EXIT_CODE%.
    echo Review the error above. No Workshop source folders were committed.
) else (
    echo Fighter dependency audit completed successfully.
)

echo.
pause
exit /b %EXIT_CODE%
