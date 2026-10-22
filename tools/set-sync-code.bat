@echo off
rem Saves the sync code for the daily backup (encrypted for this Windows user) and sets up the daily task.
rem Plain ASCII on purpose: cmd skips lines in batch files that mix "chcp 65001" with Persian text.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0backup-firebase.ps1" -Setup
echo.
echo Log of every backup: %~dp0..\backups\auto-backup.log
pause
