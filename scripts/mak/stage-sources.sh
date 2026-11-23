#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Part of macArmyKnife, a modified version of Vorssaint
# (https://github.com/vorssaint/vorssaint-utils), changed 2026-11-23.
#
# Prints the app sources `./build.sh --mak` compiles: a staged copy of
# Sources/Vorssaint whose UI string tables say "macArmyKnife" where upstream
# says "Vorssaint". The committed sources stay identical to upstream, so
# merging a new upstream release never conflicts over wording.
#
# Scope, on purpose narrow:
#   - only the string tables (Core/*Strings.swift, Core/Localization.swift,
#     Core/Localizations/*.swift), never code that might use the name as data;
#   - only the whole word "Vorssaint" (identifiers such as
#     keepAwakeActiveIconVorssaint and file names such as libVorssaintNowPlaying
#     are untouched);
#   - entries that credit or ask support for the upstream project (donations,
#     GitHub stars, Discord, the official Homebrew cask) keep the Vorssaint name.
set -euo pipefail
cd "$(dirname "$0")/../.."

DEST="build/objects/mak-sources"   # build/objects survives release builds
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

rsync -a --delete Sources/Vorssaint/ "$TMP/Vorssaint/"

KEEP_KEYS='donate|supportIntro|discordIntro|homebrewOfficialIntro'
for f in "$TMP"/Vorssaint/Core/*Strings.swift(N) \
         "$TMP"/Vorssaint/Core/Localization.swift \
         "$TMP"/Vorssaint/Core/Localizations/*.swift(N); do
    rel="${f#$TMP/}"
    KEEP_KEYS="$KEEP_KEYS" perl -CSD -pi -e '
        next if /^\s*(?:$ENV{KEEP_KEYS})\w*\s*:/;
        s/\bVorssaint\b/macArmyKnife/g;
    ' "$f"
    # Keep the source modification time so incremental builds only recompile
    # tables whose upstream text actually changed.
    touch -r "Sources/$rel" "$f"
done

mkdir -p "$DEST"
rsync -a --checksum --delete "$TMP/Vorssaint/" "$DEST/Vorssaint/"
find "$DEST/Vorssaint" -name '*.swift' -type f | LC_ALL=C sort
