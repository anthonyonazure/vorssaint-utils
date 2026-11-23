#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Part of macArmyKnife, a modified version of Vorssaint
# (https://github.com/vorssaint/vorssaint-utils), changed 2026-11-23.
#
# Brings the newest Vorssaint release into macArmyKnife, safely:
#
#   1. fetch upstream (remote "origin") and the fork (remote "fork");
#   2. find the newest upstream release tag (stable vX.Y.Z only, unless
#      --include-betas) and stop quietly if mak/main already contains it;
#   3. in a separate scratch worktree, merge that tag into a copy of mak/main;
#   4. run the full test suite, build macArmyKnife, and check the built app
#      (identity, signature, and that the fork's own features are inside);
#   5. only then: quit macArmyKnife, swap in the new app (keeping the previous
#      one as a backup), relaunch it, and confirm it is running;
#   6. only after all of that: move mak/main forward and push it to the fork
#      with a normal push (never a force push).
#
# On a merge conflict, red tests, a failed build or a failed check, nothing
# installed changes, mak/main does not move, a report explains what happened,
# and the script exits non-zero. If the new app will not start, the previous
# app is put back and relaunched.
#
# Settings survive updates: they live under the app's bundle id, and the
# signing certificate stays the same, so macOS keeps its permission grants.
#
# Usage: scripts/sync-upstream.sh [options]
#   --target <ref>     merge this ref instead of the newest release tag
#   --include-betas    also consider beta and release-candidate tags
#   --reinstall        rebuild and reinstall mak/main even with no new release
#   --no-install       stop after the verified build (a rehearsal)
#   --no-push          do not push mak/main to the fork
#   --notify           post a macOS notification when something happened
#
# Exit codes: 0 updated or nothing to do · 2 merge conflict · 3 another sync
# is running · 4 repository not ready (dirty, wrong branch, diverged) · 5 tests
# failed · 6 build failed · 7 built app failed its checks · 8 install or
# relaunch failed (previous app restored).
#
# Report of the last run: ~/Library/Logs/macArmyKnife/last-sync-report.md
setopt pipefail no_unset
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin${PATH:+:$PATH}"

# ---------------------------------------------------------------- settings
APP_NAME="macArmyKnife"
BUNDLE_ID="io.github.anthonyonazure.macarmyknife"
SIGNING_IDENTITY="macArmyKnife Signing"
BRANCH="mak/main"
APP="/Applications/$APP_NAME.app"
LOG_DIR="$HOME/Library/Logs/macArmyKnife"
STATE_DIR="$HOME/Library/Application Support/macArmyKnife-sync"
CACHE_DIR="$HOME/Library/Caches/macArmyKnife-sync"
WT="$CACHE_DIR/worktree"
BACKUP_APP="$STATE_DIR/previous/$APP_NAME.app"
REPORT="$LOG_DIR/last-sync-report.md"

# Strings inside the built program that prove the fork's own features made
# it in. A build from the wrong branch silently dropped the cleaner tools
# once; this check stops that from ever being installed again.
FEATURE_MARKERS=(
    "LargeFileFinder:Cleaner large files"
    "DuplicateFileFinder:Cleaner duplicates"
    "StartupItemsManager:Cleaner startup items"
    "CleanerToolsWindowController:Cleaner tools window"
    "cleanerRescan:Cleaner rescan"
    "notchAfterMenus:Island after the app menus"
    "CommandBarToolAnswer:Command bar quick tools"
)

TARGET_OVERRIDE=""
INCLUDE_BETAS=0
REINSTALL=0
NO_INSTALL=0
NO_PUSH=0
NOTIFY=0
while (( $# )); do
    case "$1" in
        --target) TARGET_OVERRIDE="${2:?--target needs a ref}"; shift ;;
        --include-betas) INCLUDE_BETAS=1 ;;
        --reinstall) REINSTALL=1 ;;
        --no-install) NO_INSTALL=1 ;;
        --no-push) NO_PUSH=1 ;;
        --notify) NOTIFY=1 ;;
        -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
        *) print -u2 "unknown option: $1"; exit 64 ;;
    esac
    shift
done

