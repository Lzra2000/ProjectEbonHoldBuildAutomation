#!/usr/bin/env sh
# Runs the Lua 5.1 test suite (same runtime as the WoW 3.3.5a client).
#
#   sh tests/run.sh                  # fast suite (skips 70k board sim)
#   sh tests/run.sh --full           # include slow simulation tests
#   sh tests/run.sh --only architecture
#   FILTER=freeze sh tests/run.sh
#   VERBOSE=1 sh tests/run.sh --only load
#
# New files matching tests/test_*.lua are picked up automatically (no edit
# needed here) so parallel test-expansion work does not fight this runner.
set -eu
cd "$(dirname "$0")/.."

FULL="${EBB_FULL:-0}"
FILTER="${EBB_TEST_FILTER:-${FILTER:-}}"
VERBOSE="${VERBOSE:-${EBB_VERBOSE:-0}}"
ANNOTATE="${EBB_ANNOTATE:-0}"
LOG_DIR="${EBB_LOG_DIR:-.cache/check-logs}"

# On GitHub Actions, surface failures in the PR "Files changed" UI.
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    ANNOTATE=1
fi

usage() {
    cat <<'EOF'
Usage: sh tests/run.sh [options] [filter]

Options:
  --full              Include slow suites (70k board simulation)
  --only <filter>     Run only matching test file(s)
  --verbose, -v       Extra runner context (timing, skip reasons, log paths)
  --help, -h          Show this help

Filter matches a substring of the test path/basename, e.g.:
  architecture  -> tests/test_architecture.lua
  freeze        -> freeze_first, freeze_recovery, freeze_first_simulation
  test_load.lua -> exact-ish path match

Environment:
  FILTER / EBB_TEST_FILTER   Same as --only
  EBB_FULL=1                 Same as --full
  VERBOSE / EBB_VERBOSE=1    Same as --verbose
  EBB_ANNOTATE=1             Emit GitHub Actions ::error annotations
  EBB_LOG_DIR                Where per-test logs are written (default .cache/check-logs)

Re-run one failing file after a CI failure:
  sh tests/run.sh --only <name>
  # or:
  lua5.1 tests/test_<name>.lua
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --full) FULL=1; shift ;;
        --only)
            if [ $# -lt 2 ]; then echo "ERROR: --only needs a filter" >&2; exit 2; fi
            FILTER="$2"; shift 2 ;;
        --verbose|-v) VERBOSE=1; shift ;;
        --help|-h) usage; exit 0 ;;
        -*)
            echo "Unknown option: $1 (try --help)" >&2
            exit 2 ;;
        *)
            FILTER="$1"; shift ;;
    esac
done

if ! command -v lua5.1 >/dev/null 2>&1; then
    echo "lua5.1 not found -- run: sh scripts/dev-setup.sh" >&2
    echo "On Windows: use Git Bash/WSL, or put lua5.1 on PATH (see docs/dev-testing.md)." >&2
    exit 1
fi

mkdir -p "$LOG_DIR"
RUN_STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo manual)
SUITE_LOG="$LOG_DIR/tests-${RUN_STAMP}.log"
: > "$SUITE_LOG"

is_slow() {
    case "$1" in
        */test_freeze_first_simulation.lua) return 0 ;;
        *) return 1 ;;
    esac
}

