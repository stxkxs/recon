#!/usr/bin/env bash
#
# jsanalysis.sh - JavaScript file analysis module for recon
#
# Discovers and analyzes JavaScript files on a target for:
# exposed API keys, hardcoded secrets, API endpoints,
# source map references, and internal URLs.
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_JSANALYSIS_LOADED:-}" ]] && return 0
_RECON_MODULE_JSANALYSIS_LOADED=1

# Module info
MODULE_JSANALYSIS_NAME="jsanalysis"
MODULE_JSANALYSIS_DESCRIPTION="JavaScript file analysis"

# CDN domains to skip (third-party libraries)
_JSANALYSIS_CDN_DOMAINS=(
    "cdnjs.cloudflare.com"
    "unpkg.com"
    "cdn.jsdelivr.net"
    "ajax.googleapis.com"
    "code.jquery.com"
    "stackpath.bootstrapcdn.com"
    "maxcdn.bootstrapcdn.com"
    "fonts.googleapis.com"
)

# API key / secret patterns
_JSANALYSIS_AWS_KEY_PATTERN='AKIA[0-9A-Z]{16}'
_JSANALYSIS_GOOGLE_API_PATTERN='AIza[0-9A-Za-z_-]{35}'
_JSANALYSIS_GITHUB_TOKEN_PATTERN='gh[pousr]_[A-Za-z0-9_]{36}'
_JSANALYSIS_SLACK_TOKEN_PATTERN='xox[baprs]-[0-9a-zA-Z-]+'
_JSANALYSIS_STRIPE_KEY_PATTERN='[sr]k_(live|test)_[0-9a-zA-Z]{24,}'
_JSANALYSIS_JWT_PATTERN='eyJ[A-Za-z0-9_-]*\.eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*'
_JSANALYSIS_GENERIC_SECRET_PATTERN='["'"'"'](api[_-]?key|api[_-]?secret|access[_-]?token|secret[_-]?key|private[_-]?key|auth[_-]?token)["'"'"'][[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9+/=_-]{8,}["'"'"']'

