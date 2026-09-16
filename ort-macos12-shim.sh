#!/bin/bash
# ---------------------------------------------------------------------------
# video-extract-mcp : correctif macOS 12 + Mac Intel pour onnxruntime-node.
#
# Probleme (reproduit ici : macOS 12.7.6, x86_64) :
#   node dist/vision/embedWorker.js
#   -> dlopen(.../onnxruntime-node/bin/napi-v6/darwin/x64/onnxruntime_binding.node)
#      Symbol not found: __ZNSt3__18to_charsEPcS0_d
#        Expected in: /usr/lib/libc++.1.dylib
#
# Les binaires darwin-x64 precompiles par onnxruntime-node sont lies a une
# libc++ plus recente que celle de macOS 12 : ils utilisent les surcharges C++17
# flottantes std::to_chars (float / double / long double), apparues avec
# macOS 13. Sans correctif, tout le backend ONNX natif est inutilisable.
#
# Attention : le contournement "device: 'wasm'" ne marche pas non plus ici.
# @huggingface/transformers fait `import * as ONNX_NODE from "onnxruntime-node"`
# statiquement (dist/transformers.node.mjs, ligne 7545) : le chargement du
# module echoue avant toute selection de backend. Seul le binaire est en cause.
#
# Correctif, en deux temps :
#   1. compiler native/ort-toshim/to_chars_shim.cpp en `cxx.dylib` a cote du
#      dylib ORT : elle fournit les 9 symboles to_chars manquants et reexporte
#      la libc++ reelle, donc les autres symboles se resolvent normalement ;
#   2. rediriger la dependance /usr/lib/libc++.1.dylib du dylib ORT vers ce
#      shim avec install_name_tool. Le dylib ORT n'etant pas signe du tout,
#      ni sudo ni re-signature ne sont necessaires.
#
# Usage :
#   ./ort-macos12-shim.sh            applique le correctif (idempotent)
#   ./ort-macos12-shim.sh --check    verifie l'etat sans rien modifier
#   ./ort-macos12-shim.sh --restore  restaure les binaires d'origine
#
# A relancer apres chaque `npm install` (qui remplace les binaires de
# node_modules) : install-node-deps.sh l'appelle automatiquement.
# ---------------------------------------------------------------------------

ROOT="$(cd "$(dirname "$0")" && pwd)"
SHIM_SRC="$ROOT/native/ort-toshim/to_chars_shim.cpp"
ORT_BIN="$ROOT/node_modules/onnxruntime-node/bin"
LIBCXX="/usr/lib/libc++.1.dylib"
SHIM_BASENAME="cxx.dylib"
SHIM_REF="@loader_path/$SHIM_BASENAME"

MODE="apply"
case "${1:-}" in
  --check)   MODE="check" ;;
  --restore) MODE="restore" ;;
  -h|--help) echo "usage: $0 [--check|--restore]"; exit 0 ;;
  "")        ;;
  *)         echo "option inconnue : $1" >&2; exit 2 ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "=== correctif ORT macOS 12 : mode=$MODE ==="
echo "hote   : $(uname -s) $(uname -m) / macOS $(sw_vers -productVersion 2>/dev/null)"
echo "racine : $ROOT"

DYLIBS=()
# find plutot qu'un glob : la profondeur varie selon la version d'ORT
# (bin/napi-v6/darwin/x64/, bin/napi-v3/..., etc.).
while IFS= read -r f; do
  [ -n "$f" ] && DYLIBS+=("$f")
done < <(find "$ORT_BIN" -type f -name 'libonnxruntime*.dylib' 2>/dev/null | sort)

if [ "${#DYLIBS[@]}" -eq 0 ]; then
  echo "onnxruntime-node absent de node_modules : rien a faire."
  exit 0
fi
echo "dylibs ORT trouves : ${#DYLIBS[@]}"

# Le dylib ORT a-t-il des references non resolues vers to_chars (=> macOS 13+) ?
needs_shim() { nm -u "$1" 2>/dev/null | grep -q 'to_chars'; }
# Sa dependance libc++ a-t-elle deja ete redirigee vers le shim ?
is_patched() { otool -L "$1" 2>/dev/null | grep -q "$SHIM_BASENAME"; }

