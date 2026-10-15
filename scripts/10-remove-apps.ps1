# =====================================================================
# 10-remove-apps.ps1 — агрессивное удаление UWP/Provisioned пакетов
# Windows 11 Wezograph build (Audit Mode)
#
# Параметры:
#   -KeepStore     не удалять Microsoft Store и его зависимости
#   -KeepNotepad   оставить Notepad (UWP-версию)
#   -KeepXbox      не трогать Xbox-стек (GameBar остаётся, но отключается в 12-м скрипте)
#   -RemoveEdge    попытаться удалить MS Edge (работает не на всех сборках)
# =====================================================================

param(
    [switch]$KeepStore,
    [switch]$KeepNotepad,
    [switch]$KeepXbox,
    [switch]$RemoveEdge
)

$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy Bypass -Scope Process -Force

$log = "$env:TEMP\wezograph_apps.log"
function Log($msg) { Write-Host $msg; Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format s), $msg) }

Log "=== Удаление приложений: старт ==="

# ---------- Список масок имён пакетов ----------
$appPatterns = @(
    # Реклама / спонсоры / предустановленный мусор
    '*Microsoft.BingNews*','*Microsoft.BingSearch*','*Microsoft.BingWeather*',
    '*Microsoft.GetHelp*','*Microsoft.Getstarted*','*Microsoft.MicrosoftOfficeHub*',
    '*Microsoft.MicrosoftSolitaireCollection*','*Microsoft.PowerAutomateDesktop*',
    '*Microsoft.Todos*',
    '*Microsoft.549981C3F5F10*',          # Cortana
    '*Microsoft.MixedReality.Portal*',
    '*Microsoft.Clipchamp*','*Clipchamp*',
    '*MicrosoftTeams*','*MicrosoftCorporationII.MicrosoftTeams*',
    '*Microsoft.OutlookForWindows*',
    '*Microsoft.Copilot*','*WindowsCopilot*',
    '*Microsoft.StartExperiencesApp*',
    # Медиа / игры / коммуникации
    '*Microsoft.Xbox.TCUI*','*Microsoft.XboxApp*','*Microsoft.XboxGameOverlay*',
    '*Microsoft.XboxGamingOverlay*','*Microsoft.XboxIdentityProvider*','*Microsoft.XboxSpeechToTextOverlay*',
    '*Microsoft.GamingApp*',
    '*Microsoft.YourPhone*','*Microsoft.Messaging*','*Microsoft.CommunicationsApps*',
    '*Microsoft.OneConnect*','*Microsoft.People*','*Microsoft.Wallet*',
    '*Microsoft.MSPaint*','*Microsoft.3DBuilder*','*Microsoft.Paint3D*','*Microsoft.Paint*',
    '*Microsoft.MicrosoftStickyNotes*','*Microsoft.WindowsSoundRecorder*',
    '*Microsoft.ZuneMusic*','*Microsoft.ZuneVideo*','*Microsoft.Media.Player*',
    '*Microsoft.SkypeApp*',
    '*Microsoft.Delve*','*Microsoft.Forms*','*Microsoft.OneNote*',
    '*Microsoft.MinecraftUWP*','*Disney*','*Netflix*','*Spotify*','*TikTok*',
    '*Amazon*','*AdobeSystemsIncorporated*',
    '*FitbitCoach*','*LinkedIn*','*PicsArt*','*BytedancePteLtd*','*Duolingo*',
    '*WatchESPN*','*Canon*','*EclipseManager*','*ActiproSoftware*',
    '*FreshPaint*','*DesignPlus*','*MarchofEmpires*','*CandyCrush*','*BubbleWitch*',
    '*SpeedTest*','*Instagram*','*Windy*','*SynthwaveRacer*',
    '*ROVERCITYSTUDIO*','*XING*','*AOL*','*AccuWeather*','*HiddenCityMysteryofShadows*',
    # Системный балласт
    '*Microsoft.Advertising*','*Microsoft.OneDriveSync*','*microsoft.windowscommunicationsapps*',
    '*Microsoft.Feed*','*Microsoft.CommsPhone*','*Microsoft.ConnectivityStore*',
    '*Microsoft.PaymentMesh*','*Microsoft.Services.Store.Engagement*',
    '*Microsoft.UI.Xaml.CDebugProber*',
    '*Microsoft.BioEnrollment*','*Microsoft.DiagnosticInfoViewer*',
    '*Microsoft.ECCApp*','*Microsoft.Apprep.ChxApp*','*Microsoft.AssignedAccess*',
    '*Microsoft.CrossDevice*','*Microsoft.DeviceDiscovery*',
    '*Microsoft.NET.UpdateHistory*',
    '*Microsoft.Windows.DevHome*',
    '*Microsoft.RecoveryWindow*',
    '*Microsoft.WindowsTerminalPreview*',
    '*Microsoft.Windows.Photos*',
    '*Microsoft.BingFinance*','*Microsoft.BingSports*','*Microsoft.BingFoodandDrink*',
    '*Microsoft.BingHealthAndFitness*','*Microsoft.BingTravel*',
    '*Microsoft.Reader*','*Microsoft.Journey*','*Microsoft.HelpAndTips*',
    '*Microsoft.WindowsFeedbackHub*','*Microsoft.Whiteboard*','*Microsoft.Family*',
    '*MicrosoftAccount*','*RetailDemo*','*Microsoft.Retail*',
    '*Microsoft.DesktopAppInstaller*' # winget — при желании вернёте через Store
)

