#!/bin/bash
# Tests de fumee : preflight + binaires + serveur MCP + CLI.
# Log deterministe : smoke-test.log

export PATH="$HOME/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm use 22 >/dev/null 2>&1

cd /Users/user/Documents/video-extract-mcp || exit 1
LOG=/Users/user/Documents/video-extract-mcp/smoke-test.log
exec > "$LOG" 2>&1

echo "=== $(date) SMOKE TEST ==="
echo "node: $(node --version)  npm: $(npm --version)"
echo "PATH bin: $(command -v ffmpeg)"
echo ""

echo "--- [1] VERSIONS BINAIRES ---"
ffmpeg -version 2>&1 | head -1
ffprobe -version 2>&1 | head -1
yt-dlp --version 2>&1 | head -1
echo ""

echo "--- [2] PREFLIGHT (attend tesseract manquant, non bloquant) ---"
npx tsx scripts/preflight.ts 2>&1
echo "PREFLIGHT_EXIT=$?"
echo ""

echo "--- [3] SMOKE MCP : tools/list sur dist/mcp.js ---"
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  | node dist/mcp.js > /tmp/mcp-smoke-out.txt 2>&1 &
MPID=$!
sleep 8
kill $MPID 2>/dev/null
wait $MPID 2>/dev/null
echo "--- sortie serveur (1200 premiers octets) ---"
head -c 1200 /tmp/mcp-smoke-out.txt
echo ""
echo ""

echo "--- [4] CLI --help ---"
node dist/cli.js --help 2>&1 | head -30
echo "CLI_EXIT=$?"
echo ""

echo "=== $(date) FIN SMOKE TEST ==="
