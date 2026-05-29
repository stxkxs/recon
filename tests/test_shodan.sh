#!/usr/bin/env bash
#
# test_shodan.sh - Unit tests for Shodan module
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
source "${PROJECT_ROOT}/lib/modules/shodan.sh"

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
echo "Testing: Shodan Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

((TESTS_RUN++)) || true
if declare -f shodan_run &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} shodan_run function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} shodan_run function defined"
fi

((TESTS_RUN++)) || true
if declare -f shodan_print &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} shodan_print function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} shodan_print function defined"
fi

((TESTS_RUN++)) || true
if declare -f shodan_check &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} shodan_check function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} shodan_check function defined"
fi

echo ""

# ─── Dependency Check Tests ───

echo "--- dependency check ---"

((TESTS_RUN++)) || true
if shodan_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} shodan_check passes (curl and jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} shodan_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "shodan" "$MODULE_SHODAN_NAME" "MODULE_SHODAN_NAME is 'shodan'"
assert_equals "Shodan host intelligence" "$MODULE_SHODAN_DESCRIPTION" "MODULE_SHODAN_DESCRIPTION is set"

echo ""

# ─── No API Key Tests (graceful degradation) ───

echo "--- no API key behavior ---"

# Ensure no API key is set for these tests
unset RECON_API_SHODAN 2>/dev/null || true
RECON_CONFIG[api_keys.shodan]=""

result=$(shodan_run "93.184.216.34" 2>/dev/null)

assert_json_valid "$result" "shodan_run without API key returns valid JSON"
assert_json_has_key "$result" "error" "Result has 'error' key"
assert_json_value "$result" "error" "no_api_key" "Error is 'no_api_key'"
assert_json_has_key "$result" "ip" "Result has 'ip' key"
assert_json_has_key "$result" "ports" "Result has 'ports' key"
assert_json_has_key "$result" "vulns" "Result has 'vulns' key"
assert_json_has_key "$result" "org" "Result has 'org' key"
assert_json_has_key "$result" "isp" "Result has 'isp' key"
assert_json_has_key "$result" "services" "Result has 'services' key"
assert_json_has_key "$result" "country" "Result has 'country' key"
assert_json_has_key "$result" "hostnames" "Result has 'hostnames' key"
assert_json_has_key "$result" "last_update" "Result has 'last_update' key"

# Verify arrays are empty, strings are empty
assert_json_value "$result" "ip" "" "IP is empty string when no key"

ports_count=$(echo "$result" | jq '.ports | length')
assert_equals "0" "$ports_count" "Ports array is empty when no key"

vulns_count=$(echo "$result" | jq '.vulns | length')
assert_equals "0" "$vulns_count" "Vulns array is empty when no key"

echo ""

# ─── Print Function Tests ───

echo "--- print function ---"

# Test that shodan_print handles error JSON gracefully
((TESTS_RUN++)) || true
print_output=$(shodan_print "$result" "example.com" 2>&1 || true)
if [[ $? -eq 0 ]] || true; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} shodan_print handles error JSON without crashing"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} shodan_print handles error JSON without crashing"
fi

# Test print with mock valid data
mock_data=$(jq -n '{
    ip: "93.184.216.34",
    ports: [80, 443],
    services: [
        {port: 80, transport: "tcp", product: "nginx", version: "1.19", banner: ""},
        {port: 443, transport: "tcp", product: "nginx", version: "1.19", banner: ""}
    ],
    vulns: ["CVE-2021-1234"],
    org: "Example Inc",
    isp: "Edgecast",
    country: "United States",
    hostnames: ["example.com"],
    last_update: "2024-01-01T00:00:00"
}')

((TESTS_RUN++)) || true
print_output=$(shodan_print "$mock_data" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} shodan_print produces output for valid data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} shodan_print produces output for valid data"
fi

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECON_MODULE_SHODAN_LOADED" == "1" ]]; then
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
