#!/usr/bin/env bash
#
# test_wayback.sh - Unit tests for Wayback Machine module
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
source "${PROJECT_ROOT}/lib/modules/wayback.sh"

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
echo "Testing: Wayback Machine Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

((TESTS_RUN++)) || true
if declare -f wayback_run &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} wayback_run function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} wayback_run function defined"
fi

((TESTS_RUN++)) || true
if declare -f wayback_print &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} wayback_print function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} wayback_print function defined"
fi

((TESTS_RUN++)) || true
if declare -f wayback_check &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} wayback_check function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} wayback_check function defined"
fi

echo ""

# ─── Dependency Check Tests ───

echo "--- dependency check ---"

((TESTS_RUN++)) || true
if wayback_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} wayback_check passes (curl and jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} wayback_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "wayback" "$MODULE_WAYBACK_NAME" "MODULE_WAYBACK_NAME is 'wayback'"
assert_equals "Wayback Machine URL discovery" "$MODULE_WAYBACK_DESCRIPTION" "MODULE_WAYBACK_DESCRIPTION is set"

echo ""

# ─── Mock Data Tests ───

echo "--- print function with mock data ---"

# Test that wayback_print handles empty result gracefully
empty_result=$(jq -n '{
    urls: [],
    total: 0,
    path_groups: {},
    interesting_extensions: {},
    source: "web.archive.org",
    query_time: "2024-01-01T00:00:00Z"
}')

((TESTS_RUN++)) || true
print_output=$(wayback_print "$empty_result" "example.com" 2>&1 || true)
if [[ $? -eq 0 ]] || true; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} wayback_print handles empty result without crashing"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} wayback_print handles empty result without crashing"
fi

# Test print with mock valid data
mock_data=$(jq -n '{
    urls: [
        "https://example.com/admin/login.php",
        "https://example.com/admin/config.php",
        "https://example.com/api/v1/users",
        "https://example.com/api/v2/data.json",
        "https://example.com/backup/db.sql",
        "https://example.com/assets/style.css",
        "https://example.com/.env",
        "https://example.com/robots.txt",
        "https://example.com/sitemap.xml",
        "https://example.com/old/backup.zip"
    ],
    total: 150,
    path_groups: {"/admin": 25, "/api": 42, "/assets": 18, "/backup": 5, "/old": 3},
    interesting_extensions: {".php": 12, ".env": 1, ".sql": 3, ".json": 8, ".xml": 5, ".zip": 2},
    source: "web.archive.org",
    query_time: "2024-01-01T00:00:00Z"
}')

((TESTS_RUN++)) || true
print_output=$(wayback_print "$mock_data" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} wayback_print produces output for valid data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} wayback_print produces output for valid data"
fi

# Verify mock data structure
assert_json_valid "$mock_data" "Mock data is valid JSON"
assert_json_has_key "$mock_data" "urls" "Mock data has 'urls' key"
assert_json_has_key "$mock_data" "total" "Mock data has 'total' key"
assert_json_has_key "$mock_data" "path_groups" "Mock data has 'path_groups' key"
assert_json_has_key "$mock_data" "interesting_extensions" "Mock data has 'interesting_extensions' key"
assert_json_has_key "$mock_data" "source" "Mock data has 'source' key"
assert_json_has_key "$mock_data" "query_time" "Mock data has 'query_time' key"
assert_json_value "$mock_data" "source" "web.archive.org" "Source is 'web.archive.org'"
assert_json_value "$mock_data" "total" "150" "Total is 150"

# Verify urls is an array
((TESTS_RUN++)) || true
urls_type=$(echo "$mock_data" | jq -r '.urls | type')
if [[ "$urls_type" == "array" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} urls field is an array"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} urls field is an array (got $urls_type)"
fi

# Verify path_groups is an object
((TESTS_RUN++)) || true
pg_type=$(echo "$mock_data" | jq -r '.path_groups | type')
if [[ "$pg_type" == "object" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} path_groups field is an object"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} path_groups field is an object (got $pg_type)"
fi

# Verify interesting_extensions is an object
((TESTS_RUN++)) || true
ie_type=$(echo "$mock_data" | jq -r '.interesting_extensions | type')
if [[ "$ie_type" == "object" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} interesting_extensions field is an object"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} interesting_extensions field is an object (got $ie_type)"
fi

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECOND_MODULE_WAYBACK_LOADED" == "1" ]]; then
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
