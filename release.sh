#!/usr/bin/env zsh
# release.sh — Build, verify, package, and publish a JustIn release.
#
# Usage: ./release.sh <version>
#   e.g. ./release.sh 1.0
#
# Requires: xcodebuild, hdiutil, gh (GitHub CLI), git, codesign, xcrun
#
# Adapted from the WaxOn/WaxOff release script. JustIn bundles no external
# binaries and has no entitlements/sandbox, docs site, or GitHub Pages, so the
# binary-signing, entitlements, manual/landing, and Pages-deployment steps are
# intentionally omitted.

set -euo pipefail

REPO="sevmorris/JustIn"

# notarytool keychain profile, shared by every sibling release script. A profile
# cannot be exported, so a new Mac needs it created again under this name:
#   xcrun notarytool store-credentials notarytool --apple-id <email> --team-id T9RLNAXPWU
# Set NOTARY_PROFILE to use another (a Mac still holding the old WoWoNotary one).
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool}"

# ── Args ──────────────────────────────────────────────────────────────────────
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>"
    echo "  e.g. $0 1.0"
    exit 1
fi

VERSION="$1"
TAG="v${VERSION}"
SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT="$PROJECT_DIR/JustIn.xcodeproj"
SCHEME="JustIn"
DERIVED_DATA="/tmp/justin_build_${VERSION}"
APP_PATH="$DERIVED_DATA/Build/Products/Release/JustIn.app"
STAGING="/tmp/justin_dmg_${VERSION}"
DMG="/tmp/JustIn-${TAG}.dmg"
MOUNT="/tmp/justin_verify_${VERSION}"

