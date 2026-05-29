#!/usr/bin/env bash
#
# dirs.sh - Directory and sensitive file discovery module for recon
#
# Probes common directories, config files, admin panels, API docs,
# debug endpoints, backup files, actuator endpoints, and security
# files to identify exposed sensitive resources.
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_DIRS_LOADED:-}" ]] && return 0
_RECON_MODULE_DIRS_LOADED=1

# Module info
MODULE_DIRS_NAME="dirs"
MODULE_DIRS_DESCRIPTION="Directory and sensitive file discovery"

# Path categories
# Version control
DIRS_VERSION_CONTROL=( "/.git/config" "/.git/HEAD" "/.svn/entries" "/.svn/wc.db" "/.hg/dirstate" "/.bzr/README" )

# Config files
DIRS_CONFIG_FILES=( "/.env" "/.env.local" "/.env.production" "/.env.backup" "/config.php" "/config.yml" "/config.json" "/wp-config.php" "/wp-config.php.bak" "/configuration.php" "/database.yml" "/.htaccess" "/.htpasswd" "/web.config" "/appsettings.json" )

# Admin panels
DIRS_ADMIN_PANELS=( "/admin" "/admin/" "/administrator/" "/wp-admin/" "/wp-login.php" "/phpmyadmin/" "/adminer.php" "/cpanel" "/webmail" "/manager/html" )

# API docs
DIRS_API_DOCS=( "/swagger.json" "/swagger-ui.html" "/api-docs" "/swagger/" "/openapi.json" "/graphql" "/graphiql" "/_graphql" "/api/swagger" "/redoc" )

# Debug/Dev
DIRS_DEBUG_DEV=( "/phpinfo.php" "/info.php" "/debug" "/_debug" "/trace" "/elmah.axd" "/server-status" "/server-info" "/.DS_Store" "/Thumbs.db" "/test.php" "/debug.php" )

# Backup files
DIRS_BACKUP=( "/backup/" "/backups/" "/backup.zip" "/backup.sql" "/dump.sql" "/database.sql" "/db.sql" "/site.tar.gz" "/www.zip" "/backup.tar.gz" )

# Actuator/monitoring
DIRS_ACTUATOR=( "/actuator" "/actuator/health" "/actuator/env" "/actuator/configprops" "/health" "/metrics" "/jolokia" "/console" )

# Security files
DIRS_SECURITY=( "/.well-known/security.txt" "/security.txt" "/crossdomain.xml" "/clientaccesspolicy.xml" "/robots.txt" "/sitemap.xml" )

# Map a path to its category name
# Usage: _dirs_get_category "/path"
_dirs_get_category() {
    local path=$1

    local p
    for p in "${DIRS_VERSION_CONTROL[@]}"; do
        [[ "$p" == "$path" ]] && echo "version_control" && return 0
    done
    for p in "${DIRS_CONFIG_FILES[@]}"; do
        [[ "$p" == "$path" ]] && echo "config_file" && return 0
    done
    for p in "${DIRS_ADMIN_PANELS[@]}"; do
        [[ "$p" == "$path" ]] && echo "admin_panel" && return 0
    done
    for p in "${DIRS_API_DOCS[@]}"; do
        [[ "$p" == "$path" ]] && echo "api_docs" && return 0
    done
    for p in "${DIRS_DEBUG_DEV[@]}"; do
        [[ "$p" == "$path" ]] && echo "debug_dev" && return 0
    done
    for p in "${DIRS_BACKUP[@]}"; do
        [[ "$p" == "$path" ]] && echo "backup" && return 0
    done
    for p in "${DIRS_ACTUATOR[@]}"; do
        [[ "$p" == "$path" ]] && echo "actuator" && return 0
    done
    for p in "${DIRS_SECURITY[@]}"; do
        [[ "$p" == "$path" ]] && echo "security" && return 0
    done

    echo "custom"
    return 0
}

