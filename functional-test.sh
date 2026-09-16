#!/bin/bash
# Test fonctionnel : pipeline complet (resolution + ffmpeg + embeddings natives).
# Log deterministe : functional-test.log
#
# Les URL d'origine (commondatastorage.googleapis.com) repondent 403 depuis cette
# machine : l'ancien test "passait" donc sans rien tester (0 frame, status
# auth_required). On couvre ici les DEUX chemins de resolution avec des sources
# reellement joignables :
#   - media.w3.org/.../sintel/trailer.mp4  -> resolveur "direct" (telechargement)
#   - youtube.com/watch?v=jNQXAC9IVRw      -> resolveur "yt-dlp" + sous-titres
#
# Le test ECHOUE (code de sortie = nombre d'echecs) si un resultat n'est plus
# celui attendu : status, duree, frames selectionnees, embeddings calcules.

# Node 22 is required: Node 26 itself cannot boot on macOS 12 (see README,
# "macOS 12 on Intel"). nvm use fails silently if nvm/that version is absent.

export PATH="$HOME/bin:$PATH"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm use 22 >/dev/null 2>&1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1
LOG="$ROOT/functional-test.log"
exec > "$LOG" 2>&1

# Pas de telechargement de modeles lourds (Whisper 1.3 Go) pendant le test
export VIDEO_EXTRACT_AUTO_FETCH_MODELS=0

DIRECT="https://media.w3.org/2010/05/sintel/trailer.mp4"
YT="https://www.youtube.com/watch?v=jNQXAC9IVRw"

FAILURES=0

# check <libelle> <resultat.json> <expression JS, `r` = manifeste>
check() {
  local label="$1" file="$2" expr="$3"
  if RESULT_FILE="$file" EXPR="$expr" node -e '
    const r = JSON.parse(require("node:fs").readFileSync(process.env.RESULT_FILE, "utf8"));
    process.exit(eval(process.env.EXPR) ? 0 : 1);
  '; then
    echo "PASS  $label"
  else
    echo "FAIL  $label"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "=== $(date) TEST FONCTIONNEL ==="
echo "direct : $DIRECT"
echo "youtube: $YT"
echo ""

echo "--- [A] METADATA DIRECTE (aucun telechargement de media) ---"
mkdir -p ./output-meta
node dist/cli.js "$DIRECT" --frames none --no-transcript --out ./output-meta > ./output-meta/result.json 2>&1
echo "EXIT_A=$?"
check "A: status ok, duree connue, aucune frame demandee" ./output-meta/result.json \
  'r.source.status === "ok" && r.source.resolvedBy === "direct" && r.source.duration > 0 && r.frames.length === 0'
echo ""

echo "--- [B] FRAMES + EMBEDDINGS NATIVES (ffmpeg/ffprobe + SigLIP) ---"
mkdir -p ./output-frames
node dist/cli.js "$DIRECT" --max-frames 3 --no-transcript --out ./output-frames > ./output-frames/result.json 2>&1
echo "EXIT_B=$?"
check "B: frames selectionnees parmi des candidats" ./output-frames/result.json \
  'r.frames.length >= 1 && r.processing.candidateFrames >= r.frames.length'
check "B: embeddings calcules (le correctif ORT macOS 12 tient)" ./output-frames/result.json \
  'r.frames.some(f => f.nearestSelectedSimilarity > 0.01)'
check "B: aucune degradation d'embedding" ./output-frames/result.json \
  '!r.processing.warnings.some(w => w.includes("embedding failed"))'
echo ""

echo "--- [C] RESOLUTION YT-DLP + SOUS-TITRES (aucun modele ASR telecharge) ---"
mkdir -p ./output-yt
node dist/cli.js "$YT" --frames none --out ./output-yt > ./output-yt/result.json 2>&1
echo "EXIT_C=$?"
check "C: status ok, titre et duree via yt-dlp" ./output-yt/result.json \
  'r.source.status === "ok" && r.source.resolvedBy === "ytdlp" && r.source.title.length > 0 && r.source.duration > 0'
check "C: transcript issu des sous-titres" ./output-yt/result.json \
  'r.transcript !== null && r.transcript.segments.length > 0'
echo ""

echo "--- [D] FICHIERS PRODUITS ---"
find ./output-meta ./output-frames ./output-yt -type f 2>/dev/null | grep -v result.json | head -25
echo ""

echo "--- [E] ffprobe sur les medias recuperes ---"
find ./output-frames ./output-yt -name '*.mp4' 2>/dev/null | while read -r f; do
  echo "fichier: $f"
  ffprobe -v error -show_entries format=duration,size -of default=noprint_wrappers=1 "$f"
done
echo ""

echo "--- [F] AVERTISSEMENTS (tesseract absent est attendu et non bloquant) ---"
node -e '
  const r = JSON.parse(require("node:fs").readFileSync("./output-frames/result.json", "utf8"));
  console.log(r.processing.warnings.length ? r.processing.warnings.join("\n") : "(aucun)");
'
echo ""

echo "=== RESUME ==="
echo "echecs : $FAILURES"
echo "=== $(date) FIN TEST FONCTIONNEL ==="
exit $FAILURES