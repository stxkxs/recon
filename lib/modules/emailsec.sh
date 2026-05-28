#!/usr/bin/env bash
#
# emailsec.sh - Email security analysis module for recond
#
# Performs comprehensive email security analysis including:
# SPF record parsing and validation, DMARC policy analysis,
# DKIM selector discovery and key strength checking, and BIMI records.
#
# This module runs AFTER other modules and reads their results.
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_EMAILSEC_LOADED:-}" ]] && return 0
_RECOND_MODULE_EMAILSEC_LOADED=1

# Module info
MODULE_EMAILSEC_NAME="emailsec"
MODULE_EMAILSEC_DESCRIPTION="Email security analysis"

# DKIM selectors to check
EMAILSEC_DKIM_SELECTORS=(google default mail dkim s1 s2 k1 k2 selector1 selector2 mandrill amazonses)

# ─── SPF Analysis ───

# Count DNS lookups for an SPF record (includes, a, mx, ptr, exists, redirect)
# Usage: count=$(emailsec_count_spf_lookups "v=spf1 include:_spf.google.com ~all" "$target" "$timeout" 0)
emailsec_count_spf_lookups() {
    local record=$1
    local target=$2
    local timeout=$3
    local depth=${4:-0}

    # Prevent infinite recursion
    if [[ "$depth" -ge 10 ]]; then
        echo "0"
        return 0
    fi

    local count=0
    local mechanisms
    mechanisms=$(echo "$record" | tr ' ' '\n')

    while IFS= read -r mech; do
        [[ -z "$mech" ]] && continue
        case "$mech" in
            include:*)
                ((count++)) || true
                # Follow the include chain
                local include_domain="${mech#include:}"
                local include_record
                include_record=$(safe_timeout "$timeout" dig +short "$include_domain" TXT 2>/dev/null | grep "v=spf1" | head -1 || true)
                # Remove surrounding quotes
                include_record="${include_record%\"}"
                include_record="${include_record#\"}"
                if [[ -n "$include_record" ]]; then
                    local sub_count
                    sub_count=$(emailsec_count_spf_lookups "$include_record" "$include_domain" "$timeout" $((depth + 1)))
                    count=$((count + sub_count))
                fi
                ;;
            a|a:*|mx|mx:*|ptr|ptr:*|exists:*)
                ((count++)) || true
                ;;
            redirect=*)
                ((count++)) || true
                local redirect_domain="${mech#redirect=}"
                local redirect_record
                redirect_record=$(safe_timeout "$timeout" dig +short "$redirect_domain" TXT 2>/dev/null | grep "v=spf1" | head -1 || true)
                redirect_record="${redirect_record%\"}"
                redirect_record="${redirect_record#\"}"
                if [[ -n "$redirect_record" ]]; then
                    local sub_count
                    sub_count=$(emailsec_count_spf_lookups "$redirect_record" "$redirect_domain" "$timeout" $((depth + 1)))
                    count=$((count + sub_count))
                fi
                ;;
        esac
    done <<< "$mechanisms"

    echo "$count"
}

