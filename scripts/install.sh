#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--no-open" ) ]]; then
    printf 'Usage: bash scripts/install.sh [--no-open]\n' >&2
    exit 1
fi
if pgrep -x MasterKey >/dev/null; then
    printf 'Please quit MasterKey from its settings window before installing.\n' >&2
    exit 1
fi
bash scripts/build.sh
mkdir -p "$PWD/.build/package.noindex"
INSTALL_STAGE="$(mktemp -d "$PWD/.build/package.noindex/XXXXXXXX")"
trap 'rm -rf "$INSTALL_STAGE"' EXIT
ditto -x -k dist/MasterKey.zip "$INSTALL_STAGE"
ditto "$INSTALL_STAGE/MasterKey.app" /Applications/MasterKey.app
codesign --verify --strict /Applications/MasterKey.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/MasterKey.app
printf 'Installed: /Applications/MasterKey.app\n'
if [[ "${1:-}" != "--no-open" ]]; then open /Applications/MasterKey.app; fi