filter_matches() {
    # empty filter = all
    fpath=$1
    [ -z "$FILTER" ] && return 0
    base=$(basename "$fpath" .lua)
    base=${base#test_}
    printf '%s\n%s\n%s\n' "$fpath" "$(basename "$fpath")" "$base" | grep -qi -- "$FILTER"
}

# Collect tests/test_*.lua (portable: no mapfile / arrays).
TEST_LIST="$LOG_DIR/test-list-${RUN_STAMP}.txt"
: > "$TEST_LIST"
for f in tests/test_*.lua; do
    [ -f "$f" ] || continue
    printf '%s\n' "$f" >> "$TEST_LIST"
done

if [ ! -s "$TEST_LIST" ]; then
    echo "ERROR: no tests/test_*.lua files found" >&2
    exit 1
fi

# Stable order: alphabetical, with slow suites listed last among selected.
ORDERED="$LOG_DIR/test-order-${RUN_STAMP}.txt"
: > "$ORDERED"
# shellcheck disable=SC2013
for f in $(sort "$TEST_LIST"); do
    is_slow "$f" && continue
    printf '%s\n' "$f" >> "$ORDERED"
done
# shellcheck disable=SC2013
for f in $(sort "$TEST_LIST"); do
    is_slow "$f" || continue
    printf '%s\n' "$f" >> "$ORDERED"
done

emit_annotations_from_log() {
    test_file=$1
    log_file=$2
    [ "$ANNOTATE" = "1" ] || return 0
    # Prefer explicit FAIL / ERROR lines; fall back to whole log tail.
    # shellcheck disable=SC2162
    grep -E 'FAIL:|ERROR:|SYNTAX ERROR:|NOT AVAILABLE' "$log_file" 2>/dev/null | while IFS= read line; do
        [ -z "$line" ] && continue
        # Strip CR for Windows-produced logs.
        line=$(printf '%s' "$line" | tr -d '\r')
        file=$(printf '%s' "$line" | sed -n 's/.*\([^[:space:]]*\.lua\)\(:[0-9][0-9]*\)\?.*/\1/p' | head -n 1)
        lineno=$(printf '%s' "$line" | sed -n 's/.*\.lua:\([0-9][0-9]*\).*/\1/p' | head -n 1)
        # Sanitize for annotation (no newlines).
        msg=$(printf '%s' "$line" | tr '\n' ' ')
        if [ -n "$file" ] && [ -n "$lineno" ]; then
            printf '::error file=%s,line=%s::%s\n' "$file" "$lineno" "$msg"
        elif [ -n "$file" ]; then
            printf '::error file=%s::%s\n' "$file" "$msg"
        else
            printf '::error file=%s::%s\n' "$test_file" "$msg"
        fi
    done
    # If no FAIL line was found but the process failed, still annotate.
    if ! grep -qE 'FAIL:|ERROR:|SYNTAX ERROR:|NOT AVAILABLE' "$log_file" 2>/dev/null; then
        tail_msg=$(tail -n 5 "$log_file" 2>/dev/null | tr '\n' ' ' | tr -d '\r')
        [ -n "$tail_msg" ] || tail_msg="test exited non-zero (see log)"
        printf '::error file=%s::%s\n' "$test_file" "$tail_msg"
    fi
}

if [ "$VERBOSE" = "1" ]; then
    echo "VERBOSE: lua5.1=$(command -v lua5.1)"
    echo "VERBOSE: cwd=$(pwd)"
    echo "VERBOSE: FULL=$FULL FILTER=${FILTER:-<all>} ANNOTATE=$ANNOTATE"
    echo "VERBOSE: suite log=$SUITE_LOG"
    echo "VERBOSE: discovered $(wc -l < "$TEST_LIST" | tr -d ' ') test file(s)"
    # Trace loadfile() / print a loaded-module summary at process exit.
    export LUA_INIT="@tests/verbose_init.lua"
fi

overall_fail=0
ran=0
skipped=0
failed_names=""

# shellcheck disable=SC2162
while IFS= read f; do
    [ -z "$f" ] && continue
    if ! filter_matches "$f"; then
        continue
    fi
    # Slow suites are skipped unless --full / EBB_FULL=1, OR the user
    # explicitly filtered to that file (so a failing CI sim is re-runnable).
    if is_slow "$f" && [ "$FULL" != "1" ] && [ -z "$FILTER" ]; then
        echo "SKIP: $f (slow 70k board sim; re-run with --full or EBB_FULL=1)"
        echo "SKIP: $f" >> "$SUITE_LOG"
        skipped=$((skipped + 1))
        continue
    fi

    ran=$((ran + 1))
    base=$(basename "$f" .lua)
    test_log="$LOG_DIR/${base}-${RUN_STAMP}.log"
    echo "==> $f"
    echo "==> $f" >> "$SUITE_LOG"
    start_ts=$(date +%s 2>/dev/null || echo 0)

    set +e
    lua5.1 "$f" >"$test_log" 2>&1
    rc=$?
    set -e

    end_ts=$(date +%s 2>/dev/null || echo 0)
    elapsed=0
    if [ "$start_ts" != "0" ] && [ "$end_ts" != "0" ]; then
        elapsed=$((end_ts - start_ts))
    fi

    cat "$test_log" >> "$SUITE_LOG"
    if [ "$rc" -eq 0 ]; then
        if [ "$VERBOSE" = "1" ]; then
            echo "OK: $f (${elapsed}s)"
            # Dump a short context summary from the test's own prints.
            grep -E 'passed|Passed|OK:|Simulated|keys' "$test_log" 2>/dev/null | tail -n 3 | sed 's/^/    /' || true
        else
            echo "OK: $f"
        fi
    else
        overall_fail=1
        failed_names="$failed_names $f"
        echo "FAIL: $f (exit $rc${elapsed:+, ${elapsed}s})" >&2
        echo "----- output ($test_log) -----" >&2
        cat "$test_log" >&2
        echo "----- end output -----" >&2
        echo "Re-run locally:  sh tests/run.sh --only $(basename "$f" .lua | sed 's/^test_//')" >&2
        echo "Or directly:     lua5.1 $f" >&2
        emit_annotations_from_log "$f" "$test_log"
    fi
done < "$ORDERED"

if [ "$ran" -eq 0 ]; then
    echo "ERROR: filter ${FILTER:-} matched no tests (see tests/test_*.lua)" >&2
    echo "Try: sh tests/run.sh --help" >&2
    exit 2
fi

echo ""
if [ "$overall_fail" -eq 0 ]; then
    echo "Test suite passed ($ran file(s) run, $skipped skipped)."
    [ "$VERBOSE" = "1" ] && echo "VERBOSE: combined log $SUITE_LOG"
else
    echo "Test suite FAILED.$failed_names" >&2
    echo "Logs: $SUITE_LOG" >&2
    echo "Re-run failed only, e.g.: sh tests/run.sh --only architecture" >&2
fi
exit $overall_fail
