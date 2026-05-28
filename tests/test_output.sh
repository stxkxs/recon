#!/usr/bin/env bash
#
# test_output.sh - Unit tests for output formatting
#

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Force colors for test output
export RECOND_COLOR=always

# Source the modules
source "${PROJECT_ROOT}/lib/core/common.sh"
source "${PROJECT_ROOT}/lib/core/output.sh"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors are already defined in common.sh

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
        echo "  Invalid JSON: $json"
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
echo "Testing: lib/core/output.sh"
echo "================================================"
echo ""

# Test json_init
echo "--- json_init ---"
result=$(json_init "https://example.com" "example.com")
assert_json_valid "$result" "json_init produces valid JSON"
assert_json_has_key "$result" "meta" "Has meta key"
assert_json_has_key "$result" "target" "Has target key"
assert_json_has_key "$result" "results" "Has results key"
assert_json_has_key "$result" "errors" "Has errors key"
assert_json_value "$result" "target" "example.com" "Target value is correct"
assert_json_value "$result" "meta.target_original" "https://example.com" "Original target preserved"
assert_json_value "$result" "meta.target_normalized" "example.com" "Normalized target correct"
echo ""

# Test json_add_result
echo "--- json_add_result ---"
base=$(json_init "example.com" "example.com")
data='{"a": ["192.168.1.1"], "aaaa": []}'
result=$(echo "$base" | json_add_result "dns" "success" "$data")
assert_json_valid "$result" "json_add_result produces valid JSON"
assert_json_has_key "$result" "results.dns" "Has dns result"
assert_json_value "$result" "results.dns.status" "success" "DNS status is success"
echo ""

# Test json_add_error
echo "--- json_add_error ---"
base=$(json_init "example.com" "example.com")
result=$(echo "$base" | json_add_error "ssl" "api.example.com" "connection timeout")
assert_json_valid "$result" "json_add_error produces valid JSON"
error_count=$(echo "$result" | jq '.errors | length')
assert_equals "1" "$error_count" "Has one error"
error_module=$(echo "$result" | jq -r '.errors[0].module')
assert_equals "ssl" "$error_module" "Error module is ssl"
echo ""

# Test json_add_conflict
echo "--- json_add_conflict ---"
base=$(json_init "example.com" "example.com")
evidence='{"headers": "cloudflare", "dns": "cloudfront"}'
result=$(echo "$base" | json_add_conflict "cdn" "$evidence")
assert_json_valid "$result" "json_add_conflict produces valid JSON"
conflict_count=$(echo "$result" | jq '.conflicts | length')
assert_equals "1" "$conflict_count" "Has one conflict"
echo ""

# Test json_finalize
echo "--- json_finalize ---"
base=$(json_init "example.com" "example.com")
data='{"a": ["192.168.1.1"]}'
base=$(echo "$base" | json_add_result "dns" "success" "$data")
result=$(echo "$base" | json_finalize)
assert_json_valid "$result" "json_finalize produces valid JSON"
assert_json_has_key "$result" "meta.ended_at" "Has ended_at timestamp"
assert_json_has_key "$result" "summary" "Has summary"
assert_json_has_key "$result" "summary.modules_run" "Has modules_run count"
echo ""

# Test json_object
echo "--- json_object ---"
result=$(json_object "key1" "value1" "key2" "value2")
assert_json_valid "$result" "json_object produces valid JSON"
assert_json_value "$result" "key1" "value1" "key1 has correct value"
assert_json_value "$result" "key2" "value2" "key2 has correct value"
echo ""

# Test json_array
echo "--- json_array ---"
result=$(json_array "item1" "item2" "item3")
assert_json_valid "$result" "json_array produces valid JSON"
length=$(echo "$result" | jq 'length')
assert_equals "3" "$length" "Array has 3 items"
first=$(echo "$result" | jq -r '.[0]')
assert_equals "item1" "$first" "First item is correct"
echo ""

# Test json_array_from_lines
echo "--- json_array_from_lines ---"
result=$(echo -e "line1\nline2\nline3" | json_array_from_lines)
assert_json_valid "$result" "json_array_from_lines produces valid JSON"
length=$(echo "$result" | jq 'length')
assert_equals "3" "$length" "Array has 3 items from lines"
echo ""

# Test json_escape
echo "--- json_escape ---"
result=$(json_escape 'string with "quotes"')
# Should be a valid JSON string (with outer quotes)
assert_json_valid "$result" "json_escape produces valid JSON string"
echo ""

# Test full workflow
echo "--- Full workflow ---"
json=$(json_init "https://EXAMPLE.COM/path" "example.com")
json=$(echo "$json" | json_add_result "dns" "success" '{"a": ["93.184.216.34"]}')
json=$(echo "$json" | json_add_result "ssl" "success" '{"issuer": "DigiCert"}')
json=$(echo "$json" | json_add_error "http" "example.com" "timeout")
json=$(echo "$json" | json_finalize)
assert_json_valid "$json" "Full workflow produces valid JSON"
modules_run=$(echo "$json" | jq '.summary.modules_run')
assert_equals "2" "$modules_run" "Summary shows 2 modules run"
errors_count=$(echo "$json" | jq '.summary.total_errors')
assert_equals "1" "$errors_count" "Summary shows 1 error"
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
