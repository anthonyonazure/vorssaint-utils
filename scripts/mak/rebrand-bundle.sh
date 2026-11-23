#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Part of macArmyKnife, a modified version of Vorssaint
# (https://github.com/vorssaint/vorssaint-utils), changed 2026-11-23.
#
# Finishes a staged macArmyKnife bundle before build.sh signs it. build.sh has
# already set the bundle id, name, executable and fan helper identity (shared
# with the Developer variant); this adds what only macArmyKnife needs:
#   - its own icon, menu bar glyph and in-app mark instead of Vorssaint's;
#   - permission prompts and the copyright line that name macArmyKnife;
#   - the GPL licence and the modification notice inside the app.
#
# Usage: scripts/mak/rebrand-bundle.sh <path/to/macArmyKnife.app>
set -euo pipefail
cd "$(dirname "$0")/../.."

BUNDLE="${1:?usage: rebrand-bundle.sh <bundle>}"
PLIST="$BUNDLE/Contents/Info.plist"
RES="$BUNDLE/Contents/Resources"
ART="Resources/MacArmyKnife"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }

# Icons. The adaptive Assets.car is compiled from Vorssaint's Icon Composer
# file and wins over AppIcon.icns whenever CFBundleIconName points at it, so
# drop both and let the Finder and Dock use the macArmyKnife .icns.
rm -f "$RES/Assets.car"
pb "Delete :CFBundleIconName" 2>/dev/null || true
pb "Set :CFBundleIconFile AppIcon"
for file in AppIcon.icns MenuBarIcon.png MenuBarIcon@2x.png BrandMark.png; do
    cp "$ART/$file" "$RES/$file"
done

# Permission prompts: macOS shows these strings when it asks for access, so
# they must name the app being approved.
for key in $(pb "Print" | sed -n 's/^    \(NS[A-Za-z]*UsageDescription\) = .*/\1/p'); do
    value="$(pb "Print :$key")"
    # plutil takes the value as its own argument, so apostrophes stay intact.
    plutil -replace "$key" -string "${value//Vorssaint/macArmyKnife}" "$PLIST"
done
for strings in "$RES"/*.lproj/InfoPlist.strings(N); do
    perl -CSD -pi -e 's/\bVorssaint\b/macArmyKnife/g' "$strings"
done
plutil -replace NSHumanReadableCopyright -string \
    "Based on Vorssaint © 2026 Vorssaint. macArmyKnife changes © 2026 anthonyonazure. GPL-3.0-or-later." "$PLIST"

# GPL: ship the licence and say this is a modified version.
cp LICENSE "$RES/LICENSE.txt"
cp MACARMYKNIFE.md "$RES/MACARMYKNIFE.md"

if grep -q 'Vorssaint' <(pb "Print" | grep 'UsageDescription'); then
    echo "✗ a permission prompt still names Vorssaint" >&2
    exit 1
fi
echo "  rebranded bundle as macArmyKnife"