# Mask a secret value for safe display
# Usage: _jsanalysis_mask_secret "AKIAIOSFODNN7EXAMPLE"
# Output: "AKIA...MPLE"
_jsanalysis_mask_secret() {
    local secret=$1
    local len=${#secret}
    if [[ "$len" -le 8 ]]; then
        echo "${secret:0:2}***${secret: -2}"
    else
        echo "${secret:0:4}...${secret: -4}"
    fi
}

# Check if a URL belongs to a CDN domain
# Usage: _jsanalysis_is_cdn "https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js"
# Returns: 0 if CDN, 1 if not
_jsanalysis_is_cdn() {
    local url=$1
    for cdn in "${_JSANALYSIS_CDN_DOMAINS[@]}"; do
        if echo "$url" | grep -qi "$cdn"; then
            return 0
        fi
    done
    return 1
}

# Extract script src URLs from HTML
# Usage: _jsanalysis_extract_scripts "$html" "$target"
# Output: one URL per line, absolute URLs
_jsanalysis_extract_scripts() {
    local html=$1
    local target=$2

    # Extract src attributes from script tags
    local raw_urls
    raw_urls=$(echo "$html" | grep -oE '<script[^>]*src=["'"'"'][^"'"'"']+["'"'"']' | sed -E 's/.*src=["'"'"']([^"'"'"']+)["'"'"'].*/\1/' || true)

    if [[ -z "$raw_urls" ]]; then
        return 0
    fi

    # Normalize URLs
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue

        # Skip data: and blob: URLs
        if echo "$url" | grep -qE '^(data:|blob:|javascript:)'; then
            continue
        fi

        # Make relative URLs absolute
        if echo "$url" | grep -qE '^https?://'; then
            echo "$url"
        elif echo "$url" | grep -qE '^//'; then
            echo "https:${url}"
        elif echo "$url" | grep -qE '^/'; then
            echo "https://${target}${url}"
        else
            echo "https://${target}/${url}"
        fi
    done <<< "$raw_urls"
}

# Scan a JS file content for secrets
# Usage: _jsanalysis_scan_secrets "$content"
# Output: JSON array of {type, value} objects
_jsanalysis_scan_secrets() {
    local content=$1
    local secrets='[]'

    # AWS keys
    local aws_matches
    aws_matches=$(echo "$content" | grep -oE "$_JSANALYSIS_AWS_KEY_PATTERN" 2>/dev/null || true)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        local masked
        masked=$(_jsanalysis_mask_secret "$match")
        secrets=$(echo "$secrets" | jq --arg type "aws_key" --arg value "$masked" '. += [{"type": $type, "value": $value}]')
    done <<< "$aws_matches"

    # Google API keys
    local google_matches
    google_matches=$(echo "$content" | grep -oE "$_JSANALYSIS_GOOGLE_API_PATTERN" 2>/dev/null || true)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        local masked
        masked=$(_jsanalysis_mask_secret "$match")
        secrets=$(echo "$secrets" | jq --arg type "google_api_key" --arg value "$masked" '. += [{"type": $type, "value": $value}]')
    done <<< "$google_matches"

    # GitHub tokens
    local github_matches
    github_matches=$(echo "$content" | grep -oE "$_JSANALYSIS_GITHUB_TOKEN_PATTERN" 2>/dev/null || true)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        local masked
        masked=$(_jsanalysis_mask_secret "$match")
        secrets=$(echo "$secrets" | jq --arg type "github_token" --arg value "$masked" '. += [{"type": $type, "value": $value}]')
    done <<< "$github_matches"

    # Slack tokens
    local slack_matches
    slack_matches=$(echo "$content" | grep -oE "$_JSANALYSIS_SLACK_TOKEN_PATTERN" 2>/dev/null || true)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        local masked
        masked=$(_jsanalysis_mask_secret "$match")
        secrets=$(echo "$secrets" | jq --arg type "slack_token" --arg value "$masked" '. += [{"type": $type, "value": $value}]')
    done <<< "$slack_matches"

    # Stripe keys
    local stripe_matches
    stripe_matches=$(echo "$content" | grep -oE "$_JSANALYSIS_STRIPE_KEY_PATTERN" 2>/dev/null || true)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        local masked
        masked=$(_jsanalysis_mask_secret "$match")
        secrets=$(echo "$secrets" | jq --arg type "stripe_key" --arg value "$masked" '. += [{"type": $type, "value": $value}]')
    done <<< "$stripe_matches"

    # JWTs
    local jwt_matches
    jwt_matches=$(echo "$content" | grep -oE "$_JSANALYSIS_JWT_PATTERN" 2>/dev/null || true)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        local masked
        masked=$(_jsanalysis_mask_secret "$match")
        secrets=$(echo "$secrets" | jq --arg type "jwt" --arg value "$masked" '. += [{"type": $type, "value": $value}]')
    done <<< "$jwt_matches"

    # Generic secrets (api_key, api_secret, access_token, etc.)
    local generic_matches
    generic_matches=$(echo "$content" | grep -oE "$_JSANALYSIS_GENERIC_SECRET_PATTERN" 2>/dev/null || true)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        local masked
        masked=$(_jsanalysis_mask_secret "$match")
        secrets=$(echo "$secrets" | jq --arg type "generic_secret" --arg value "$masked" '. += [{"type": $type, "value": $value}]')
    done <<< "$generic_matches"

    echo "$secrets"
}

# Scan a JS file content for API endpoints
# Usage: _jsanalysis_scan_endpoints "$content"
# Output: JSON array of endpoint strings
_jsanalysis_scan_endpoints() {
    local content=$1
    local endpoints='[]'

    # Match /api/v[0-9]... paths
    local api_versioned
    api_versioned=$(echo "$content" | grep -oE '/api/v[0-9]+[/a-zA-Z0-9_-]*' 2>/dev/null || true)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        endpoints=$(echo "$endpoints" | jq --arg e "$match" 'if (. | index($e)) then . else . += [$e] end')
    done <<< "$api_versioned"

    # Match /api/ paths
    local api_paths
    api_paths=$(echo "$content" | grep -oE '/api/[a-zA-Z0-9_/-]+' 2>/dev/null || true)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        endpoints=$(echo "$endpoints" | jq --arg e "$match" 'if (. | index($e)) then . else . += [$e] end')
    done <<< "$api_paths"

    # Match fetch/axios URL patterns
    local fetch_urls
    fetch_urls=$(echo "$content" | grep -oE 'fetch\(["'"'"']/[^"'"'"']+' 2>/dev/null | sed -E 's/fetch\(["'"'"']/\//' || true)
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        endpoints=$(echo "$endpoints" | jq --arg e "$match" 'if (. | index($e)) then . else . += [$e] end')
    done <<< "$fetch_urls"

    echo "$endpoints"
}

# Scan a JS file content for source map references
# Usage: _jsanalysis_scan_sourcemaps "$content"
# Output: JSON array of source map filenames
_jsanalysis_scan_sourcemaps() {
    local content=$1
    local sourcemaps='[]'

    local map_refs
    map_refs=$(echo "$content" | grep -oE '//# sourceMappingURL=[^ ]+' 2>/dev/null | sed 's|//# sourceMappingURL=||' || true)

    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        sourcemaps=$(echo "$sourcemaps" | jq --arg m "$match" 'if (. | index($m)) then . else . += [$m] end')
    done <<< "$map_refs"

    echo "$sourcemaps"
}

# Run JavaScript file analysis
# Usage: jsanalysis_run "example.com"
# Output: JSON object with analysis results
jsanalysis_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "jsanalysis" 2>/dev/null || echo "15")

    local max_files
    max_files=$(config_get "modules.jsanalysis.max_files" "20")
    local max_file_size
    max_file_size=$(config_get "modules.jsanalysis.max_file_size" "2097152")

    # Step 1: Fetch main page
    local html
    html=$(curl -s -L --max-time "$timeout" "https://$target/" 2>/dev/null || true)

    if [[ -z "$html" ]]; then
        warn "jsanalysis: Could not fetch page from $target"
        jq -n '{
            scripts_found: 0,
            scripts_analyzed: 0,
            api_keys: [],
            endpoints: [],
            source_maps: [],
            risk: "none",
            files: []
        }'
        return 0
    fi

    # Step 2: Extract script URLs
    local script_urls
    script_urls=$(_jsanalysis_extract_scripts "$html" "$target")

    local scripts_found=0
    local scripts_analyzed=0
    local all_keys='[]'
    local all_endpoints='[]'
    local all_sourcemaps='[]'
    local all_files='[]'

    if [[ -n "$script_urls" ]]; then
        scripts_found=$(echo "$script_urls" | wc -l | tr -d ' ')
    fi

    # Step 3 & 4: Filter CDN and download each JS file
    local file_count=0
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue

        # Stop if we've reached max files
        if [[ "$file_count" -ge "$max_files" ]]; then
            break
        fi

        # Skip CDN domains
        if _jsanalysis_is_cdn "$url"; then
            continue
        fi

        # Check file size before downloading
        local content_length
        content_length=$(curl -sI --max-time 5 "$url" 2>/dev/null | grep -i 'content-length' | sed -E 's/.*:[[:space:]]*([0-9]+).*/\1/' | head -1 || true)

        if [[ -n "$content_length" ]] && [[ "$content_length" -gt "$max_file_size" ]]; then
            debug "jsanalysis: Skipping $url (size: $content_length > max: $max_file_size)"
            continue
        fi

        # Download file
        local js_content
        js_content=$(safe_timeout "$timeout" curl -s --max-time "$timeout" "$url" 2>/dev/null || true)

        if [[ -z "$js_content" ]]; then
            continue
        fi

        ((file_count++)) || true
        ((scripts_analyzed++)) || true

        # Extract filename from URL
        local filename
        filename=$(basename "$url" | sed 's/?.*//')

        # Step 5: Scan for secrets
        local file_keys
        file_keys=$(_jsanalysis_scan_secrets "$js_content")
        local keys_count
        keys_count=$(echo "$file_keys" | jq 'length')

        # Add file reference to each key
        if [[ "$keys_count" -gt 0 ]]; then
            local keys_with_file
            keys_with_file=$(echo "$file_keys" | jq --arg f "$filename" '[.[] | . + {"file": $f}]')
            all_keys=$(echo "$all_keys" | jq --argjson new "$keys_with_file" '. + $new')
        fi

        # Step 6: Scan for endpoints
        local file_endpoints
        file_endpoints=$(_jsanalysis_scan_endpoints "$js_content")
        local endpoints_count
        endpoints_count=$(echo "$file_endpoints" | jq 'length')

        # Merge endpoints (deduplicate)
        if [[ "$endpoints_count" -gt 0 ]]; then
            all_endpoints=$(jq -n --argjson a "$all_endpoints" --argjson b "$file_endpoints" '$a + $b | unique')
        fi

        # Step 7: Scan for source maps
        local file_sourcemaps
        file_sourcemaps=$(_jsanalysis_scan_sourcemaps "$js_content")
        local sourcemaps_count
        sourcemaps_count=$(echo "$file_sourcemaps" | jq 'length')

        if [[ "$sourcemaps_count" -gt 0 ]]; then
            all_sourcemaps=$(jq -n --argjson a "$all_sourcemaps" --argjson b "$file_sourcemaps" '$a + $b | unique')
        fi

        # Get actual file size
        local file_size
        file_size=${#js_content}

        # Build file entry
        all_files=$(echo "$all_files" | jq \
            --arg url "$url" \
            --argjson size "$file_size" \
            --argjson keys_found "$keys_count" \
            --argjson endpoints_found "$endpoints_count" \
            '. += [{"url": $url, "size": $size, "keys_found": $keys_found, "endpoints_found": $endpoints_found}]')

    done <<< "$script_urls"

    # Determine risk level
    local total_keys
    total_keys=$(echo "$all_keys" | jq 'length')
    local total_sourcemaps
    total_sourcemaps=$(echo "$all_sourcemaps" | jq 'length')

    local risk="none"
    if [[ "$total_keys" -gt 0 ]]; then
        # Check for high-value secrets
        local has_aws has_stripe has_github
        has_aws=$(echo "$all_keys" | jq '[.[] | select(.type == "aws_key")] | length')
        has_stripe=$(echo "$all_keys" | jq '[.[] | select(.type == "stripe_key")] | length')
        has_github=$(echo "$all_keys" | jq '[.[] | select(.type == "github_token")] | length')

        if [[ "$has_aws" -gt 0 ]] || [[ "$has_stripe" -gt 0 ]] || [[ "$has_github" -gt 0 ]]; then
            risk="critical"
        elif [[ "$total_keys" -ge 3 ]]; then
            risk="high"
        else
            risk="medium"
        fi
    elif [[ "$total_sourcemaps" -gt 0 ]]; then
        risk="low"
    fi

    # Build final JSON output
    jq -n \
        --argjson scripts_found "$scripts_found" \
        --argjson scripts_analyzed "$scripts_analyzed" \
        --argjson api_keys "$all_keys" \
        --argjson endpoints "$all_endpoints" \
        --argjson source_maps "$all_sourcemaps" \
        --arg risk "$risk" \
        --argjson files "$all_files" \
        '{
            scripts_found: $scripts_found,
            scripts_analyzed: $scripts_analyzed,
            api_keys: $api_keys,
            endpoints: $endpoints,
            source_maps: $source_maps,
            risk: $risk,
            files: $files
        }'
}

