#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TOOLS_DIR="$PROJECT_DIR/.tools"
MODELS_DIR="$PROJECT_DIR/.local-models"
RUNTIME_DIR="$PROJECT_DIR/.runtime"
WHISPER_BIN="$TOOLS_DIR/whisper.cpp/build/bin/whisper-server"
OLLAMA_BIN="$TOOLS_DIR/Ollama.app/Contents/Resources/ollama"
WHISPER_MODEL="$MODELS_DIR/ggml-small.en.bin"
mkdir -p "$RUNTIME_DIR"

if [[ ! -x "$WHISPER_BIN" || ! -x "$OLLAMA_BIN" || ! -f "$WHISPER_MODEL" ]]; then
  echo "Local engines are missing. Run scripts/setup-local-models.sh first."
  exit 1
fi

PIDS=()
CACHE_DIR=""
cleanup() {
  for pid in $PIDS; do kill "$pid" 2>/dev/null || true; done
  [[ -z "$CACHE_DIR" ]] || rm -rf "$CACHE_DIR"
}
trap cleanup EXIT INT TERM

if ! curl -fsS --max-time 2 http://127.0.0.1:8080/health >/dev/null 2>&1; then
  "$WHISPER_BIN" --model "$WHISPER_MODEL" --host 127.0.0.1 --port 8080 >"$RUNTIME_DIR/whisper.log" 2>&1 &
  PIDS+=($!)
fi

if ! curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  OLLAMA_HOST=127.0.0.1:11434 OLLAMA_MODELS="$MODELS_DIR/ollama" "$OLLAMA_BIN" serve >"$RUNTIME_DIR/ollama.log" 2>&1 &
  PIDS+=($!)
fi

for url in http://127.0.0.1:8080/health http://127.0.0.1:11434/api/tags; do
  for _ in {1..90}; do
    curl -fsS --max-time 2 "$url" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fsS --max-time 2 "$url" >/dev/null
done

if BACKEND_HEALTH=$(curl -fsS --max-time 2 http://127.0.0.1:8787/health 2>/dev/null); then
  if ! print -r -- "$BACKEND_HEALTH" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const h=JSON.parse(s);process.exit(h.dependencies?.provider==="local"?0:1)})'; then
    echo "Port 8787 is occupied by a non-local or stale AavAI backend. Stop that process and run this script again."
    exit 1
  fi
else
  cd "$PROJECT_DIR/backend"
  AAVAI_PROVIDER=local node src/server.mjs >"$RUNTIME_DIR/backend.log" 2>&1 &
  PIDS+=($!)
fi
for _ in {1..30}; do
  curl -fsS --max-time 2 http://127.0.0.1:8787/health >/dev/null 2>&1 && break
  sleep 1
done
curl -fsS http://127.0.0.1:8787/health
echo
echo "Local AI services are ready. Launching AavAI..."
cd "$PROJECT_DIR"
MANIFEST_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
SDK_26_5="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
SDK="${AAVAI_SDK_PATH:-$SDK_26_5}"
[[ -d "$SDK" ]] || SDK="$(xcrun --show-sdk-path)"
SWIFT_INTERFACE_VERSION="Apple Swift version 6.3.2 effective-5.10 (swiftlang-6.3.2.1.2 clang-2100.0.123.2)"
CACHE_DIR="$(mktemp -d /private/tmp/aavai-run-cache.XXXXXX)"
export CLANG_MODULE_CACHE_PATH="$CACHE_DIR/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_DIR/swiftpm-module-cache"
[[ -d "$MANIFEST_SDK" ]] || MANIFEST_SDK="$SDK"
export SDKROOT="$MANIFEST_SDK"
swift run --disable-sandbox --sdk "$SDK" \
  -Xswiftc -interface-compiler-version -Xswiftc "$SWIFT_INTERFACE_VERSION" AavAI
