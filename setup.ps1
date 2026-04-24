# ============================================
# Автоматическая настройка SSH туннеля + VNC
# Запускать от имени Администратора!
# ============================================

$VPS_IP = "217.114.12.59"
$VPS_USER = "root"
$userName = $env:USERNAME
$sshDir = "C:\Users\$userName\.ssh"
$keyPath = "$sshDir\id_ed25519"
$sshExe = "C:\OpenSSH\OpenSSH-Win64\ssh.exe"
$keygenExe = "C:\OpenSSH\OpenSSH-Win64\ssh-keygen.exe"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Установка SSH + VNC туннеля к VPS" -ForegroundColor Cyan
Write-Host "  Пользователь: $userName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function Download-File {
    param([string]$Url, [string]$OutFile)
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        return $true
    } catch { return $false }
}

# --- Выбор порта ---
Write-Host "`nВведи порт (по умолчанию 2224, если занят введи 2225, 2226...):" -ForegroundColor Cyan
$portInput = Read-Host "Порт"
if ([string]::IsNullOrWhiteSpace($portInput)) { $SSH_PORT = 2224 }
else { $SSH_PORT = [int]$portInput }
Write-Host "Порт: $SSH_PORT" -ForegroundColor Green

# --- ШАГ 1: OpenSSH ---
Write-Host "`n[1/6] Установка OpenSSH..." -ForegroundColor Yellow
if (!(Test-Path $sshExe)) {
    if (Download-File "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip" "C:\OpenSSH.zip") {
        Expand-Archive -Path "C:\OpenSSH.zip" -DestinationPath "C:\OpenSSH" -Force
        powershell.exe -ExecutionPolicy Bypass -File "C:\OpenSSH\OpenSSH-Win64\install-sshd.ps1"
        Write-Host "OpenSSH установлен!" -ForegroundColor Green
    } else { Write-Host "Ошибка скачивания!" -ForegroundColor Red; exit 1 }
} else { Write-Host "Уже установлен." -ForegroundColor Green }

$env:PATH += ";C:\OpenSSH\OpenSSH-Win64"
[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\OpenSSH\OpenSSH-Win64", "Machine")

# --- ШАГ 2: SSH сервер ---
Write-Host "`n[2/6] Запуск SSH сервера..." -ForegroundColor Yellow
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
Write-Host "SSH сервер запущен!" -ForegroundColor Green

# --- ШАГ 3: SSH ключ ---
Write-Host "`n[3/6] Создание SSH ключа..." -ForegroundColor Yellow

if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

$keyCreated = Test-Path "$keyPath.pub"

if (!$keyCreated) {
    # Метод 1: через echo передаём пустые ответы
    try {
        $result = echo "" | & $keygenExe -t ed25519 -C "tunnel-key" -f "$keyPath" 2>&1
        $keyCreated = Test-Path "$keyPath.pub"
    } catch {}
}

if (!$keyCreated) {
    # Метод 2: через cmd
    try {
        cmd /c "echo.|$keygenExe -t ed25519 -C tunnel-key -f `"$keyPath`""
        $keyCreated = Test-Path "$keyPath.pub"
    } catch {}
}

if ($keyCreated) {
    $pubKey = Get-Content "$keyPath.pub"
    Write-Host "SSH ключ создан!" -ForegroundColor Green
    Write-Host $pubKey -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  СОЗДАЙ КЛЮЧ ВРУЧНУЮ:" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "1. Выполни эту команду:" -ForegroundColor Yellow
    Write-Host "   $keygenExe -t ed25519 -C tunnel-key" -ForegroundColor White
    Write-Host ""
    Write-Host "2. На все вопросы жми Enter" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "3. Потом выполни:" -ForegroundColor Yellow
    Write-Host "   cat $keyPath.pub" -ForegroundColor White
    Write-Host ""
    Write-Host "4. Скопируй ключ и добавь на VPS:" -ForegroundColor Yellow
    Write-Host "   ssh root@$VPS_IP" -ForegroundColor White
    Write-Host "   echo `"ВАШ_КЛЮЧ`" >> ~/.ssh/authorized_keys" -ForegroundColor White
    Write-Host ""
    Write-Host "5. Запусти туннель:" -ForegroundColor Yellow
    Write-Host "   Start-ScheduledTask -TaskName 'SSH Tunnel'" -ForegroundColor White
    Write-Host ""
    $pubKey = "КЛЮЧ_НЕ_СОЗДАН"
}

# --- ШАГ 4: VNC ---
Write-Host "`n[4/6] Установка VNC..." -ForegroundColor Yellow
$vncInstalled = $false
if (Get-Service "tvnserver" -ErrorAction SilentlyContinue) { $vncInstalled = $true }

if (!$vncInstalled) {
    Write-Host "Скачиваю TightVNC..." -ForegroundColor Gray
    if (Download-File "https://www.tightvnc.com/download/2.8.85/tightvnc-2.8.85-gpl-setup-64bit.msi" "C:\vnc.msi") {
        Start-Process msiexec.exe -ArgumentList "/i C:\vnc.msi /quiet /norestart ADDLOCAL=Server SET_USEVNCAUTHENTICATION=1 VALUE_OF_USEVNCAUTHENTICATION=1 SET_PASSWORD=1 VALUE_OF_PASSWORD=12345678" -Wait
        Start-Service "tvnserver" -ErrorAction SilentlyContinue
        Set-Service -Name "tvnserver" -StartupType 'Automatic' -ErrorAction SilentlyContinue
        Write-Host "VNC установлен! Пароль: 12345678" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "VNC не скачался! Скачай вручную:" -ForegroundColor Red
        Write-Host "https://www.tightvnc.com/download.php" -ForegroundColor White
        Write-Host "Установи TightVNC 64-bit, пароль: 12345678" -ForegroundColor Gray
    }
} else { Write-Host "VNC уже установлен." -ForegroundColor Green }

# --- ШАГ 5: Фаервол ---
Write-Host "`n[5/6] Настройка фаервола..." -ForegroundColor Yellow
netsh advfirewall firewall add rule name="VNC-5900" protocol=TCP dir=in localport=5900 action=allow | Out-Null
netsh advfirewall firewall add rule name="SSH-22" protocol=TCP dir=in localport=22 action=allow | Out-Null
Write-Host "Порты открыты!" -ForegroundColor Green

# --- ШАГ 6: Туннель ---
Write-Host "`n[6/6] Создание туннеля..." -ForegroundColor Yellow

Set-Content -Path "C:\ssh_tunnel.bat" -Value ":loop
`"$sshExe`" -N -R ${SSH_PORT}:localhost:22 -R 5901:localhost:5900 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes root@$VPS_IP
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
Write-Host "  Готово!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
if ($pubKey -ne "КЛЮЧ_НЕ_СОЗДАН") {
    Write-Host ""
    Write-Host "Добавь ключ на VPS командой:" -ForegroundColor Red
    Write-Host "echo `"$pubKey`" >> ~/.ssh/authorized_keys" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Потом запусти туннель:" -ForegroundColor Cyan
    Write-Host "Start-ScheduledTask -TaskName 'SSH Tunnel'" -ForegroundColor White
}
