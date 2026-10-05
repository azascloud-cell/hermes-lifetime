# Dual-repo setup (public runner + private state)

## Repos
| Repo | Visibility | Role |
|------|------------|------|
| `azascloud-cell/hermes-lifetime` | **Public** | Workflow + scripts (unlimited Actions minutes) |
| `azascloud-cell/model-hermes` | **Private** | SOUL, memory, session DB, config, **.env** |

## One-time: PAT for private repo

1. GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)**
2. Generate new token (classic)
   - Note: `hermes-state-pat`
   - Expiration: 90 days or no expiration
   - Scope: **`repo`** (full control of private repositories)
3. Copy the token

## One-time: secret di repo PUBLIC

Repo **hermes-lifetime** → Settings → Secrets and variables → Actions → New repository secret:

| Name | Value |
|------|--------|
| `STATE_REPO_TOKEN` | PAT yang baru dibuat |

Opsional (tetap berguna):
- `OLLAMA_API_KEY`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`, dashboard auth, …

Key miarouter / aisub boleh **hanya di dashboard** — akan ikut tersimpan di `.env` private repo.

## Flow
1. Job start → clone `model-hermes` → restore `~/.hermes` (termasuk `.env`)
2. Merge providers (base_url)
3. Hermes jalan
4. Job end → push penuh `~/.hermes` (termasuk `.env`) ke `model-hermes`

## Cek sukses di log Actions
- `Restored from private repo azascloud-cell/model-hermes`
- `.env keys present: ... MIAROUTER_API_KEY AISUBSCRIPTION_API_KEY ...`
- `Pushed full state (incl .env) to azascloud-cell/model-hermes`
- `Providers registered: ... miarouter ... aisub-gemma`
