#!/usr/bin/env bash
#
# test_integration.sh - Integration tests for recond
#
# These tests require network access and test against real domains
#

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Define colors for test output (not sourcing common.sh to keep tests standalone)
TEST_RED='\033[0;31m'
TEST_GREEN='\033[0;32m'
TEST_YELLOW='\033[1;33m'
TEST_NC='\033[0m'

# Test helper functions
assert_success() {
    local message=$1
    shift

    ((TESTS_RUN++)) || true

    if "$@" >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} $message"
        return 0
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} $message"
        return 1
    fi
}

assert_output_contains() {
    local message=$1
    local pattern=$2
    shift 2

    ((TESTS_RUN++)) || true

    local output
    output=$("$@" 2>&1) || true

    if echo "$output" | grep -q "$pattern"; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} $message"
        return 0
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} $message"
        echo "  Pattern '$pattern' not found in output"
        return 1
    fi
}

assert_json_output() {
    local message=$1
    shift

    ((TESTS_RUN++)) || true

    local output
    output=$("$@" 2>&1) || true

    if echo "$output" | jq . >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} $message"
        return 0
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} $message"
        echo "  Output is not valid JSON"
        return 1
    fi
}

skip_test() {
    local message=$1
    local reason=$2

    ((TESTS_RUN++)) || true
    ((TESTS_SKIPPED++)) || true
    echo -e "${TEST_YELLOW}○${TEST_NC} $message (skipped: $reason)"
}

# Check network connectivity
check_network() {
    if ! ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
        echo -e "${TEST_YELLOW}Warning: No network connectivity, some tests will be skipped${TEST_NC}"
        return 1
    fi
    return 0
}

RECOND="${PROJECT_ROOT}/bin/recond"

echo "================================================"
echo "Integration Tests for recond"
echo "================================================"
echo ""

# Check if recond is executable
if [[ ! -x "$RECOND" ]]; then
    echo -e "${TEST_RED}Error: $RECOND is not executable${TEST_NC}"
    exit 1
fi

# Check dependencies
echo "--- Checking dependencies ---"
assert_success "dig is available" command -v dig
assert_success "curl is available" command -v curl
assert_success "openssl is available" command -v openssl
assert_success "whois is available" command -v whois
assert_success "jq is available" command -v jq
echo ""

# Test help and version
echo "--- Help and version ---"
assert_success "recond --help works" "$RECOND" --help
assert_success "recond --version works" "$RECOND" --version
assert_output_contains "Version shows correct format" "recond version" "$RECOND" --version
echo ""

# Test list modules
echo "--- Module listing ---"
assert_success "recond --list-modules works" "$RECOND" --list-modules
assert_output_contains "Lists dns module" "dns" "$RECOND" --list-modules
assert_output_contains "Lists ssl module" "ssl" "$RECOND" --list-modules
assert_output_contains "Lists http module" "http" "$RECOND" --list-modules
assert_output_contains "Lists ports module" "ports" "$RECOND" --list-modules
assert_output_contains "Lists cors module" "cors" "$RECOND" --list-modules
assert_output_contains "Lists score module" "score" "$RECOND" --list-modules
assert_output_contains "Lists crt module" "crt" "$RECOND" --list-modules
assert_output_contains "Lists shodan module" "shodan" "$RECOND" --list-modules
assert_output_contains "Lists virustotal module" "virustotal" "$RECOND" --list-modules
assert_output_contains "Lists waf module" "waf" "$RECOND" --list-modules
assert_output_contains "Lists dnssec module" "dnssec" "$RECOND" --list-modules
assert_output_contains "Lists takeover module" "takeover" "$RECOND" --list-modules

