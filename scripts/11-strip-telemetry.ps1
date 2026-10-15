# =====================================================================
# 11-strip-telemetry.ps1 — вырезание телеметрии, CEIP, планировщика
# Windows 11 Wezograph build (Audit Mode)
# =====================================================================

param(
    [switch]$KeepTasks        # только политики/службы, scheduled tasks не трогать
)

$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy Bypass -Scope Process -Force

$log = "$env:TEMP\wezograph_telemetry.log"
function Log($msg) { Write-Host $msg; Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format s), $msg) }
Log "=== Телеметрия: старт ==="

# ---------- 1. Политики через реестр ----------
$policySets = @(
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Props=@{
        AllowTelemetry=0; MaxTelemetryAllowed=1; DisableShieldedVFWindows=0 } },
    @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Props=@{
        AllowTelemetry=1; MaxTelemetryAllowed=1 } },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\MRT'; Props=@{ DontReportInfectionInformation=1; DontOfferThroughWUAU=1 } },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; Props=@{ CEIPEnable=0 } },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'; Props=@{ AITEnable=0; SBEnable=0; DisableInventory=1 } },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Props=@{ DODownloadMode=99 } },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization'; Props=@{ NoLockScreenCamera=1 } },
    @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeviceMetadata'; Props=@{ DiagtrackEnabled=0 } },
    @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack\EventTranscriptKey'; Props=@{ EnableEventTranscript=0 } },
    @{ Path='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\ProgramCompatibilityAssistant'; Props=@{ DisableCEIP=1 } },
    @{ Path='HKLM:\SOFTWARE\Microsoft\RemovalTools\MRT'; Props=@{ EULA=1 } },
    @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Props=@{ TailoredExperiencesWithDiagnosticDataEnabled=0 } },
    @{ Path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack'; Props=@{ ShowedToastAtLevel=1 } },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Props=@{
        DisableWindowsConsumerFeatures=1; DisableSoftLanding=1; DisableWindowsSpotlightFeatures=1;
        DisableCloudContentFeatures=1; DisableEnterpriseAuthParser=1 } },
    @{ Path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'; Props=@{ PublishUserActivities=0; UploadUserActivities=0; EnableActivityFeed=0 } },
    @{ Path='HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\System'; Props=@{ AllowExperimentation=0 } },
    @{ Path='HKLM:\SOFTWARE\Microsoft\PolicyManager\default\System\AllowExperimentation'; Props=@{ value=0 } },
    @{ Path='HKLM:\SOFTWARE\Microsoft\PolicyManager\default\System\AllowOnlineTipDelivery'; Props=@{ value=0 } },
    @{ Path='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Props=@{ HideSCAHealth=1 } }
)

foreach ($set in $policySets) {
    New-Item -Path $set.Path -Force -ErrorAction SilentlyContinue | Out-Null
    foreach ($k in $set.Props.Keys) {
        Set-ItemProperty -Path $set.Path -Name $k -Type DWord -Value $set.Props[$k] -Force -ErrorAction SilentlyContinue
    }
}
Log "Политики реестра применены."

# ---------- 2. Отключение служб телеметрии ----------
foreach ($s in @('DiagTrack','dmwappushservice','wisvc','lfsvc','MapsBroker','RetailDemo','PushToInstall')) {
    try {
        Stop-Service $s -Force -ErrorAction SilentlyContinue
        Set-Service $s -StartupType Disabled -ErrorAction SilentlyContinue
        Log "Служба $s → Disabled"
    } catch { Log "  ! $s : $($_.Exception.Message)" }
}

# ---------- 3. Scheduled Tasks ----------
if (-not $KeepTasks) {
    $taskPaths = @(
        '\Microsoft\Windows\Application Experience\*',
        '\Microsoft\Windows\ApplicationData\*',
        '\Microsoft\Windows\Autochk\*',
        '\Microsoft\Windows\Customer Experience Improvement Program\*',
        '\Microsoft\Windows\DiskDiagnostic\*',
        '\Microsoft\Windows\Feedback Hub\*',
        '\Microsoft\Windows\Flighting\*',
        '\Microsoft\Windows\Location\*',
        '\Microsoft\Windows\Maps\*',
        '\Microsoft\Windows\NetTrace\*',
        '\Microsoft\Windows\PIE\*',
        '\Microsoft\Windows\Power Efficiency Diagnostics\*',
        '\Microsoft\Windows\Shell\IndexesDetector*',
        '\Microsoft\Windows\SoftwareProtectionPlatform\SvcRestartTask*',
        '\Microsoft\Windows\Time Synchronization\SynchronizeTime*',
        '\Microsoft\Windows\Unified Telemetry Platform\*',
        '\Microsoft\Windows\UPnP\*',
        '\Microsoft\Windows\User Profile Service\*',
        '\Microsoft\Windows\WDI\*',
        '\Microsoft\Windows\Windows Error Reporting\*',
        '\Microsoft\Windows\Windows Filtering Platform\*',
        '\Microsoft\Windows\WindowsUpdate\*Scheduled*'
    )
    foreach ($tp in $taskPaths) {
        Get-ScheduledTask -TaskPath ($tp.Substring(0, $tp.LastIndexOf('\')+1)) -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -like ($tp.Split('\')[-1]) } | ForEach-Object {
                try {
                    Disable-ScheduledTask -TaskPath $_.TaskPath -TaskName $_.TaskName -ErrorAction Stop | Out-Null
                    Log "Task disabled: $($_.TaskPath)$($_.TaskName)"
                } catch { Log "  ! task $($_.TaskPath)$($_.TaskName): $($_.Exception.Message)" }
            }
    }
    # Явные notorious-задачи
    @('\Microsoft\Windows\Application Experience\ProgramDataUpdater',
      '\Microsoft\Windows\Application Experience\StartupAppTask',
      '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
      '\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask',
      '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
      '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
      '\Microsoft\Windows\Feedback Hub\HarvesterTask',
      '\Microsoft\Windows\Unified Telemetry Platform\UnifiedTelemetryPlatformUpload',
      '\Microsoft\Windows\Unified Telemetry Platform\NotifyUdcUser') | ForEach-Object {
        $parts = $_.Split('\')
        $name = $parts[-1]; $path = ($parts[0..($parts.Length-2)] -join '\') + '\'
        try { Disable-ScheduledTask -TaskPath $path -TaskName $name -ErrorAction Stop | Out-Null; Log "Task disabled: $_" } catch {}
    }
}

# ---------- 4. Файлы/каталоги телеметрии ----------
$targets = @(
    "$env:SystemRoot\System32\UDCRightsData",
    "$env:SystemRoot\System32\CatRoot2\dbgg.sqlite",
    "$env:ProgramData\Microsoft\Diagnosis",
    "$env:ProgramData\Microsoft\Network\Downloader",
    "$env:ProgramData\Microsoft\Windows\WER"
)
foreach ($t in $targets) {
    Remove-Item -Path $t -Recurse -Force -ErrorAction SilentlyContinue
}

# WER полностью отключаем
New-Item 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Force | Out-Null
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Name 'Disabled' -Type DWord -Value 1 -Force

Log "=== Телеметрия: готово. Лог: $log ==="