# Analyze SPF record
# Usage: spf_json=$(emailsec_analyze_spf "$target" "$timeout" "$scan_spf_record")
emailsec_analyze_spf() {
    local target=$1
    local timeout=$2
    local spf_record=${3:-}

    # If no record passed, do our own lookup
    if [[ -z "$spf_record" ]]; then
        local txt_records
        txt_records=$(safe_timeout "$timeout" dig +short "$target" TXT 2>/dev/null || true)
        # Count SPF records
        local spf_count=0
        local spf_line=""
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            # Remove surrounding quotes
            local clean="${line%\"}"
            clean="${clean#\"}"
            if [[ "$clean" == *"v=spf1"* ]]; then
                ((spf_count++)) || true
                spf_line="$clean"
            fi
        done <<< "$txt_records"
        spf_record="$spf_line"
    fi

    # No SPF record found
    if [[ -z "$spf_record" ]]; then
        jq -n '{
            found: false,
            record: "",
            mechanisms: [],
            dns_lookups: 0,
            dns_lookup_limit: 10,
            all_qualifier: "",
            includes: [],
            issues: ["No SPF record found"]
        }'
        return 0
    fi

    # Remove surrounding quotes if present
    spf_record="${spf_record%\"}"
    spf_record="${spf_record#\"}"

    # Parse mechanisms
    local mechanisms='[]'
    local includes='[]'
    local all_qualifier=""
    local issues='[]'

    local tokens
    tokens=$(echo "$spf_record" | tr ' ' '\n')

    while IFS= read -r token; do
        [[ -z "$token" ]] && continue
        [[ "$token" == "v=spf1" ]] && continue

        mechanisms=$(echo "$mechanisms" | jq --arg t "$token" '. += [$t]')

        case "$token" in
            include:*)
                local inc_domain="${token#include:}"
                includes=$(echo "$includes" | jq --arg d "$inc_domain" '. += [$d]')
                ;;
            +all)
                all_qualifier="+all"
                issues=$(echo "$issues" | jq '. += ["CRITICAL: +all allows any server to send email as this domain"]')
                ;;
            "?all")
                all_qualifier="?all"
                issues=$(echo "$issues" | jq '. += ["WARNING: ?all (neutral) does not prevent unauthorized senders"]')
                ;;
            "~all")
                all_qualifier="~all"
                ;;
            "-all")
                all_qualifier="-all"
                ;;
            all)
                all_qualifier="+all"
                issues=$(echo "$issues" | jq '. += ["CRITICAL: bare all (defaults to +all) allows any server to send email"]')
                ;;
        esac
    done <<< "$tokens"

    # Count DNS lookups (with include chain resolution)
    local dns_lookups
    dns_lookups=$(emailsec_count_spf_lookups "$spf_record" "$target" "$timeout" 0)

    if [[ "$dns_lookups" -gt 10 ]]; then
        issues=$(echo "$issues" | jq --argjson n "$dns_lookups" '. += ["WARNING: SPF DNS lookup count (\($n)) exceeds the limit of 10"]')
    fi

    # Check for multiple SPF records (re-check if we did our own lookup)
    local multi_count
    multi_count=$(safe_timeout "$timeout" dig +short "$target" TXT 2>/dev/null | grep -c "v=spf1" || true)
    if [[ "$multi_count" -gt 1 ]]; then
        issues=$(echo "$issues" | jq '. += ["ERROR: Multiple SPF records found - only one is allowed per RFC 7208"]')
    fi

    jq -n \
        --arg record "$spf_record" \
        --argjson mechanisms "$mechanisms" \
        --argjson dns_lookups "$dns_lookups" \
        --arg all_qualifier "$all_qualifier" \
        --argjson includes "$includes" \
        --argjson issues "$issues" \
        '{
            found: true,
            record: $record,
            mechanisms: $mechanisms,
            dns_lookups: $dns_lookups,
            dns_lookup_limit: 10,
            all_qualifier: $all_qualifier,
            includes: $includes,
            issues: $issues
        }'
}

# ─── DMARC Analysis ───

