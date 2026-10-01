# Hermes Lifetime — Nero Power

**Hermes Agent** berjalan 24/7 di **GitHub Actions** (public repo = no hard limit minutes).

Setiap sesi hidup **5 jam 50 menit**, lalu otomatis restart. Dashboard bisa diakses lewat Cloudflare Tunnel (link dikirim ke Telegram setiap kali start).

Lebih powerful daripada container Pterodactyl terbatas — runner GitHub punya resource lebih besar & bebas.

---

## Fitur

- Lifetime loop (self-trigger + schedule safety-net)
- Dashboard + Basic Auth
- Cloudflare Quick Tunnel (URL baru tiap sesi, dikirim ke Telegram)
- State (memory, sessions, skills) di-persist lewat Actions Cache
- Config & provider kamu (xkiro, groq, aisub, miarouter, gemini, dll)

---

## Setup Cepat (1x saja)

### 1. Masukkan Secrets

Pergi ke: **Settings → Secrets and variables → Actions → New repository secret**

Isi semua yang ada di file `.env` lama kamu:

| Secret Name | Wajib | Keterangan |
|-------------|-------|----------|
| `TELEGRAM_BOT_TOKEN` | ✅ | Token bot dari BotFather |
| `TELEGRAM_ALLOWED_USERS` | ✅ | User ID kamu (7699507804) |
| `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` | ✅ | biasanya `admin` |
| `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` | ✅ | password dashboard |
| `HERMES_DASHBOARD_BASIC_AUTH_SECRET` | ✅ | string random panjang |
| `XKIRO_API_KEY` | ✅ | |
| `AISUBSCRIPTION_API_KEY` | ✅ | |
| `MIAROUTER_API_KEY` | ✅ | |
| `GOOGLE_API_KEY` / `GEMINI_API_KEY` | ✅ | |
| `FIGMA_PAT` | optional | |
| `GROQ_API_KEY` | optional | |
| `OLLAMA_API_KEY` | optional | |

### 2. Jalankan Pertama Kali

1. Buka tab **Actions**
2. Pilih workflow **Hermes Lifetime**
3. Klik **Run workflow** → **Run workflow**

Tunggu beberapa menit (install Hermes + tunnel).

Bot Telegram kamu akan menerima pesan berisi **link dashboard**.

### 3. Selesai

Setiap sesi akan otomatis memicu sesi berikutnya. Safety net cron juga jalan setiap 6 jam.

---

## Akses Dashboard

- Link dikirim otomatis ke Telegram setiap restart
- Login pakai username/password yang kamu set di secrets
- Port internal: 9119

---

## Catatan Penting

- Repo **public** → GitHub Actions minutes gratis & generous
- Jangan commit file `.env` (sudah di-gitignore)
- State di-cache antar job. Kalau cache hilang, memory/session mulai fresh (tapi config tetap)
- Kalau mau stop total: disable workflow di tab Actions

---

Dibangun oleh **Nero** — Script Architect for Pterodactyl & beyond.
