# =====================================================================
# 12-disable-services.ps1 — отключение/удаление служб
# Windows 11 Wezograph build (Audit Mode)
#
# Параметры:
#   -KeepPrint     не трогать Spooler и Print* (принтер нужен?)
#   -KeepSearch    оставить Windows Search (WSearch, SearchIndexer)
#   -Remove        реально удалять службы через sc.exe delete (агрессивно!)
#   -KeepHyperV    не трогать гипервизор-стек (vmcompute и пр.)
# =====================================================================

param(
    [switch]$KeepPrint,
    [switch]$KeepSearch,
    [switch]$Remove,
    [switch]$KeepHyperV
)

$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy Bypass -Scope Process -Force

$log = "$env:TEMP\wezograph_services.log"
function Log($msg) { Write-Host $msg; Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format s), $msg) }
Log "=== Службы: старт (Remove=$Remove) ==="

# ---------- Список служб на отключение ----------
$disableList = @(
    # Телеметрия/диагностика/отчёты
    'DiagTrack','dmwappushservice','wisvc','lfsvc','MapsBroker','RetailDemo',
    'WMPNetworkSvc','icssvc','TroubleshootingSvc','TroubledInstaller',
    'PushToInstall','DPS','WdiServiceHost','WdiSystemHost','Wecsvc',
    'SysMain','WerSvc','PcaSvc','TabletInputService','TokenBroker',
    'XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc',
    'BthHFSrv','bthserv','WiaRpc','stisvc',
    'RemoteRegistry','SharedAccess','RasAuto','RasMan','L2tpIcmSvc',
    'TermService','SessionEnv','UmRdpService','RmSvc',
    'Zoneserver','W32Time','EventSystem',
    'AppIDSvc','AppMgmt','AppReadiness','AppvClient',
    'Browser','FDResPub','SSDPSRV','upnphost','WpcMonSvc',
    'HomeGroupListener','HomeGroupProvider',
    'msiserver',                     # MSI — аккуратно: может ломать установщики
    'ose','osppsvc',
    'PerfHost','TrkWks',
    'WbioSrvc','WSearch',
    'wcncsvc','fhsvc','vmic*','vds','VolSnap',
    'wbengine','WMPNetworkSvc'
)

if ($KeepPrint) { $disableList = $disableList | Where-Object { $_ -notin @('Spooler','PrintNotify','PrintWorkflowUserSvc') } }
else { $disableList += @('Spooler','PrintNotify','PrintWorkflowUserSvc') }
if ($KeepSearch) { $disableList = $disableList | Where-Object { $_ -ne 'WSearch' } }
if ($KeepHyperV) { $disableList = $disableList | Where-Object { $_ -notlike 'vmic*' } }

foreach ($name in $disableList) {
    Get-Service -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Stop-Service $_.Name -Force -ErrorAction SilentlyContinue
            Set-Service $_.Name -StartupType Disabled -ErrorAction Stop
            Log "Disabled: $($_.Name)"
            if ($Remove) {
                cmd /c "sc.exe delete `"$($_.Name)`"" | Out-Null
                Log "Deleted : $($_.Name)"
            }
        } catch { Log "  ! $($_.Name): $($_.Exception.Message)" }
    }
}

# ---------- User-mode services (CDPUserSvc, OneSyncSvc и т.п.) ----------
$userSvcs = @(
    'CDPUserSvc','OneSyncSvc','DevicesFlowUserSvc','MessagingService',
    'PimIndexMaintenanceSvc','Unistoresvc','WpnUserService','ClipSVC'
)
foreach ($u in $userSvcs) {
    Get-Service -Name "$u*" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            Stop-Service $_.Name -Force -EA SilentlyContinue
            Set-Service $_.Name -StartupType Disabled -EA SilentlyContinue
            Log "Disabled(user): $($_.Name)"
        } catch {}
    }
}

# ---------- Отключение «периферийных» компонентов через DISM (best-effort) ----------
Log "DISM: удаление периферийных компонентов (некритичные ошибки логируются)..."
foreach ($f in @('OpenSSH.Client~~~~0.0.1.0','LegacyComponents','DirectPlay','MediaPlayback','Printing-XPSServices-Package-FoD')) {
    cmd /c "dism /online /disable-feature /featurename:$f /norestart" | Out-Null
    Log "DISM disable-feature: $f (rc=$LASTEXITCODE)"
}

# ---------- Автостарт-записи реестра (Run) для мусора ----------
$runKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
)
$junkRunValues = @('SecurityHealth','OneDriveSetup','MicrosoftEdgeUpdateTaskMachineUA','WindowsDefender')
foreach ($k in $runKeys) {
    foreach ($v in $junkRunValues) {
        Remove-ItemProperty -Path $k -Name $v -ErrorAction SilentlyContinue
    }
}

Log "=== Службы: готово. Лог: $log ==="
