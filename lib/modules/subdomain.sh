#!/usr/bin/env bash
#
# subdomain.sh - Subdomain discovery module for recond
#
# Checks common subdomains against a target domain
# Supports custom wordlists and parallel checking
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_SUBDOMAIN_LOADED:-}" ]] && return 0
_RECOND_MODULE_SUBDOMAIN_LOADED=1

# Module info
MODULE_SUBDOMAIN_NAME="subdomain"
MODULE_SUBDOMAIN_DESCRIPTION="Subdomain discovery"

# Default subdomains (fallback if no wordlist)
DEFAULT_SUBDOMAINS=(
    www app api blog docs developer dev
    help support status mail admin staging
    test beta cdn assets static ws graphql
    oauth auth sso login portal dashboard
    admin2 console manage git gitlab ci
    metrics grafana kibana elastic
    internal corp vpn intranet
    billing payments stripe
    integrations connect webhooks events
    mobile m ios android
    sandbox demo preview
    cdn1 cdn2 images img files upload media
    smtp email imap calendar
    voip phone sip call
    search analytics tracking
    db database redis cache
    queue jobs workers
    reporting reports export
)

# Load wordlist from file
# Usage: readarray -t subdomains < <(subdomain_load_wordlist "/path/to/wordlist.txt")
subdomain_load_wordlist() {
    local wordlist=$1

    if [[ -f "$wordlist" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Skip empty lines and comments
            [[ -z "$line" ]] && continue
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            # Trim whitespace
            line=$(echo "$line" | xargs)
            [[ -n "$line" ]] && echo "$line"
        done < "$wordlist"
    fi
}

# Get subdomains to check (from wordlist or defaults)
# Usage: readarray -t subs < <(subdomain_get_list)
subdomain_get_list() {
    local wordlist
    wordlist=$(config_get "modules.subdomain.wordlist" "" 2>/dev/null || echo "")

    # Try wordlist file
    if [[ -n "$wordlist" ]] && [[ -f "$wordlist" ]]; then
        subdomain_load_wordlist "$wordlist"
        return 0
    fi

    # Try default wordlist location
    local script_dir
    script_dir=$(get_script_dir 2>/dev/null || echo ".")
    local default_wordlist="${script_dir}/../../etc/subdomains.txt"
    if [[ -f "$default_wordlist" ]]; then
        subdomain_load_wordlist "$default_wordlist"
        return 0
    fi

    # Fallback to built-in list
    printf '%s\n' "${DEFAULT_SUBDOMAINS[@]}"
}

# Run subdomain enumeration
# Usage: subdomain_run "example.com"
# Output: JSON object with discovered subdomains
subdomain_run() {
    local domain=$1
    local timeout
    timeout=$(get_timeout "dns" 2>/dev/null || echo "5")

    local result_json
    result_json=$(jq -n '{
        found: [],
        checked: 0,
        total: 0
    }')

    # Get subdomain list
    local subdomains=()
    readarray -t subdomains < <(subdomain_get_list)
    local total=${#subdomains[@]}

    result_json=$(echo "$result_json" | jq --arg total "$total" '.total = ($total | tonumber)')

    local found_json='[]'
    local checked=0

    for sub in "${subdomains[@]}"; do
        ((checked++))

        local fqdn="${sub}.${domain}"

        # Try to resolve A record
        local ip
        ip=$(safe_timeout "$timeout" dig +short "$fqdn" A 2>/dev/null | head -1 || true)

        if [[ -n "$ip" ]] && [[ "$ip" =~ ^[0-9.]+$ ]]; then
            # Check for CNAME
            local cname
            cname=$(safe_timeout "$timeout" dig +short "$fqdn" CNAME 2>/dev/null | head -1 || true)

            local entry
            if [[ -n "$cname" ]]; then
                entry=$(jq -n \
                    --arg sub "$sub" \
                    --arg fqdn "$fqdn" \
                    --arg ip "$ip" \
                    --arg cname "$cname" \
                    '{subdomain: $sub, fqdn: $fqdn, ip: $ip, cname: $cname}')
            else
                entry=$(jq -n \
                    --arg sub "$sub" \
                    --arg fqdn "$fqdn" \
                    --arg ip "$ip" \
                    '{subdomain: $sub, fqdn: $fqdn, ip: $ip, cname: null}')
            fi

            found_json=$(echo "$found_json" | jq --argjson entry "$entry" '. += [$entry]')
        fi
    done

    result_json=$(echo "$result_json" | jq \
        --argjson found "$found_json" \
        --arg checked "$checked" \
        '.found = $found | .checked = ($checked | tonumber)')

    echo "$result_json"
}

# Terminal output for subdomain results
# Usage: subdomain_print "$json_result"
subdomain_print() {
    local json=$1

    header "SUBDOMAIN ENUMERATION"

    local found_count
    found_count=$(echo "$json" | jq '.found | length')
    local total
    total=$(echo "$json" | jq '.total')

    if [[ "$found_count" -gt 0 ]]; then
        echo "$json" | jq -r '.found[] | "\(.fqdn)|\(.ip)|\(.cname // "")"' | while IFS='|' read -r fqdn ip cname; do
            if [[ -n "$cname" ]]; then
                printf "  ${GREEN}%-30s${NC} → %s ${YELLOW}(CNAME: %s)${NC}\n" "$fqdn" "$ip" "$cname"
            else
                printf "  ${GREEN}%-30s${NC} → %s\n" "$fqdn" "$ip"
            fi
        done
        echo -e "\n${CYAN}Found $found_count subdomains (checked $total)${NC}"
    else
        info "No common subdomains found (checked $total)"
    fi
}

# Check if subdomain module can run
subdomain_check() {
    check_dependencies dig
}
