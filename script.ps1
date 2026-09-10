#Requires -RunAsAdministrator

# Cek apakah sudah berjalan sebagai Admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-NOT $isAdmin) {
    Write-Host "[!] Membutuhkan akses Administrator..." -ForegroundColor Yellow
    # Restart script dengan hak admin
    Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"" -Verb RunAs
    exit
}

# Path ke folder script (agar path file main.py terbaca dengan benar)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mainPyPath = Join-Path $scriptDir "main.py"

# 1. Kunci Layar (Lock Screen) agar browser tidak terganggu
Write-Host "[*] Mengunci Layar..." -ForegroundColor Cyan
Start-Sleep -Seconds 1
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $true, $true)

# 2. Jalankan main.py dengan Console Host agar log terlihat
Write-Host "[*] Menjalankan main.py..." -ForegroundColor Green
Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", "& { python `"$mainPyPath`"; Read-Host 'Tekan Enter untuk lanjut setelah selesai' }" -WindowStyle Maximized


NoTrack AI — https://notrack.ai/
