#!/usr/bin/env bash
#
# reverseip.sh - Reverse IP lookup module for recon
#
# Queries the HackerTarget API to find domains hosted on the same IP address.
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_REVERSEIP_LOADED:-}" ]] && return 0
_RECON_MODULE_REVERSEIP_LOADED=1

# Module info
MODULE_REVERSEIP_NAME="reverseip"
MODULE_REVERSEIP_DESCRIPTION="Reverse IP lookup"

# Run reverse IP lookup
# Usage: reverseip_run "example.com" or reverseip_run "93.184.216.34"
# Output: JSON object with domains sharing the same IP
reverseip_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "reverseip" 2>/dev/null || echo "10")

    local query_time
    query_time=$(get_timestamp)

    # If target is not an IP, resolve it
    local ip="$target"
    if ! [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(safe_timeout "$timeout" dig +short "$target" A 2>/dev/null | head -1 || true)
        if [[ -z "$ip" ]] || ! [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            warn "Reverse IP: could not resolve $target to an IP address"
            jq -n --arg t "$target" --arg qt "$query_time" '{
                error: "resolve_failed",
                ip: "",
                resolved_from: $t,
                domains: [],
                total: 0,
                source: "hackertarget.com",
                query_time: $qt
            }'
            return 0
        fi
    fi

    # Query HackerTarget reverse IP lookup API
    local response
    response=$(safe_timeout "$timeout" curl -s --connect-timeout 5 --max-time "$timeout" "https://api.hackertarget.com/reverseiplookup/?q=${ip}" 2>/dev/null || true)

    # Handle empty response
    if [[ -z "$response" ]]; then
        warn "Reverse IP: API request failed or returned empty response"
        jq -n --arg ip "$ip" --arg t "$target" --arg qt "$query_time" '{
            error: "api_error",
            ip: $ip,
            resolved_from: $t,
            domains: [],
            total: 0,
            source: "hackertarget.com",
            query_time: $qt
        }'
        return 0
    fi

    # Check for API error responses
    if echo "$response" | grep -qi "API count exceeded\|error"; then
        local err_msg
        err_msg=$(echo "$response" | head -1)
        warn "Reverse IP: API error - $err_msg"
        jq -n --arg ip "$ip" --arg t "$target" --arg err "$err_msg" --arg qt "$query_time" '{
            error: $err,
            ip: $ip,
            resolved_from: $t,
            domains: [],
            total: 0,
            source: "hackertarget.com",
            query_time: $qt
        }'
        return 0
    fi

    # Response is plain text, one domain per line
    # Filter out empty lines and build domains array
    local domains_json
    domains_json=$(echo "$response" \
        | sed '/^[[:space:]]*$/d' \
        | jq -R . \
        | jq -s '.')

    # Handle pipeline failure
    if [[ -z "$domains_json" ]] || [[ "$domains_json" == "null" ]]; then
        domains_json='[]'
    fi

    local total
    total=$(echo "$domains_json" | jq 'length')

    jq -n \
        --arg ip "$ip" \
        --arg t "$target" \
        --argjson domains "$domains_json" \
        --argjson total "$total" \
        --arg qt "$query_time" \
        '{
            ip: $ip,
            resolved_from: $t,
            domains: $domains,
            total: $total,
            source: "hackertarget.com",
            query_time: $qt
        }'
}

# Terminal output for reverse IP results
# Usage: reverseip_print "$json_result" "example.com"
reverseip_print() {
    local json=$1
    local target=$2

    header "REVERSE IP LOOKUP - $target"

    # Check for error
    local err
    err=$(echo "$json" | jq -r '.error // empty')
    if [[ -n "$err" ]]; then
        warn "Reverse IP lookup not available: $err"
        return 0
    fi

    # Show IP resolved from target
    local ip
    ip=$(echo "$json" | jq -r '.ip // empty')
    local resolved_from
    resolved_from=$(echo "$json" | jq -r '.resolved_from // empty')
    if [[ -n "$ip" ]]; then
        subheader "Host"
        success "IP: $ip"
        if [[ -n "$resolved_from" ]] && [[ "$resolved_from" != "$ip" ]]; then
            info "Resolved from: $resolved_from"
        fi
    fi

    # Show total domains found
    local total
    total=$(echo "$json" | jq '.total')

    if [[ "$total" -gt 0 ]]; then
        subheader "Domains on this IP ($total found)"
        local display_limit=30
        local domains_list
        domains_list=$(echo "$json" | jq -r '.domains[]')
        local count=0
        while read -r domain; do
            ((count++)) || true
            if [[ "$count" -le "$display_limit" ]]; then
                success "$domain"
            elif [[ "$count" -eq $((display_limit + 1)) ]]; then
                info "... and $((total - display_limit)) more domains"
                break
            fi
        done <<< "$domains_list"
    else
        warn "No domains found for $ip"
    fi

    local source
    source=$(echo "$json" | jq -r '.source')
    local query_time
    query_time=$(echo "$json" | jq -r '.query_time')
    info "Source: $source | Query time: $query_time"
}

# Check if reverse IP module can run
# Returns 0 if dependencies are met
reverseip_check() {
    check_dependencies curl jq dig
}
