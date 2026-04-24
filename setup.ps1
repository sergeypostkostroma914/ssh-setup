# ============================================
# Автоматическая настройка SSH туннеля + VNC
# Запускать от имени Администратора!
# ============================================

$VPS_IP = "217.114.12.59"
$VPS_USER = "root"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Установка SSH + VNC туннеля к VPS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# --- Функция: скачать файл ---
function Download-File {
    param([string]$Url, [string]$OutFile)
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

# --- Выбор порта ---
Write-Host "`nВведи порт для SSH туннеля (по умолчанию 2224)." -ForegroundColor Cyan
Write-Host "Если этот порт уже занят другим ПК — введи другой (например 2225, 2226...)" -ForegroundColor Gray
$portInput = Read-Host "Порт"
if ([string]::IsNullOrWhiteSpace($portInput)) {
    $SSH_PORT = 2224
} else {
    $SSH_PORT = [int]$portInput
}
Write-Host "Выбран порт: $SSH_PORT" -ForegroundColor Green

# --- ШАГ 1: Установка OpenSSH ---
Write-Host "`n[1/6] Установка OpenSSH..." -ForegroundColor Yellow

if (!(Test-Path "C:\OpenSSH\OpenSSH-Win64\ssh.exe")) {
    Write-Host "Скачиваю OpenSSH с GitHub..." -ForegroundColor Gray
    $downloaded = Download-File "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip" "C:\OpenSSH.zip"
    if ($downloaded) {
        Expand-Archive -Path "C:\OpenSSH.zip" -DestinationPath "C:\OpenSSH" -Force
        powershell.exe -ExecutionPolicy Bypass -File "C:\OpenSSH\OpenSSH-Win64\install-sshd.ps1"
        Write-Host "OpenSSH установлен!" -ForegroundColor Green
    } else {
        Write-Host "Ошибка скачивания OpenSSH!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "OpenSSH уже установлен." -ForegroundColor Green
}

# Добавить OpenSSH в PATH
$env:PATH += ";C:\OpenSSH\OpenSSH-Win64"
[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\OpenSSH\OpenSSH-Win64", "Machine")

# --- ШАГ 2: Запуск SSH ---
Write-Host "`n[2/6] Запуск SSH сервера..." -ForegroundColor Yellow
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
Write-Host "SSH сервер запущен!" -ForegroundColor Green

# --- ШАГ 3: Создание SSH ключа ---
Write-Host "`n[3/6] Создание SSH ключа..." -ForegroundColor Yellow
$sshDir = "$env:USERPROFILE\.ssh"
$keyPath = "$sshDir\id_ed25519"

if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

if (!(Test-Path $keyPath)) {
    Push-Location $sshDir
    & "C:\OpenSSH\OpenSSH-Win64\ssh-keygen.exe" -t ed25519 -C "tunnel-key" -N "" -f "$keyPath"
    Pop-Location
}

if (Test-Path "$keyPath.pub") {
    $pubKey = Get-Content "$keyPath.pub"
    Write-Host "SSH ключ создан!" -ForegroundColor Green
} else {
    Write-Host "Ошибка создания ключа!" -ForegroundColor Red
    $pubKey = "КЛЮЧ_НЕ_СОЗДАН"
}

# --- ШАГ 4: Установка TigerVNC ---
Write-Host "`n[4/6] Установка TigerVNC..." -ForegroundColor Yellow

$vncInstalled = $false
if (Test-Path "C:\Program Files\TigerVNC\winvnc4.exe") { $vncInstalled = $true }
if (Get-Service "winvnc4" -ErrorAction SilentlyContinue) { $vncInstalled = $true }

if (!$vncInstalled) {
    Write-Host "Скачиваю TigerVNC..." -ForegroundColor Gray

    $vncUrls = @(
        "https://github.com/TigerVNC/tigervnc/releases/download/v1.13.1/tigervnc64-1.13.1.exe",
        "https://sourceforge.net/projects/tigervnc/files/stable/1.13.1/tigervnc64-1.13.1.exe/download"
    )

    $downloaded = $false
    foreach ($url in $vncUrls) {
        Write-Host "Пробую: $url" -ForegroundColor Gray
        if (Download-File $url "C:\tigervnc.exe") {
            $downloaded = $true
            break
        }
    }

    if ($downloaded) {
        Start-Process "C:\tigervnc.exe" -ArgumentList "/silent /install" -Wait
        Write-Host "TigerVNC установлен!" -ForegroundColor Green
        Start-Service "winvnc4" -ErrorAction SilentlyContinue
        Set-Service -Name "winvnc4" -StartupType 'Automatic' -ErrorAction SilentlyContinue
    } else {
        Write-Host "Не удалось скачать TigerVNC. Пропускаю..." -ForegroundColor Red
    }
} else {
    Write-Host "VNC уже установлен." -ForegroundColor Green
}

# --- ШАГ 5: Открыть порты ---
Write-Host "`n[5/6] Настройка фаервола..." -ForegroundColor Yellow
netsh advfirewall firewall add rule name="VNC-5900" protocol=TCP dir=in localport=5900 action=allow | Out-Null
netsh advfirewall firewall add rule name="SSH-22" protocol=TCP dir=in localport=22 action=allow | Out-Null
Write-Host "Порты открыты!" -ForegroundColor Green

# --- ШАГ 6: Создание туннеля ---
Write-Host "`n[6/6] Создание SSH туннеля..." -ForegroundColor Yellow

$sshExe = "C:\OpenSSH\OpenSSH-Win64\ssh.exe"

Set-Content -Path "C:\ssh_tunnel.bat" -Value ":loop
`"$sshExe`" -N -R ${SSH_PORT}:localhost:22 -R 5901:localhost:5900 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes root@217.114.12.59
timeout /t 10
goto loop"

Unregister-ScheduledTask -TaskName "SSH Tunnel" -Confirm:$false -ErrorAction SilentlyContinue

$action = New-ScheduledTaskAction -Execute "C:\ssh_tunnel.bat"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "SSH Tunnel" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null

Write-Host "Туннель настроен!" -ForegroundColor Green

# --- ИТОГ ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Установка завершена!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "ВАЖНО: Добавь этот ключ на VPS:" -ForegroundColor Red
Write-Host $pubKey -ForegroundColor Yellow
Write-Host ""
Write-Host "Команда для VPS:" -ForegroundColor Cyan
Write-Host "echo `"$pubKey`" >> ~/.ssh/authorized_keys" -ForegroundColor White
Write-Host ""
Write-Host "После добавления ключа запусти туннель:" -ForegroundColor Cyan
Write-Host "Start-ScheduledTask -TaskName 'SSH Tunnel'" -ForegroundColor White
Write-Host ""
Write-Host "Подключение к VNC с твоего ПК:" -ForegroundColor Cyan
Write-Host "1. ssh -L 5901:localhost:5901 root@217.114.12.59" -ForegroundColor White
Write-Host "2. Открой VNC Viewer -> localhost:5901" -ForegroundColor White
Write-Host "3. Пароль VNC: 12345678" -ForegroundColor Yellow
Write-Host "SSH порт туннеля: $SSH_PORT" -ForegroundColor Cyan
