# Windows 11 Wezograph — ультралёгкая сборка через Sysprep + Audit Mode

Сборка Windows 11, вычищенная до минимума: удалены почти все UWP-приложения, телеметрия,
Cortana, Edge (по возможности), OneDrive, куча служб и фоновых задач. Опционально — полное
удаление Microsoft Defender. Всё делается **в режиме аудита** до генерации образа, чтобы
`generalize` + `OOBE` дали чистую систему без «призраков» удалённых пакетов.

> ⚠️ **Дисклеймер.** Удаление Defender и глубокая зачистка снижают безопасность и могут
> ломать Windows Update, Store, поиск и обновления больших релизов (23H2→24H2 и т.п.).
> Делайте это на своей машине и только если понимаете последствия. Сначала — тестовая ВМ!

---

## Структура репозитория

```
.
├── README.md                  ← эта инструкция
├── scripts/
│   ├── 00-audit-entry.ps1     ← быстрый вход в audit mode из работающей системы
│   ├── 10-remove-apps.ps1     ← удаление UWP/Provisioned пакетов (много и агрессивно)
│   ├── 11-strip-telemetry.ps1 ← телеметрия, Tasks, DiagTrack, CustomerExperience
│   ├── 12-disable-services.ps1← отключение служб (по желанию / на автозапуск / на удаление)
│   ├── 13-remove-defender.ps1 ← ⚠ полное удаление Microsoft Defender (+ Tuning/FLRM)
│   ├── 14-cleanup.ps1         ← Temp, DISM component cleanup, hiberfil, pagefile-минимум
│   └── 99-sysprep-finalize.ps1← финальный прогон всех шагов + sysprep /generalize /oobe /shutdown
├── autounattend.xml           ← OOBE-ответ: автологин админом, skip-проверки, без MS-аккаунта
└── UnattendAudit.xml          ← Sysprep-ответ: /generalize + немедленный вход в Audit Mode
```

---

## Пошаговая инструкция

### Шаг 0. Подготовка

1. ISO Windows 11 (любая редакция, Pro рекомендуется).
2. Тестовая ВМ (VirtualBox/VMware/Hyper-V) или второй диск. **Не делайте это на рабочем ПК без бэкапа.**
3. На целевой машине включите в BIOS/UEFI возможность запуска скриптов не нужно —
   политики обхода подписи задаются сами в скриптах (`Set-ExecutionPolicy Bypass -Scope Process`).

### Шаг 1. Установка Windows до экрана OOBE

1. Загрузитесь с ISO, разбейте/отформатируйте диск, установите систему.
2. Когда начнётся OOBE («Давайте укажем имя вашего устройства») — **не проходите её**.
   Нажмите **Ctrl+Shift+F3**. Система установит встроенного Administrator и перезагрузится
   прямо в **режим аудита** (Audit Mode — рабочий стол без оболочки OOBE).

   Альтернатива из уже установленной системы: запустить `scripts\00-audit-entry.ps1`
   от администратора (сделает `sysprep /audit /reboot`).

### Шаг 2. Скрипты в режиме аудита

В режиме аудита откройте PowerShell **от имени Администратора** и выполните по порядку
(можно скопировать папку `scripts` на рабочую машину заранее, например на отдельный раздел
или USB):

```powershell
# 1. Удалить приложения (куча UWP + provisioned, чтобы не ставились заново)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\10-remove-apps.ps1

# 2. Вырезать телеметрию и планировщик
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\11-strip-telemetry.ps1

# 3. Отключить службы (выберите режим: -Remove часть можно реально удалить)
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\12-disable-services.ps1

# 4. ⚠ Удалить Microsoft Defender (опционально, но "по-настоящему")
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\13-remove-defender.ps1

# 5. Мусор, DISM-зачистка компонентного стора, hiberfil и т.д.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\14-cleanup.ps1
```