# Terminal output for JS analysis results
# Usage: jsanalysis_print "$json_result" "example.com"
jsanalysis_print() {
    local json=$1
    local target=$2

    header "JS ANALYSIS - $target"

    local scripts_found scripts_analyzed risk
    scripts_found=$(echo "$json" | jq -r '.scripts_found')
    scripts_analyzed=$(echo "$json" | jq -r '.scripts_analyzed')
    risk=$(echo "$json" | jq -r '.risk')

    subheader "Overview"
    info "Scripts found: ${scripts_found}"
    info "Scripts analyzed: ${scripts_analyzed}"

    # Risk level with appropriate color
    case "$risk" in
        critical)
            error "Risk level: CRITICAL"
            ;;
        high)
            error "Risk level: HIGH"
            ;;
        medium)
            warn "Risk level: MEDIUM"
            ;;
        low)
            info "Risk level: LOW"
            ;;
        *)
            success "Risk level: NONE"
            ;;
    esac

    # API keys found
    local key_count
    key_count=$(echo "$json" | jq '.api_keys | length')
    if [[ "$key_count" -gt 0 ]]; then
        subheader "API Keys / Secrets Found ($key_count)"
        echo "$json" | jq -r '.api_keys[] | "\(.type): \(.value) [in \(.file)]"' | while IFS= read -r line; do
            error "$line"
        done
    else
        subheader "API Keys / Secrets"
        success "No exposed API keys or secrets found"
    fi

    # Endpoints
    local endpoint_count
    endpoint_count=$(echo "$json" | jq '.endpoints | length')
    if [[ "$endpoint_count" -gt 0 ]]; then
        subheader "API Endpoints ($endpoint_count)"
        echo "$json" | jq -r '.endpoints[]' | while IFS= read -r line; do
            info "$line"
        done
    fi

    # Source maps
    local sourcemap_count
    sourcemap_count=$(echo "$json" | jq '.source_maps | length')
    if [[ "$sourcemap_count" -gt 0 ]]; then
        subheader "Source Maps ($sourcemap_count)"
        echo "$json" | jq -r '.source_maps[]' | while IFS= read -r line; do
            warn "$line"
        done
    fi

    # Files analyzed
    local file_count
    file_count=$(echo "$json" | jq '.files | length')
    if [[ "$file_count" -gt 0 ]]; then
        subheader "Files Analyzed"
        echo "$json" | jq -r '.files[] | "\(.url) (size: \(.size), keys: \(.keys_found), endpoints: \(.endpoints_found))"' | while IFS= read -r line; do
            info "$line"
        done
    fi
}

# Check if JS analysis module can run
# Returns 0 if dependencies are met
jsanalysis_check() {
    check_dependencies curl jq
}