# Count total modules in list
((TESTS_RUN++)) || true
module_count=$("$RECOND" --list-modules 2>&1 | grep -c '^  [a-z]') || true
if [[ "$module_count" -eq 27 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${TEST_GREEN}✓${TEST_NC} Module list shows all 27 modules"
else
    ((TESTS_FAILED++)) || true
    echo -e "${TEST_RED}✗${TEST_NC} Module list should show 27 modules (got $module_count)"
fi
echo ""

# Test input validation
echo "--- Input validation ---"
assert_output_contains "Rejects missing target" "No target specified" "$RECOND" 2>&1 || true
assert_output_contains "Rejects invalid domain" "Invalid target" "$RECOND" "not-a-valid-input" 2>&1 || true
echo ""

# Network-dependent tests
if check_network; then
    echo ""
    echo "--- DNS module (network) ---"
    assert_success "DNS module runs" "$RECOND" -m dns -q example.com
    assert_json_output "DNS JSON output is valid" "$RECOND" --json -m dns example.com

    # Check JSON structure
    json=$("$RECOND" --json -m dns example.com 2>/dev/null)
    ((TESTS_RUN++)) || true
    if echo "$json" | jq -e '.results.dns.data.a' >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} DNS JSON has A records"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} DNS JSON has A records"
    fi
    echo ""

    echo "--- HTTP module (network) ---"
    assert_success "HTTP module runs" "$RECOND" -m http -q example.com
    assert_json_output "HTTP JSON output is valid" "$RECOND" --json -m http example.com
    echo ""

    echo "--- Files module (network) ---"
    assert_success "Files module runs" "$RECOND" -m files -q example.com
    assert_json_output "Files JSON output is valid" "$RECOND" --json -m files example.com
    echo ""

    echo "--- Tech module (network) ---"
    assert_success "Tech module runs" "$RECOND" -m tech -q example.com
    assert_json_output "Tech JSON output is valid" "$RECOND" --json -m tech example.com
    echo ""

    echo "--- Multiple modules (network) ---"
    assert_success "Multiple modules run" "$RECOND" -m dns,http -q example.com
    json=$("$RECOND" --json -m dns,http example.com 2>/dev/null)
    ((TESTS_RUN++)) || true
    dns_present=$(echo "$json" | jq -e '.results.dns' >/dev/null 2>&1 && echo "1" || echo "0")
    http_present=$(echo "$json" | jq -e '.results.http' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$dns_present" == "1" ]] && [[ "$http_present" == "1" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} Both DNS and HTTP results present"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} Both DNS and HTTP results present"
    fi
    echo ""

    echo "--- Ports module (network) ---"
    assert_success "Ports module runs" "$RECOND" -m ports -q example.com
    assert_json_output "Ports JSON output is valid" "$RECOND" --json -m ports example.com
    echo ""

    echo "--- CORS module (network) ---"
    assert_success "CORS module runs" "$RECOND" -m cors -q example.com
    assert_json_output "CORS JSON output is valid" "$RECOND" --json -m cors example.com
    echo ""

    echo "--- Score flag (network) ---"
    assert_json_output "Score JSON output is valid" "$RECOND" --json -s -m dns,http,ssl,files example.com
    echo ""

    echo "--- Report generation (network) ---"
    tmphtml=$(mktemp /tmp/recon_test_XXXXXX.html)
    assert_success "Report generates" "$RECOND" -q --report "$tmphtml" -m dns example.com
    ((TESTS_RUN++)) || true
    if [[ -f "$tmphtml" ]] && grep -q "<!DOCTYPE html>" "$tmphtml" 2>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} Generated HTML report is valid"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} Generated HTML report is valid"
    fi
    rm -f "$tmphtml"
    echo ""

    echo "--- IP module (network) ---"
    assert_success "IP module runs on IP" "$RECOND" -m ip -q 8.8.8.8
    assert_json_output "IP JSON output is valid" "$RECOND" --json 8.8.8.8
    echo ""

    echo "--- CRT module (network) ---"
    assert_success "CRT module runs" "$RECOND" -m crt -q example.com
    assert_json_output "CRT JSON output is valid" "$RECOND" --json -m crt example.com
    json=$("$RECOND" --json -m crt example.com 2>/dev/null)
    ((TESTS_RUN++)) || true
    if echo "$json" | jq -e '.results.crt.data.subdomains' >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} CRT JSON has subdomains array"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} CRT JSON has subdomains array"
    fi
    echo ""

    echo "--- WAF module (network) ---"
    assert_success "WAF module runs" "$RECOND" -m waf -q example.com
    assert_json_output "WAF JSON output is valid" "$RECOND" --json -m waf example.com
    json=$("$RECOND" --json -m waf example.com 2>/dev/null)
    ((TESTS_RUN++)) || true
    if echo "$json" | jq -e '.results.waf.data.detected' >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} WAF JSON has detected field"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} WAF JSON has detected field"
    fi
    echo ""

    echo "--- DNSSEC module (network) ---"
    assert_success "DNSSEC module runs" "$RECOND" -m dnssec -q example.com
    assert_json_output "DNSSEC JSON output is valid" "$RECOND" --json -m dnssec example.com
    json=$("$RECOND" --json -m dnssec example.com 2>/dev/null)
    ((TESTS_RUN++)) || true
    if echo "$json" | jq -e '.results.dnssec.data.enabled' >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} DNSSEC JSON has enabled field"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} DNSSEC JSON has enabled field"
    fi
    echo ""

    echo "--- Shodan module without API key (network) ---"
    assert_json_output "Shodan JSON graceful without key" "$RECOND" --json -m shodan example.com
    json=$("$RECOND" --json -m shodan example.com 2>/dev/null)
    ((TESTS_RUN++)) || true
    shodan_error=$(echo "$json" | jq -r '.results.shodan.data.error // empty' 2>/dev/null)
    if [[ "$shodan_error" == "no_api_key" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} Shodan gracefully reports no_api_key"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} Shodan should report no_api_key error"
    fi
    echo ""

    echo "--- VirusTotal module without API key (network) ---"
    assert_json_output "VirusTotal JSON graceful without key" "$RECOND" --json -m virustotal example.com
    json=$("$RECOND" --json -m virustotal example.com 2>/dev/null)
    ((TESTS_RUN++)) || true
    vt_error=$(echo "$json" | jq -r '.results.virustotal.data.error // empty' 2>/dev/null)
    if [[ "$vt_error" == "no_api_key" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} VirusTotal gracefully reports no_api_key"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} VirusTotal should report no_api_key error"
    fi
    echo ""

    echo "--- New modules in combined scan (network) ---"
    json=$("$RECOND" --json -m dns,crt,waf,dnssec example.com 2>/dev/null)
    for mod in dns crt waf dnssec; do
        ((TESTS_RUN++)) || true
        if echo "$json" | jq -e ".results.${mod}" >/dev/null 2>&1; then
            ((TESTS_PASSED++)) || true
            echo -e "${TEST_GREEN}✓${TEST_NC} Combined scan has ${mod} results"
        else
            ((TESTS_FAILED++)) || true
            echo -e "${TEST_RED}✗${TEST_NC} Combined scan should have ${mod} results"
        fi
    done
    echo ""

    echo "--- Report with new modules (network) ---"
    tmphtml2=$(mktemp /tmp/recon_test_XXXXXX.html)
    "$RECOND" -q --report "$tmphtml2" -m dns,crt,waf,dnssec example.com >/dev/null 2>&1 || true
    for section in "Certificate Transparency" "WAF/CDN Detection" "DNSSEC Validation"; do
        ((TESTS_RUN++)) || true
        if grep -q "$section" "$tmphtml2" 2>/dev/null; then
            ((TESTS_PASSED++)) || true
            echo -e "${TEST_GREEN}✓${TEST_NC} HTML report contains ${section}"
        else
            ((TESTS_FAILED++)) || true
            echo -e "${TEST_RED}✗${TEST_NC} HTML report should contain ${section}"
        fi
    done
    rm -f "$tmphtml2"
    echo ""

    echo "--- Full scan (network) ---"
    assert_success "Full scan runs" "$RECOND" -q example.com

    # Test JSON completeness
    json=$("$RECOND" --json example.com 2>/dev/null)
    ((TESTS_RUN++)) || true
    summary_present=$(echo "$json" | jq -e '.summary' >/dev/null 2>&1 && echo "1" || echo "0")
    meta_present=$(echo "$json" | jq -e '.meta' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$summary_present" == "1" ]] && [[ "$meta_present" == "1" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} Full JSON has meta and summary"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} Full JSON has meta and summary"
    fi
    echo ""

    echo "--- Output to file (network) ---"
    tmpfile=$(mktemp)
    assert_success "Output to file works" "$RECOND" --json -m dns example.com -o "$tmpfile"
    ((TESTS_RUN++)) || true
    if [[ -f "$tmpfile" ]] && jq . "$tmpfile" >/dev/null 2>&1; then
        ((TESTS_PASSED++)) || true
        echo -e "${TEST_GREEN}✓${TEST_NC} Output file contains valid JSON"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${TEST_RED}✗${TEST_NC} Output file contains valid JSON"
    fi
    rm -f "$tmpfile"
    echo ""

else
    skip_test "DNS module" "no network"
    skip_test "HTTP module" "no network"
    skip_test "Files module" "no network"
    skip_test "Tech module" "no network"
    skip_test "Multiple modules" "no network"
    skip_test "Ports module" "no network"
    skip_test "CORS module" "no network"
    skip_test "Score flag" "no network"
    skip_test "Report generation" "no network"
    skip_test "IP module" "no network"
    skip_test "CRT module" "no network"
    skip_test "WAF module" "no network"
    skip_test "DNSSEC module" "no network"
    skip_test "Shodan module" "no network"
    skip_test "VirusTotal module" "no network"
    skip_test "Combined new modules" "no network"
    skip_test "Report with new modules" "no network"
    skip_test "Full scan" "no network"
    skip_test "Output to file" "no network"
fi

# Summary
echo ""
echo "================================================"
echo "Test Summary"
echo "================================================"
echo -e "Total:   $TESTS_RUN"
echo -e "Passed:  ${TEST_GREEN}$TESTS_PASSED${TEST_NC}"
echo -e "Failed:  ${TEST_RED}$TESTS_FAILED${TEST_NC}"
echo -e "Skipped: ${TEST_YELLOW}$TESTS_SKIPPED${TEST_NC}"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