# ── Helpers ───────────────────────────────────────────────────────────────────
step()  { echo "\n▶ $*"; }
ok()    { echo "  ✓ $*"; }
fail()  { echo "\n  ✗ $*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────
step "Preflight checks"
for cmd in xcodebuild hdiutil gh git codesign xcrun; do
    command -v $cmd &>/dev/null || fail "'$cmd' not found in PATH"
done
ok "Tools present"

# True when this user's console session is locked. Reads IOKit's console-user
# records for our uid rather than taking the first: with more than one user
# logged in, the first record need not be ours.
screen_locked() {
    local plist i uid
    plist=$(ioreg -n Root -d1 -a 2>/dev/null) || return 1
    for i in 0 1 2 3 4 5 6 7; do
        uid=$(plutil -extract "IOConsoleUsers.$i.kCGSSessionUserIDKey" raw -o - - <<<"$plist" 2>/dev/null) || return 1
        [[ "$uid" == "$(id -u)" ]] || continue
        [[ "$(plutil -extract "IOConsoleUsers.$i.CGSSessionScreenIsLocked" raw -o - - <<<"$plist" 2>/dev/null)" == true ]]
        return
    done
    return 1
}

# A missing profile used to surface at the notarization step, after a clean
# build — which is how a new Mac found out. Asking costs one API call.
# A locked screen reads as a missing profile: notarytool keeps its credentials
# in the data-protection keychain, which locks with the screen. On 2026-09-24 a
# release stopped here at 4 a.m. and was sent looking for a profile that was
# there all along. Asked only once the check has failed, so it can never stop a
# release that would otherwise go ahead.
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &>/dev/null; then
    screen_locked && fail "The screen is locked, so notarytool cannot read its keychain profile '$NOTARY_PROFILE' — unlock the Mac and re-run"
    fail "notarytool profile '$NOTARY_PROFILE' is missing, rejected or unreachable — create it with: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <email> --team-id T9RLNAXPWU"
fi
ok "notarytool profile '$NOTARY_PROFILE' works"

cd "$PROJECT_DIR"

if [[ -n "$(git status --porcelain)" ]]; then
    fail "Working tree is dirty — commit or stash changes before releasing"
fi
ok "Working tree clean"

if git tag | grep -q "^${TAG}$"; then
    fail "Tag $TAG already exists — has this version been released?"
fi
ok "Tag $TAG is available"

# ── Version bump ──────────────────────────────────────────────────────────────
step "Bumping version to $VERSION"
CURRENT=$(grep MARKETING_VERSION "$PROJECT/project.pbxproj" | head -1 | grep -o '[0-9][0-9.]*')
if [[ "$CURRENT" == "$VERSION" ]]; then
    ok "Already at $VERSION"
else
    ESC_CURRENT=$(printf '%s' "$CURRENT" | sed 's/[.[\*^$]/\\&/g')
    ESC_VERSION=$(printf '%s'  "$VERSION" | sed 's/[.[\*^$]/\\&/g')
    sed -i '' "s/MARKETING_VERSION = ${ESC_CURRENT};/MARKETING_VERSION = ${ESC_VERSION};/g" \
        "$PROJECT/project.pbxproj"
    ok "Bumped $CURRENT → $VERSION"
    git add "$PROJECT/project.pbxproj"
    git commit -m "Bump version to $VERSION"
    ok "Committed version bump"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
step "Building (clean, Release)"
rm -rf "$DERIVED_DATA"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet
[[ -d "$APP_PATH" ]] || fail "Build did not produce $APP_PATH"
ok "Build complete"

# ── Sign ──────────────────────────────────────────────────────────────────────
step "Codesigning app (Developer ID, Hardened Runtime)"
IDENTITY="Developer ID Application: Seven Morris (T9RLNAXPWU)"
codesign --force --options runtime --sign "$IDENTITY" "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"
ok "Codesigning complete"

# ── Verify app version ────────────────────────────────────────────────────────
step "Verifying built app version"
BUILT_VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
[[ "$BUILT_VERSION" == "$VERSION" ]] || \
    fail "App version mismatch: expected $VERSION, got $BUILT_VERSION"
ok "App reports $BUILT_VERSION"

# ── Stage DMG contents ────────────────────────────────────────────────────────
step "Staging DMG contents"
rm -rf "$STAGING"
mkdir "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
ok "App and Applications alias staged"

# ── Create DMG ────────────────────────────────────────────────────────────────
step "Creating DMG"
rm -f "$DMG"
hdiutil create \
    -volname "JustIn $TAG" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -o "$DMG" \
    -quiet
ok "Created $(du -sh $DMG | cut -f1) DMG"

# ── Notarize ──────────────────────────────────────────────────────────────────
step "Notarizing DMG"
# NOTARY_PROFILE is defined at the top and proven usable in preflight — the
# same account-level profile as the sibling apps.
xcrun notarytool submit "$DMG" --wait --keychain-profile "$NOTARY_PROFILE"
xcrun stapler staple "$DMG"
ok "Notarization complete"

# ── Verify DMG ────────────────────────────────────────────────────────────────
step "Verifying DMG contents"
rm -rf "$MOUNT"
mkdir "$MOUNT"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -quiet -nobrowse
DMG_VERSION=$(defaults read "$MOUNT/JustIn.app/Contents/Info.plist" CFBundleShortVersionString)
hdiutil detach "$MOUNT" -quiet
[[ "$DMG_VERSION" == "$VERSION" ]] || \
    fail "DMG version mismatch: expected $VERSION, got $DMG_VERSION"
ok "DMG contains $DMG_VERSION"

# ── Update README download link ───────────────────────────────────────────────
# Per project convention: rewrite unconditionally and let `git status --porcelain`
# decide whether anything actually changed before committing.
step "Updating README to ${TAG}"
sed -i '' "s|JustIn-v[0-9][0-9.]*\.dmg|JustIn-${TAG}.dmg|g" "$PROJECT_DIR/README.md"
sed -i '' "s|<strong>Version:</strong> [0-9][0-9.]*|<strong>Version:</strong> ${VERSION}|g" "$PROJECT_DIR/README.md"
# Plain-text "Version X.Y.Z" form used by the simplified README.
sed -i '' "s|Version [0-9][0-9.]*|Version ${VERSION}|g" "$PROJECT_DIR/README.md"
if [[ -n "$(git status --porcelain)" ]]; then
    git add "$PROJECT_DIR/README.md"
    git commit -m "docs: update download link to ${TAG}"
    ok "README points to ${TAG}"
else
    ok "README already up to date"
fi

# ── Tag and push ──────────────────────────────────────────────────────────────
step "Tagging and pushing"
git tag "$TAG"
# Resolve the tracked remote/branch so this works from any branch (e.g. a
# worktree branch whose name differs from its upstream). Fall back to
# `origin` + current branch when no upstream is configured; `-u` sets it
# on first push so subsequent runs resolve cleanly.
if UPSTREAM=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then
    REMOTE="${UPSTREAM%%/*}"
    BRANCH="${UPSTREAM#*/}"
else
    REMOTE="origin"
    BRANCH=$(git branch --show-current)
fi
git push -u "$REMOTE" "HEAD:$BRANCH"
git push "$REMOTE" "$TAG"
ok "Pushed $TAG to $REMOTE/$BRANCH"

# ── GitHub release ────────────────────────────────────────────────────────────
step "Creating GitHub release"
PREV_TAG=$(git tag --sort=-creatordate | grep -v "^${TAG}$" | head -1 || true)
if [[ -n "$PREV_TAG" ]]; then
    CHANGES=$(git log "${PREV_TAG}..HEAD" --pretty=format:"- %s" \
        | grep -v "^- Bump version" \
        | grep -v "^- docs: update download link" || true)
else
    CHANGES=$(git log --pretty=format:"- %s" \
        | grep -v "^- Bump version" \
        | grep -v "^- docs: update download link" || true)
fi
[[ -n "$CHANGES" ]] || CHANGES="- Initial release"
RELEASE_NOTES="### Changes
${CHANGES}"
gh release create "$TAG" "$DMG" \
    --repo "$REPO" \
    --title "JustIn $TAG" \
    --notes "$RELEASE_NOTES"
ok "Release published"

# ── Remove old releases (keep the ${KEEP_RELEASES} most recent) ───────────────
KEEP_RELEASES=5
step "Removing old releases (keeping ${KEEP_RELEASES} most recent)"
OLD_TAGS=$(gh release list --repo "$REPO" --limit 100 --json tagName \
    --jq '.[].tagName' | tail -n +$((KEEP_RELEASES + 1)) || true)
if [[ -z "$OLD_TAGS" ]]; then
    ok "No old releases to remove"
else
    while IFS= read -r old_tag; do
        gh release delete "$old_tag" --repo "$REPO" --yes --cleanup-tag 2>/dev/null || true
        git tag -d "$old_tag" 2>/dev/null || true
        ok "Removed $old_tag"
    done <<< "$OLD_TAGS"
fi

# ── Clean up temp files ───────────────────────────────────────────────────────
step "Cleaning up"
rm -rf "$STAGING" "$MOUNT" "$DERIVED_DATA"
rm -f "$DMG"
ok "Temp files removed"

# ── Open release page ─────────────────────────────────────────────────────────
RELEASE_URL="https://github.com/${REPO}/releases/tag/${TAG}"
echo "\n✓ JustIn $TAG released successfully."
echo "  $RELEASE_URL"
open "$RELEASE_URL"
