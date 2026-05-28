#!/usr/bin/env bash
#
# test_virustotal.sh - Unit tests for VirusTotal module
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
source "${PROJECT_ROOT}/lib/modules/virustotal.sh"

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
echo "Testing: VirusTotal Module"
echo "================================================"
echo ""

# ─── Dependency Check ───

echo "--- virustotal dependency checks ---"

# Test virustotal_check passes (curl and jq should be available)
((TESTS_RUN++)) || true
if virustotal_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} virustotal_check passes (curl and jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} virustotal_check passes"
fi

echo ""

# ─── Function Existence ───

echo "--- virustotal function existence ---"

for func in virustotal_run virustotal_print virustotal_check; do
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

# ─── Module Info ───

echo "--- virustotal module info ---"

assert_equals "virustotal" "$MODULE_VIRUSTOTAL_NAME" "MODULE_VIRUSTOTAL_NAME is 'virustotal'"
assert_equals "VirusTotal reputation analysis" "$MODULE_VIRUSTOTAL_DESCRIPTION" "MODULE_VIRUSTOTAL_DESCRIPTION is set"

echo ""

# ─── No API Key Behavior ───

echo "--- virustotal without API key ---"

# Ensure no API key is set
unset RECOND_API_VIRUSTOTAL 2>/dev/null || true

# Initialize config so get_api_key works
load_config 2>/dev/null || true

result=$(virustotal_run "example.com" 2>/dev/null)

assert_json_valid "$result" "virustotal_run without API key returns valid JSON"
assert_json_has_key "$result" "error" "Result has error field"
assert_json_value "$result" "error" "no_api_key" "Error is 'no_api_key'"
assert_json_has_key "$result" "reputation" "Result has reputation field"
assert_json_has_key "$result" "detections" "Result has detections field"
assert_json_has_key "$result" "categories" "Result has categories field"
assert_json_has_key "$result" "target" "Result has target field"
assert_json_has_key "$result" "target_type" "Result has target_type field"
assert_json_value "$result" "target" "example.com" "Target is 'example.com'"
assert_json_value "$result" "target_type" "domain" "Target type is 'domain'"
assert_json_value "$result" "reputation" "0" "Reputation defaults to 0"

echo ""

# ─── IP Target Detection ───

echo "--- virustotal IP target detection ---"

ip_result=$(virustotal_run "93.184.216.34" 2>/dev/null)

assert_json_valid "$ip_result" "virustotal_run with IP returns valid JSON"
assert_json_value "$ip_result" "target" "93.184.216.34" "IP target is preserved"
assert_json_value "$ip_result" "target_type" "ip" "IP target type is 'ip'"

echo ""

# ─── Print Function (smoke test) ───

echo "--- virustotal_print smoke test ---"

# Test that virustotal_print doesn't crash with no-API-key JSON
((TESTS_RUN++)) || true
if virustotal_print "$result" "example.com" >/dev/null 2>&1; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} virustotal_print handles no_api_key error gracefully"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} virustotal_print handles no_api_key error gracefully"
fi

# Test with mock successful data
mock_result=$(jq -n '{
    reputation: 5,
    detections: {
        malicious: 0,
        suspicious: 1,
        harmless: 70,
        undetected: 12
    },
    categories: {"Forcepoint": "information technology", "Sophos": "information technology"},
    last_analysis_date: "2024-01-15",
    target: "example.com",
    target_type: "domain"
}')

((TESTS_RUN++)) || true
if virustotal_print "$mock_result" "example.com" >/dev/null 2>&1; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} virustotal_print handles successful result"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} virustotal_print handles successful result"
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
