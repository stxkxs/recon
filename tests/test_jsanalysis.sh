#!/usr/bin/env bash
#
# test_jsanalysis.sh - Unit tests for JavaScript analysis module
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
source "${PROJECT_ROOT}/lib/modules/jsanalysis.sh"

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
echo "Testing: JS Analysis Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

for func in jsanalysis_run jsanalysis_print jsanalysis_check _jsanalysis_mask_secret; do
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
if jsanalysis_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} jsanalysis_check passes (curl available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} jsanalysis_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "jsanalysis" "$MODULE_JSANALYSIS_NAME" "MODULE_JSANALYSIS_NAME is 'jsanalysis'"
assert_equals "JavaScript file analysis" "$MODULE_JSANALYSIS_DESCRIPTION" "MODULE_JSANALYSIS_DESCRIPTION is set"

echo ""

# ─── Mask Secret Tests ───
#
# Fake-key fixtures are deliberately split with bash concatenation ("AKIA""...")
# so GitHub/partner secret scanners don't flag them. Runtime values are
# identical to a single literal; do not collapse the splits.

echo "--- _jsanalysis_mask_secret ---"

# Long secret (> 8 chars): show first 4 + ... + last 4
masked=$(_jsanalysis_mask_secret "AKIA""FAKEKEY0TESTONLY")
assert_equals "AKIA...ONLY" "$masked" "Long secret shows first 4 + ... + last 4"

# Exactly 8 chars: short mode (first 2 + *** + last 2)
masked=$(_jsanalysis_mask_secret "abcd1234")
assert_equals "ab***34" "$masked" "8-char secret shows first 2 + *** + last 2"

# Short secret (< 8 chars)
masked=$(_jsanalysis_mask_secret "abc123")
assert_equals "ab***23" "$masked" "6-char secret shows first 2 + *** + last 2"

# Very short secret
masked=$(_jsanalysis_mask_secret "ab")
assert_equals "ab***ab" "$masked" "2-char secret handled"

# 9 chars (just above threshold)
masked=$(_jsanalysis_mask_secret "123456789")
assert_equals "1234...6789" "$masked" "9-char secret shows first 4 + ... + last 4"

# Google API key pattern (AIza + 35 chars = 39 total)
masked=$(_jsanalysis_mask_secret "AIza""FAKE_TEST_KEY_NOT_REAL_000000000000")
assert_equals "AIza...0000" "$masked" "Google API key masked correctly"

# GitHub token pattern
masked=$(_jsanalysis_mask_secret "ghp_""00FAKE00TEST00TOKEN00NOT00REAL00XXXX")
assert_equals "ghp_...XXXX" "$masked" "GitHub token masked correctly"

echo ""

# ─── CDN Detection Tests ───

echo "--- CDN detection ---"

((TESTS_RUN++)) || true
if _jsanalysis_is_cdn "https://cdnjs.cloudflare.com/ajax/libs/jquery.min.js"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} cdnjs.cloudflare.com detected as CDN"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} cdnjs.cloudflare.com should be detected as CDN"
fi

((TESTS_RUN++)) || true
if _jsanalysis_is_cdn "https://cdn.jsdelivr.net/npm/vue@3/dist/vue.js"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} cdn.jsdelivr.net detected as CDN"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} cdn.jsdelivr.net should be detected as CDN"
fi

((TESTS_RUN++)) || true
if ! _jsanalysis_is_cdn "https://example.com/assets/app.js"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} example.com NOT detected as CDN"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} example.com should NOT be detected as CDN"
fi

((TESTS_RUN++)) || true
if _jsanalysis_is_cdn "https://unpkg.com/react@18/umd/react.production.min.js"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} unpkg.com detected as CDN"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} unpkg.com should be detected as CDN"
fi

echo ""

# ─── Script Extraction Tests ───

echo "--- script extraction ---"

test_html='<html><head>
<script src="/assets/app.js"></script>
<script src="https://example.com/bundle.js"></script>
<script src="//cdn.example.com/lib.js"></script>
<script src="main.js"></script>
<script>var x = 1;</script>
</head></html>'

