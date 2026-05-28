#!/usr/bin/env bash
#
# dns.sh - DNS enumeration module for recond
#
# Performs DNS lookups for various record types including:
# A, AAAA, MX, TXT, NS, CAA, DMARC, DKIM
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_DNS_LOADED:-}" ]] && return 0
_RECOND_MODULE_DNS_LOADED=1

# Module info
MODULE_DNS_NAME="dns"
MODULE_DNS_DESCRIPTION="DNS enumeration"

# Default DKIM selectors to check
DEFAULT_DKIM_SELECTORS=(google default mail dkim s1 s2 k1 selector1 selector2)

# Run DNS enumeration
# Usage: dns_run "example.com"
# Output: JSON object with DNS results
dns_run() {
    local domain=$1
    local timeout
    timeout=$(get_timeout "dns" 2>/dev/null || echo "5")

    local result_json
    result_json=$(jq -n '{
        a: [],
        aaaa: [],
        ns: [],
        mx: [],
        txt: [],
        caa: [],
        dmarc: null,
        dkim: {}
    }')

    # A Records
    local a_records
    a_records=$(safe_timeout "$timeout" dig +short "$domain" A 2>/dev/null | grep -E '^[0-9.]+$' || true)
    if [[ -n "$a_records" ]]; then
        result_json=$(echo "$result_json" | jq --arg records "$a_records" '.a = ($records | split("\n") | map(select(length > 0)))')
    fi

    # AAAA Records
    local aaaa_records
    aaaa_records=$(safe_timeout "$timeout" dig +short "$domain" AAAA 2>/dev/null | grep -E '^[0-9a-fA-F:]+$' || true)
    if [[ -n "$aaaa_records" ]]; then
        result_json=$(echo "$result_json" | jq --arg records "$aaaa_records" '.aaaa = ($records | split("\n") | map(select(length > 0)))')
    fi

    # NS Records
    local ns_records
    ns_records=$(safe_timeout "$timeout" dig +short "$domain" NS 2>/dev/null || true)
    if [[ -n "$ns_records" ]]; then
        result_json=$(echo "$result_json" | jq --arg records "$ns_records" '.ns = ($records | split("\n") | map(select(length > 0)))')
    fi

    # MX Records
    local mx_records
    mx_records=$(safe_timeout "$timeout" dig +short "$domain" MX 2>/dev/null | sort -n || true)
    if [[ -n "$mx_records" ]]; then
        local mx_json='[]'
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local priority host
            priority=$(echo "$line" | awk '{print $1}')
            host=$(echo "$line" | awk '{print $2}')
            mx_json=$(echo "$mx_json" | jq --arg p "$priority" --arg h "$host" '. += [{priority: ($p | tonumber), host: $h}]')
        done <<< "$mx_records"
        result_json=$(echo "$result_json" | jq --argjson mx "$mx_json" '.mx = $mx')
    fi

    # TXT Records
    local txt_records
    txt_records=$(safe_timeout "$timeout" dig +short "$domain" TXT 2>/dev/null || true)
    if [[ -n "$txt_records" ]]; then
        result_json=$(echo "$result_json" | jq --arg records "$txt_records" '.txt = ($records | split("\n") | map(select(length > 0)))')
    fi

    # CAA Records
    local caa_records
    caa_records=$(safe_timeout "$timeout" dig +short "$domain" CAA 2>/dev/null || true)
    if [[ -n "$caa_records" ]]; then
        result_json=$(echo "$result_json" | jq --arg records "$caa_records" '.caa = ($records | split("\n") | map(select(length > 0)))')
    fi

    # DMARC Record
    local dmarc
    dmarc=$(safe_timeout "$timeout" dig +short "_dmarc.$domain" TXT 2>/dev/null | head -1 || true)
    if [[ -n "$dmarc" ]]; then
        result_json=$(echo "$result_json" | jq --arg dmarc "$dmarc" '.dmarc = $dmarc')
    fi

    # DKIM Records
    local dkim_json='{}'
    for selector in "${DEFAULT_DKIM_SELECTORS[@]}"; do
        local dkim
        dkim=$(safe_timeout "$timeout" dig +short "${selector}._domainkey.$domain" TXT 2>/dev/null | head -1 || true)
        if [[ -n "$dkim" ]]; then
            dkim_json=$(echo "$dkim_json" | jq --arg sel "$selector" --arg val "$dkim" '.[$sel] = $val')
        fi
    done
    result_json=$(echo "$result_json" | jq --argjson dkim "$dkim_json" '.dkim = $dkim')

    echo "$result_json"
}

# Terminal output for DNS results
# Usage: dns_print "$json_result" "example.com"
dns_print() {
    local json=$1
    local domain=$2

    header "DNS RECORDS - $domain"

    # A Records
    subheader "A Records (IPv4)"
    local a_count
    a_count=$(echo "$json" | jq '.a | length')
    if [[ "$a_count" -gt 0 ]]; then
        echo "$json" | jq -r '.a[]' | while read -r ip; do
            success "$ip"
        done
    else
        info "No A records found"
    fi

    # AAAA Records
    subheader "AAAA Records (IPv6)"
    local aaaa_count
    aaaa_count=$(echo "$json" | jq '.aaaa | length')
    if [[ "$aaaa_count" -gt 0 ]]; then
        echo "$json" | jq -r '.aaaa[]' | while read -r ip; do
            success "$ip"
        done
    else
        info "No AAAA records found"
    fi

    # NS Records
    subheader "NS Records (Nameservers)"
    echo "$json" | jq -r '.ns[]' 2>/dev/null | while read -r ns; do
        success "$ns"
    done

    # MX Records
    subheader "MX Records (Mail)"
    local mx_count
    mx_count=$(echo "$json" | jq '.mx | length')
    if [[ "$mx_count" -gt 0 ]]; then
        echo "$json" | jq -r '.mx[] | "\(.priority) \(.host)"' | while read -r line; do
            success "$line"
        done
    fi

    # TXT Records
    subheader "TXT Records"
    echo "$json" | jq -r '.txt[]' 2>/dev/null | while read -r txt; do
        echo "  $txt"
    done

    # CAA Records
    subheader "CAA Records (Certificate Authority Authorization)"
    local caa_count
    caa_count=$(echo "$json" | jq '.caa | length')
    if [[ "$caa_count" -gt 0 ]]; then
        echo "$json" | jq -r '.caa[]' | while read -r record; do
            success "$record"
        done
    else
        info "No CAA records found"
    fi

    # DMARC Record
    subheader "DMARC Record"
    local dmarc
    dmarc=$(echo "$json" | jq -r '.dmarc // empty')
    if [[ -n "$dmarc" ]]; then
        success "$dmarc"
    else
        info "No DMARC record found"
    fi

    # DKIM Records
    subheader "DKIM Records (common selectors)"
    local dkim_found=false
    for selector in "${DEFAULT_DKIM_SELECTORS[@]}"; do
        local dkim
        dkim=$(echo "$json" | jq -r ".dkim.\"$selector\" // empty")
        if [[ -n "$dkim" ]]; then
            success "${selector}._domainkey: found"
            dkim_found=true
        fi
    done
    if ! $dkim_found; then
        info "No DKIM records found for common selectors"
    fi
}

# Check if DNS module can run
# Returns 0 if dependencies are met
dns_check() {
    check_dependencies dig
}
