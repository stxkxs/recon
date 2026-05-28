#!/usr/bin/env bash
#
# ip.sh - IP-specific reconnaissance module for recond
#
# Performs reconnaissance on IP addresses:
# - Reverse DNS lookup
# - WHOIS/ASN information
# - Geolocation hints
# - Port scanning (if enabled)
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_IP_LOADED:-}" ]] && return 0
_RECOND_MODULE_IP_LOADED=1

# Module info
MODULE_IP_NAME="ip"
MODULE_IP_DESCRIPTION="IP-specific reconnaissance"

# Perform reverse DNS lookup
# Usage: ip_reverse_dns "192.0.2.1"
# Returns: JSON object with reverse DNS results
ip_reverse_dns() {
    local ip=$1
    local timeout
    timeout=$(get_timeout "dns" 2>/dev/null || echo "5")

    local result
    result=$(jq -n '{
        ip: "",
        ptr: null,
        hostnames: []
    }' | jq --arg ip "$ip" '.ip = $ip')

    # Perform reverse lookup
    local ptr
    ptr=$(safe_timeout "$timeout" dig +short -x "$ip" 2>/dev/null | head -1 || true)

    if [[ -n "$ptr" ]]; then
        # Remove trailing dot
        ptr=${ptr%.}
        result=$(echo "$result" | jq --arg ptr "$ptr" '.ptr = $ptr')

        # Add to hostnames
        result=$(echo "$result" | jq --arg h "$ptr" '.hostnames += [$h]')
    fi

    echo "$result"
}