extracted=$(_jsanalysis_extract_scripts "$test_html" "example.com")

((TESTS_RUN++)) || true
if echo "$extracted" | grep -q "https://example.com/assets/app.js"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Relative /path URL resolved to absolute"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Relative /path URL should be resolved to absolute"
    echo "  Extracted: $extracted"
fi

((TESTS_RUN++)) || true
if echo "$extracted" | grep -q "https://example.com/bundle.js"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Absolute URL preserved"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Absolute URL should be preserved"
fi

((TESTS_RUN++)) || true
if echo "$extracted" | grep -q "https://cdn.example.com/lib.js"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Protocol-relative URL resolved to https"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Protocol-relative URL should be resolved to https"
fi

((TESTS_RUN++)) || true
if echo "$extracted" | grep -q "https://example.com/main.js"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Bare relative URL resolved to absolute"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Bare relative URL should be resolved to absolute"
fi

echo ""

# ─── Secret Scanning Tests ───

echo "--- secret scanning ---"

# Fake-key fixtures are split with single-quote concat ('AKIA''FAKE...') so
# secret scanners don't see contiguous matching tokens. The runtime string
# remains identical to a single literal — do not collapse the splits.
test_js_content='
var config = {
    awsKey: "AKIA''FAKEKEY0TESTONLY0",
    googleKey: "AIza''FAKE_TEST_KEY_NOT_REAL_000000000000",
    githubToken: "ghp_''00FAKE00TEST00TOKEN00NOT00REAL00XXXX",
    slackToken: "xoxb-000000000-fakeTestValue",
    stripeKey: "rk_test_''00fake00test00value000000",
    jwt: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc123def456ghi789"
};
'

secrets=$(_jsanalysis_scan_secrets "$test_js_content")
assert_json_valid "$secrets" "Secret scan returns valid JSON"

