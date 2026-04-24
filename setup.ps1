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
Write-Host "`nВведи пароль от VPS (нужен один раз чтобы добавить ключ):" -ForegroundColor Cyan
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
    Write-Host "Не удалось создать ключ! Выполни вручную:" -ForegroundColor Red
    Write-Host "$keygenExe -t ed25519 -C tunnel-key" -ForegroundColor Yellow
    Write-Host "Потом запусти скрипт снова." -ForegroundColor Yellow
    exit 1
}

# --- Добавить ключ на VPS автоматически ---
Write-Host "`nДобавляю ключ на VPS..." -ForegroundColor Cyan
$env:SSHPASS = $vpsPassword
$keyAdded = $false

try {
    $cmd = "mkdir -p ~/.ssh && echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    echo $vpsPassword | & $sshExe -o StrictHostKeyChecking=no -o PasswordAuthentication=yes root@$VPS_IP $cmd 2>$null
    $keyAdded = $true
    Write-Host "Ключ добавлен на VPS!" -ForegroundColor Green
} catch {}

if (!$keyAdded) {
    Write-Host "Добавь ключ вручную на VPS:" -ForegroundColor Red
    Write-Host "echo `"$pubKey`" >> ~/.ssh/authorized_keys" -ForegroundColor Yellow
    Read-Host "Нажми Enter когда добавишь"
}

# --- Найти свободные порты на VPS ---
Write-Host "`nИщу свободные порты..." -ForegroundColor Cyan

function Get-FreeVpsPort {
    param([int]$StartPort)
    $port = $StartPort
    while ($true) {
        $result = & $sshExe -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$VPS_IP "ss -tlnp 2>/dev/null | grep :$port" 2>$null
        if ([string]::IsNullOrEmpty($result)) { return $port }
        $port++
    }
}

$SSH_PORT = Get-FreeVpsPort -StartPort 2222
$VNC_PORT = Get-FreeVpsPort -StartPort 5900
Write-Host "SSH порт: $SSH_PORT" -ForegroundColor Green
Write-Host "VNC порт: $VNC_PORT" -ForegroundColor Green

# --- ШАГ 4: UltraVNC ---
Write-Host "`n[4/6] Установка UltraVNC..." -ForegroundColor Yellow

$vncInstalled = $false
if (Get-Service "uvnc_service" -ErrorAction SilentlyContinue) { $vncInstalled = $true }
if (Test-Path "C:\Program Files\uvnc bvba\UltraVNC\winvnc.exe") { $vncInstalled = $true }

if (!$vncInstalled) {
    Write-Host "Скачиваю UltraVNC..." -ForegroundColor Gray
    $vncUrls = @(
        "https://www.uvnc.com/component/jdownloads/send/7-ultravnc-1-x-x/864-ultravnc-1-4-0-6-x64-setup.html",
        "https://github.com/ultravnc/UltraVNC/releases/download/V1_4_0_6/UltraVNC_1_4_0_6_X64_Setup.exe"
    )

    $downloaded = $false
    foreach ($url in $vncUrls) {
        Write-Host "Пробую: $url" -ForegroundColor Gray
        if (Download-File $url "C:\uvnc_setup.exe") {
            # Проверить что скачался нормальный файл
            $fileSize = (Get-Item "C:\uvnc_setup.exe").Length
            if ($fileSize -gt 1MB) {
                $downloaded = $true
                break
            }
        }
    }

    if ($downloaded) {
        Write-Host "Устанавливаю UltraVNC..." -ForegroundColor Gray
        Start-Process "C:\uvnc_setup.exe" -ArgumentList "/silent /install" -Wait
        
        # Настроить пароль через реестр
        $vncRegPath = "HKLM:\SOFTWARE\ORL\WinVNC3\Default"
        if (!(Test-Path $vncRegPath)) { New-Item -Path $vncRegPath -Force | Out-Null }
        
        # Включить loopback подключения
        reg add "HKLM\SOFTWARE\ORL\WinVNC3\Default" /v AllowLoopback /t REG_DWORD /d 1 /f | Out-Null
        reg add "HKLM\SOFTWARE\uvnc llc\UltraVNC" /v AllowLoopback /t REG_DWORD /d 1 /f | Out-Null

        Start-Service "uvnc_service" -ErrorAction SilentlyContinue
        Set-Service -Name "uvnc_service" -StartupType 'Automatic' -ErrorAction SilentlyContinue
        Write-Host "UltraVNC установлен!" -ForegroundColor Green
    } else {
        Write-Host "Не удалось скачать UltraVNC автоматически." -ForegroundColor Red
        Write-Host "Скачай вручную: https://uvnc.com/downloads/ultravnc.html" -ForegroundColor Yellow
        Write-Host "Установи UltraVNC 64bit Server и установи пароль 12345678" -ForegroundColor Yellow
        Read-Host "Нажми Enter когда установишь"
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
Write-Host "Для подключения к рабочему столу:" -ForegroundColor Cyan
Write-Host "1. ssh -L ${VNC_PORT}:localhost:${VNC_PORT} root@$VPS_IP" -ForegroundColor White
Write-Host "2. VNC Viewer -> localhost:$VNC_PORT" -ForegroundColor White
Write-Host "3. Пароль VNC: 12345678" -ForegroundColor Yellow
