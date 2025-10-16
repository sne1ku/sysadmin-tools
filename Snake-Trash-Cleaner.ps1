<# 
   Очистка пользовательских корзин на сервере удаленных рабочих столов
   
    Запуск от администратора
     Dry-run: добавьте -WhatIf к Remove-Item для проверки

     Одиночное удаление у одного пользователя:
     # === Настройки ===
$sid = 'S-1-5-21-1234567890-123456789-123456789-1001'   # укажи нужный SID
$archiveRoot = 'C:\RecycleArchives'                     # куда складывать архивы (если нужно)
New-Item -Path $archiveRoot -ItemType Directory -Force | Out-Null

# === Перебор дисков и просмотр содержимого корзины пользователя по SID ===
Get-PSDrive -PSProvider FileSystem | ForEach-Object {
    $root = $_.Root
    $path = Join-Path $root '$Recycle.Bin'
    if (Test-Path $path) {
        $sidPath = Join-Path $path $sid
        if (Test-Path $sidPath) {
            Write-Host "=== Корзина для $sid найдена на диске $root ==="
            
            $files = Get-ChildItem -LiteralPath $sidPath -Force -ErrorAction SilentlyContinue
            if ($files) {
                $files | Select Name,Length,LastWriteTime | Format-Table -AutoSize

                foreach ($file in $files) {
                    # === УДАЛЕНИЕ (раскомментируй при необходимости) ===
                    # Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    # Write-Host "Удалён: $($file.FullName)"

                    # === ПЕРЕНОС В АРХИВ (раскомментируй при необходимости) ===
                    # $dest = Join-Path $archiveRoot ($env:COMPUTERNAME + '_' + $file.Name)
                    # Move-Item -LiteralPath $file.FullName -Destination $dest -Force
                    # Write-Host "Перемещён: $($file.FullName) -> $dest"
                }
            } else {
                Write-Host "Файлы в корзине SID $sid на диске $root не найдены."
            }
        }
    }
}




#>
$results = @()
$drives = Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Root # получаем список корневых точек файловых дисков (например C:\, D:\ и т.д.). Это нужно, чтобы найти $Recycle.Bin на каждом диске.

foreach ($drive in $drives) {
    $recycleRoot = Join-Path $drive '$Recycle.Bin'
    if (Test-Path $recycleRoot) {
        Get-ChildItem -Path $recycleRoot -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $item = $_
            try {
                # Для проверки сначала заменить -Force на -WhatIf
                Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop # -WhatIf
                $results += [pscustomobject]@{Server = $env:COMPUTERNAME; Drive = $drive; SID = $item.Name; Status = 'Deleted'; Path = $item.FullName; Time=(Get-Date)}
            } catch {
                $results += [pscustomobject]@{Server = $env:COMPUTERNAME; Drive = $drive; SID = $item.Name; Status = "Error: $($_.Exception.Message)"; Path = $item.FullName; Time=(Get-Date)}
            }
        }
    }
}

# Показать результат в консоли
$results | Format-Table -AutoSize

# Можно сохранить в CSV
$results | Export-Csv -Path ".\RecycleCleanup_$($env:COMPUTERNAME)_$(Get-Date -Format yyyyMMddHHmmss).csv" -NoTypeInformation
