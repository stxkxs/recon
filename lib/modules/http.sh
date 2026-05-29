#!/usr/bin/env bash
#
# http.sh - HTTP header analysis module for recon
#
# Analyzes HTTP response headers including:
# - Server identification
# - Security headers (HSTS, CSP, X-Frame-Options, etc.)
# - Infrastructure hints (CDN, proxy headers)
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_HTTP_LOADED:-}" ]] && return 0
_RECON_MODULE_HTTP_LOADED=1

# Module info
MODULE_HTTP_NAME="http"
MODULE_HTTP_DESCRIPTION="HTTP header analysis"

# Security headers to check
SECURITY_HEADERS=(
    "strict-transport-security"
    "x-frame-options"
    "x-content-type-options"
    "x-xss-protection"
    "content-security-policy"
    "referrer-policy"
    "permissions-policy"
    "cross-origin-opener-policy"
)

# Infrastructure hint header patterns
INFRA_HEADER_PATTERNS='x-|cf-|via:|x-cache|x-served-by|x-amz|x-vercel|x-envoy|trace-id|ratelimit'

# Default subdomains to check
DEFAULT_HTTP_SUBDOMAINS=(www app api)

# Analyze HTTP headers for a single URL
# Usage: http_analyze_url "https://example.com"
# Returns: JSON object with header analysis
http_analyze_url() {
    local url=$1
    local timeout
    timeout=$(get_timeout "http" 2>/dev/null || echo "10")

    local result
    result=$(jq -n '{
        url: "",
        reachable: false,
        status_codes: [],
        server: null,
        security_headers: {},
        infrastructure_hints: {}
    }' | jq --arg url "$url" '.url = $url')

    # Fetch headers
    local headers
    headers=$(curl -sI -L --max-time "$timeout" --max-redirs 3 "$url" 2>/dev/null | head -100)

    if [[ -z "$headers" ]]; then
        echo "$result"
        return 0
    fi

    result=$(echo "$result" | jq '.reachable = true')

    # Extract status codes from redirect chain
    local status_codes
    status_codes=$(echo "$headers" | grep -iE '^HTTP/' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    if [[ -n "$status_codes" ]]; then
        result=$(echo "$result" | jq --arg codes "$status_codes" '.status_codes = ($codes | split(",") | map(select(length > 0)))')
    fi

    # Extract server
    local server
    server=$(echo "$headers" | grep -i '^server:' | tail -1 | sed 's/^[Ss]erver:[[:space:]]*//' | tr -d '\r')
    if [[ -n "$server" ]]; then
        result=$(echo "$result" | jq --arg v "$server" '.server = $v')
    fi

    # Check security headers
    local sec_headers_json='{}'
    for header in "${SECURITY_HEADERS[@]}"; do
        local value
        value=$(echo "$headers" | grep -i "^${header}:" | head -1 | sed "s/^[^:]*:[[:space:]]*//" | tr -d '\r')
        if [[ -n "$value" ]]; then
            sec_headers_json=$(echo "$sec_headers_json" | jq --arg h "$header" --arg v "$value" '.[$h] = $v')
        fi
    done
    result=$(echo "$result" | jq --argjson sh "$sec_headers_json" '.security_headers = $sh')

    # Extract infrastructure hints
    local infra_json='{}'
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local header_name
        header_name=$(echo "$line" | cut -d: -f1 | tr '[:upper:]' '[:lower:]' | tr -d '\r')
        local header_value
        header_value=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr -d '\r')
        if [[ -n "$header_name" ]] && [[ -n "$header_value" ]]; then
            infra_json=$(echo "$infra_json" | jq --arg h "$header_name" --arg v "$header_value" '.[$h] = $v')
        fi
    done < <(echo "$headers" | grep -iE "^($INFRA_HEADER_PATTERNS)" || true)
    result=$(echo "$result" | jq --argjson ih "$infra_json" '.infrastructure_hints = $ih')

    echo "$result"
}

# Run HTTP analysis on domain and subdomains
# Usage: http_run "example.com"
# Output: JSON object with all HTTP results
http_run() {
    local domain=$1
    local dns_timeout
    dns_timeout=$(get_timeout "dns" 2>/dev/null || echo "5")

    local result_json
    result_json=$(jq -n '{
        urls: []
    }')

    # Build list of URLs to check
    local urls=("https://${domain}")

    # Add subdomains that resolve
    for sub in "${DEFAULT_HTTP_SUBDOMAINS[@]}"; do
        local ip
        ip=$(safe_timeout "$dns_timeout" dig +short "${sub}.${domain}" A 2>/dev/null | head -1 || true)
        if [[ -n "$ip" ]] && [[ "$ip" =~ ^[0-9.]+$ ]]; then
            urls+=("https://${sub}.${domain}")
        fi
    done

    # Analyze each URL
    local urls_json='[]'
    for url in "${urls[@]}"; do
        local url_result
        url_result=$(http_analyze_url "$url")
        urls_json=$(echo "$urls_json" | jq --argjson u "$url_result" '. += [$u]')
    done

    result_json=$(echo "$result_json" | jq --argjson urls "$urls_json" '.urls = $urls')
    echo "$result_json"
}

# Terminal output for HTTP results
# Usage: http_print "$json_result"
http_print() {
    local json=$1

    header "HTTP HEADER ANALYSIS"

    echo "$json" | jq -r '.urls[] | @base64' | while read -r url_b64; do
        local url_data
        url_data=$(echo "$url_b64" | base64 -d)

        local url
        url=$(echo "$url_data" | jq -r '.url')
        local reachable
        reachable=$(echo "$url_data" | jq -r '.reachable')

        subheader "$url"

        if [[ "$reachable" != "true" ]]; then
            info "Could not fetch headers"
            continue
        fi

        # Status codes
        local status_codes
        status_codes=$(echo "$url_data" | jq -r '.status_codes | join(" → ")' 2>/dev/null || echo "")
        if [[ -n "$status_codes" ]] && [[ "$status_codes" != "null" ]]; then
            success "HTTP $status_codes"
        fi

        # Server
        local server
        server=$(echo "$url_data" | jq -r '.server // empty')
        if [[ -n "$server" ]]; then
            info "Server: $server"
        fi

        # Security headers
        echo -e "\n  ${CYAN}Security Headers:${NC}"
        local has_security_headers=false
        for header in "${SECURITY_HEADERS[@]}"; do
            local value
            value=$(echo "$url_data" | jq -r ".security_headers.\"$header\" // empty")
            if [[ -n "$value" ]]; then
                echo -e "    ${GREEN}✓${NC} ${header}: ${value:0:60}${value:60:+...}"
                has_security_headers=true
            fi
        done
        if ! $has_security_headers; then
            echo "    (none found)"
        fi

        # Infrastructure hints
        local infra_count
        infra_count=$(echo "$url_data" | jq '.infrastructure_hints | length')
        if [[ "$infra_count" -gt 0 ]]; then
            echo -e "\n  ${CYAN}Infrastructure Hints:${NC}"
            echo "$url_data" | jq -r '.infrastructure_hints | to_entries[] | "    \(.key): \(.value)"' | head -10
        fi
    done
}

# Check if HTTP module can run
http_check() {
    check_dependencies curl dig
}
