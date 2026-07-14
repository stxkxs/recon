#!/usr/bin/env bash
#
# virustotal.sh - VirusTotal reputation analysis module for recon
#
# Queries the VirusTotal API v3 for domain/IP reputation data including
# detection stats, categories, and analysis dates.
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_VIRUSTOTAL_LOADED:-}" ]] && return 0
_RECON_MODULE_VIRUSTOTAL_LOADED=1

# Module info
MODULE_VIRUSTOTAL_NAME="virustotal"
MODULE_VIRUSTOTAL_DESCRIPTION="VirusTotal reputation analysis"

# API base URL
_VT_API_BASE="https://www.virustotal.com/api/v3"

# Run VirusTotal reputation lookup
# Usage: virustotal_run "example.com"
# Output: JSON object with reputation results
virustotal_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "virustotal" 2>/dev/null || echo "10")

    # Determine target type (IP vs domain)
    local target_type endpoint
    if [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        target_type="ip"
        endpoint="${_VT_API_BASE}/ip_addresses/${target}"
    else
        target_type="domain"
        endpoint="${_VT_API_BASE}/domains/${target}"
    fi

    # Get API key
    local api_key
    api_key=$(get_api_key "virustotal" 2>/dev/null || echo "")

    if [[ -z "$api_key" ]]; then
        warn "VirusTotal: No API key configured (set RECON_API_VIRUSTOTAL or add to config)"
        jq -n \
            --arg target "$target" \
            --arg target_type "$target_type" \
            '{
                error: "no_api_key",
                reputation: 0,
                detections: {},
                categories: [],
                target: $target,
                target_type: $target_type
            }'
        return 0
    fi

    # Make API request
    local response http_code body
    response=$(safe_timeout "$timeout" curl -s -w "\n%{http_code}" \
        --connect-timeout 5 --max-time "$timeout" \
        -H "x-apikey: ${api_key}" \
        "${endpoint}" 2>/dev/null) || {
        warn "VirusTotal: Request timed out or failed"
        jq -n \
            --arg target "$target" \
            --arg target_type "$target_type" \
            '{
                error: "request_failed",
                reputation: 0,
                detections: {},
                categories: [],
                target: $target,
                target_type: $target_type
            }'
        return 0
    }

    # Split response into body and HTTP status code
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
        warn "VirusTotal: API returned HTTP ${http_code}"
        jq -n \
            --arg target "$target" \
            --arg target_type "$target_type" \
            --arg http_code "$http_code" \
            '{
                error: ("http_" + $http_code),
                reputation: 0,
                detections: {},
                categories: [],
                target: $target,
                target_type: $target_type
            }'
        return 0
    fi

    # Validate response is JSON
    if ! echo "$body" | jq . >/dev/null 2>&1; then
        warn "VirusTotal: Invalid JSON response"
        jq -n \
            --arg target "$target" \
            --arg target_type "$target_type" \
            '{
                error: "invalid_response",
                reputation: 0,
                detections: {},
                categories: [],
                target: $target,
                target_type: $target_type
            }'
        return 0
    fi

    # Extract fields from API response
    local reputation malicious suspicious harmless undetected categories last_analysis_date
    reputation=$(echo "$body" | jq -r '.data.attributes.reputation // 0')
    malicious=$(echo "$body" | jq -r '.data.attributes.last_analysis_stats.malicious // 0')
    suspicious=$(echo "$body" | jq -r '.data.attributes.last_analysis_stats.suspicious // 0')
    harmless=$(echo "$body" | jq -r '.data.attributes.last_analysis_stats.harmless // 0')
    undetected=$(echo "$body" | jq -r '.data.attributes.last_analysis_stats.undetected // 0')
    categories=$(echo "$body" | jq '.data.attributes.categories // {}')
    last_analysis_date=$(echo "$body" | jq -r '
        .data.attributes.last_analysis_date //
        .data.attributes.last_modification_date // 0
        | if type == "number" and . > 0 then (. | todate | split("T")[0]) else "unknown" end
    ')

    # Build output JSON
    jq -n \
        --argjson reputation "$reputation" \
        --argjson malicious "$malicious" \
        --argjson suspicious "$suspicious" \
        --argjson harmless "$harmless" \
        --argjson undetected "$undetected" \
        --argjson categories "$categories" \
        --arg last_analysis_date "$last_analysis_date" \
        --arg target "$target" \
        --arg target_type "$target_type" \
        '{
            reputation: $reputation,
            detections: {
                malicious: $malicious,
                suspicious: $suspicious,
                harmless: $harmless,
                undetected: $undetected
            },
            categories: $categories,
            last_analysis_date: $last_analysis_date,
            target: $target,
            target_type: $target_type
        }'
}

# Terminal output for VirusTotal results
# Usage: virustotal_print "$json_result" "example.com"
virustotal_print() {
    local json=$1
    local target=$2

    header "VIRUSTOTAL REPUTATION - $target"

    # Check for error
    local vt_error
    vt_error=$(echo "$json" | jq -r '.error // empty')
    if [[ -n "$vt_error" ]]; then
        case "$vt_error" in
            no_api_key)
                warn "No VirusTotal API key configured"
                info "Set RECON_API_VIRUSTOTAL environment variable or add to config"
                ;;
            request_failed)
                warn "VirusTotal API request failed"
                ;;
            http_*)
                warn "VirusTotal API returned error: ${vt_error}"
                ;;
            *)
                warn "VirusTotal error: ${vt_error}"
                ;;
        esac
        return 0
    fi

    # Reputation score
    subheader "Reputation Score"
    local reputation
    reputation=$(echo "$json" | jq -r '.reputation')
    if [[ "$reputation" -ge 0 ]]; then
        success "Reputation: ${reputation} (higher is better)"
    else
        error "Reputation: ${reputation} (negative indicates bad reputation)"
    fi

    # Detection stats
    subheader "Detection Stats"
    local malicious suspicious harmless undetected
    malicious=$(echo "$json" | jq -r '.detections.malicious')
    suspicious=$(echo "$json" | jq -r '.detections.suspicious')
    harmless=$(echo "$json" | jq -r '.detections.harmless')
    undetected=$(echo "$json" | jq -r '.detections.undetected')

    if [[ "$malicious" -gt 0 ]]; then
        error "Malicious: ${malicious}"
    else
        success "Malicious: ${malicious}"
    fi

    if [[ "$suspicious" -gt 0 ]]; then
        warn "Suspicious: ${suspicious}"
    else
        success "Suspicious: ${suspicious}"
    fi

    success "Harmless: ${harmless}"
    info "Undetected: ${undetected}"

    # Categories
    subheader "Categories"
    local cat_count
    cat_count=$(echo "$json" | jq '.categories | length')
    if [[ "$cat_count" -gt 0 ]]; then
        echo "$json" | jq -r '.categories | to_entries[] | "\(.key): \(.value)"' | while read -r line; do
            success "$line"
        done
    else
        info "No categories assigned"
    fi

    # Last analysis date
    subheader "Last Analysis"
    local analysis_date
    analysis_date=$(echo "$json" | jq -r '.last_analysis_date')
    if [[ "$analysis_date" != "unknown" ]]; then
        info "Last analyzed: ${analysis_date}"
    else
        info "Analysis date unknown"
    fi
}

# Check if VirusTotal module can run
# Returns 0 if dependencies are met
virustotal_check() {
    check_dependencies curl jq
}
