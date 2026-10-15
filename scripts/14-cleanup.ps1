# =====================================================================
# 14-cleanup.ps1 — зачистка мусора, DISM component cleanup, hiberfil
# Windows 11 Wezograph build (Audit Mode)
#
# Параметры:
#   -NoDISM        пропустить долгий StartComponentCleanup / ResetBase
#   -MinPagefile   загнать pagefile в минимум (C: 512MB fixed)
# =====================================================================

param(
    [switch]$NoDISM,
    [switch]$MinPagefile
)

$ErrorActionPreference = 'Continue'
Set-ExecutionPolicy Bypass -Scope Process -Force

$log = "$env:TEMP\wezograph_cleanup.log"
function Log($msg) { Write-Host $msg; Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format s), $msg) }
Log "=== Cleanup: старт ==="

# ---------- 1. Temp-папки ----------
Log "Чистим temp..."
$tempPaths = @(
    "$env:SystemRoot\Temp",
    "$env:TEMP",
    "C:\Users\Default\AppData\Local\Temp",
    "C:\Users\Administrator\AppData\Local\Temp",
    "$env:ProgramData\Microsoft\Windows\INetCache",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"  # thumbcache
)
foreach ($t in $tempPaths) {
    if (Test-Path $t) {
        Get-ChildItem $t -Recurse -Force -EA SilentlyContinue | Remove-Item -Recurse -Force -EA SilentlyContinue
    }
}

# ---------- 2. Остатки обновления ----------
Log "Чистим WinSxS pending / SoftwareDistribution..."
Stop-Service wuauserv,BITS,cryptsvc -Force -EA SilentlyContinue
Remove-Item "$env:SystemRoot\SoftwareDistribution\Download\*" -Recurse -Force -EA SilentlyContinue
Start-Service wuauserv,BITS -EA SilentlyContinue

# ---------- 3. Prefetch / Superfetch leftovers ----------
Remove-Item "$env:SystemRoot\Prefetch\*" -Force -EA SilentlyContinue

# ---------- 4. Logs ----------
wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }
Log "Event log очищен."

# ---------- 5. Hibernation + fast startup ----------
Log "powercfg: hibernation off, hybrid sleep off..."
cmd /c "powercfg /h off" | Out-Null
cmd /c "powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP HYBRIDSLEEP 0" | Out-Null
cmd /c "powercfg /setactive SCHEME_CURRENT" | Out-Null
Remove-Item "C:\hiberfil.sys" -Force -EA SilentlyContinue

# ---------- 6. CompactOS (сильно уменьшает размер, но CPU+ при IO) ----------
Log "CompactOS: compact /EXE (осторожно, влияет на производительность)..."
cmd /c "compact /c /s:C:\Windows /i /exe" | Out-Null
Log "CompactOS запущен (может работать долго)."

# ---------- 7. DISM component cleanup ----------
if (-not $NoDISM) {
    Log "DISM /StartComponentCleanup (долгий)..."
    cmd /c "dism /online /cleanup-image /StartComponentCleanup" | Out-Null
    Log "DISM /ResetBase (откатывает компоненты, нельзя удалить апдейты после)..."
    cmd /c "dism /online /cleanup-image /StartComponentCleanup /ResetBase" | Out-Null
} else { Log "DISM пропущен по флагу." }

# ---------- 8. Pagefile minimum ----------
if ($MinPagefile) {
    Log "Pagefile → 512MB fixed на C:"
    $cs = Get-WmiObject Win32_ComputerSystem
    $os = Get-WmiObject Win32_OperatingSystem
    # отключаем автоматический выбор
    $cs.AutomaticManagedPagefile = $false
    $cs.Put() | Out-Null
    $pf = Get-WmiObject Win32_PageFileSetting -Filter "SettingID='pagefile.sys @ C:'"
    if ($pf) {
        $pf.InitialSize = 512; $pf.MaximumSize = 512; $pf.Put() | Out-Null
    } else {
        Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{Name='C:\pagefile.sys'; InitialSize=512; MaximumSize=512} | Out-Null
    }
}

# ---------- 9. Пакеты Appx «призраки» ----------
Log "Зачистка orphaned Appx-записей через Get-AppxPackage -AllUsers..."
try {
    Get-AppxPackage -AllUsers -EA SilentlyContinue | Where-Object {
        $_.InstallLocation -and -not (Test-Path $_.InstallLocation)
    } | ForEach-Object {
        Log "Orphan removed: $($_.Name)"
        try { Add-AppxPackage -Register -DisableDevelopmentMode "$($_.InstallLocation)\AppXManifest.xml" -EA SilentlyContinue } catch {}
    }
} catch {}

# ---------- 10. Recycle Bin / индекс ----------
cmd /c "rd /s /q C:\`$Recycle.Bin" 2>$null | Out-Null

Log "=== Cleanup: готово. Лог: $log ==="