Или всё одной командой с финальным Sysprep-выключением:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\99-sysprep-finalize.ps1
```

> Если `13-remove-defender.ps1` требует перезагрузку посреди процесса — перезагрузитесь,
> снова зайдите в аудит (он активен до первого `/generalize`) и доведите остальные шаги.

### Шаг 3. Финализация — Sysprep Generalize

После того как всё вычищено:

```cmd
C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /unattend:C:\wezo\autounattend.xml
```

(если XML лежит в корне `C:\`, поправьте путь; либо используйте `UnattendAudit.xml` — см. ниже)

Что делает:
- `/generalize` — сбрасывает SID, драйверную базу, удаляет остатки учётных записей и
  «призрачные» записи удалённых AppX-пакетов из профиля;
- `/oobe` — при следующем включении покажет чистый OOBE (или пройдёт его по autounattend);
- `/shutdown` — выключит машину, готовую к клонированию/захвату образа.

### Шаг 4. (Опция) Клонирование вместо OOBE

Если нужен образ для развертывания: после `/generalize /oobe /shutdown` включите ВМ и
снимите `.wim`/`.vhdx`, либо сразу примените `autounattend.xml` с `AutoLogon`, чтобы
первый вход был автоматическим.

### Шаг 5. Первый вход

После OOBE система загрузится в профиль Administrator (или созданный вами аккаунт).
Проверьте:

```powershell
Get-AppxPackage -AllUsers | Measure-Object      # пакетов должно быть мало
Get-Service WinDefend, WdNisSvc, SecurityHealthService -ErrorAction SilentlyContinue  # пусто, если Defender удалён
Get-ScheduledTask -TaskPath "\Microsoft\Windows\Application Experience\*" | ? State -ne Disabled
```

---

## Создание ISO из готовой сборки

После того как система вычищена и сделан `sysprep /generalize /oobe /shutdown` (Шаг 3),
можно упаковать её в установочный ISO, чтобы ставить на другие машины без ручной зачистки.

### Вариант А. Автоустановочный ISO «как у Microsoft» (через install.wim)

**1. Снимите образ диска в `.wim`:**

Загрузитесь с WinPE (или второй ВМ с DISM), подключите диск собранной системы
(например, `D:`) и выполните:

```cmd
DISM /Capture-Image /ImageFile:C:\wezo\install.wim /CaptureDir:D:\ ^
     /Name:"Windows 11 Wezograph" /Description:"Sysprep generalizied" /Compress:max
```

> Диск должен быть именно после `/generalize /shutdown`, иначе образ не развернётся
> корректно на другом железе.

**2. Соберите папку дистрибутива:**

Распакуйте оригинальный ISO Windows 11 в папку, например `C:\wezo\iso\`, и замените
в ней файл образа:

```
C:\wezo\iso\
├── boot\               ← из оригинального ISO (не трогать)
├── efi\                ← из оригинального ISO
├── sources\
│   ├── install.wim     ← ВАШ новый install.wim (заменяет оригинальный)
│   └── ...             ← остальное из оригинального ISO
├── autounattend.xml    ← ваш ответный файл (в корне — подхватывается автоматически)
└── setup.exe, ...
```

Опционально обновите индекс образов (если меняли метаданные):

```cmd
DISM /Get-WimInfo /WimFile:C:\wezo\iso\sources\install.wim
```

**3. Создайте загрузочный ISO.** Один из способов:

*oscdimg (официальный способ, из Windows ADK):*

```cmd
"C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe" ^
  -m -o -u2 -udfver102 ^
  -bootdata:2#p0,e,bC:\wezo\iso\boot\etfsboot.com#pEF,e,bC:\wezo\iso\efi\microsoft\boot\efisys.bin ^
  C:\wezo\iso C:\wezo\Wezograph_Win11.iso
