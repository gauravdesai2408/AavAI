#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
TOOLS_DIR="$PROJECT_DIR/.tools"
MODELS_DIR="$PROJECT_DIR/.local-models"
RUNTIME_DIR="$PROJECT_DIR/.runtime"
mkdir -p "$TOOLS_DIR" "$MODELS_DIR" "$RUNTIME_DIR"

if [[ ! -x "$TOOLS_DIR/cmake/bin/cmake" ]]; then
  CMAKE_APP=$(find "$TOOLS_DIR/cmake-extract" -maxdepth 3 -type d -name CMake.app 2>/dev/null | head -1)
  if [[ -z "$CMAKE_APP" ]]; then
    echo "Downloading project-local CMake..."
    CMAKE_JSON="$RUNTIME_DIR/cmake-release.json"
    curl -fsSL https://api.github.com/repos/Kitware/CMake/releases/latest -o "$CMAKE_JSON"
    CMAKE_URL=$(node -e 'const fs=require("fs");const r=JSON.parse(fs.readFileSync(process.argv[1]));const a=r.assets.find(x=>/macos-universal\.tar\.gz$/.test(x.name));if(!a)process.exit(1);process.stdout.write(a.browser_download_url)' "$CMAKE_JSON")
    curl -fL "$CMAKE_URL" -o "$RUNTIME_DIR/cmake.tar.gz"
    rm -rf "$TOOLS_DIR/cmake-extract"
    mkdir -p "$TOOLS_DIR/cmake-extract"
    tar -xzf "$RUNTIME_DIR/cmake.tar.gz" -C "$TOOLS_DIR/cmake-extract"
    CMAKE_APP=$(find "$TOOLS_DIR/cmake-extract" -maxdepth 3 -type d -name CMake.app | head -1)
  fi
  [[ -n "$CMAKE_APP" ]] || { echo "CMake.app was not found after extraction"; exit 1; }
  ln -sfn "$CMAKE_APP/Contents" "$TOOLS_DIR/cmake"
fi

if [[ ! -d "$TOOLS_DIR/whisper.cpp/.git" ]]; then
  echo "Downloading whisper.cpp..."
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp.git "$TOOLS_DIR/whisper.cpp"
fi

echo "Building whisper.cpp for Apple Silicon..."
"$TOOLS_DIR/cmake/bin/cmake" -S "$TOOLS_DIR/whisper.cpp" -B "$TOOLS_DIR/whisper.cpp/build" -DCMAKE_BUILD_TYPE=Release
"$TOOLS_DIR/cmake/bin/cmake" --build "$TOOLS_DIR/whisper.cpp/build" --config Release -j 4

WHISPER_MODEL="$MODELS_DIR/ggml-small.en.bin"
if [[ ! -f "$WHISPER_MODEL" ]]; then
  echo "Downloading Whisper small.en model..."
  "$TOOLS_DIR/whisper.cpp/models/download-ggml-model.sh" small.en "$MODELS_DIR"
fi

if [[ ! -f "$MODELS_DIR/ggml-large-v3-turbo-q5_0.bin" ]]; then
  echo "Downloading the accuracy speech model..."
  "$TOOLS_DIR/whisper.cpp/models/download-ggml-model.sh" large-v3-turbo-q5_0 "$MODELS_DIR"
fi

if [[ ! -x "$TOOLS_DIR/Ollama.app/Contents/Resources/ollama" ]]; then
  echo "Downloading Ollama for macOS..."
  curl -fL https://ollama.com/download/Ollama-darwin.zip -o "$RUNTIME_DIR/Ollama-darwin.zip"
  rm -rf "$TOOLS_DIR/Ollama.app"
  ditto -x -k "$RUNTIME_DIR/Ollama-darwin.zip" "$TOOLS_DIR"
fi

OLLAMA_BIN="$TOOLS_DIR/Ollama.app/Contents/Resources/ollama"
if ! curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "Starting Ollama..."
  OLLAMA_HOST=127.0.0.1:11434 OLLAMA_MODELS="$MODELS_DIR/ollama" "$OLLAMA_BIN" serve >"$RUNTIME_DIR/ollama.log" 2>&1 &
  echo $! > "$RUNTIME_DIR/ollama.pid"
  for _ in {1..60}; do
    curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && break
    sleep 1
  done
fi

echo "Downloading Qwen cleanup model..."
OLLAMA_HOST=127.0.0.1:11434 OLLAMA_MODELS="$MODELS_DIR/ollama" "$OLLAMA_BIN" pull qwen3:4b-instruct
echo "Local models are ready."
