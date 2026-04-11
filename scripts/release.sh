#!/bin/bash
# Release a new version of Xdigest to GitHub.
#
# Usage:
#   ./scripts/release.sh           # auto-bump minor (e.g. 0.1.0 -> 0.2.0)
#   ./scripts/release.sh 0.5.0     # explicit version
#
# What it does:
#   1. Preflight checks (main branch, clean tree, synced with origin,
#      gh CLI authenticated, tag unused, valid semver)
#   2. Full security audit (gitleaks working tree + history)
#   3. Write new version + timestamp build number into Info.plist
#   4. Build + sign + notarize the DMG via make-dmg.sh
#   5. Commit the version bump (only after the build succeeds)
#   6. Tag + push commit + push tag
#   7. Create GitHub release with the DMG attached + auto-generated notes
#
# Recovery:
#
#   Build fails (notarization rejected, signing error, etc.):
#     The trap auto-reverts Info.plist. Nothing committed, nothing to
#     undo. Fix the underlying issue and re-run.
#
#   Build succeeds but commit fails:
#     Trap reverts Info.plist. Re-run.
#
#   Commit succeeds but push fails:
#     git reset --hard HEAD~1
#     (local commit only; no remote changes to undo.)
#
#   Commit pushed but tag push failed:
#     git tag -d v$VERSION
#     git reset --hard origin/main
#     (but origin/main now has the commit; either force-revert on the
#      remote via a new commit, or accept the commit as sunk cost and
#      re-run release.sh with the next version.)
#
#   Tag pushed but `gh release create` failed:
#     git push origin :refs/tags/v$VERSION   # delete remote tag
#     git tag -d v$VERSION                   # delete local tag
#     git reset --hard HEAD~1                # undo local commit
#     git push --force-with-lease            # undo remote commit
#     Re-run.

set -euo pipefail

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INFO_PLIST="$PROJECT_DIR/Sources/XdigestApp/Info.plist"
APPCAST="$PROJECT_DIR/appcast.xml"
DMG_PATH="$PROJECT_DIR/dist/Xdigest.dmg"
RELEASE_BRANCH="main"
REPO_SLUG="webcpu/Xdigest"
APPCAST_URL="https://raw.githubusercontent.com/$REPO_SLUG/$RELEASE_BRANCH/appcast.xml"

# -----------------------------------------------------------------------------
# Helpers (mirror make-dmg.sh for consistency)
# -----------------------------------------------------------------------------