RC=0
for dylib in "${DYLIBS[@]}"; do
  dir="$(dirname "$dylib")"
  label="${dir#"$ORT_BIN"/}/$(basename "$dylib")"
  echo ""
  echo "--- $label"

  # Architecture du dylib (darwin/x64 ou darwin/arm64) : ce n'est pas forcement
  # celle rapportee par uname -m (node lance sous Rosetta, par exemple).
  case "$(basename "$dir")" in
    x64)   ARCH="x86_64" ;;
    arm64) ARCH="arm64" ;;
    *)     ARCH="$(uname -m)" ;;
  esac

  # Seule l'architecture reellement chargee sur cet hote nous interesse :
  # patcher l'autre n'apporterait rien et ne pourrait pas etre verifie.
  if [ "$ARCH" != "$(uname -m)" ]; then
    echo "ignoree : architecture $ARCH != hote $(uname -m)"
    continue
  fi

  if [ "$MODE" = "restore" ]; then
    if is_patched "$dylib"; then
      install_name_tool -change "$SHIM_REF" "$LIBCXX" "$dylib" \
        && echo "restaure : $SHIM_BASENAME -> $LIBCXX"
    else
      echo "deja d'origine"
    fi
    rm -f "$dir/$SHIM_BASENAME"
    continue
  fi

  if ! needs_shim "$dylib"; then
    echo "aucun symbole to_chars manquant : binaire deja compatible, correctif inutile"
    rm -f "$dir/$SHIM_BASENAME"
    continue
  fi

  if [ "$MODE" = "check" ]; then
    if is_patched "$dylib" && [ -f "$dir/$SHIM_BASENAME" ]; then
      echo "OK : shim en place et dependance libc++ redirigee"
    else
      echo "A FAIRE : correctif incomplet (shim=$([ -f "$dir/$SHIM_BASENAME" ] && echo oui || echo non))"
      RC=1
    fi
    continue
  fi

  # /usr/bin/clang++ plutot que le binaire interne de CommandLineTools : c'est
  # lui qui localise seul les en-tetes du SDK. -isysroot est ajoute en renfort
  # (sans lui, `#include <cerrno>` echoue avec "errno.h file not found").
  CXX="$(command -v clang++ 2>/dev/null)"
  [ -z "$CXX" ] && CXX="$(xcrun --find clang++ 2>/dev/null)"
  if [ -z "$CXX" ] || [ ! -f "$SHIM_SRC" ]; then
    echo "ERREUR : clang++ ou $SHIM_SRC introuvable"
    echo "         outils de developpement absents ? -> xcode-select --install"
    RC=2
    continue
  fi
  SDK="$(xcrun --show-sdk-path 2>/dev/null)"
  SYSROOT=""
  [ -n "$SDK" ] && SYSROOT="-isysroot $SDK"

  if ! "$CXX" -std=c++17 -O2 -fPIC -dynamiclib -arch "$ARCH" \
        $SYSROOT -mmacosx-version-min=12.0 -install_name "$SHIM_REF" \
        -Wl,-reexport-lc++ -o "$TMP/$SHIM_BASENAME" "$SHIM_SRC" 2>"$TMP/build.err"; then
    echo "ERREUR : compilation du shim echouee"
    sed -n '1,6p' "$TMP/build.err"
    RC=2
    continue
  fi

  cp -f "$TMP/$SHIM_BASENAME" "$dir/$SHIM_BASENAME" || { echo "ERREUR : copie du shim"; RC=2; continue; }
  echo "shim installe : ${dir#"$ROOT"/}/$SHIM_BASENAME"

  if is_patched "$dylib"; then
    echo "patch deja present : $SHIM_BASENAME"
  elif install_name_tool -change "$LIBCXX" "$SHIM_REF" "$dylib" 2>"$TMP/dyn.err"; then
    echo "patch applique : $LIBCXX -> $SHIM_REF"
  else
    echo "ERREUR : install_name_tool"
    sed -n '1,3p' "$TMP/dyn.err"
    RC=2
    continue
  fi

  # Verification reelle, pas seulement declarative : charger le binding natif.
  if command -v node >/dev/null 2>&1; then
    if (cd "$ROOT" && node -e "import('onnxruntime-node').then(()=>process.exit(0),e=>{console.error(String(e && e.message));process.exit(1)})") >"$TMP/load.out" 2>&1; then
      echo "verification : onnxruntime-node se charge correctement"
    else
      echo "verification : ECHEC du chargement du binding"
      sed -n '1,4p' "$TMP/load.out"
      RC=3
    fi
  fi
done

echo ""
echo "=== RESUME ==="
for dylib in "${DYLIBS[@]}"; do
  dir="$(dirname "$dylib")"
  case "$(basename "$dir")" in
    x64)   ARCH="x86_64" ;;
    arm64) ARCH="arm64" ;;
    *)     ARCH="$(uname -m)" ;;
  esac
  if [ "$ARCH" != "$(uname -m)" ]; then
    state="ignoree (architecture $ARCH)"
  elif is_patched "$dylib" && [ -f "$dir/$SHIM_BASENAME" ]; then
    state="patche"
  elif needs_shim "$dylib"; then
    state="NON patche (a faire)"
  else
    state="inutile (binaire compatible)"
  fi
  echo "  ${dir#"$ORT_BIN"/}/$(basename "$dylib") : $state"
done
echo "code de sortie : $RC"
exit $RC