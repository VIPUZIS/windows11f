# =====================================================================
# 13-remove-defender.ps1 — ⚠ ПОЛНОЕ УДАЛЕНИЕ Microsoft Defender ⚠
# Windows 11 Wezograph build (Audit Mode)
#
# ЧТО ДЕЛАЕТ:
#   1. Отключает Tamper Protection через реестр + выключенный WSC
#   2. Останавливает и отключает службы WinDefend, WdNisSvc, Sense, wscsvc...
#   3. Выставляет политики DisableAntiSpyware / DisableRealTimeMonitoring
#   4. Удаляет SecHealthUI Appx
#   5. Переименовывает файлы драйверов-фильтров (WdFilter/WdNisDrv/WdBoot)
#      на *.wezograph.disabled — после reboot они не загрузятся; сами .sys
#      можно удалить из offline-образа (см. README).
#   6. Сносит планировщик Defender и папки ProgramData\Microsoft\Windows Defender
#
# !!! Требуется ПЕРЕЗАГРУЗКА в конце для завершения снятия фильтров. !!!
# !!! После этого система НЕ имеет антивируса. Решайте сами.        !!!
# =====================================================================

param(
    [switch]$DryRun          # показать что будет сделано, ничего не менять
)

$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy Bypass -Scope Process -Force

$log = "$env:TEMP\wezograph_defender.log"
function Log($msg) { Write-Host $msg; Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format s), $msg) }
function Run($cmd) { if ($DryRun) { Log "DRYRUN: $cmd" } else { cmd /c $cmd 2>&1 | Out-Null; Log "EXEC : $cmd (rc=$LASTEXITCODE)" } }

Log "=== Defender removal: старт (DryRun=$DryRun) ==="

# ---------- 1. Политика: отключение до остановки служб ----------
$polPaths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet',
    'HKLM:\SYSTEM\CurrentControlSet\Services\SecurityHealthService'
)
foreach ($p in $polPaths) { New-Item -Path $p -Force -EA SilentlyContinue | Out-Null }

$pol = @{
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' = @{
        DisableAntiSpyware=1; DisableAntiVirus=1; DisableSpecialFeatures=1;
        AllowSwitchToNonBestPractices=1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' = @{
        DisableBehaviorMonitoring=1; DisableOnAccessProtection=1;
        DisableRealtimeMonitoring=1; DisableScanOnRealtimeEnable=1;
        DisableIOAVProtection=1; DisableRawFullScan=1
    }
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet' = @{
        SpyNetReporting=0; SubmitSamplesConsent=2; DontReportInfectionInformation=1
    }
    'HKLM:\SYSTEM\CurrentControlSet\Services\SecurityHealthService' = @{ Start=4 }
}
foreach ($k in $pol.Keys) {
    foreach ($n in $pol[$k].Keys) {
        Set-ItemProperty -Path $k -Name $n -Type DWord -Value $pol[$k][$n] -Force -EA SilentlyContinue
    }
}
Log "Политики Defender → disabled."

# ---------- 2. Службы ----------
foreach ($s in @('WinDefend','WdNisSvc','Sense','SecurityHealthService','wscsvc')) {
    Run "sc stop `"$s`""
    Run "sc config `"$s`" start= disabled"
    Run "sc failure `"$s`" reset= 0 actions= ignore/0"
    Log "Service down: $s"
}

# ---------- 3. SecHealthUI Appx ----------
try {
    Get-AppxPackage -AllUsers *SecHealthUI* | Remove-AppxPackage -EA SilentlyContinue
    Get-ProvisionedAppxPackage -Online -EA SilentlyContinue |
        Where-Object PackageName -like '*SecHealthUI*' | ForEach-Object {
            Remove-ProvisionedAppxPackage -Online -PackageName $_.PackageName -EA SilentlyContinue
        }
    Log "SecHealthUI удалён (если был)."
} catch {}

# ---------- 4. Планировщик Defender ----------
Get-ScheduledTask -TaskPath '\Microsoft\Windows\Windows Defender\' -EA SilentlyContinue | ForEach-Object {
    Disable-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName -EA SilentlyContinue | Out-Null
    Log "Task disabled: $($_.TaskName)"
}

# ---------- 5. Файлы фильтров: rename на следующий boot ----------
Log "Переименование driver/sys файлов (вступит после reboot)..."
$driverFiles = @(
    "$env:SystemRoot\System32\drivers\WdFilter.sys",
    "$env:SystemRoot\System32\drivers\WdNisDrv.sys",
    "$env:SystemRoot\System32\drivers\WdBoot.sys"
)
foreach ($f in $driverFiles) {
    if (Test-Path $f) {
        Run ("move /y `"{0}`" `"{0}.wezograph.disabled`"" -f $f)
    }
}
# MsMpEng.exe и компаньоны
$binFiles = @(
    "$env:ProgramFiles\Windows Defender\MsMpEng.exe",
    "$env:ProgramFiles\Windows Defender\nisupdate.exe",
    "$env:ProgramFiles\Windows Defender\MpCmdRun.exe"
)
foreach ($f in $binFiles) { if (Test-Path $f) { Run ("del /f /q `"{0}`"" -f $f) } }

# Если move не сработал из-за блокировки — используем PendingFileRenameOperations
if (-not $DryRun) {
    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $existing = (Get-ItemProperty $regPath -Name PendingFileRenameOperations -EA SilentlyContinue).PendingFileRenameOperations
    $newVal = @()
    if ($existing) { $newVal += $existing }
    foreach ($f in $driverFiles) {
        if (Test-Path $f) {
            $newVal += "\??\$f"; $newVal += "\??\$f.wezograph.disabled"
        }
    }
    if ($newVal.Count -gt 0) {
        Set-ItemProperty -Path $regPath -Name PendingFileRenameOperations -Value $newVal -Type MultiString -Force
        Log "PendingFileRenameOperations записан — файлы уйдут при reboot."
    }
}

# ---------- 6. ProgramData / кэши ----------
$dirs = @(
    "$env:ProgramData\Microsoft\Windows Defender",
    "$env:ProgramData\Microsoft\Windows Defender Advanced Threat Protection",
    "$env:ProgramData\Microsoft\Network\Downloader"
)
foreach ($d in $dirs) {
    if (Test-Path $d) { Run ("rmdir /s /q `"{0}`"" -f $d) }
}

# ---------- 7. Подчистка реестра служб (чтобы не восстанавливались) ----------
foreach ($s in @('WinDefend','WdNisSvc','Sense','WdBoot','WdFilter','WdNisDrv')) {
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$s"
    if (Test-Path $key) {
        Set-ItemProperty $key -Name Start -Type DWord -Value 4 -Force -EA SilentlyContinue
        Set-ItemProperty $key -Name ImagePath -Value 'system32\drivers\notexist.sys' -Type ExpandString -Force -EA SilentlyContinue
        Log "Service key neutered: $s"
    }
}

Log "=== Defender removal: ГОТОВО ==="
Log ">>> ТРЕБУЕТСЯ ПЕРЕЗАГРУЗКА. После reboot вернитесь в Audit Mode и продолжайте сборку <<<"

if (-not $DryRun) {
    $ans = Read-Host "Перезагрузить сейчас? (y/N)"
    if ($ans -match '^[yY]') {
        Log "Reboot по запросу пользователя..."
        Restart-Computer -Force
    } else {
        Log "Reboot отложен пользователем. Не забудьте сделать его перед sysprep!"
    }
}
