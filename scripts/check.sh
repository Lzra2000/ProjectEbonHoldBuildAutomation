#!/usr/bin/env sh
# Runs the same checks as .github/workflows/lua-syntax.yml, locally and in
# one command, so a broken build is caught before pushing instead of in CI.
#
#   sh scripts/check.sh
#
# Requires: lua5.1 (syntax check), texlua from texlive-binaries (test suite).
# See scripts/dev-setup.sh to install both.
set -eu
cd "$(dirname "$0")/.."

overall_fail=0

echo "== 1/3  Lua 5.1 syntax check (excludes tests/) =="
if ! command -v luac5.1 >/dev/null 2>&1; then
    echo "luac5.1 not found -- run: sh scripts/dev-setup.sh" >&2
    exit 1
fi
fail=0
find . -name "*.lua" -not -path "./tests/*" -not -path "./.git/*" > /tmp/ebb_lua_files.txt
while IFS= read -r f; do
    if ! luac5.1 -p "$f"; then
        echo "SYNTAX ERROR: $f"
        fail=1
    fi
done < /tmp/ebb_lua_files.txt
if [ "$fail" -eq 0 ]; then echo "OK: no syntax errors"; else overall_fail=1; fi

echo ""
echo "== 2/3  Test suite (tests/run.sh) =="
if ! command -v texlua >/dev/null 2>&1; then
    echo "texlua not found -- run: sh scripts/dev-setup.sh" >&2
    exit 1
fi
if sh tests/run.sh; then
    echo "OK: test suite passed"
else
    overall_fail=1
fi

echo ""
echo "== 3/3  Every .toc file exists on disk =="
fail=0
awk '{ sub(/\r$/, ""); if ($0 ~ /^[^[:space:]]+\.lua$/) print }' EbonBuilds.toc > /tmp/ebb_toc_files.txt
while IFS= read -r line; do
    [ -f "$line" ] || { echo "MISSING: $line (listed in EbonBuilds.toc)"; fail=1; }
done < /tmp/ebb_toc_files.txt
if [ "$fail" -eq 0 ]; then echo "OK: all TOC files present"; else overall_fail=1; fi

echo ""
if [ "$overall_fail" -eq 0 ]; then
    echo "All checks passed."
else
    echo "One or more checks FAILED -- see above." >&2
fi
exit $overall_fail