# Analyze DMARC record
# Usage: dmarc_json=$(emailsec_analyze_dmarc "$target" "$timeout" "$scan_dmarc_record")
emailsec_analyze_dmarc() {
    local target=$1
    local timeout=$2
    local dmarc_record=${3:-}

    # If no record passed, do our own lookup
    if [[ -z "$dmarc_record" ]]; then
        dmarc_record=$(safe_timeout "$timeout" dig +short "_dmarc.$target" TXT 2>/dev/null | head -1 || true)
    fi

    # Remove surrounding quotes
    dmarc_record="${dmarc_record%\"}"
    dmarc_record="${dmarc_record#\"}"

    if [[ -z "$dmarc_record" ]] || [[ "$dmarc_record" == "null" ]]; then
        jq -n '{
            found: false,
            record: "",
            policy: "",
            subdomain_policy: "",
            pct: 100,
            rua: "",
            ruf: "",
            adkim: "",
            aspf: "",
            fo: "",
            strength: "missing",
            issues: ["No DMARC record found"]
        }'
        return 0
    fi

    # Parse DMARC tags
    local policy="" subdomain_policy="" pct="100" rua="" ruf="" adkim="" aspf="" fo=""
    local issues='[]'

    # Split on semicolons and parse tags
    local tags
    IFS=';' read -ra tags <<< "$dmarc_record"

    for tag in "${tags[@]}"; do
        # Trim whitespace
        tag=$(echo "$tag" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$tag" ]] && continue

        local key="${tag%%=*}"
        local value="${tag#*=}"
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        case "$key" in
            p) policy="$value" ;;
            sp) subdomain_policy="$value" ;;
            pct) pct="$value" ;;
            rua) rua="$value" ;;
            ruf) ruf="$value" ;;
            adkim) adkim="$value" ;;
            aspf) aspf="$value" ;;
            fo) fo="$value" ;;
        esac
    done

    # Grade policy strength
    local strength="missing"
    case "$policy" in
        reject) strength="strong" ;;
        quarantine) strength="moderate" ;;
        none)
            strength="weak"
            issues=$(echo "$issues" | jq '. += ["DMARC policy is none - emails failing authentication are still delivered"]')
            ;;
    esac

    # Check for missing aggregate report URI
    if [[ -z "$rua" ]]; then
        issues=$(echo "$issues" | jq '. += ["No DMARC aggregate report URI (rua) configured"]')
    fi

    # Check percentage
    if [[ "$pct" != "100" ]]; then
        issues=$(echo "$issues" | jq --arg pct "$pct" '. += ["DMARC policy only applies to \($pct)% of messages"]')
    fi

    # Check subdomain policy
    if [[ -z "$subdomain_policy" ]] && [[ "$policy" != "reject" ]]; then
        issues=$(echo "$issues" | jq '. += ["No subdomain policy (sp) set - inherits main domain policy"]')
    fi

    jq -n \
        --arg record "$dmarc_record" \
        --arg policy "$policy" \
        --arg subdomain_policy "$subdomain_policy" \
        --argjson pct "${pct:-100}" \
        --arg rua "$rua" \
        --arg ruf "$ruf" \
        --arg adkim "$adkim" \
        --arg aspf "$aspf" \
        --arg fo "$fo" \
        --arg strength "$strength" \
        --argjson issues "$issues" \
        '{
            found: true,
            record: $record,
            policy: $policy,
            subdomain_policy: $subdomain_policy,
            pct: $pct,
            rua: $rua,
            ruf: $ruf,
            adkim: $adkim,
            aspf: $aspf,
            fo: $fo,
            strength: $strength,
            issues: $issues
        }'
}

# ─── DKIM Analysis ───

