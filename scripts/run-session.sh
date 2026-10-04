#!/usr/bin/env bash
set -euo pipefail

export HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
export BACKUP_ROOT="${BACKUP_ROOT:-${GITHUB_WORKSPACE:-.}/hermes-backup}"
export PYTHONUNBUFFERED=1
export DASHBOARD_PORT="${DASHBOARD_PORT:-9119}"
export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"

SESSION_MINUTES=350
BACKUP_EVERY_SEC=300
LOG_DIR="/tmp/hermes-logs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$LOG_DIR" "$HERMES_HOME" "$BACKUP_ROOT"

DASH_PID=""
TUNNEL_PID=""
GATEWAY_PID=""
CURRENT_TUNNEL_URL=""
LAST_BACKUP_TS=0

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_DIR/session.log"; }

persist() {
  if [ -x "$SCRIPT_DIR/persist-hermes.sh" ]; then
    bash "$SCRIPT_DIR/persist-hermes.sh" "$@" 2>&1 | tee -a "$LOG_DIR/session.log" || true
  else
    log "WARN: persist-hermes.sh not found"
  fi
}

install_hermes() {
  if command -v hermes >/dev/null 2>&1; then
    log "Hermes already present: $(hermes --version 2>/dev/null || echo ok)"
    return
  fi
  log "Installing Hermes Agent..."
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
  export PATH="$HOME/.local/bin:$HOME/.hermes/bin:$PATH"
  source "$HOME/.bashrc" 2>/dev/null || true
  if ! command -v hermes >/dev/null 2>&1; then
    log "ERROR: hermes not found after install"
    exit 1
  fi
  log "Hermes installed"
}

write_env() {
  log "Merging secrets into $HERMES_HOME/.env (dashboard keys preserved)..."
  ENV_FILE="$HERMES_HOME/.env"
  touch "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  TMP_MERGE="$(mktemp)"
  if [ -s "$ENV_FILE" ]; then
    grep -v '^#' "$ENV_FILE" | grep -v '^[[:space:]]*$' > "$TMP_MERGE" || true
  else
    : > "$TMP_MERGE"
  fi
  upsert() {
    local key="$1" val="$2"
    [ -z "$val" ] && return 0
    if grep -q "^${key}=" "$TMP_MERGE" 2>/dev/null; then
      sed -i "s|^${key}=.*|${key}=${val}|" "$TMP_MERGE"
    else
      echo "${key}=${val}" >> "$TMP_MERGE"
    fi
  }
  upsert XKIRO_API_KEY "${XKIRO_API_KEY:-}"
  upsert OLLAMA_API_KEY "${OLLAMA_API_KEY:-}"
  upsert GROQ_API_KEY "${GROQ_API_KEY:-}"
  upsert OPENAI_API_KEY "${OPENAI_API_KEY:-}"
  upsert OPENCODE_ZEN_API_KEY "${OPENCODE_ZEN_API_KEY:-}"
  upsert AISUBSCRIPTION_API_KEY "${AISUBSCRIPTION_API_KEY:-}"
  upsert MIAROUTER_API_KEY "${MIAROUTER_API_KEY:-}"
  upsert TELEGRAM_BOT_TOKEN "${TELEGRAM_BOT_TOKEN:-}"
  upsert TELEGRAM_ALLOWED_USERS "${TELEGRAM_ALLOWED_USERS:-}"
  upsert FIGMA_PAT "${FIGMA_PAT:-}"
  upsert GOOGLE_API_KEY "${GOOGLE_API_KEY:-}"
  upsert GEMINI_API_KEY "${GEMINI_API_KEY:-}"
  upsert GEMINI_BASE_URL "${GEMINI_BASE_URL:-https://generativelanguage.googleapis.com/v1beta/}"
  upsert OLLAMA_BASE_URL "${OLLAMA_BASE_URL:-https://ollama.com/v1}"
  upsert DASHBOARD_PORT "${DASHBOARD_PORT:-9119}"
  upsert HERMES_HOME "$HERMES_HOME"
  upsert PYTHONUNBUFFERED "1"
  local auth_user="${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:-}"
  local auth_pass="${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:-}"
  local auth_secret="${HERMES_DASHBOARD_BASIC_AUTH_SECRET:-}"
  if [ -z "$auth_secret" ] || [ "$auth_secret" = "change-me-to-random-32chars-min" ]; then
    if grep -q "^HERMES_DASHBOARD_BASIC_AUTH_SECRET=." "$TMP_MERGE" 2>/dev/null; then
      log "Kept existing HERMES_DASHBOARD_BASIC_AUTH_SECRET"
    else
      auth_secret="$(openssl rand -base64 48 | tr -d '\n')"
      upsert HERMES_DASHBOARD_BASIC_AUTH_SECRET "$auth_secret"
      log "Generated new HERMES_DASHBOARD_BASIC_AUTH_SECRET"
    fi
  else
    upsert HERMES_DASHBOARD_BASIC_AUTH_SECRET "$auth_secret"
  fi
  [ -n "$auth_user" ] && upsert HERMES_DASHBOARD_BASIC_AUTH_USERNAME "$auth_user"
  [ -n "$auth_pass" ] && upsert HERMES_DASHBOARD_BASIC_AUTH_PASSWORD "$auth_pass"
  if ! grep -q "^HERMES_DASHBOARD_BASIC_AUTH_USERNAME=" "$TMP_MERGE" 2>/dev/null; then
    upsert HERMES_DASHBOARD_BASIC_AUTH_USERNAME "admin"
  fi
  { echo "# Merged by Nero Lifetime"; cat "$TMP_MERGE"; } > "$ENV_FILE"
  rm -f "$TMP_MERGE"
  chmod 600 "$ENV_FILE"
  set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
  for k in XKIRO_API_KEY GROQ_API_KEY AISUBSCRIPTION_API_KEY MIAROUTER_API_KEY OLLAMA_API_KEY GOOGLE_API_KEY GEMINI_API_KEY TELEGRAM_BOT_TOKEN; do
    v="${!k:-}"
    if [ -n "$v" ]; then log "KEY $k = SET (len=${#v})"; else log "KEY $k = EMPTY"; fi
  done
  log ".env merged"
}

