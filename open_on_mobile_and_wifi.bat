@echo off
rem Serves the app on this Wi-Fi (port 8080) so a phone on the same Wi-Fi can open it.
rem Plain ASCII on purpose: cmd skips lines in batch files that mix "chcp 65001" with Persian text.
for /f "tokens=4" %%a in ('route print^|findstr 0.0.0.0.*0.0.0.0') do (
    set LOCAL_IP=%%a
    goto :found_ip
)
:found_ip
echo ========================================================
echo   Eisenhower Matrix on this Wi-Fi
echo ========================================================
echo.
echo   This PC:             http://localhost:8080
echo   Phone on this Wi-Fi: http://%LOCAL_IP%:8080
echo.
echo   This address is a separate copy of the app: enter the sync code once in its Settings.
echo   Close this window to stop the server.
echo ========================================================
python "%~dp0tools\serve_lan.py"
pause
