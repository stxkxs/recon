#!/usr/bin/env bash
#
# dnssec.sh - DNSSEC validation module for recon
#
# Validates DNSSEC deployment including:
# DNSKEY, DS, RRSIG records, NSEC/NSEC3, and AD flag
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_DNSSEC_LOADED:-}" ]] && return 0
_RECON_MODULE_DNSSEC_LOADED=1

# Module info
MODULE_DNSSEC_NAME="dnssec"
MODULE_DNSSEC_DESCRIPTION="DNSSEC validation"

# Run DNSSEC validation
# Usage: dnssec_run "example.com"
# Output: JSON object with DNSSEC results
dnssec_run() {
    local domain=$1
    local timeout
    timeout=$(get_timeout "dnssec" 2>/dev/null || echo "10")

    # Query DNSKEY records
    local dnskey_output
    dnskey_output=$(safe_timeout "$timeout" dig +dnssec "$domain" DNSKEY +short 2>/dev/null || true)
    local has_dnskey=false
    local algorithm="null"
    local key_count=0
    if [[ -n "$dnskey_output" ]]; then
        has_dnskey=true
        key_count=$(echo "$dnskey_output" | grep -c '^' || true)
        # Extract algorithm from first DNSKEY line (field 3)
        local algo_num
        algo_num=$(echo "$dnskey_output" | head -1 | awk '{print $3}')
        case "$algo_num" in
            5)  algorithm="RSASHA1" ;;
            7)  algorithm="RSASHA1-NSEC3-SHA1" ;;
            8)  algorithm="RSASHA256" ;;
            10) algorithm="RSASHA512" ;;
            13) algorithm="ECDSAP256SHA256" ;;
            14) algorithm="ECDSAP384SHA384" ;;
            15) algorithm="ED25519" ;;
            16) algorithm="ED448" ;;
            *)  algorithm="UNKNOWN($algo_num)" ;;
        esac
    fi

    # Query DS records
    local ds_output
    ds_output=$(safe_timeout "$timeout" dig +dnssec "$domain" DS +short 2>/dev/null || true)
    local has_ds=false
    if [[ -n "$ds_output" ]]; then
        has_ds=true
    fi

    # Query RRSIG records
    local rrsig_output
    rrsig_output=$(safe_timeout "$timeout" dig +dnssec "$domain" RRSIG +short 2>/dev/null || true)
    local has_rrsig=false
    if [[ -n "$rrsig_output" ]]; then
        has_rrsig=true
    fi

    # Query NSEC3PARAM (indicates NSEC3 usage)
    local nsec3_output
    nsec3_output=$(safe_timeout "$timeout" dig "$domain" NSEC3PARAM +short 2>/dev/null || true)
    local has_nsec3=false
    if [[ -n "$nsec3_output" ]]; then
        has_nsec3=true
    fi

    # Check AD (Authenticated Data) flag
    local ad_output
    ad_output=$(safe_timeout "$timeout" dig +dnssec "$domain" A 2>/dev/null || true)
    local has_ad=false
    if echo "$ad_output" | grep -q 'flags:.*ad'; then
        has_ad=true
    fi

    # Determine enabled and valid status
    local enabled=false
    local valid=false
    if [[ "$has_dnskey" == "true" ]]; then
        enabled=true
        if [[ "$has_ds" == "true" ]] && [[ "$has_rrsig" == "true" ]]; then
            valid=true
        fi
    fi

    # Build JSON output
    local algo_json
    if [[ "$algorithm" == "null" ]]; then
        algo_json="null"
    else
        algo_json="\"$algorithm\""
    fi

    jq -n \
        --argjson enabled "$enabled" \
        --argjson valid "$valid" \
        --argjson dnskey "$has_dnskey" \
        --argjson ds "$has_ds" \
        --argjson rrsig "$has_rrsig" \
        --argjson nsec3 "$has_nsec3" \
        --argjson ad_flag "$has_ad" \
        --argjson algorithm "$algo_json" \
        --argjson key_count "$key_count" \
        '{
            enabled: $enabled,
            valid: $valid,
            dnskey: $dnskey,
            ds: $ds,
            rrsig: $rrsig,
            nsec3: $nsec3,
            ad_flag: $ad_flag,
            algorithm: $algorithm,
            key_count: $key_count
        }'
}

# Terminal output for DNSSEC results
# Usage: dnssec_print "$json_result" "example.com"
dnssec_print() {
    local json=$1
    local domain=$2

    header "DNSSEC VALIDATION - $domain"

    local enabled
    enabled=$(echo "$json" | jq -r '.enabled')

    if [[ "$enabled" == "true" ]]; then
        success "DNSSEC is enabled"

        local valid
        valid=$(echo "$json" | jq -r '.valid')
        if [[ "$valid" == "true" ]]; then
            success "DNSSEC chain is valid (DNSKEY + DS + RRSIG present)"
        else
            warn "DNSSEC chain is incomplete"
        fi

        subheader "Record Status"

        local dnskey ds rrsig nsec3 ad_flag
        dnskey=$(echo "$json" | jq -r '.dnskey')
        ds=$(echo "$json" | jq -r '.ds')
        rrsig=$(echo "$json" | jq -r '.rrsig')
        nsec3=$(echo "$json" | jq -r '.nsec3')
        ad_flag=$(echo "$json" | jq -r '.ad_flag')

        [[ "$dnskey" == "true" ]] && success "DNSKEY: present" || warn "DNSKEY: missing"
        [[ "$ds" == "true" ]] && success "DS: present" || warn "DS: missing"
        [[ "$rrsig" == "true" ]] && success "RRSIG: present" || warn "RRSIG: missing"
        [[ "$nsec3" == "true" ]] && success "NSEC3: enabled (zone walking resistant)" || info "NSEC3: not detected"
        [[ "$ad_flag" == "true" ]] && success "AD flag: set (authenticated)" || warn "AD flag: not set"

        subheader "Key Details"
        local algorithm key_count
        algorithm=$(echo "$json" | jq -r '.algorithm // "unknown"')
        key_count=$(echo "$json" | jq -r '.key_count')
        info "Algorithm: $algorithm"
        info "Key count: $key_count"
    else
        warn "DNSSEC is not enabled for $domain"
    fi
}

# Check if DNSSEC module can run
# Returns 0 if dependencies are met
dnssec_check() {
    check_dependencies dig jq
}
