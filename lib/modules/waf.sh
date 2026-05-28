#!/usr/bin/env bash
#
# waf.sh - WAF/CDN detection module for recond
#
# Passive fingerprinting via HTTP response headers to identify
# Web Application Firewalls and CDN providers including:
# Cloudflare, Akamai, AWS CloudFront, Incapsula/Imperva,
# Sucuri, Azure Front Door, F5 BigIP, Fastly, Plesk
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_WAF_LOADED:-}" ]] && return 0
_RECOND_MODULE_WAF_LOADED=1

# Module info
MODULE_WAF_NAME="waf"
MODULE_WAF_DESCRIPTION="WAF/CDN detection"

# WAF/CDN fingerprint definitions
# Each entry maps a header name (lowercase) to a pattern and provider
# Format: "header_name|pattern|provider"
WAF_FINGERPRINTS=(
    "cf-ray|.*|cloudflare"
    "cf-request-id|.*|cloudflare"
    "server|cloudflare|cloudflare"
    "x-cdn|incapsula|incapsula"
    "x-iinfo|.*|incapsula"
    "x-sucuri-id|.*|sucuri"
    "x-sucuri-cache|.*|sucuri"
    "server|akamaihost|akamai"
    "x-akamai-transformed|.*|akamai"
    "x-amz-cf-id|.*|cloudfront"
    "x-amz-cf-pop|.*|cloudfront"
    "x-azure-ref|.*|azure_front_door"
    "server|bigip|f5"
    "x-powered-by-plesk|.*|plesk"
    "x-fw-serve|.*|fastly"
    "x-cdn|.*|generic_cdn"
)

# Fetch headers from a URL
# Usage: _waf_fetch_headers "https://example.com"
# Output: raw headers (lowercase)
_waf_fetch_headers() {
    local url=$1
    local timeout
    timeout=$(get_timeout "waf" 2>/dev/null || echo "10")

    safe_timeout "$timeout" curl -sI -L --max-redirs 3 --max-time "$timeout" "$url" 2>/dev/null | tr -d '\r' || true
}

# Match headers against fingerprints
# Usage: _waf_match_headers "$headers"
# Output: JSON object with "indicators" array and "providers" array
_waf_match_headers() {
    local headers=$1
    local indicators='[]'
    local providers='[]'

    for fingerprint in "${WAF_FINGERPRINTS[@]}"; do
        local fp_header fp_pattern fp_provider
        fp_header=$(echo "$fingerprint" | cut -d'|' -f1)
        fp_pattern=$(echo "$fingerprint" | cut -d'|' -f2)
        fp_provider=$(echo "$fingerprint" | cut -d'|' -f3)

        # Search for matching header (case-insensitive)
        local match
        match=$(echo "$headers" | grep -i "^${fp_header}:" | head -1 || true)

        if [[ -n "$match" ]]; then
            local header_value
            header_value=$(echo "$match" | sed "s/^[^:]*:[[:space:]]*//" | tr -d '\r\n')

            # Check if the value matches the pattern
            if [[ "$fp_pattern" == ".*" ]] || echo "$header_value" | grep -qi "$fp_pattern"; then
                local header_name
                header_name=$(echo "$match" | cut -d: -f1)
                indicators=$(echo "$indicators" | jq \
                    --arg h "$header_name" \
                    --arg v "$header_value" \
                    '. += [{"header": $h, "value": $v}]')
                providers=$(echo "$providers" | jq --arg p "$fp_provider" '. += [$p]')
            fi
        fi
    done

    # Deduplicate indicators by header name
    indicators=$(echo "$indicators" | jq '[group_by(.header)[] | first]')

    jq -n --argjson indicators "$indicators" --argjson providers "$providers" \
        '{"indicators": $indicators, "providers": $providers}'
}