REPO="$(git -C "${0:A:h}" rev-parse --show-toplevel 2>/dev/null)" || { print -u2 "not inside the macArmyKnife checkout"; exit 4; }
mkdir -p "$LOG_DIR" "$STATE_DIR" "$CACHE_DIR"
STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG="$LOG_DIR/sync-$STAMP.log"
exec > >(tee -a "$LOG") 2>&1
# Keep two months of logs.
find "$LOG_DIR" -name 'sync-*.log' -mtime +60 -delete 2>/dev/null

say() { print -r -- "[$(date '+%H:%M:%S')] $*"; }

# report <exit-code> <one-line outcome> <details markdown>
report() {
    local code="$1" outcome="$2" details="${3:-}"
    {
        print -r -- "# macArmyKnife sync: $outcome"
        print -r -- ""
        print -r -- "- When: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        print -r -- "- Result code: $code"
        print -r -- "- Upstream release considered: ${TARGET:-none}"
        print -r -- "- mak/main now: $(git -C "$REPO" rev-parse --short "$BRANCH" 2>/dev/null)"
        print -r -- "- Installed app: $(installed_summary)"
        print -r -- "- Full log: $LOG"
        print -r -- ""
        [[ -n "$details" ]] && print -r -- "$details"
    } > "$REPORT"
    say "report written to $REPORT"
    if (( NOTIFY )) && [[ "$code" != 0 || "$outcome" == Updated* ]]; then
        /usr/bin/osascript -e "display notification \"$outcome\" with title \"macArmyKnife sync\"" >/dev/null 2>&1 || true
    fi
}

installed_summary() {
    [[ -d "$APP" ]] || { print -r -- "not installed"; return; }
    local version stamp
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
    stamp="$(/usr/libexec/PlistBuddy -c 'Print :VorssaintBuildCommit' "$APP/Contents/Info.plist" 2>/dev/null)"
    print -r -- "$APP_NAME $version (built from ${stamp:-unknown})"
}

finish() { local code="$1"; say "done (exit $code)"; exit "$code"; }

# ---------------------------------------------------------------- lock
LOCK="$STATE_DIR/sync.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    if [[ -f "$LOCK/pid" ]] && ! kill -0 "$(cat "$LOCK/pid")" 2>/dev/null; then
        rm -rf "$LOCK"; mkdir "$LOCK"
    else
        say "another sync is running (lock $LOCK)"
        exit 3
    fi
fi
print $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT
trap 'exit 130' INT TERM HUP

say "macArmyKnife sync starting in $REPO"

# ---------------------------------------------------------------- preflight
current_branch="$(git -C "$REPO" symbolic-ref --quiet --short HEAD 2>/dev/null)"
if [[ "$current_branch" != "$BRANCH" ]]; then
    report 4 "Not run: checkout is not on $BRANCH" "The checkout at \`$REPO\` is on \`${current_branch:-detached HEAD}\`. Switch it back to \`$BRANCH\`."
    finish 4
fi
if [[ -n "$(git -C "$REPO" status --porcelain --untracked-files=no)" ]] \
    || [[ -e "$(git -C "$REPO" rev-parse --git-path MERGE_HEAD)" ]]; then
    report 4 "Not run: the checkout has uncommitted changes" "Commit or discard the changes in \`$REPO\` first:

