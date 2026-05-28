#!/usr/bin/env bash
#
# test_emailsec.sh - Unit tests for email security analysis module
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
source "${PROJECT_ROOT}/lib/modules/emailsec.sh"

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
echo "Testing: Email Security Module"
echo "================================================"
echo ""

# ─── Function Existence Tests ───

echo "--- function existence ---"

((TESTS_RUN++)) || true
if declare -f emailsec_run &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} emailsec_run function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} emailsec_run function defined"
fi

((TESTS_RUN++)) || true
if declare -f emailsec_print &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} emailsec_print function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} emailsec_print function defined"
fi

((TESTS_RUN++)) || true
if declare -f emailsec_check &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} emailsec_check function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} emailsec_check function defined"
fi

# Test helper functions exist
for func in emailsec_analyze_spf emailsec_analyze_dmarc emailsec_analyze_dkim emailsec_analyze_bimi emailsec_grade emailsec_count_spf_lookups; do
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
if emailsec_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} emailsec_check passes (dig and jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} emailsec_check passes"
fi

echo ""

# ─── Module Info Tests ───

echo "--- module info ---"

assert_equals "emailsec" "$MODULE_EMAILSEC_NAME" "MODULE_EMAILSEC_NAME is 'emailsec'"
assert_equals "Email security analysis" "$MODULE_EMAILSEC_DESCRIPTION" "MODULE_EMAILSEC_DESCRIPTION is set"

echo ""

# ─── Run Without Scan Data ───

echo "--- emailsec_run without scan data ---"

# Ensure no scan data is set
unset RECOND_SCAN_JSON 2>/dev/null || true

result=$(emailsec_run "example.com" 2>/dev/null)

assert_json_valid "$result" "emailsec_run without scan data returns valid JSON"
assert_json_has_key "$result" "grade" "Result has 'grade' key"
assert_json_has_key "$result" "spf" "Result has 'spf' key"
assert_json_has_key "$result" "dmarc" "Result has 'dmarc' key"
assert_json_has_key "$result" "dkim" "Result has 'dkim' key"
assert_json_has_key "$result" "bimi" "Result has 'bimi' key"
assert_json_has_key "$result" "recommendations" "Result has 'recommendations' key"

# Check SPF sub-structure
assert_json_has_key "$result" "spf.mechanisms" "SPF has mechanisms key"
assert_json_has_key "$result" "spf.dns_lookups" "SPF has dns_lookups key"
assert_json_has_key "$result" "spf.dns_lookup_limit" "SPF has dns_lookup_limit key"
assert_json_has_key "$result" "spf.issues" "SPF has issues key"

# Check DMARC sub-structure
assert_json_has_key "$result" "dmarc.policy" "DMARC has policy key"
assert_json_has_key "$result" "dmarc.strength" "DMARC has strength key"
assert_json_has_key "$result" "dmarc.issues" "DMARC has issues key"

# Check DKIM sub-structure
assert_json_has_key "$result" "dkim.selectors_checked" "DKIM has selectors_checked key"
assert_json_has_key "$result" "dkim.selectors_found" "DKIM has selectors_found key"
assert_json_has_key "$result" "dkim.issues" "DKIM has issues key"

# Check BIMI sub-structure
# bimi.found may be false, so check with type instead of jq -e
((TESTS_RUN++)) || true
bimi_found_type=$(echo "$result" | jq -r '.bimi.found | type')
if [[ "$bimi_found_type" == "boolean" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} BIMI has found key (boolean)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} BIMI has found key (boolean)"
    echo "  Got type: $bimi_found_type"
fi

# SPF dns_lookup_limit should always be 10
assert_json_value "$result" "spf.dns_lookup_limit" "10" "SPF dns_lookup_limit is 10"

# DKIM selectors_checked should be 12 (our selector list length)
assert_json_value "$result" "dkim.selectors_checked" "12" "DKIM checked 12 selectors"