write_config() {
  if [ -f "config.yaml" ] && [ ! -f "$HERMES_HOME/config.yaml" ]; then
    cp -f config.yaml "$HERMES_HOME/config.yaml"
    log "config.yaml installed (first time)"
  elif [ -f "$HERMES_HOME/config.yaml" ]; then
    log "config.yaml present — merging providers (base_url fix)"
  else
    mkdir -p "$HERMES_HOME"
    echo "model: {}" > "$HERMES_HOME/config.yaml"
    log "created minimal config.yaml"
  fi
  MERGE_SCRIPT=""
  if [ -f "$SCRIPT_DIR/merge_providers.py" ]; then MERGE_SCRIPT="$SCRIPT_DIR/merge_providers.py"
  elif [ -f "scripts/merge_providers.py" ]; then MERGE_SCRIPT="scripts/merge_providers.py"; fi
  if [ -n "$MERGE_SCRIPT" ]; then
    python3 "$MERGE_SCRIPT" 2>&1 | while IFS= read -r line; do log "merge: $line"; done || log "WARN: merge_providers failed"
  else
    log "WARN: merge_providers.py not found"
  fi
}

dashboard_alive() {
  local code; code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:$DASHBOARD_PORT" 2>/dev/null || echo "000")
  echo "$code" | grep -qE '200|401|302|403'
}
tunnel_alive() { [ -n "${TUNNEL_PID}" ] && kill -0 "$TUNNEL_PID" 2>/dev/null; }
gateway_alive() { [ -n "${GATEWAY_PID}" ] && kill -0 "$GATEWAY_PID" 2>/dev/null; }

start_dashboard_only() {
  log "Starting Dashboard on :${DASHBOARD_PORT}..."
  pkill -f "hermes dashboard" 2>/dev/null || true; sleep 1
  export HERMES_DASHBOARD_BASIC_AUTH_USERNAME="${HERMES_DASHBOARD_BASIC_AUTH_USERNAME:-admin}"
  export HERMES_DASHBOARD_BASIC_AUTH_PASSWORD="${HERMES_DASHBOARD_BASIC_AUTH_PASSWORD:-}"
  export HERMES_DASHBOARD_BASIC_AUTH_SECRET="${HERMES_DASHBOARD_BASIC_AUTH_SECRET:-}"
  nohup hermes dashboard --host 0.0.0.0 --port "$DASHBOARD_PORT" --no-open > "$LOG_DIR/dashboard.log" 2>&1 &
  DASH_PID=$!; log "Dashboard PID=$DASH_PID"
  for i in $(seq 1 40); do dashboard_alive && { log "Dashboard ready"; return 0; }; sleep 1; done
  log "WARN: Dashboard not ready"; tail -20 "$LOG_DIR/dashboard.log" || true
}

