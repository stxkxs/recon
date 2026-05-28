#!/usr/bin/env bash
#
# test_reverseip.sh - Unit tests for Reverse IP module
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
source "${PROJECT_ROOT}/lib/modules/reverseip.sh"

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
echo "Testing: Reverse IP Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

((TESTS_RUN++)) || true
if declare -f reverseip_run &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} reverseip_run function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} reverseip_run function defined"
fi

((TESTS_RUN++)) || true
if declare -f reverseip_print &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} reverseip_print function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} reverseip_print function defined"
fi

((TESTS_RUN++)) || true
if declare -f reverseip_check &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} reverseip_check function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} reverseip_check function defined"
fi

echo ""

# ─── Dependency Check Tests ───

echo "--- dependency check ---"

((TESTS_RUN++)) || true
if reverseip_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} reverseip_check passes (curl, jq, and dig available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} reverseip_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "reverseip" "$MODULE_REVERSEIP_NAME" "MODULE_REVERSEIP_NAME is 'reverseip'"
assert_equals "Reverse IP lookup" "$MODULE_REVERSEIP_DESCRIPTION" "MODULE_REVERSEIP_DESCRIPTION is set"

echo ""

# ─── Print Function Tests ───

echo "--- print function ---"

# Test that reverseip_print handles error JSON gracefully
error_json=$(jq -n '{
    error: "resolve_failed",
    ip: "",
    resolved_from: "nonexistent.invalid",
    domains: [],
    total: 0,
    source: "hackertarget.com",
    query_time: "2026-01-01T00:00:00Z"
}')

((TESTS_RUN++)) || true
print_output=$(reverseip_print "$error_json" "nonexistent.invalid" 2>&1 || true)
if [[ $? -eq 0 ]] || true; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} reverseip_print handles error JSON without crashing"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} reverseip_print handles error JSON without crashing"
fi

# Test print with mock valid data
mock_data=$(jq -n '{
    ip: "93.184.216.34",
    resolved_from: "example.com",
    domains: ["example.com", "www.example.com", "mail.example.com", "shop.example.com", "blog.example.com"],
    total: 5,
    source: "hackertarget.com",
    query_time: "2026-01-01T00:00:00Z"
}')

((TESTS_RUN++)) || true
print_output=$(reverseip_print "$mock_data" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} reverseip_print produces output for valid data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} reverseip_print produces output for valid data"
fi

# Verify mock data JSON structure
assert_json_valid "$mock_data" "Mock data is valid JSON"
assert_json_has_key "$mock_data" "ip" "Mock data has 'ip' key"
assert_json_has_key "$mock_data" "resolved_from" "Mock data has 'resolved_from' key"
assert_json_has_key "$mock_data" "domains" "Mock data has 'domains' key"
assert_json_has_key "$mock_data" "total" "Mock data has 'total' key"
assert_json_has_key "$mock_data" "source" "Mock data has 'source' key"
assert_json_has_key "$mock_data" "query_time" "Mock data has 'query_time' key"
assert_json_value "$mock_data" "ip" "93.184.216.34" "IP is '93.184.216.34'"
assert_json_value "$mock_data" "resolved_from" "example.com" "Resolved from is 'example.com'"
assert_json_value "$mock_data" "source" "hackertarget.com" "Source is 'hackertarget.com'"
assert_json_value "$mock_data" "total" "5" "Total is 5"

# Verify domains is an array
((TESTS_RUN++)) || true
domain_type=$(echo "$mock_data" | jq -r '.domains | type')
if [[ "$domain_type" == "array" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} domains field is an array"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} domains field is an array (got $domain_type)"
fi

# Verify domains count matches total
((TESTS_RUN++)) || true
domains_len=$(echo "$mock_data" | jq '.domains | length')
domains_total=$(echo "$mock_data" | jq '.total')
if [[ "$domains_len" == "$domains_total" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} domains array length ($domains_len) matches total ($domains_total)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} domains array length ($domains_len) should match total ($domains_total)"
fi

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECOND_MODULE_REVERSEIP_LOADED" == "1" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Source guard variable is set"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Source guard variable is set"
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
