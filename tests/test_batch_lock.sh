#!/usr/bin/env bash
#
# test_batch_lock.sh - --lock is what decides whether a batch takes a lock
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export RECON_COLOR=always
WORKDIR=$(mktemp -d)
export RECON_STATE_DIR="${WORKDIR}/state"
LOCK_LOG="${WORKDIR}/lock.log"
LOCK_MODE=ok

cleanup() {
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

source "${PROJECT_ROOT}/lib/core/common.sh"
source "${PROJECT_ROOT}/lib/core/input.sh"
source "${PROJECT_ROOT}/lib/core/state.sh"
source "${PROJECT_ROOT}/lib/batch/runner.sh"

# normalize_target trims with xargs. The batch runner also calls xargs -P.
# The stub trims when used as a filter and skips the parallel scan.
xargs() {
    if [[ "${1:-}" == "-P" ]]; then
        cat >/dev/null
        return 0
    fi
    command xargs "$@"
}

state_acquire_lock() {
    echo "acquire $1" >> "$LOCK_LOG"
    [[ "$LOCK_MODE" == ok ]]
}

state_release_lock() {
    echo "release $1" >> "$LOCK_LOG"
    return 0
}

config_get() {
    echo "$2"
}

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

assert_equals() {
    local expected=$1
    local actual=$2
    local message=$3
    ((TESTS_RUN++)) || true
    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
    fi
}

reset_log() {
    : > "$LOCK_LOG"
}

run_batch() {
    batch_run "$TARGETS" 1 "${WORKDIR}/out" "" false "$1" >"${WORKDIR}/run.out" 2>&1
}

TARGETS="${WORKDIR}/targets.txt"
printf '%s\n' "example.com" > "$TARGETS"
mkdir -p "$RECON_STATE_DIR" "${WORKDIR}/out"

echo "================================================"
echo "Testing: batch lock flag"
echo "================================================"

reset_log
run_batch false
assert_equals "" "$(cat "$LOCK_LOG")" "batch_run without --lock does not take a lock"

reset_log
run_batch true
mapfile -t locked < "$LOCK_LOG"
assert_equals "acquire" "${locked[0]%% *}" "batch_run --lock acquires a lock"
assert_equals "release" "${locked[1]%% *}" "batch_run --lock releases that lock"
assert_equals "${locked[0]#acquire }" "${locked[1]#release }" "batch_run releases the same batch id it acquired"

reset_log
LOCK_MODE=fail
set +e
run_batch true
lock_status=$?
set -e
LOCK_MODE=ok
assert_equals "1" "$lock_status" "batch_run --lock fails when the lock is held"
assert_equals "acquire" "$(awk '{print $1}' "$LOCK_LOG" | paste -sd, -)" "a refused lock is not released"

write_incomplete() {
    local id=$1
    rm -f "${RECON_STATE_DIR}"/checkpoint_*.json
    jq -n --arg id "$id" --arg file "$TARGETS" '{
        batch_id: $id,
        targets_file: $file,
        status: "in_progress",
        targets: ["example.com"],
        completed_targets: [],
        failed_targets: [],
        total: 1,
        completed: 0,
        failed: 0
    }' > "${RECON_STATE_DIR}/checkpoint_${id}.json"
}

reset_log
write_incomplete "targets_open"
batch_resume false >"${WORKDIR}/run.out" 2>&1
assert_equals "" "$(cat "$LOCK_LOG")" "batch_resume without --lock does not take a lock"

reset_log
write_incomplete "targets_held"
batch_resume true >"${WORKDIR}/run.out" 2>&1
mapfile -t resumed < "$LOCK_LOG"
assert_equals "acquire" "${resumed[0]%% *}" "batch_resume --lock acquires a lock"
assert_equals "release" "${resumed[1]%% *}" "batch_resume --lock releases that lock"
assert_equals "targets_held" "${resumed[0]#acquire }" "batch_resume --lock locks the resumed batch"

echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo "Total:  $TESTS_RUN"
echo -e "Passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed: ${RED}${TESTS_FAILED}${NC}"

if [[ "$TESTS_FAILED" -gt 0 ]]; then
    exit 1
fi
