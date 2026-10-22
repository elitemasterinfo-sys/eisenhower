# Daily read-only backup of the Eisenhower tasks from Firebase into ..\backups
# Only GETs the data; never writes to Firebase.
#   backup-firebase.ps1            take one backup (what the scheduled task runs)
#   backup-firebase.ps1 -Register  create or refresh the daily scheduled task
#   backup-firebase.ps1 -Setup     ask for the sync code in a small window, then -Register, then one backup
#                                  (what set-sync-code.bat runs); the result is shown in a message box
# The sync code is kept in backups\sync-code.dat, encrypted so only this Windows user can decrypt it (DPAPI);
# backups\ never leaves this PC (not in git, not served on Wi-Fi). Keeps the newest 30 automatic backups,
# never touches other files, and keeps everything if a backup looks much smaller than the last one.
param([switch]$Setup, [switch]$Register)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$appDir     = Split-Path -Parent $PSScriptRoot
$backupDir  = Join-Path $appDir 'backups'
$secretFile = Join-Path $backupDir 'sync-code.dat'
$url        = 'https://task-manager-c285d-default-rtdb.firebaseio.com/tasks.json'
$keep       = 30
$taskName   = 'Eisenhower Firebase Backup'

function Register-BackupTask {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $daily = New-ScheduledTaskTrigger -Daily -At '13:00'
    $logon = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $logon.Delay = 'PT10M'
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $description = 'Read-only daily backup of the Eisenhower app tasks (Firebase) into D:\Ai\eisenhower-app\backups'
    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($daily, $logon) -Settings $settings -Description $description -Force | Out-Null
    } catch {
        # A logon trigger can need admin rights on some PCs; the daily one (run late if the PC was off) is enough
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $daily -Settings $settings -Description $description -Force | Out-Null
    }
}

# A normal window with a password box: pasting there is easier than in a console
function Read-SyncCode {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Eisenhower daily backup'
    $form.StartPosition = 'CenterScreen'
    $form.TopMost = $true
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(440, 150)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Paste the sync code (Firebase Database Secret) and click OK.`nIt is saved encrypted; only this Windows user can read it."
    $label.SetBounds(14, 12, 412, 40)
    $box = New-Object System.Windows.Forms.TextBox
    $box.UseSystemPasswordChar = $true
    $box.SetBounds(14, 60, 412, 24)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.SetBounds(250, 104, 84, 30)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cancel.SetBounds(342, 104, 84, 30)
    $form.Controls.AddRange(@($label, $box, $ok, $cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $form.Add_Shown({ $form.Activate(); $box.Focus() })
    $answer = $form.ShowDialog()
    $text = $box.Text.Trim()
    $form.Dispose()
    if ($answer -ne [System.Windows.Forms.DialogResult]::OK -or -not $text) { return $null }
    return (ConvertTo-SecureString $text -AsPlainText -Force)
}

function Show-Result($text, $isError) {
    Add-Type -AssemblyName System.Windows.Forms
    $icon = if ($isError) { [System.Windows.Forms.MessageBoxIcon]::Warning } else { [System.Windows.Forms.MessageBoxIcon]::Information }
    [void][System.Windows.Forms.MessageBox]::Show($text, 'Eisenhower daily backup', [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
}

New-Item -ItemType Directory -Force $backupDir | Out-Null

if ($Setup) {
    $code = Read-SyncCode
    if ($code) {
        $code | ConvertFrom-SecureString | Set-Content $secretFile
    } elseif (-not (Test-Path $secretFile)) {
        Show-Result 'No sync code entered; nothing was saved. Run set-sync-code.bat again when you have the code.' $true
        exit 1
    }
}
if ($Setup -or $Register) { Register-BackupTask }
if ($Register -and -not $Setup) {
    Write-Host "Scheduled task '$taskName' is set (daily 13:00, or as soon as the PC is on)."
    exit 0
}

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
$exitCode = 0
$result = ''
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
    $result = "Backup OK: {0} active, {1} in trash" -f $counts.active, $counts.trash
    if (Test-Path $failed) { Remove-Item $failed }

    $autos = @(Get-ChildItem $backupDir -Filter 'auto-firebase-tasks-*.json' | Sort-Object Name -Descending)
    $shrunk = $false
    if ($autos.Count -gt 1) {
        $prev = Get-Counts $autos[1].FullName
        if ($counts.active -lt [Math]::Floor($prev.active / 2)) {
            $shrunk = $true
            Write-Log ("WARN  active tasks dropped from {0} to {1}; keeping every old backup" -f $prev.active, $counts.active)
            Set-Content -Path $failed -Encoding UTF8 -Value ("{0:yyyy-MM-dd HH:mm}: active tasks dropped from {1} to {2}. Check the app; all old backups are kept." -f (Get-Date), $prev.active, $counts.active)
            $result += "`nWARNING: active tasks dropped from $($prev.active) to $($counts.active); all old backups are kept."
        }
    }
    if (-not $shrunk) { $autos | Select-Object -Skip $keep | Remove-Item }
}
catch {
    if ($tmp -and (Test-Path $tmp)) { Remove-Item $tmp }
    $reason = $_.Exception.Message
    if ($reason -match '401|403|Unauthorized|Forbidden') {
        $reason = if (Test-Path $secretFile) { 'the database refused the saved sync code: run set-sync-code.bat and paste the code again' } else { 'database is locked: run tools\set-sync-code.bat and paste the sync code' }
    }
    Write-Log "FAIL  $reason"
    Set-Content -Path $failed -Encoding UTF8 -Value ("{0:yyyy-MM-dd HH:mm}: {1}" -f (Get-Date), $reason)
    $result = "Backup FAILED: $reason"
    $exitCode = 1
}

Write-Host $result
if ($Setup) { Show-Result $result ($exitCode -ne 0) }
exit $exitCode
