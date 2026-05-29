#!/usr/bin/env bash
#
# whois.sh - WHOIS lookup module for recon
#
# Performs WHOIS lookups on discovered IP addresses
# Extracts organization, network, and geographic information
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_WHOIS_LOADED:-}" ]] && return 0
_RECON_MODULE_WHOIS_LOADED=1

# Module info
MODULE_WHOIS_NAME="whois"
MODULE_WHOIS_DESCRIPTION="WHOIS lookups"

# Fields to extract from WHOIS
WHOIS_EXTRACT_FIELDS=(
    orgname
    netname
    org-name
    descr
    organization
    country
    cidr
)

# Default subdomains to check for IPs
DEFAULT_WHOIS_SUBDOMAINS=(www app api)

# Perform WHOIS lookup on a single IP
# Usage: whois_lookup_ip "192.0.2.1"
# Returns: JSON object with WHOIS data
whois_lookup_ip() {
    local ip=$1
    local timeout
    timeout=$(get_timeout "whois" 2>/dev/null || echo "15")

    local result
    result=$(jq -n '{
        ip: "",
        found: false,
        data: {}
    }' | jq --arg ip "$ip" '.ip = $ip')

    # Perform WHOIS lookup
    local whois_data
    whois_data=$(safe_timeout "$timeout" whois "$ip" 2>/dev/null || true)

    if [[ -z "$whois_data" ]]; then
        echo "$result"
        return 0
    fi

    result=$(echo "$result" | jq '.found = true')

    # Extract relevant fields
    local data_json='{}'
    for field in "${WHOIS_EXTRACT_FIELDS[@]}"; do
        local value
        # Case-insensitive grep, get first match
        value=$(echo "$whois_data" | grep -i "^${field}:" | head -1 | sed "s/^[^:]*:[[:space:]]*//" | tr -d '\r')
        if [[ -n "$value" ]]; then
            data_json=$(echo "$data_json" | jq --arg f "$field" --arg v "$value" '.[$f] = $v')
        fi
    done

    result=$(echo "$result" | jq --argjson data "$data_json" '.data = $data')
    echo "$result"
}

# Get unique IPs from domain and subdomains
# Usage: readarray -t ips < <(whois_get_ips "example.com")
whois_get_ips() {
    local domain=$1
    local timeout
    timeout=$(get_timeout "dns" 2>/dev/null || echo "5")

    local ips=()

    # Main domain
    local main_ip
    main_ip=$(safe_timeout "$timeout" dig +short "$domain" A 2>/dev/null | head -1 || true)
    if [[ -n "$main_ip" ]] && [[ "$main_ip" =~ ^[0-9.]+$ ]]; then
        ips+=("$main_ip")
    fi

    # Subdomains
    for sub in "${DEFAULT_WHOIS_SUBDOMAINS[@]}"; do
        local ip
        ip=$(safe_timeout "$timeout" dig +short "${sub}.${domain}" A 2>/dev/null | head -1 || true)
        if [[ -n "$ip" ]] && [[ "$ip" =~ ^[0-9.]+$ ]]; then
            ips+=("$ip")
        fi
    done

    # Return unique IPs
    printf '%s\n' "${ips[@]}" | sort -u
}

# Run WHOIS lookups on all discovered IPs
# Usage: whois_run "example.com"
# Output: JSON object with all WHOIS results
whois_run() {
    local domain=$1
    local rate_delay
    rate_delay=$(config_get "rate_limits.whois_delay" "1" 2>/dev/null || echo "1")

    local result_json
    result_json=$(jq -n '{
        lookups: []
    }')

    # Get unique IPs
    local ips=()
    readarray -t ips < <(whois_get_ips "$domain")

    # Lookup each IP
    local lookups_json='[]'
    local first=true
    for ip in "${ips[@]}"; do
        # Rate limiting (skip delay for first request)
        if $first; then
            first=false
        else
            sleep "$rate_delay"
        fi

        local lookup_result
        lookup_result=$(whois_lookup_ip "$ip")
        lookups_json=$(echo "$lookups_json" | jq --argjson l "$lookup_result" '. += [$l]')
    done

    result_json=$(echo "$result_json" | jq --argjson lookups "$lookups_json" '.lookups = $lookups')
    echo "$result_json"
}

# Run WHOIS lookup for a direct IP target
# Usage: whois_run_ip "192.0.2.1"
whois_run_ip() {
    local ip=$1

    local result_json
    result_json=$(jq -n '{
        lookups: []
    }')

    local lookup_result
    lookup_result=$(whois_lookup_ip "$ip")

    result_json=$(echo "$result_json" | jq --argjson lookup "[$lookup_result]" '.lookups = $lookup')
    echo "$result_json"
}

# Terminal output for WHOIS results
# Usage: whois_print "$json_result"
whois_print() {
    local json=$1

    header "WHOIS & IP INFORMATION"

    local lookup_count
    lookup_count=$(echo "$json" | jq '.lookups | length')

    if [[ "$lookup_count" -eq 0 ]]; then
        info "No IP addresses found to lookup"
        return 0
    fi

    echo "$json" | jq -r '.lookups[] | @base64' | while read -r lookup_b64; do
        local lookup_data
        lookup_data=$(echo "$lookup_b64" | base64 -d)

        local ip
        ip=$(echo "$lookup_data" | jq -r '.ip')
        local found
        found=$(echo "$lookup_data" | jq -r '.found')

        subheader "IP: $ip"

        if [[ "$found" != "true" ]]; then
            info "WHOIS lookup failed"
            continue
        fi

        # Print each found field
        for field in "${WHOIS_EXTRACT_FIELDS[@]}"; do
            local value
            value=$(echo "$lookup_data" | jq -r ".data.\"$field\" // empty")
            if [[ -n "$value" ]]; then
                info "${field}: ${value}"
            fi
        done
    done
}

# Check if WHOIS module can run
whois_check() {
    check_dependencies whois dig
}
