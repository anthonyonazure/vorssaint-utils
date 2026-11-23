# macArmyKnife

macArmyKnife is a personal, modified version of **Vorssaint**
(https://github.com/vorssaint/vorssaint-utils), © 2026 Vorssaint, licensed
under the GNU General Public License v3.0 or later. It is not an official
Vorssaint build and is not endorsed by the Vorssaint maintainer.

- Modified by: anthonyonazure
- Modifications started: 2026-11 (this rename: 2026-11-23)
- Source for this build: https://github.com/anthonyonazure/vorssaint-utils (branch `mak/main`)
- Licence: GPL-3.0-or-later, unchanged (see `LICENSE`). Original copyright
  headers are kept in every file.

## What this fork changes

Features added on top of Vorssaint:

- Cleaner tools: large files, duplicate files, startup items, a Cleaner tools
  window and Rescan.
- Uninstaller: select all, app sizes, last used, and sorting.
- Command bar quick tools: dice, random data, number bases, hashes, time zones,
  word definitions and remembered recent commands.
- Dynamic Island placement after the app menus on notched displays.

Identity, per the upstream `TRADEMARKS.md`:

- Its own name (macArmyKnife), icon, bundle identifier
  (`io.github.anthonyonazure.macarmyknife`), and self-signed signing identity
  ("macArmyKnife Signing").
- No update feed: the built-in updater is switched off so it can never install
  the official Vorssaint over this app. Upstream releases arrive through
  `scripts/sync-upstream.sh`, which merges each new Vorssaint release into
  `mak/main`, runs the tests, and only then rebuilds and reinstalls.
- In-app feedback is switched off (it would reach the Vorssaint maintainer).

## How it is built

`./build.sh --mak --install` builds and installs `/Applications/macArmyKnife.app`.
The rename is a thin layer so upstream releases keep merging cleanly:

- `Sources/Vorssaint/Core/ForkIdentity.swift` holds the name, bundle id and the
  switches; a handful of upstream files check it.
- `scripts/mak/` holds the icon generator, the signing setup, the bundle
  rebranding step and the staged string tables (the app's wording says
  macArmyKnife while the committed upstream text stays untouched).
- `Resources/MacArmyKnife/` holds the generated icon artwork.