# Recommendations should be an array
((TESTS_RUN++)) || true
rec_type=$(echo "$result" | jq -r '.recommendations | type')
if [[ "$rec_type" == "array" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} recommendations is an array"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} recommendations should be array, got $rec_type"
fi

# Grade should be a single letter A-F
((TESTS_RUN++)) || true
grade=$(echo "$result" | jq -r '.grade')
if [[ "$grade" =~ ^[A-F]$ ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} grade is a valid letter ($grade)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} grade should be A-F, got $grade"
fi

echo ""

# ─── Print Function Tests ───

echo "--- print function ---"

# Test with comprehensive mock data
mock_data=$(jq -n '{
    grade: "B",
    spf: {
        found: true,
        record: "v=spf1 include:_spf.google.com include:sendgrid.net -all",
        mechanisms: ["include:_spf.google.com", "include:sendgrid.net", "-all"],
        dns_lookups: 4,
        dns_lookup_limit: 10,
        all_qualifier: "-all",
        includes: ["_spf.google.com", "sendgrid.net"],
        issues: []
    },
    dmarc: {
        found: true,
        record: "v=DMARC1; p=quarantine; sp=none; pct=100; rua=mailto:dmarc@example.com; ruf=mailto:forensic@example.com; adkim=s; aspf=s",
        policy: "quarantine",
        subdomain_policy: "none",
        pct: 100,
        rua: "mailto:dmarc@example.com",
        ruf: "mailto:forensic@example.com",
        adkim: "s",
        aspf: "s",
        fo: "",
        strength: "moderate",
        issues: []
    },
    dkim: {
        selectors_checked: 12,
        selectors_found: [
            {
                selector: "google",
                record: "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...",
                key_type: "rsa",
                key_bits: 2048,
                weak: false
            },
            {
                selector: "s1",
                record: "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQ...",
                key_type: "rsa",
                key_bits: 1024,
                weak: true
            }
        ],
        issues: ["DKIM selector s1 uses 1024-bit RSA key (should be 2048+)"]
    },
    bimi: {
        found: true,
        record: "v=BIMI1; l=https://example.com/logo.svg; a=https://example.com/vmc.pem",
        logo_url: "https://example.com/logo.svg",
        vmc_url: "https://example.com/vmc.pem"
    },
    recommendations: [
        "Consider upgrading DMARC policy from quarantine to reject",
        "Upgrade DKIM keys to 2048-bit RSA or stronger"
    ]
}')

((TESTS_RUN++)) || true
print_output=$(emailsec_print "$mock_data" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} emailsec_print produces output for valid data"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} emailsec_print produces output for valid data"
fi

# Test print with minimal mock data (grade F, nothing found)
mock_minimal=$(jq -n '{
    grade: "F",
    spf: {
        found: false,
        record: "",
        mechanisms: [],
        dns_lookups: 0,
        dns_lookup_limit: 10,
        all_qualifier: "",
        includes: [],
        issues: ["No SPF record found"]
    },
    dmarc: {
        found: false,
        record: "",
        policy: "",
        subdomain_policy: "",
        pct: 100,
        rua: "",
        ruf: "",
        adkim: "",
        aspf: "",
        fo: "",
        strength: "missing",
        issues: ["No DMARC record found"]
    },
    dkim: {
        selectors_checked: 12,
        selectors_found: [],
        issues: ["No DKIM selectors found for common selectors"]
    },
    bimi: {
        found: false,
        record: "",
        logo_url: "",
        vmc_url: ""
    },
    recommendations: [
        "Add an SPF TXT record to prevent email spoofing",
        "Add a DMARC record for email authentication policy",
        "Configure DKIM email signing for your domain",
        "Consider adding a BIMI record for brand visibility in email clients"
    ]
}')

((TESTS_RUN++)) || true
print_output=$(emailsec_print "$mock_minimal" "example.com" 2>&1 || true)
if [[ -n "$print_output" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} emailsec_print handles empty/missing data without crashing"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} emailsec_print handles empty/missing data without crashing"
fi

echo ""

# ─── Grading Tests ───

echo "--- grading logic ---"

# Grade A: Strong SPF + DMARC reject + DKIM 2048+ + BIMI
spf_a=$(jq -n '{found: true, all_qualifier: "-all"}')
dmarc_a=$(jq -n '{found: true, policy: "reject"}')
dkim_a=$(jq -n '{selectors_found: [{selector: "google", key_bits: 2048, weak: false}]}')
bimi_a=$(jq -n '{found: true}')

grade=$(emailsec_grade "$spf_a" "$dmarc_a" "$dkim_a" "$bimi_a")
assert_equals "A" "$grade" "Grade A: strong SPF + DMARC reject + DKIM 2048 + BIMI"

# Grade B: Good SPF + DMARC quarantine + DKIM found
dmarc_b=$(jq -n '{found: true, policy: "quarantine"}')
bimi_b=$(jq -n '{found: false}')

grade=$(emailsec_grade "$spf_a" "$dmarc_b" "$dkim_a" "$bimi_b")
assert_equals "B" "$grade" "Grade B: SPF + DMARC quarantine + DKIM found"

# Grade B: Good SPF + DMARC reject + DKIM found (no BIMI)
grade=$(emailsec_grade "$spf_a" "$dmarc_a" "$dkim_a" "$bimi_b")
assert_equals "B" "$grade" "Grade B: SPF + DMARC reject + DKIM (weak key, no BIMI)"

# Grade C: SPF present + DMARC present (no DKIM)
dmarc_c=$(jq -n '{found: true, policy: "none"}')
dkim_c=$(jq -n '{selectors_found: []}')

grade=$(emailsec_grade "$spf_a" "$dmarc_c" "$dkim_c" "$bimi_b")
assert_equals "C" "$grade" "Grade C: SPF + DMARC present, no DKIM"

# Grade D: Only SPF
dmarc_d=$(jq -n '{found: false, policy: ""}')

grade=$(emailsec_grade "$spf_a" "$dmarc_d" "$dkim_c" "$bimi_b")
assert_equals "D" "$grade" "Grade D: SPF only, no DMARC"

# Grade D: Only DMARC
spf_d=$(jq -n '{found: false, all_qualifier: ""}')

grade=$(emailsec_grade "$spf_d" "$dmarc_c" "$dkim_c" "$bimi_b")
assert_equals "D" "$grade" "Grade D: DMARC only, no SPF"

# Grade F: Neither SPF nor DMARC
grade=$(emailsec_grade "$spf_d" "$dmarc_d" "$dkim_c" "$bimi_b")
assert_equals "F" "$grade" "Grade F: no SPF, no DMARC"

echo ""

# ─── Run With Mock Scan Data ───

echo "--- emailsec_run with mock scan data ---"

export RECOND_SCAN_JSON
RECOND_SCAN_JSON=$(jq -n '{
    results: {
        dns: {
            data: {
                txt: [
                    "\"v=spf1 include:_spf.google.com ~all\"",
                    "\"google-site-verification=abcdef\""
                ],
                dmarc: "\"v=DMARC1; p=reject; rua=mailto:dmarc@example.com\"",
                dkim: {
                    google: "\"v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQE\""
                }
            }
        }
    }
}')

result=$(emailsec_run "example.com" 2>/dev/null)

assert_json_valid "$result" "emailsec_run with scan data returns valid JSON"
assert_json_has_key "$result" "grade" "Scan result has grade key"
assert_json_has_key "$result" "spf" "Scan result has spf key"
assert_json_has_key "$result" "dmarc" "Scan result has dmarc key"
assert_json_has_key "$result" "dkim" "Scan result has dkim key"
assert_json_has_key "$result" "bimi" "Scan result has bimi key"
assert_json_has_key "$result" "recommendations" "Scan result has recommendations key"

# Verify SPF was found from scan data
assert_json_value "$result" "spf.found" "true" "SPF found from scan data"

# Verify DMARC was found from scan data
assert_json_value "$result" "dmarc.found" "true" "DMARC found from scan data"

unset RECOND_SCAN_JSON

echo ""

# ─── Source Guard Tests ───

echo "--- source guard ---"

((TESTS_RUN++)) || true
if [[ "$_RECOND_MODULE_EMAILSEC_LOADED" == "1" ]]; then
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
