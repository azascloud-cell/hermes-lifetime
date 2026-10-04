#!/usr/bin/env bash
# ============================================================
# Nero | Hermes GHA Persist
# Backup & Restore SOUL.md, MEMORY, USER, state.db, skills
# ============================================================
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
BACKUP_ROOT="${BACKUP_ROOT:-${GITHUB_WORKSPACE:-.}/hermes-backup}"
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)

log() { echo "[persist] $(date -u +%H:%M:%S) $*"; }

ensure_dirs() {
  mkdir -p "$HERMES_HOME"/{memories,skills,state-snapshots}
  mkdir -p "$BACKUP_ROOT"/{hermes,memories,skills,snapshots}
}

restore() {
  ensure_dirs
  log "Restoring from $BACKUP_ROOT → $HERMES_HOME"

  if [ -d "$BACKUP_ROOT/hermes" ] && [ "$(ls -A "$BACKUP_ROOT/hermes" 2>/dev/null)" ]; then
    rsync -a \
      --exclude='*.tmp' --exclude='*.lock' --exclude='.env' \
      "$BACKUP_ROOT/hermes/" "$HERMES_HOME/" || true
    log "Full tree restored"
  else
    for f in SOUL.md config.yaml state.db state.db-wal state.db-shm; do
      [ -f "$BACKUP_ROOT/$f" ] && cp -a "$BACKUP_ROOT/$f" "$HERMES_HOME/$f" && log "Restored $f" || true
    done
    [ -d "$BACKUP_ROOT/memories" ] && rsync -a "$BACKUP_ROOT/memories/" "$HERMES_HOME/memories/" && log "Restored memories/" || true
    [ -d "$BACKUP_ROOT/skills" ] && rsync -a "$BACKUP_ROOT/skills/" "$HERMES_HOME/skills/" && log "Restored skills/" || true
  fi

  # Identity safety net
  if [ ! -s "$HERMES_HOME/SOUL.md" ]; then
    log "WARNING: SOUL.md missing — writing minimal identity"
    cat > "$HERMES_HOME/SOUL.md" << 'SOUL'
# Hermes Identity (Nero GHA Persist)

You are Hermes, a persistent AI agent on GitHub Actions.
You remember the user across restarts (SOUL.md + MEMORY.md + USER.md + state.db are restored).
Speak in the language the user uses. Never claim you have no memory unless restore failed.
SOUL
  fi

  mkdir -p "$HERMES_HOME/memories"
  [ -s "$HERMES_HOME/memories/MEMORY.md" ] || echo "# Agent Memory" > "$HERMES_HOME/memories/MEMORY.md"
  [ -s "$HERMES_HOME/memories/USER.md" ] || echo "# User Profile" > "$HERMES_HOME/memories/USER.md"

  log "Restore done"
  ls -la "$HERMES_HOME" 2>/dev/null | head -20 || true
  echo "--- memories ---"
  ls -la "$HERMES_HOME/memories" 2>/dev/null || true
  if [ -f "$HERMES_HOME/SOUL.md" ]; then
    echo "--- SOUL.md (first 8 lines) ---"
    head -8 "$HERMES_HOME/SOUL.md"
  fi
}

backup() {
  ensure_dirs
  log "Backing up $HERMES_HOME → $BACKUP_ROOT"

  if command -v sqlite3 >/dev/null 2>&1 && [ -f "$HERMES_HOME/state.db" ]; then
    sqlite3 "$HERMES_HOME/state.db" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
  fi

  mkdir -p "$BACKUP_ROOT/hermes"
  rsync -a \
    --exclude='*.tmp' --exclude='*.lock' --exclude='cache/' --exclude='__pycache__/' --exclude='.env' \
    "$HERMES_HOME/" "$BACKUP_ROOT/hermes/" || true

  for f in SOUL.md config.yaml state.db state.db-wal state.db-shm; do
    [ -f "$HERMES_HOME/$f" ] && cp -a "$HERMES_HOME/$f" "$BACKUP_ROOT/" || true
  done
  [ -d "$HERMES_HOME/memories" ] && rsync -a "$HERMES_HOME/memories/" "$BACKUP_ROOT/memories/" || true
  [ -d "$HERMES_HOME/skills" ] && rsync -a "$HERMES_HOME/skills/" "$BACKUP_ROOT/skills/" || true

  SNAP="$BACKUP_ROOT/snapshots/$TIMESTAMP"
  mkdir -p "$SNAP"
  rsync -a "$BACKUP_ROOT/hermes/" "$SNAP/" 2>/dev/null || true
  ls -1dt "$BACKUP_ROOT/snapshots/"*/ 2>/dev/null | tail -n +6 | xargs -r rm -rf

  log "Backup done ($(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1))"
}

status() {
  echo "=== Hermes Persist Status ==="
  echo "HERMES_HOME=$HERMES_HOME"
  echo "BACKUP_ROOT=$BACKUP_ROOT"
  echo
  echo "-- SOUL.md --"
  if [ -s "$HERMES_HOME/SOUL.md" ]; then head -6 "$HERMES_HOME/SOUL.md"; else echo "(missing)"; fi
  echo
  echo "-- memories --"
  ls -la "$HERMES_HOME/memories/" 2>/dev/null || echo "(none)"
  echo
  echo "-- state.db --"
  if [ -f "$HERMES_HOME/state.db" ]; then
    ls -lh "$HERMES_HOME/state.db"*
    command -v sqlite3 >/dev/null 2>&1 && sqlite3 "$HERMES_HOME/state.db" "SELECT COUNT(*) AS sessions FROM sessions;" 2>/dev/null || true
  else
    echo "(no state.db)"
  fi
}

case "${1:-}" in
  restore) restore ;;
  backup)  backup  ;;
  status)  status  ;;
  *) echo "Usage: $0 {restore|backup|status}"; exit 1 ;;
esac
