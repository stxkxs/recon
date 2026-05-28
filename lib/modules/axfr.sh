#!/usr/bin/env bash
#
# axfr.sh - DNS zone transfer testing module for recond
#
# Tests each authoritative nameserver for AXFR (zone transfer)
# vulnerability and extracts transferred records if successful.
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_AXFR_LOADED:-}" ]] && return 0
_RECOND_MODULE_AXFR_LOADED=1

# Module info
MODULE_AXFR_NAME="axfr"
MODULE_AXFR_DESCRIPTION="DNS zone transfer testing"

# Run DNS zone transfer test
# Usage: axfr_run "example.com"
# Output: JSON object with AXFR results
axfr_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "axfr" 2>/dev/null || echo "10")

    # Step 1: Get nameservers for the target
    local ns_output
    ns_output=$(dig +short "$target" NS 2>/dev/null || true)

    # Clean nameserver entries: remove trailing dots, filter empty lines
    local nameservers=()
    while IFS= read -r ns; do
        # Remove trailing dot and whitespace
        ns=$(echo "$ns" | sed 's/\.$//' | tr -d '[:space:]')
        [[ -z "$ns" ]] && continue
        nameservers+=("$ns")
    done <<< "$ns_output"

    local ns_count=${#nameservers[@]}

    # If no nameservers found, return early
    if [[ "$ns_count" -eq 0 ]]; then
        jq -n '{
            nameservers_tested: 0,
            vulnerable: false,
            transfers: []
        }'
        return 0
    fi

    local vulnerable=false
    local transfers_json="[]"

    # Step 2: For each nameserver, attempt AXFR
    for ns in "${nameservers[@]}"; do
        local axfr_output
        axfr_output=$(safe_timeout "$timeout" dig AXFR "$target" "@$ns" 2>/dev/null || true)

        local success=false
        local records_json="[]"
        local records_count=0

        # Check if transfer succeeded: look for actual records (lines with IN keyword)
        # Filter out comments (;), empty lines, and error lines
        local record_lines
        record_lines=$(echo "$axfr_output" | grep -E $'\tIN\t' 2>/dev/null | grep -v '^;' || true)

        if [[ -n "$record_lines" ]]; then
            success=true
            vulnerable=true

            # Parse transferred records - extract name, type, and value
            # DNS record format: name TTL IN type value
            local count=0
            records_json="["
            local first=true

            while IFS= read -r line; do
                [[ -z "$line" ]] && continue

                # Cap at 500 records per transfer
                if [[ "$count" -ge 500 ]]; then
                    break
                fi

                # Parse the record line
                local rec_name rec_type rec_value
                rec_name=$(echo "$line" | awk '{print $1}' | sed 's/\.$//')
                rec_type=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="IN") print $(i+1)}')
                # Get everything after the record type
                rec_value=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="IN") {for(j=i+2;j<=NF;j++) printf "%s ", $j; print ""}}' | sed 's/[[:space:]]*$//')

                # Only include recognized record types
                case "$rec_type" in
                    A|AAAA|CNAME|MX|NS|TXT|SOA|SRV)
                        if [[ "$first" == "true" ]]; then
                            first=false
                        else
                            records_json+=","
                        fi
                        # Use jq to safely escape values
                        local rec_obj
                        rec_obj=$(jq -n \
                            --arg name "$rec_name" \
                            --arg type "$rec_type" \
                            --arg value "$rec_value" \
                            '{name: $name, type: $type, value: $value}')
                        records_json+="$rec_obj"
                        ((count++)) || true
                        ;;
                esac
            done <<< "$record_lines"

            records_json+="]"
            records_count=$count
        fi

        # Build per-nameserver result
        local transfer_obj
        transfer_obj=$(jq -n \
            --arg nameserver "$ns" \
            --argjson success "$success" \
            --argjson records_count "$records_count" \
            --argjson records "$records_json" \
            '{
                nameserver: $nameserver,
                success: $success,
                records_count: $records_count,
                records: $records
            }')

        transfers_json=$(echo "$transfers_json" | jq --argjson obj "$transfer_obj" '. + [$obj]')
    done

    # Build final JSON output
    jq -n \
        --argjson nameservers_tested "$ns_count" \
        --argjson vulnerable "$vulnerable" \
        --argjson transfers "$transfers_json" \
        '{
            nameservers_tested: $nameservers_tested,
            vulnerable: $vulnerable,
            transfers: $transfers
        }'
}

# Terminal output for AXFR results
# Usage: axfr_print "$json_result" "example.com"
axfr_print() {
    local json=$1
    local target=$2

    header "DNS ZONE TRANSFER TEST - $target"

    local ns_tested
    ns_tested=$(echo "$json" | jq -r '.nameservers_tested')
    info "Nameservers tested: $ns_tested"

    if [[ "$ns_tested" -eq 0 ]]; then
        warn "No nameservers found for $target"
        return 0
    fi

    local vulnerable
    vulnerable=$(echo "$json" | jq -r '.vulnerable')

    echo ""

    # Show each transfer attempt
    local transfer_count
    transfer_count=$(echo "$json" | jq '.transfers | length')

    local i=0
    while [[ "$i" -lt "$transfer_count" ]]; do
        local ns ns_success rec_count
        ns=$(echo "$json" | jq -r ".transfers[$i].nameserver")
        ns_success=$(echo "$json" | jq -r ".transfers[$i].success")
        rec_count=$(echo "$json" | jq -r ".transfers[$i].records_count")

        if [[ "$ns_success" == "true" ]]; then
            error "VULNERABLE: $ns - zone transfer succeeded ($rec_count records)"
        else
            success "SAFE: $ns - zone transfer refused"
        fi

        ((i++)) || true
    done

    # If vulnerable, show warning and sample records
    if [[ "$vulnerable" == "true" ]]; then
        echo ""
        warn "ZONE TRANSFER VULNERABILITY DETECTED"
        warn "Attackers can enumerate all DNS records for this domain"

        # Show sample records from the first successful transfer
        local j=0
        while [[ "$j" -lt "$transfer_count" ]]; do
            local j_success
            j_success=$(echo "$json" | jq -r ".transfers[$j].success")
            if [[ "$j_success" == "true" ]]; then
                local j_ns j_rec_count
                j_ns=$(echo "$json" | jq -r ".transfers[$j].nameserver")
                j_rec_count=$(echo "$json" | jq -r ".transfers[$j].records_count")

                subheader "Sample records from $j_ns ($j_rec_count total)"

                # Show up to 10 sample records
                local sample_limit=10
                if [[ "$j_rec_count" -lt "$sample_limit" ]]; then
                    sample_limit=$j_rec_count
                fi

                local k=0
                while [[ "$k" -lt "$sample_limit" ]]; do
                    local rec_name rec_type rec_value
                    rec_name=$(echo "$json" | jq -r ".transfers[$j].records[$k].name")
                    rec_type=$(echo "$json" | jq -r ".transfers[$j].records[$k].type")
                    rec_value=$(echo "$json" | jq -r ".transfers[$j].records[$k].value")
                    info "$rec_name  $rec_type  $rec_value"
                    ((k++)) || true
                done

                if [[ "$j_rec_count" -gt 10 ]]; then
                    info "... and $((j_rec_count - 10)) more records"
                fi

                break
            fi
            ((j++)) || true
        done
    else
        echo ""
        success "No zone transfer vulnerabilities detected"
    fi
}

# Check if AXFR module can run
# Returns 0 if dependencies are met
axfr_check() {
    check_dependencies dig
}