log()    { printf '==> %s\n' "$*"; }
detail() { sed 's/^/    /'; }
die()    { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Trap: if we modified Info.plist or wrote appcast.xml but haven't
# committed the changes yet, restore them so a failed build doesn't
# leave the tree dirty. For appcast.xml specifically: if the file did
# not exist in HEAD (first-ever release), delete it; otherwise restore
# from HEAD. The PREEXISTS flag is set during preflight.
INFO_PLIST_DIRTY=0
APPCAST_DIRTY=0
APPCAST_PREEXISTS=0
cleanup_dirty_files() {
    if [ "$INFO_PLIST_DIRTY" = "1" ]; then
        git checkout -- "$INFO_PLIST" 2>/dev/null || true
    fi
    if [ "$APPCAST_DIRTY" = "1" ]; then
        if [ "$APPCAST_PREEXISTS" = "1" ]; then
            git checkout -- "$APPCAST" 2>/dev/null || true
        else
            rm -f "$APPCAST"
        fi
    fi
}
trap cleanup_dirty_files EXIT

# -----------------------------------------------------------------------------
# Args
# -----------------------------------------------------------------------------

# Reads CFBundleShortVersionString from the repo's Info.plist. Used as
# a fallback when the remote appcast can't be reached.
current_version_from_info_plist() {
    [ -f "$INFO_PLIST" ] || die "Info.plist not found at $INFO_PLIST"
    plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST" 2>/dev/null \
        || die "couldn't read CFBundleShortVersionString from $INFO_PLIST"
}

# Fetches the remote appcast.xml on origin/main and prints the
# <sparkle:shortVersionString> from its first <item>. Prints nothing on
# 404, network failure, or parse failure -- the caller detects this via
# the empty output and falls back to the local Info.plist.
#
# Regex assumes single-line `<sparkle:shortVersionString>VALUE</...>`.
# The writer (this same script) always emits it on one line; don't
# pretty-print appcast.xml without adjusting this regex.
#
# Trailing `|| true` is required: with `set -o pipefail`, grep's
# non-zero exit on no-match would terminate the script via `set -e`.
current_version_from_remote_appcast() {
    local xml
    xml=$(curl -sfL --max-time 10 "$APPCAST_URL" 2>/dev/null) || return 0
    printf '%s' "$xml" \
        | grep -oE '<sparkle:shortVersionString>[^<]+</sparkle:shortVersionString>' \
        | head -1 \
        | sed -E 's/<[^>]+>//g' 2>/dev/null \
        || true
}

VERSION=${1:-}
if [ -z "$VERSION" ]; then
    # No argument: read the "current" version. The authoritative source
    # is the remote appcast.xml on origin/main -- that's what's actually
    # been released. If the remote doesn't exist yet (first release) or
    # can't be reached, fall back to the committed Info.plist.
    CURRENT=$(current_version_from_remote_appcast)
    if [ -n "$CURRENT" ]; then
        log "Remote appcast.xml says latest is $CURRENT"
    else
        CURRENT=$(current_version_from_info_plist)
        log "No remote appcast found; using local Info.plist ($CURRENT)"
    fi
    if ! [[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        die "can't auto-bump: current version '$CURRENT' isn't major.minor.patch"
    fi
    VERSION="${BASH_REMATCH[1]}.$((BASH_REMATCH[2] + 1)).0"
    log "Auto-bumping minor: $CURRENT -> $VERSION"
fi

# Strict semver: major.minor.patch, digits only. Catches bad explicit
# args and is a defense-in-depth check on the auto-bump output.
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "VERSION must be major.minor.patch (e.g. 0.2.0), got: $VERSION"

TAG="v$VERSION"

cd "$PROJECT_DIR"

# -----------------------------------------------------------------------------
# Preflight: fail fast before any side effects
# -----------------------------------------------------------------------------

log "Preflight"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "$RELEASE_BRANCH" ] \
    || die "not on $RELEASE_BRANCH (currently on $BRANCH)"

[ -z "$(git status --porcelain)" ] \
    || die "working tree is not clean -- commit or stash first"

command -v gh >/dev/null 2>&1 \
    || die "gh CLI not found (install with: brew install gh)"

gh auth status >/dev/null 2>&1 \
    || die "gh CLI not authenticated (run: gh auth login)"

if git rev-parse --verify "$TAG" >/dev/null 2>&1; then
    die "tag $TAG already exists locally"
fi

[ -f "$INFO_PLIST" ] || die "Info.plist not found at $INFO_PLIST"

# Record whether appcast.xml existed before we started, so the trap
# knows how to clean up (restore from HEAD vs. delete).
[ -f "$APPCAST" ] && APPCAST_PREEXISTS=1

# Sync check: make sure origin/main isn't ahead of us. Without this, the
# post-build `git push` fails after 3-8 minutes of wasted notarization.
git fetch origin "$RELEASE_BRANCH" 2>&1 | detail
if ! git merge-base --is-ancestor "origin/$RELEASE_BRANCH" HEAD; then
    die "origin/$RELEASE_BRANCH has commits not in local HEAD (run: git pull)"
fi

# Remote tag check (exact match via refspec, no grep).
if [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
    die "tag $TAG already exists on origin"
fi

printf '    all checks passed\n'

# -----------------------------------------------------------------------------
# Security audit (full history -- a push is irrevocable for secrets)
# -----------------------------------------------------------------------------

log "Security audit"
"$SCRIPT_DIR/security-check.sh" 2>&1 | detail

# -----------------------------------------------------------------------------
# Write Info.plist (NOT committed yet -- build first, then commit)
# -----------------------------------------------------------------------------

# Format: YYYYMMDD.HHMMSS in UTC. Monotonic by construction. Apple's
# CFBundleVersion comparator treats period-separated segments as
# integers, so (20260411, 183310) < (20260411, 183311) < (20260412, 000000).
# Don't change this format without updating CFBundleVersion-aware consumers.
BUILD=$(date -u +%Y%m%d.%H%M%S)

log "Writing Info.plist: version=$VERSION build=$BUILD"
INFO_PLIST_DIRTY=1
plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
plutil -replace CFBundleVersion -string "$BUILD" "$INFO_PLIST"
plutil -lint "$INFO_PLIST" >/dev/null || die "Info.plist is invalid after bump"

# -----------------------------------------------------------------------------
# Build notarized DMG (reads version + build from the uncommitted Info.plist)
# -----------------------------------------------------------------------------

log "Building notarized DMG (this takes 3-8 minutes including notarization)"
"$SCRIPT_DIR/make-dmg.sh" 2>&1 | detail

[ -f "$DMG_PATH" ] || die "make-dmg.sh did not produce $DMG_PATH"

# -----------------------------------------------------------------------------
# Write appcast.xml (Sparkle-compatible schema, single <item> for latest)
# -----------------------------------------------------------------------------
#
# After this commit lands on origin/main, the next release.sh run will
# fetch this file as the authoritative source of the current version.
# The DMG URL uses /releases/latest/download/... so it's stable across
# bumps (matches the `dist/Xdigest.dmg` fixed filename we already use).

log "Writing appcast.xml"
APPCAST_DIRTY=1
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
DMG_SIZE=$(stat -f%z "$DMG_PATH")
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Xdigest</title>
    <link>https://github.com/$REPO_SLUG</link>
    <description>Xdigest release feed</description>
    <language>en</language>
    <item>
      <title>Xdigest $VERSION</title>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:version>$BUILD</sparkle:version>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="https://github.com/$REPO_SLUG/releases/download/v$VERSION/Xdigest.dmg"
        sparkle:shortVersionString="$VERSION"
        sparkle:version="$BUILD"
        length="$DMG_SIZE"
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

# -----------------------------------------------------------------------------
# Commit the version bump + appcast (only after a successful build)
# -----------------------------------------------------------------------------

log "Committing version bump + appcast"
git add "$INFO_PLIST" "$APPCAST"
git commit -m "chore: release $VERSION" 2>&1 | detail
INFO_PLIST_DIRTY=0
APPCAST_DIRTY=0

# -----------------------------------------------------------------------------
# Tag + push
# -----------------------------------------------------------------------------

log "Tagging $TAG"
git tag "$TAG"

log "Pushing commit to origin/$RELEASE_BRANCH"
git push origin HEAD 2>&1 | detail

log "Pushing tag $TAG"
git push origin "$TAG" 2>&1 | detail

# -----------------------------------------------------------------------------
# GitHub release
# -----------------------------------------------------------------------------

log "Creating GitHub release $TAG"
gh release create "$TAG" "$DMG_PATH" \
    --title "Xdigest $VERSION" \
    --generate-notes 2>&1 | detail

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
log "Released $TAG"
printf '    https://github.com/%s/releases/tag/%s\n' "$REPO" "$TAG"
