#!/usr/bin/env bash
#
# test_takeover.sh - Unit tests for subdomain takeover detection module
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
source "${PROJECT_ROOT}/lib/modules/takeover.sh"

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
echo "Testing: Subdomain Takeover Detection Module"
echo "================================================"
echo ""

# ─── Basic Module Tests ───

echo "--- takeover module basics ---"

# Test takeover_check (dependency check)
((TESTS_RUN++)) || true
if takeover_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} takeover_check passes (dig, curl, jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} takeover_check passes"
fi

# Test required functions exist
for func in takeover_run takeover_print takeover_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

# Test helper functions exist
for func in takeover_match_service takeover_is_dangling takeover_check_fingerprint; do
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

# ─── Data Structure Tests ───

echo "--- data structures ---"

# Test TAKEOVER_SERVICES is populated
((TESTS_RUN++)) || true
if [[ ${#TAKEOVER_SERVICES[@]} -ge 20 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} TAKEOVER_SERVICES has ${#TAKEOVER_SERVICES[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} TAKEOVER_SERVICES should have >= 20 entries, got ${#TAKEOVER_SERVICES[@]}"
fi

# Test specific service mappings
assert_equals "GitHub Pages" "${TAKEOVER_SERVICES[.github.io]}" "TAKEOVER_SERVICES maps .github.io to GitHub Pages"
assert_equals "Heroku" "${TAKEOVER_SERVICES[.herokuapp.com]}" "TAKEOVER_SERVICES maps .herokuapp.com to Heroku"
assert_equals "AWS S3" "${TAKEOVER_SERVICES[.s3.amazonaws.com]}" "TAKEOVER_SERVICES maps .s3.amazonaws.com to AWS S3"
assert_equals "Shopify" "${TAKEOVER_SERVICES[.myshopify.com]}" "TAKEOVER_SERVICES maps .myshopify.com to Shopify"
assert_equals "Netlify" "${TAKEOVER_SERVICES[.netlify.app]}" "TAKEOVER_SERVICES maps .netlify.app to Netlify"
assert_equals "Vercel" "${TAKEOVER_SERVICES[.vercel.app]}" "TAKEOVER_SERVICES maps .vercel.app to Vercel"

# Test TAKEOVER_FINGERPRINTS is populated
((TESTS_RUN++)) || true
if [[ ${#TAKEOVER_FINGERPRINTS[@]} -ge 5 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} TAKEOVER_FINGERPRINTS has ${#TAKEOVER_FINGERPRINTS[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} TAKEOVER_FINGERPRINTS should have >= 5 entries, got ${#TAKEOVER_FINGERPRINTS[@]}"
fi

# Test specific fingerprint mappings
assert_equals "GitHub Pages" "${TAKEOVER_FINGERPRINTS["There isn't a GitHub Pages site here"]}" "Fingerprint maps GitHub Pages error"
assert_equals "Heroku" "${TAKEOVER_FINGERPRINTS["No such app"]}" "Fingerprint maps Heroku error"
assert_equals "AWS S3" "${TAKEOVER_FINGERPRINTS["NoSuchBucket"]}" "Fingerprint maps S3 error"

echo ""

# ─── Service Matching Tests ───

echo "--- service matching ---"

# Test takeover_match_service with known CNAMEs
result=$(takeover_match_service "mysite.github.io")
assert_equals "GitHub Pages" "$result" "Matches .github.io as GitHub Pages"

result=$(takeover_match_service "myapp.herokuapp.com")
assert_equals "Heroku" "$result" "Matches .herokuapp.com as Heroku"

result=$(takeover_match_service "bucket.s3.amazonaws.com")
assert_equals "AWS S3" "$result" "Matches .s3.amazonaws.com as AWS S3"

result=$(takeover_match_service "shop.myshopify.com")
assert_equals "Shopify" "$result" "Matches .myshopify.com as Shopify"

result=$(takeover_match_service "site.netlify.app")
assert_equals "Netlify" "$result" "Matches .netlify.app as Netlify"

# Test no match
result=$(takeover_match_service "example.com") || true
assert_equals "" "$result" "No match for generic domain"

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "takeover" "$MODULE_TAKEOVER_NAME" "MODULE_TAKEOVER_NAME is takeover"
assert_equals "Subdomain takeover detection" "$MODULE_TAKEOVER_DESCRIPTION" "MODULE_TAKEOVER_DESCRIPTION is correct"

echo ""

# ─── Run Without Scan Data ───

echo "--- takeover_run without scan data ---"

# Unset RECON_SCAN_JSON to test fallback behavior
unset RECON_SCAN_JSON 2>/dev/null || true

result=$(takeover_run "example.com")
assert_json_valid "$result" "takeover_run without scan data returns valid JSON"
assert_json_has_key "$result" "vulnerable" "Result has vulnerable key"
assert_json_has_key "$result" "checked" "Result has checked key"
assert_json_has_key "$result" "total_subdomains" "Result has total_subdomains key"
assert_json_has_key "$result" "findings" "Result has findings key"

# vulnerable and findings should be arrays
((TESTS_RUN++)) || true
vuln_type=$(echo "$result" | jq -r '.vulnerable | type')
if [[ "$vuln_type" == "array" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} vulnerable is an array"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} vulnerable should be array, got $vuln_type"
fi

((TESTS_RUN++)) || true
findings_type=$(echo "$result" | jq -r '.findings | type')
if [[ "$findings_type" == "array" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} findings is an array"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} findings should be array, got $findings_type"
fi

echo ""

# ─── Run With Mock Scan Data ───

echo "--- takeover_run with mock scan data ---"

# Create mock scan JSON with subdomain data that includes CNAMEs
export RECON_SCAN_JSON
RECON_SCAN_JSON=$(jq -n '{
    results: {
        subdomain: {
            data: {
                found: [
                    {fqdn: "www.example.com", ip: "93.184.216.34", cname: null},
                    {fqdn: "blog.example.com", ip: "93.184.216.34", cname: "example.ghost.io."},
                    {fqdn: "app.example.com", ip: "1.2.3.4", cname: "example.herokuapp.com."},
                    {fqdn: "docs.example.com", ip: "5.6.7.8", cname: null},
                    {fqdn: "shop.example.com", ip: "9.10.11.12", cname: "example.myshopify.com."}
                ],
                checked: 50,
                total: 50
            }
        }
    }
}')

result=$(takeover_run "example.com")
assert_json_valid "$result" "takeover_run with scan data returns valid JSON"
assert_json_has_key "$result" "vulnerable" "Scan result has vulnerable key"
assert_json_has_key "$result" "findings" "Scan result has findings key"
assert_json_has_key "$result" "checked" "Scan result has checked key"
assert_json_has_key "$result" "total_subdomains" "Scan result has total_subdomains key"

# Should have processed 5 subdomains
assert_json_value "$result" "total_subdomains" "5" "total_subdomains is 5"

# checked should be 5
assert_json_value "$result" "checked" "5" "checked is 5"

unset RECON_SCAN_JSON

echo ""

# ─── Run With Empty Subdomain Data ───

echo "--- takeover_run with empty scan data ---"

export RECON_SCAN_JSON
RECON_SCAN_JSON=$(jq -n '{
    results: {
        subdomain: {
            data: {
                found: [],
                checked: 0,
                total: 0
            }
        }
    }
}')

result=$(takeover_run "example.com")
assert_json_valid "$result" "takeover_run with empty scan data returns valid JSON"

# With no subdomains found, it should fall back to checking the target itself
((TESTS_RUN++)) || true
total=$(echo "$result" | jq '.total_subdomains')
if [[ "$total" -ge 1 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Falls back to checking target domain when no subdomains found"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Should fall back to target domain check, got total=$total"
fi

unset RECON_SCAN_JSON

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
