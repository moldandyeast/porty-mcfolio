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

echo "release.sh: only --bootstrap is implemented in this commit. See Task 14 for the full flow." >&2
exit 1
