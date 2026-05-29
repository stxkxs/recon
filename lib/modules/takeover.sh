#!/usr/bin/env bash
#
# takeover.sh - Subdomain takeover detection module for recon
#
# Checks subdomains for dangling CNAMEs and known vulnerable service
# fingerprints that could allow subdomain takeover attacks.
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_TAKEOVER_LOADED:-}" ]] && return 0
_RECON_MODULE_TAKEOVER_LOADED=1

# Module info
MODULE_TAKEOVER_NAME="takeover"
MODULE_TAKEOVER_DESCRIPTION="Subdomain takeover detection"

# Known vulnerable services: CNAME pattern → service name
declare -A TAKEOVER_SERVICES
TAKEOVER_SERVICES=(
    [".github.io"]="GitHub Pages"
    [".herokuapp.com"]="Heroku"
    [".herokudns.com"]="Heroku"
    [".s3.amazonaws.com"]="AWS S3"
    [".s3-website"]="AWS S3"
    [".cloudfront.net"]="AWS CloudFront"
    [".azurewebsites.net"]="Azure"
    [".blob.core.windows.net"]="Azure Blob"
    [".cloudapp.net"]="Azure"
    [".trafficmanager.net"]="Azure Traffic Manager"
    [".myshopify.com"]="Shopify"
    [".ghost.io"]="Ghost"
    [".surge.sh"]="Surge"
    [".bitbucket.io"]="Bitbucket"
    [".wordpress.com"]="WordPress"
    [".pantheonsite.io"]="Pantheon"
    [".zendesk.com"]="Zendesk"
    [".teamwork.com"]="Teamwork"
    [".helpjuice.com"]="Helpjuice"
    [".helpscoutdocs.com"]="HelpScout"
    [".cargo.site"]="Cargo"
    [".statuspage.io"]="Statuspage"
    [".tumblr.com"]="Tumblr"
    [".ghost.org"]="Ghost"
    [".freshdesk.com"]="Freshdesk"
    [".uservoice.com"]="UserVoice"
    [".simplebooklet.com"]="Simplebooklet"
    [".fly.dev"]="Fly.io"
    [".netlify.app"]="Netlify"
    [".vercel.app"]="Vercel"
    [".unbouncepages.com"]="Unbounce"
    [".landingi.com"]="Landingi"
)

# Known error page fingerprints: body text → service name
declare -A TAKEOVER_FINGERPRINTS
TAKEOVER_FINGERPRINTS=(
    ["There isn't a GitHub Pages site here"]="GitHub Pages"
    ["No such app"]="Heroku"
    ["NoSuchBucket"]="AWS S3"
    ["The specified bucket does not exist"]="AWS S3"
    ["Sorry, this shop is currently unavailable"]="Shopify"
    ["The thing you were looking for is no longer here"]="Ghost"
    ["Do you want to register"]="WordPress"
    ["project not found"]="Surge"
    ["Repository not found"]="Bitbucket"
)

# Match a CNAME against known vulnerable services
# Usage: service=$(takeover_match_service "example.github.io")
# Returns: service name or empty string
takeover_match_service() {
    local cname=$1
    local cname_lower
    cname_lower=$(echo "$cname" | tr '[:upper:]' '[:lower:]')

    for pattern in "${!TAKEOVER_SERVICES[@]}"; do
        if [[ "$cname_lower" == *"$pattern"* ]]; then
            echo "${TAKEOVER_SERVICES[$pattern]}"
            return 0
        fi
    done

    echo ""
    return 1
}

# Check if a CNAME target is dangling (returns NXDOMAIN)
# Usage: if takeover_is_dangling "target.example.com" "$timeout"; then ...
takeover_is_dangling() {
    local target=$1
    local timeout=$2

    local dig_output
    dig_output=$(safe_timeout "$timeout" dig +noall +comments "$target" A 2>/dev/null || true)

    if echo "$dig_output" | grep -qi "NXDOMAIN"; then
        return 0
    fi

    return 1
}

# Check HTTP response for takeover fingerprints
# Usage: match=$(takeover_check_fingerprint "subdomain.example.com" "$timeout")
# Returns: fingerprint match string or empty
takeover_check_fingerprint() {
    local subdomain=$1
    local timeout=$2

    local body
    body=$(safe_timeout "$timeout" curl -sL -o - -k --max-time "$timeout" "http://${subdomain}" 2>/dev/null || true)

    if [[ -z "$body" ]]; then
        echo ""
        return 1
    fi

    for fingerprint in "${!TAKEOVER_FINGERPRINTS[@]}"; do
        if [[ "$body" == *"$fingerprint"* ]]; then
            echo "$fingerprint"
            return 0
        fi
    done

    echo ""
    return 1
}