if ($KeepStore) {
    $appPatterns = $appPatterns | Where-Object {
        $_ -notin @('*Microsoft.WindowsStore*','*Microsoft.StorePurchaseApp*','*Microsoft.DesktopAppInstaller*')
    }
} else {
    $appPatterns += '*Microsoft.WindowsStore*','*Microsoft.StorePurchaseApp*','*Microsoft.ClientLicenseProtocol*'
}
if ($KeepNotepad) {
    $appPatterns = $appPatterns | Where-Object { $_ -notmatch 'Notepad' }
} else {
    $appPatterns += '*Microsoft.Notepad*'
}
if (-not $KeepXbox) {
    $appPatterns += '*Microsoft.Xbox*', '*Microsoft.GameServices*', '*Microsoft.PlayAsYouGo*'
}
if ($RemoveEdge) {
    $appPatterns += '*Microsoft.MicrosoftEdge*','*Microsoft.MicrosoftEdgeDevToolsClient*'
}

# Чистим список от мусорных placeholder-строк
$appPatterns = $appPatterns | Where-Object { $_ -and $_ -ne '-nonexistent-' -and $_ -notmatch '__never__' } | Sort-Object -Unique

Log "Шаблонов для удаления: $($appPatterns.Count)"

# ---------- 1. Удаление установленных пакетов у текущего пользователя ----------
foreach ($pat in $appPatterns) {
    try {
        $pkgs = Get-AppxPackage -Name $pat -ErrorAction SilentlyContinue
        foreach ($p in $pkgs) {
            Log "Remove-AppxPackage: $($p.Name) [$($p.PackageFullName)]"
            $p | Remove-AppxPackage -ErrorAction Continue | Out-Null
        }
    } catch { Log "  ! пропуск $($pat): $($_.Exception.Message)" }
}

# ---------- 2. Удаление у ВСЕХ пользователей (AllUsers) ----------
foreach ($pat in $appPatterns) {
    try {
        Get-AppxPackage -AllUsers -Name $pat -ErrorAction SilentlyContinue | ForEach-Object {
            Log "Remove-AppxPackage -AllUsers: $($_.Name)"
            try { $_ | Remove-AppxPackage -ErrorAction Continue | Out-Null } catch {}
        }
    } catch {}
}

# ---------- 3. Provisioned-пакеты (чтобы не ставились новым юзерам / после generalize) ----------
foreach ($pat in $appPatterns) {
    try {
        Get-ProvisionedAppxPackage -Online -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageName -like $pat } | ForEach-Object {
                Log "Remove-ProvisionedAppxPackage: $($_.PackageName)"
                try {
                    Remove-ProvisionedAppxPackage -Online -PackageName $_.PackageName -ErrorAction Continue | Out-Null
                } catch { Log "  ! provisioned skip: $($_.Exception.Message)" }
            }
    } catch {}
}

# ---------- 4. OneDrive (Win32 + автозапуск) ----------
Log "Удаление OneDrive..."
try {
    taskkill /f /im OneDrive.exe 2>$null | Out-Null
    if (Test-Path "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
        Start-Process "$env:SystemRoot\SysWOW64\OneDriveSetup.exe" '/uninstall' -Wait -ErrorAction SilentlyContinue
    } elseif (Test-Path "$env:SystemRoot\System32\OneDriveSetup.exe") {
        Start-Process "$env:SystemRoot\System32\OneDriveSetup.exe" '/uninstall' -Wait -ErrorAction SilentlyContinue
    }
    # следы
    Remove-Item -Path "$env:SystemRoot\System32\OneDrive*" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\SysWOW64\OneDrive*" -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft' -Name 'OneDrive' -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\OneDrive' -Name 'DisableFileSyncNGSC' -Type DWord -Value 1 -Force
} catch { Log "  ! OneDrive: $($_.Exception.Message)" }

# ---------- 5. Teams (new Teams, Win32) ----------
try {
    Get-AppxPackage -AllUsers *Teams* | Remove-AppxPackage -ErrorAction SilentlyContinue
    $teamsMachine = "$env:ProgramFiles\WindowsApps" # если что-то осталось — чистит generalize
    cmd /c "taskkill /f /im ms-teams.exe 2>nul" | Out-Null
    cmd /c "taskkill /f /im Teams.exe 2>nul" | Out-Null
} catch {}

# ---------- 6. Edge (если разрешено и возможно) ----------
if ($RemoveEdge) {
    Log "Попытка удалить Edge через setup-stub..."
    $setup = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    # Официально Edge удаляется только через `msedge.exe --uninstall` из setup.exe в некоторых каналах.
    # Делаем best-effort: блокируем автообновление и скрываем ярлыки.
    New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Name 'InstallDefault' -Type DWord -Value 0 -Force -ErrorAction SilentlyContinue
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate' -Name 'DoNotUpdateToEdgeWithChromium' -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue
}

# ---------- 7. Автоустановка приложений после OOBE (Cloud Content / Silent App Install) ----------
Log "Отключение самостановки рекомендованных приложений..."
$paths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications'
)
foreach ($p in $paths) { New-Item -Path $p -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Type DWord -Value 1 -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableSoftLanding' -Type DWord -Value 1 -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableCloudOptimizedContent' -Type DWord -Value 1 -Force
Set-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\PushNotifications' -Name 'NoToastApplicationNotificationOnLockScreen' -Type DWord -Value 1 -Force -ErrorAction SilentlyContinue

Log "=== Удаление приложений: готово. Лог: $log ==="
