#!/usr/bin/env bash
#
# securitytrails.sh - SecurityTrails domain intelligence module for recond
#
# Queries the SecurityTrails API for domain information including:
# subdomains, associated domains, DNS records, and domain metadata.
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_SECURITYTRAILS_LOADED:-}" ]] && return 0
_RECOND_MODULE_SECURITYTRAILS_LOADED=1

# Module info
MODULE_SECURITYTRAILS_NAME="securitytrails"
MODULE_SECURITYTRAILS_DESCRIPTION="SecurityTrails domain intelligence"

# SecurityTrails API base URL
SECURITYTRAILS_API_BASE="https://api.securitytrails.com/v1"

# Run SecurityTrails domain lookup
# Usage: securitytrails_run "example.com"
# Output: JSON object with SecurityTrails results
securitytrails_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "securitytrails" 2>/dev/null || echo "15")

    local api_key
    api_key=$(get_api_key "securitytrails" 2>/dev/null || echo "")

    # If no API key, return error JSON
    if [[ -z "$api_key" ]]; then
        warn "SecurityTrails: no API key configured (set RECOND_API_SECURITYTRAILS or add to config)"
        jq -n --arg t "$target" '{
            error: "no_api_key",
            domain_info: {},
            subdomains: {list: [], total: 0},
            associated_domains: {list: [], total: 0},
            dns_history: {},
            target: $t
        }'
        return 0
    fi

    # Query domain info endpoint
    local domain_response
    domain_response=$(safe_timeout "$timeout" curl -s -f \
        -H "apikey: ${api_key}" \
        "${SECURITYTRAILS_API_BASE}/domain/${target}" 2>/dev/null || true)

    local domain_info='{}'
    if [[ -n "$domain_response" ]] && echo "$domain_response" | jq . >/dev/null 2>&1; then
        # Check for API error response
        if echo "$domain_response" | jq -e '.message' >/dev/null 2>&1; then
            local api_error
            api_error=$(echo "$domain_response" | jq -r '.message')
            warn "SecurityTrails: API error - $api_error"
            jq -n --arg t "$target" --arg err "$api_error" '{
                error: $err,
                domain_info: {},
                subdomains: {list: [], total: 0},
                associated_domains: {list: [], total: 0},
                dns_history: {},
                target: $t
            }'
            return 0
        fi

        domain_info=$(echo "$domain_response" | jq '{
            alexa_rank: (.alexa_rank // null),
            hostname: (.hostname // ""),
            current_dns: (.current_dns // {})
        }')
    else
        warn "SecurityTrails: domain info request failed or returned invalid data"
    fi

    # Query subdomains endpoint
    local subdomains_response
    subdomains_response=$(safe_timeout "$timeout" curl -s -f \
        -H "apikey: ${api_key}" \
        "${SECURITYTRAILS_API_BASE}/domain/${target}/subdomains" 2>/dev/null || true)

    local subdomains_list='[]'
    local subdomains_total=0
    if [[ -n "$subdomains_response" ]] && echo "$subdomains_response" | jq . >/dev/null 2>&1; then
        # Build full subdomain names by appending .{domain}
        subdomains_list=$(echo "$subdomains_response" | jq --arg domain "$target" '
            [(.subdomains // [])[] | . + "." + $domain]
        ')
        subdomains_total=$(echo "$subdomains_response" | jq '.subdomain_count // (.subdomains | length) // 0')
    fi

    # Query associated domains endpoint
    local associated_response
    associated_response=$(safe_timeout "$timeout" curl -s -f \
        -H "apikey: ${api_key}" \
        "${SECURITYTRAILS_API_BASE}/domain/${target}/associated" 2>/dev/null || true)

    local associated_list='[]'
    local associated_total=0
    if [[ -n "$associated_response" ]] && echo "$associated_response" | jq . >/dev/null 2>&1; then
        associated_list=$(echo "$associated_response" | jq '[(.records // [])[] | .hostname // empty]')
        associated_total=$(echo "$associated_response" | jq '.record_count // (.records | length) // 0')
    fi

    # Build final JSON output
    jq -n \
        --argjson domain_info "$domain_info" \
        --argjson subdomains_list "$subdomains_list" \
        --argjson subdomains_total "$subdomains_total" \
        --argjson associated_list "$associated_list" \
        --argjson associated_total "$associated_total" \
        --arg target "$target" \
        '{
            domain_info: $domain_info,
            subdomains: {list: $subdomains_list, total: $subdomains_total},
            associated_domains: {list: $associated_list, total: $associated_total},
            dns_history: {},
            target: $target
        }'
}

# Terminal output for SecurityTrails results
# Usage: securitytrails_print "$json_result" "example.com"
securitytrails_print() {
    local json=$1
    local target=$2

    header "SECURITYTRAILS - $target"

    # Check for error
    local err
    err=$(echo "$json" | jq -r '.error // empty')
    if [[ -n "$err" ]]; then
        warn "SecurityTrails lookup not available: $err"
        return 0
    fi

    # Domain info
    local hostname alexa_rank
    hostname=$(echo "$json" | jq -r '.domain_info.hostname // empty')
    alexa_rank=$(echo "$json" | jq -r '.domain_info.alexa_rank // empty')

    if [[ -n "$hostname" ]] || [[ -n "$alexa_rank" ]]; then
        subheader "Domain Info"
        [[ -n "$hostname" ]] && info "Hostname: $hostname"
        [[ -n "$alexa_rank" ]] && [[ "$alexa_rank" != "null" ]] && info "Alexa Rank: $alexa_rank"
    fi

    # Current DNS
    local dns_keys
    dns_keys=$(echo "$json" | jq -r '.domain_info.current_dns // {} | keys | length')
    if [[ "$dns_keys" -gt 0 ]]; then
        subheader "Current DNS"
        echo "$json" | jq -r '.domain_info.current_dns | to_entries[] | "\(.key): \(.value.values // [] | map(.ip // .value // .) | join(", "))"' 2>/dev/null | while read -r line; do
            info "$line"
        done
    fi

    # Subdomains
    local subdomain_total
    subdomain_total=$(echo "$json" | jq '.subdomains.total')
    subheader "Subdomains ($subdomain_total found)"
    if [[ "$subdomain_total" -gt 0 ]]; then
        echo "$json" | jq -r '.subdomains.list[:20][]' | while read -r sub; do
            success "$sub"
        done
        if [[ "$subdomain_total" -gt 20 ]]; then
            info "... and $((subdomain_total - 20)) more"
        fi
    else
        info "No subdomains found"
    fi

    # Associated domains
    local associated_total
    associated_total=$(echo "$json" | jq '.associated_domains.total')
    if [[ "$associated_total" -gt 0 ]]; then
        subheader "Associated Domains ($associated_total found)"
        echo "$json" | jq -r '.associated_domains.list[]' | while read -r assoc; do
            success "$assoc"
        done
    fi
}

# Check if SecurityTrails module can run
# Returns 0 if dependencies are met
securitytrails_check() {
    check_dependencies curl jq
}
