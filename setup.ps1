# ============================================
# Автоматическая настройка SSH туннеля + VNC
# Запускать от имени Администратора!
# ============================================

$VPS_IP = "217.114.12.59"
$VPS_USER = "root"
$SSH_PORT = "2224"
$VNC_PORT = "5900"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Установка SSH + VNC туннеля к VPS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# --- ШАГ 1: Установка OpenSSH ---
Write-Host "`n[1/6] Установка OpenSSH..." -ForegroundColor Yellow

if (!(Test-Path "C:\OpenSSH\OpenSSH-Win64\ssh.exe")) {
    Write-Host "Скачиваю OpenSSH с GitHub..." -ForegroundColor Gray
    Invoke-WebRequest -Uri "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip" -OutFile "C:\OpenSSH.zip"
    Expand-Archive -Path "C:\OpenSSH.zip" -DestinationPath "C:\OpenSSH" -Force
    powershell.exe -ExecutionPolicy Bypass -File "C:\OpenSSH\OpenSSH-Win64\install-sshd.ps1"
    Write-Host "OpenSSH установлен!" -ForegroundColor Green
} else {
    Write-Host "OpenSSH уже установлен, пропускаю." -ForegroundColor Green
}

# --- ШАГ 2: Запуск SSH ---
Write-Host "`n[2/6] Запуск SSH сервера..." -ForegroundColor Yellow
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
Write-Host "SSH сервер запущен!" -ForegroundColor Green

# --- ШАГ 3: Создание SSH ключа ---
Write-Host "`n[3/6] Создание SSH ключа..." -ForegroundColor Yellow
$keyPath = "$env:USERPROFILE\.ssh\id_ed25519"
if (!(Test-Path $keyPath)) {
    ssh-keygen -t ed25519 -C "tunnel-key" -f $keyPath -N '""'
    Write-Host "SSH ключ создан!" -ForegroundColor Green
} else {
    Write-Host "SSH ключ уже существует, пропускаю." -ForegroundColor Green
}

$pubKey = Get-Content "$keyPath.pub"
Write-Host "`nТвой публичный ключ:" -ForegroundColor Cyan
Write-Host $pubKey -ForegroundColor White

# --- ШАГ 4: Установка VNC (TightVNC) ---
Write-Host "`n[4/6] Установка TightVNC..." -ForegroundColor Yellow

if (!(Test-Path "C:\Program Files\TightVNC\tvnserver.exe")) {
    Write-Host "Скачиваю TightVNC..." -ForegroundColor Gray
    Invoke-WebRequest -Uri "https://www.tightvnc.com/download/2.8.85/tightvnc-2.8.85-gpl-setup-64bit.msi" -OutFile "C:\tightvnc.msi"
    
    # Установка в тихом режиме с паролем 12345678
    Start-Process msiexec.exe -ArgumentList '/i C:\tightvnc.msi /quiet /norestart ADDLOCAL=Server SET_USEVNCAUTHENTICATION=1 VALUE_OF_USEVNCAUTHENTICATION=1 SET_PASSWORD=1 VALUE_OF_PASSWORD=12345678' -Wait
    Write-Host "TightVNC установлен! Пароль: 12345678" -ForegroundColor Green
} else {
    Write-Host "TightVNC уже установлен, пропускаю." -ForegroundColor Green
}

# Запустить VNC сервер
Start-Service tvnserver -ErrorAction SilentlyContinue
Set-Service -Name tvnserver -StartupType 'Automatic' -ErrorAction SilentlyContinue

# --- ШАГ 5: Открыть порты в фаерволе ---
Write-Host "`n[5/6] Настройка фаервола..." -ForegroundColor Yellow
netsh advfirewall firewall add rule name="VNC" protocol=TCP dir=in localport=5900 action=allow | Out-Null
netsh advfirewall firewall add rule name="SSH" protocol=TCP dir=in localport=22 action=allow | Out-Null
Write-Host "Порты открыты!" -ForegroundColor Green

# --- ШАГ 6: Создание туннеля ---
Write-Host "`n[6/6] Создание SSH туннеля..." -ForegroundColor Yellow

Set-Content -Path "C:\ssh_tunnel.bat" -Value @"
:loop
ssh -N -R ${SSH_PORT}:localhost:22 -R 5901:localhost:5900 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes ${VPS_USER}@${VPS_IP}
timeout /t 10
goto loop
"@

$action = New-ScheduledTaskAction -Execute "C:\ssh_tunnel.bat"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "SSH Tunnel" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null

Write-Host "Туннель настроен!" -ForegroundColor Green

# --- ИТОГ ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Установка завершена!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "ВАЖНО: Добавь этот ключ на VPS вручную:" -ForegroundColor Red
Write-Host $pubKey -ForegroundColor Yellow
Write-Host ""
Write-Host "Команда для VPS:" -ForegroundColor Cyan
Write-Host "echo `"$pubKey`" >> ~/.ssh/authorized_keys" -ForegroundColor White
Write-Host ""
Write-Host "После добавления ключа запусти туннель:" -ForegroundColor Cyan
Write-Host "Start-ScheduledTask -TaskName 'SSH Tunnel'" -ForegroundColor White
Write-Host ""
Write-Host "Подключение к VNC с твоего ПК:" -ForegroundColor Cyan
Write-Host "ssh -L 5901:localhost:5901 root@$VPS_IP" -ForegroundColor White
Write-Host "Затем открой VNC клиент и подключись к localhost:5901" -ForegroundColor White
Write-Host "Пароль VNC: 12345678" -ForegroundColor Yellow