# Determine the primary provider from a JSON providers array
# Usage: _waf_primary_provider "$providers_json"
_waf_primary_provider() {
    local providers_json=$1

    local count
    count=$(echo "$providers_json" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "null"
        return
    fi

    # Filter out generic_cdn if specific providers exist
    local specific
    specific=$(echo "$providers_json" | jq '[.[] | select(. != "generic_cdn")]')
    local specific_count
    specific_count=$(echo "$specific" | jq 'length')

    if [[ "$specific_count" -gt 0 ]]; then
        echo "$specific" | jq -r 'group_by(.) | sort_by(-length) | .[0][0]'
    else
        echo "generic_cdn"
    fi
}

# Determine confidence level
# Usage: _waf_confidence "$indicators_json" "$provider"
_waf_confidence() {
    local indicators=$1
    local provider=$2

    local count
    count=$(echo "$indicators" | jq 'length')

    if [[ "$count" -ge 2 ]]; then
        echo "high"
    elif [[ "$count" -eq 1 ]]; then
        # Check if the single match is only a Server header
        local header_name
        header_name=$(echo "$indicators" | jq -r '.[0].header' | tr '[:upper:]' '[:lower:]')
        if [[ "$header_name" == "server" ]]; then
            echo "low"
        else
            echo "medium"
        fi
    else
        echo "null"
    fi
}

# Run WAF/CDN detection
# Usage: waf_run "example.com"
# Output: JSON object with WAF detection results
waf_run() {
    local target=$1

    # Fetch headers from both HTTPS and HTTP
    local https_headers http_headers all_headers
    https_headers=$(_waf_fetch_headers "https://${target}")
    http_headers=$(_waf_fetch_headers "http://${target}")

    # Combine all headers for analysis
    all_headers=$(printf '%s\n%s' "$https_headers" "$http_headers")

    # Count total unique headers checked
    local headers_checked
    headers_checked=$(echo "$all_headers" | grep -c ':' 2>/dev/null || echo "0")

    # Match against fingerprints
    local match_result
    match_result=$(_waf_match_headers "$all_headers")

    local indicators providers
    indicators=$(echo "$match_result" | jq '.indicators')
    providers=$(echo "$match_result" | jq '.providers')

    local indicator_count
    indicator_count=$(echo "$indicators" | jq 'length')

    if [[ "$indicator_count" -gt 0 ]]; then
        local provider confidence
        provider=$(_waf_primary_provider "$providers")
        confidence=$(_waf_confidence "$indicators" "$provider")

        jq -n \
            --argjson detected true \
            --arg provider "$provider" \
            --arg confidence "$confidence" \
            --argjson indicators "$indicators" \
            --argjson headers_checked "$headers_checked" \
            '{
                detected: $detected,
                provider: $provider,
                confidence: $confidence,
                indicators: $indicators,
                headers_checked: $headers_checked
            }'
    else
        jq -n \
            --argjson headers_checked "$headers_checked" \
            '{
                detected: false,
                provider: null,
                confidence: null,
                indicators: [],
                headers_checked: $headers_checked
            }'
    fi
}

# Terminal output for WAF detection results
# Usage: waf_print "$json_result" "example.com"
waf_print() {
    local json=$1
    local target=$2

    header "WAF/CDN DETECTION - $target"

    local detected
    detected=$(echo "$json" | jq -r '.detected')

    if [[ "$detected" == "true" ]]; then
        local provider confidence
        provider=$(echo "$json" | jq -r '.provider')
        confidence=$(echo "$json" | jq -r '.confidence')

        success "WAF/CDN Detected: ${provider}"
        info "Confidence: ${confidence}"

        subheader "Indicators"
        echo "$json" | jq -r '.indicators[] | "\(.header): \(.value)"' | while IFS= read -r line; do
            success "$line"
        done
    else
        info "No WAF/CDN detected"
    fi

    local headers_checked
    headers_checked=$(echo "$json" | jq -r '.headers_checked')
    info "Headers analyzed: ${headers_checked}"
}

# Check if WAF module can run
# Returns 0 if dependencies are met
waf_check() {
    check_dependencies curl jq
}
