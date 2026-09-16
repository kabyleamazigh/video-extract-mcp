#!/bin/bash
# Installation des dependances npm + build, avec Node 22 (Node 26 impossible sur macOS 12).
# Log deterministe : install-deps.log

export PATH="$HOME/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm use 22 >/dev/null 2>&1

cd /Users/user/Documents/video-extract-mcp || exit 1
LOG=/Users/user/Documents/video-extract-mcp/install-deps.log
exec > "$LOG" 2>&1

echo "=== $(date) DEBUT INSTALL DEPS ==="
node --version
npm --version
df -h /System/Volumes/Data | tail -1

# PATH persistant pour ~/bin (ffmpeg/ffprobe/yt-dlp)
grep -q 'HOME/bin' "$HOME/.zprofile" 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zprofile"

echo ""
echo "--- npm install (cache local, engine-strict desactive) ---"
npm install --engine-strict=false --no-fund --no-audit \
  --cache /Users/user/Documents/video-extract-mcp/.npm-cache 2>&1
echo "NPM_EXIT=$?"

echo ""
echo "--- correctif onnxruntime macOS 12 (shim std::to_chars) ---"
# npm install vient de (re)poser les binaires d'onnxruntime-node : ils sont
# lies a une libc++ macOS 13+ et ne se chargent pas sur macOS 12 tant que le
# patch n'est pas reapplique. Voir l'en-tete de ort-macos12-shim.sh.
bash /Users/user/Documents/video-extract-mcp/ort-macos12-shim.sh 2>&1
echo "SHIM_EXIT=$?"

echo ""
echo "--- taille node_modules ---"
du -sh node_modules 2>/dev/null

echo ""
echo "--- npm run build (tsc) ---"
npm run build 2>&1 | tail -40
echo "BUILD_EXIT=$?"

echo ""
echo "--- node_modules/.bin ---"
ls node_modules/.bin 2>/dev/null | head -20

echo ""
echo "=== $(date) FIN INSTALL DEPS ==="
df -h /System/Volumes/Data | tail -1
