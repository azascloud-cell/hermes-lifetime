#!/usr/bin/env bash
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
STATE_REPO="${STATE_REPO:-${GITHUB_REPOSITORY:-azascloud-cell/hermes-lifetime}}"
STATE_BRANCH="${STATE_BRANCH:-hermes-state}"
TOKEN="${STATE_REPO_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
WORKSPACE="${GITHUB_WORKSPACE:-.}"

mkdir -p "$HERMES_HOME/memories" "$HERMES_HOME/state"

echo "=== Restore from ${STATE_REPO}@${STATE_BRANCH} ==="

if [ -n "$TOKEN" ]; then
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
    echo "Restored OK"
  else
    echo "No state yet or clone failed:"
    cat /tmp/restore-clone.err 2>/dev/null || true
  fi
fi

if [ ! -s "$HERMES_HOME/SOUL.md" ] && [ -f "$WORKSPACE/SOUL.md" ]; then
  cp "$WORKSPACE/SOUL.md" "$HERMES_HOME/SOUL.md"
  echo "Seeded SOUL.md"
fi

echo "--- after restore ---"
ls -la "$HERMES_HOME" | head -25 || true
[ -f "$HERMES_HOME/state.db" ] && ls -lh "$HERMES_HOME/state.db" || echo "NO state.db at root"
[ -f "$HERMES_HOME/state/state.db" ] && ls -lh "$HERMES_HOME/state/state.db" || true
[ -s "$HERMES_HOME/SOUL.md" ] && head -3 "$HERMES_HOME/SOUL.md" || echo "NO SOUL"
ls -la "$HERMES_HOME/memories" 2>/dev/null || true
[ -s "$HERMES_HOME/memories/USER.md" ] && echo "USER.md present" || echo "NO USER.md"