# Analyze DKIM selectors
# Usage: dkim_json=$(emailsec_analyze_dkim "$target" "$timeout" "$scan_dkim_json")
emailsec_analyze_dkim() {
    local target=$1
    local timeout=$2
    local scan_dkim=${3:-}

    local selectors_checked=0
    local selectors_found='[]'
    local issues='[]'

    for selector in "${EMAILSEC_DKIM_SELECTORS[@]}"; do
        ((selectors_checked++)) || true

        local dkim_record=""

        # Try to read from scan data first
        if [[ -n "$scan_dkim" ]] && [[ "$scan_dkim" != "{}" ]] && [[ "$scan_dkim" != "null" ]]; then
            dkim_record=$(echo "$scan_dkim" | jq -r --arg sel "$selector" '.[$sel] // empty' 2>/dev/null || true)
        fi

        # Fall back to our own lookup
        if [[ -z "$dkim_record" ]]; then
            dkim_record=$(safe_timeout "$timeout" dig +short "${selector}._domainkey.$target" TXT 2>/dev/null | head -1 || true)
        fi

        # Remove surrounding quotes
        dkim_record="${dkim_record%\"}"
        dkim_record="${dkim_record#\"}"

        if [[ -z "$dkim_record" ]] || [[ "$dkim_record" == "null" ]]; then
            continue
        fi

        # Parse key type
        local key_type="rsa"
        if [[ "$dkim_record" == *"k=ed25519"* ]]; then
            key_type="ed25519"
        elif [[ "$dkim_record" == *"k=rsa"* ]]; then
            key_type="rsa"
        fi

        # Extract and estimate key length from p= value
        local key_bits=0
        local weak=false
        local p_value=""
        # Extract p= value (base64 public key)
        if [[ "$dkim_record" =~ p=([A-Za-z0-9+/=]+) ]]; then
            p_value="${BASH_REMATCH[1]}"
            if [[ -n "$p_value" ]] && [[ "$p_value" != "=" ]]; then
                # Estimate key size: base64 decode length * 8 gives approximate RSA bits
                local decoded_len
                decoded_len=$(echo -n "$p_value" | base64 -d 2>/dev/null | wc -c | tr -d ' ' || echo "0")
                if [[ "$decoded_len" -gt 0 ]]; then
                    key_bits=$((decoded_len * 8))
                    # Round to nearest standard key size
                    if [[ "$key_bits" -le 640 ]]; then
                        key_bits=512
                    elif [[ "$key_bits" -le 896 ]]; then
                        key_bits=768
                    elif [[ "$key_bits" -le 1280 ]]; then
                        key_bits=1024
                    elif [[ "$key_bits" -le 2560 ]]; then
                        key_bits=2048
                    else
                        key_bits=4096
                    fi
                fi
            fi
        fi

        # Flag weak keys
        if [[ "$key_type" == "rsa" ]] && [[ "$key_bits" -gt 0 ]] && [[ "$key_bits" -lt 2048 ]]; then
            weak=true
            issues=$(echo "$issues" | jq --arg sel "$selector" --argjson bits "$key_bits" \
                '. += ["DKIM selector \($sel) uses \($bits)-bit RSA key (should be 2048+)"]')
        fi

        selectors_found=$(echo "$selectors_found" | jq \
            --arg selector "$selector" \
            --arg record "$dkim_record" \
            --arg key_type "$key_type" \
            --argjson key_bits "$key_bits" \
            --argjson weak "$weak" \
            '. += [{
                selector: $selector,
                record: $record,
                key_type: $key_type,
                key_bits: $key_bits,
                weak: $weak
            }]')
    done

    local found_count
    found_count=$(echo "$selectors_found" | jq 'length')
    if [[ "$found_count" -eq 0 ]]; then
        issues=$(echo "$issues" | jq '. += ["No DKIM selectors found for common selectors"]')
    fi

    jq -n \
        --argjson selectors_checked "$selectors_checked" \
        --argjson selectors_found "$selectors_found" \
        --argjson issues "$issues" \
        '{
            selectors_checked: $selectors_checked,
            selectors_found: $selectors_found,
            issues: $issues
        }'
}

# ─── BIMI Analysis ───

# Analyze BIMI record
# Usage: bimi_json=$(emailsec_analyze_bimi "$target" "$timeout")
emailsec_analyze_bimi() {
    local target=$1
    local timeout=$2

    local bimi_record
    bimi_record=$(safe_timeout "$timeout" dig +short "default._bimi.$target" TXT 2>/dev/null | head -1 || true)

    # Remove surrounding quotes
    bimi_record="${bimi_record%\"}"
    bimi_record="${bimi_record#\"}"

    if [[ -z "$bimi_record" ]] || [[ "$bimi_record" == "null" ]]; then
        jq -n '{
            found: false,
            record: "",
            logo_url: "",
            vmc_url: ""
        }'
        return 0
    fi

    # Parse BIMI tags
    local logo_url="" vmc_url=""

    # Extract l= (logo URL)
    if [[ "$bimi_record" =~ l=([^;[:space:]]+) ]]; then
        logo_url="${BASH_REMATCH[1]}"
    fi

    # Extract a= (VMC/authority URL)
    if [[ "$bimi_record" =~ a=([^;[:space:]]+) ]]; then
        vmc_url="${BASH_REMATCH[1]}"
    fi

    jq -n \
        --arg record "$bimi_record" \
        --arg logo_url "$logo_url" \
        --arg vmc_url "$vmc_url" \
        '{
            found: true,
            record: $record,
            logo_url: $logo_url,
            vmc_url: $vmc_url
        }'
}