# Determine severity based on category, path, and status code
# Usage: _dirs_get_severity "category" "path" status_code
_dirs_get_severity() {
    local category=$1
    local path=$2
    local status=$3

    # 403 results are always low severity
    if [[ "$status" -eq 403 ]]; then
        echo "low"
        return 0
    fi

    # Critical: version control or config files exposed with 200
    if [[ "$status" -eq 200 ]]; then
        case "$category" in
            version_control)
                echo "critical"
                return 0
                ;;
            config_file)
                # .env files and database configs are critical
                case "$path" in
                    /.env|/.env.local|/.env.production|/.env.backup)
                        echo "critical"
                        ;;
                    /wp-config.php|/wp-config.php.bak|/database.yml|/.htpasswd)
                        echo "critical"
                        ;;
                    *)
                        echo "high"
                        ;;
                esac
                return 0
                ;;
            admin_panel)
                echo "high"
                return 0
                ;;
            api_docs|actuator)
                echo "medium"
                return 0
                ;;
            debug_dev)
                echo "high"
                return 0
                ;;
            backup)
                echo "critical"
                return 0
                ;;
            security)
                echo "low"
                return 0
                ;;
            *)
                echo "medium"
                return 0
                ;;
        esac
    fi

    # 401 implies something exists behind auth
    if [[ "$status" -eq 401 ]]; then
        echo "medium"
        return 0
    fi

    # 301/302 redirects
    if [[ "$status" -eq 301 ]] || [[ "$status" -eq 302 ]]; then
        echo "low"
        return 0
    fi

    echo "low"
}

# Determine overall risk from findings
# Usage: _dirs_overall_risk "$findings_json"
_dirs_overall_risk() {
    local findings=$1

    local count
    count=$(echo "$findings" | jq 'length')

    if [[ "$count" -eq 0 ]]; then
        echo "none"
        return 0
    fi

    local has_critical has_high has_medium
    has_critical=$(echo "$findings" | jq '[.[] | select(.severity == "critical")] | length')
    has_high=$(echo "$findings" | jq '[.[] | select(.severity == "high")] | length')
    has_medium=$(echo "$findings" | jq '[.[] | select(.severity == "medium")] | length')

    if [[ "$has_critical" -gt 0 ]]; then
        echo "critical"
    elif [[ "$has_high" -gt 0 ]]; then
        echo "high"
    elif [[ "$has_medium" -gt 0 ]]; then
        echo "medium"
    else
        echo "low"
    fi
}

