#!/usr/bin/env bash
# Restore essential state from branch hermes-state on same repo
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
STATE_REPO="${STATE_REPO:-${GITHUB_REPOSITORY:-azascloud-cell/hermes-lifetime}}"
STATE_BRANCH="${STATE_BRANCH:-hermes-state}"
TOKEN="${STATE_REPO_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
WORKSPACE="${GITHUB_WORKSPACE:-.}"

mkdir -p "$HERMES_HOME/memories"

echo "=== Restore state from ${STATE_REPO}@${STATE_BRANCH} ==="

if [ -z "$TOKEN" ]; then
  echo "WARN: no token — skip remote restore"
else
  STAGE="${RUNNER_TEMP:-/tmp}/hermes-restore-$$"
  rm -rf "$STAGE"
  set +e
  git clone --depth 1 --branch "$STATE_BRANCH" \
    "https://x-access-token:${TOKEN}@github.com/${STATE_REPO}.git" \
    "$STAGE" 2>/tmp/restore-clone.err
  RC=$?
  set -e
  if [ $RC -eq 0 ] && [ -d "$STAGE/.hermes" ]; then
    rsync -a "$STAGE/.hermes/" "$HERMES_HOME/"
    echo "Restored from branch ${STATE_BRANCH}"
  else
    echo "No state branch yet or clone failed (first run OK):"
    cat /tmp/restore-clone.err 2>/dev/null || true
  fi
fi

# Seed SOUL from main checkout if still missing
if [ ! -s "$HERMES_HOME/SOUL.md" ] && [ -f "$WORKSPACE/SOUL.md" ]; then
  cp "$WORKSPACE/SOUL.md" "$HERMES_HOME/SOUL.md"
  echo "Seeded SOUL.md from repo"
fi

echo "--- status ---"
ls -la "$HERMES_HOME" | head -20 || true
[ -f "$HERMES_HOME/SOUL.md" ] && head -5 "$HERMES_HOME/SOUL.md" || echo "NO SOUL"
[ -f "$HERMES_HOME/state.db" ] && ls -lh "$HERMES_HOME/state.db" || echo "NO state.db"
ls -la "$HERMES_HOME/memories" 2>/dev/null || true