# ─── Grading ───

# Calculate overall email security grade
# Usage: grade=$(emailsec_grade "$spf_json" "$dmarc_json" "$dkim_json" "$bimi_json")
emailsec_grade() {
    local spf_json=$1
    local dmarc_json=$2
    local dkim_json=$3
    local bimi_json=$4

    local spf_found dmarc_found dkim_count bimi_found
    spf_found=$(echo "$spf_json" | jq -r '.found')
    dmarc_found=$(echo "$dmarc_json" | jq -r '.found')
    dkim_count=$(echo "$dkim_json" | jq '.selectors_found | length')
    bimi_found=$(echo "$bimi_json" | jq -r '.found')

    local spf_all dmarc_policy dkim_strong
    spf_all=$(echo "$spf_json" | jq -r '.all_qualifier')
    dmarc_policy=$(echo "$dmarc_json" | jq -r '.policy')

    # Check DKIM key strength (all found keys must be 2048+)
    dkim_strong="true"
    if [[ "$dkim_count" -gt 0 ]]; then
        local weak_count
        weak_count=$(echo "$dkim_json" | jq '[.selectors_found[] | select(.weak == true)] | length')
        if [[ "$weak_count" -gt 0 ]]; then
            dkim_strong="false"
        fi
    fi

    # Grade A: Strong SPF (-all) + DMARC reject + DKIM 2048+ + BIMI
    if [[ "$spf_found" == "true" ]] && [[ "$spf_all" == "-all" ]] && \
       [[ "$dmarc_policy" == "reject" ]] && \
       [[ "$dkim_count" -gt 0 ]] && [[ "$dkim_strong" == "true" ]] && \
       [[ "$bimi_found" == "true" ]]; then
        echo "A"
        return 0
    fi

    # Grade B: Good SPF + DMARC quarantine/reject + DKIM found
    if [[ "$spf_found" == "true" ]] && \
       [[ "$dmarc_policy" == "reject" || "$dmarc_policy" == "quarantine" ]] && \
       [[ "$dkim_count" -gt 0 ]]; then
        echo "B"
        return 0
    fi

    # Grade C: SPF present + DMARC present
    if [[ "$spf_found" == "true" ]] && [[ "$dmarc_found" == "true" ]]; then
        echo "C"
        return 0
    fi

    # Grade D: SPF or DMARC present (not both)
    if [[ "$spf_found" == "true" ]] || [[ "$dmarc_found" == "true" ]]; then
        echo "D"
        return 0
    fi

    # Grade F: Neither SPF nor DMARC
    echo "F"
}

# ─── Main Module Functions ───

