#!/usr/bin/env sh
# Publishes an actual GitHub Release (release notes page under /releases) for
# a version that's already tagged locally -- a `git tag` + `git push` alone
# does NOT create a GitHub Release, only a ref. This closes that gap.
#
#   GITHUB_TOKEN=ghp_xxx sh scripts/publish-github-release.sh 3.06
#
# Pulls the release title/notes straight from the matching "### <version>"
# section of FAQ.md, so run this after scripts/release.sh (which requires
# that section to exist) and after pushing the tag.
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
    echo "Usage: GITHUB_TOKEN=... sh scripts/publish-github-release.sh <version>   (e.g. 3.06)" >&2
    exit 1
fi
VERSION="$1"
TAG="v$VERSION"

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "GITHUB_TOKEN is not set. Export a token with 'repo' scope first." >&2
    exit 1
fi

REPO="$(git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
if [ -z "$REPO" ]; then
    echo "Could not determine owner/repo from 'origin' remote." >&2
    exit 1
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Local tag $TAG not found -- run scripts/release.sh first." >&2
    exit 1
fi

if ! git cat-file -e "$TAG:dist/EbonBuilds.zip" 2>/dev/null; then
    echo "dist/EbonBuilds.zip is not present in the $TAG commit -- run scripts/build-dist.sh and include it in the release commit before publishing (scripts/release.sh does this automatically)." >&2
    exit 1
fi

# Pull the notes: from "### $VERSION" up to (not including) the next "### ".
NOTES="$(awk -v ver="^### $VERSION " '
    $0 ~ ver { found=1; print; next }
    found && /^### / { exit }
    found { print }
' FAQ.md)"

if [ -z "$NOTES" ]; then
    echo "No '### $VERSION' section found in FAQ.md -- add a changelog entry first." >&2
    exit 1
fi

TITLE="$(printf '%s\n' "$NOTES" | head -1 | sed 's/^### //')"
CHANGES="$(printf '%s\n' "$NOTES" | tail -n +2)"

# Pinned to the tag (not "main"), so the link always serves the zip that
# actually matches this release, even after later commits move main on.
DOWNLOAD_URL="https://github.com/$REPO/raw/$TAG/dist/EbonBuilds.zip"
BODY="**Install:** [Download EbonBuilds.zip]($DOWNLOAD_URL)$(printf '\n')Extract it and drop the \`EbonBuilds\` folder into \`Interface/AddOns/\`.
$(printf '%s' "$CHANGES")"

PAYLOAD_FILE="$(mktemp)"
trap 'rm -f "$PAYLOAD_FILE"' EXIT
python3 - "$TAG" "$TITLE" "$BODY" > "$PAYLOAD_FILE" <<'PYEOF'
import json, sys
tag, title, body = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({"tag_name": tag, "name": title, "body": body, "draft": False, "prerelease": False}))
PYEOF

RESPONSE="$(curl -s -X POST \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases" \
    -d @"$PAYLOAD_FILE")"

URL="$(printf '%s' "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('html_url',''))" 2>/dev/null || true)"

if [ -z "$URL" ]; then
    echo "Failed to create release. Response:" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

echo "Published: $URL"