# Get ASN information for IP
# Usage: ip_asn_lookup "192.0.2.1"
# Returns: JSON object with ASN data
ip_asn_lookup() {
    local ip=$1
    local timeout
    timeout=$(get_timeout "dns" 2>/dev/null || echo "5")

    local result
    result=$(jq -n '{
        ip: "",
        asn: null,
        asn_name: null,
        prefix: null
    }' | jq --arg ip "$ip" '.ip = $ip')

    # Query Team Cymru DNS (IP to ASN mapping)
    # Reverse the IP octets and query origin.asn.cymru.com
    local reversed_ip
    reversed_ip=$(echo "$ip" | awk -F. '{print $4"."$3"."$2"."$1}')

    local asn_info
    asn_info=$(safe_timeout "$timeout" dig +short "${reversed_ip}.origin.asn.cymru.com" TXT 2>/dev/null | head -1 || true)

    if [[ -n "$asn_info" ]] && [[ "$asn_info" != *"NXDOMAIN"* ]]; then
        # Parse: "ASN | Prefix | Country | Registry | Date"
        # Remove quotes
        asn_info=${asn_info//\"/}

        local asn
        asn=$(echo "$asn_info" | cut -d'|' -f1 | xargs)
        local prefix
        prefix=$(echo "$asn_info" | cut -d'|' -f2 | xargs)

        if [[ -n "$asn" ]]; then
            result=$(echo "$result" | jq --arg asn "$asn" '.asn = $asn')
        fi

        if [[ -n "$prefix" ]]; then
            result=$(echo "$result" | jq --arg prefix "$prefix" '.prefix = $prefix')
        fi

        # Get ASN name
        if [[ -n "$asn" ]]; then
            local asn_name_info
            asn_name_info=$(safe_timeout "$timeout" dig +short "AS${asn}.asn.cymru.com" TXT 2>/dev/null | head -1 || true)
            if [[ -n "$asn_name_info" ]]; then
                # Parse: "ASN | Country | Registry | Date | Name"
                asn_name_info=${asn_name_info//\"/}
                local asn_name
                asn_name=$(echo "$asn_name_info" | cut -d'|' -f5 | xargs)
                if [[ -n "$asn_name" ]]; then
                    result=$(echo "$result" | jq --arg name "$asn_name" '.asn_name = $name')
                fi
            fi
        fi
    fi

    echo "$result"
}

# Run full IP reconnaissance
# Usage: ip_run "192.0.2.1"
# Output: JSON object with all IP recond results
ip_run() {
    local ip=$1
    local timeout
    timeout=$(get_timeout "whois" 2>/dev/null || echo "15")

    local result_json
    result_json=$(jq -n '{
        ip: "",
        type: "ipv4",
        reverse_dns: {},
        asn: {},
        whois: {},
        geolocation: {}
    }' | jq --arg ip "$ip" '.ip = $ip')

    # Determine IP type
    if [[ "$ip" =~ : ]]; then
        result_json=$(echo "$result_json" | jq '.type = "ipv6"')
    fi

    # Reverse DNS
    local rdns
    rdns=$(ip_reverse_dns "$ip")
    result_json=$(echo "$result_json" | jq --argjson rdns "$rdns" '.reverse_dns = $rdns')

    # ASN lookup
    local asn
    asn=$(ip_asn_lookup "$ip")
    result_json=$(echo "$result_json" | jq --argjson asn "$asn" '.asn = $asn')

    # WHOIS lookup
    local whois_data
    whois_data=$(safe_timeout "$timeout" whois "$ip" 2>/dev/null || true)

    if [[ -n "$whois_data" ]]; then
        local whois_json='{}'

        # Extract common fields
        for field in orgname netname org-name descr organization country cidr netrange; do
            local value
            value=$(echo "$whois_data" | grep -i "^${field}:" | head -1 | sed "s/^[^:]*:[[:space:]]*//" | tr -d '\r')
            if [[ -n "$value" ]]; then
                whois_json=$(echo "$whois_json" | jq --arg f "$field" --arg v "$value" '.[$f] = $v')
            fi
        done

        result_json=$(echo "$result_json" | jq --argjson whois "$whois_json" '.whois = $whois')

        # Extract geolocation hints
        local geo_json='{}'
        local country
        country=$(echo "$whois_data" | grep -i "^country:" | head -1 | sed "s/^[^:]*:[[:space:]]*//" | tr -d '\r')
        if [[ -n "$country" ]]; then
            geo_json=$(echo "$geo_json" | jq --arg c "$country" '.country = $c')
        fi

        local city
        city=$(echo "$whois_data" | grep -i "^city:" | head -1 | sed "s/^[^:]*:[[:space:]]*//" | tr -d '\r')
        if [[ -n "$city" ]]; then
            geo_json=$(echo "$geo_json" | jq --arg c "$city" '.city = $c')
        fi

        local state
        state=$(echo "$whois_data" | grep -i "^state\|stateprov:" | head -1 | sed "s/^[^:]*:[[:space:]]*//" | tr -d '\r')
        if [[ -n "$state" ]]; then
            geo_json=$(echo "$geo_json" | jq --arg s "$state" '.state = $s')
        fi

        result_json=$(echo "$result_json" | jq --argjson geo "$geo_json" '.geolocation = $geo')
    fi

    echo "$result_json"
}

# Terminal output for IP results
# Usage: ip_print "$json_result"
ip_print() {
    local json=$1

    local ip
    ip=$(echo "$json" | jq -r '.ip')

    header "IP RECONNAISSANCE - $ip"

    # Reverse DNS
    subheader "Reverse DNS"
    local ptr
    ptr=$(echo "$json" | jq -r '.reverse_dns.ptr // empty')
    if [[ -n "$ptr" ]]; then
        success "PTR: $ptr"
    else
        info "No PTR record found"
    fi

    # ASN Information
    subheader "ASN Information"
    local asn
    asn=$(echo "$json" | jq -r '.asn.asn // empty')
    local asn_name
    asn_name=$(echo "$json" | jq -r '.asn.asn_name // empty')
    local prefix
    prefix=$(echo "$json" | jq -r '.asn.prefix // empty')

    if [[ -n "$asn" ]]; then
        success "ASN: $asn"
        [[ -n "$asn_name" ]] && info "Name: $asn_name"
        [[ -n "$prefix" ]] && info "Prefix: $prefix"
    else
        info "ASN information not available"
    fi

    # WHOIS Information
    subheader "WHOIS Information"
    local whois_empty
    whois_empty=$(echo "$json" | jq '.whois | length == 0')
    if [[ "$whois_empty" == "false" ]]; then
        echo "$json" | jq -r '.whois | to_entries[] | "\(.key): \(.value)"' | while read -r line; do
            info "$line"
        done
    else
        info "WHOIS data not available"
    fi

    # Geolocation
    subheader "Geolocation Hints"
    local geo_empty
    geo_empty=$(echo "$json" | jq '.geolocation | length == 0')
    if [[ "$geo_empty" == "false" ]]; then
        local country
        country=$(echo "$json" | jq -r '.geolocation.country // empty')
        local city
        city=$(echo "$json" | jq -r '.geolocation.city // empty')
        local state
        state=$(echo "$json" | jq -r '.geolocation.state // empty')

        local location=""
        [[ -n "$city" ]] && location="$city"
        [[ -n "$state" ]] && location="${location:+$location, }$state"
        [[ -n "$country" ]] && location="${location:+$location, }$country"

        if [[ -n "$location" ]]; then
            success "Location: $location"
        fi
    else
        info "Geolocation hints not available"
    fi
}

# Check if IP module can run
ip_check() {
    check_dependencies dig whois
}
