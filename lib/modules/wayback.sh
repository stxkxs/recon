#!/usr/bin/env bash
#
# wayback.sh - Wayback Machine URL discovery module for recon
#
# Queries the Wayback Machine CDX API to discover historical URLs
# for a domain, groups them by path segment, and identifies
# interesting file extensions.
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_WAYBACK_LOADED:-}" ]] && return 0
_RECON_MODULE_WAYBACK_LOADED=1

# Module info
MODULE_WAYBACK_NAME="wayback"
MODULE_WAYBACK_DESCRIPTION="Wayback Machine URL discovery"

# Wayback CDX API base URL
WAYBACK_CDX_BASE="https://web.archive.org/cdx/search/cdx"

# Interesting extensions to flag
WAYBACK_INTERESTING_EXTENSIONS=(.php .env .bak .sql .conf .config .xml .json .yml .yaml .log .old .backup .zip .tar .gz)

# Run Wayback Machine URL discovery
# Usage: wayback_run "example.com"
# Output: JSON object with discovered URLs, path groups, and interesting extensions
wayback_run() {
    local domain=$1
    local timeout
    timeout=$(get_timeout "wayback" 2>/dev/null || echo "30")

    local query_time
    query_time=$(get_timestamp)

    # Query Wayback Machine CDX API
    local raw_response
    raw_response=$(safe_timeout "$timeout" curl -s --connect-timeout 5 --max-time "$timeout" "${WAYBACK_CDX_BASE}?url=*.${domain}&output=json&fl=original&collapse=urlkey&limit=5000" 2>/dev/null || true)

    # Handle empty response
    if [[ -z "$raw_response" ]]; then
        jq -n \
            --arg query_time "$query_time" \
            '{
                urls: [],
                total: 0,
                path_groups: {},
                interesting_extensions: {},
                source: "web.archive.org",
                query_time: $query_time
            }'
        return 0
    fi

    # Validate JSON
    if ! echo "$raw_response" | jq . >/dev/null 2>&1; then
        jq -n \
            --arg query_time "$query_time" \
            '{
                urls: [],
                total: 0,
                path_groups: {},
                interesting_extensions: {},
                source: "web.archive.org",
                query_time: $query_time
            }'
        return 0
    fi

    # Parse the JSON response: first row is header ["original"], skip it
    # Extract unique URLs
    local urls_json
    urls_json=$(echo "$raw_response" | jq -r '.[1:][] | .[0]' 2>/dev/null | sort -u | jq -R . | jq -s '.')

    if [[ -z "$urls_json" ]] || [[ "$urls_json" == "null" ]]; then
        urls_json='[]'
    fi

    local total
    total=$(echo "$urls_json" | jq 'length')

    # Group by first path segment
    local path_groups_json
    path_groups_json=$(echo "$urls_json" | jq -r '.[]' 2>/dev/null \
        | while read -r url; do
            # Extract path from URL, get first segment
            local path
            path=$(echo "$url" | sed -E 's|https?://[^/]*||' | sed 's|^/||' | cut -d'/' -f1)
            if [[ -n "$path" ]]; then
                echo "/$path"
            fi
        done \
        | sort | uniq -c | sort -rn \
        | awk '{print $2"\t"$1}' \
        | jq -R 'split("\t") | {(.[0]): (.[1] | tonumber)}' \
        | jq -s 'add // {}')

    if [[ -z "$path_groups_json" ]] || [[ "$path_groups_json" == "null" ]]; then
        path_groups_json='{}'
    fi

    # Count interesting extensions
    local interesting_json
    interesting_json=$(echo "$urls_json" | jq -r '.[]' 2>/dev/null \
        | grep -iE '\.(php|env|bak|sql|conf|config|xml|json|yml|yaml|log|old|backup|zip|tar|gz)(\?.*)?$' \
        | sed -E 's/\?.*$//' \
        | grep -ioE '\.[a-z]+$' \
        | tr '[:upper:]' '[:lower:]' \
        | sort | uniq -c | sort -rn \
        | awk '{print $2"\t"$1}' \
        | jq -R 'split("\t") | {(.[0]): (.[1] | tonumber)}' \
        | jq -s 'add // {}' || echo '{}')

    if [[ -z "$interesting_json" ]] || [[ "$interesting_json" == "null" ]]; then
        interesting_json='{}'
    fi

    # Limit URLs array to first 100 for output
    local urls_limited
    urls_limited=$(echo "$urls_json" | jq '.[0:100]')

    jq -n \
        --argjson urls "$urls_limited" \
        --argjson total "$total" \
        --argjson path_groups "$path_groups_json" \
        --argjson interesting_extensions "$interesting_json" \
        --arg query_time "$query_time" \
        '{
            urls: $urls,
            total: $total,
            path_groups: $path_groups,
            interesting_extensions: $interesting_extensions,
            source: "web.archive.org",
            query_time: $query_time
        }'
}

# Terminal output for Wayback Machine results
# Usage: wayback_print "$json_result" "example.com"
wayback_print() {
    local json=$1
    local target=$2

    header "WAYBACK MACHINE - $target"

    local total
    total=$(echo "$json" | jq '.total')

    if [[ "$total" -eq 0 ]]; then
        warn "No URLs found in Wayback Machine for $target"
        return 0
    fi

    subheader "Total URLs Discovered"
    success "$total unique URLs found"

    # Show top 10 path groups
    local path_group_count
    path_group_count=$(echo "$json" | jq '.path_groups | length')
    if [[ "$path_group_count" -gt 0 ]]; then
        subheader "Top Path Groups"
        echo "$json" | jq -r '.path_groups | to_entries | sort_by(-.value) | .[0:10][] | "\(.key) (\(.value) URLs)"' | while read -r line; do
            info "$line"
        done
    fi

    # Show interesting extensions
    local interesting_count
    interesting_count=$(echo "$json" | jq '.interesting_extensions | length')
    if [[ "$interesting_count" -gt 0 ]]; then
        subheader "Interesting Extensions"
        echo "$json" | jq -r '.interesting_extensions | to_entries | sort_by(-.value)[] | "\(.key): \(.value) files"' | while read -r line; do
            warn "$line"
        done
    fi

    # Show first few interesting URLs
    local interesting_urls
    interesting_urls=$(echo "$json" | jq -r '[.urls[] | select(test("\\.(php|env|bak|sql|conf|config|xml|json|yml|yaml|log|old|backup|zip|tar|gz)(\\?.*)?$"; "i"))] | .[0:10][]' 2>/dev/null || true)
    if [[ -n "$interesting_urls" ]]; then
        subheader "Interesting URLs (sample)"
        echo "$interesting_urls" | while read -r url; do
            warn "$url"
        done
    fi

    local source
    source=$(echo "$json" | jq -r '.source')
    local query_time
    query_time=$(echo "$json" | jq -r '.query_time')
    info "Source: $source | Query time: $query_time"
}

# Check if Wayback module can run
# Returns 0 if dependencies are met
wayback_check() {
    check_dependencies curl jq
}
