#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE_APP="$PROJECT_DIR/dist/AavAI.app"
USER_APPS_DIR="$HOME/Applications"
DESTINATION="$USER_APPS_DIR/AavAI.app"

if pgrep -x AavAI >/dev/null; then
  echo "Quit AavAI before installing an update."
  exit 1
fi
"$PROJECT_DIR/scripts/build-app.sh"
codesign --verify --deep --strict "$SOURCE_APP"
mkdir -p "$USER_APPS_DIR"
ROLLBACK_DIR="$(mktemp -d "$USER_APPS_DIR/.aavai-install.XXXXXX")"
restore_on_failure() {
  if [[ -e "$ROLLBACK_DIR/previous.app" && ! -e "$DESTINATION" ]]; then
    mv "$ROLLBACK_DIR/previous.app" "$DESTINATION"
  fi
  rmdir "$ROLLBACK_DIR" 2>/dev/null || true
}
trap restore_on_failure EXIT
if [[ -e "$DESTINATION" ]]; then
  mv "$DESTINATION" "$ROLLBACK_DIR/previous.app"
fi
# Move the verified build rather than retain another multi-gigabyte copy in dist.
mv "$SOURCE_APP" "$DESTINATION"
if [[ -e "$ROLLBACK_DIR/previous.app" ]]; then
  rm -rf "$ROLLBACK_DIR/previous.app"
fi
rmdir "$ROLLBACK_DIR"
trap - EXIT
open "$DESTINATION"
echo "Installed $DESTINATION"