# Run email security analysis
# Usage: RECOND_SCAN_JSON="$json" emailsec_run "example.com"
# Output: JSON object with email security results
emailsec_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "emailsec" 2>/dev/null || echo "15")

    # Try to extract existing data from scan results
    local scan_spf="" scan_dmarc="" scan_dkim="{}"

    if [[ -n "${RECOND_SCAN_JSON:-}" ]]; then
        # Extract SPF from TXT records
        scan_spf=$(echo "$RECOND_SCAN_JSON" | jq -r \
            '[.results.dns.data.txt[] // empty | select(test("v=spf1"))] | .[0] // empty' 2>/dev/null || true)
        # Remove surrounding quotes
        scan_spf="${scan_spf%\"}"
        scan_spf="${scan_spf#\"}"

        # Extract DMARC
        scan_dmarc=$(echo "$RECOND_SCAN_JSON" | jq -r '.results.dns.data.dmarc // empty' 2>/dev/null || true)

        # Extract DKIM
        scan_dkim=$(echo "$RECOND_SCAN_JSON" | jq -c '.results.dns.data.dkim // {}' 2>/dev/null || echo '{}')
    fi

    # Run analyses
    local spf_json dmarc_json dkim_json bimi_json
    spf_json=$(emailsec_analyze_spf "$target" "$timeout" "$scan_spf")
    dmarc_json=$(emailsec_analyze_dmarc "$target" "$timeout" "$scan_dmarc")
    dkim_json=$(emailsec_analyze_dkim "$target" "$timeout" "$scan_dkim")
    bimi_json=$(emailsec_analyze_bimi "$target" "$timeout")

    # Calculate grade
    local grade
    grade=$(emailsec_grade "$spf_json" "$dmarc_json" "$dkim_json" "$bimi_json")

    # Collect all recommendations
    local recommendations='[]'

    # SPF recommendations
    local spf_found
    spf_found=$(echo "$spf_json" | jq -r '.found')
    if [[ "$spf_found" != "true" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += ["Add an SPF TXT record to prevent email spoofing"]')
    else
        local spf_all
        spf_all=$(echo "$spf_json" | jq -r '.all_qualifier')
        case "$spf_all" in
            "+all") recommendations=$(echo "$recommendations" | jq '. += ["Change SPF +all to -all to reject unauthorized senders"]') ;;
            "?all") recommendations=$(echo "$recommendations" | jq '. += ["Change SPF ?all to -all for stricter enforcement"]') ;;
            "~all") recommendations=$(echo "$recommendations" | jq '. += ["Consider changing SPF ~all to -all for strict enforcement"]') ;;
        esac
    fi

    # DMARC recommendations
    local dmarc_found
    dmarc_found=$(echo "$dmarc_json" | jq -r '.found')
    if [[ "$dmarc_found" != "true" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += ["Add a DMARC record for email authentication policy"]')
    else
        local dmarc_policy
        dmarc_policy=$(echo "$dmarc_json" | jq -r '.policy')
        if [[ "$dmarc_policy" == "none" ]]; then
            recommendations=$(echo "$recommendations" | jq '. += ["Upgrade DMARC policy from none to quarantine or reject"]')
        elif [[ "$dmarc_policy" == "quarantine" ]]; then
            recommendations=$(echo "$recommendations" | jq '. += ["Consider upgrading DMARC policy from quarantine to reject"]')
        fi
    fi

    # DKIM recommendations
    local dkim_count
    dkim_count=$(echo "$dkim_json" | jq '.selectors_found | length')
    if [[ "$dkim_count" -eq 0 ]]; then
        recommendations=$(echo "$recommendations" | jq '. += ["Configure DKIM email signing for your domain"]')
    else
        local weak_count
        weak_count=$(echo "$dkim_json" | jq '[.selectors_found[] | select(.weak == true)] | length')
        if [[ "$weak_count" -gt 0 ]]; then
            recommendations=$(echo "$recommendations" | jq '. += ["Upgrade DKIM keys to 2048-bit RSA or stronger"]')
        fi
    fi

    # BIMI recommendations
    local bimi_found
    bimi_found=$(echo "$bimi_json" | jq -r '.found')
    if [[ "$bimi_found" != "true" ]]; then
        recommendations=$(echo "$recommendations" | jq '. += ["Consider adding a BIMI record for brand visibility in email clients"]')
    fi

    # Build final JSON output
    jq -n \
        --arg grade "$grade" \
        --argjson spf "$spf_json" \
        --argjson dmarc "$dmarc_json" \
        --argjson dkim "$dkim_json" \
        --argjson bimi "$bimi_json" \
        --argjson recommendations "$recommendations" \
        '{
            grade: $grade,
            spf: $spf,
            dmarc: $dmarc,
            dkim: $dkim,
            bimi: $bimi,
            recommendations: $recommendations
        }'
}

