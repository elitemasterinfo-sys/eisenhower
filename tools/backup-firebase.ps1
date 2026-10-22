# Daily read-only backup of the Eisenhower tasks from Firebase into ..\backups
# Only GETs the data; never writes to Firebase.
#   backup-firebase.ps1            take one backup (what the scheduled task runs)
#   backup-firebase.ps1 -Register  create or refresh the daily scheduled task
#   backup-firebase.ps1 -Setup     ask for the sync code, then -Register, then one backup (set-sync-code.bat)
# The sync code is kept in a file only this Windows user can decrypt (DPAPI). Keeps the newest 30 automatic
# backups, never touches other files, and keeps everything if a backup looks much smaller than the last one.
param([switch]$Setup, [switch]$Register)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$appDir     = Split-Path -Parent $PSScriptRoot
$backupDir  = Join-Path $appDir 'backups'
$secretDir  = Join-Path $env:LOCALAPPDATA 'EisenhowerBackup'
$secretFile = Join-Path $secretDir 'sync-code.dat'
$url        = 'https://task-manager-c285d-default-rtdb.firebaseio.com/tasks.json'
$keep       = 30
$taskName   = 'Eisenhower Firebase Backup'

function Register-BackupTask {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $daily = New-ScheduledTaskTrigger -Daily -At '13:00'
    $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $logon.Delay = 'PT10M'
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($daily, $logon) -Settings $settings -Description 'Read-only daily backup of the Eisenhower app tasks (Firebase) into D:\Ai\eisenhower-app\backups' -Force | Out-Null
    } catch {
        # A logon trigger can need admin rights on some PCs; the daily one (run late if the PC was off) is enough
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $daily -Settings $settings -Description 'Read-only daily backup of the Eisenhower app tasks (Firebase) into D:\Ai\eisenhower-app\backups' -Force | Out-Null
    }
    Write-Host "Scheduled task '$taskName' is set (daily 13:00, or as soon as the PC is on)."
}

if ($Setup) {
    Write-Host ''
    Write-Host '  Daily backup of the Eisenhower app'
    Write-Host '  Paste the sync code (Firebase Database Secret) and press Enter.'
    Write-Host '  It is saved encrypted; only this Windows user can read it.'
    Write-Host ''
    $code = Read-Host 'Sync code (Database Secret)' -AsSecureString
    if ($code.Length -gt 0) {
        New-Item -ItemType Directory -Force $secretDir | Out-Null
        $code | ConvertFrom-SecureString | Set-Content $secretFile
        Write-Host 'Sync code saved (encrypted for this Windows user).'
    } else {
        Write-Host 'Nothing entered; the saved code (if any) is kept.'
    }
}
if ($Setup -or $Register) { Register-BackupTask }
if ($Register -and -not $Setup) { exit 0 }

New-Item -ItemType Directory -Force $backupDir | Out-Null
$log    = Join-Path $backupDir 'auto-backup.log'
$failed = Join-Path $backupDir 'LAST-AUTO-BACKUP-FAILED.txt'
function Write-Log($msg) {
    Add-Content -Path $log -Value ('{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $msg) -Encoding UTF8
}

function Get-Counts($file) {
    $data = [IO.File]::ReadAllText($file, [Text.Encoding]::UTF8) | ConvertFrom-Json
    $items = @()
    if ($data -is [array]) { $items = @($data | Where-Object { $_ }) }
    elseif ($data) { $items = @($data.PSObject.Properties | ForEach-Object { $_.Value } | Where-Object { $_ }) }
    $trash = @($items | Where-Object { $_.deleted -and -not $_.purged }).Count
    $active = @($items | Where-Object { -not $_.deleted }).Count
    return @{ total = $items.Count; active = $active; trash = $trash }
}

$tmp = $null
try {
    $query = ''
    if (Test-Path $secretFile) {
        $secure = Get-Content $secretFile | ConvertTo-SecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $query = '?auth=' + [Uri]::EscapeDataString($plain)
    }

    $stamp = '{0:yyyy-MM-dd_HHmmss}' -f (Get-Date)
    $file = Join-Path $backupDir "auto-firebase-tasks-$stamp.json"
    $tmp = "$file.part"
    Invoke-WebRequest -Uri ($url + $query) -UseBasicParsing -TimeoutSec 60 -OutFile $tmp
    $counts = Get-Counts $tmp
    Move-Item $tmp $file -Force
    $tmp = $null
    Write-Log ("OK    {0} active, {1} in trash -> {2}" -f $counts.active, $counts.trash, (Split-Path -Leaf $file))
    Write-Host ("Backup OK: {0} active, {1} in trash" -f $counts.active, $counts.trash)
    if (Test-Path $failed) { Remove-Item $failed }

    $autos = @(Get-ChildItem $backupDir -Filter 'auto-firebase-tasks-*.json' | Sort-Object Name -Descending)
    if ($autos.Count -gt 1) {
        $prev = Get-Counts $autos[1].FullName
        if ($counts.active -lt [Math]::Floor($prev.active / 2)) {
            Write-Log ("WARN  active tasks dropped from {0} to {1}; keeping every old backup" -f $prev.active, $counts.active)
            Set-Content -Path $failed -Encoding UTF8 -Value ("{0:yyyy-MM-dd HH:mm}: active tasks dropped from {1} to {2}. Check the app; all old backups are kept." -f (Get-Date), $prev.active, $counts.active)
            exit 0
        }
    }
    $autos | Select-Object -Skip $keep | Remove-Item
}
catch {
    if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp }
    $reason = $_.Exception.Message
    if ($reason -match '401|403|Unauthorized|Forbidden') { $reason = 'database is locked: run tools\set-sync-code.bat and paste the sync code' }
    Write-Log "FAIL  $reason"
    Set-Content -Path $failed -Encoding UTF8 -Value ("{0:yyyy-MM-dd HH:mm}: {1}" -f (Get-Date), $reason)
    Write-Host "Backup FAILED: $reason"
    exit 1
}
