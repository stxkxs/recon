#!/usr/bin/env bash
#
# cors.sh - CORS misconfiguration detection module for recon
#
# Tests for common CORS misconfigurations:
# - Wildcard Access-Control-Allow-Origin
# - Origin reflection (reflects any origin)
# - Null origin allowed
# - Credentials with wildcard
# - Subdomain-based trust
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_CORS_LOADED:-}" ]] && return 0
_RECON_MODULE_CORS_LOADED=1

# Module info
MODULE_CORS_NAME="cors"
MODULE_CORS_DESCRIPTION="CORS misconfiguration detection"

# Test origins to send
CORS_TEST_ORIGINS=(
    "https://evil.com"
    "null"
    "https://attacker.example.com"
)

# Check CORS headers for a single URL with a given origin
# Usage: cors_check_origin "https://example.com" "https://evil.com"
# Returns: JSON object with CORS response
cors_check_origin() {
    local url=$1
    local origin=$2
    local timeout
    timeout=$(get_timeout "http" 2>/dev/null || echo "5")

    local result
    result=$(jq -n '{
        origin_sent: "",
        acao: null,
        acac: null,
        acam: null,
        acah: null
    }' | jq --arg o "$origin" '.origin_sent = $o')

    # Send request with Origin header
    local headers
    headers=$(curl -sI --max-time "$timeout" \
        -H "Origin: $origin" \
        "$url" 2>/dev/null | head -50)

    if [[ -z "$headers" ]]; then
        echo "$result"
        return 0
    fi

    # Extract CORS headers
    local acao
    acao=$(echo "$headers" | grep -i '^access-control-allow-origin:' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
    if [[ -n "$acao" ]]; then
        result=$(echo "$result" | jq --arg v "$acao" '.acao = $v')
    fi

    local acac
    acac=$(echo "$headers" | grep -i '^access-control-allow-credentials:' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
    if [[ -n "$acac" ]]; then
        result=$(echo "$result" | jq --arg v "$acac" '.acac = $v')
    fi

    local acam
    acam=$(echo "$headers" | grep -i '^access-control-allow-methods:' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
    if [[ -n "$acam" ]]; then
        result=$(echo "$result" | jq --arg v "$acam" '.acam = $v')
    fi

    local acah
    acah=$(echo "$headers" | grep -i '^access-control-allow-headers:' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
    if [[ -n "$acah" ]]; then
        result=$(echo "$result" | jq --arg v "$acah" '.acah = $v')
    fi

    echo "$result"
}

# Analyze CORS results for misconfigurations
# Usage: cors_analyze "$results_json"
# Returns: JSON array of findings
cors_analyze() {
    local results=$1
    local findings='[]'

    # Check each test result
    echo "$results" | jq -c '.tests[]' | while read -r test; do
        local origin_sent
        origin_sent=$(echo "$test" | jq -r '.origin_sent')
        local acao
        acao=$(echo "$test" | jq -r '.acao // ""')
        local acac
        acac=$(echo "$test" | jq -r '.acac // ""')

        # Wildcard origin
        if [[ "$acao" == "*" ]]; then
            echo "wildcard"
        fi

        # Origin reflection
        if [[ "$acao" == "$origin_sent" ]] && [[ "$origin_sent" == "https://evil.com" ]]; then
            echo "reflection"
        fi

        # Null origin accepted
        if [[ "$acao" == "null" ]] && [[ "$origin_sent" == "null" ]]; then
            echo "null_origin"
        fi

        # Credentials with wildcard
        if [[ "$acao" == "*" ]] && [[ "${acac,,}" == "true" ]]; then
            echo "credentials_wildcard"
        fi

        # Credentials with reflection
        if [[ "$acao" == "$origin_sent" ]] && [[ "${acac,,}" == "true" ]] && [[ "$origin_sent" == "https://evil.com" ]]; then
            echo "credentials_reflection"
        fi
    done
}

# Run CORS misconfiguration checks
# Usage: cors_run "example.com"
# Output: JSON object with CORS analysis
cors_run() {
    local domain=$1
    local timeout
    timeout=$(get_timeout "http" 2>/dev/null || echo "5")

    local url="https://${domain}"

    local result_json
    result_json=$(jq -n '{
        url: "",
        tests: [],
        findings: [],
        risk: "none"
    }' | jq --arg url "$url" '.url = $url')

    # Build subdomain origin for testing
    local subdomain_origin="https://evil.${domain}"

    local all_origins=("${CORS_TEST_ORIGINS[@]}" "$subdomain_origin")

    local tests_json='[]'
    for origin in "${all_origins[@]}"; do
        local test_result
        test_result=$(cors_check_origin "$url" "$origin")
        tests_json=$(echo "$tests_json" | jq --argjson t "$test_result" '. += [$t]')
    done

    result_json=$(echo "$result_json" | jq --argjson tests "$tests_json" '.tests = $tests')

    # Analyze for misconfigurations
    local findings='[]'
    local risk="none"

    # Check each test
    for i in $(seq 0 $((${#all_origins[@]} - 1))); do
        local acao
        acao=$(echo "$tests_json" | jq -r ".[$i].acao // \"\"")
        local acac
        acac=$(echo "$tests_json" | jq -r ".[$i].acac // \"\"")
        local origin_sent
        origin_sent=$(echo "$tests_json" | jq -r ".[$i].origin_sent")

        if [[ -z "$acao" ]]; then
            continue
        fi

        # Wildcard origin
        if [[ "$acao" == "*" ]]; then
            findings=$(echo "$findings" | jq '. += [{"type": "wildcard", "severity": "low", "detail": "Access-Control-Allow-Origin: * allows any origin"}]')
            [[ "$risk" == "none" ]] && risk="low"
        fi

        # Origin reflection
        if [[ "$acao" == "$origin_sent" ]] && [[ "$origin_sent" == "https://evil.com" || "$origin_sent" == "https://attacker.example.com" ]]; then
            findings=$(echo "$findings" | jq --arg o "$origin_sent" '. += [{"type": "reflection", "severity": "high", "detail": ("Origin reflection: server reflects arbitrary origin " + $o)}]')
            risk="high"
        fi

        # Null origin
        if [[ "$acao" == "null" ]] && [[ "$origin_sent" == "null" ]]; then
            findings=$(echo "$findings" | jq '. += [{"type": "null_origin", "severity": "medium", "detail": "Null origin accepted - sandboxed iframes can access this resource"}]')
            [[ "$risk" != "high" ]] && risk="medium"
        fi

        # Credentials with wildcard
        if [[ "$acao" == "*" ]] && [[ "${acac,,}" == "true" ]]; then
            findings=$(echo "$findings" | jq '. += [{"type": "credentials_wildcard", "severity": "high", "detail": "Wildcard origin with credentials enabled (browser will block but server misconfigured)"}]')
            risk="high"
        fi

        # Credentials with reflection
        if [[ "$acao" == "$origin_sent" ]] && [[ "${acac,,}" == "true" ]] && [[ "$origin_sent" != *"$domain"* ]]; then
            findings=$(echo "$findings" | jq --arg o "$origin_sent" '. += [{"type": "credentials_reflection", "severity": "critical", "detail": ("Credentials enabled with origin reflection for " + $o + " - full account takeover possible")}]')
            risk="critical"
        fi

        # Subdomain trust
        if [[ "$acao" == "$subdomain_origin" ]]; then
            findings=$(echo "$findings" | jq --arg o "$subdomain_origin" '. += [{"type": "subdomain_trust", "severity": "medium", "detail": ("Subdomain origin trusted: " + $o)}]')
            [[ "$risk" != "high" && "$risk" != "critical" ]] && risk="medium"
        fi
    done

    result_json=$(echo "$result_json" | jq \
        --argjson findings "$findings" \
        --arg risk "$risk" \
        '.findings = $findings | .risk = $risk')

    echo "$result_json"
}

# Terminal output for CORS results
# Usage: cors_print "$json_result" "example.com"
cors_print() {
    local json=$1
    local target=${2:-""}

    header "CORS ANALYSIS - ${target}"

    local findings_count
    findings_count=$(echo "$json" | jq '.findings | length')
    local risk
    risk=$(echo "$json" | jq -r '.risk')

    # Risk level display
    local risk_color="$GREEN"
    case "$risk" in
        low)      risk_color="$YELLOW" ;;
        medium)   risk_color="$YELLOW" ;;
        high)     risk_color="$RED" ;;
        critical) risk_color="$RED" ;;
    esac
    echo -e "  ${BOLD}Risk Level:${NC} ${risk_color}${risk^^}${NC}"
    echo ""

    # Show test results
    subheader "CORS Probes"
    echo "$json" | jq -r '.tests[] | "\(.origin_sent)|\(.acao // "none")|\(.acac // "")"' | while IFS='|' read -r origin acao acac; do
        if [[ "$acao" != "none" ]] && [[ -n "$acao" ]]; then
            local cred_info=""
            [[ -n "$acac" ]] && cred_info=" ${YELLOW}(credentials: $acac)${NC}"
            echo -e "  Origin: ${CYAN}$origin${NC}"
            echo -e "    ACAO: ${GREEN}$acao${NC}${cred_info}"
        else
            echo -e "  Origin: ${CYAN}$origin${NC} ${DIM}(no CORS headers)${NC}"
        fi
    done

    # Show findings
    if [[ "$findings_count" -gt 0 ]]; then
        echo ""
        subheader "Findings"
        echo "$json" | jq -r '.findings[] | "\(.severity)|\(.type)|\(.detail)"' | while IFS='|' read -r severity ftype detail; do
            local sev_color="$GREEN"
            case "$severity" in
                low)      sev_color="$YELLOW" ;;
                medium)   sev_color="$YELLOW" ;;
                high)     sev_color="$RED" ;;
                critical) sev_color="$RED" ;;
            esac
            echo -e "  ${sev_color}[$severity]${NC} $detail"
        done
    else
        echo ""
        success "No CORS misconfigurations detected"
    fi
}

# Check if CORS module can run
cors_check() {
    check_dependencies curl
}
