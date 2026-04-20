#!/usr/bin/env bash
# Ensure the `cass` binary is on PATH. Downloads the latest release into
# this plugin's data dir on first run, then Claude Code auto-adds that
# dir to PATH for subsequent plugin commands (including MCP headersHelper).
#
# Idempotent: exits 0 when cass is already available or the latest version
# is already installed. Fails soft (exits 0 with a warning) on download
# errors so plugin activation isn't blocked.

set -euo pipefail

# Already on PATH? Nothing to do.
if command -v cass >/dev/null 2>&1; then
  exit 0
fi

CASS_REPO="Cassandras-Edge/cass"
BIN_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.local/share/cass-bootstrap}/bin"
CASS_BIN="${BIN_DIR}/cass"
VERSION_FILE="${BIN_DIR}/.cass-version"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "cass bootstrap: unsupported arch $ARCH" >&2; exit 0 ;;
esac

case "$OS" in
  mingw*|msys*|cygwin*|windows_nt*)
    echo "cass bootstrap: native Windows not supported — use WSL" >&2
    exit 0
    ;;
esac

TARGET="${OS}-${ARCH}"
ASSET="cass-${TARGET}"

LATEST=$(curl -sSL --max-time 10 \
  "https://api.github.com/repos/${CASS_REPO}/releases/latest" \
  | grep '"tag_name"' | head -1 | cut -d'"' -f4)
if [ -z "$LATEST" ]; then
  echo "cass bootstrap: failed to fetch latest version" >&2
  exit 0
fi

if [ -x "$CASS_BIN" ] && [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$LATEST" ]; then
  exit 0
fi

URL="https://github.com/${CASS_REPO}/releases/download/${LATEST}/${ASSET}"
echo "Installing cass ${LATEST} for ${TARGET}..." >&2

mkdir -p "$BIN_DIR"
if curl -sSL --fail --max-time 60 "$URL" -o "$CASS_BIN"; then
  chmod +x "$CASS_BIN"
  echo "$LATEST" > "$VERSION_FILE"
  echo "cass ${LATEST} installed to ${CASS_BIN}" >&2
else
  echo "cass bootstrap: failed to download from ${URL}" >&2
  rm -f "$CASS_BIN"
  exit 0
fi
