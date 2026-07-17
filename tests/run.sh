#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
texlua tests/test_features.lua
texlua tests/test_load.lua
