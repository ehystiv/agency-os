#!/bin/bash
# Builds an "installer" .dmg of AgencyOS: the app and, next to it, a shortcut to
# Applications to drag it onto. Uses only macOS tools (hdiutil, osascript).
#
# Usage:
#   tools/make_dmg.sh <AgencyOS.app or the .dmg exported by Godot> [output.dmg] [--simple]
#
# --simple skips arranging the icons in the Finder window
# (the first time macOS asks for permission to control the Finder).

set -euo pipefail

VOLUME="AgencyOS"
SOURCE=""
OUTPUT=""
LAYOUT=1

for arg in "$@"; do
	case "$arg" in
		--simple) LAYOUT=0 ;;
		*) if [ -z "$SOURCE" ]; then SOURCE="$arg"; else OUTPUT="$arg"; fi ;;
	esac
done

if [ -z "$SOURCE" ] || [ ! -e "$SOURCE" ]; then
	echo "Usage: $0 <AgencyOS.app | AgencyOS.dmg> [output.dmg] [--simple]" >&2
	exit 1
fi

WORK="$(mktemp -d)"
STAGE="$WORK/$VOLUME"
MOUNTED_SOURCE=""
MOUNTED_RW=""
cleanup() {
	[ -n "$MOUNTED_RW" ] && hdiutil detach "$MOUNTED_RW" -quiet || true
	[ -n "$MOUNTED_SOURCE" ] && hdiutil detach "$MOUNTED_SOURCE" -quiet || true
	rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$STAGE"

# 1. Get the app: directly, or from Godot's .dmg.
if [[ "$SOURCE" == *.dmg ]]; then
	MOUNTED_SOURCE="$WORK/source"
	hdiutil attach "$SOURCE" -nobrowse -readonly -mountpoint "$MOUNTED_SOURCE" -quiet
	APP="$(find "$MOUNTED_SOURCE" -maxdepth 1 -name '*.app' | head -1)"
else
	APP="$SOURCE"
fi
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
	echo "No app (.app) found in $SOURCE" >&2
	exit 1
fi
APP_NAME="$(basename "$APP")"
[ -z "$OUTPUT" ] && OUTPUT="$(dirname "$SOURCE")/${APP_NAME%.app}-installer.dmg"

echo "App: $APP"
ditto "$APP" "$STAGE/$APP_NAME"
ln -s /Applications "$STAGE/Applicazioni"
if [ -n "$MOUNTED_SOURCE" ]; then
	hdiutil detach "$MOUNTED_SOURCE" -quiet
	MOUNTED_SOURCE=""
fi

# With another "AgencyOS" disk mounted the Finder wouldn't know which one to arrange.
if [ "$LAYOUT" -eq 1 ] && [ -d "/Volumes/$VOLUME" ]; then
	echo "A \"$VOLUME\" disk is already mounted: eject it to get the icons arranged. Going on without."
	LAYOUT=0
fi

# 2. Writable image, so the Finder window can be arranged.
RW="$WORK/rw.dmg"
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW" -quiet

if [ "$LAYOUT" -eq 1 ]; then
	MOUNTED_RW="/Volumes/$VOLUME"
	hdiutil attach "$RW" -noautoopen -quiet
	# Window without bars, large icons: the app on the left, Applications on the right.
	# The link keeps the Italian name: it is what the user sees in the Finder.
	if ! osascript <<OSA
tell application "Finder"
	tell disk "$VOLUME"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {200, 120, 760, 460}
		set viewOptions to the icon view options of container window
		set arrangement of viewOptions to not arranged
		set icon size of viewOptions to 128
		set position of item "$APP_NAME" of container window to {150, 160}
		set position of item "Applicazioni" of container window to {410, 160}
		update without registering applications
		delay 1
		close
	end tell
end tell
OSA
	then
		echo "Icon layout failed (Finder permission denied?): the .dmg works anyway."
	fi
	sync
	hdiutil detach "$MOUNTED_RW" -quiet
	MOUNTED_RW=""
fi

# 3. Final compressed, read-only version.
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$OUTPUT" -quiet
echo "Created: $OUTPUT"
