#!/usr/bin/env bash
#
# test_input.sh - Unit tests for input normalization
#

set -euo pipefail

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Force colors for test output
export RECOND_COLOR=always

# Source the input module
source "${PROJECT_ROOT}/lib/core/common.sh"
source "${PROJECT_ROOT}/lib/core/input.sh"

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

assert_true() {
    local result=$1
    local message=${2:-""}

    ((TESTS_RUN++)) || true

    if [[ "$result" == "true" ]] || [[ "$result" == "0" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
    fi
}

assert_false() {
    local result=$1
    local message=${2:-""}

    ((TESTS_RUN++)) || true

    if [[ "$result" == "false" ]] || [[ "$result" == "1" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
    fi
}

# Run function and capture exit code
run_returns() {
    local expected_code=$1
    shift
    local message=${!#}
    set -- "${@:1:$#-1}"

    ((TESTS_RUN++)) || true

    local actual_code=0
    "$@" >/dev/null 2>&1 || actual_code=$?

    if [[ "$expected_code" == "$actual_code" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $message"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $message"
        echo "  Expected exit code: $expected_code"
        echo "  Actual exit code:   $actual_code"
    fi
}

echo "================================================"
echo "Testing: lib/core/input.sh"
echo "================================================"
echo ""

# Test normalize_target
echo "--- normalize_target ---"
assert_equals "example.com" "$(normalize_target 'example.com')" "Plain domain"
assert_equals "example.com" "$(normalize_target 'Example.COM')" "Uppercase domain"
assert_equals "example.com" "$(normalize_target 'https://example.com')" "HTTPS URL"
assert_equals "example.com" "$(normalize_target 'http://example.com')" "HTTP URL"
assert_equals "example.com" "$(normalize_target 'https://example.com/')" "URL with trailing slash"
assert_equals "example.com" "$(normalize_target 'https://example.com/path/to/page')" "URL with path"
assert_equals "example.com" "$(normalize_target 'https://example.com:443')" "URL with port"
assert_equals "example.com" "$(normalize_target 'https://example.com:8080/path')" "URL with port and path"
assert_equals "example.com" "$(normalize_target 'https://user:pass@example.com')" "URL with auth"
assert_equals "example.com" "$(normalize_target 'https://example.com?query=1')" "URL with query"
assert_equals "example.com" "$(normalize_target 'https://example.com#fragment')" "URL with fragment"
assert_equals "example.com" "$(normalize_target '  example.com  ')" "Domain with whitespace"
echo ""

# Test detect_input_type
echo "--- detect_input_type ---"
assert_equals "domain" "$(detect_input_type 'example.com')" "Detect domain"
assert_equals "domain" "$(detect_input_type 'sub.example.com')" "Detect subdomain"
assert_equals "domain" "$(detect_input_type 'a.b.c.example.co.uk')" "Detect deep subdomain"
assert_equals "ipv4" "$(detect_input_type '192.168.1.1')" "Detect IPv4"
assert_equals "ipv4" "$(detect_input_type '8.8.8.8')" "Detect IPv4 (Google DNS)"
assert_equals "ipv4" "$(detect_input_type '10.0.0.1')" "Detect IPv4 (private)"
assert_equals "ipv6" "$(detect_input_type '2001:db8::1')" "Detect IPv6"
assert_equals "ipv6" "$(detect_input_type '::1')" "Detect IPv6 (loopback)"
assert_equals "unknown" "$(detect_input_type 'not-valid')" "Detect unknown (no TLD)"
assert_equals "unknown" "$(detect_input_type '256.1.1.1')" "Detect unknown (invalid IP)"
echo ""

# Test validate_domain
echo "--- validate_domain ---"
run_returns 0 validate_domain "example.com" "Valid domain: example.com"
run_returns 0 validate_domain "sub.example.com" "Valid domain: sub.example.com"
run_returns 0 validate_domain "a-b-c.example.com" "Valid domain: a-b-c.example.com"
run_returns 0 validate_domain "example.co.uk" "Valid domain: example.co.uk"
run_returns 1 validate_domain "example" "Invalid domain: no TLD"
run_returns 1 validate_domain "-example.com" "Invalid domain: leading hyphen"
run_returns 1 validate_domain "example-.com" "Invalid domain: trailing hyphen"
run_returns 1 validate_domain "exam ple.com" "Invalid domain: space in name"
echo ""

# Test validate_ipv4
echo "--- validate_ipv4 ---"
run_returns 0 validate_ipv4 "192.168.1.1" "Valid IPv4: 192.168.1.1"
run_returns 0 validate_ipv4 "0.0.0.0" "Valid IPv4: 0.0.0.0"
run_returns 0 validate_ipv4 "255.255.255.255" "Valid IPv4: 255.255.255.255"
run_returns 1 validate_ipv4 "256.1.1.1" "Invalid IPv4: octet > 255"
run_returns 1 validate_ipv4 "192.168.1" "Invalid IPv4: only 3 octets"
run_returns 1 validate_ipv4 "192.168.1.1.1" "Invalid IPv4: 5 octets"
run_returns 1 validate_ipv4 "abc.def.ghi.jkl" "Invalid IPv4: non-numeric"
echo ""

# Test validate_target
echo "--- validate_target ---"
run_returns 0 validate_target "example.com" "Valid target: domain"
run_returns 0 validate_target "192.168.1.1" "Valid target: IPv4"
run_returns 0 validate_target "2001:db8::1" "Valid target: IPv6"
run_returns 1 validate_target "not-valid" "Invalid target: no TLD"
run_returns 1 validate_target "256.1.1.1" "Invalid target: bad IP"
echo ""

# Test is_private_ip
echo "--- is_private_ip ---"
run_returns 0 is_private_ip "10.0.0.1" "Private IP: 10.0.0.1"
run_returns 0 is_private_ip "10.255.255.255" "Private IP: 10.255.255.255"
run_returns 0 is_private_ip "172.16.0.1" "Private IP: 172.16.0.1"
run_returns 0 is_private_ip "172.31.255.255" "Private IP: 172.31.255.255"
run_returns 0 is_private_ip "192.168.0.1" "Private IP: 192.168.0.1"
run_returns 0 is_private_ip "192.168.255.255" "Private IP: 192.168.255.255"
run_returns 0 is_private_ip "127.0.0.1" "Private IP: 127.0.0.1 (loopback)"
run_returns 0 is_private_ip "169.254.1.1" "Private IP: 169.254.1.1 (link-local)"
run_returns 1 is_private_ip "8.8.8.8" "Public IP: 8.8.8.8"
run_returns 1 is_private_ip "1.1.1.1" "Public IP: 1.1.1.1"
run_returns 1 is_private_ip "172.15.0.1" "Public IP: 172.15.0.1 (below private range)"
run_returns 1 is_private_ip "172.32.0.1" "Public IP: 172.32.0.1 (above private range)"
echo ""

# Test get_apex_domain
echo "--- get_apex_domain ---"
assert_equals "example.com" "$(get_apex_domain 'example.com')" "Apex of example.com"
assert_equals "example.com" "$(get_apex_domain 'www.example.com')" "Apex of www.example.com"
assert_equals "example.com" "$(get_apex_domain 'a.b.c.example.com')" "Apex of a.b.c.example.com"
assert_equals "example.co.uk" "$(get_apex_domain 'www.example.co.uk')" "Apex of www.example.co.uk"
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
