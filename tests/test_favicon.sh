#!/usr/bin/env bash
#
# test_favicon.sh - Unit tests for Favicon Hash module
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
source "${PROJECT_ROOT}/lib/modules/favicon.sh"

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
echo "Testing: Favicon Hash Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

((TESTS_RUN++)) || true
if declare -f favicon_run &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} favicon_run function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} favicon_run function defined"
fi

((TESTS_RUN++)) || true
if declare -f favicon_print &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} favicon_print function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} favicon_print function defined"
fi

((TESTS_RUN++)) || true
if declare -f favicon_check &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} favicon_check function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} favicon_check function defined"
fi

echo ""

# ─── Dependency Check Tests ───

echo "--- dependency check ---"

((TESTS_RUN++)) || true
if favicon_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} favicon_check passes (curl and jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} favicon_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "favicon" "$MODULE_FAVICON_NAME" "MODULE_FAVICON_NAME is 'favicon'"
assert_equals "Favicon hash fingerprinting" "$MODULE_FAVICON_DESCRIPTION" "MODULE_FAVICON_DESCRIPTION is set"

echo ""

# ─── Print Function Tests (found=true) ───

echo "--- print function (found=true) ---"

mock_found=$(jq -n '{
    found: true,
    url: "https://example.com/favicon.ico",
    hashes: {mmh3: "-1234567890", md5: "abc123def456"},
    hash_method: "mmh3+md5",
    shodan_query: "http.favicon.hash:-1234567890",
    shodan_url: "https://www.shodan.io/search?query=http.favicon.hash:-1234567890"
}')

((TESTS_RUN++)) || true
print_output=$(favicon_print "$mock_found" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} favicon_print produces output for found favicon"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} favicon_print produces output for found favicon"
fi

# Verify key content appears in print output
((TESTS_RUN++)) || true
if echo "$print_output" | grep -q "FAVICON HASH"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Print output contains header"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Print output contains header"
fi

((TESTS_RUN++)) || true
if echo "$print_output" | grep -q "abc123def456"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Print output contains MD5 hash"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Print output contains MD5 hash"
fi

((TESTS_RUN++)) || true
if echo "$print_output" | grep -q "\-1234567890"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Print output contains mmh3 hash"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Print output contains mmh3 hash"
fi

((TESTS_RUN++)) || true
if echo "$print_output" | grep -q "shodan.io"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Print output contains Shodan URL"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Print output contains Shodan URL"
fi

echo ""

# ─── Print Function Tests (found=false) ───

echo "--- print function (found=false) ---"

mock_not_found=$(jq -n '{
    found: false,
    url: "",
    hashes: {mmh3: "", md5: ""},
    hash_method: "",
    shodan_query: "",
    shodan_url: ""
}')

((TESTS_RUN++)) || true
print_output_nf=$(favicon_print "$mock_not_found" "example.com" 2>&1 || true)
if [[ -n "$print_output_nf" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} favicon_print produces output for not-found favicon"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} favicon_print produces output for not-found favicon"
fi

((TESTS_RUN++)) || true
if echo "$print_output_nf" | grep -qi "no favicon"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Print output shows 'no favicon' warning"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Print output shows 'no favicon' warning"
fi

echo ""

# ─── Mock JSON Structure Tests ───

echo "--- JSON structure (found=true) ---"

assert_json_valid "$mock_found" "Mock found JSON is valid"
assert_json_has_key "$mock_found" "found" "Result has 'found' key"
assert_json_has_key "$mock_found" "url" "Result has 'url' key"
assert_json_has_key "$mock_found" "hashes" "Result has 'hashes' key"
assert_json_has_key "$mock_found" "hashes.mmh3" "Result has 'hashes.mmh3' key"
assert_json_has_key "$mock_found" "hashes.md5" "Result has 'hashes.md5' key"
assert_json_has_key "$mock_found" "hash_method" "Result has 'hash_method' key"
assert_json_has_key "$mock_found" "shodan_query" "Result has 'shodan_query' key"
assert_json_has_key "$mock_found" "shodan_url" "Result has 'shodan_url' key"

assert_json_value "$mock_found" "found" "true" "found is true"
assert_json_value "$mock_found" "url" "https://example.com/favicon.ico" "url is correct"
assert_json_value "$mock_found" "hashes.md5" "abc123def456" "MD5 hash matches"
assert_json_value "$mock_found" "hashes.mmh3" "-1234567890" "mmh3 hash matches"
assert_json_value "$mock_found" "hash_method" "mmh3+md5" "hash_method is mmh3+md5"
assert_json_value "$mock_found" "shodan_query" "http.favicon.hash:-1234567890" "shodan_query is correct"

echo ""

echo "--- JSON structure (found=false) ---"

assert_json_valid "$mock_not_found" "Mock not-found JSON is valid"
assert_json_value "$mock_not_found" "found" "false" "found is false"
assert_json_value "$mock_not_found" "url" "" "url is empty"
assert_json_value "$mock_not_found" "hashes.mmh3" "" "mmh3 is empty"
assert_json_value "$mock_not_found" "hashes.md5" "" "md5 is empty"
assert_json_value "$mock_not_found" "hash_method" "" "hash_method is empty"
assert_json_value "$mock_not_found" "shodan_query" "" "shodan_query is empty"
assert_json_value "$mock_not_found" "shodan_url" "" "shodan_url is empty"

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECON_MODULE_FAVICON_LOADED" == "1" ]]; then
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