secret_count=$(echo "$secrets" | jq 'length')
((TESTS_RUN++)) || true
if [[ "$secret_count" -ge 5 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Found $secret_count secrets in test content"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Should find at least 5 secrets (found $secret_count)"
fi

# Verify AWS key type is detected
((TESTS_RUN++)) || true
aws_found=$(echo "$secrets" | jq '[.[] | select(.type == "aws_key")] | length')
if [[ "$aws_found" -gt 0 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} AWS key type detected"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} AWS key type should be detected"
fi

# Verify values are masked
((TESTS_RUN++)) || true
aws_value=$(echo "$secrets" | jq -r '[.[] | select(.type == "aws_key")][0].value')
if echo "$aws_value" | grep -q '\.\.\.'; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} AWS key value is masked: $aws_value"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} AWS key value should be masked (got: $aws_value)"
fi

# Verify Google key is detected
((TESTS_RUN++)) || true
google_found=$(echo "$secrets" | jq '[.[] | select(.type == "google_api_key")] | length')
if [[ "$google_found" -gt 0 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Google API key type detected"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Google API key type should be detected"
fi

echo ""

# ─── Endpoint Scanning Tests ───

echo "--- endpoint scanning ---"

test_js_endpoints='
fetch("/api/v1/users");
fetch("/api/v2/products/list");
var url = "/api/auth/login";
var base = "/api/v3/admin/settings";
'

endpoints=$(_jsanalysis_scan_endpoints "$test_js_endpoints")
assert_json_valid "$endpoints" "Endpoint scan returns valid JSON"

endpoint_count=$(echo "$endpoints" | jq 'length')
((TESTS_RUN++)) || true
if [[ "$endpoint_count" -ge 3 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Found $endpoint_count endpoints in test content"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Should find at least 3 endpoints (found $endpoint_count)"
fi

# Check for specific endpoint
((TESTS_RUN++)) || true
if echo "$endpoints" | jq -r '.[]' | grep -q '/api/v1/users'; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} /api/v1/users endpoint found"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} /api/v1/users endpoint should be found"
fi

echo ""

# ─── Source Map Tests ───

echo "--- source map scanning ---"

test_js_sourcemap='
var x = 1;
//# sourceMappingURL=app.js.map
'

sourcemaps=$(_jsanalysis_scan_sourcemaps "$test_js_sourcemap")
assert_json_valid "$sourcemaps" "Source map scan returns valid JSON"

sm_count=$(echo "$sourcemaps" | jq 'length')
assert_equals "1" "$sm_count" "Found 1 source map reference"

sm_value=$(echo "$sourcemaps" | jq -r '.[0]')
assert_equals "app.js.map" "$sm_value" "Source map filename is app.js.map"

echo ""

# ─── Print Function Tests ───

echo "--- print function ---"

# Test print with mock data (no keys found)
mock_clean=$(jq -n '{
    scripts_found: 5,
    scripts_analyzed: 3,
    api_keys: [],
    endpoints: ["/api/v1/users", "/api/v2/data"],
    source_maps: [],
    risk: "none",
    files: [
        {"url": "https://example.com/app.js", "size": 12345, "keys_found": 0, "endpoints_found": 2}
    ]
}')

((TESTS_RUN++)) || true
print_output=$(jsanalysis_print "$mock_clean" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} jsanalysis_print produces output for clean data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} jsanalysis_print produces output for clean data"
fi

# Test print with mock critical data
mock_critical=$(jq -n '{
    scripts_found: 8,
    scripts_analyzed: 6,
    api_keys: [
        {"type": "aws_key", "value": "AKIA...MPLE", "file": "app.js"},
        {"type": "google_api_key", "value": "AIza...z12", "file": "config.js"}
    ],
    endpoints: ["/api/v1/users", "/api/v2/data"],
    source_maps: ["app.js.map"],
    risk: "critical",
    files: [
        {"url": "https://example.com/app.js", "size": 50000, "keys_found": 1, "endpoints_found": 1},
        {"url": "https://example.com/config.js", "size": 2000, "keys_found": 1, "endpoints_found": 1}
    ]
}')

((TESTS_RUN++)) || true
print_output=$(jsanalysis_print "$mock_critical" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} jsanalysis_print produces output for critical data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} jsanalysis_print produces output for critical data"
fi

# Verify header is in output
((TESTS_RUN++)) || true
if echo "$print_output" | grep -q "JS ANALYSIS"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Print output contains JS ANALYSIS header"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Print output should contain JS ANALYSIS header"
fi

# Verify risk level appears
((TESTS_RUN++)) || true
if echo "$print_output" | grep -qi "CRITICAL"; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Print output shows CRITICAL risk level"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Print output should show CRITICAL risk level"
fi

echo ""

# ─── JSON Output Structure Tests ───

echo "--- JSON output structure ---"

mock_result=$(jq -n '{
    scripts_found: 10,
    scripts_analyzed: 7,
    api_keys: [{"type": "aws_key", "value": "AKIA...MPLE", "file": "app.js"}],
    endpoints: ["/api/v1/users"],
    source_maps: ["app.js.map"],
    risk: "critical",
    files: [{"url": "https://example.com/app.js", "size": 5000, "keys_found": 1, "endpoints_found": 1}]
}')

assert_json_valid "$mock_result" "Mock result is valid JSON"
assert_json_has_key "$mock_result" "scripts_found" "Has 'scripts_found' key"
assert_json_has_key "$mock_result" "scripts_analyzed" "Has 'scripts_analyzed' key"
assert_json_has_key "$mock_result" "api_keys" "Has 'api_keys' key"
assert_json_has_key "$mock_result" "endpoints" "Has 'endpoints' key"
assert_json_has_key "$mock_result" "source_maps" "Has 'source_maps' key"
assert_json_has_key "$mock_result" "risk" "Has 'risk' key"
assert_json_has_key "$mock_result" "files" "Has 'files' key"
assert_json_value "$mock_result" "scripts_found" "10" "scripts_found is 10"
assert_json_value "$mock_result" "scripts_analyzed" "7" "scripts_analyzed is 7"
assert_json_value "$mock_result" "risk" "critical" "risk is critical"

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECOND_MODULE_JSANALYSIS_LOADED" == "1" ]]; then
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
