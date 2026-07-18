#!/usr/bin/env sh
# Wires up the repo's tracked hooks (.githooks/) so scripts/check.sh runs
# automatically before every commit. One-time, per clone.
#
#   sh scripts/install-hooks.sh
set -eu
cd "$(dirname "$0")/.."
chmod +x .githooks/* scripts/*.sh
git config core.hooksPath .githooks
echo "Installed. Pre-commit will now run scripts/check.sh (skip once with: git commit --no-verify)"
