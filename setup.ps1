# ============================================
# Автоматическая настройка SSH туннеля + RustDesk
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
Write-Host "  Установка SSH туннеля + RustDesk" -ForegroundColor Cyan
Write-Host "  Пользователь: $userName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function Download-File {
    param([string]$Url, [string]$OutFile)
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        $size = (Get-Item $OutFile).Length
        if ($size -gt 100KB) { return $true }
        return $false
    } catch { return $false }
}

# --- Запросить пароль VPS ---
Write-Host "`nВведи пароль от VPS:" -ForegroundColor Cyan
$vpsPasswordSecure = Read-Host "Пароль VPS" -AsSecureString
$vpsPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($vpsPasswordSecure)
)

# --- ШАГ 1: OpenSSH ---
Write-Host "`n[1/5] Установка OpenSSH..." -ForegroundColor Yellow
if (!(Test-Path $sshExe)) {
    if (Download-File "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip" "C:\OpenSSH.zip") {
        Expand-Archive -Path "C:\OpenSSH.zip" -DestinationPath "C:\OpenSSH" -Force
        powershell.exe -ExecutionPolicy Bypass -File "C:\OpenSSH\OpenSSH-Win64\install-sshd.ps1"
        Write-Host "OpenSSH установлен!" -ForegroundColor Green
    } else { Write-Host "Ошибка!" -ForegroundColor Red; exit 1 }
} else { Write-Host "Уже установлен." -ForegroundColor Green }

$env:PATH += ";C:\OpenSSH\OpenSSH-Win64"
[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\OpenSSH\OpenSSH-Win64", "Machine")

# --- ШАГ 2: SSH сервер ---
Write-Host "`n[2/5] Запуск SSH сервера..." -ForegroundColor Yellow
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue
Write-Host "SSH сервер запущен!" -ForegroundColor Green

# --- ШАГ 3: SSH ключ ---
Write-Host "`n[3/5] Создание SSH ключа..." -ForegroundColor Yellow
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
    Write-Host "Ключ не создался! Выполни вручную:" -ForegroundColor Red
    Write-Host "$keygenExe -t ed25519 -C tunnel-key" -ForegroundColor Yellow
    Read-Host "Нажми Enter когда создашь"
    $pubKey = Get-Content "$keyPath.pub" -ErrorAction SilentlyContinue
}

# --- Добавить ключ на VPS ---
Write-Host "`nДобавляю ключ на VPS..." -ForegroundColor Cyan
try {
    $cmd = "mkdir -p ~/.ssh && echo '$pubKey' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    echo $vpsPassword | & $sshExe -o StrictHostKeyChecking=no -o PasswordAuthentication=yes root@$VPS_IP $cmd 2>$null
    Write-Host "Ключ добавлен!" -ForegroundColor Green
} catch {
    Write-Host "Добавь вручную:" -ForegroundColor Red
    Write-Host "echo `"$pubKey`" >> ~/.ssh/authorized_keys" -ForegroundColor Yellow
    Read-Host "Нажми Enter когда добавишь"
}

# --- Найти свободные порты ---
Write-Host "`nИщу свободные порты на VPS..." -ForegroundColor Cyan

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
Write-Host "SSH порт: $SSH_PORT" -ForegroundColor Green

# --- ШАГ 4: RustDesk ---
Write-Host "`n[4/5] Установка RustDesk..." -ForegroundColor Yellow

$rustdeskInstalled = Test-Path "C:\Program Files\RustDesk\RustDesk.exe"

if (!$rustdeskInstalled) {
    Write-Host "Скачиваю RustDesk с GitHub..." -ForegroundColor Gray
    $rdUrl = "https://github.com/rustdesk/rustdesk/releases/download/1.2.6/rustdesk-1.2.6-x86_64.exe"
    
    if (Download-File $rdUrl "C:\rustdesk_setup.exe") {
        Write-Host "Устанавливаю RustDesk..." -ForegroundColor Gray
        Start-Process "C:\rustdesk_setup.exe" -ArgumentList "--silent-install" -Wait
        Write-Host "RustDesk установлен!" -ForegroundColor Green
    } else {
        Write-Host "Не удалось скачать! Попробую другую версию..." -ForegroundColor Red
        $rdUrl2 = "https://github.com/rustdesk/rustdesk/releases/download/1.2.4/rustdesk-1.2.4-x86_64.exe"
        if (Download-File $rdUrl2 "C:\rustdesk_setup.exe") {
            Start-Process "C:\rustdesk_setup.exe" -ArgumentList "--silent-install" -Wait
            Write-Host "RustDesk установлен!" -ForegroundColor Green
        } else {
            Write-Host "Не удалось установить RustDesk!" -ForegroundColor Red
        }
    }
} else {
    Write-Host "RustDesk уже установлен." -ForegroundColor Green
}

# Запустить RustDesk как службу
$rustdeskExe = "C:\Program Files\RustDesk\RustDesk.exe"
if (Test-Path $rustdeskExe) {
    Start-Process $rustdeskExe -ArgumentList "--install-service" -Wait -ErrorAction SilentlyContinue
    Start-Service "RustDesk" -ErrorAction SilentlyContinue
    Set-Service -Name "RustDesk" -StartupType 'Automatic' -ErrorAction SilentlyContinue
}

# --- ШАГ 5: Туннель ---
Write-Host "`n[5/5] Создание туннеля..." -ForegroundColor Yellow

netsh advfirewall firewall add rule name="SSH-22" protocol=TCP dir=in localport=22 action=allow | Out-Null

Set-Content -Path "C:\ssh_tunnel.bat" -Value ":loop
`"$sshExe`" -N -R ${SSH_PORT}:localhost:22 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes root@$VPS_IP
timeout /t 10
goto loop"

Unregister-ScheduledTask -TaskName "SSH Tunnel" -Confirm:$false -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute "C:\ssh_tunnel.bat"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "SSH Tunnel" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName "SSH Tunnel"
Write-Host "Туннель запущен!" -ForegroundColor Green

# Получить ID RustDesk
Start-Sleep -Seconds 3
$rdId = ""
try {
    $rdId = & $rustdeskExe --get-id 2>$null
} catch {}

# --- ИТОГ ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Всё готово!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "SSH порт туннеля: $SSH_PORT" -ForegroundColor Yellow
if ($rdId) {
    Write-Host "RustDesk ID: $rdId" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Для подключения:" -ForegroundColor Cyan
    Write-Host "1. Установи RustDesk на своём ПК" -ForegroundColor White
    Write-Host "2. Введи ID: $rdId" -ForegroundColor White
    Write-Host "3. Подключись!" -ForegroundColor White
} else {
    Write-Host ""
    Write-Host "Для подключения:" -ForegroundColor Cyan
    Write-Host "1. Установи RustDesk на своём ПК" -ForegroundColor White
    Write-Host "2. На удалённом ПК открой RustDesk и посмотри ID" -ForegroundColor White
    Write-Host "3. Введи этот ID на своём ПК и подключись" -ForegroundColor White
}
