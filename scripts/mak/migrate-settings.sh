#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Part of macArmyKnife, a modified version of Vorssaint
# (https://github.com/vorssaint/vorssaint-utils), changed 2026-11-23.
#
# One-time copy of the Vorssaint (Developer) app's settings and data into
# macArmyKnife, before macArmyKnife's first launch:
#   - preferences (defaults domain com.vorssaint.utils.dev), through
#     `defaults export`/`import` so cfprefsd's live values are what moves;
#   - ~/Library/Application Support/com.vorssaint.utils.dev (clipboard history,
#     clipboard images, shelf files, price list), owner-only like the original;
#   - ~/Library/Caches/com.vorssaint.utils.dev (recent captures list, agent
#     usage archive).
# Nothing is moved or deleted: the Developer app keeps its copy.
#
# It refuses to run while either app is running, and it refuses to run twice
# (a marker records the copy), so a later reinstall can never overwrite newer
# macArmyKnife data with old Developer data. --force skips the marker check
# after backing up whatever macArmyKnife already has.
#
# Usage: scripts/mak/migrate-settings.sh [--force]
set -euo pipefail

FROM="com.vorssaint.utils.dev"
TO="io.github.anthonyonazure.macarmyknife"
SUPPORT="$HOME/Library/Application Support"
CACHES="$HOME/Library/Caches"
MARKER="$SUPPORT/$TO/.migrated-from-developer-app"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

running() { pgrep -f "/Contents/MacOS/$1( |$)" >/dev/null 2>&1; }

if running VorssaintDeveloper; then
    echo "✗ Vorssaint (Developer) is running; quit it first so its settings are flushed." >&2
    exit 1
fi
if running macArmyKnife; then
    echo "✗ macArmyKnife is running; quit it before copying settings into it." >&2
    exit 1
fi
if [[ -e "$MARKER" && $FORCE -eq 0 ]]; then
    echo "✓ Already copied on $(cat "$MARKER"); nothing to do (use --force to copy again)."
    exit 0
fi
if ! defaults export "$FROM" - >/dev/null 2>&1; then
    echo "✗ No settings found for $FROM." >&2
    exit 1
fi

STAMP="$(date '+%Y-%m-%d %H:%M:%S')"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Back up anything macArmyKnife already has before replacing it.
if defaults export "$TO" "$WORK/existing.plist" 2>/dev/null \
    && [[ "$(plutil -convert json -o - "$WORK/existing.plist" 2>/dev/null)" != "{}" ]]; then
    BACKUP="$SUPPORT/$TO-backup-$(date '+%Y%m%d-%H%M%S')"
    mkdir -p "$BACKUP"
    chmod 700 "$BACKUP"
    cp "$WORK/existing.plist" "$BACKUP/preferences.plist"
    [[ -d "$SUPPORT/$TO" ]] && ditto "$SUPPORT/$TO" "$BACKUP/Application Support"
    echo "  backed up existing macArmyKnife settings to $BACKUP"
fi

# Preferences. Simulation switches used for testing the Developer build have
# no meaning here and are dropped if present.
defaults export "$FROM" "$WORK/prefs.plist"
for key in simulateUpdate simulateBetaUI; do
    /usr/libexec/PlistBuddy -c "Delete :$key" "$WORK/prefs.plist" 2>/dev/null || true
done
defaults import "$TO" "$WORK/prefs.plist"
echo "  copied preferences ($(/usr/libexec/PlistBuddy -c Print "$WORK/prefs.plist" | grep -c ' = ') keys)"

# Application Support and Caches, merged over anything already there.
for base in "$SUPPORT" "$CACHES"; do
    if [[ -d "$base/$FROM" ]]; then
        mkdir -p "$base/$TO"
        chmod 700 "$base/$TO"
        ditto "$base/$FROM" "$base/$TO"
        echo "  copied ${base/#$HOME/~}/$FROM"
    fi
done

print -r -- "$STAMP from $FROM" > "$MARKER"
chmod 600 "$MARKER"
echo "✓ Settings and data copied into macArmyKnife."
