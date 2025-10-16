<#
.SYNOPSIS
    Snake-VM-Backup-Master.ps1
    Резервное копирование виртуальной машины Hyper-V с архивацией и очисткой старых бекапов.

.DESCRIPTION
    Скрипт выполняет:
    1. Удаление бекапов старше N дней
    2. Экспорт указанной ВМ в локальную папку
    3. Архивацию экспорта с помощью 7-Zip (с удалением исходных файлов)
    4. Очистку временных данных

.REQUIREMENTS
    - Windows с ролью\службой Hyper-V
    - PowerShell с модулем Hyper-V (обычно входит в состав Windows)
    - 7-Zip, установленный по пути C:\Program Files\7-Zip\7z.exe
    - Запуск от имени администратора (для экспорта ВМ и доступа к системным ресурсам)

.NOTES
    Автор: Sneiku
    Версия: 1.1
    Дата: 2025-08-17
#>

# === КОНФИГУРАЦИЯ (измените под свои нужды) ===
$LogPath           = "C:\Logs\BackupLog.txt"          # Путь к файлу лога
$BackupRoot        = "D:\BAK"                         # Корневая папка для бекапов
$VMName            = "JIRA"                           # Имя виртуальной машины в Hyper-V
$RetentionDays     = 10                               # Сколько дней хранить бекапы
$SevenZipPath      = "C:\Program Files\7-Zip\7z.exe"  # Путь к 7-Zip
$ArchivePrefix     = "VM_SRV-JIRA"                    # Префикс имени архива
# ===============================================

# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Log {
    param([string]$Message, [string]$ForegroundColor = "White")
    Write-Host "[ $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ] $Message" -ForegroundColor $ForegroundColor
}
# ===============================

# === НАЧАЛО ВЫПОЛНЕНИЯ ===
Start-Transcript -Path $LogPath -Append -ErrorAction SilentlyContinue | Out-Null

try {
    # Проверка прав администратора
    if (-not (Test-IsAdmin)) {
        throw "Скрипт должен запускаться от имени администратора."
    }

    Write-Log "Начало выполнения скрипта резервного копирования ВМ '$VMName'."

    # === Проверка и создание каталогов ===
    if (-not (Test-Path -Path $BackupRoot)) {
        Write-Log "Каталог '$BackupRoot' не существует. Создаю автоматически." -ForegroundColor Cyan
        New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    } else {
        Write-Log "Каталог '$BackupRoot' найден."
    }

    # === Проверка наличия 7-Zip ===
    if (-not (Test-Path -Path $SevenZipPath)) {
        throw "7-Zip не найден по пути: $SevenZipPath. Убедитесь, что он установлен."
    }
    Write-Log "7-Zip обнаружен: $SevenZipPath"

    # === Удаление старых бекапов ===
    Write-Log "Поиск бекапов старше $RetentionDays дней в '$BackupRoot'..."
    $oldBackups = Get-ChildItem -Path $BackupRoot -File -Filter "*.zip" -ErrorAction SilentlyContinue |
                  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) }

    if ($oldBackups) {
        foreach ($backup in $oldBackups) {
            Remove-Item -Path $backup.FullName -Force
            Write-Log "Удалён старый бекап: $($backup.Name)"
        }
    } else {
        Write-Log "Старых бекапов не найдено."
    }

    # === Проверка существования ВМ ===
    Write-Log "Проверка наличия виртуальной машины '$VMName'..."
    $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
    if (-not $vm) {
        throw "Виртуальная машина '$VMName' не найдена на этом хосте Hyper-V."
    }

    if ($vm.State -ne 'Off') {
        Write-Log "ВМ '$VMName' находится в состоянии '$($vm.State)'. Экспорт возможен только из состояния 'Off'." -ForegroundColor Yellow
        throw "Остановите виртуальную машину вручную перед запуском бекапа."
    }
    Write-Log "ВМ '$VMName' найдена и выключена. Готов к экспорту."

    # === Экспорт ВМ ===
    $exportPath = Join-Path $BackupRoot ("srv-" + $VMName.ToLower())
    Write-Log "Экспорт ВМ в: $exportPath"

    # Удалим старую папку экспорта, если она осталась
    if (Test-Path -Path $exportPath) {
        Write-Log "Обнаружена старая папка экспорта. Удаляю: $exportPath" -ForegroundColor Yellow
        Remove-Item -Path $exportPath -Recurse -Force
    }

    Export-VM -Name $VMName -Path $BackupRoot
    if (-not (Test-Path -Path $exportPath)) {
        throw "Экспорт завершился, но папка '$exportPath' не создана. Проверьте права и место на диске."
    }
    Write-Log "Экспорт ВМ завершён."

    # === Архивация ===
    $curdate = Get-Date -Format "yyyyMMdd"
    $archivePath = Join-Path $BackupRoot "${curdate}_${ArchivePrefix}.zip"
    Write-Log "Архивация в: $archivePath" -ForegroundColor Cyan

    & $SevenZipPath a -tzip -ssw -mx1 -r0 -sdel $archivePath $exportPath
    if ($LASTEXITCODE -ne 0) {
        throw "Ошибка при архивации с помощью 7-Zip. Код ошибки: $LASTEXITCODE"
    }

    # Проверим, что архив создан
    if (-not (Test-Path -Path $archivePath)) {
        throw "Архив не создан, несмотря на успешный код возврата 7-Zip."
    }

    $archiveSize = [Math]::Round((Get-Item $archivePath).Length / 1GB, 2)
    Write-Log "Архивация завершена. Размер: ${archiveSize} ГБ"

    # === Финальная очистка (на всякий случай) ===
    if (Test-Path -Path $exportPath) {
        Write-Log "Удаление временной папки экспорта: $exportPath"
        Remove-Item -Path $exportPath -Recurse -Force
    }

    Write-Log "✅ Резервное копирование успешно завершено." -ForegroundColor Green

} catch {
    Write-Log "❌ КРИТИЧЕСКАЯ ОШИБКА: $($_.Exception.Message)" -ForegroundColor Red
    throw  # Пробрасываем ошибку, чтобы Stop-Transcript сработал в finally
} finally {
    try {
        Stop-Transcript | Out-Null
    } catch {
        # Игнорируем ошибку, если транскрибирование не было начато
    }
}
