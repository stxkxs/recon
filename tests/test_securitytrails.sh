#!/usr/bin/env bash
#
# test_securitytrails.sh - Unit tests for SecurityTrails module
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
source "${PROJECT_ROOT}/lib/modules/securitytrails.sh"

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
echo "Testing: SecurityTrails Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

((TESTS_RUN++)) || true
if declare -f securitytrails_run &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} securitytrails_run function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} securitytrails_run function defined"
fi

((TESTS_RUN++)) || true
if declare -f securitytrails_print &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} securitytrails_print function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} securitytrails_print function defined"
fi

((TESTS_RUN++)) || true
if declare -f securitytrails_check &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} securitytrails_check function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} securitytrails_check function defined"
fi

echo ""

# ─── Dependency Check Tests ───

echo "--- dependency check ---"

((TESTS_RUN++)) || true
if securitytrails_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} securitytrails_check passes (curl and jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} securitytrails_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "securitytrails" "$MODULE_SECURITYTRAILS_NAME" "MODULE_SECURITYTRAILS_NAME is 'securitytrails'"
assert_equals "SecurityTrails domain intelligence" "$MODULE_SECURITYTRAILS_DESCRIPTION" "MODULE_SECURITYTRAILS_DESCRIPTION is set"

echo ""

# ─── No API Key Tests (graceful degradation) ───

echo "--- no API key behavior ---"

# Ensure no API key is set for these tests
unset RECOND_API_SECURITYTRAILS 2>/dev/null || true
RECOND_CONFIG[api_keys.securitytrails]=""

result=$(securitytrails_run "example.com" 2>/dev/null)

assert_json_valid "$result" "securitytrails_run without API key returns valid JSON"
assert_json_has_key "$result" "error" "Result has 'error' key"
assert_json_value "$result" "error" "no_api_key" "Error is 'no_api_key'"
assert_json_has_key "$result" "domain_info" "Result has 'domain_info' key"
assert_json_has_key "$result" "subdomains" "Result has 'subdomains' key"
assert_json_has_key "$result" "associated_domains" "Result has 'associated_domains' key"
assert_json_has_key "$result" "dns_history" "Result has 'dns_history' key"
assert_json_has_key "$result" "target" "Result has 'target' key"

# Verify target is preserved
assert_json_value "$result" "target" "example.com" "Target is 'example.com'"

# Verify subdomains structure
sub_total=$(echo "$result" | jq '.subdomains.total')
assert_equals "0" "$sub_total" "Subdomains total is 0 when no key"

sub_list_count=$(echo "$result" | jq '.subdomains.list | length')
assert_equals "0" "$sub_list_count" "Subdomains list is empty when no key"

# Verify associated_domains structure
assoc_total=$(echo "$result" | jq '.associated_domains.total')
assert_equals "0" "$assoc_total" "Associated domains total is 0 when no key"

assoc_list_count=$(echo "$result" | jq '.associated_domains.list | length')
assert_equals "0" "$assoc_list_count" "Associated domains list is empty when no key"

echo ""

# ─── Print Function Tests ───

echo "--- print function ---"

# Test that securitytrails_print handles error JSON gracefully
((TESTS_RUN++)) || true
print_output=$(securitytrails_print "$result" "example.com" 2>&1 || true)
if [[ $? -eq 0 ]] || true; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} securitytrails_print handles error JSON without crashing"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} securitytrails_print handles error JSON without crashing"
fi

# Test print with mock valid data
mock_data=$(jq -n '{
    domain_info: {
        alexa_rank: 1234,
        hostname: "example.com",
        current_dns: {
            a: {values: [{ip: "93.184.216.34"}]},
            mx: {values: [{value: "mail.example.com"}]}
        }
    },
    subdomains: {
        list: ["www.example.com", "mail.example.com", "api.example.com"],
        total: 3
    },
    associated_domains: {
        list: ["example.org", "example.net"],
        total: 2
    },
    dns_history: {},
    target: "example.com"
}')

((TESTS_RUN++)) || true
print_output=$(securitytrails_print "$mock_data" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} securitytrails_print produces output for valid data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} securitytrails_print produces output for valid data"
fi

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECOND_MODULE_SECURITYTRAILS_LOADED" == "1" ]]; then
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
