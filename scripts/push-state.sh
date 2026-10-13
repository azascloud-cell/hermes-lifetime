#!/usr/bin/env bash
# Push essential Hermes state to branch hermes-state (same public repo)
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
STATE_REPO="${STATE_REPO:-${GITHUB_REPOSITORY:-azascloud-cell/hermes-lifetime}}"
STATE_BRANCH="${STATE_BRANCH:-hermes-state}"
TOKEN="${STATE_REPO_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"

if [ -z "$TOKEN" ]; then
  echo "ERROR: no token"; exit 0
fi
if [ ! -d "$HERMES_HOME" ]; then
  echo "ERROR: no HERMES_HOME"; exit 0
fi

STAGE="${RUNNER_TEMP:-/tmp}/hermes-state-$$"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cd "$STAGE"

echo "=== Push state → ${STATE_REPO}@${STATE_BRANCH} ==="
echo "HERMES_HOME listing:"
find "$HERMES_HOME" -maxdepth 3 \( -name 'state.db*' -o -name 'SOUL.md' -o -name 'MEMORY.md' -o -name 'USER.md' -o -name 'sessions.json' -o -name '*.db' \) 2>/dev/null || true

git init -q
git config user.email "hermes-bot@users.noreply.github.com"
git config user.name "Hermes Lifetime"
git checkout -b "$STATE_BRANCH"

mkdir -p .hermes/memories .hermes/skills .hermes/state

copy_if() {
  [ -e "$1" ] || return 0
  mkdir -p "$(dirname "$2")"
  cp -a "$1" "$2"
  echo "  + $1 → $2"
}

copy_if "$HERMES_HOME/SOUL.md"       .hermes/SOUL.md
copy_if "$HERMES_HOME/config.yaml"   .hermes/config.yaml
copy_if "$HERMES_HOME/sessions.json" .hermes/sessions.json

# state.db can live in several places depending on Hermes version
for candidate in \
  "$HERMES_HOME/state.db" \
  "$HERMES_HOME/state/state.db" \
  "$HERMES_HOME/data/state.db" \
  "$HERMES_HOME/gateway/state.db"; do
  if [ -f "$candidate" ]; then
    copy_if "$candidate" .hermes/state.db
    # companion wal/shm next to it
    copy_if "${candidate}-wal" .hermes/state.db-wal
    copy_if "${candidate}-shm" .hermes/state.db-shm
    break
  fi
done

# Any other sqlite under .hermes (session stores)
while IFS= read -r db; do
  base=$(basename "$db")
  [ "$base" = "state.db" ] && continue
  rel="${db#$HERMES_HOME/}"
  copy_if "$db" ".hermes/$rel"
done < <(find "$HERMES_HOME" -name '*.db' -type f 2>/dev/null | head -20)

if [ -d "$HERMES_HOME/memories" ]; then
  rsync -a "$HERMES_HOME/memories/" .hermes/memories/
  echo "  + memories/"
fi

# sessions directory if exists
if [ -d "$HERMES_HOME/sessions" ]; then
  rsync -a --max-size=2m "$HERMES_HOME/sessions/" .hermes/sessions/ 2>/dev/null || true
  echo "  + sessions/"
fi
if [ -d "$HERMES_HOME/state" ]; then
  rsync -a --max-size=20m --exclude='*.sock' --exclude='*.lock' \
    "$HERMES_HOME/state/" .hermes/state/ 2>/dev/null || true
  echo "  + state/"
fi

if [ -d "$HERMES_HOME/skills" ]; then
  rsync -a --max-size=200k \
    --exclude='node_modules/' --exclude='__pycache__/' --exclude='.git/' \
    "$HERMES_HOME/skills/" .hermes/skills/ 2>/dev/null || true
fi

cat > README.md << EOF
# hermes-state
Snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

SIZE_KB=$(du -sk .hermes 2>/dev/null | cut -f1 || echo 0)
echo "Payload: ${SIZE_KB} KB"
if [ "${SIZE_KB:-0}" -gt 100000 ]; then
  echo "ERROR: payload too large"; du -sh .hermes/* 2>/dev/null | sort -h | tail -20; exit 1
fi

# Report what we got
echo "--- packed ---"
[ -f .hermes/state.db ] && ls -lh .hermes/state.db || echo "WARN: state.db STILL MISSING"
[ -f .hermes/SOUL.md ] && echo "SOUL ok"
ls -la .hermes/memories/ 2>/dev/null || true

git add -A
if git diff --cached --quiet; then
  echo "Nothing to commit"; exit 0
fi
git commit -m "state $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git remote add origin "https://x-access-token:${TOKEN}@github.com/${STATE_REPO}.git"

set +e
git push -u origin "$STATE_BRANCH" --force 2>/tmp/push.err
RC=$?
set -e
if [ $RC -ne 0 ]; then
  echo "PUSH FAILED:"; cat /tmp/push.err; exit 1
fi
echo "OK: ${STATE_REPO}@${STATE_BRANCH}"
