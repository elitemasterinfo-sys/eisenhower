@echo off
rem Saves the sync code for the daily backup (encrypted for this Windows user) and sets up the daily task.
rem A small window asks for the code and a message shows the result. Log: ..\backups\auto-backup.log
rem Plain ASCII on purpose: cmd skips lines in batch files that mix "chcp 65001" with Persian text.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0backup-firebase.ps1" -Setup
