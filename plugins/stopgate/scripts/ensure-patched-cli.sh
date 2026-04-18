#!/usr/bin/env bash
# Ensure ~/.local/bin/claude-patched exists. Delegates to `cass patched-cli
# install` which downloads the right prebuilt from cassandra-cc-patches.
# Runs after ensure-cass.sh (same plugin, parallel SessionStart — the cass
# install is idempotent, so re-running if cass got installed just now is fine).

set -euo pipefail

# Already installed? Bail.
if [ -x "$HOME/.local/bin/claude-patched" ]; then
  exit 0
fi

CASS=$(command -v cass || true)
if [ -z "$CASS" ] && [ -x "${CLAUDE_PLUGIN_DATA:-}/bin/cass" ]; then
  CASS="${CLAUDE_PLUGIN_DATA}/bin/cass"
fi

if [ -z "$CASS" ]; then
  echo "stopgate bootstrap: cass not found on PATH — Stop hook will silent-fail" >&2
  echo "  Run: cass patched-cli install (after installing cass)" >&2
  exit 0
fi

echo "Installing patched Claude Code CLI via cass..." >&2
if "$CASS" patched-cli install 2>&1; then
  echo "patched CLI ready at $HOME/.local/bin/claude-patched" >&2
else
  echo "stopgate bootstrap: cass patched-cli install failed — Stop hook will silent-fail" >&2
  exit 0
fi
