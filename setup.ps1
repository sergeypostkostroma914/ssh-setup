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

# --- Запросить пароль VPS ---
Write-Host "`nВведи пароль от VPS (он нужен один раз чтобы добавить ключ):" -ForegroundColor Cyan
$vpsPasswordSecure = Read-Host "Пароль VPS" -AsSecureString
$vpsPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($vpsPasswordSecure)
)

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

# Установить sshpass для автоматического ввода пароля
$sshpassUrl = "https://github.com/dtulyashov/sshpass-win/releases/download/v1.0/sshpass.exe"
if (!(Test-Path "C:\OpenSSH\OpenSSH-Win64\sshpass.exe")) {
    Download-File $sshpassUrl "C:\OpenSSH\OpenSSH-Win64\sshpass.exe" | Out-Null
}

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
    try {
        echo "" | & $keygenExe -t ed25519 -C "tunnel-key" -f "$keyPath" 2>&1 | Out-Null
        $keyCreated = Test-Path "$keyPath.pub"
    } catch {}
}
if (!$keyCreated) {
    try {
        cmd /c "echo.|$keygenExe -t ed25519 -C tunnel-key -f `"$keyPath`"" | Out-Null
        $keyCreated = Test-Path "$keyPath.pub"
    } catch {}
}

if ($keyCreated) {
    $pubKey = Get-Content "$keyPath.pub"
    Write-Host "SSH ключ создан!" -ForegroundColor Green
} else {
    Write-Host "Не удалось создать ключ автоматически." -ForegroundColor Red
    Write-Host "Выполни вручную: $keygenExe -t ed25519 -C tunnel-key" -ForegroundColor Yellow
    Write-Host "Потом запусти скрипт снова." -ForegroundColor Yellow
    exit 1
}

# --- Автоматически добавить ключ на VPS ---
Write-Host "`nДобавляю ключ на VPS автоматически..." -ForegroundColor Cyan

# Установить plink если есть, иначе используем встроенный способ
$env:SSHPASS = $vpsPassword

# Попробуем через sshpass
$sshpass = "C:\OpenSSH\OpenSSH-Win64\sshpass.exe"
$keyAdded = $false

if (Test-Path $sshpass) {
    try {
        & $sshpass -e $sshExe -o StrictHostKeyChecking=no root@$VPS_IP "echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        $keyAdded = $true
        Write-Host "Ключ добавлен на VPS!" -ForegroundColor Green
    } catch {}
}

if (!$keyAdded) {
    # Попробуем через PowerShell SSH с паролем через stdin
    try {
        $cmd = "echo '$pubKey' >> ~/.ssh/authorized_keys"
        echo $vpsPassword | & $sshExe -o StrictHostKeyChecking=no -o PasswordAuthentication=yes root@$VPS_IP $cmd
        $keyAdded = $true
        Write-Host "Ключ добавлен на VPS!" -ForegroundColor Green
    } catch {}
}

if (!$keyAdded) {
    Write-Host ""
    Write-Host "Не удалось добавить ключ автоматически." -ForegroundColor Red
    Write-Host "Добавь вручную — зайди на VPS и выполни:" -ForegroundColor Yellow
    Write-Host "echo `"$pubKey`" >> ~/.ssh/authorized_keys" -ForegroundColor White
    Write-Host ""
    Read-Host "Нажми Enter когда добавишь ключ на VPS"
}

# --- Найти свободные порты на VPS ---
Write-Host "`nИщу свободные порты на VPS..." -ForegroundColor Cyan

function Get-FreeVpsPort {
    param([int]$StartPort)
    $port = $StartPort
    while ($true) {
        $result = & $sshExe -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$VPS_IP "ss -tlnp 2>/dev/null | grep :$port" 2>$null
        if ([string]::IsNullOrEmpty($result)) {
            return $port
        }
        $port++
    }
}

$SSH_PORT = Get-FreeVpsPort -StartPort 2222
$VNC_PORT = Get-FreeVpsPort -StartPort 5900
Write-Host "SSH порт: $SSH_PORT" -ForegroundColor Green
Write-Host "VNC порт: $VNC_PORT" -ForegroundColor Green

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
        Write-Host "VNC не скачался! Скачай вручную: https://www.tightvnc.com/download.php" -ForegroundColor Red
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
`"$sshExe`" -N -R ${SSH_PORT}:localhost:22 -R ${VNC_PORT}:localhost:5900 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes root@$VPS_IP
timeout /t 10
goto loop"

Unregister-ScheduledTask -TaskName "SSH Tunnel" -Confirm:$false -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute "C:\ssh_tunnel.bat"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "SSH Tunnel" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null

# Запустить туннель сразу
Start-ScheduledTask -TaskName "SSH Tunnel"

Write-Host "Туннель запущен!" -ForegroundColor Green

# --- ИТОГ ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Всё готово! ПК подключён к VPS!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Порты этого ПК:" -ForegroundColor Cyan
Write-Host "  SSH: $SSH_PORT" -ForegroundColor Yellow
Write-Host "  VNC: $VNC_PORT" -ForegroundColor Yellow
Write-Host ""
Write-Host "Для подключения к рабочему столу с твоего ПК:" -ForegroundColor Cyan
Write-Host "1. ssh -L ${VNC_PORT}:localhost:${VNC_PORT} root@$VPS_IP" -ForegroundColor White
Write-Host "2. VNC Viewer -> localhost:$VNC_PORT" -ForegroundColor White
Write-Host "3. Пароль VNC: 12345678" -ForegroundColor Yellow
