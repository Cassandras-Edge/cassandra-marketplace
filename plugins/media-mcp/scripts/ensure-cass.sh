#!/usr/bin/env bash
# Ensure a current `cass` binary is available. Version-gates against the
# latest GitHub release — if no cass is on PATH (or it reports an older
# version), download the latest into this plugin's data dir. Claude Code
# adds that dir to PATH for subsequent plugin commands including the MCP
# headersHelper.
#
# cass itself also self-updates on every invocation (rate-limited to 1h),
# so a stale install on the user's PATH will heal on next real command.
# This script catches the case where cass is missing entirely OR a stale
# install is lying about its version (pre-0.6.6 binaries hard-coded the
# version string and never updated it on release).
#
# Fails soft (exits 0 with a warning) on any error so plugin activation
# is never blocked.

set -euo pipefail

CASS_REPO="Cassandras-Edge/cass"
BIN_DIR="${CLAUDE_PLUGIN_DATA:-$HOME/.local/share/cass-bootstrap}/bin"
CASS_BIN="${BIN_DIR}/cass"
VERSION_FILE="${BIN_DIR}/.cass-version"

LATEST=$(curl -sSL --max-time 10 \
  "https://api.github.com/repos/${CASS_REPO}/releases/latest" \
  | grep '"tag_name"' | head -1 | cut -d'"' -f4)
if [ -z "$LATEST" ]; then
  echo "cass bootstrap: failed to fetch latest version — skipping" >&2
  exit 0
fi
LATEST_NOV="${LATEST#v}"

# If any cass on PATH already reports the latest version, nothing to do.
# Parses output like "cass, version 0.6.6" -> "0.6.6".
if command -v cass >/dev/null 2>&1; then
  INSTALLED=$(cass --version 2>/dev/null | awk '{print $NF}' | tr -d ',')
  if [ "$INSTALLED" = "$LATEST_NOV" ]; then
    exit 0
  fi
fi

# Skip download if our plugin-data binary is already at latest.
if [ -x "$CASS_BIN" ] && [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$LATEST" ]; then
  exit 0
fi

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
