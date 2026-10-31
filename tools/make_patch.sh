#!/bin/bash
# Builds an update for AgencyOS: a Godot patch .pck with every file that changed since the
# installed app (the base), plus the update.json the app reads from the latest GitHub release.
# See "Updates" in CLAUDE.md.
#
# Usage:
#   tools/make_patch.sh <base AgencyOS.app or installer .dmg> [out_dir] [--notes "text"]
#
# The version is application/config/version in project.godot: bump it first.
# The export runs on a temporary copy of the project, not on the folder open in the editor.
# GODOT can point to the Godot binary (default: ~/Downloads/Godot.app).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE=""
OUT=""
NOTES=""

while [ $# -gt 0 ]; do
	case "$1" in
		--notes) NOTES="${2:-}"; shift ;;
		*) if [ -z "$SOURCE" ]; then SOURCE="$1"; else OUT="$1"; fi ;;
	esac
	shift
done

if [ -z "$SOURCE" ] || [ ! -e "$SOURCE" ]; then
	echo "Usage: $0 <AgencyOS.app | installer.dmg> [out_dir] [--notes \"text\"]" >&2
	exit 1
fi
if [ -z "$OUT" ]; then
	OUT="$ROOT/build/patch"
	mkdir -p "$ROOT/build" && touch "$ROOT/build/.gdignore"
fi

GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || GODOT="$(command -v godot || true)"
if [ -z "$GODOT" ]; then
	echo "Godot not found: set GODOT to its binary." >&2
	exit 1
fi

WORK="$(mktemp -d)"
MOUNTED=""
cleanup() {
	[ -n "$MOUNTED" ] && hdiutil detach "$MOUNTED" -quiet || true
	rm -rf "$WORK"
}
trap cleanup EXIT

# 1. The base: its .pck and the version it was exported with.
if [[ "$SOURCE" == *.dmg ]]; then
	MOUNTED="$WORK/base"
	hdiutil attach "$SOURCE" -nobrowse -readonly -mountpoint "$MOUNTED" -quiet
	APP="$(find "$MOUNTED" -maxdepth 1 -name '*.app' | head -1)"
else
	APP="$SOURCE"
fi
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
	echo "No app (.app) found in $SOURCE" >&2
	exit 1
fi
BASE_PCK="$(find "$APP/Contents/Resources" -maxdepth 1 -name '*.pck' | head -1)"
BASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
VERSION="$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/project.godot")"
if [ -z "$BASE_PCK" ] || [ -z "$VERSION" ]; then
	echo "Missing the base .pck or application/config/version in project.godot." >&2
	exit 1
fi
# The base version comes from Info.plist: with application/short_version empty in the export
# preset, Godot writes application/config/version there, the same value BootPatch reads at runtime.
LOWEST="$(printf '%s\n%s\n' "$BASE_VERSION" "$VERSION" | sort -V | head -1)"
if [ "$LOWEST" != "$BASE_VERSION" ]; then
	echo "The patch version ($VERSION) is older than the base ($BASE_VERSION): bump application/config/version." >&2
	exit 1
fi
echo "Base: $BASE_VERSION ($APP)"
echo "Patch: $VERSION"

# 2. Export the patch from a copy (.godot is kept, so the import is quick).
rsync -a --exclude .git --exclude /build "$ROOT/" "$WORK/project/"
FILE="agencyos-$VERSION.pck"
mkdir -p "$OUT"
# A .pck left by an earlier run must not pass for this export's output.
rm -f "$OUT/$FILE" "$OUT/update.json"
"$GODOT" --headless --path "$WORK/project" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$WORK/project" --export-patch macOS "$OUT/$FILE" --patches "$BASE_PCK" >"$WORK/export.log" 2>&1 || true
if [ ! -s "$OUT/$FILE" ]; then
	cat "$WORK/export.log" >&2
	echo "Export failed." >&2
	exit 1
fi

# 3. The manifest.
REPO="$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##' || true)"
[ -z "$REPO" ] && REPO="ehystiv/agency-os"
SHA="$(shasum -a 256 "$OUT/$FILE" | cut -d' ' -f1)"
SIZE="$(stat -f%z "$OUT/$FILE")"
# JSON string with quotes, escaped by JavaScriptCore (always there on macOS, like hdiutil).
NOTES_JSON="$(osascript -l JavaScript -e 'function run(argv) { return JSON.stringify(argv[0]) }' -- "$NOTES")"
cat >"$OUT/update.json" <<EOF
{
	"version": "$VERSION",
	"base": "$BASE_VERSION",
	"file": "$FILE",
	"url": "https://github.com/$REPO/releases/download/v$VERSION/$FILE",
	"sha256": "$SHA",
	"size": $SIZE,
	"notes": $NOTES_JSON,
	"page": "https://github.com/$REPO/releases/tag/v$VERSION"
}
EOF

echo
echo "Written $OUT/$FILE ($SIZE bytes) and $OUT/update.json"
echo "Publish with:"
echo "  gh release create v$VERSION \"$OUT/$FILE\" \"$OUT/update.json\" --title \"AgencyOS 98 $VERSION\" --notes-file <notes>"
