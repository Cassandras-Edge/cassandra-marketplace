#!/usr/bin/env bash
# Fire-and-forget cookies sync for this plugin's service. Backgrounds the
# `cass cookies sync` call so the SessionStart hook returns immediately —
# cookie freshness is best-effort, not startup-critical. Output goes to
# a per-service log under the plugin data dir for post-hoc inspection.
# Pass the cass service name as $1 (yt-mcp, twitter, claude-ai).

set -euo pipefail

SERVICE="${1:-}"
[ -z "$SERVICE" ] && exit 0
command -v cass >/dev/null 2>&1 || exit 0

LOG_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.cache/cass-bootstrap}"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/cookies-sync-${SERVICE}.log"

nohup cass cookies sync "$SERVICE" --no-open >"$LOG" 2>&1 </dev/null &
disown 2>/dev/null || true
exit 0
