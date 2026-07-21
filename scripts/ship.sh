#!/usr/bin/env sh
# One-command release: runs scripts/release.sh, then pushes main and the
# tag. The pushed tag triggers .github/workflows/release.yml, which
# publishes the GitHub Release and uploads the zip asset. This script
# exists because release/push/publish were three separate manual steps,
# and "pushed the tag but never published the Release" has already
# happened once in this repo's history.
#
#   GITHUB_TOKEN=ghp_xxx sh scripts/ship.sh 3.19
#
# Each stage only runs if the previous one succeeded, and the script
# tells you exactly where it stopped, so a mid-way failure never leaves
# you guessing which of the three steps still needs doing by hand.
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
    echo "Usage: GITHUB_TOKEN=... sh scripts/ship.sh <version>   (e.g. 3.19)" >&2
    exit 1
fi
VERSION="$1"

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "GITHUB_TOKEN is not set -- required for the publish step. Aborting before anything happens." >&2
    exit 1
fi

echo "== 1/3  release.sh (bump, check, dist, commit, tag) =="
sh scripts/release.sh "$VERSION"

echo ""
echo "== 2/3  push main and v$VERSION =="
# Token goes through a temporary credential helper, never into the remote
# URL -- a URL-embedded token leaks into .git/config and shell history.
# shellcheck disable=SC2016  # single quotes are deliberate: $GITHUB_TOKEN must expand inside the helper at credential time, not here
git -c credential.helper='!f() { echo "username=x-access-token"; echo "password=$GITHUB_TOKEN"; }; f' \
    push origin main "v$VERSION"

echo ""
echo "== 3/3  GitHub Release =="
REPO="$(git remote get-url origin | sed -E 's#.*github\.com[:/]##; s#\.git$##')"
echo "The pushed tag triggers the Release workflow:"
echo "  https://github.com/$REPO/actions/workflows/release.yml"
echo "It runs the checks, builds the zip, and publishes the Release with the asset."
echo "Manual fallback if Actions is unavailable:"
echo "  GITHUB_TOKEN=... sh scripts/publish-github-release.sh $VERSION"

echo ""
echo "Shipped $VERSION."
