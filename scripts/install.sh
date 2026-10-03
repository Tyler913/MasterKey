#!/bin/bash
# Builds MasterKey and installs it as the only copy at /Applications/MasterKey.app.
#   --no-open            Install without launching.
#   --reset-permissions  Clear every macOS privacy entry for MasterKey, including
#                        stale ones left by earlier ad hoc signed builds.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="local.masterkey.bridge"
TARGET="/Applications/MasterKey.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
OPEN_APP=1
RESET_PERMISSIONS=0
for argument in "$@"; do
    case "$argument" in
        --no-open) OPEN_APP=0 ;;
        --reset-permissions) RESET_PERMISSIONS=1 ;;
        *) printf 'Usage: bash scripts/install.sh [--no-open] [--reset-permissions]\n' >&2; exit 1 ;;
    esac
done

bash scripts/build.sh

# The app handles SIGTERM as a normal quit and releases any held keys.
if pgrep -x MasterKey >/dev/null; then
    printf 'Quitting running MasterKey...\n'
    pkill -TERM -x MasterKey || true
    for _ in {1..50}; do pgrep -x MasterKey >/dev/null || break; sleep 0.1; done
    if pgrep -x MasterKey >/dev/null; then
        printf 'MasterKey did not quit. Quit it from its settings window and try again.\n' >&2
        exit 1
    fi
fi

# Move other copies to the Trash, then forget every registration that no longer
# exists so Launch Services only knows the installed copy.
move_to_trash() {
    local destination="$HOME/.Trash/$(basename "$1" .app) $(date +%Y%m%d-%H%M%S)-$RANDOM.app"
    mv "$1" "$destination"
    printf 'Moved to Trash: %s\n' "$1"
}
registered_paths() {
    "$LSREGISTER" -dump 2>/dev/null | awk -v id="$BUNDLE_ID" '
        /^-{10,}/ { if (match_id && path != "") print path; path = ""; match_id = 0; next }
        /^path:/ { sub(/^path:[ \t]+/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
        /^identifier:/ { if ($2 == id) match_id = 1 }
        END { if (match_id && path != "") print path }'
}
PROJECT_BUILD="$PWD/.build/"
while IFS= read -r copy; do
    [[ -z "$copy" || "$copy" == "$TARGET" || "$copy" == "$PROJECT_BUILD"* ]] && continue
    if [[ -d "$copy" ]]; then move_to_trash "$copy"; fi
done < <({ mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'"; registered_paths; } | sort -u)
while IFS= read -r path; do
    [[ -z "$path" || "$path" == "$TARGET" ]] && continue
    "$LSREGISTER" -u "$path" 2>/dev/null || true
done < <(registered_paths | sort -u)

mkdir -p "$PWD/.build/package.noindex"
INSTALL_STAGE="$(mktemp -d "$PWD/.build/package.noindex/XXXXXXXX")"
trap 'rm -rf "$INSTALL_STAGE"' EXIT
ditto -x -k dist/MasterKey.zip "$INSTALL_STAGE"
# Replace the bundle instead of merging into it so no files from older builds remain.
rm -rf "$TARGET"
ditto "$INSTALL_STAGE/MasterKey.app" "$TARGET"
codesign --verify --strict "$TARGET"
"$LSREGISTER" -f "$TARGET"
printf 'Installed: %s\n' "$TARGET"

if (( RESET_PERMISSIONS )); then
    # Each ad hoc signed build is a new code identity, so earlier grants no longer
    # apply. Clearing them leaves one fresh entry per permission after relaunch.
    tccutil reset All "$BUNDLE_ID"
    printf 'Cleared privacy permissions. Grant Accessibility and Input Monitoring again when MasterKey asks.\n'
fi

if (( OPEN_APP )); then open "$TARGET"; fi
