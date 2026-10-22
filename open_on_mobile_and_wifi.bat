@echo off
chcp 65001 > nul
echo ========================================================
echo   اجرای ماتریس آیزنهاور برای دسترسی در شبکه و موبایل
echo ========================================================
echo.

:: Get local IP address
for /f "tokens=4" %%a in ('route print^|findstr 0.0.0.0.*0.0.0.0') do (
    set LOCAL_IP=%%a
    goto :found_ip
)
:found_ip

echo [1] آدرس دسترسی در همین کامپیوتر:
echo     http://localhost:8080
echo.
echo [2] آدرس دسترسی از گوشی یا لپ‌تاپ دیگر (روی همین وای‌فای):
echo     http://%LOCAL_IP%:8080
echo.
echo در حال اجرای سرور محلی... (برای توقف، این پنجره را ببندید)
echo ========================================================
echo.

python -m http.server 8080 --directory "%~dp0."
pause