# Run directory discovery
# Usage: dirs_run "example.com"
# Output: JSON object with discovery results
dirs_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "dirs" 2>/dev/null || echo "10")

    local delay
    delay=$(config_get "modules.dirs.request_delay" "0.2")

    # Build the full path list from all categories
    local all_paths=()
    all_paths+=("${DIRS_VERSION_CONTROL[@]}")
    all_paths+=("${DIRS_CONFIG_FILES[@]}")
    all_paths+=("${DIRS_ADMIN_PANELS[@]}")
    all_paths+=("${DIRS_API_DOCS[@]}")
    all_paths+=("${DIRS_DEBUG_DEV[@]}")
    all_paths+=("${DIRS_BACKUP[@]}")
    all_paths+=("${DIRS_ACTUATOR[@]}")
    all_paths+=("${DIRS_SECURITY[@]}")

    # Load custom wordlist if configured
    local custom_wordlist
    custom_wordlist=$(config_get "modules.dirs.wordlist" "")
    if [[ -n "$custom_wordlist" ]] && [[ -f "$custom_wordlist" ]]; then
        while IFS= read -r line; do
            line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [[ -z "$line" ]] && continue
            [[ "$line" == \#* ]] && continue
            # Ensure path starts with /
            [[ "$line" != /* ]] && line="/$line"
            all_paths+=("$line")
        done < "$custom_wordlist"
    fi

    local total_checked=0
    local findings='[]'
    local categories='{}'

    # Interesting status codes
    local interesting_codes="200 403 401 301 302"

    for path in "${all_paths[@]}"; do
        local status
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-redirs 0 --connect-timeout 5 --max-time "$timeout" "https://${target}${path}" 2>/dev/null || echo "000")
        ((total_checked++)) || true

        # Check if status code is interesting
        local is_interesting=false
        for code in $interesting_codes; do
            if [[ "$status" == "$code" ]]; then
                is_interesting=true
                break
            fi
        done

        if $is_interesting; then
            local category
            category=$(_dirs_get_category "$path")

            local severity
            severity=$(_dirs_get_severity "$category" "$path" "$status")

            findings=$(echo "$findings" | jq \
                --arg path "$path" \
                --argjson status "$status" \
                --arg category "$category" \
                --arg severity "$severity" \
                '. += [{"path": $path, "status": $status, "category": $category, "severity": $severity}]')

            # Update category counts
            local current_count
            current_count=$(echo "$categories" | jq -r --arg cat "$category" '.[$cat] // 0')
            categories=$(echo "$categories" | jq --arg cat "$category" --argjson count "$((current_count + 1))" '.[$cat] = $count')
        fi

        # Rate limit between requests
        sleep "$delay"
    done

    local found_count
    found_count=$(echo "$findings" | jq 'length')

    local risk
    risk=$(_dirs_overall_risk "$findings")

    jq -n \
        --argjson total_checked "$total_checked" \
        --argjson found "$findings" \
        --arg risk "$risk" \
        --argjson categories "$categories" \
        '{
            total_checked: $total_checked,
            found: $found,
            risk: $risk,
            categories: $categories
        }'
}

# Terminal output for directory discovery results
# Usage: dirs_print "$json_result" "example.com"
dirs_print() {
    local json=$1
    local target=$2

    header "DIRECTORY DISCOVERY - $target"

    local risk
    risk=$(echo "$json" | jq -r '.risk')

    local total_checked
    total_checked=$(echo "$json" | jq -r '.total_checked')

    local found_count
    found_count=$(echo "$json" | jq '.found | length')

    # Risk level display
    subheader "Risk Level"
    case "$risk" in
        critical) error "CRITICAL" ;;
        high)     error "HIGH" ;;
        medium)   warn "MEDIUM" ;;
        low)      info "LOW" ;;
        none)     success "NONE" ;;
    esac

    # Summary counts
    subheader "Summary"
    info "Total paths checked: $total_checked"
    if [[ "$found_count" -gt 0 ]]; then
        success "Findings: $found_count"
    else
        success "No sensitive paths found"
        return 0
    fi

    # Group by severity, show critical and high first
    for severity in critical high medium low; do
        local sev_findings
        sev_findings=$(echo "$json" | jq -r --arg s "$severity" '[.found[] | select(.severity == $s)]')
        local sev_count
        sev_count=$(echo "$sev_findings" | jq 'length')

        if [[ "$sev_count" -gt 0 ]]; then
            subheader "${severity^^} Severity ($sev_count)"
            echo "$sev_findings" | jq -r '.[] | "\(.path) [HTTP \(.status)] (\(.category))"' | while IFS= read -r line; do
                case "$severity" in
                    critical|high) error "$line" ;;
                    medium)        warn "$line" ;;
                    low)           info "$line" ;;
                esac
            done
        fi
    done

    # Category breakdown
    local cat_count
    cat_count=$(echo "$json" | jq '.categories | length')
    if [[ "$cat_count" -gt 0 ]]; then
        subheader "Category Breakdown"
        echo "$json" | jq -r '.categories | to_entries[] | "\(.key): \(.value)"' | while IFS= read -r line; do
            info "$line"
        done
    fi
}

# Check if dirs module can run
# Returns 0 if dependencies are met
dirs_check() {
    check_dependencies curl jq
}
