#!/usr/bin/env bash
#
# test_modules.sh - Unit tests for new modules (ports, cors, score)
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
source "${PROJECT_ROOT}/lib/modules/ports.sh"
source "${PROJECT_ROOT}/lib/modules/cors.sh"
source "${PROJECT_ROOT}/lib/modules/score.sh"
source "${PROJECT_ROOT}/lib/modules/crt.sh"
source "${PROJECT_ROOT}/lib/modules/shodan.sh"
source "${PROJECT_ROOT}/lib/modules/virustotal.sh"
source "${PROJECT_ROOT}/lib/modules/waf.sh"
source "${PROJECT_ROOT}/lib/modules/dnssec.sh"
source "${PROJECT_ROOT}/lib/modules/takeover.sh"
source "${PROJECT_ROOT}/lib/modules/wayback.sh"
source "${PROJECT_ROOT}/lib/modules/securitytrails.sh"
source "${PROJECT_ROOT}/lib/modules/reverseip.sh"
source "${PROJECT_ROOT}/lib/modules/asn.sh"
source "${PROJECT_ROOT}/lib/modules/axfr.sh"
source "${PROJECT_ROOT}/lib/modules/methods.sh"
source "${PROJECT_ROOT}/lib/modules/dirs.sh"
source "${PROJECT_ROOT}/lib/modules/jsanalysis.sh"
source "${PROJECT_ROOT}/lib/modules/favicon.sh"
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
echo "Testing: All Modules (27 total)"
echo "================================================"
echo ""

# ─── Ports Module Tests ───

echo "--- ports module ---"

# Test port_check function exists and is callable
((TESTS_RUN++)) || true
if declare -f port_check &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} port_check function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} port_check function defined"
fi

# Test ports_check (dependency check)
((TESTS_RUN++)) || true
if ports_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} ports_check passes (bash /dev/tcp available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} ports_check passes"
fi

