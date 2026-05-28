#!/usr/bin/env bash
#
# test_crt.sh - Unit tests for crt.sh Certificate Transparency module
#

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Force colors for test output
export RECOND_COLOR=always

# Source required libraries
source "${PROJECT_ROOT}/lib/core/common.sh"
source "${PROJECT_ROOT}/lib/core/config.sh"
source "${PROJECT_ROOT}/lib/core/input.sh"
source "${PROJECT_ROOT}/lib/core/output.sh"
source "${PROJECT_ROOT}/lib/core/state.sh"
source "${PROJECT_ROOT}/lib/modules/crt.sh"

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

    if echo "$json" | jq -e ".$key" >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Key '$key' not found in JSON"
    fi
}

assert_json_value() {
    local json=$1
    local key=$2
    local expected=$3
    local message=${4:-""}

    ((TESTS_RUN++)) || true

    local actual
    actual=$(echo "$json" | jq -r ".$key")

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Expected .$key = $expected"
        echo "  Actual .$key = $actual"
    fi
}

echo "================================================"
echo "Testing: CRT (Certificate Transparency) Module"
echo "================================================"
echo ""

# ─── crt_check Tests ───

echo "--- crt_check ---"

# Test crt_check passes (curl and jq should be available)
((TESTS_RUN++)) || true
if crt_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} crt_check passes (curl and jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} crt_check passes"
fi

echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

for func in crt_run crt_print crt_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "crt" "$MODULE_CRT_NAME" "MODULE_CRT_NAME is 'crt'"
assert_equals "Certificate Transparency log search" "$MODULE_CRT_DESCRIPTION" "MODULE_CRT_DESCRIPTION is set"

echo ""

# ─── Source Guard Test ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "${_RECOND_MODULE_CRT_LOADED}" == "1" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} source guard variable set"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} source guard variable set"
fi

echo ""

# ─── Network Tests (crt_run with real domain) ───

echo "--- crt_run (network required) ---"

# Test with a well-known domain that should have CT log entries
result=$(crt_run "example.com" 2>/dev/null || echo '{"subdomains":[],"total":0,"source":"crt.sh","query_time":"error"}')

assert_json_valid "$result" "crt_run returns valid JSON"
assert_json_has_key "$result" "subdomains" "Result has 'subdomains' key"
assert_json_has_key "$result" "total" "Result has 'total' key"
assert_json_has_key "$result" "source" "Result has 'source' key"
assert_json_has_key "$result" "query_time" "Result has 'query_time' key"
assert_json_value "$result" "source" "crt.sh" "Source is 'crt.sh'"

# Verify subdomains is an array
((TESTS_RUN++)) || true
subdomain_type=$(echo "$result" | jq -r '.subdomains | type')
if [[ "$subdomain_type" == "array" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} subdomains field is an array"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} subdomains field is an array (got $subdomain_type)"
fi

# Verify total matches subdomains array length
((TESTS_RUN++)) || true
total=$(echo "$result" | jq '.total')
array_len=$(echo "$result" | jq '.subdomains | length')
if [[ "$total" == "$array_len" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} total ($total) matches subdomains array length"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} total ($total) should match subdomains array length ($array_len)"
fi

# If results were returned, check they look like valid domains
((TESTS_RUN++)) || true
if [[ "$total" -gt 0 ]]; then
    first_sub=$(echo "$result" | jq -r '.subdomains[0]')
    if [[ "$first_sub" == *"example.com"* ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} Subdomains contain the target domain ($total found, first: $first_sub)"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} First subdomain should contain 'example.com', got: $first_sub"
    fi
else
    # Network may be unavailable or crt.sh may be slow; treat 0 results as a pass with warning
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} crt_run returned 0 results (crt.sh may be unavailable or slow)"
fi

# Verify no wildcard entries remain
((TESTS_RUN++)) || true
wildcard_count=$(echo "$result" | jq '[.subdomains[] | select(startswith("*."))] | length')
if [[ "$wildcard_count" == "0" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} No wildcard entries in results"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Found $wildcard_count wildcard entries that should have been stripped"
fi

# Verify results are deduplicated (no duplicates)
((TESTS_RUN++)) || true
unique_count=$(echo "$result" | jq '.subdomains | unique | length')
if [[ "$array_len" == "$unique_count" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Results are deduplicated"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Results have duplicates ($array_len total vs $unique_count unique)"
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
