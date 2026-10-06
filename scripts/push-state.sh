#!/usr/bin/env bash
# Push ~/.hermes (incl .env) to private STATE_REPO
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

echo "Pushing state → ${STATE_REPO} (${STATE_BRANCH})"
echo "HERMES_HOME=$HERMES_HOME"
ls -la "$HERMES_HOME" | head -20 || true

# Clone existing or init fresh
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

# Sync full hermes home INCLUDING .env
mkdir -p .hermes
rsync -a --delete \
  --exclude='cache/' \
  --exclude='__pycache__/' \
  --exclude='*.tmp' \
  --exclude='*.lock' \
  "$HERMES_HOME/" .hermes/

cat > README.md << 'EOF'
# Hermes private state store

Auto-updated by hermes-lifetime (public runner).
Contains SOUL, memory, state.db, config, .env — keep private.
EOF

git add -A

if git diff --cached --quiet; then
  echo "Nothing new to commit"
  exit 0
fi

git commit -m "state $(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Force push so empty/first-run always works
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
if [ -f .hermes/state.db ]; then
  ls -lh .hermes/state.db
fi
if [ -f .hermes/SOUL.md ]; then
  echo "SOUL.md present ($(wc -c < .hermes/SOUL.md) bytes)"
fi
