#!/usr/bin/env bash
# Sync this service's cookies on SessionStart. Runs `cass cookies sync`
# unconditionally so the auth service always has fresh credentials —
# Firefox-local "ok" does not imply server-side freshness. Uses --no-open
# so a missing-cookies state doesn't spawn a browser window. Exits 0 either
# way so plugin load is never blocked. Pass the cass service name as $1
# (yt-mcp, twitter, claude-ai, ...).

set -euo pipefail

SERVICE="${1:-}"
if [ -z "$SERVICE" ]; then
  echo "ensure-cookies.sh: missing service argument" >&2
  exit 0
fi

# cass may not be on PATH yet (ensure-cass.sh runs in parallel on first
# install). Skip silently — next session will sync.
if ! command -v cass >/dev/null 2>&1; then
  exit 0
fi

output=$(cass cookies sync "$SERVICE" --no-open 2>&1 || true)

# Surface the outcome line so the user sees what happened. Looks for the
# last action line printed by `cass cookies sync` (Synced / No cookies /
# INVALID / Valid / Dry).
action=$(printf '%s\n' "$output" | awk '/^  (Synced|No cookies|Cookies|INVALID|Valid|Dry)/ {last=$0} END {print last}')
if [ -n "$action" ]; then
  echo "  ${SERVICE}:${action#  }" >&2
fi