```

*Aльтернатива без ADK — AnyBurn или ImgBurn:* «Create ISO image from folder» → укажите
папку `C:\wezo\iso`, в настройках задайте загрузочный бинарник `boot\etfsboot.com`
(ImgBurn: Options → Boot Disc → Load file). Для записи на флешку вместо ISO можно
использовать **Ventoy** (скопируйте туда файлы дистрибутива + autounattend.xml) или
**Rufus** (режим DD-образа/ISO оригинала, затем подмените install.wim на флешке).

Готово: `Wezograph_Win11.iso` ставится на любую машину — при наличии `autounattend.xml`
в корне установка пройдёт автоматически до готового рабочего стола.

### Вариант Б. ISO с автоустановкой + развёртыванием образа (unattended DISM-Install)

Если хотите, чтобы ISO сам форматировал диск и применял ваш `.wim` без участия человека,
добавьте в `autounattend.xml` секции `DiskConfiguration` + `ImageInstall` (указывает на
`sources\install.wim`, индекс 1) — тогда достаточно обычного UEFI-bootable ISO из Варианта А.

### Вариант В. Быстрый ISO из готовой ВМ (клон-диск → ISO)

Для переноса целиком (со всеми настройками, но **без generalize так делать нельзя!**):

1. После `sysprep /generalize /oobe /shutdown` сконвертируйте диск ВМ в RAW:
   `qemu-img convert -O raw disk.vhdx disk.raw` (или снимок VirtualBox → VDI→RAW).
2. ISO с Linux live-флешки снимите образ: `dd if=disk.raw of=image.img`.
3. Такой носитель клонируется на диск утилитой dd/Ventoy — это уже не установщик Windows,
   а «дубликат» системы. Подходит только для одинакового железа/UEFI-настроек.

### Проверка ISO перед распространением

- Смонтируйте ISO и убедитесь, что `sources\install.wim` весит ожидаемо и содержит нужный индекс.
- Загрузитесь с ISO в тестовой ВМ (Secure Boot может требовать подпись — отключите или
  используйте стандартный boot-код от оригинального ISO, он подписан).
- После установки проверьте `Get-AppxPackage -AllUsers` — пакеты не должны «воскреснуть».

### Частые проблемы

| Симптом | Причина / решение |
|---|---|
| Установка зависает на «Подготовка файлов» | install.wim снят до `/generalize`; снимайте образ только после generalize+shutdown |
| BSOD INACCESSIBLE_BOOT_DEVICE при установке | в ISO попал old-style BIOS boot без нужных драйверов; добавьте драйверы в wim: `DISM /Add-Driver` |
| ISO не грузится с UEFI | неверные флаги oscdimg; используйте команду выше с `-bootdata:2#p0...#pEF...` |
| OOBE всё равно спрашивает аккаунт MS | `autounattend.xml` лежит не в корне ISO или не в `C:\Panels\Unattend\` на целевом диске |

---

## Вариант с автоматическим входом в Audit Mode после generalize

Если хотите, чтобы после `sysprep /generalize` машина сама возвращалась в аудит
(например, для двухпроходной сборки), используйте `UnattendAudit.xml`:

```cmd
C:\Windows\System32\Sysprep\sysprep.exe /generalize /audit /reboot /unattend:C:\wezo\UnattendAudit.xml
```

---

## Что именно удаляется (краткий список)

**Приложения:** Copilot, Clipchamp, Teams, TikTok/Instagram/Spotify и прочие «спонсоры»,
Bing-клиенты, News, Weather, Xbox (GameBar остаётся функциональной, но отключается),
YourPhone, Maps, Sound Recorder, Media Player (Legacy), 3D Builder/Paint, Power Automate,
Solitaire, Sticky Notes, Wallet, Alarms (опционально), Delve Forms, To Do, Notepad (→ замена
на классический/Win32, опция `-KeepNotepad`), Whiteboard, Feedback Hub, Get Help,
Microsoft Start, Family, RetailDemo, и все Provisioned-варианты этих пакетов.

**Телеметрия:** DiagTrack, ConnectedUserExperiencesCsp, dmwappushservice, ScheduledTelemetry,
CustomerExperienceImprovementProgram, все `\Application Experience*`, `Data Integrity`,
`SoftwareProtectionPlatform`-фоновые tasks, Unified Telemetry Platform tasks, NPS, PIE,
CEIP, SmartScreen-политики (опция), DiLink/Link-to-Phone tasks.

**Службы (disabled/deleted):** PrintNotify (опц.), Fax, Touch Keyboard (опц.), WerMgr,
WMPNetworkSvc, DevicesFlowUserSvc, OneSyncSvc, MessagingService, CDPUserSvc, PimIndexMaint,
SharedAccess, RemoteRegistry (опц.), WSearch (опц.), Spooler (опц., `-KeepPrint`),
SysMain, WMPNetworkSvc, wbengine (опц.) и десятки других — см. массивы в скрипте.

**Defender:** WinDefend, WdNisSvc, wscsvc(SecurityHealthService), Sense, TamperProtection,
плюс удаление Appx `Microsoft.Windows.SecHealthUI`, вырезка фильтров `WdFilter/WdNisDrv/WdBoot`
через bcdedit-безопасный путь (rename-подход на next boot), удаление групповых политик
Defender-планировщика.

---

## Известные ограничения

- `Appx`-пакеты, защищённые GVLK/System-компонентами (Cred Dialog UI, ShellExperiencePack
  частично), могут не удаляться — скрипты логируют пропуски и идут дальше.
- После удаления Defender крупные feature-обновления могут откатиться или потребовать
  вернуть Defender обратно перед обновлением.
- Windows Store после полной зачистки может требовать `wsreset`/переустановки метаданных —
  в скриптах есть опция `-KeepStore`.
- Sysprep **нельзя** запускать больше 3 раз на одной установке без обхода `SkipRearm` —
  для итеративной сборки снимайте снапшот ВМ после каждого успешного generalize.