\`\`\`
$(git -C "$REPO" status --short --untracked-files=no)
\`\`\`"
    finish 4
fi

say "fetching upstream and fork"
if ! git -C "$REPO" fetch --quiet origin --tags || ! git -C "$REPO" fetch --quiet fork; then
    report 4 "Not run: could not fetch from GitHub" "Network or GitHub trouble; nothing changed. The next run will try again."
    finish 4
fi

# The fork may hold commits made elsewhere; take them, but never rewrite.
if git -C "$REPO" rev-parse --verify --quiet "fork/$BRANCH" >/dev/null; then
    if ! git -C "$REPO" merge-base --is-ancestor "fork/$BRANCH" "$BRANCH"; then
        if git -C "$REPO" merge-base --is-ancestor "$BRANCH" "fork/$BRANCH"; then
            say "fast-forwarding $BRANCH to fork/$BRANCH"
            git -C "$REPO" merge --quiet --ff-only "fork/$BRANCH" || { report 4 "Not run: could not fast-forward to the fork" ""; finish 4; }
        else
            report 4 "Not run: $BRANCH and fork/$BRANCH have diverged" "Local \`$BRANCH\` and the fork's copy both have commits the other lacks. A person needs to merge them; this script never force-pushes."
            finish 4
        fi
    fi
fi

push_branch() {
    (( NO_PUSH )) && { say "not pushing (--no-push)"; return 0; }
    if git -C "$REPO" rev-parse --verify --quiet "fork/$BRANCH" >/dev/null \
        && [[ "$(git -C "$REPO" rev-parse "fork/$BRANCH")" == "$(git -C "$REPO" rev-parse "$BRANCH")" ]]; then
        return 0
    fi
    say "pushing $BRANCH to the fork"
    git -C "$REPO" push --quiet fork "$BRANCH:$BRANCH"
}

# ---------------------------------------------------------------- target
latest_release_tag() {
    git -C "$REPO" tag -l 'v*' | /usr/bin/python3 -c '
import re, sys
include_betas = sys.argv[1] == "1"
best = None
for tag in sys.stdin.read().split():
    m = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)(?:-(alpha|beta|rc)\.(\d+))?", tag)
    if not m or (m.group(4) and not include_betas):
        continue
    pre = (0, ("alpha", "beta", "rc").index(m.group(4)), int(m.group(5))) if m.group(4) else (1, 0, 0)
    key = (int(m.group(1)), int(m.group(2)), int(m.group(3))) + pre
    if best is None or key > best[0]:
        best = (key, tag)
print(best[1] if best else "")
' "$INCLUDE_BETAS"
}

BASE_SHA="$(git -C "$REPO" rev-parse "$BRANCH")"
TARGET="${TARGET_OVERRIDE:-$(latest_release_tag)}"
if [[ -z "$TARGET" ]] || ! git -C "$REPO" rev-parse --verify --quiet "$TARGET^{commit}" >/dev/null; then
    report 4 "Not run: no upstream release found" "Could not resolve \`${TARGET:-a release tag}\`."
    finish 4
fi
TARGET_SHA="$(git -C "$REPO" rev-parse "$TARGET^{commit}")"

NEED_MERGE=1
git -C "$REPO" merge-base --is-ancestor "$TARGET_SHA" "$BASE_SHA" && NEED_MERGE=0
if (( ! NEED_MERGE && ! REINSTALL )); then
    say "$BRANCH already includes $TARGET; nothing to do"
    push_note=""
    if ! push_branch; then push_note="Pushing $BRANCH to the fork failed; the next run will try again."; fi
    report 0 "Up to date (already includes $TARGET)" "${push_note:-No new upstream release since the last sync. Nothing was changed.}"
    finish 0
fi

# ---------------------------------------------------------------- scratch worktree
say "preparing the scratch worktree"
if ! git -C "$WT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$REPO" worktree prune
    [[ -e "$WT" ]] && rm -rf "$WT"
    git -C "$REPO" worktree add --quiet --detach "$WT" "$BASE_SHA" || { report 4 "Not run: could not create the scratch worktree" ""; finish 4; }
fi
git -C "$WT" merge --abort >/dev/null 2>&1
git -C "$WT" checkout --quiet --detach --force "$BASE_SHA" && git -C "$WT" clean -fdq
CANDIDATE_SHA="$BASE_SHA"

if (( NEED_MERGE )); then
    say "merging $TARGET into a copy of $BRANCH"
    if ! git -C "$WT" merge --quiet --no-ff --no-edit -m "Merge upstream release $TARGET into $BRANCH" "$TARGET_SHA"; then
        conflicts="$(git -C "$WT" diff --name-only --diff-filter=U)"
        git -C "$WT" merge --abort >/dev/null 2>&1
        report 2 "Stopped: merging $TARGET conflicts with macArmyKnife's changes" "Nothing installed was changed and \`$BRANCH\` did not move.

These files changed both upstream and in macArmyKnife and need a person to combine them:

\`\`\`
$conflicts
\`\`\`

To resolve: in \`$REPO\`, run \`git merge $TARGET\`, fix the files above keeping both sides' intent, run \`./build.sh --test\`, commit, then run this script again."
        finish 2
    fi
    CANDIDATE_SHA="$(git -C "$WT" rev-parse HEAD)"
fi

# New hard-coded Vorssaint bundle ids arriving from upstream can mean a new
# "is this our own app?" check that does not know about macArmyKnife yet.
identity_notes=""
if (( NEED_MERGE )); then
    new_ids="$(git -C "$WT" diff "$BASE_SHA" "$CANDIDATE_SHA" -- Sources \
        | grep -E '^\+[^+].*"com\.vorssaint\.utils(\.dev)?"' | grep -v 'label:' | head -20)"
    if [[ -n "$new_ids" ]]; then
        identity_notes="Worth a look: this release adds code that names the Vorssaint bundle id directly. If it is an \"is this our own app\" check, macArmyKnife may need adding to it (see \`ForkIdentity.isOwnBundleID\`).

\`\`\`
$new_ids
\`\`\`"
    fi
fi

# ---------------------------------------------------------------- tests
say "running the full test suite"
if ! (cd "$WT" && ./build.sh --test > "$CACHE_DIR/test-output.log" 2>&1); then
    failed="$(grep -E 'FAILED|✗|error:|^  - ' "$CACHE_DIR/test-output.log" | head -40)"
    cp "$CACHE_DIR/test-output.log" "$LOG_DIR/sync-$STAMP-tests.log"
    report 5 "Stopped: tests failed after merging $TARGET" "Nothing installed was changed and \`$BRANCH\` did not move.

\`\`\`
$failed
\`\`\`

Full test output: $LOG_DIR/sync-$STAMP-tests.log

$identity_notes"
    finish 5
fi
checks="$(grep -E '^TESTS OK' "$CACHE_DIR/test-output.log" | tail -1)"
say "tests passed: $checks"

# ---------------------------------------------------------------- build
say "building $APP_NAME"
if ! (cd "$WT" && ./build.sh --mak > "$CACHE_DIR/build-output.log" 2>&1); then
    cp "$CACHE_DIR/build-output.log" "$LOG_DIR/sync-$STAMP-build.log"
    report 6 "Stopped: the build failed after merging $TARGET" "Tests passed, but building the app failed. Nothing installed was changed and \`$BRANCH\` did not move.

\`\`\`
$(grep -E 'error|✗' "$CACHE_DIR/build-output.log" | head -30)
\`\`\`

Full build output: $LOG_DIR/sync-$STAMP-build.log"
    finish 6
fi
BUILT="$WT/build/stage.noindex/$APP_NAME.app"

# ---------------------------------------------------------------- verify the built app
problems=()
plist="$BUILT/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null; }
[[ -d "$BUILT" ]] || problems+=("no app bundle at $BUILT")
[[ "$(pb CFBundleIdentifier)" == "$BUNDLE_ID" ]] || problems+=("bundle id is '$(pb CFBundleIdentifier)'")
[[ "$(pb CFBundleName)" == "$APP_NAME" ]] || problems+=("name is '$(pb CFBundleName)'")
pb CFBundleIconName >/dev/null && problems+=("still points at the Vorssaint adaptive icon")
codesign --verify --deep --strict "$BUILT" 2>/dev/null || problems+=("signature does not verify")
codesign -dvv "$BUILT" 2>&1 | grep -q "^Authority=$SIGNING_IDENTITY\$" || problems+=("not signed by $SIGNING_IDENTITY")
binary="$BUILT/Contents/MacOS/$APP_NAME"
for marker in "${FEATURE_MARKERS[@]}"; do
    grep -q -a -- "${marker%%:*}" "$binary" 2>/dev/null || problems+=("missing feature: ${marker#*:}")
done
if (( ${#problems} )); then
    report 7 "Stopped: the new build failed its checks" "Nothing installed was changed and \`$BRANCH\` did not move.

$(printf -- '- %s\n' "${problems[@]}")"
    finish 7
fi
say "built app verified: $(pb CFBundleShortVersionString), $(pb VorssaintBuildCommit)"

if (( NO_INSTALL )); then
    report 0 "Rehearsal passed for $TARGET (not installed)" "Merge, ${checks:-tests} and build all passed in the scratch worktree. Nothing was installed and \`$BRANCH\` did not move (--no-install).

$identity_notes"
    finish 0
fi

# ---------------------------------------------------------------- install
app_running() { pgrep -x "$APP_NAME" >/dev/null 2>&1; }
stop_app() {
    app_running || return 0
    pkill -x "$APP_NAME" 2>/dev/null
    for _ in {1..100}; do app_running || return 0; sleep 0.1; done
    return 1
}
sign_installed() {
    local helper="$APP/Contents/Library/LaunchServices/$BUNDLE_ID.fan-control"
    local adapter="$APP/Contents/Frameworks/libVorssaintNowPlaying.dylib"
    security unlock-keychain -p macarmyknife-signing "$HOME/Library/Keychains/macarmyknife-signing.keychain-db" 2>/dev/null
    if [[ -f "$helper" ]]; then
        codesign --force --strip-disallowed-xattrs --identifier "$BUNDLE_ID.fan-control" \
            --sign "$SIGNING_IDENTITY" "$helper" || return 1
    fi
    if [[ -f "$adapter" ]]; then
        codesign --force --strip-disallowed-xattrs --identifier "$BUNDLE_ID.now-playing" \
            --sign "$SIGNING_IDENTITY" "$adapter" || return 1
    fi
    codesign --force --strip-disallowed-xattrs --sign "$SIGNING_IDENTITY" "$APP"
}
restore_previous() {
    say "restoring the previous app"
    stop_app
    rm -rf "$APP"
    if [[ -d "$BACKUP_APP" ]]; then
        mv "$BACKUP_APP" "$APP" && open "$APP"
    fi
}

was_running=0
app_running && was_running=1
say "installing (the app quits for a few seconds)"
mkdir -p "${BACKUP_APP:h}"
rm -rf "$BACKUP_APP"
if ! stop_app; then
    report 8 "Stopped: could not quit the running app" "Nothing installed was changed and \`$BRANCH\` did not move."
    finish 8
fi
# A rename, not a copy: the previous app stays byte for byte as it was, so
# putting it back cannot disturb its signature.
[[ -d "$APP" ]] && mv "$APP" "$BACKUP_APP"
install_ok=1
ditto --noextattr --noqtn "$BUILT" "$APP" || install_ok=0
if (( install_ok )); then
    # Copying into /Applications adds file metadata after the fact; sign the
    # installed copy again once it has settled, as build.sh --install does.
    sleep 3
    xattr -cr "$APP" 2>/dev/null
    sign_installed && codesign --verify --deep --strict "$APP" 2>/dev/null || install_ok=0
fi
if (( ! install_ok )); then
    restore_previous
    report 8 "Stopped: installing the new app failed; previous app restored" "\`$BRANCH\` did not move."
    finish 8
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1

say "relaunching $APP_NAME"
open "$APP"
started=0
for _ in {1..30}; do app_running && { started=1; break; }; sleep 1; done
# Still running a little later means it did not crash on launch.
(( started )) && { sleep 8; app_running || started=0; }
if (( ! started )); then
    restore_previous
    report 8 "Stopped: the new app did not stay running; previous app restored" "\`$BRANCH\` did not move. Check Console for a $APP_NAME crash report."
    finish 8
fi

# ---------------------------------------------------------------- advance and push
push_note="Pushed \`$BRANCH\` to the fork."
if [[ "$CANDIDATE_SHA" != "$BASE_SHA" ]]; then
    if ! git -C "$REPO" merge --quiet --ff-only "$CANDIDATE_SHA"; then
        report 4 "Installed, but could not move $BRANCH forward" "The new app is installed and running, but \`$REPO\` changed during the sync. The merge commit is \`$CANDIDATE_SHA\`; fast-forward \`$BRANCH\` to it by hand."
        finish 4
    fi
fi
push_branch || push_note="Pushing \`$BRANCH\` to the fork failed; the next run will try again."

outcome="Updated to $TARGET"
(( NEED_MERGE )) || outcome="Reinstalled $BRANCH (already included $TARGET)"
report 0 "$outcome" "- Tests: ${checks:-passed}
- Previous app kept at: $BACKUP_APP
- $push_note

$identity_notes"
finish 0
