#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/AavAI.app"
RUNTIME_DIR="$APP_DIR/Contents/Resources/LocalRuntime"
WHISPER_BUILD="$PROJECT_DIR/.tools/whisper.cpp/build/bin"
OLLAMA_RESOURCES="$PROJECT_DIR/.tools/Ollama.app/Contents/Resources"
OLLAMA_BIN="$OLLAMA_RESOURCES/ollama"
WHISPER_MODEL="$PROJECT_DIR/.local-models/ggml-small.en.bin"
WHISPER_ACCURATE_MODEL="$PROJECT_DIR/.local-models/ggml-large-v3-turbo-q5_0.bin"
OLLAMA_MODELS="$PROJECT_DIR/.local-models/ollama"
NODE_BIN="$(command -v node || true)"
DITTO_OPTIONS=(--norsrc --noextattr --noacl --nopersistRootless)
MANIFEST_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
SDK_26_5="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
SDK="${AAVAI_SDK_PATH:-$SDK_26_5}"
[[ -d "$SDK" ]] || SDK="$(xcrun --show-sdk-path)"
SWIFT_INTERFACE_VERSION="Apple Swift version 6.3.2 effective-5.10 (swiftlang-6.3.2.1.2 clang-2100.0.123.2)"
BUILD_CACHE_DIR="$(mktemp -d /private/tmp/aavai-build-cache.XXXXXX)"
trap 'rm -rf "$BUILD_CACHE_DIR"' EXIT INT TERM
export CLANG_MODULE_CACHE_PATH="$BUILD_CACHE_DIR/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_CACHE_DIR/swiftpm-module-cache"
[[ -d "$MANIFEST_SDK" ]] || MANIFEST_SDK="$SDK"
export SDKROOT="$MANIFEST_SDK"

for required in "$WHISPER_BUILD/whisper-server" "$OLLAMA_BIN" "$WHISPER_MODEL" "$WHISPER_ACCURATE_MODEL" "$OLLAMA_MODELS"; do
  if [[ ! -e "$required" ]]; then
    echo "Missing local runtime component: $required"
    echo "Run scripts/setup-local-models.sh first."
    exit 1
  fi
done
if [[ -z "$NODE_BIN" || ! -x "$NODE_BIN" ]]; then
  echo "Node.js was not found. Install Node 22 or newer and rerun this script."
  exit 1
fi

cd "$PROJECT_DIR"
swift build --disable-sandbox --sdk "$SDK" \
  -Xswiftc -interface-compiler-version -Xswiftc "$SWIFT_INTERFACE_VERSION" \
  -c release --product AavAI
BIN_DIR="$(swift build --disable-sandbox --sdk "$SDK" \
  -Xswiftc -interface-compiler-version -Xswiftc "$SWIFT_INTERFACE_VERSION" \
  -c release --show-bin-path)"

STAGING_DIR="$DIST_DIR/.AavAI.app.staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR/Contents/MacOS" "$STAGING_DIR/Contents/Resources/LocalRuntime/bin" "$STAGING_DIR/Contents/Resources/LocalRuntime/models" "$STAGING_DIR/Contents/Resources/LocalRuntime/ollama"

ditto $DITTO_OPTIONS "$BIN_DIR/AavAI" "$STAGING_DIR/Contents/MacOS/AavAI"
ditto $DITTO_OPTIONS "$PROJECT_DIR/packaging/Info.plist" "$STAGING_DIR/Contents/Info.plist"
print -n 'APPL????' > "$STAGING_DIR/Contents/PkgInfo"

ditto $DITTO_OPTIONS "$WHISPER_BUILD" "$STAGING_DIR/Contents/Resources/LocalRuntime/bin"
ditto $DITTO_OPTIONS "$OLLAMA_RESOURCES" "$STAGING_DIR/Contents/Resources/LocalRuntime/ollama"
ditto $DITTO_OPTIONS "$NODE_BIN" "$STAGING_DIR/Contents/Resources/LocalRuntime/bin/node"
ditto $DITTO_OPTIONS "$WHISPER_MODEL" "$STAGING_DIR/Contents/Resources/LocalRuntime/models/ggml-small.en.bin"
ditto $DITTO_OPTIONS "$WHISPER_ACCURATE_MODEL" "$STAGING_DIR/Contents/Resources/LocalRuntime/models/ggml-large-v3-turbo-q5_0.bin"
ditto $DITTO_OPTIONS "$OLLAMA_MODELS" "$STAGING_DIR/Contents/Resources/LocalRuntime/models/ollama"
# Finder metadata on .DS_Store can carry flags that `ditto` cannot recreate in
# a sandboxed build. The backend contains ordinary source files, so a plain
# recursive copy is both sufficient and reproducible here.
cp -R "$PROJECT_DIR/backend" "$STAGING_DIR/Contents/Resources/LocalRuntime/backend"

chmod +x "$STAGING_DIR/Contents/MacOS/AavAI" "$STAGING_DIR/Contents/Resources/LocalRuntime/bin/whisper-server" "$STAGING_DIR/Contents/Resources/LocalRuntime/bin/node" "$STAGING_DIR/Contents/Resources/LocalRuntime/ollama/ollama" "$STAGING_DIR/Contents/Resources/LocalRuntime/ollama/llama-server"
xattr -cr "$STAGING_DIR"
# Ad-hoc signing normally makes the designated requirement equal to the current
# binary's cdhash. That changes on every build and silently invalidates macOS
# Accessibility approval. A stable local requirement keeps this app identity
# consistent across rebuilds; production distribution should replace this with
# a Developer ID Application signature and notarization.
codesign --force --deep --sign - --identifier com.aavai.mac \
  --requirements '=designated => identifier "com.aavai.mac"' "$STAGING_DIR"
codesign --verify --deep --strict --verbose=2 "$STAGING_DIR"

rm -rf "$APP_DIR"
mv "$STAGING_DIR" "$APP_DIR"
echo "Built $APP_DIR"
