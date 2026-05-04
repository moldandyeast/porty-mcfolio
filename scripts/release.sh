#!/usr/bin/env bash
#
# Sparkle release pipeline for Porty McFolio.
#
# Usage:
#   release.sh --bootstrap                # one-time: create gh-pages branch + empty appcast
#   release.sh <version>                  # build, sign, publish a release
#   release.sh <version> --dry-run        # do everything except git push, gh release create, gh-pages push
#   release.sh <version> --critical       # mark this release as a critical update
#
# Prerequisites:
#   - Working tree clean, on main
#   - docs/release-notes/v<version>.md exists
#   - cmark-gfm installed (brew install cmark-gfm)
#   - Sparkle's sign_update binary available
#   - Developer ID + notary credentials (see scripts/build-dmg.sh)
#   - GitHub Pages enabled on the gh-pages branch (one-time, after --bootstrap)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

bootstrap_gh_pages() {
    echo "==> Bootstrapping gh-pages branch..."

    if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
        echo "error: gh-pages branch already exists on origin. Bootstrap is one-time." >&2
        exit 1
    fi

    local origin_url author_email author_name
    origin_url=$(git remote get-url origin)
    author_email=$(git config user.email)
    author_name=$(git config user.name)

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT

    # Build gh-pages in an isolated throwaway repo, then push to origin.
    # Avoids `git worktree add --orphan` (added in git 2.42) for compatibility
    # with the Apple-bundled git 2.39.x.
    (
        cd "$tmpdir"
        git init -q -b gh-pages
        cat > appcast.xml <<'XML'
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Porty McFolio</title>
    <link>https://moldandyeast.github.io/porty-mcfolio/appcast.xml</link>
    <description>Updates for Porty McFolio</description>
    <language>en</language>
  </channel>
</rss>
XML
        git add appcast.xml
        git -c user.email="$author_email" \
            -c user.name="$author_name" \
            commit -q -m "chore: bootstrap empty appcast"
        git remote add origin "$origin_url"
        git push -u origin gh-pages
    )

    echo "==> gh-pages branch created and pushed."
    echo "==> Next: enable GitHub Pages from the gh-pages branch root in repo Settings → Pages."
    echo "==> Then verify: curl -fsS https://moldandyeast.github.io/porty-mcfolio/appcast.xml"
}

if [[ "${1:-}" == "--bootstrap" ]]; then
    bootstrap_gh_pages
    exit 0
fi

# Argument parsing
VERSION="${1:-}"
DRY_RUN=0
CRITICAL=0
shift || true
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --critical) CRITICAL=1 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "usage: release.sh <version> [--dry-run] [--critical]" >&2
    echo "       release.sh --bootstrap" >&2
    exit 1
fi

echo "==> Preflight..."

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree not clean" >&2
    exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "error: not on main (on $CURRENT_BRANCH)" >&2
    exit 1
fi

YML_VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | awk '{print $2}' | tr -d '"')
if [[ "$YML_VERSION" != "$VERSION" ]]; then
    echo "error: project.yml MARKETING_VERSION ($YML_VERSION) != requested $VERSION" >&2
    exit 1
fi

NOTES_FILE="docs/release-notes/v${VERSION}.md"
if [[ ! -f "$NOTES_FILE" ]]; then
    echo "error: release notes file missing: $NOTES_FILE" >&2
    exit 1
fi

command -v cmark-gfm >/dev/null || { echo "error: cmark-gfm not installed (brew install cmark-gfm)" >&2; exit 1; }

SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData/PortyMcFolio-*/SourcePackages/artifacts/sparkle -name sign_update 2>/dev/null | head -1)
if [[ -z "$SIGN_UPDATE" ]]; then
    echo "error: sign_update not found. Run xcodebuild -resolvePackageDependencies first." >&2
    exit 1
fi

echo "    version:      $VERSION"
echo "    dry-run:      $DRY_RUN"
echo "    critical:     $CRITICAL"
echo "    notes file:   $NOTES_FILE"
echo "    sign_update:  $SIGN_UPDATE"

