#!/bin/bash
# Builds the installer of a new base: exports the macOS app (export preset "macOS") from a
# temporary copy of the project, then wraps it into an installer .dmg with make_dmg.sh.
# See "Updates" in CLAUDE.md: a new base is needed when project.godot, the engine,
# autoload/boot_patch.gd or the export preset change.
#
# Usage:
#   tools/make_base.sh [output.dmg] [--simple]
#
# The version is application/config/version in project.godot. The default output is
# build/AgencyOS-<version>.dmg. --simple is passed on to make_dmg.sh (no Finder layout).
# GODOT can point to the Godot binary (default: ~/Downloads/Godot.app).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT=""
DMG_ARGS=()
for arg in "$@"; do
	case "$arg" in
		--simple) DMG_ARGS+=("--simple") ;;
		*) OUTPUT="$arg" ;;
	esac
done

GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || GODOT="$(command -v godot || true)"
if [ -z "$GODOT" ]; then
	echo "Godot not found: set GODOT to its binary." >&2
	exit 1
fi

VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/project.godot")"
if [ -z "$VERSION" ]; then
	echo "Missing application/config/version in project.godot." >&2
	exit 1
fi
if [ -z "$OUTPUT" ]; then
	mkdir -p "$ROOT/build" && touch "$ROOT/build/.gdignore"
	OUTPUT="$ROOT/build/AgencyOS-$VERSION.dmg"
fi
mkdir -p "$(dirname "$OUTPUT")"
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Export from a copy, not from the folder open in the editor (.godot is kept: quicker import).
rsync -a --exclude .git --exclude /build "$ROOT/" "$WORK/project/"
# Twice: on a fresh checkout (CI) new SVGs need a second pass to be imported.
"$GODOT" --headless --path "$WORK/project" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$WORK/project" --import >/dev/null 2>&1 || true
APP="$WORK/AgencyOS.app"
"$GODOT" --headless --path "$WORK/project" --export-release macOS "$APP" >"$WORK/export.log" 2>&1 || true
if [ ! -d "$APP" ]; then
	cat "$WORK/export.log" >&2
	echo "Export failed." >&2
	exit 1
fi
EXPORTED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [ "$EXPORTED" != "$VERSION" ]; then
	echo "The exported app says $EXPORTED, project.godot says $VERSION." >&2
	exit 1
fi
echo "Exported AgencyOS $VERSION"

"$ROOT/tools/make_dmg.sh" "$APP" "$OUTPUT" "${DMG_ARGS[@]+"${DMG_ARGS[@]}"}"
