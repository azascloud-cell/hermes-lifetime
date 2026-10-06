#!/usr/bin/env bash
# Push ONLY essential Hermes state to private STATE_REPO
# Do NOT push tools/, hermes-agent install, caches (too large → push fails)
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
STATE_REPO="${STATE_REPO:-azascloud-cell/model-hermes}"
STATE_BRANCH="${STATE_BRANCH:-main}"
STATE_REPO_TOKEN="${STATE_REPO_TOKEN:-}"

if [ -z "$STATE_REPO_TOKEN" ]; then
  echo "ERROR: STATE_REPO_TOKEN empty — skip push"
  exit 0
fi

if [ ! -d "$HERMES_HOME" ]; then
  echo "ERROR: HERMES_HOME missing: $HERMES_HOME"
  exit 0
fi

STAGE="${RUNNER_TEMP:-/tmp}/hermes-state-push-$$"
rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "Pushing ESSENTIAL state only → ${STATE_REPO} (${STATE_BRANCH})"
echo "HERMES_HOME=$HERMES_HOME"

set +e
git clone --depth 1 --branch "$STATE_BRANCH" \
  "https://x-access-token:${STATE_REPO_TOKEN}@github.com/${STATE_REPO}.git" \
  "$STAGE" 2>/tmp/push-clone.err
RC=$?
set -e

if [ $RC -ne 0 ] || [ ! -d "$STAGE/.git" ]; then
  echo "Clone failed, init fresh:"
  cat /tmp/push-clone.err 2>/dev/null || true
  rm -rf "$STAGE"
  mkdir -p "$STAGE"
  cd "$STAGE"
  git init -b "$STATE_BRANCH"
  git remote add origin "https://x-access-token:${STATE_REPO_TOKEN}@github.com/${STATE_REPO}.git"
else
  cd "$STAGE"
fi

git config user.email "hermes-lifetime[bot]@users.noreply.github.com"
git config user.name "Hermes Lifetime Bot"

# Wipe previous staged content layout
rm -rf .hermes
mkdir -p .hermes/memories .hermes/skills .hermes/state-snapshots

# --- ONLY what we need to restore identity + session + keys ---
copy_if() {
  local src="$1" dst="$2"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
    echo "  + $src"
  fi
}

copy_if "$HERMES_HOME/SOUL.md"        .hermes/SOUL.md
copy_if "$HERMES_HOME/config.yaml"    .hermes/config.yaml
copy_if "$HERMES_HOME/.env"           .hermes/.env
copy_if "$HERMES_HOME/state.db"       .hermes/state.db
copy_if "$HERMES_HOME/state.db-wal"   .hermes/state.db-wal
copy_if "$HERMES_HOME/state.db-shm"   .hermes/state.db-shm

# memories (MEMORY.md, USER.md, etc.)
if [ -d "$HERMES_HOME/memories" ]; then
  rsync -a "$HERMES_HOME/memories/" .hermes/memories/
  echo "  + memories/ ($(find .hermes/memories -type f | wc -l) files)"
fi

# user skills only (not whole tools tree)
if [ -d "$HERMES_HOME/skills" ]; then
  rsync -a \
    --exclude='*/node_modules/' \
    --exclude='*/__pycache__/' \
    --exclude='*/.git/' \
    "$HERMES_HOME/skills/" .hermes/skills/ 2>/dev/null || true
  echo "  + skills/"
fi

# sessions json if present
copy_if "$HERMES_HOME/sessions.json" .hermes/sessions.json

# Explicitly DO NOT copy:
# tools/  hermes-agent/  cache/  node/  nvm/  large installs

cat > README.md << 'EOF'
# Hermes private state store

Essential state only (SOUL, memories, state.db, config, .env).
Updated by hermes-lifetime public runner. Keep private.
EOF

# Safety: refuse if somehow huge
SIZE_KB=$(du -sk .hermes 2>/dev/null | cut -f1)
echo "State payload: ${SIZE_KB} KB"
if [ "${SIZE_KB:-0}" -gt 150000 ]; then
  echo "ERROR: payload > 150MB — abort push (something wrong included)"
  du -sh .hermes/* 2>/dev/null | sort -h | tail -20
  exit 1
fi

git add -A

if git diff --cached --quiet; then
  echo "Nothing new to commit"
  exit 0
fi

git commit -m "state $(date -u +%Y-%m-%dT%H:%M:%SZ)"

set +e
git push -u origin "HEAD:${STATE_BRANCH}" --force 2>/tmp/push.err
PUSH_RC=$?
set -e

if [ $PUSH_RC -ne 0 ]; then
  echo "PUSH FAILED:"
  cat /tmp/push.err || true
  exit 1
fi

echo "OK: pushed to ${STATE_REPO}@${STATE_BRANCH}"
if [ -f .hermes/.env ]; then
  echo "Saved .env keys:"
  grep -E '^[A-Z0-9_]+=' .hermes/.env | cut -d= -f1
fi
[ -f .hermes/state.db ] && ls -lh .hermes/state.db
[ -f .hermes/SOUL.md ] && echo "SOUL.md: $(wc -c < .hermes/SOUL.md) bytes"
[ -d .hermes/memories ] && ls -la .hermes/memories/
