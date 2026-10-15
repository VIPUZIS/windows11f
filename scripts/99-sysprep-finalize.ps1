# =====================================================================
# 99-sysprep-finalize.ps1 — прогон всех шагов + финальный Sysprep
# Windows 11 Wezograph build (Audit Mode)
#
# Параметры (пробрасываются в дочерние скрипты):
#   -KeepStore -KeepNotepad -KeepXbox -RemoveEdge
#   -NoDefender            не запускать удаление Defender
#   -Remove                удалять службы, а не только отключать
#   -NoDISM                пропустить долгий DISM cleanup
#   -MinPagefile
#   -UnattendPath <path>   путь к autounattend.xml для /oobe
#   -SkipSysprep           только зачистка, без sysprep (для итераций)
# =====================================================================

param(
    [switch]$KeepStore,
    [switch]$KeepNotepad,
    [switch]$KeepXbox,
    [switch]$RemoveEdge,
    [switch]$NoDefender,
    [switch]$Remove,
    [switch]$NoDISM,
    [switch]$MinPagefile,
    [string]$UnattendPath = 'C:\wezo\autounattend.xml',
    [switch]$SkipSysprep
)

$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy Bypass -Scope Process -Force

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# Собираем аргументы для дочерних скриптов (только реально заданные switch'и)
$appArgs = @()
if ($KeepStore)   { $appArgs += '-KeepStore' }
if ($KeepNotepad) { $appArgs += '-KeepNotepad' }
if ($KeepXbox)    { $appArgs += '-KeepXbox' }
if ($RemoveEdge)  { $appArgs += '-RemoveEdge' }

$svcArgs = @(); if ($Remove)     { $svcArgs += '-Remove' }
$clnArgs = @()
if ($NoDISM)     { $clnArgs += '-NoDISM' }
if ($MinPagefile){ $clnArgs += '-MinPagefile' }

function Invoke-Step($name, $script, $argList) {
    Write-Host "`n==================== $name ====================" -ForegroundColor Yellow
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script @argList
    Write-Host "==================== $name завершено (rc=$LASTEXITCODE) ====" -ForegroundColor DarkYellow
}

Invoke-Step "1/5 Приложения" "$here\10-remove-apps.ps1" $appArgs
Invoke-Step "2/5 Телеметрия" "$here\11-strip-telemetry.ps1" @()
Invoke-Step "3/5 Службы"     "$here\12-disable-services.ps1" $svcArgs

if (-not $NoDefender) {
    Invoke-Step "4/5 Defender" "$here\13-remove-defender.ps1" @()
} else {
    Write-Host "[Wezograph] Шаг 4 (Defender) пропущен по флагу -NoDefender." -ForegroundColor Cyan
}

Invoke-Step "5/5 Cleanup" "$here\14-cleanup.ps1" $clnArgs

if ($SkipSysprep) {
    Write-Host "[Wezograph] SkipSysprep=true — sysprep НЕ запущен. Повторите позже." -ForegroundColor Green
    exit 0
}

Write-Host "`n[Wezograph] ФИНАЛЬНЫЙ SYSPEEP: /generalize /oobe /shutdown" -ForegroundColor Magenta
if (-not (Test-Path $UnattendPath)) {
    Write-Warning "Файл ответов '$UnattendPath' не найден — запускаем sysprep БЕЗ /unattend."
    $unArg = @()
} else {
    $unArg = @("/unattend:$UnattendPath")
}

$sysprep = "$env:SystemRoot\System32\Sysprep\sysprep.exe"
Start-Process -FilePath $sysprep -ArgumentList ('/generalize','/oobe','/shutdown') + $unArg -Wait
