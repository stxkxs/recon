#!/usr/bin/env bash
#
# files.sh - Common files check module for recond
#
# Checks for common files and endpoints:
# - /.well-known/security.txt
# - /robots.txt
# - /sitemap.xml
# - OpenID configuration
# - App link files
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_FILES_LOADED:-}" ]] && return 0
_RECOND_MODULE_FILES_LOADED=1

# Module info
MODULE_FILES_NAME="files"
MODULE_FILES_DESCRIPTION="Common files check"

# Default files to check
DEFAULT_FILE_PATHS=(
    "/.well-known/security.txt"
    "/robots.txt"
    "/sitemap.xml"
    "/.well-known/openid-configuration"
    "/.well-known/assetlinks.json"
    "/.well-known/apple-app-site-association"
)

# Check a single file/endpoint
# Usage: files_check_path "example.com" "/robots.txt"
# Returns: JSON object with file status and preview
files_check_path() {
    local domain=$1
    local path=$2
    local timeout
    timeout=$(get_timeout "http" 2>/dev/null || echo "5")

    local url="https://${domain}${path}"

    local result
    result=$(jq -n '{
        path: "",
        url: "",
        status: null,
        content_type: null,
        preview: null
    }' | jq --arg path "$path" --arg url "$url" '.path = $path | .url = $url')

    # Check status
    local headers
    headers=$(curl -sI --max-time "$timeout" "$url" 2>/dev/null | head -20)

    if [[ -z "$headers" ]]; then
        echo "$result"
        return 0
    fi

    # Extract status code
    local status
    status=$(echo "$headers" | head -1 | awk '{print $2}')
    if [[ -n "$status" ]]; then
        result=$(echo "$result" | jq --arg s "$status" '.status = ($s | tonumber? // $s)')
    fi

    # Extract content type
    local content_type
    content_type=$(echo "$headers" | grep -i '^content-type:' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | cut -d';' -f1 | tr -d '\r')
    if [[ -n "$content_type" ]]; then
        result=$(echo "$result" | jq --arg ct "$content_type" '.content_type = $ct')
    fi

    # Get preview for successful requests to text files
    if [[ "$status" == "200" ]]; then
        local is_text=false
        case "$path" in
            *.txt|*.xml|*robots*|*security*)
                is_text=true
                ;;
        esac

        if $is_text || [[ "$content_type" == *text* ]] || [[ "$content_type" == *json* ]] || [[ "$content_type" == *xml* ]]; then
            local preview
            preview=$(curl -s --max-time "$timeout" "$url" 2>/dev/null | head -15)
            if [[ -n "$preview" ]]; then
                result=$(echo "$result" | jq --arg p "$preview" '.preview = $p')
            fi
        fi
    fi

    echo "$result"
}

# Run files check on domain
# Usage: files_run "example.com"
# Output: JSON object with all file check results
files_run() {
    local domain=$1

    local result_json
    result_json=$(jq -n '{
        files: []
    }')

    local files_json='[]'
    for path in "${DEFAULT_FILE_PATHS[@]}"; do
        local file_result
        file_result=$(files_check_path "$domain" "$path")
        files_json=$(echo "$files_json" | jq --argjson f "$file_result" '. += [$f]')
    done

    result_json=$(echo "$result_json" | jq --argjson files "$files_json" '.files = $files')
    echo "$result_json"
}

# Terminal output for files results
# Usage: files_print "$json_result"
files_print() {
    local json=$1

    header "COMMON FILES & ENDPOINTS"

    echo "$json" | jq -r '.files[] | @base64' | while read -r file_b64; do
        local file_data
        file_data=$(echo "$file_b64" | base64 -d)

        local path
        path=$(echo "$file_data" | jq -r '.path')
        local status
        status=$(echo "$file_data" | jq -r '.status // "N/A"')
        local preview
        preview=$(echo "$file_data" | jq -r '.preview // empty')

        if [[ "$status" == "200" ]]; then
            success "$path (200 OK)"

            # Show preview for text files
            if [[ -n "$preview" ]]; then
                echo "$preview" | head -10 | sed 's/^/    /'
            fi
        elif [[ "$status" != "null" ]] && [[ "$status" != "N/A" ]]; then
            info "$path ($status)"
        fi
    done
}

# Check if files module can run
files_check() {
    check_dependencies curl
}
