#!/usr/bin/env bash
#
# asn.sh - ASN expansion and prefix enumeration module for recond
#
# Performs ASN lookups via Team Cymru DNS and enumerates all
# announced prefixes via RADB whois for network mapping.
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_ASN_LOADED:-}" ]] && return 0
_RECOND_MODULE_ASN_LOADED=1

# Module info
MODULE_ASN_NAME="asn"
MODULE_ASN_DESCRIPTION="ASN expansion and prefix enumeration"

# Run ASN expansion lookup
# Usage: asn_run "example.com" or asn_run "93.184.216.34"
# Output: JSON object with ASN and prefix data
asn_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "asn" 2>/dev/null || echo "15")

    # If target is not an IP, resolve it
    local ip="$target"
    if ! [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(dig +short "$target" A 2>/dev/null | head -1 || true)
        if [[ -z "$ip" ]] || ! [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            warn "ASN: could not resolve $target to an IP address"
            jq -n --arg t "$target" '{
                error: "resolve_failed",
                ip: "",
                asn: "",
                asn_name: "",
                asn_country: "",
                prefixes: [],
                total_prefixes: 0,
                total_ips_approx: 0
            }'
            return 0
        fi
    fi

    # Step 1: Team Cymru DNS lookup - reverse IP octets
    local o1 o2 o3 o4
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
    local reversed="${o4}.${o3}.${o2}.${o1}"

    local cymru_response
    cymru_response=$(dig +short "${reversed}.origin.asinfo.cymru.com" TXT 2>/dev/null || true)

    if [[ -z "$cymru_response" ]]; then
        warn "ASN: Team Cymru lookup returned no data for $ip"
        jq -n --arg ip "$ip" '{
            error: "no_asn_found",
            ip: $ip,
            asn: "",
            asn_name: "",
            asn_country: "",
            prefixes: [],
            total_prefixes: 0,
            total_ips_approx: 0
        }'
        return 0
    fi

    # Parse Cymru response: "ASN | prefix | CC | RIR | date"
    # Remove surrounding quotes
    cymru_response=$(echo "$cymru_response" | tr -d '"')

    local asn_number prefix asn_country
    asn_number=$(echo "$cymru_response" | awk -F'|' '{gsub(/[[:space:]]/, "", $1); print $1}')
    prefix=$(echo "$cymru_response" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')
    asn_country=$(echo "$cymru_response" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')

    if [[ -z "$asn_number" ]] || [[ "$asn_number" == "" ]]; then
        warn "ASN: could not parse ASN from Cymru response"
        jq -n --arg ip "$ip" '{
            error: "parse_failed",
            ip: $ip,
            asn: "",
            asn_name: "",
            asn_country: "",
            prefixes: [],
            total_prefixes: 0,
            total_ips_approx: 0
        }'
        return 0
    fi

    # Step 2: Get ASN name via Cymru lookup
    local asn_name_response asn_name
    asn_name_response=$(dig +short "AS${asn_number}.asn.cymru.com" TXT 2>/dev/null || true)

    if [[ -n "$asn_name_response" ]]; then
        # Remove quotes and extract the name (last field after the last pipe)
        asn_name_response=$(echo "$asn_name_response" | tr -d '"')
        asn_name=$(echo "$asn_name_response" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $NF); print $NF}')
    else
        asn_name=""
    fi

    # Step 3: Get all prefixes via RADB whois
    local whois_response
    whois_response=$(safe_timeout "$timeout" whois -h whois.radb.net -- "-i origin AS${asn_number}" 2>/dev/null || true)

    local prefixes_json="[]"
    local total_ips=0

    if [[ -n "$whois_response" ]]; then
        # Parse route: and descr: lines, grouping them as pairs
        local current_route="" current_descr=""
        local prefix_entries=()

        while IFS= read -r line; do
            if [[ "$line" =~ ^route:[[:space:]]*(.*) ]]; then
                # If we had a previous route, save it
                if [[ -n "$current_route" ]]; then
                    prefix_entries+=("${current_route}|${current_descr}")
                fi
                current_route=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                current_descr=""
            elif [[ "$line" =~ ^descr:[[:space:]]*(.*) ]]; then
                # Only capture first descr line per route block
                if [[ -z "$current_descr" ]]; then
                    current_descr=$(echo "${BASH_REMATCH[1]}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                fi
            elif [[ -z "$line" ]] || [[ "$line" =~ ^$ ]]; then
                # Empty line marks end of a record block
                if [[ -n "$current_route" ]]; then
                    prefix_entries+=("${current_route}|${current_descr}")
                    current_route=""
                    current_descr=""
                fi
            fi
        done <<< "$whois_response"

        # Save last entry if present
        if [[ -n "$current_route" ]]; then
            prefix_entries+=("${current_route}|${current_descr}")
        fi

        # Deduplicate and build JSON array
        local seen_prefixes=()
        local unique_entries=()
        for entry in "${prefix_entries[@]}"; do
            local p="${entry%%|*}"
            local already_seen=false
            for seen in "${seen_prefixes[@]:-}"; do
                if [[ "$seen" == "$p" ]]; then
                    already_seen=true
                    break
                fi
            done
            if ! $already_seen; then
                seen_prefixes+=("$p")
                unique_entries+=("$entry")
            fi
        done

        # Build JSON and calculate IP count
        if [[ ${#unique_entries[@]} -gt 0 ]]; then
            local json_items=()
            for entry in "${unique_entries[@]}"; do
                local p="${entry%%|*}"
                local d="${entry#*|}"
                json_items+=("$(jq -n --arg prefix "$p" --arg description "$d" \
                    '{prefix: $prefix, description: $description}')")

                # Calculate IP count from CIDR
                if [[ "$p" =~ /([0-9]+)$ ]]; then
                    local cidr_len="${BASH_REMATCH[1]}"
                    local ip_count=$((1 << (32 - cidr_len)))
                    total_ips=$((total_ips + ip_count))
                fi
            done

            prefixes_json=$(printf '%s\n' "${json_items[@]}" | jq -s '.')
        fi
    fi

    local total_prefixes
    total_prefixes=$(echo "$prefixes_json" | jq 'length')

    # Build final JSON
    jq -n \
        --arg ip "$ip" \
        --arg asn "AS${asn_number}" \
        --arg asn_name "$asn_name" \
        --arg asn_country "$asn_country" \
        --argjson prefixes "$prefixes_json" \
        --argjson total_prefixes "$total_prefixes" \
        --argjson total_ips_approx "$total_ips" \
        '{
            ip: $ip,
            asn: $asn,
            asn_name: $asn_name,
            asn_country: $asn_country,
            prefixes: $prefixes,
            total_prefixes: $total_prefixes,
            total_ips_approx: $total_ips_approx
        }'
}

# Terminal output for ASN expansion results
# Usage: asn_print "$json_result" "example.com"
asn_print() {
    local json=$1
    local target=$2

    header "ASN EXPANSION - $target"

    # Check for error
    local err
    err=$(echo "$json" | jq -r '.error // empty')
    if [[ -n "$err" ]]; then
        warn "ASN lookup not available: $err"
        return 0
    fi

    # ASN info
    subheader "ASN Information"
    local asn asn_name asn_country
    asn=$(echo "$json" | jq -r '.asn // empty')
    asn_name=$(echo "$json" | jq -r '.asn_name // empty')
    asn_country=$(echo "$json" | jq -r '.asn_country // empty')

    [[ -n "$asn" ]] && success "ASN: $asn"
    [[ -n "$asn_name" ]] && info "Name: $asn_name"
    [[ -n "$asn_country" ]] && info "Country: $asn_country"

    local ip
    ip=$(echo "$json" | jq -r '.ip // empty')
    [[ -n "$ip" ]] && info "Resolved IP: $ip"

    # Prefix summary
    subheader "Prefix Summary"
    local total_prefixes total_ips_approx
    total_prefixes=$(echo "$json" | jq -r '.total_prefixes')
    total_ips_approx=$(echo "$json" | jq -r '.total_ips_approx')

    info "Total prefixes: ${total_prefixes}"
    info "Approximate IP count: ${total_ips_approx}"

    # List prefixes (limit to first 20)
    if [[ "$total_prefixes" -gt 0 ]]; then
        local display_count=$total_prefixes
        if [[ "$display_count" -gt 20 ]]; then
            display_count=20
        fi

        subheader "Announced Prefixes (showing ${display_count} of ${total_prefixes})"
        echo "$json" | jq -r '.prefixes[:20][] | "\(.prefix)\(if .description != "" then " - " + .description else "" end)"' | while read -r line; do
            success "$line"
        done

        if [[ "$total_prefixes" -gt 20 ]]; then
            info "... and $((total_prefixes - 20)) more prefixes"
        fi
    else
        info "No announced prefixes found"
    fi
}

# Check if ASN module can run
# Returns 0 if dependencies are met
asn_check() {
    check_dependencies dig whois jq
}