echo "==> Building DMG via build-dmg.sh..."
./scripts/build-dmg.sh
DMG_PATH=$(ls -t dist/PortyMcFolio-${VERSION}-*.dmg | head -1)
[[ -f "$DMG_PATH" ]] || { echo "error: build-dmg.sh did not produce a DMG" >&2; exit 1; }
echo "    DMG:          $DMG_PATH"

echo "==> Signing DMG for Sparkle..."
SIG_OUTPUT=$("$SIGN_UPDATE" "$DMG_PATH")
ED_SIG=$(echo "$SIG_OUTPUT" | grep -oE 'sparkle:edSignature="[^"]+"' | sed 's/.*"\(.*\)"/\1/')
LEN=$(echo "$SIG_OUTPUT" | grep -oE 'length="[^"]+"' | sed 's/.*"\(.*\)"/\1/')
[[ -n "$ED_SIG" && -n "$LEN" ]] || { echo "error: sign_update output unexpected:"; echo "$SIG_OUTPUT" >&2; exit 1; }
echo "    signature:    ${ED_SIG:0:20}..."
echo "    length:       $LEN bytes"

echo "==> Rendering release notes..."
NOTES_HTML=$(cmark-gfm "$NOTES_FILE")

PUB_DATE=$(date -R)
DMG_BASENAME=$(basename "$DMG_PATH")
ENCLOSURE_URL="https://github.com/moldandyeast/porty-mcfolio/releases/download/v${VERSION}/${DMG_BASENAME}"

CRITICAL_TAG=""
if [[ "$CRITICAL" -eq 1 ]]; then
    CRITICAL_TAG="      <sparkle:criticalUpdate />\n"
fi

MIN_OS=$(grep -E '^\s*MACOSX_DEPLOYMENT_TARGET:' project.yml | head -1 | awk '{print $2}' | tr -d '"')

ITEM_XML=$(cat <<XML
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:minimumSystemVersion>${MIN_OS}</sparkle:minimumSystemVersion>
$(printf "$CRITICAL_TAG")      <description><![CDATA[
${NOTES_HTML}
]]></description>
      <enclosure
        url="${ENCLOSURE_URL}"
        sparkle:edSignature="${ED_SIG}"
        length="${LEN}"
        type="application/octet-stream"/>
    </item>
XML
)

if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "==> DRY RUN — would prepend to appcast:"
    echo "----- BEGIN ITEM -----"
    echo "$ITEM_XML"
    echo "----- END ITEM -----"
    echo "==> DRY RUN — would create release at $ENCLOSURE_URL"
    echo "==> DRY RUN — done."
    exit 0
fi

echo "==> Publishing appcast..."
GH_PAGES_DIR=$(mktemp -d)
trap "rm -rf '$GH_PAGES_DIR'; git worktree prune" EXIT
git fetch origin gh-pages
git worktree add "$GH_PAGES_DIR" gh-pages

# Prepend the new <item> immediately after </language>
python3 -c "
import re, sys
appcast = open('$GH_PAGES_DIR/appcast.xml').read()
new_item = '''$ITEM_XML'''
new = re.sub(
    r'(</language>\s*)',
    r'\1\n' + new_item + '\n',
    appcast,
    count=1
)
open('$GH_PAGES_DIR/appcast.xml', 'w').write(new)
"

(cd "$GH_PAGES_DIR" && \
    git add appcast.xml && \
    git commit -q -m "chore(appcast): release v${VERSION}" && \
    git push origin gh-pages)

echo "==> Creating GitHub Release..."
gh release create "v${VERSION}" --title "v${VERSION}" --notes-file "$NOTES_FILE" "$DMG_PATH"

echo "==> Tagging main..."
git tag "v${VERSION}"
git push origin "v${VERSION}"

echo
echo "==> ✅ Released v${VERSION}"
echo "    Appcast:  https://moldandyeast.github.io/porty-mcfolio/appcast.xml"
echo "    Release:  https://github.com/moldandyeast/porty-mcfolio/releases/tag/v${VERSION}"
