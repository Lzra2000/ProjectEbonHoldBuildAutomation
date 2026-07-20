#!/usr/bin/env sh
# Pushes docs/wiki/ to the repository's GitHub wiki. One-time prerequisite
# GitHub imposes: the wiki's git repo only exists after the FIRST page is
# created through the web UI (any placeholder content -- this overwrites
# it). After that, this script keeps the wiki in sync with docs/wiki/.
#
#   GITHUB_TOKEN=... sh scripts/publish-wiki.sh
set -eu
cd "$(dirname "$0")/.."

if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "GITHUB_TOKEN is not set." >&2
    exit 1
fi

WIKI_DIR="$(mktemp -d)"
trap 'rm -rf "$WIKI_DIR"' EXIT

# shellcheck disable=SC2016  # deliberate: token expands inside the helper at credential time
if ! git -c credential.helper='!f() { echo "username=x-access-token"; echo "password=$GITHUB_TOKEN"; }; f' \
    clone --quiet "https://github.com/Lzra2000/-ProjectEbonHoldBuildAutomation.wiki.git" "$WIKI_DIR" 2>/dev/null; then
    echo "Wiki repo not found. Create the first page once via the GitHub UI (Wiki tab -> Create the first page), then rerun." >&2
    exit 1
fi

cp docs/wiki/*.md "$WIKI_DIR/"
cd "$WIKI_DIR"
git add -A
if git diff --cached --quiet; then
    echo "Wiki already up to date."
    exit 0
fi
git -c user.email="wiki@ebonbuilds" -c user.name="EbonBuilds docs" commit --quiet -m "Sync from docs/wiki/"
# shellcheck disable=SC2016
git -c credential.helper='!f() { echo "username=x-access-token"; echo "password=$GITHUB_TOKEN"; }; f' push --quiet
echo "Wiki published."
