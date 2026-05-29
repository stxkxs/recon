#!/usr/bin/env bash
#
# test_waf.sh - Unit tests for WAF/CDN detection module
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
source "${PROJECT_ROOT}/lib/modules/waf.sh"

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
echo "Testing: WAF/CDN Detection Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

for func in waf_run waf_print waf_check; do
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

echo "--- dependency checks ---"

((TESTS_RUN++)) || true
if waf_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} waf_check passes (curl and jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} waf_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "waf" "$MODULE_WAF_NAME" "MODULE_WAF_NAME is 'waf'"
assert_equals "WAF/CDN detection" "$MODULE_WAF_DESCRIPTION" "MODULE_WAF_DESCRIPTION is correct"

echo ""

# ─── Fingerprint Data Tests ───

echo "--- fingerprint data ---"

((TESTS_RUN++)) || true
if [[ ${#WAF_FINGERPRINTS[@]} -ge 10 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} WAF_FINGERPRINTS has ${#WAF_FINGERPRINTS[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} WAF_FINGERPRINTS should have at least 10 entries (got ${#WAF_FINGERPRINTS[@]})"
fi

# Verify known providers are in fingerprints
for provider in cloudflare incapsula sucuri akamai cloudfront azure_front_door f5 fastly; do
    ((TESTS_RUN++)) || true
    found=false
    for fp in "${WAF_FINGERPRINTS[@]}"; do
        if echo "$fp" | grep -q "$provider"; then
            found=true
            break
        fi
    done
    if $found; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} Fingerprint includes provider: $provider"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} Fingerprint missing provider: $provider"
    fi
done

echo ""

# ─── Header Matching Tests ───

echo "--- header matching logic ---"

# Test Cloudflare detection (multiple indicators)
cloudflare_headers="HTTP/1.1 200 OK
Server: cloudflare
CF-RAY: abc123-LAX
Content-Type: text/html"

cf_result=$(_waf_match_headers "$cloudflare_headers")
assert_json_valid "$cf_result" "Cloudflare matching returns valid JSON"

cf_indicators=$(echo "$cf_result" | jq '.indicators')
cf_providers=$(echo "$cf_result" | jq '.providers')

cf_count=$(echo "$cf_indicators" | jq 'length')
((TESTS_RUN++)) || true
if [[ "$cf_count" -ge 2 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Cloudflare headers produce $cf_count indicators"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Cloudflare headers should produce >= 2 indicators (got $cf_count)"
fi

cf_provider=$(_waf_primary_provider "$cf_providers")
assert_equals "cloudflare" "$cf_provider" "Primary provider detected as cloudflare"

cf_confidence=$(_waf_confidence "$cf_indicators" "$cf_provider")
assert_equals "high" "$cf_confidence" "Multiple indicators yield high confidence"

# Test Akamai detection (single non-server header)
akamai_headers="HTTP/1.1 200 OK
X-Akamai-Transformed: 9 - 0 pmb=mNONE,1
Content-Type: text/html"

ak_result=$(_waf_match_headers "$akamai_headers")
ak_indicators=$(echo "$ak_result" | jq '.indicators')
ak_count=$(echo "$ak_indicators" | jq 'length')
assert_equals "1" "$ak_count" "Akamai single header produces 1 indicator"

ak_confidence=$(_waf_confidence "$ak_indicators" "akamai")
assert_equals "medium" "$ak_confidence" "Single non-server header yields medium confidence"

# Test server-only detection (low confidence)
server_only_headers="HTTP/1.1 200 OK
Server: BigIP
Content-Type: text/html"

so_result=$(_waf_match_headers "$server_only_headers")
so_indicators=$(echo "$so_result" | jq '.indicators')
so_confidence=$(_waf_confidence "$so_indicators" "f5")
assert_equals "low" "$so_confidence" "Server-only match yields low confidence"

# Test no WAF detected
clean_headers="HTTP/1.1 200 OK
Server: Apache/2.4.41
Content-Type: text/html
X-Powered-By: PHP/7.4"

clean_result=$(_waf_match_headers "$clean_headers")
clean_indicators=$(echo "$clean_result" | jq '.indicators')
clean_count=$(echo "$clean_indicators" | jq 'length')
assert_equals "0" "$clean_count" "Clean headers produce 0 indicators"

echo ""

# ─── JSON Output Structure Tests ───

echo "--- JSON output structure ---"

# Build a mock "no WAF" result
no_waf_json=$(jq -n '{
    detected: false,
    provider: null,
    confidence: null,
    indicators: [],
    headers_checked: 10
}')

assert_json_valid "$no_waf_json" "No-WAF JSON structure is valid"
assert_json_has_key "$no_waf_json" "detected" "Has 'detected' key"
assert_json_has_key "$no_waf_json" "provider" "Has 'provider' key"
assert_json_has_key "$no_waf_json" "confidence" "Has 'confidence' key"
assert_json_has_key "$no_waf_json" "indicators" "Has 'indicators' key"
assert_json_has_key "$no_waf_json" "headers_checked" "Has 'headers_checked' key"
assert_json_value "$no_waf_json" "detected" "false" "detected is false"

# Build a mock "WAF detected" result
waf_json=$(jq -n '{
    detected: true,
    provider: "cloudflare",
    confidence: "high",
    indicators: [
        {"header": "CF-RAY", "value": "abc123-LAX"},
        {"header": "Server", "value": "cloudflare"}
    ],
    headers_checked: 15
}')

assert_json_valid "$waf_json" "WAF-detected JSON structure is valid"
assert_json_value "$waf_json" "detected" "true" "detected is true"
assert_json_value "$waf_json" "provider" "cloudflare" "provider is cloudflare"
assert_json_value "$waf_json" "confidence" "high" "confidence is high"

indicator_count=$(echo "$waf_json" | jq '.indicators | length')
assert_equals "2" "$indicator_count" "indicators array has 2 entries"

echo ""

# ─── AWS CloudFront detection ───

echo "--- additional provider tests ---"

cloudfront_headers="HTTP/2 200
X-Amz-Cf-Id: abc123def456
X-Amz-Cf-Pop: SFO5-C1
Content-Type: text/html"

cf_front_result=$(_waf_match_headers "$cloudfront_headers")
cf_front_indicators=$(echo "$cf_front_result" | jq '.indicators')
cf_front_providers=$(echo "$cf_front_result" | jq '.providers')
cf_front_count=$(echo "$cf_front_indicators" | jq 'length')
((TESTS_RUN++)) || true
if [[ "$cf_front_count" -ge 2 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} CloudFront headers produce $cf_front_count indicators"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} CloudFront headers should produce >= 2 indicators (got $cf_front_count)"
fi

cf_front_provider=$(_waf_primary_provider "$cf_front_providers")
assert_equals "cloudfront" "$cf_front_provider" "Primary provider detected as cloudfront"

# Sucuri detection
sucuri_headers="HTTP/1.1 200 OK
X-Sucuri-ID: 12345
X-Sucuri-Cache: HIT
Server: Sucuri/Cloudproxy"

sucuri_result=$(_waf_match_headers "$sucuri_headers")
sucuri_indicators=$(echo "$sucuri_result" | jq '.indicators')
sucuri_providers=$(echo "$sucuri_result" | jq '.providers')
sucuri_provider=$(_waf_primary_provider "$sucuri_providers")
assert_equals "sucuri" "$sucuri_provider" "Primary provider detected as sucuri"

sucuri_confidence=$(_waf_confidence "$sucuri_indicators" "$sucuri_provider")
assert_equals "high" "$sucuri_confidence" "Multiple Sucuri indicators yield high confidence"

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
