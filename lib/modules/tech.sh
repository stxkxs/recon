#!/usr/bin/env bash
#
# tech.sh - Technology detection module for recond
#
# Detects technologies from HTML content and HTTP headers:
# - Frontend frameworks (React, Vue, Angular, etc.)
# - Analytics/monitoring services
# - CDN and infrastructure
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_TECH_LOADED:-}" ]] && return 0
_RECOND_MODULE_TECH_LOADED=1

# Module info
MODULE_TECH_NAME="tech"
MODULE_TECH_DESCRIPTION="Technology detection"

# Frontend frameworks to detect
FRONTEND_FRAMEWORKS=(
    react angular vue svelte ember backbone
    jquery nextjs nuxt gatsby remix
)

# Analytics and monitoring services
ANALYTICS_SERVICES=(
    sentry datadog segment mixpanel amplitude
    intercom fullstory hotjar heap rollbar
    bugsnag newrelic
)

# CDN and infrastructure detection (from headers)
INFRA_SIGNATURES=(
    "cloudflare:Cloudflare"
    "cloudfront:AWS CloudFront"
    "akamai:Akamai"
    "fastly:Fastly"
    "vercel:Vercel"
    "netlify:Netlify"
    "envoy:Envoy Proxy"
    "nginx:Nginx"
    "apache:Apache"
)

# Detect technologies from HTML content
# Usage: tech_detect_from_html "$html_content"
# Returns: JSON array of detected technologies
tech_detect_from_html() {
    local html=$1
    local html_lower
    html_lower=$(echo "$html" | tr '[:upper:]' '[:lower:]')

    local detected='[]'

    # Frontend frameworks
    for tech in "${FRONTEND_FRAMEWORKS[@]}"; do
        if echo "$html_lower" | grep -qi "$tech" 2>/dev/null; then
            detected=$(echo "$detected" | jq --arg t "$tech" '. += [$t]')
        fi
    done

    # Analytics services
    for tech in "${ANALYTICS_SERVICES[@]}"; do
        if echo "$html_lower" | grep -qi "$tech" 2>/dev/null; then
            detected=$(echo "$detected" | jq --arg t "$tech" '. += [$t]')
        fi
    done

    echo "$detected"
}

# Detect infrastructure from headers
# Usage: tech_detect_from_headers "$headers"
# Returns: JSON array of detected infrastructure
tech_detect_from_headers() {
    local headers=$1
    local headers_lower
    headers_lower=$(echo "$headers" | tr '[:upper:]' '[:lower:]')

    local detected='[]'

    for sig in "${INFRA_SIGNATURES[@]}"; do
        local pattern
        pattern=$(echo "$sig" | cut -d: -f1)
        local name
        name=$(echo "$sig" | cut -d: -f2)

        if echo "$headers_lower" | grep -qi "$pattern" 2>/dev/null; then
            detected=$(echo "$detected" | jq --arg t "$name" '. += [$t]')
        fi
    done

    echo "$detected"
}

# Run technology detection
# Usage: tech_run "example.com"
# Output: JSON object with detected technologies
tech_run() {
    local domain=$1
    local timeout
    timeout=$(get_timeout "http" 2>/dev/null || echo "10")

    local result_json
    result_json=$(jq -n '{
        frontend: [],
        analytics: [],
        infrastructure: []
    }')

    # Fetch main page and app subdomain
    local html=""
    local app_html=""

    html=$(curl -sL --max-time "$timeout" "https://${domain}" 2>/dev/null | head -500 || true)
    app_html=$(curl -sL --max-time "$timeout" "https://app.${domain}" 2>/dev/null | head -500 || true)

    local combined_html="${html} ${app_html}"

    # Detect frontend frameworks
    local frontend='[]'
    for tech in "${FRONTEND_FRAMEWORKS[@]}"; do
        if echo "$combined_html" | grep -qi "$tech" 2>/dev/null; then
            frontend=$(echo "$frontend" | jq --arg t "$tech" '. += [$t]')
        fi
    done
    result_json=$(echo "$result_json" | jq --argjson f "$frontend" '.frontend = ($f | unique)')

    # Detect analytics
    local analytics='[]'
    for tech in "${ANALYTICS_SERVICES[@]}"; do
        if echo "$combined_html" | grep -qi "$tech" 2>/dev/null; then
            analytics=$(echo "$analytics" | jq --arg t "$tech" '. += [$t]')
        fi
    done
    result_json=$(echo "$result_json" | jq --argjson a "$analytics" '.analytics = ($a | unique)')

    # Fetch headers and detect infrastructure
    local headers
    headers=$(curl -sI --max-time 5 "https://${domain}" 2>/dev/null || true)

    local infra='[]'
    for sig in "${INFRA_SIGNATURES[@]}"; do
        local pattern
        pattern=$(echo "$sig" | cut -d: -f1)
        local name
        name=$(echo "$sig" | cut -d: -f2)

        if echo "$headers" | grep -qi "$pattern" 2>/dev/null; then
            infra=$(echo "$infra" | jq --arg t "$name" '. += [$t]')
        fi
    done
    result_json=$(echo "$result_json" | jq --argjson i "$infra" '.infrastructure = ($i | unique)')

    echo "$result_json"
}

# Terminal output for technology results
# Usage: tech_print "$json_result"
tech_print() {
    local json=$1

    header "TECHNOLOGY DETECTION"

    # Frontend frameworks
    subheader "Frontend Frameworks"
    local frontend_count
    frontend_count=$(echo "$json" | jq '.frontend | length')
    if [[ "$frontend_count" -gt 0 ]]; then
        echo "$json" | jq -r '.frontend[]' | while read -r tech; do
            success "$tech detected"
        done
    else
        info "No frontend frameworks detected"
    fi

    # Analytics
    subheader "Analytics & Monitoring"
    local analytics_count
    analytics_count=$(echo "$json" | jq '.analytics | length')
    if [[ "$analytics_count" -gt 0 ]]; then
        echo "$json" | jq -r '.analytics[]' | while read -r tech; do
            success "$tech detected"
        done
    else
        info "No analytics services detected"
    fi

    # Infrastructure
    subheader "CDN & Infrastructure"
    local infra_count
    infra_count=$(echo "$json" | jq '.infrastructure | length')
    if [[ "$infra_count" -gt 0 ]]; then
        echo "$json" | jq -r '.infrastructure[]' | while read -r tech; do
            success "$tech"
        done
    else
        info "No infrastructure detected"
    fi
}

# Check if tech module can run
tech_check() {
    check_dependencies curl
}
