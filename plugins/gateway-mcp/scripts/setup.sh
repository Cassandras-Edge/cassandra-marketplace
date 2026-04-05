#!/usr/bin/env bash
# gateway-setup — Add Cassandra Gateway + discovery MCP servers to .mcp.json
#
# Creates or updates .mcp.json in the project root with:
#   - cassandra-gateway (execute-only, streamable-http)
#   - Per-service discovery servers (market-research, etc.)
#
# Requires: MCP_API_KEY env var or prompts for it.

set -euo pipefail

PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-.}"
MCP_CONFIG="$PROJECT_ROOT/.mcp.json"

# Gateway URL (default: cluster internal, override with GATEWAY_URL)
GATEWAY_URL="${GATEWAY_URL:-https://gateway.cassandrasedge.com/mcp}"
MARKET_URL="${MARKET_URL:-https://market-research.cassandrasedge.com/mcp}"

# Check for API key
API_KEY="${MCP_API_KEY:-}"
if [ -z "$API_KEY" ]; then
  echo "MCP_API_KEY env var not set."
  echo "Set it to your mcp_ API key for the gateway service."
  echo "  export MCP_API_KEY=mcp_gateway_..."
  exit 1
fi

# Build the MCP config entries
GATEWAY_CONFIG=$(cat <<EOF
{
  "type": "streamable-http",
  "url": "$GATEWAY_URL",
  "headers": {
    "Authorization": "Bearer $API_KEY"
  }
}
EOF
)

MARKET_CONFIG=$(cat <<EOF
{
  "type": "streamable-http",
  "url": "$MARKET_URL",
  "headers": {
    "Authorization": "Bearer $API_KEY"
  }
}
EOF
)

# Create or merge into .mcp.json
if [ -f "$MCP_CONFIG" ]; then
  # Merge into existing config
  EXISTING=$(cat "$MCP_CONFIG")
  echo "$EXISTING" | python3 -c "
import sys, json
config = json.load(sys.stdin)
servers = config.setdefault('mcpServers', {})
servers['cassandra-gateway'] = $GATEWAY_CONFIG
servers['market-research'] = $MARKET_CONFIG
print(json.dumps(config, indent=2))
" > "$MCP_CONFIG.tmp" && mv "$MCP_CONFIG.tmp" "$MCP_CONFIG"
  echo "Updated $MCP_CONFIG with cassandra-gateway + market-research"
else
  # Create new config
  python3 -c "
import json
config = {
  'mcpServers': {
    'cassandra-gateway': $GATEWAY_CONFIG,
    'market-research': $MARKET_CONFIG
  }
}
print(json.dumps(config, indent=2))
" > "$MCP_CONFIG"
  echo "Created $MCP_CONFIG with cassandra-gateway + market-research"
fi

echo ""
echo "MCP servers configured:"
echo "  cassandra-gateway  → $GATEWAY_URL (execute)"
echo "  market-research    → $MARKET_URL (discovery)"
echo ""
echo "Add more discovery servers by editing $MCP_CONFIG."
