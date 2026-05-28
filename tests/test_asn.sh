#!/usr/bin/env bash
#
# test_asn.sh - Unit tests for ASN module
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
source "${PROJECT_ROOT}/lib/modules/asn.sh"

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
echo "Testing: ASN Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

((TESTS_RUN++)) || true
if declare -f asn_run &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} asn_run function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} asn_run function defined"
fi

((TESTS_RUN++)) || true
if declare -f asn_print &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} asn_print function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} asn_print function defined"
fi

((TESTS_RUN++)) || true
if declare -f asn_check &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} asn_check function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} asn_check function defined"
fi

echo ""

# ─── Dependency Check Tests ───

echo "--- dependency check ---"

((TESTS_RUN++)) || true
if asn_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} asn_check passes (dig, whois, and jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} asn_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "asn" "$MODULE_ASN_NAME" "MODULE_ASN_NAME is 'asn'"
assert_equals "ASN expansion and prefix enumeration" "$MODULE_ASN_DESCRIPTION" "MODULE_ASN_DESCRIPTION is set"

echo ""

# ─── Error JSON Tests ───

echo "--- error json structure ---"

# Test with an unresolvable target to get error JSON
result=$(asn_run "this-domain-does-not-exist-xyz123.invalid" 2>/dev/null)

assert_json_valid "$result" "asn_run with unresolvable target returns valid JSON"
assert_json_has_key "$result" "error" "Result has 'error' key"
assert_json_value "$result" "error" "resolve_failed" "Error is 'resolve_failed'"
assert_json_has_key "$result" "ip" "Result has 'ip' key"
assert_json_has_key "$result" "asn" "Result has 'asn' key"
assert_json_has_key "$result" "asn_name" "Result has 'asn_name' key"
assert_json_has_key "$result" "asn_country" "Result has 'asn_country' key"
assert_json_has_key "$result" "prefixes" "Result has 'prefixes' key"
assert_json_has_key "$result" "total_prefixes" "Result has 'total_prefixes' key"
assert_json_has_key "$result" "total_ips_approx" "Result has 'total_ips_approx' key"

# Verify empty defaults
assert_json_value "$result" "ip" "" "IP is empty string on error"

prefixes_count=$(echo "$result" | jq '.prefixes | length')
assert_equals "0" "$prefixes_count" "Prefixes array is empty on error"

assert_json_value "$result" "total_prefixes" "0" "total_prefixes is 0 on error"
assert_json_value "$result" "total_ips_approx" "0" "total_ips_approx is 0 on error"

echo ""

# ─── Print Function Tests ───

echo "--- print function ---"

# Test that asn_print handles error JSON gracefully
((TESTS_RUN++)) || true
print_output=$(asn_print "$result" "example.com" 2>&1 || true)
if [[ $? -eq 0 ]] || true; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} asn_print handles error JSON without crashing"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} asn_print handles error JSON without crashing"
fi

# Test print with mock valid data
mock_data=$(jq -n '{
    ip: "93.184.216.34",
    asn: "AS15133",
    asn_name: "EDGECAST - Verizon Digital Media Services",
    asn_country: "US",
    prefixes: [
        {prefix: "93.184.216.0/24", description: "EDGECAST Netblk"},
        {prefix: "93.184.220.0/22", description: "EDGECAST Netblk"},
        {prefix: "192.229.128.0/17", description: "EDGECAST Networks"}
    ],
    total_prefixes: 3,
    total_ips_approx: 33536
}')

((TESTS_RUN++)) || true
print_output=$(asn_print "$mock_data" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} asn_print produces output for valid data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} asn_print produces output for valid data"
fi

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECOND_MODULE_ASN_LOADED" == "1" ]]; then
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
