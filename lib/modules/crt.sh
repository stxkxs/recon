#!/usr/bin/env bash
#
# crt.sh - Certificate Transparency log search module for recon
#
# Queries crt.sh to discover subdomains from CT log entries.
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_CRT_LOADED:-}" ]] && return 0
_RECON_MODULE_CRT_LOADED=1

# Module info
MODULE_CRT_NAME="crt"
MODULE_CRT_DESCRIPTION="Certificate Transparency log search"

# Run CT log search
# Usage: crt_run "example.com"
# Output: JSON object with discovered subdomains
crt_run() {
    local domain=$1
    local timeout
    timeout=$(get_timeout "crt" 2>/dev/null || echo "15")

    local query_time
    query_time=$(get_timestamp)

    # Query crt.sh API
    local raw_response
    raw_response=$(safe_timeout "$timeout" curl -s --connect-timeout 5 --max-time "$timeout" "https://crt.sh/?q=%25.${domain}&output=json" 2>/dev/null || true)

    # Handle empty or error response
    if [[ -z "$raw_response" ]] || ! echo "$raw_response" | jq . >/dev/null 2>&1; then
        jq -n \
            --arg query_time "$query_time" \
            '{
                subdomains: [],
                total: 0,
                source: "crt.sh",
                query_time: $query_time
            }'
        return 0
    fi

    # Extract unique subdomains from name_value field
    # - Split multi-line name_value entries (crt.sh sometimes returns \n-separated values)
    # - Strip leading wildcard (*.) prefixes
    # - Lowercase, deduplicate, and sort
    local subdomains_json
    subdomains_json=$(echo "$raw_response" | jq -r \
        '.[].name_value' 2>/dev/null \
        | tr ',' '\n' \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
        | sed 's/^\*\.//' \
        | tr '[:upper:]' '[:lower:]' \
        | grep -E "\.${domain//./\\.}$|^${domain//./\\.}$" \
        | sort -u \
        | jq -R . \
        | jq -s '.')

    # Handle jq pipeline failure
    if [[ -z "$subdomains_json" ]] || [[ "$subdomains_json" == "null" ]]; then
        subdomains_json='[]'
    fi

    local total
    total=$(echo "$subdomains_json" | jq 'length')

    jq -n \
        --argjson subdomains "$subdomains_json" \
        --argjson total "$total" \
        --arg query_time "$query_time" \
        '{
            subdomains: $subdomains,
            total: $total,
            source: "crt.sh",
            query_time: $query_time
        }'
}

# Terminal output for CT log results
# Usage: crt_print "$json_result" "example.com"
crt_print() {
    local json=$1
    local domain=$2

    header "CERTIFICATE TRANSPARENCY - $domain"

    local total
    total=$(echo "$json" | jq '.total')

    if [[ "$total" -gt 0 ]]; then
        subheader "Subdomains from CT Logs ($total found)"
        echo "$json" | jq -r '.subdomains[]' | while read -r subdomain; do
            success "$subdomain"
        done
    else
        warn "No subdomains found in CT logs for $domain"
    fi

    local source
    source=$(echo "$json" | jq -r '.source')
    local query_time
    query_time=$(echo "$json" | jq -r '.query_time')
    info "Source: $source | Query time: $query_time"
}

# Check if CT module can run
# Returns 0 if dependencies are met
crt_check() {
    check_dependencies curl jq
}
