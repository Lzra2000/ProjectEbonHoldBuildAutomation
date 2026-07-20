#!/usr/bin/env sh
# Release helper enforcing the project's standing convention: every release
# bumps EbonBuilds.toc's version, updates FAQ.md, passes the full check
# suite, and is committed + tagged.
#
#   sh scripts/release.sh 3.06
#
# Does NOT push -- review the commit/tag and push yourself:
#   git push origin main && git push origin v3.06
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
    echo "Usage: sh scripts/release.sh <new-version>   (e.g. 3.06)" >&2
    exit 1
fi
NEW_VERSION="$1"

if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree not clean -- commit or stash your changes first." >&2
    git status --short
    exit 1
fi

LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "")"

if [ -n "$LAST_TAG" ]; then
    if git diff --quiet "$LAST_TAG" -- FAQ.md; then
        echo "FAQ.md has not changed since $LAST_TAG." >&2
        echo "Convention: every release documents its changes in FAQ.md (in-game via /ebb faq). Update it before releasing." >&2
        exit 1
    fi
fi

echo "== Bumping version: EbonBuilds.toc, FAQ.md header =="
if ! grep -q "^## Version:" EbonBuilds.toc; then
    echo "Could not find '## Version:' line in EbonBuilds.toc" >&2
    exit 1
fi
sed -i.bak "s/^## Version: .*/## Version: $NEW_VERSION/" EbonBuilds.toc && rm -f EbonBuilds.toc.bak

if grep -q "Latest version: " FAQ.md; then
    sed -i.bak "s/Latest version: [^ ]*/Latest version: $NEW_VERSION/" FAQ.md && rm -f FAQ.md.bak
fi

echo ""
echo "== Running full check suite =="
echo "== Regenerating in-game FAQ pages from FAQ.md =="
sh scripts/build-faq-pages.sh
sh scripts/check.sh

echo ""
echo "== Rebuilding dist/EbonBuilds.zip =="
sh scripts/build-dist.sh

echo ""
echo "== Committing and tagging =="
git add EbonBuilds.toc FAQ.md
git add -f dist/EbonBuilds.zip
git commit -q -m "chore(release): bump version to $NEW_VERSION"
git tag "v$NEW_VERSION" -m "v$NEW_VERSION"

echo ""
echo "Done. Review with 'git show HEAD' then push and publish:"
echo "  git push origin main && git push origin v$NEW_VERSION"
echo "  GITHUB_TOKEN=... sh scripts/publish-github-release.sh $NEW_VERSION   # a pushed tag alone is NOT a GitHub Release"
