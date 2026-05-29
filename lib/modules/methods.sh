#!/usr/bin/env bash
#
# methods.sh - HTTP methods enumeration module for recon
#
# Probes target paths for allowed HTTP methods including dangerous ones
# (TRACE, PUT, DELETE, PATCH) and checks for XST vulnerability via TRACE.
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_METHODS_LOADED:-}" ]] && return 0
_RECON_MODULE_METHODS_LOADED=1

# Module info
MODULE_METHODS_NAME="methods"
MODULE_METHODS_DESCRIPTION="HTTP methods enumeration"

# Paths to test
METHODS_TEST_PATHS=("/" "/api/" "/api/v1/" "/admin/")

# Dangerous methods to probe
METHODS_DANGEROUS=("TRACE" "PUT" "DELETE" "PATCH")

# Status codes that indicate a method is NOT allowed
METHODS_BLOCKED_CODES=("405" "501" "000")

# Check if a status code indicates the method is allowed
# Usage: _methods_is_allowed "200"
_methods_is_allowed() {
    local code=$1
    for blocked in "${METHODS_BLOCKED_CODES[@]}"; do
        if [[ "$code" == "$blocked" ]]; then
            return 1
        fi
    done
    return 0
}

# Run HTTP methods enumeration
# Usage: methods_run "example.com"
# Output: JSON object with methods enumeration results
methods_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "methods" 2>/dev/null || echo "10")

    local findings='[]'
    local total_dangerous=0
    local xst_vulnerable=false
    local paths_tested=0

    for path in "${METHODS_TEST_PATHS[@]}"; do
        ((paths_tested++)) || true

        # Send OPTIONS request to get Allow header
        local options_status options_allow
        options_status=$(safe_timeout "$timeout" curl -s -o /dev/null -w "%{http_code}" \
            -X OPTIONS --max-redirs 0 \
            "https://${target}${path}" 2>/dev/null || echo "000")

        options_allow=$(safe_timeout "$timeout" curl -s -I -X OPTIONS --max-redirs 0 \
            "https://${target}${path}" 2>/dev/null \
            | grep -i "^allow:" \
            | sed 's/[Aa]llow: //; s/\r//' \
            | head -1 || true)

        # Probe each dangerous method
        local dangerous_found='[]'

        for method in "${METHODS_DANGEROUS[@]}"; do
            local status
            status=$(safe_timeout "$timeout" curl -s -o /dev/null -w "%{http_code}" \
                -X "$method" --max-redirs 0 --connect-timeout 5 \
                "https://${target}${path}" 2>/dev/null || echo "000")

            if _methods_is_allowed "$status"; then
                dangerous_found=$(echo "$dangerous_found" | jq --arg m "$method" '. += [$m]')
                ((total_dangerous++)) || true

                # Check for XST vulnerability with TRACE
                if [[ "$method" == "TRACE" ]]; then
                    local trace_body
                    trace_body=$(safe_timeout "$timeout" curl -s -X TRACE --max-redirs 0 --connect-timeout 5 \
                        "https://${target}${path}" 2>/dev/null || true)
                    if echo "$trace_body" | grep -qi "TRACE"; then
                        xst_vulnerable=true
                    fi
                fi
            fi

            sleep 0.2
        done

        # Build finding for this path
        findings=$(echo "$findings" | jq \
            --arg path "$path" \
            --arg options_allow "$options_allow" \
            --argjson dangerous_methods "$dangerous_found" \
            '. += [{
                path: $path,
                options_allow: $options_allow,
                dangerous_methods: $dangerous_methods
            }]')
    done

    # Determine risk level
    local risk="none"
    if [[ "$xst_vulnerable" == "true" ]]; then
        risk="critical"
    elif echo "$findings" | jq -e '[.[].dangerous_methods[] | select(. == "PUT" or . == "DELETE")] | length > 0' >/dev/null 2>&1; then
        risk="high"
    elif [[ "$total_dangerous" -gt 0 ]]; then
        risk="medium"
    fi

    jq -n \
        --argjson paths_tested "$paths_tested" \
        --argjson findings "$findings" \
        --arg risk "$risk" \
        --argjson total_dangerous "$total_dangerous" \
        --argjson xst_vulnerable "$xst_vulnerable" \
        '{
            paths_tested: $paths_tested,
            findings: $findings,
            risk: $risk,
            total_dangerous: $total_dangerous,
            xst_vulnerable: $xst_vulnerable
        }'
}

# Terminal output for HTTP methods results
# Usage: methods_print "$json_result" "example.com"
methods_print() {
    local json=$1
    local target=$2

    header "HTTP METHODS - $target"

    # Show risk level with color
    local risk
    risk=$(echo "$json" | jq -r '.risk')
    subheader "Risk Assessment"
    case "$risk" in
        critical)
            error "Risk Level: CRITICAL (XST vulnerability detected)"
            ;;
        high)
            error "Risk Level: HIGH (PUT or DELETE methods allowed)"
            ;;
        medium)
            warn "Risk Level: MEDIUM (unusual methods allowed)"
            ;;
        none)
            success "Risk Level: NONE (no dangerous methods detected)"
            ;;
    esac

    local total_dangerous
    total_dangerous=$(echo "$json" | jq -r '.total_dangerous')
    info "Total dangerous methods found: $total_dangerous"

    # Show findings per path
    local paths_tested
    paths_tested=$(echo "$json" | jq -r '.paths_tested')
    subheader "Paths Tested ($paths_tested)"

    echo "$json" | jq -c '.findings[]' | while IFS= read -r finding; do
        local path options_allow dangerous_count
        path=$(echo "$finding" | jq -r '.path')
        options_allow=$(echo "$finding" | jq -r '.options_allow')
        dangerous_count=$(echo "$finding" | jq '.dangerous_methods | length')

        info "Path: $path"
        if [[ -n "$options_allow" ]] && [[ "$options_allow" != "null" ]] && [[ "$options_allow" != "" ]]; then
            success "  Allow header: $options_allow"
        else
            info "  Allow header: (not returned)"
        fi

        if [[ "$dangerous_count" -gt 0 ]]; then
            echo "$finding" | jq -r '.dangerous_methods[]' | while read -r method; do
                error "  Dangerous method allowed: $method"
            done
        else
            success "  No dangerous methods detected"
        fi
    done

    # XST warning
    local xst_vulnerable
    xst_vulnerable=$(echo "$json" | jq -r '.xst_vulnerable')
    if [[ "$xst_vulnerable" == "true" ]]; then
        echo ""
        error "WARNING: Cross-Site Tracing (XST) vulnerability detected!"
        error "TRACE method is enabled and echoes request content back."
        error "This can be exploited to steal credentials via XSS + TRACE."
    fi
}

# Check if methods module can run
# Returns 0 if dependencies are met
methods_check() {
    check_dependencies curl jq
}
