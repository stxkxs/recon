#!/usr/bin/env bash
#
# score.sh - Security posture scoring module for recon
#
# Analyzes scan results and produces a security score:
# - Grade A-F based on weighted checks
# - Individual category scores
# - Actionable recommendations
#
# This module runs AFTER other modules and reads their results.
#

# Prevent multiple sourcing
[[ -n "${_RECON_MODULE_SCORE_LOADED:-}" ]] && return 0
_RECON_MODULE_SCORE_LOADED=1

# Module info
MODULE_SCORE_NAME="score"
MODULE_SCORE_DESCRIPTION="Security posture scoring"

# Score weights (out of 100 total points)
# Transport security: 25 pts
# Email security: 15 pts
# Certificate health: 15 pts
# Security headers: 25 pts
# Infrastructure: 10 pts
# Information exposure: 10 pts

# Calculate score from full scan JSON
# Usage: score_calculate "$full_scan_json"
# Returns: JSON object with scoring breakdown
score_calculate() {
    local scan_json=$1

    local total_score=0
    local max_score=0
    local checks='[]'

    # ─── Transport Security (25 pts) ───

    # HTTPS available (10 pts)
    max_score=$((max_score + 10))
    local https_reachable
    https_reachable=$(echo "$scan_json" | jq -r '.results.http.data.urls[0].reachable // false' 2>/dev/null || echo "false")
    if [[ "$https_reachable" == "true" ]]; then
        total_score=$((total_score + 10))
        checks=$(echo "$checks" | jq '. += [{"category": "transport", "check": "HTTPS available", "pass": true, "points": 10, "max": 10}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "transport", "check": "HTTPS available", "pass": false, "points": 0, "max": 10, "recommendation": "Enable HTTPS on your web server"}]')
    fi

    # HSTS header (10 pts)
    max_score=$((max_score + 10))
    local hsts
    hsts=$(echo "$scan_json" | jq -r '.results.http.data.urls[0].security_headers["strict-transport-security"] // ""' 2>/dev/null || echo "")
    if [[ -n "$hsts" ]]; then
        total_score=$((total_score + 10))
        checks=$(echo "$checks" | jq '. += [{"category": "transport", "check": "HSTS enabled", "pass": true, "points": 10, "max": 10}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "transport", "check": "HSTS enabled", "pass": false, "points": 0, "max": 10, "recommendation": "Add Strict-Transport-Security header"}]')
    fi

    # HTTP redirects to HTTPS (5 pts)
    max_score=$((max_score + 5))
    local status_codes
    status_codes=$(echo "$scan_json" | jq -r '.results.http.data.urls[0].status_codes // [] | join(",")' 2>/dev/null || echo "")
    if [[ "$status_codes" == *"301"* ]] || [[ "$status_codes" == *"302"* ]] || [[ "$status_codes" == *"200"* ]]; then
        total_score=$((total_score + 5))
        checks=$(echo "$checks" | jq '. += [{"category": "transport", "check": "HTTP redirect", "pass": true, "points": 5, "max": 5}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "transport", "check": "HTTP redirect", "pass": false, "points": 0, "max": 5, "recommendation": "Redirect HTTP to HTTPS"}]')
    fi

    # ─── Email Security (15 pts) ───

    # SPF record (5 pts)
    max_score=$((max_score + 5))
    local txt_records
    txt_records=$(echo "$scan_json" | jq -r '.results.dns.data.txt // [] | join(" ")' 2>/dev/null || echo "")
    if [[ "$txt_records" == *"v=spf1"* ]]; then
        total_score=$((total_score + 5))
        checks=$(echo "$checks" | jq '. += [{"category": "email", "check": "SPF record", "pass": true, "points": 5, "max": 5}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "email", "check": "SPF record", "pass": false, "points": 0, "max": 5, "recommendation": "Add SPF TXT record to prevent email spoofing"}]')
    fi

    # DMARC record (5 pts)
    max_score=$((max_score + 5))
    local dmarc
    dmarc=$(echo "$scan_json" | jq -r '.results.dns.data.dmarc // ""' 2>/dev/null || echo "")
    if [[ -n "$dmarc" ]] && [[ "$dmarc" != "null" ]]; then
        total_score=$((total_score + 5))
        checks=$(echo "$checks" | jq '. += [{"category": "email", "check": "DMARC record", "pass": true, "points": 5, "max": 5}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "email", "check": "DMARC record", "pass": false, "points": 0, "max": 5, "recommendation": "Add DMARC record for email authentication"}]')
    fi

    # DKIM record (5 pts)
    max_score=$((max_score + 5))
    local dkim_count
    dkim_count=$(echo "$scan_json" | jq '.results.dns.data.dkim // {} | length' 2>/dev/null || echo "0")
    if [[ "$dkim_count" -gt 0 ]]; then
        total_score=$((total_score + 5))
        checks=$(echo "$checks" | jq '. += [{"category": "email", "check": "DKIM record", "pass": true, "points": 5, "max": 5}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "email", "check": "DKIM record", "pass": false, "points": 0, "max": 5, "recommendation": "Configure DKIM for email signing"}]')
    fi

    # ─── Certificate Health (15 pts) ───

    # Valid SSL certificate (10 pts)
    max_score=$((max_score + 10))
    local ssl_connected
    ssl_connected=$(echo "$scan_json" | jq -r '.results.ssl.data.certificates[0].connected // false' 2>/dev/null || echo "false")
    if [[ "$ssl_connected" == "true" ]]; then
        total_score=$((total_score + 10))
        checks=$(echo "$checks" | jq '. += [{"category": "certificate", "check": "Valid SSL certificate", "pass": true, "points": 10, "max": 10}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "certificate", "check": "Valid SSL certificate", "pass": false, "points": 0, "max": 10, "recommendation": "Install a valid SSL certificate"}]')
    fi

    # CAA record (5 pts)
    max_score=$((max_score + 5))
    local caa_count
    caa_count=$(echo "$scan_json" | jq '.results.dns.data.caa // [] | length' 2>/dev/null || echo "0")
    if [[ "$caa_count" -gt 0 ]]; then
        total_score=$((total_score + 5))
        checks=$(echo "$checks" | jq '. += [{"category": "certificate", "check": "CAA record", "pass": true, "points": 5, "max": 5}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "certificate", "check": "CAA record", "pass": false, "points": 0, "max": 5, "recommendation": "Add CAA DNS record to restrict certificate issuance"}]')
    fi

    # ─── Security Headers (25 pts) ───

    # Content-Security-Policy (8 pts)
    max_score=$((max_score + 8))
    local csp
    csp=$(echo "$scan_json" | jq -r '.results.http.data.urls[0].security_headers["content-security-policy"] // ""' 2>/dev/null || echo "")
    if [[ -n "$csp" ]]; then
        total_score=$((total_score + 8))
        checks=$(echo "$checks" | jq '. += [{"category": "headers", "check": "Content-Security-Policy", "pass": true, "points": 8, "max": 8}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "headers", "check": "Content-Security-Policy", "pass": false, "points": 0, "max": 8, "recommendation": "Add Content-Security-Policy header to prevent XSS"}]')
    fi

    # X-Frame-Options (5 pts)
    max_score=$((max_score + 5))
    local xfo
    xfo=$(echo "$scan_json" | jq -r '.results.http.data.urls[0].security_headers["x-frame-options"] // ""' 2>/dev/null || echo "")
    if [[ -n "$xfo" ]]; then
        total_score=$((total_score + 5))
        checks=$(echo "$checks" | jq '. += [{"category": "headers", "check": "X-Frame-Options", "pass": true, "points": 5, "max": 5}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "headers", "check": "X-Frame-Options", "pass": false, "points": 0, "max": 5, "recommendation": "Add X-Frame-Options header to prevent clickjacking"}]')
    fi

    # X-Content-Type-Options (4 pts)
    max_score=$((max_score + 4))
    local xcto
    xcto=$(echo "$scan_json" | jq -r '.results.http.data.urls[0].security_headers["x-content-type-options"] // ""' 2>/dev/null || echo "")
    if [[ -n "$xcto" ]]; then
        total_score=$((total_score + 4))
        checks=$(echo "$checks" | jq '. += [{"category": "headers", "check": "X-Content-Type-Options", "pass": true, "points": 4, "max": 4}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "headers", "check": "X-Content-Type-Options", "pass": false, "points": 0, "max": 4, "recommendation": "Add X-Content-Type-Options: nosniff header"}]')
    fi

    # Referrer-Policy (4 pts)
    max_score=$((max_score + 4))
    local rp
    rp=$(echo "$scan_json" | jq -r '.results.http.data.urls[0].security_headers["referrer-policy"] // ""' 2>/dev/null || echo "")
    if [[ -n "$rp" ]]; then
        total_score=$((total_score + 4))
        checks=$(echo "$checks" | jq '. += [{"category": "headers", "check": "Referrer-Policy", "pass": true, "points": 4, "max": 4}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "headers", "check": "Referrer-Policy", "pass": false, "points": 0, "max": 4, "recommendation": "Add Referrer-Policy header"}]')
    fi

    # Permissions-Policy (4 pts)
    max_score=$((max_score + 4))
    local pp
    pp=$(echo "$scan_json" | jq -r '.results.http.data.urls[0].security_headers["permissions-policy"] // ""' 2>/dev/null || echo "")
    if [[ -n "$pp" ]]; then
        total_score=$((total_score + 4))
        checks=$(echo "$checks" | jq '. += [{"category": "headers", "check": "Permissions-Policy", "pass": true, "points": 4, "max": 4}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "headers", "check": "Permissions-Policy", "pass": false, "points": 0, "max": 4, "recommendation": "Add Permissions-Policy header to control browser features"}]')
    fi

    # ─── Infrastructure (10 pts) ───

    # Nameservers configured (5 pts)
    max_score=$((max_score + 5))
    local ns_count
    ns_count=$(echo "$scan_json" | jq '.results.dns.data.ns // [] | length' 2>/dev/null || echo "0")
    if [[ "$ns_count" -ge 2 ]]; then
        total_score=$((total_score + 5))
        checks=$(echo "$checks" | jq '. += [{"category": "infrastructure", "check": "Multiple nameservers", "pass": true, "points": 5, "max": 5}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "infrastructure", "check": "Multiple nameservers", "pass": false, "points": 0, "max": 5, "recommendation": "Configure at least 2 nameservers for redundancy"}]')
    fi

    # security.txt present (5 pts)
    max_score=$((max_score + 5))
    local security_txt_status
    security_txt_status=$(echo "$scan_json" | jq -r '[.results.files.data.files[] | select(.path == "/.well-known/security.txt")] | .[0].status // 0' 2>/dev/null || echo "0")
    if [[ "$security_txt_status" == "200" ]]; then
        total_score=$((total_score + 5))
        checks=$(echo "$checks" | jq '. += [{"category": "infrastructure", "check": "security.txt present", "pass": true, "points": 5, "max": 5}]')
    else
        checks=$(echo "$checks" | jq '. += [{"category": "infrastructure", "check": "security.txt present", "pass": false, "points": 0, "max": 5, "recommendation": "Add /.well-known/security.txt for vulnerability disclosure"}]')
    fi

    # ─── Calculate Grade ───
    local percentage=0
    if [[ "$max_score" -gt 0 ]]; then
        percentage=$((total_score * 100 / max_score))
    fi

    local grade="F"
    if [[ "$percentage" -ge 90 ]]; then
        grade="A"
    elif [[ "$percentage" -ge 80 ]]; then
        grade="B"
    elif [[ "$percentage" -ge 70 ]]; then
        grade="C"
    elif [[ "$percentage" -ge 60 ]]; then
        grade="D"
    fi

    # Build final result
    local result
    result=$(jq -n \
        --argjson score "$total_score" \
        --argjson max "$max_score" \
        --argjson percentage "$percentage" \
        --arg grade "$grade" \
        --argjson checks "$checks" \
        '{
            score: $score,
            max_score: $max,
            percentage: $percentage,
            grade: $grade,
            checks: $checks,
            passed: [$checks[] | select(.pass == true)] | length,
            failed: [$checks[] | select(.pass == false)] | length,
            recommendations: [$checks[] | select(.pass == false) | .recommendation // empty]
        }')

    echo "$result"
}

# Run scoring (requires full scan JSON as input via env)
# Usage: RECON_SCAN_JSON="$json" score_run "example.com"
score_run() {
    local target=$1

    if [[ -z "${RECON_SCAN_JSON:-}" ]]; then
        # Return empty score if no scan data available
        jq -n '{score: 0, max_score: 0, percentage: 0, grade: "N/A", checks: [], passed: 0, failed: 0, recommendations: ["Run a full scan first to generate a security score"]}'
        return 0
    fi

    score_calculate "$RECON_SCAN_JSON"
}

# Terminal output for score results
# Usage: score_print "$json_result" "example.com"
score_print() {
    local json=$1
    local target=${2:-""}

    header "SECURITY SCORE - ${target}"

    local grade
    grade=$(echo "$json" | jq -r '.grade')
    local percentage
    percentage=$(echo "$json" | jq -r '.percentage')
    local passed
    passed=$(echo "$json" | jq -r '.passed')
    local failed
    failed=$(echo "$json" | jq -r '.failed')

    # Grade display with color
    local grade_color="$RED"
    case "$grade" in
        A) grade_color="$GREEN" ;;
        B) grade_color="$GREEN" ;;
        C) grade_color="$YELLOW" ;;
        D) grade_color="$YELLOW" ;;
    esac

    echo -e "  ${BOLD}Grade: ${grade_color}${grade}${NC}  ${BOLD}Score: ${percentage}%${NC}  (${passed} passed, ${failed} failed)"
    echo ""

    # Score bar
    local bar_width=40
    local filled=$((bar_width * percentage / 100))
    local empty=$((bar_width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo -e "  ${grade_color}[${bar}]${NC} ${percentage}%"
    echo ""

    # Category breakdown
    local categories=("transport" "email" "certificate" "headers" "infrastructure")
    local category_names=("Transport Security" "Email Security" "Certificate Health" "Security Headers" "Infrastructure")

    for i in "${!categories[@]}"; do
        local cat="${categories[$i]}"
        local cat_name="${category_names[$i]}"
        local cat_score
        cat_score=$(echo "$json" | jq "[.checks[] | select(.category == \"$cat\") | .points] | add // 0")
        local cat_max
        cat_max=$(echo "$json" | jq "[.checks[] | select(.category == \"$cat\") | .max] | add // 0")

        if [[ "$cat_max" -gt 0 ]]; then
            local cat_pct=$((cat_score * 100 / cat_max))
            local cat_color="$RED"
            [[ "$cat_pct" -ge 70 ]] && cat_color="$YELLOW"
            [[ "$cat_pct" -ge 90 ]] && cat_color="$GREEN"
            printf "  ${BOLD}%-22s${NC} ${cat_color}%3d%%${NC} (%d/%d)\n" "$cat_name" "$cat_pct" "$cat_score" "$cat_max"
        fi
    done

    # Detailed checks
    echo ""
    subheader "Checks"
    echo "$json" | jq -r '.checks[] | "\(.pass)|\(.check)|\(.points)|\(.max)"' | while IFS='|' read -r pass check points max; do
        if [[ "$pass" == "true" ]]; then
            printf "  ${GREEN}✓${NC} %-35s %s/%s\n" "$check" "$points" "$max"
        else
            printf "  ${RED}✗${NC} %-35s %s/%s\n" "$check" "$points" "$max"
        fi
    done

    # Recommendations
    local rec_count
    rec_count=$(echo "$json" | jq '.recommendations | length')
    if [[ "$rec_count" -gt 0 ]]; then
        echo ""
        subheader "Recommendations"
        echo "$json" | jq -r '.recommendations[]' | while read -r rec; do
            echo -e "  ${YELLOW}→${NC} $rec"
        done
    fi
}

# Check if score module can run
score_check() {
    # Only needs jq which is already required
    check_dependencies jq
}
