#!/usr/bin/env bash
# Single-repo state push → branch hermes-state on THIS repo
# Essential files only. Never commits .env (use GitHub Secrets).
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
# Default: same repo that is running the workflow
STATE_REPO="${STATE_REPO:-${GITHUB_REPOSITORY:-azascloud-cell/hermes-lifetime}}"
STATE_BRANCH="${STATE_BRANCH:-hermes-state}"
# Prefer dedicated token, else GITHUB_TOKEN (enough for same public repo)
TOKEN="${STATE_REPO_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"

if [ -z "$TOKEN" ]; then
  echo "ERROR: no token (GITHUB_TOKEN / STATE_REPO_TOKEN)"
  exit 0
fi

if [ ! -d "$HERMES_HOME" ]; then
  echo "ERROR: no HERMES_HOME at $HERMES_HOME"
  exit 0
fi

STAGE="${RUNNER_TEMP:-/tmp}/hermes-state-$$"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cd "$STAGE"

echo "=== Push state → ${STATE_REPO}@${STATE_BRANCH} ==="

# Init orphan branch content
git init -q
git config user.email "hermes-bot@users.noreply.github.com"
git config user.name "Hermes Lifetime"
git checkout -b "$STATE_BRANCH"

mkdir -p .hermes/memories .hermes/skills

copy_if() {
  [ -e "$1" ] || return 0
  mkdir -p "$(dirname "$2")"
  cp -a "$1" "$2"
  echo "  + $1"
}

copy_if "$HERMES_HOME/SOUL.md"      .hermes/SOUL.md
copy_if "$HERMES_HOME/config.yaml"  .hermes/config.yaml
copy_if "$HERMES_HOME/state.db"     .hermes/state.db
copy_if "$HERMES_HOME/state.db-wal" .hermes/state.db-wal
copy_if "$HERMES_HOME/state.db-shm" .hermes/state.db-shm
copy_if "$HERMES_HOME/sessions.json" .hermes/sessions.json

if [ -d "$HERMES_HOME/memories" ]; then
  rsync -a "$HERMES_HOME/memories/" .hermes/memories/
  echo "  + memories/"
fi

# Optional small skills only
if [ -d "$HERMES_HOME/skills" ]; then
  rsync -a --max-size=500k \
    --exclude='node_modules/' --exclude='__pycache__/' --exclude='.git/' \
    "$HERMES_HOME/skills/" .hermes/skills/ 2>/dev/null || true
fi

# NEVER copy .env to public branch
cat > README.md << EOF
# hermes-state branch

Auto snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ)
Contains SOUL, memories, state.db, config — not .env (keys in Actions Secrets).
EOF

SIZE_KB=$(du -sk .hermes 2>/dev/null | cut -f1 || echo 0)
echo "Payload: ${SIZE_KB} KB"
if [ "${SIZE_KB:-0}" -gt 80000 ]; then
  echo "ERROR: payload too large"
  du -sh .hermes/* 2>/dev/null | sort -h | tail -15
  exit 1
fi

git add -A
if git diff --cached --quiet; then
  echo "Nothing to commit"
  exit 0
fi

git commit -m "state $(date -u +%Y-%m-%dT%H:%M:%SZ)"

git remote add origin "https://x-access-token:${TOKEN}@github.com/${STATE_REPO}.git"

set +e
git push -u origin "$STATE_BRANCH" --force 2>/tmp/push.err
RC=$?
set -e

if [ $RC -ne 0 ]; then
  echo "PUSH FAILED:"
  cat /tmp/push.err
  exit 1
fi

echo "OK: ${STATE_REPO}@${STATE_BRANCH}"
[ -f .hermes/state.db ] && ls -lh .hermes/state.db
[ -f .hermes/SOUL.md ] && echo "SOUL: $(wc -c < .hermes/SOUL.md) bytes"
ls -la .hermes/memories/ 2>/dev/null || true
