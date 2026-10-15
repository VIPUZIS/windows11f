# =====================================================================
# 00-audit-entry.ps1 — вход в режим аудита из уже установленной системы
# Windows 11 Wezograph build
# Запускать: от имени Администратора
# =====================================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'

Write-Host "[Wezograph] Вход в Audit Mode (sysprep /audit /reboot)..." -ForegroundColor Cyan

$sysprep = "$env:SystemRoot\System32\Sysprep\sysprep.exe"
if (-not (Test-Path $sysprep)) {
    Write-Error "Sysprep не найден: $sysprep"
    exit 1
}

# /audit — перезагрузка в режим аудита под встроенным Administrator
# /generalize НЕ делаем — это потом, на финальном шаге.
Start-Process -FilePath $sysprep -ArgumentList '/audit','/reboot' -Wait

Write-Host "[Wezograph] Машина уходит в reboot в Audit Mode." -ForegroundColor Green
