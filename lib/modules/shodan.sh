#!/usr/bin/env bash
#
# shodan.sh - Shodan host intelligence module for recon
#
# Queries the Shodan API for host information including:
# open ports, services, vulnerabilities, ISP, and organization data.
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_SHODAN_LOADED:-}" ]] && return 0
_RECON_MODULE_SHODAN_LOADED=1

# Module info
MODULE_SHODAN_NAME="shodan"
MODULE_SHODAN_DESCRIPTION="Shodan host intelligence"

# Shodan API base URL
SHODAN_API_BASE="https://api.shodan.io"

# Run Shodan host lookup
# Usage: shodan_run "example.com" or shodan_run "93.184.216.34"
# Output: JSON object with Shodan results
shodan_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "shodan" 2>/dev/null || echo "10")

    local api_key
    api_key=$(get_api_key "shodan" 2>/dev/null || echo "")

    # If no API key, return error JSON
    if [[ -z "$api_key" ]]; then
        warn "Shodan: no API key configured (set RECON_API_SHODAN or add to config)"
        jq -n '{
            error: "no_api_key",
            ip: "",
            ports: [],
            services: [],
            vulns: [],
            org: "",
            isp: "",
            country: "",
            hostnames: [],
            last_update: ""
        }'
        return 0
    fi

    # If target is not an IP, resolve it
    local ip="$target"
    if ! [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(dig +short "$target" A 2>/dev/null | head -1 || true)
        if [[ -z "$ip" ]] || ! [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            warn "Shodan: could not resolve $target to an IP address"
            jq -n --arg t "$target" '{
                error: "resolve_failed",
                ip: "",
                ports: [],
                services: [],
                vulns: [],
                org: "",
                isp: "",
                country: "",
                hostnames: [],
                last_update: ""
            }'
            return 0
        fi
    fi

    # Query Shodan host endpoint
    local response
    response=$(safe_timeout "$timeout" curl -s -f "${SHODAN_API_BASE}/shodan/host/${ip}?key=${api_key}" 2>/dev/null || true)

    if [[ -z "$response" ]] || ! echo "$response" | jq . >/dev/null 2>&1; then
        warn "Shodan: API request failed or returned invalid data"
        jq -n --arg ip "$ip" '{
            error: "api_error",
            ip: $ip,
            ports: [],
            services: [],
            vulns: [],
            org: "",
            isp: "",
            country: "",
            hostnames: [],
            last_update: ""
        }'
        return 0
    fi

    # Check for API error response
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        local api_error
        api_error=$(echo "$response" | jq -r '.error')
        warn "Shodan: API error - $api_error"
        jq -n --arg ip "$ip" --arg err "$api_error" '{
            error: $err,
            ip: $ip,
            ports: [],
            services: [],
            vulns: [],
            org: "",
            isp: "",
            country: "",
            hostnames: [],
            last_update: ""
        }'
        return 0
    fi

    # Extract fields from Shodan response
    local result_json
    result_json=$(echo "$response" | jq '{
        ip: (.ip_str // ""),
        ports: (.ports // []),
        services: [(.data // [])[] | {
            port: (.port // 0),
            transport: (.transport // "tcp"),
            product: (.product // ""),
            version: (.version // ""),
            banner: ((.data // "")[:200])
        }],
        vulns: ((.vulns // {}) | keys),
        org: (.org // ""),
        isp: (.isp // ""),
        country: (.country_name // ""),
        hostnames: (.hostnames // []),
        last_update: (.last_update // "")
    }')

    echo "$result_json"
}

# Terminal output for Shodan results
# Usage: shodan_print "$json_result" "example.com"
shodan_print() {
    local json=$1
    local target=$2

    header "SHODAN HOST INTELLIGENCE - $target"

    # Check for error
    local err
    err=$(echo "$json" | jq -r '.error // empty')
    if [[ -n "$err" ]]; then
        warn "Shodan lookup not available: $err"
        return 0
    fi

    # IP
    local ip
    ip=$(echo "$json" | jq -r '.ip // empty')
    if [[ -n "$ip" ]]; then
        subheader "Host"
        success "IP: $ip"
        local org
        org=$(echo "$json" | jq -r '.org // empty')
        [[ -n "$org" ]] && info "Organization: $org"
        local isp
        isp=$(echo "$json" | jq -r '.isp // empty')
        [[ -n "$isp" ]] && info "ISP: $isp"
        local country
        country=$(echo "$json" | jq -r '.country // empty')
        [[ -n "$country" ]] && info "Country: $country"
    fi

    # Hostnames
    local hostname_count
    hostname_count=$(echo "$json" | jq '.hostnames | length')
    if [[ "$hostname_count" -gt 0 ]]; then
        subheader "Hostnames"
        echo "$json" | jq -r '.hostnames[]' | while read -r h; do
            success "$h"
        done
    fi

    # Open Ports
    subheader "Open Ports"
    local port_count
    port_count=$(echo "$json" | jq '.ports | length')
    if [[ "$port_count" -gt 0 ]]; then
        echo "$json" | jq -r '.ports[]' | while read -r port; do
            success "Port $port"
        done
    else
        info "No open ports found"
    fi

    # Services
    local service_count
    service_count=$(echo "$json" | jq '.services | length')
    if [[ "$service_count" -gt 0 ]]; then
        subheader "Services"
        echo "$json" | jq -r '.services[] | "Port \(.port)/\(.transport): \(.product)\(if .version != "" then " " + .version else "" end)"' | while read -r svc; do
            info "$svc"
        done
    fi

    # Vulnerabilities
    local vuln_count
    vuln_count=$(echo "$json" | jq '.vulns | length')
    if [[ "$vuln_count" -gt 0 ]]; then
        subheader "Vulnerabilities ($vuln_count found)"
        echo "$json" | jq -r '.vulns[]' | while read -r vuln; do
            error "$vuln"
        done
    else
        subheader "Vulnerabilities"
        success "No known vulnerabilities detected"
    fi

    # Last update
    local last_update
    last_update=$(echo "$json" | jq -r '.last_update // empty')
    if [[ -n "$last_update" ]]; then
        echo ""
        info "Last updated: $last_update"
    fi
}

# Check if Shodan module can run
# Returns 0 if dependencies are met
shodan_check() {
    check_dependencies curl jq
}
