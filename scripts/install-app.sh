#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE_APP="$PROJECT_DIR/dist/AavAI.app"
USER_APPS_DIR="$HOME/Applications"
DESTINATION="$USER_APPS_DIR/AavAI.app"

"$PROJECT_DIR/scripts/build-app.sh"
mkdir -p "$USER_APPS_DIR"
if [[ -e "$DESTINATION" ]]; then
  BACKUP="$USER_APPS_DIR/AavAI.backup.$(date +%Y%m%d-%H%M%S).app"
  mv "$DESTINATION" "$BACKUP"
  echo "Previous app moved to $BACKUP"
fi
ditto "$SOURCE_APP" "$DESTINATION"
open "$DESTINATION"
echo "Installed $DESTINATION"
