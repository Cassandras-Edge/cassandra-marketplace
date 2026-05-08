#!/usr/bin/env bash
# Fire-and-forget perplexity cookie refresh on SessionStart. Backgrounds
# `cass cookies refresh perplexity-mcp` so this hook returns immediately —
# cookie freshness is best-effort, not startup-critical.
#
# `refresh` is smarter than `sync`: if cf_clearance still has plenty of TTL
# it skips Firefox and just re-pushes the existing jar. If cf_clearance is
# near expiry it pops Firefox in the background to mint a fresh one.
#
# Output goes to a per-service log under the plugin data dir.

set -euo pipefail

command -v cass >/dev/null 2>&1 || exit 0

LOG_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.cache/cass-bootstrap}"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/cookies-refresh-perplexity-mcp.log"

# Prevent more than one refresh per ~30 minutes per machine to avoid
# spamming the auth service when sessions start in rapid succession.
STAMP_FILE="${LOG_DIR}/.cookies-refresh-perplexity-mcp.stamp"
if [ -f "$STAMP_FILE" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$STAMP_FILE" 2>/dev/null || echo 0) ))
  if [ "$age" -lt 1800 ]; then
    exit 0
  fi
fi
touch "$STAMP_FILE"

# Public portal — overrides any localhost CASS_PORTAL_URL leaking from
# env/schwab.local.env when this runs from a Claude Code launch context.
CASS_PORTAL_URL="https://portal.cassandrasedge.com" \
  nohup cass cookies refresh perplexity-mcp --timeout 30 \
  >"$LOG" 2>&1 </dev/null &
disown 2>/dev/null || true
exit 0
