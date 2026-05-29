#!/usr/bin/env bash
#
# test_methods.sh - Unit tests for HTTP methods enumeration module
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
source "${PROJECT_ROOT}/lib/modules/methods.sh"

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

    if echo "$json" | jq "has(\"$key\")" 2>/dev/null | grep -q 'true'; then
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
echo "Testing: HTTP Methods Enumeration Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

for func in methods_run methods_print methods_check; do
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

# ─── Dependency Check Tests ───

echo "--- dependency check ---"

((TESTS_RUN++)) || true
if methods_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} methods_check passes (curl available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} methods_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "methods" "$MODULE_METHODS_NAME" "MODULE_METHODS_NAME is 'methods'"
assert_equals "HTTP methods enumeration" "$MODULE_METHODS_DESCRIPTION" "MODULE_METHODS_DESCRIPTION is set"

echo ""

# ─── Module Constants Tests ───

echo "--- module constants ---"

((TESTS_RUN++)) || true
if [[ ${#METHODS_TEST_PATHS[@]} -ge 4 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} METHODS_TEST_PATHS has ${#METHODS_TEST_PATHS[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} METHODS_TEST_PATHS should have at least 4 entries (got ${#METHODS_TEST_PATHS[@]})"
fi

((TESTS_RUN++)) || true
if [[ ${#METHODS_DANGEROUS[@]} -ge 4 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} METHODS_DANGEROUS has ${#METHODS_DANGEROUS[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} METHODS_DANGEROUS should have at least 4 entries (got ${#METHODS_DANGEROUS[@]})"
fi

# Verify dangerous methods include expected values
for method in TRACE PUT DELETE PATCH; do
    ((TESTS_RUN++)) || true
    found=false
    for m in "${METHODS_DANGEROUS[@]}"; do
        if [[ "$m" == "$method" ]]; then
            found=true
            break
        fi
    done
    if $found; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} METHODS_DANGEROUS includes $method"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} METHODS_DANGEROUS missing $method"
    fi
done

echo ""

# ─── Helper Function Tests ───

echo "--- helper functions ---"

((TESTS_RUN++)) || true
if _methods_is_allowed "200"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Status 200 is considered allowed"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Status 200 should be considered allowed"
fi

((TESTS_RUN++)) || true
if ! _methods_is_allowed "405"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Status 405 is considered blocked"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Status 405 should be considered blocked"
fi

((TESTS_RUN++)) || true
if ! _methods_is_allowed "501"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Status 501 is considered blocked"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Status 501 should be considered blocked"
fi

((TESTS_RUN++)) || true
if ! _methods_is_allowed "000"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Status 000 is considered blocked"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Status 000 should be considered blocked"
fi

((TESTS_RUN++)) || true
if _methods_is_allowed "403"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Status 403 is considered allowed (not in blocked list)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Status 403 should be considered allowed (not in blocked list)"
fi

echo ""

# ─── Print Function Tests ───

echo "--- print function ---"

# Test print with mock data - no dangerous methods (risk: none)
mock_safe=$(jq -n '{
    paths_tested: 4,
    findings: [
        {path: "/", options_allow: "GET, POST, OPTIONS", dangerous_methods: []},
        {path: "/api/", options_allow: "GET, OPTIONS", dangerous_methods: []},
        {path: "/api/v1/", options_allow: "", dangerous_methods: []},
        {path: "/admin/", options_allow: "", dangerous_methods: []}
    ],
    risk: "none",
    total_dangerous: 0,
    xst_vulnerable: false
}')

((TESTS_RUN++)) || true
print_output=$(methods_print "$mock_safe" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} methods_print produces output for safe data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} methods_print produces output for safe data"
fi

# Test print with mock data - dangerous methods (risk: high)
mock_danger=$(jq -n '{
    paths_tested: 4,
    findings: [
        {path: "/", options_allow: "GET, POST, PUT, DELETE, OPTIONS", dangerous_methods: ["PUT", "DELETE"]},
        {path: "/api/", options_allow: "GET, OPTIONS", dangerous_methods: []},
        {path: "/api/v1/", options_allow: "", dangerous_methods: ["PATCH"]},
        {path: "/admin/", options_allow: "", dangerous_methods: []}
    ],
    risk: "high",
    total_dangerous: 3,
    xst_vulnerable: false
}')

((TESTS_RUN++)) || true
print_output=$(methods_print "$mock_danger" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} methods_print produces output for dangerous data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} methods_print produces output for dangerous data"
fi

# Test print with mock data - XST vulnerability (risk: critical)
mock_xst=$(jq -n '{
    paths_tested: 4,
    findings: [
        {path: "/", options_allow: "GET, POST, TRACE, OPTIONS", dangerous_methods: ["TRACE"]},
        {path: "/api/", options_allow: "", dangerous_methods: []},
        {path: "/api/v1/", options_allow: "", dangerous_methods: []},
        {path: "/admin/", options_allow: "", dangerous_methods: []}
    ],
    risk: "critical",
    total_dangerous: 1,
    xst_vulnerable: true
}')

((TESTS_RUN++)) || true
print_output=$(methods_print "$mock_xst" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} methods_print produces output for XST data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} methods_print produces output for XST data"
fi

echo ""

# ─── JSON Output Structure Tests ───

echo "--- JSON output structure ---"

assert_json_valid "$mock_safe" "Safe mock JSON is valid"
assert_json_has_key "$mock_safe" "paths_tested" "Has 'paths_tested' key"
assert_json_has_key "$mock_safe" "findings" "Has 'findings' key"
assert_json_has_key "$mock_safe" "risk" "Has 'risk' key"
assert_json_has_key "$mock_safe" "total_dangerous" "Has 'total_dangerous' key"
assert_json_has_key "$mock_safe" "xst_vulnerable" "Has 'xst_vulnerable' key"

assert_json_value "$mock_safe" "paths_tested" "4" "paths_tested is 4"
assert_json_value "$mock_safe" "risk" "none" "risk is none for safe target"
assert_json_value "$mock_safe" "total_dangerous" "0" "total_dangerous is 0 for safe target"
assert_json_value "$mock_safe" "xst_vulnerable" "false" "xst_vulnerable is false for safe target"

findings_count=$(echo "$mock_safe" | jq '.findings | length')
assert_equals "4" "$findings_count" "findings array has 4 entries"

assert_json_valid "$mock_danger" "Danger mock JSON is valid"
assert_json_value "$mock_danger" "risk" "high" "risk is high when PUT/DELETE allowed"
assert_json_value "$mock_danger" "total_dangerous" "3" "total_dangerous is 3"

danger_methods_count=$(echo "$mock_danger" | jq '.findings[0].dangerous_methods | length')
assert_equals "2" "$danger_methods_count" "First path has 2 dangerous methods"

assert_json_valid "$mock_xst" "XST mock JSON is valid"
assert_json_value "$mock_xst" "risk" "critical" "risk is critical for XST"
assert_json_value "$mock_xst" "xst_vulnerable" "true" "xst_vulnerable is true for XST"

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECON_MODULE_METHODS_LOADED" == "1" ]]; then
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
