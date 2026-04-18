#!/usr/bin/env bash
# Check this service's cookies on SessionStart. Prints a clear action line
# to stderr if the service is MISSING; exits 0 either way so plugin load
# is never blocked. Pass the cass service name as $1 (yt-mcp, twitter,
# claude-ai, ...).

set -euo pipefail

SERVICE="${1:-}"
if [ -z "$SERVICE" ]; then
  echo "ensure-cookies.sh: missing service argument" >&2
  exit 0
fi

# cass may not be on PATH yet (ensure-cass.sh runs in parallel on first
# install). Skip silently — next session will report status.
if ! command -v cass >/dev/null 2>&1; then
  exit 0
fi

status=$(cass cookies status 2>&1 || true)
# Match the line starting with the service name after whitespace.
line=$(printf '%s\n' "$status" | awk -v s="$SERVICE" '$1 == s {print; exit}')

if [ -z "$line" ]; then
  # Service not recognized by this cass version — bail quietly.
  exit 0
fi

if echo "$line" | grep -qi "MISSING"; then
  echo "" >&2
  echo "  ${SERVICE} cookies not synced — run:  cass cookies sync ${SERVICE}" >&2
fi