# Test PORT_SERVICES array is populated
((TESTS_RUN++)) || true
if [[ "${PORT_SERVICES[80]}" == "http" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} PORT_SERVICES maps port 80 to http"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} PORT_SERVICES maps port 80 to http"
fi

assert_equals "https" "${PORT_SERVICES[443]}" "PORT_SERVICES maps port 443 to https"
assert_equals "ssh" "${PORT_SERVICES[22]}" "PORT_SERVICES maps port 22 to ssh"
assert_equals "mysql" "${PORT_SERVICES[3306]}" "PORT_SERVICES maps port 3306 to mysql"
assert_equals "redis" "${PORT_SERVICES[6379]}" "PORT_SERVICES maps port 6379 to redis"
assert_equals "postgresql" "${PORT_SERVICES[5432]}" "PORT_SERVICES maps port 5432 to postgresql"

# Test DEFAULT_PORTS array has expected entries
((TESTS_RUN++)) || true
if [[ ${#DEFAULT_PORTS[@]} -ge 10 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} DEFAULT_PORTS has ${#DEFAULT_PORTS[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} DEFAULT_PORTS has enough entries (got ${#DEFAULT_PORTS[@]})"
fi

echo ""

# ─── CORS Module Tests ───

echo "--- cors module ---"

# Test cors_check (dependency check)
((TESTS_RUN++)) || true
if cors_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} cors_check passes (curl available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} cors_check passes"
fi

# Test CORS_TEST_ORIGINS is populated
((TESTS_RUN++)) || true
if [[ ${#CORS_TEST_ORIGINS[@]} -ge 2 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} CORS_TEST_ORIGINS has ${#CORS_TEST_ORIGINS[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} CORS_TEST_ORIGINS has enough entries"
fi

# Test cors_check_origin function exists
((TESTS_RUN++)) || true
if declare -f cors_check_origin &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} cors_check_origin function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} cors_check_origin function defined"
fi

echo ""

# ─── Score Module Tests ───

echo "--- score module ---"

# Test score_check
((TESTS_RUN++)) || true
if score_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} score_check passes (jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} score_check passes"
fi

# Test score_run without scan data returns valid JSON
result=$(score_run "example.com")
assert_json_valid "$result" "score_run without data returns valid JSON"
assert_json_has_key "$result" "grade" "Score result has grade"
assert_json_has_key "$result" "percentage" "Score result has percentage"
assert_json_has_key "$result" "recommendations" "Score result has recommendations"

# Test score_calculate with mock scan data
mock_scan=$(jq -n '{
    results: {
        dns: {
            data: {
                a: ["93.184.216.34"],
                ns: ["ns1.example.com.", "ns2.example.com."],
                txt: ["\"v=spf1 -all\""],
                caa: ["0 issue \"letsencrypt.org\""],
                dmarc: "v=DMARC1; p=reject",
                dkim: {"google": "v=DKIM1; k=rsa"}
            }
        },
        ssl: {
            data: {
                certificates: [{"connected": true, "subject": "CN=example.com"}]
            }
        },
        http: {
            data: {
                urls: [{
                    reachable: true,
                    status_codes: ["301", "200"],
                    security_headers: {
                        "strict-transport-security": "max-age=31536000",
                        "content-security-policy": "default-src self",
                        "x-frame-options": "DENY",
                        "x-content-type-options": "nosniff",
                        "referrer-policy": "strict-origin",
                        "permissions-policy": "camera=()"
                    }
                }]
            }
        },
        files: {
            data: {
                files: [
                    {"path": "/.well-known/security.txt", "status": 200}
                ]
            }
        }
    }
}')

score_result=$(score_calculate "$mock_scan")
assert_json_valid "$score_result" "score_calculate produces valid JSON"

# With all checks passing, should get a high score
score_grade=$(echo "$score_result" | jq -r '.grade')
score_pct=$(echo "$score_result" | jq -r '.percentage')

((TESTS_RUN++)) || true
if [[ "$score_grade" == "A" ]] || [[ "$score_grade" == "B" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Full security mock data gives grade $score_grade ($score_pct%)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Full security mock data should give A or B, got $score_grade ($score_pct%)"
fi

# Test with minimal data (should get low score)
minimal_scan=$(jq -n '{
    results: {
        dns: { data: { a: ["1.2.3.4"], ns: [], txt: [], caa: [], dmarc: null, dkim: {} } },
        ssl: { data: { certificates: [{"connected": false}] } },
        http: { data: { urls: [{"reachable": false, "security_headers": {}}] } },
        files: { data: { files: [] } }
    }
}')

minimal_result=$(score_calculate "$minimal_scan")
minimal_grade=$(echo "$minimal_result" | jq -r '.grade')
minimal_pct=$(echo "$minimal_result" | jq -r '.percentage')

((TESTS_RUN++)) || true
if [[ "$minimal_pct" -lt 30 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Minimal security data gives low score: $minimal_grade ($minimal_pct%)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Minimal security data should give low score, got $minimal_grade ($minimal_pct%)"
fi

# Test recommendations are generated
rec_count=$(echo "$minimal_result" | jq '.recommendations | length')
((TESTS_RUN++)) || true
if [[ "$rec_count" -gt 5 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Low-score result generates $rec_count recommendations"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Low-score result should generate many recommendations, got $rec_count"
fi

echo ""

# ─── CRT Module Tests ───

echo "--- crt module ---"

# Test crt_check
((TESTS_RUN++)) || true
if crt_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} crt_check passes (curl, jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} crt_check passes"
fi

# Test functions exist
for func in crt_run crt_print crt_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

# Test module info
assert_equals "crt" "$MODULE_CRT_NAME" "MODULE_CRT_NAME is correct"
((TESTS_RUN++)) || true
if [[ -n "$MODULE_CRT_DESCRIPTION" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} MODULE_CRT_DESCRIPTION is set"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} MODULE_CRT_DESCRIPTION is set"
fi

echo ""

# ─── Shodan Module Tests ───

echo "--- shodan module ---"

# Test shodan_check
((TESTS_RUN++)) || true
if shodan_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} shodan_check passes (curl, jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} shodan_check passes"
fi

# Test functions exist
for func in shodan_run shodan_print shodan_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

# Test module info
assert_equals "shodan" "$MODULE_SHODAN_NAME" "MODULE_SHODAN_NAME is correct"

# Test no-API-key graceful handling
result=$(shodan_run "example.com" 2>/dev/null)
assert_json_valid "$result" "shodan_run without API key returns valid JSON"
assert_json_has_key "$result" "error" "shodan_run without key has error field"
assert_json_value "$result" "error" "no_api_key" "shodan error is no_api_key"
assert_json_has_key "$result" "ports" "shodan result has ports key"
assert_json_has_key "$result" "vulns" "shodan result has vulns key"

echo ""

# ─── VirusTotal Module Tests ───

echo "--- virustotal module ---"

# Test virustotal_check
((TESTS_RUN++)) || true
if virustotal_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} virustotal_check passes (curl, jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} virustotal_check passes"
fi

# Test functions exist
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

# Test module info
assert_equals "virustotal" "$MODULE_VIRUSTOTAL_NAME" "MODULE_VIRUSTOTAL_NAME is correct"

# Test no-API-key graceful handling
result=$(virustotal_run "example.com" 2>/dev/null)
assert_json_valid "$result" "virustotal_run without API key returns valid JSON"
assert_json_has_key "$result" "error" "virustotal_run without key has error field"
assert_json_value "$result" "error" "no_api_key" "virustotal error is no_api_key"
assert_json_has_key "$result" "reputation" "virustotal result has reputation key"
assert_json_has_key "$result" "detections" "virustotal result has detections key"
assert_json_value "$result" "target_type" "domain" "virustotal detects domain target type"

# Test IP target type detection
result_ip=$(virustotal_run "8.8.8.8" 2>/dev/null)
assert_json_value "$result_ip" "target_type" "ip" "virustotal detects IP target type"

echo ""

# ─── WAF Module Tests ───

echo "--- waf module ---"

# Test waf_check
((TESTS_RUN++)) || true
if waf_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} waf_check passes (curl, jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} waf_check passes"
fi

# Test functions exist
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

# Test module info
assert_equals "waf" "$MODULE_WAF_NAME" "MODULE_WAF_NAME is correct"

# Test WAF_FINGERPRINTS array is populated
((TESTS_RUN++)) || true
if [[ ${#WAF_FINGERPRINTS[@]} -ge 10 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} WAF_FINGERPRINTS has ${#WAF_FINGERPRINTS[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} WAF_FINGERPRINTS should have at least 10 entries (got ${#WAF_FINGERPRINTS[@]})"
fi

# Test _waf_match_headers with Cloudflare headers
cf_headers=$(printf 'Server: cloudflare\r\nCF-RAY: abc123-LAX\r\n')
match_result=$(_waf_match_headers "$cf_headers")
assert_json_valid "$match_result" "_waf_match_headers returns valid JSON"
((TESTS_RUN++)) || true
provider_count=$(echo "$match_result" | jq '[.providers[] | select(. == "cloudflare")] | length')
if [[ "$provider_count" -gt 0 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Cloudflare headers detected correctly"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Cloudflare headers should be detected"
fi

# Test _waf_match_headers with clean headers (no WAF)
clean_headers=$(printf 'Server: nginx\r\nContent-Type: text/html\r\n')
clean_result=$(_waf_match_headers "$clean_headers")
((TESTS_RUN++)) || true
clean_ind_count=$(echo "$clean_result" | jq '.indicators | length')
if [[ "$clean_ind_count" -eq 0 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Clean headers produce no WAF indicators"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Clean headers should produce no WAF indicators (got $clean_ind_count)"
fi

echo ""

# ─── DNSSEC Module Tests ───

echo "--- dnssec module ---"

# Test dnssec_check
((TESTS_RUN++)) || true
if dnssec_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} dnssec_check passes (dig, jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} dnssec_check passes"
fi

# Test functions exist
for func in dnssec_run dnssec_print dnssec_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

# Test module info
assert_equals "dnssec" "$MODULE_DNSSEC_NAME" "MODULE_DNSSEC_NAME is correct"

echo ""

# ─── Takeover Module Tests ───

echo "--- takeover module ---"

# Test takeover_check
((TESTS_RUN++)) || true
if takeover_check 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} takeover_check passes (dig, curl, jq available)"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} takeover_check passes"
fi

# Test functions exist
for func in takeover_run takeover_print takeover_check takeover_match_service; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

# Test module info
assert_equals "takeover" "$MODULE_TAKEOVER_NAME" "MODULE_TAKEOVER_NAME is correct"

# Test TAKEOVER_SERVICES array
((TESTS_RUN++)) || true
if [[ ${#TAKEOVER_SERVICES[@]} -ge 20 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} TAKEOVER_SERVICES has ${#TAKEOVER_SERVICES[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} TAKEOVER_SERVICES should have 20+ entries (got ${#TAKEOVER_SERVICES[@]})"
fi

# Test TAKEOVER_FINGERPRINTS array
((TESTS_RUN++)) || true
if [[ ${#TAKEOVER_FINGERPRINTS[@]} -ge 5 ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} TAKEOVER_FINGERPRINTS has ${#TAKEOVER_FINGERPRINTS[@]} entries"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} TAKEOVER_FINGERPRINTS should have 5+ entries (got ${#TAKEOVER_FINGERPRINTS[@]})"
fi

# Test takeover_match_service with known patterns
((TESTS_RUN++)) || true
svc=$(takeover_match_service "myapp.github.io" 2>/dev/null) || true
if [[ "$svc" == "GitHub Pages" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} takeover_match_service matches github.io → GitHub Pages"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} takeover_match_service should match github.io (got: $svc)"
fi

((TESTS_RUN++)) || true
svc=$(takeover_match_service "myapp.herokuapp.com" 2>/dev/null) || true
if [[ "$svc" == "Heroku" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} takeover_match_service matches herokuapp.com → Heroku"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} takeover_match_service should match herokuapp.com (got: $svc)"
fi

((TESTS_RUN++)) || true
svc=$(takeover_match_service "mybucket.s3.amazonaws.com" 2>/dev/null) || true
if [[ "$svc" == "AWS S3" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} takeover_match_service matches s3.amazonaws.com → AWS S3"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} takeover_match_service should match s3.amazonaws.com (got: $svc)"
fi

# Test takeover_run without scan data returns valid JSON
result=$(takeover_run "example.com" 2>/dev/null)
assert_json_valid "$result" "takeover_run without scan data returns valid JSON"
assert_json_has_key "$result" "vulnerable" "takeover result has vulnerable key"
assert_json_has_key "$result" "checked" "takeover result has checked key"
assert_json_has_key "$result" "findings" "takeover result has findings key"

# Test takeover_run with mock RECOND_SCAN_JSON
mock_scan_json=$(jq -n '{
    results: {
        subdomain: {
            data: {
                found: [
                    {fqdn: "www.example.com", ip: "1.2.3.4", cname: null},
                    {fqdn: "blog.example.com", ip: "5.6.7.8", cname: "example.github.io."}
                ]
            }
        }
    }
}')
export RECOND_SCAN_JSON="$mock_scan_json"
result_with_data=$(takeover_run "example.com" 2>/dev/null)
unset RECOND_SCAN_JSON
assert_json_valid "$result_with_data" "takeover_run with mock scan data returns valid JSON"
assert_json_value "$result_with_data" "total_subdomains" "2" "takeover counts 2 subdomains from mock data"

echo ""

# ─── Wayback Module Tests ───

echo "--- wayback module ---"

for func in wayback_run wayback_print wayback_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

assert_equals "wayback" "$MODULE_WAYBACK_NAME" "MODULE_WAYBACK_NAME is correct"

echo ""

# ─── SecurityTrails Module Tests ───

echo "--- securitytrails module ---"

for func in securitytrails_run securitytrails_print securitytrails_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

assert_equals "securitytrails" "$MODULE_SECURITYTRAILS_NAME" "MODULE_SECURITYTRAILS_NAME is correct"

# Test no-API-key graceful handling
unset RECOND_API_SECURITYTRAILS 2>/dev/null || true
RECOND_CONFIG[api_keys.securitytrails]=""
result=$(securitytrails_run "example.com" 2>/dev/null)
assert_json_valid "$result" "securitytrails_run without API key returns valid JSON"
assert_json_has_key "$result" "error" "securitytrails result has error field"

echo ""

# ─── Reverse IP Module Tests ───

echo "--- reverseip module ---"

for func in reverseip_run reverseip_print reverseip_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

assert_equals "reverseip" "$MODULE_REVERSEIP_NAME" "MODULE_REVERSEIP_NAME is correct"

echo ""

# ─── ASN Module Tests ───

echo "--- asn module ---"

for func in asn_run asn_print asn_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

assert_equals "asn" "$MODULE_ASN_NAME" "MODULE_ASN_NAME is correct"

echo ""

# ─── AXFR Module Tests ───

echo "--- axfr module ---"

for func in axfr_run axfr_print axfr_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

assert_equals "axfr" "$MODULE_AXFR_NAME" "MODULE_AXFR_NAME is correct"

echo ""

# ─── Methods Module Tests ───

echo "--- methods module ---"

for func in methods_run methods_print methods_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

assert_equals "methods" "$MODULE_METHODS_NAME" "MODULE_METHODS_NAME is correct"

echo ""

# ─── Dirs Module Tests ───

echo "--- dirs module ---"

for func in dirs_run dirs_print dirs_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

assert_equals "dirs" "$MODULE_DIRS_NAME" "MODULE_DIRS_NAME is correct"

echo ""

# ─── JS Analysis Module Tests ───

echo "--- jsanalysis module ---"

for func in jsanalysis_run jsanalysis_print jsanalysis_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

assert_equals "jsanalysis" "$MODULE_JSANALYSIS_NAME" "MODULE_JSANALYSIS_NAME is correct"

echo ""

# ─── Favicon Module Tests ───

echo "--- favicon module ---"

for func in favicon_run favicon_print favicon_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

assert_equals "favicon" "$MODULE_FAVICON_NAME" "MODULE_FAVICON_NAME is correct"

echo ""

# ─── Email Security Module Tests ───

echo "--- emailsec module ---"

for func in emailsec_run emailsec_print emailsec_check; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

assert_equals "emailsec" "$MODULE_EMAILSEC_NAME" "MODULE_EMAILSEC_NAME is correct"

echo ""

# ─── Config integration for new modules ───

echo "--- config integration ---"

# Init config to test defaults
_init_config_defaults

# Test new module defaults exist
for mod in crt shodan virustotal waf dnssec takeover wayback securitytrails reverseip asn axfr methods dirs jsanalysis favicon emailsec; do
    ((TESTS_RUN++)) || true
    if [[ -v "RECOND_CONFIG[modules.${mod}.enabled]" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} Config default exists: modules.${mod}.enabled"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} Config default missing: modules.${mod}.enabled"
    fi
done

# Test new timeout defaults
for mod in crt waf dnssec takeover shodan virustotal wayback securitytrails reverseip asn axfr methods dirs jsanalysis favicon emailsec; do
    ((TESTS_RUN++)) || true
    if [[ -v "RECOND_CONFIG[timeouts.${mod}]" ]]; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} Timeout default exists: timeouts.${mod}=${RECOND_CONFIG[timeouts.${mod}]}"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} Timeout default missing: timeouts.${mod}"
    fi
done

# Test virustotal API key config exists
((TESTS_RUN++)) || true
if [[ -v "RECOND_CONFIG[api_keys.virustotal]" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Config default exists: api_keys.virustotal"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Config default missing: api_keys.virustotal"
fi

echo ""

# ─── Report section functions for new modules ───

echo "--- report sections ---"

# Source report module
source "${PROJECT_ROOT}/lib/core/report.sh"

for func in _report_crt_section _report_waf_section _report_dnssec_section _report_shodan_section _report_virustotal_section _report_takeover_section _report_wayback_section _report_securitytrails_section _report_reverseip_section _report_asn_section _report_axfr_section _report_methods_section _report_dirs_section _report_jsanalysis_section _report_favicon_section _report_emailsec_section; do
    ((TESTS_RUN++)) || true
    if declare -f "$func" &>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} $func function defined"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} $func function defined"
    fi
done

# Test report generation with new module data
mock_report_json=$(jq -n '{
    meta: {version: "2.0.0", started_at: "2024-01-01T00:00:00Z", ended_at: "2024-01-01T00:01:00Z"},
    target: "example.com",
    results: {
        dns: {status: "success", data: {a: ["93.184.216.34"], aaaa: [], ns: ["ns1.example.com."], mx: [], txt: [], caa: [], dmarc: null, dkim: {}}},
        crt: {status: "success", data: {subdomains: ["www.example.com", "mail.example.com"], total: 2, source: "crt.sh"}},
        waf: {status: "success", data: {detected: true, provider: "cloudflare", confidence: "high", indicators: [{"header": "CF-RAY", "value": "abc123"}], headers_checked: 12}},
        dnssec: {status: "success", data: {enabled: true, valid: true, dnskey: true, ds: true, rrsig: true, nsec3: false, ad_flag: true, algorithm: "ECDSAP256SHA256", key_count: 2}},
        shodan: {status: "success", data: {error: "no_api_key", ip: "", ports: [], vulns: []}},
        virustotal: {status: "success", data: {error: "no_api_key", reputation: 0, detections: {}}},
        takeover: {status: "success", data: {vulnerable: [], checked: 2, total_subdomains: 2, findings: []}}
    },
    summary: {modules_run: 7, modules_success: 7, modules_failed: 0, total_errors: 0}
}')

tmpfile=$(mktemp /tmp/recon_test_XXXXXX.html)
report_result=$(report_generate "$mock_report_json" "$tmpfile")

((TESTS_RUN++)) || true
if [[ -f "$tmpfile" ]] && [[ -s "$tmpfile" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Report with new modules generated successfully"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Report with new modules should generate"
fi

# Check report contains new module sections
for section in "Certificate Transparency" "WAF/CDN Detection" "DNSSEC Validation" "Shodan Intelligence" "VirusTotal Reputation" "Subdomain Takeover"; do
    ((TESTS_RUN++)) || true
    if grep -q "$section" "$tmpfile" 2>/dev/null; then
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}✓${NC} Report contains '$section' section"
    else
        ((TESTS_FAILED++)) || true
        echo -e "${RED}✗${NC} Report should contain '$section' section"
    fi
done

rm -f "$tmpfile"
echo ""

# ─── UI Module Tests ───

echo "--- ui module ---"

# Source UI module
source "${PROJECT_ROOT}/lib/core/ui.sh"

# Test _HAS_GUM is set
((TESTS_RUN++)) || true
if [[ "$_HAS_GUM" == "true" ]] || [[ "$_HAS_GUM" == "false" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} _HAS_GUM is set to: $_HAS_GUM"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} _HAS_GUM should be true or false"
fi

# Test ui functions exist
for func in ui_banner ui_header ui_subheader ui_log_info ui_log_warn ui_log_error ui_status; do
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

# ─── Report Module Tests ───

echo "--- report module ---"

# Source report module
source "${PROJECT_ROOT}/lib/core/report.sh"

# Test report_generate function exists
((TESTS_RUN++)) || true
if declare -f report_generate &>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} report_generate function defined"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} report_generate function defined"
fi

# Test report generation with mock data
mock_report_json=$(jq -n '{
    meta: {version: "1.0.0", started_at: "2024-01-01T00:00:00Z", ended_at: "2024-01-01T00:01:00Z"},
    target: "example.com",
    results: {
        dns: {status: "success", data: {a: ["93.184.216.34"], aaaa: [], ns: ["ns1.example.com."], mx: [], txt: [], caa: [], dmarc: null, dkim: {}}}
    },
    summary: {modules_run: 1, modules_success: 1, modules_failed: 0, total_errors: 0}
}')

tmpfile=$(mktemp /tmp/recon_test_XXXXXX.html)
report_result=$(report_generate "$mock_report_json" "$tmpfile")

((TESTS_RUN++)) || true
if [[ -f "$tmpfile" ]] && [[ -s "$tmpfile" ]]; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Report file generated and non-empty"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Report file generated"
fi

# Check report contains HTML
((TESTS_RUN++)) || true
if grep -q "<!DOCTYPE html>" "$tmpfile" 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Report contains valid HTML doctype"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Report contains valid HTML doctype"
fi

# Check report contains target
((TESTS_RUN++)) || true
if grep -q "example.com" "$tmpfile" 2>/dev/null; then
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}✓${NC} Report contains target domain"
else
    ((TESTS_FAILED++)) || true
    echo -e "${RED}✗${NC} Report contains target domain"
fi

rm -f "$tmpfile"
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