# Terminal output for email security results
# Usage: emailsec_print "$json_result" "example.com"
emailsec_print() {
    local json=$1
    local target=${2:-""}

    header "EMAIL SECURITY - $target"

    # Overall grade
    local grade
    grade=$(echo "$json" | jq -r '.grade')

    local grade_color="$RED"
    case "$grade" in
        A) grade_color="$GREEN" ;;
        B) grade_color="$GREEN" ;;
        C) grade_color="$YELLOW" ;;
        D) grade_color="$YELLOW" ;;
    esac

    echo -e "  ${BOLD}Overall Grade: ${grade_color}${grade}${NC}"
    echo ""

    # ─── SPF ───
    subheader "SPF (Sender Policy Framework)"

    local spf_found
    spf_found=$(echo "$json" | jq -r '.spf.found')
    if [[ "$spf_found" == "true" ]]; then
        local spf_record
        spf_record=$(echo "$json" | jq -r '.spf.record')
        success "Record: $spf_record"

        local all_qualifier
        all_qualifier=$(echo "$json" | jq -r '.spf.all_qualifier')
        if [[ -n "$all_qualifier" ]]; then
            case "$all_qualifier" in
                "-all") success "All qualifier: $all_qualifier (hard fail - recommended)" ;;
                "~all") info "All qualifier: $all_qualifier (soft fail)" ;;
                "?all") warn "All qualifier: $all_qualifier (neutral - weak)" ;;
                "+all") error "All qualifier: $all_qualifier (pass all - dangerous)" ;;
            esac
        fi

        local dns_lookups
        dns_lookups=$(echo "$json" | jq -r '.spf.dns_lookups')
        if [[ "$dns_lookups" -gt 10 ]]; then
            warn "DNS lookups: $dns_lookups / 10 (EXCEEDS LIMIT)"
        else
            info "DNS lookups: $dns_lookups / 10"
        fi

        local include_count
        include_count=$(echo "$json" | jq '.spf.includes | length')
        if [[ "$include_count" -gt 0 ]]; then
            info "Includes:"
            echo "$json" | jq -r '.spf.includes[]' | while read -r inc; do
                echo -e "    ${DIM}$inc${NC}"
            done
        fi

        local spf_issue_count
        spf_issue_count=$(echo "$json" | jq '.spf.issues | length')
        if [[ "$spf_issue_count" -gt 0 ]]; then
            echo "$json" | jq -r '.spf.issues[]' | while read -r issue; do
                warn "$issue"
            done
        fi
    else
        error "No SPF record found"
    fi

    # ─── DMARC ───
    subheader "DMARC (Domain-based Message Authentication)"

    local dmarc_found
    dmarc_found=$(echo "$json" | jq -r '.dmarc.found')
    if [[ "$dmarc_found" == "true" ]]; then
        local dmarc_record
        dmarc_record=$(echo "$json" | jq -r '.dmarc.record')
        success "Record: $dmarc_record"

        local dmarc_policy dmarc_strength
        dmarc_policy=$(echo "$json" | jq -r '.dmarc.policy')
        dmarc_strength=$(echo "$json" | jq -r '.dmarc.strength')

        case "$dmarc_strength" in
            strong) success "Policy: $dmarc_policy ($dmarc_strength)" ;;
            moderate) info "Policy: $dmarc_policy ($dmarc_strength)" ;;
            weak) warn "Policy: $dmarc_policy ($dmarc_strength)" ;;
        esac

        local subdomain_policy
        subdomain_policy=$(echo "$json" | jq -r '.dmarc.subdomain_policy // empty')
        [[ -n "$subdomain_policy" ]] && info "Subdomain policy: $subdomain_policy"

        local pct
        pct=$(echo "$json" | jq -r '.dmarc.pct')
        [[ "$pct" != "100" ]] && warn "Percentage: ${pct}%"

        local rua
        rua=$(echo "$json" | jq -r '.dmarc.rua // empty')
        if [[ -n "$rua" ]]; then
            info "Aggregate reports: $rua"
        else
            warn "No aggregate report URI configured"
        fi

        local ruf
        ruf=$(echo "$json" | jq -r '.dmarc.ruf // empty')
        [[ -n "$ruf" ]] && info "Forensic reports: $ruf"

        local adkim
        adkim=$(echo "$json" | jq -r '.dmarc.adkim // empty')
        [[ -n "$adkim" ]] && info "DKIM alignment: $adkim"

        local aspf
        aspf=$(echo "$json" | jq -r '.dmarc.aspf // empty')
        [[ -n "$aspf" ]] && info "SPF alignment: $aspf"

        local dmarc_issue_count
        dmarc_issue_count=$(echo "$json" | jq '.dmarc.issues | length')
        if [[ "$dmarc_issue_count" -gt 0 ]]; then
            echo "$json" | jq -r '.dmarc.issues[]' | while read -r issue; do
                warn "$issue"
            done
        fi
    else
        error "No DMARC record found"
    fi

    # ─── DKIM ───
    subheader "DKIM (DomainKeys Identified Mail)"

    local dkim_checked dkim_found_count
    dkim_checked=$(echo "$json" | jq -r '.dkim.selectors_checked')
    dkim_found_count=$(echo "$json" | jq '.dkim.selectors_found | length')

    info "Checked $dkim_checked selectors, found $dkim_found_count"

    if [[ "$dkim_found_count" -gt 0 ]]; then
        echo "$json" | jq -r '.dkim.selectors_found[] | "\(.selector)|\(.key_type)|\(.key_bits)|\(.weak)"' | while IFS='|' read -r sel kt kb weak; do
            local key_info="${kt}"
            [[ "$kb" -gt 0 ]] && key_info="${key_info} ${kb}-bit"
            if [[ "$weak" == "true" ]]; then
                warn "${sel}._domainkey: ${key_info} (WEAK)"
            else
                success "${sel}._domainkey: ${key_info}"
            fi
        done
    else
        warn "No DKIM selectors found"
    fi

    local dkim_issue_count
    dkim_issue_count=$(echo "$json" | jq '.dkim.issues | length')
    if [[ "$dkim_issue_count" -gt 0 ]]; then
        echo "$json" | jq -r '.dkim.issues[]' | while read -r issue; do
            warn "$issue"
        done
    fi

    # ─── BIMI ───
    subheader "BIMI (Brand Indicators for Message Identification)"

    local bimi_found
    bimi_found=$(echo "$json" | jq -r '.bimi.found')
    if [[ "$bimi_found" == "true" ]]; then
        local bimi_record
        bimi_record=$(echo "$json" | jq -r '.bimi.record')
        success "Record: $bimi_record"

        local logo_url
        logo_url=$(echo "$json" | jq -r '.bimi.logo_url // empty')
        [[ -n "$logo_url" ]] && info "Logo URL: $logo_url"

        local vmc_url
        vmc_url=$(echo "$json" | jq -r '.bimi.vmc_url // empty')
        [[ -n "$vmc_url" ]] && info "VMC URL: $vmc_url"
    else
        info "No BIMI record found"
    fi

    # ─── Recommendations ───
    local rec_count
    rec_count=$(echo "$json" | jq '.recommendations | length')
    if [[ "$rec_count" -gt 0 ]]; then
        subheader "Recommendations"
        echo "$json" | jq -r '.recommendations[]' | while read -r rec; do
            echo -e "  ${YELLOW}→${NC} $rec"
        done
    fi
}

# Check if emailsec module can run
emailsec_check() {
    check_dependencies dig jq
}