# Run subdomain takeover detection
# Usage: takeover_run "example.com"
# Output: JSON object with takeover results
takeover_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "takeover" 2>/dev/null || echo "15")

    local vulnerable='[]'
    local findings='[]'
    local checked=0
    local total_subdomains=0

    # Collect subdomains with CNAMEs from scan data
    local subdomains_json='[]'

    if [[ -n "${RECON_SCAN_JSON:-}" ]]; then
        # Read subdomain results from scan data
        subdomains_json=$(echo "$RECON_SCAN_JSON" | jq -c '.results.subdomain.data.found // []' 2>/dev/null || echo '[]')
        total_subdomains=$(echo "$subdomains_json" | jq 'length' 2>/dev/null || echo "0")
    fi

    if [[ "$total_subdomains" -eq 0 ]]; then
        # No scan data: do a basic CNAME check on the target domain itself
        total_subdomains=1
        local cname
        cname=$(safe_timeout "$timeout" dig +short "$target" CNAME 2>/dev/null | head -1 || true)
        # Remove trailing dot
        cname="${cname%.}"

        if [[ -n "$cname" ]]; then
            subdomains_json=$(jq -n --arg fqdn "$target" --arg cname "$cname" \
                '[{fqdn: $fqdn, cname: $cname}]')
        else
            subdomains_json='[]'
        fi
    fi

    # Process each subdomain that has a CNAME
    local count
    count=$(echo "$subdomains_json" | jq 'length' 2>/dev/null || echo "0")

    local i=0
    while [[ $i -lt $count ]]; do
        local entry
        entry=$(echo "$subdomains_json" | jq -c ".[$i]")
        local fqdn cname
        fqdn=$(echo "$entry" | jq -r '.fqdn // empty')
        cname=$(echo "$entry" | jq -r '.cname // empty')

        ((i++))

        # Skip entries without a CNAME
        if [[ -z "$cname" ]] || [[ "$cname" == "null" ]]; then
            ((checked++))
            continue
        fi

        # Remove trailing dot from CNAME
        cname="${cname%.}"

        ((checked++))

        # Match CNAME against known vulnerable services
        local service
        service=$(takeover_match_service "$cname") || true

        if [[ -z "$service" ]]; then
            continue
        fi

        # Check if the CNAME target is dangling
        if takeover_is_dangling "$cname" "$timeout"; then
            vulnerable=$(echo "$vulnerable" | jq \
                --arg sub "$fqdn" \
                --arg cname "$cname" \
                --arg svc "$service" \
                '. += [{
                    subdomain: $sub,
                    cname: $cname,
                    service: $svc,
                    status: "dangling_cname",
                    confidence: "high",
                    detail: "CNAME target returns NXDOMAIN"
                }]')
            continue
        fi

        # CNAME resolves - check for takeover fingerprint in HTTP response
        local fingerprint
        fingerprint=$(takeover_check_fingerprint "$fqdn" "$timeout") || true

        if [[ -n "$fingerprint" ]]; then
            findings=$(echo "$findings" | jq \
                --arg sub "$fqdn" \
                --arg cname "$cname" \
                --arg svc "$service" \
                --arg fp "$fingerprint" \
                '. += [{
                    subdomain: $sub,
                    cname: $cname,
                    service: $svc,
                    status: "potential_takeover",
                    fingerprint_match: $fp
                }]')
        fi
    done

    # Build final JSON output
    jq -n \
        --argjson vulnerable "$vulnerable" \
        --argjson findings "$findings" \
        --argjson checked "$checked" \
        --argjson total "$total_subdomains" \
        '{
            vulnerable: $vulnerable,
            checked: $checked,
            total_subdomains: $total,
            findings: $findings
        }'
}

# Terminal output for takeover results
# Usage: takeover_print "$json_result" "example.com"
takeover_print() {
    local json=$1
    local target=${2:-""}

    header "SUBDOMAIN TAKEOVER - ${target}"

    local vuln_count
    vuln_count=$(echo "$json" | jq '.vulnerable | length')
    local finding_count
    finding_count=$(echo "$json" | jq '.findings | length')
    local checked
    checked=$(echo "$json" | jq '.checked')
    local total
    total=$(echo "$json" | jq '.total_subdomains')

    echo -e "  Checked: ${BOLD}${checked}${NC} / ${total} subdomains"
    echo ""

    # Dangling CNAMEs (high confidence)
    if [[ "$vuln_count" -gt 0 ]]; then
        subheader "Dangling CNAMEs (High Confidence)"
        echo "$json" | jq -r '.vulnerable[] | "\(.subdomain)|\(.cname)|\(.service)|\(.detail)"' | while IFS='|' read -r sub cname svc detail; do
            echo -e "  ${RED}!${NC} ${BOLD}${sub}${NC}"
            echo -e "    CNAME:   ${cname}"
            echo -e "    Service: ${svc}"
            echo -e "    Detail:  ${detail}"
            echo ""
        done
    fi

    # Fingerprint matches (potential takeover)
    if [[ "$finding_count" -gt 0 ]]; then
        subheader "Potential Takeovers (Fingerprint Match)"
        echo "$json" | jq -r '.findings[] | "\(.subdomain)|\(.cname)|\(.service)|\(.fingerprint_match)"' | while IFS='|' read -r sub cname svc fp; do
            echo -e "  ${YELLOW}!${NC} ${BOLD}${sub}${NC}"
            echo -e "    CNAME:       ${cname}"
            echo -e "    Service:     ${svc}"
            echo -e "    Fingerprint: ${fp}"
            echo ""
        done
    fi

    if [[ "$vuln_count" -eq 0 ]] && [[ "$finding_count" -eq 0 ]]; then
        success "No takeover vulnerabilities detected"
    else
        local total_issues=$((vuln_count + finding_count))
        warn "Found ${total_issues} potential takeover issue(s)"
    fi
}

# Check if takeover module can run
takeover_check() {
    check_dependencies dig curl jq
}
