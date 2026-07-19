#!/usr/bin/env sh
# Turns a pasted /ebb errors dump (or any WoW Lua error text) into the
# repo-side context needed to act on it: for every file:line it mentions,
# the surrounding source and the last commits that touched that exact
# line range. Cuts the "which change broke this" archaeology out of every
# bug report triage.
#
#   sh scripts/triage-error.sh error.txt
#   pbpaste | sh scripts/triage-error.sh -        (or xclip -o | ...)
set -eu
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
    echo "Usage: sh scripts/triage-error.sh <file-with-error-text | ->" >&2
    exit 1
fi

if [ "$1" = "-" ]; then
    INPUT="$(mktemp)"
    trap 'rm -f "$INPUT"' EXIT
    cat > "$INPUT"
else
    INPUT="$1"
fi

# WoW error paths look like:
#   Interface\AddOns\EbonBuilds\modules/build/ExportImport.lua:548:
#   ...ace\AddOns\EbonBuilds\modules/ui/BuildTabs.lua:170: (truncated)
# Normalize backslashes, strip everything up to the addon folder, and
# de-duplicate file:line pairs while preserving first-seen order.
# shellcheck disable=SC1003  # tr '\\' '/' translates backslashes to slashes; the quoting is correct
LOCATIONS="$(tr '\\' '/' < "$INPUT" \
    | grep -oE '(^|[^A-Za-z0-9_])((\.\.\.)?[A-Za-z0-9_./-]*EbonBuilds/)?(core|modules)/[A-Za-z0-9_/.-]+\.lua:[0-9]+' \
    | sed -E 's#.*((core|modules)/[A-Za-z0-9_/.-]+\.lua:[0-9]+)$#\1#' \
    | awk '!seen[$0]++' || true)"

if [ -z "$LOCATIONS" ]; then
    echo "No core/... or modules/....lua:<line> locations found in the input." >&2
    echo "Paste the full error including the Message: and Stack: lines." >&2
    exit 1
fi

echo "$LOCATIONS" | while IFS= read -r loc; do
    FILE="${loc%:*}"
    LINE="${loc##*:}"
    echo "======================================================================"
    echo "$FILE:$LINE"
    echo "======================================================================"
    if [ ! -f "$FILE" ]; then
        echo "  (file does not exist at the current checkout -- error may be from an older version)"
        continue
    fi
    START=$((LINE - 6)); [ "$START" -lt 1 ] && START=1
    END=$((LINE + 4))
    echo ""
    echo "--- source (lines $START-$END, >>> marks the error line) ---"
    awk -v s="$START" -v e="$END" -v t="$LINE" \
        'NR>=s && NR<=e { printf "%s %4d  %s\n", (NR==t ? ">>>" : "   "), NR, $0 }' "$FILE"
    echo ""
    echo "--- last 3 commits touching lines $START-$END ---"
    git log -3 --format="  %h  %ad  %an  %s" --date=short -L "$START,$END:$FILE" --no-patch 2>/dev/null \
        || echo "  (git log -L unavailable for this range)"
    echo ""
done
