#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
DEVELOPER_LIBS="$DEVELOPER_DIR/Library/Developer/usr/lib"
MANIFEST_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
SDK_26_5="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
SDK="${AAVAI_SDK_PATH:-$SDK_26_5}"
[[ -d "$SDK" ]] || SDK="$(xcrun --show-sdk-path)"
SWIFT_INTERFACE_VERSION="Apple Swift version 6.3.2 effective-5.10 (swiftlang-6.3.2.1.2 clang-2100.0.123.2)"
TEMP_DIR="$(mktemp -d /private/tmp/aavai-swift-tests.XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT INT TERM
export CLANG_MODULE_CACHE_PATH="$TEMP_DIR/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$TEMP_DIR/swiftpm-module-cache"
[[ -d "$MANIFEST_SDK" ]] || MANIFEST_SDK="$SDK"
export SDKROOT="$MANIFEST_SDK"

cd "$PROJECT_DIR"
swift test --disable-sandbox --sdk "$SDK" \
  -Xswiftc -interface-compiler-version -Xswiftc "$SWIFT_INTERFACE_VERSION" \
  --disable-xctest --enable-swift-testing
BIN_DIR="$(swift build --disable-sandbox --sdk "$SDK" \
  -Xswiftc -interface-compiler-version -Xswiftc "$SWIFT_INTERFACE_VERSION" --show-bin-path)"
OBJECTS="$BIN_DIR/AavAIPackageTests.product/Objects.LinkFileList"
FILTERED_OBJECTS="$TEMP_DIR/Objects.LinkFileList"
RUNNER="$TEMP_DIR/AavAITestRunner"

sed '/runner.swift.o/d' "$OBJECTS" > "$FILTERED_OBJECTS"
swiftc -parse-as-library "$PROJECT_DIR/scripts/support/SwiftTestMain.swift" \
  -L "$BIN_DIR" -o "$RUNNER" -module-name AavAITestRunner \
  -Xlinker -no_warn_duplicate_libraries "@$FILTERED_OBJECTS" \
  -Xlinker -rpath -Xlinker "$DEVELOPER_DIR/usr/lib/swift-6.2/macosx" \
  -target arm64-apple-macosx14.0 \
  -interface-compiler-version "$SWIFT_INTERFACE_VERSION" \
  -F "$FRAMEWORKS" -I "$FRAMEWORKS" -L "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$DEVELOPER_LIBS" \
  -sdk "$SDK"

"$RUNNER"
