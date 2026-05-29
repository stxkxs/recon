#!/usr/bin/env bash
#
# test_dnssec.sh - Unit tests for DNSSEC validation module
#

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Force colors for test output
export RECON_COLOR=always

# Source required libraries
source "${PROJECT_ROOT}/lib/core/common.sh"
source "${PROJECT_ROOT}/lib/core/config.sh"
source "${PROJECT_ROOT}/lib/core/input.sh"
source "${PROJECT_ROOT}/lib/core/output.sh"
source "${PROJECT_ROOT}/lib/core/state.sh"
source "${PROJECT_ROOT}/lib/modules/dnssec.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
assert_equals() {
    local expected=$1
    local actual=$2
    local message=${3:-""}

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

assert_json_valid() {
    local json=$1
    local message=${2:-""}

    ((TESTS_RUN++)) || true

    if echo "$json" | jq . >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Invalid JSON: ${json:0:100}..."
    fi
}

assert_json_has_key() {
    local json=$1
    local key=$2
    local message=${3:-""}

    ((TESTS_RUN++)) || true

    if echo "$json" | jq -e "has(\"$key\")" >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Key '$key' not found in JSON"
    fi
}

echo "================================================"
echo "Testing: DNSSEC Validation Module"
echo "================================================"
echo ""

# ─── DNSSEC Module Tests ───

echo "--- dnssec module ---"

# Test dnssec_check (dependency check)
((TESTS_RUN++)) || true
if dnssec_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} dnssec_check passes (dig and jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} dnssec_check passes"
fi

# Test functions exist
for func in dnssec_run dnssec_print dnssec_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

# Test module info variables
assert_equals "dnssec" "$MODULE_DNSSEC_NAME" "MODULE_DNSSEC_NAME is 'dnssec'"
assert_equals "DNSSEC validation" "$MODULE_DNSSEC_DESCRIPTION" "MODULE_DNSSEC_DESCRIPTION is set"

# Test dnssec_run returns valid JSON (using a known DNSSEC-enabled domain)
echo ""
echo "--- dnssec_run output ---"

result=$(dnssec_run "cloudflare.com")
assert_json_valid "$result" "dnssec_run returns valid JSON"

# Test output has expected boolean fields
for key in enabled valid dnskey ds rrsig nsec3 ad_flag; do
    assert_json_has_key "$result" "$key" "Result has '$key' field"
done

# Test output has algorithm and key_count
assert_json_has_key "$result" "algorithm" "Result has 'algorithm' field"
assert_json_has_key "$result" "key_count" "Result has 'key_count' field"

# Test boolean fields are actually booleans
for key in enabled valid dnskey ds rrsig nsec3 ad_flag; do
    ((TESTS_RUN++)) || true
    local_val=$(echo "$result" | jq -r ".$key")
    if [[ "$local_val" == "true" ]] || [[ "$local_val" == "false" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} '$key' is boolean ($local_val)"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} '$key' should be boolean, got: $local_val"
    fi
done

# Test key_count is a number
((TESTS_RUN++)) || true
kc=$(echo "$result" | jq -r '.key_count')
if [[ "$kc" =~ ^[0-9]+$ ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} key_count is numeric ($kc)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} key_count should be numeric, got: $kc"
fi

echo ""

# Summary
echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo -e "Total:  $TESTS_RUN"
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
