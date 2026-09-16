#!/bin/bash
# Installation des binaires systeme requis par video-extract-mcp,
# sans compilation depuis les sources (macOS 12 Monterey = pas de bottle Homebrew).
# Sortie complete dans $HOME/bin/setup.log

BIN="$HOME/bin"
LOG="$BIN/setup.log"
mkdir -p "$BIN"

# Tout rediriger dans le log (deterministe, lisible par polling)
exec > "$LOG" 2>&1

echo "=== $(date) DEBUT INSTALLATION ==="
echo "Systeme: $(sw_vers -productVersion) $(uname -m)"
df -h /System/Volumes/Data | tail -1

# ---------- 1) yt-dlp (binaire statique officiel) ----------
echo ""
echo "--- [1/4] yt-dlp ---"
curl -fL --retry 3 --connect-timeout 20 -o "$BIN/yt-dlp" \
  "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
if [ -f "$BIN/yt-dlp" ]; then
  chmod +x "$BIN/yt-dlp"
  xattr -d com.apple.quarantine "$BIN/yt-dlp" 2>/dev/null
  "$BIN/yt-dlp" --version && echo "yt-dlp OK" || echo "yt-dlp KO (exec)"
else
  echo "yt-dlp KO (download)"
fi

# ---------- 2) ffmpeg statique (evermeet.cx) ----------
echo ""
echo "--- [2/4] ffmpeg ---"
cd "$BIN" || exit 1
curl -fL --retry 3 --connect-timeout 20 -o ffmpeg.zip "https://evermeet.cx/ffmpeg/getrelease/zip"
if [ -f ffmpeg.zip ]; then
  unzip -o -q ffmpeg.zip && rm -f ffmpeg.zip
  chmod +x ffmpeg 2>/dev/null
  xattr -d com.apple.quarantine ffmpeg 2>/dev/null
  ./ffmpeg -version 2>&1 | head -1 && echo "ffmpeg OK" || echo "ffmpeg KO"
else
  echo "ffmpeg KO (download)"
fi

# ---------- 3) ffprobe statique (evermeet.cx) ----------
echo ""
echo "--- [3/4] ffprobe ---"
curl -fL --retry 3 --connect-timeout 20 -o ffprobe.zip "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip"
if [ -f ffprobe.zip ]; then
  unzip -o -q ffprobe.zip && rm -f ffprobe.zip
  chmod +x ffprobe 2>/dev/null
  xattr -d com.apple.quarantine ffprobe 2>/dev/null
  ./ffprobe -version 2>&1 | head -1 && echo "ffprobe OK" || echo "ffprobe KO"
else
  echo "ffprobe KO (download)"
fi

# ---------- 4) tesseract : bottle uniquement (echec rapide si absent) ----------
echo ""
echo "--- [4/4] tesseract (bottle only) ---"
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
  brew install --force-bottle tesseract 2>&1 | tail -8
if command -v tesseract >/dev/null 2>&1; then
  tesseract --version 2>&1 | head -1 && echo "tesseract OK"
else
  echo "tesseract ABSENT (non bloquant : seul l'OCR de texte incruste en depend)"
fi

echo ""
echo "=== RESUME ==="
for b in yt-dlp ffmpeg ffprobe tesseract; do
  printf '%s: ' "$b"
  command -v "$b" >/dev/null 2>&1 && echo "OK ($(command -v $b))" || echo "ABSENT"
done
df -h /System/Volumes/Data | tail -1
echo "=== $(date) FIN INSTALLATION ==="