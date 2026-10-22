@echo off
chcp 65001 > nul
echo ========================================================
echo   بکاپ روزانه‌ی خودکار ماتریس آیزنهاور
echo ========================================================
echo.
echo کد سینک (Database Secret) را paste کن و Enter بزن.
echo کد رمزنگاری می‌شود و فقط همین کاربر ویندوز می‌تواند بازش کند.
echo اگر دیتابیس هنوز قفل نیست، فقط Enter بزن.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup-firebase.ps1" -Setup
echo.
echo گزارش همه‌ی بکاپ‌ها: backups\auto-backup.log
pause