start_tunnel_only() {
  CLOUDFLARED="/tmp/cloudflared"
  if [ ! -x "$CLOUDFLARED" ]; then
    curl -sL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" -o "$CLOUDFLARED"
    chmod +x "$CLOUDFLARED"
  fi
  pkill -f cloudflared 2>/dev/null || true; sleep 1
  nohup "$CLOUDFLARED" tunnel --url "http://127.0.0.1:$DASHBOARD_PORT" > "$LOG_DIR/tunnel.log" 2>&1 &
  TUNNEL_PID=$!; log "Tunnel PID=$TUNNEL_PID"
  CURRENT_TUNNEL_URL=""
  for i in $(seq 1 40); do
    if [ -f "$LOG_DIR/tunnel.log" ] && grep -q "trycloudflare.com" "$LOG_DIR/tunnel.log"; then
      CURRENT_TUNNEL_URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/tunnel.log" | head -1 || true)
      if [ -n "$CURRENT_TUNNEL_URL" ]; then
        log ">>> DASHBOARD URL: $CURRENT_TUNNEL_URL"
        echo "$CURRENT_TUNNEL_URL" > /tmp/dashboard-url.txt
        TUNNEL_HOST=$(echo "$CURRENT_TUNNEL_URL" | sed -E 's|https?://||' | cut -d/ -f1)
        export HERMES_DASHBOARD_ALLOWED_HOSTS="$TUNNEL_HOST,localhost,127.0.0.1"
        export HERMES_DASHBOARD_PUBLIC_URL="$CURRENT_TUNNEL_URL"
        { echo "HERMES_DASHBOARD_ALLOWED_HOSTS=${HERMES_DASHBOARD_ALLOWED_HOSTS}"; echo "HERMES_DASHBOARD_PUBLIC_URL=${HERMES_DASHBOARD_PUBLIC_URL}"; } >> "$HERMES_HOME/.env"
        start_dashboard_only; return 0
      fi
    fi
    sleep 1
  done
  log "WARN: no tunnel URL"
}

notify_telegram() {
  [ -z "$CURRENT_TUNNEL_URL" ] && return
  [ -z "${TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${TELEGRAM_ALLOWED_USERS:-}" ] && return
  CHAT_ID=$(echo "$TELEGRAM_ALLOWED_USERS" | cut -d',' -f1 | tr -d ' ')
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=🚀 Hermes Lifetime LIVE\n${CURRENT_TUNNEL_URL}\n_Nero_" \
    -d "parse_mode=Markdown" >/dev/null 2>&1 || true
}

start_dashboard_and_tunnel() {
  start_dashboard_only; start_tunnel_only; notify_telegram
}

start_gateway() {
  log "Starting Gateway..."
  pkill -f "hermes gateway" 2>/dev/null || true; sleep 1
  nohup hermes gateway > "$LOG_DIR/gateway.log" 2>&1 &
  GATEWAY_PID=$!; log "Gateway PID=$GATEWAY_PID"; sleep 6
  if ! gateway_alive; then log "ERROR: Gateway failed"; tail -80 "$LOG_DIR/gateway.log" || true; exit 1; fi
  log "Gateway running"
}

maybe_backup() {
  local now; now=$(date +%s)
  if [ $((now - LAST_BACKUP_TS)) -ge "$BACKUP_EVERY_SEC" ]; then persist backup; LAST_BACKUP_TS=$now; fi
}

cleanup() {
  log "Cleanup — final backup..."
  persist backup
  pkill -f "hermes gateway" 2>/dev/null || true
  pkill -f "hermes dashboard" 2>/dev/null || true
  pkill -f cloudflared 2>/dev/null || true
  log "=== Session END ==="
}
trap cleanup EXIT INT TERM

main() {
  log "=== Nero Hermes Lifetime START ==="
  persist restore; persist status
  install_hermes; write_env; write_config
  [ ! -s "$HERMES_HOME/SOUL.md" ] && persist restore
  start_dashboard_and_tunnel; start_gateway
  persist backup; LAST_BACKUP_TS=$(date +%s)
  END_TIME=$(( $(date +%s) + SESSION_MINUTES * 60 ))
  log "Session until $(date -d "@$END_TIME" 2>/dev/null || date)"
  while [ $(date +%s) -lt $END_TIME ]; do
    sleep 90
    gateway_alive || { log "Gateway gone — restart"; start_gateway; }
    dashboard_alive || { log "Dashboard down — restart"; start_dashboard_only; }
    tunnel_alive || { log "Tunnel gone — restart"; start_tunnel_only; notify_telegram; }
    maybe_backup
  done
  log "Session time reached."
}
main
