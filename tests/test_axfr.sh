#!/usr/bin/env bash
#
# test_axfr.sh - Unit tests for DNS zone transfer module
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
source "${PROJECT_ROOT}/lib/modules/axfr.sh"

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
echo "Testing: DNS Zone Transfer Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

((TESTS_RUN++)) || true
if declare -f axfr_run &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} axfr_run function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} axfr_run function defined"
fi

((TESTS_RUN++)) || true
if declare -f axfr_print &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} axfr_print function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} axfr_print function defined"
fi

((TESTS_RUN++)) || true
if declare -f axfr_check &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} axfr_check function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} axfr_check function defined"
fi

echo ""

# ─── Dependency Check Tests ───

echo "--- dependency check ---"

((TESTS_RUN++)) || true
if axfr_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} axfr_check passes (dig available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} axfr_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "axfr" "$MODULE_AXFR_NAME" "MODULE_AXFR_NAME is 'axfr'"
assert_equals "DNS zone transfer testing" "$MODULE_AXFR_DESCRIPTION" "MODULE_AXFR_DESCRIPTION is set"

echo ""

# ─── Print Function Tests ───

echo "--- print function ---"

# Test print with mock data: vulnerable scenario
mock_vulnerable=$(jq -n '{
    nameservers_tested: 2,
    vulnerable: true,
    transfers: [
        {
            nameserver: "ns1.example.com",
            success: true,
            records_count: 5,
            records: [
                {name: "example.com", type: "SOA", value: "ns1.example.com. admin.example.com. 2024010101 3600 900 604800 86400"},
                {name: "example.com", type: "A", value: "93.184.216.34"},
                {name: "www.example.com", type: "CNAME", value: "example.com"},
                {name: "mail.example.com", type: "MX", value: "10 mail.example.com"},
                {name: "example.com", type: "NS", value: "ns1.example.com"}
            ]
        },
        {
            nameserver: "ns2.example.com",
            success: false,
            records_count: 0,
            records: []
        }
    ]
}')

((TESTS_RUN++)) || true
print_output=$(axfr_print "$mock_vulnerable" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} axfr_print produces output for vulnerable data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} axfr_print produces output for vulnerable data"
fi

# Test print with mock data: safe scenario
mock_safe=$(jq -n '{
    nameservers_tested: 2,
    vulnerable: false,
    transfers: [
        {
            nameserver: "ns1.example.com",
            success: false,
            records_count: 0,
            records: []
        },
        {
            nameserver: "ns2.example.com",
            success: false,
            records_count: 0,
            records: []
        }
    ]
}')

((TESTS_RUN++)) || true
print_output=$(axfr_print "$mock_safe" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} axfr_print produces output for safe data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} axfr_print produces output for safe data"
fi

# Verify mock vulnerable JSON structure
assert_json_valid "$mock_vulnerable" "Mock vulnerable data is valid JSON"
assert_json_has_key "$mock_vulnerable" "nameservers_tested" "Mock has 'nameservers_tested' key"
assert_json_has_key "$mock_vulnerable" "vulnerable" "Mock has 'vulnerable' key"
assert_json_has_key "$mock_vulnerable" "transfers" "Mock has 'transfers' key"
assert_json_value "$mock_vulnerable" "nameservers_tested" "2" "nameservers_tested is 2"
assert_json_value "$mock_vulnerable" "vulnerable" "true" "vulnerable is true"

# Verify transfer records structure
transfer_count=$(echo "$mock_vulnerable" | jq '.transfers | length')
assert_equals "2" "$transfer_count" "Two transfers in mock data"

first_ns=$(echo "$mock_vulnerable" | jq -r '.transfers[0].nameserver')
assert_equals "ns1.example.com" "$first_ns" "First nameserver is ns1.example.com"

first_success=$(echo "$mock_vulnerable" | jq -r '.transfers[0].success')
assert_equals "true" "$first_success" "First transfer succeeded"

first_rec_count=$(echo "$mock_vulnerable" | jq -r '.transfers[0].records_count')
assert_equals "5" "$first_rec_count" "First transfer has 5 records"

second_success=$(echo "$mock_vulnerable" | jq -r '.transfers[1].success')
assert_equals "false" "$second_success" "Second transfer failed"

# Verify individual record structure
first_rec_name=$(echo "$mock_vulnerable" | jq -r '.transfers[0].records[1].name')
assert_equals "example.com" "$first_rec_name" "Record name parsed correctly"

first_rec_type=$(echo "$mock_vulnerable" | jq -r '.transfers[0].records[1].type')
assert_equals "A" "$first_rec_type" "Record type parsed correctly"

first_rec_value=$(echo "$mock_vulnerable" | jq -r '.transfers[0].records[1].value')
assert_equals "93.184.216.34" "$first_rec_value" "Record value parsed correctly"

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECOND_MODULE_AXFR_LOADED" == "1" ]]; then
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
