#!/usr/bin/env bash
#
# report.sh - HTML report generation for recon
#
# Generates self-contained HTML reports from JSON scan results.
# No external CSS/JS dependencies - everything is inline.
#

# Prevent multiple sourcing
[[ -n "${_RECON_REPORT_LOADED:-}" ]] && return 0
_RECON_REPORT_LOADED=1

# Generate HTML report from JSON scan results
# Usage: report_generate "$json_result" "output.html"
report_generate() {
    local json=$1
    local output_file=$2

    local target
    target=$(echo "$json" | jq -r '.target')
    local started
    started=$(echo "$json" | jq -r '.meta.started_at // "unknown"')
    local ended
    ended=$(echo "$json" | jq -r '.meta.ended_at // "unknown"')
    local version
    version=$(echo "$json" | jq -r '.meta.version // "unknown"')
    local modules_run
    modules_run=$(echo "$json" | jq -r '.summary.modules_run // 0')
    local modules_success
    modules_success=$(echo "$json" | jq -r '.summary.modules_success // 0')
    local total_errors
    total_errors=$(echo "$json" | jq -r '.summary.total_errors // 0')

    # Start building HTML
    cat > "$output_file" << 'HTML_HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  :root {
    --bg: #0d1117; --surface: #161b22; --border: #30363d;
    --text: #e6edf3; --text-muted: #8b949e; --text-dim: #484f58;
    --green: #3fb950; --red: #f85149; --yellow: #d29922;
    --blue: #58a6ff; --cyan: #39d353; --purple: #bc8cff;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: 'SF Mono', 'Cascadia Code', 'Fira Code', monospace;
    background: var(--bg); color: var(--text);
    line-height: 1.6; padding: 2rem; max-width: 960px; margin: 0 auto;
  }
  .banner {
    color: var(--green); font-size: 0.75rem; white-space: pre;
    text-align: center; margin-bottom: 0.5rem; opacity: 0.8;
  }
  .header { text-align: center; margin-bottom: 2rem; padding-bottom: 1rem; border-bottom: 1px solid var(--border); }
  .header h1 { font-size: 1.5rem; color: var(--blue); margin-bottom: 0.5rem; }
  .header .meta { color: var(--text-muted); font-size: 0.85rem; }
  .summary {
    display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
    gap: 1rem; margin-bottom: 2rem;
  }
  .stat {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 8px; padding: 1rem; text-align: center;
  }
  .stat .value { font-size: 1.8rem; font-weight: bold; }
  .stat .label { color: var(--text-muted); font-size: 0.75rem; text-transform: uppercase; }
  .stat.green .value { color: var(--green); }
  .stat.red .value { color: var(--red); }
  .stat.blue .value { color: var(--blue); }
  .stat.yellow .value { color: var(--yellow); }
  .section {
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 8px; margin-bottom: 1.5rem; overflow: hidden;
  }
  .section-title {
    padding: 0.75rem 1rem; background: rgba(88,166,255,0.1);
    border-bottom: 1px solid var(--border); font-weight: bold;
    color: var(--blue); font-size: 0.9rem;
  }
  .section-body { padding: 1rem; }
  table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
  th { text-align: left; color: var(--text-muted); padding: 0.5rem; border-bottom: 1px solid var(--border); font-size: 0.75rem; text-transform: uppercase; }
  td { padding: 0.5rem; border-bottom: 1px solid var(--border); word-break: break-all; }
  tr:last-child td { border-bottom: none; }
  .tag {
    display: inline-block; padding: 0.15rem 0.5rem; border-radius: 4px;
    font-size: 0.75rem; font-weight: bold;
  }
  .tag-green { background: rgba(63,185,80,0.15); color: var(--green); }
  .tag-red { background: rgba(248,81,73,0.15); color: var(--red); }
  .tag-yellow { background: rgba(210,153,34,0.15); color: var(--yellow); }
  .tag-blue { background: rgba(88,166,255,0.15); color: var(--blue); }
  .pass { color: var(--green); }
  .fail { color: var(--red); }
  .kv { margin-bottom: 0.3rem; }
  .kv .key { color: var(--text-muted); }
  .kv .val { color: var(--text); }
  .list-item { padding: 0.25rem 0; }
  .grade {
    font-size: 3rem; font-weight: bold; display: inline-block;
    width: 60px; height: 60px; line-height: 60px; text-align: center;
    border-radius: 12px; margin-right: 1rem;
  }
  .grade-a { background: rgba(63,185,80,0.2); color: var(--green); }
  .grade-b { background: rgba(63,185,80,0.15); color: var(--green); }
  .grade-c { background: rgba(210,153,34,0.15); color: var(--yellow); }
  .grade-d { background: rgba(210,153,34,0.2); color: var(--yellow); }
  .grade-f { background: rgba(248,81,73,0.15); color: var(--red); }
  .bar-bg { background: var(--border); height: 8px; border-radius: 4px; overflow: hidden; margin: 0.5rem 0; }
  .bar-fill { height: 100%; border-radius: 4px; transition: width 0.3s; }
  .bar-green { background: var(--green); }
  .bar-yellow { background: var(--yellow); }
  .bar-red { background: var(--red); }
  .footer { text-align: center; color: var(--text-dim); font-size: 0.75rem; margin-top: 2rem; padding-top: 1rem; border-top: 1px solid var(--border); }
  pre { background: var(--bg); padding: 0.75rem; border-radius: 4px; overflow-x: auto; font-size: 0.8rem; }
  @media (max-width: 600px) {
    body { padding: 1rem; }
    .summary { grid-template-columns: repeat(2, 1fr); }
  }
</style>
HTML_HEAD

    # Title with target
    cat >> "$output_file" << HTML_TITLE
<title>Recon Report - ${target}</title>
</head>
<body>
<div class="banner">   _ __ ___  ___ ___  _ __
  | '__/ _ \\/ __/ _ \\| '_ \\
  | | |  __/ (_| (_) | | | |
  |_|  \\___|\\___\\___/|_| |_|</div>

<div class="header">
  <h1>${target}</h1>
  <div class="meta">
    Scanned: ${started} &mdash; v${version}
  </div>
</div>

<div class="summary">
  <div class="stat blue"><div class="value">${modules_run}</div><div class="label">Modules</div></div>
  <div class="stat green"><div class="value">${modules_success}</div><div class="label">Success</div></div>
  <div class="stat red"><div class="value">${total_errors}</div><div class="label">Errors</div></div>
HTML_TITLE

    # Add score stat if available
    local score_grade
    score_grade=$(echo "$json" | jq -r '.results.score.data.grade // empty' 2>/dev/null || true)
    if [[ -n "$score_grade" ]] && [[ "$score_grade" != "N/A" ]]; then
        local score_pct
        score_pct=$(echo "$json" | jq -r '.results.score.data.percentage // 0')
        echo "  <div class=\"stat yellow\"><div class=\"value\">${score_grade}</div><div class=\"label\">Grade (${score_pct}%)</div></div>" >> "$output_file"
    fi

    echo "</div>" >> "$output_file"

    # ─── Score Section ───
    if [[ -n "$score_grade" ]] && [[ "$score_grade" != "N/A" ]]; then
        _report_score_section "$json" >> "$output_file"
    fi

    # ─── DNS Section ───
    local has_dns
    has_dns=$(echo "$json" | jq -e '.results.dns' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_dns" == "1" ]]; then
        _report_dns_section "$json" >> "$output_file"
    fi

    # ─── Subdomain Section ───
    local has_subdomain
    has_subdomain=$(echo "$json" | jq -e '.results.subdomain' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_subdomain" == "1" ]]; then
        _report_subdomain_section "$json" >> "$output_file"
    fi

    # ─── SSL Section ───
    local has_ssl
    has_ssl=$(echo "$json" | jq -e '.results.ssl' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_ssl" == "1" ]]; then
        _report_ssl_section "$json" >> "$output_file"
    fi

    # ─── HTTP Section ───
    local has_http
    has_http=$(echo "$json" | jq -e '.results.http' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_http" == "1" ]]; then
        _report_http_section "$json" >> "$output_file"
    fi

    # ─── Ports Section ───
    local has_ports
    has_ports=$(echo "$json" | jq -e '.results.ports' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_ports" == "1" ]]; then
        _report_ports_section "$json" >> "$output_file"
    fi

    # ─── CORS Section ───
    local has_cors
    has_cors=$(echo "$json" | jq -e '.results.cors' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_cors" == "1" ]]; then
        _report_cors_section "$json" >> "$output_file"
    fi

    # ─── WHOIS Section ───
    local has_whois
    has_whois=$(echo "$json" | jq -e '.results.whois' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_whois" == "1" ]]; then
        _report_whois_section "$json" >> "$output_file"
    fi

    # ─── Tech Section ───
    local has_tech
    has_tech=$(echo "$json" | jq -e '.results.tech' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_tech" == "1" ]]; then
        _report_tech_section "$json" >> "$output_file"
    fi

    # ─── CRT Section ───
    local has_crt
    has_crt=$(echo "$json" | jq -e '.results.crt' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_crt" == "1" ]]; then
        _report_crt_section "$json" >> "$output_file"
    fi

    # ─── WAF Section ───
    local has_waf
    has_waf=$(echo "$json" | jq -e '.results.waf' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_waf" == "1" ]]; then
        _report_waf_section "$json" >> "$output_file"
    fi

    # ─── DNSSEC Section ───
    local has_dnssec
    has_dnssec=$(echo "$json" | jq -e '.results.dnssec' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_dnssec" == "1" ]]; then
        _report_dnssec_section "$json" >> "$output_file"
    fi

    # ─── Shodan Section ───
    local has_shodan
    has_shodan=$(echo "$json" | jq -e '.results.shodan' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_shodan" == "1" ]]; then
        _report_shodan_section "$json" >> "$output_file"
    fi

    # ─── VirusTotal Section ───
    local has_virustotal
    has_virustotal=$(echo "$json" | jq -e '.results.virustotal' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_virustotal" == "1" ]]; then
        _report_virustotal_section "$json" >> "$output_file"
    fi

    # ─── Takeover Section ───
    local has_takeover
    has_takeover=$(echo "$json" | jq -e '.results.takeover' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_takeover" == "1" ]]; then
        _report_takeover_section "$json" >> "$output_file"
    fi

    # ─── Wayback Section ───
    local has_wayback
    has_wayback=$(echo "$json" | jq -e '.results.wayback' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_wayback" == "1" ]]; then
        _report_wayback_section "$json" >> "$output_file"
    fi

    # ─── SecurityTrails Section ───
    local has_securitytrails
    has_securitytrails=$(echo "$json" | jq -e '.results.securitytrails' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_securitytrails" == "1" ]]; then
        _report_securitytrails_section "$json" >> "$output_file"
    fi

    # ─── Reverse IP Section ───
    local has_reverseip
    has_reverseip=$(echo "$json" | jq -e '.results.reverseip' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_reverseip" == "1" ]]; then
        _report_reverseip_section "$json" >> "$output_file"
    fi

    # ─── ASN Section ───
    local has_asn
    has_asn=$(echo "$json" | jq -e '.results.asn' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_asn" == "1" ]]; then
        _report_asn_section "$json" >> "$output_file"
    fi

    # ─── AXFR Section ───
    local has_axfr
    has_axfr=$(echo "$json" | jq -e '.results.axfr' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_axfr" == "1" ]]; then
        _report_axfr_section "$json" >> "$output_file"
    fi

    # ─── Methods Section ───
    local has_methods
    has_methods=$(echo "$json" | jq -e '.results.methods' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_methods" == "1" ]]; then
        _report_methods_section "$json" >> "$output_file"
    fi

    # ─── Dirs Section ───
    local has_dirs
    has_dirs=$(echo "$json" | jq -e '.results.dirs' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_dirs" == "1" ]]; then
        _report_dirs_section "$json" >> "$output_file"
    fi

    # ─── JS Analysis Section ───
    local has_jsanalysis
    has_jsanalysis=$(echo "$json" | jq -e '.results.jsanalysis' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_jsanalysis" == "1" ]]; then
        _report_jsanalysis_section "$json" >> "$output_file"
    fi

    # ─── Favicon Section ───
    local has_favicon
    has_favicon=$(echo "$json" | jq -e '.results.favicon' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_favicon" == "1" ]]; then
        _report_favicon_section "$json" >> "$output_file"
    fi

    # ─── Email Security Section ───
    local has_emailsec
    has_emailsec=$(echo "$json" | jq -e '.results.emailsec' >/dev/null 2>&1 && echo "1" || echo "0")
    if [[ "$has_emailsec" == "1" ]]; then
        _report_emailsec_section "$json" >> "$output_file"
    fi

    # ─── Footer ───
    cat >> "$output_file" << HTML_FOOTER
<div class="footer">
  Generated by recon v${version} &mdash; ${ended}
</div>
</body>
</html>
HTML_FOOTER

    echo "$output_file"
}

# ─── Section generators ───

_report_score_section() {
    local json=$1
    local grade
    grade=$(echo "$json" | jq -r '.results.score.data.grade')
    local pct
    pct=$(echo "$json" | jq -r '.results.score.data.percentage')
    local grade_class="grade-f"
    case "$grade" in
        A) grade_class="grade-a" ;; B) grade_class="grade-b" ;;
        C) grade_class="grade-c" ;; D) grade_class="grade-d" ;;
    esac
    local bar_class="bar-red"
    [[ "$pct" -ge 60 ]] && bar_class="bar-yellow"
    [[ "$pct" -ge 80 ]] && bar_class="bar-green"

    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Security Score</div>"
    echo "  <div class=\"section-body\">"
    echo "    <div style=\"display:flex;align-items:center;margin-bottom:1rem\">"
    echo "      <div class=\"grade ${grade_class}\">${grade}</div>"
    echo "      <div><strong>${pct}%</strong> overall score"
    echo "        <div class=\"bar-bg\"><div class=\"bar-fill ${bar_class}\" style=\"width:${pct}%\"></div></div>"
    echo "      </div>"
    echo "    </div>"
    echo "    <table><tr><th>Check</th><th>Result</th><th>Points</th></tr>"
    echo "$json" | jq -r '.results.score.data.checks[] | "<tr><td>\(.check)</td><td>\(if .pass then "<span class=\"pass\">PASS</span>" else "<span class=\"fail\">FAIL</span>" end)</td><td>\(.points)/\(.max)</td></tr>"'
    echo "    </table>"

    local rec_count
    rec_count=$(echo "$json" | jq '.results.score.data.recommendations | length')
    if [[ "$rec_count" -gt 0 ]]; then
        echo "    <div style=\"margin-top:1rem\">"
        echo "$json" | jq -r '.results.score.data.recommendations[] | "      <div class=\"list-item\"><span class=\"tag tag-yellow\">FIX</span> \(.)</div>"'
        echo "    </div>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_dns_section() {
    local json=$1
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">DNS Records</div>"
    echo "  <div class=\"section-body\">"
    echo "    <table><tr><th>Type</th><th>Records</th></tr>"

    # A records
    local a_records
    a_records=$(echo "$json" | jq -r '.results.dns.data.a // [] | join(", ")')
    [[ -n "$a_records" ]] && echo "      <tr><td><span class=\"tag tag-blue\">A</span></td><td>${a_records}</td></tr>"

    # AAAA
    local aaaa
    aaaa=$(echo "$json" | jq -r '.results.dns.data.aaaa // [] | join(", ")')
    [[ -n "$aaaa" ]] && echo "      <tr><td><span class=\"tag tag-blue\">AAAA</span></td><td>${aaaa}</td></tr>"

    # NS
    local ns
    ns=$(echo "$json" | jq -r '.results.dns.data.ns // [] | join(", ")')
    [[ -n "$ns" ]] && echo "      <tr><td><span class=\"tag tag-green\">NS</span></td><td>${ns}</td></tr>"

    # MX
    local mx
    mx=$(echo "$json" | jq -r '[.results.dns.data.mx // [] | .[] | "\(.priority) \(.host)"] | join(", ")')
    [[ -n "$mx" ]] && echo "      <tr><td><span class=\"tag tag-yellow\">MX</span></td><td>${mx}</td></tr>"

    # DMARC
    local dmarc
    dmarc=$(echo "$json" | jq -r '.results.dns.data.dmarc // ""')
    [[ -n "$dmarc" ]] && [[ "$dmarc" != "null" ]] && echo "      <tr><td><span class=\"tag tag-green\">DMARC</span></td><td>${dmarc}</td></tr>"

    echo "    </table>"
    echo "  </div>"
    echo "</div>"
}

_report_subdomain_section() {
    local json=$1
    local found_count
    found_count=$(echo "$json" | jq '.results.subdomain.data.found // [] | length')
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Subdomains (${found_count} found)</div>"
    echo "  <div class=\"section-body\">"
    if [[ "$found_count" -gt 0 ]]; then
        echo "    <table><tr><th>Subdomain</th><th>IP</th><th>CNAME</th></tr>"
        echo "$json" | jq -r '.results.subdomain.data.found[] | "<tr><td>\(.fqdn)</td><td>\(.ip)</td><td>\(.cname // "-")</td></tr>"'
        echo "    </table>"
    else
        echo "    <p style=\"color:var(--text-muted)\">No subdomains discovered</p>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_ssl_section() {
    local json=$1
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">SSL/TLS Certificates</div>"
    echo "  <div class=\"section-body\">"
    echo "    <table><tr><th>Host</th><th>Subject</th><th>Issuer</th><th>Valid Until</th><th>TLS</th></tr>"
    echo "$json" | jq -r '.results.ssl.data.certificates[] | select(.connected == true) | "<tr><td>\(.host)</td><td>\(.subject // "-")</td><td>\(.issuer // "-")</td><td>\(.not_after // "-")</td><td><span class=\"tag tag-green\">\(.tls_version // "-")</span></td></tr>"'
    echo "    </table>"
    echo "  </div>"
    echo "</div>"
}

_report_http_section() {
    local json=$1
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">HTTP Headers</div>"
    echo "  <div class=\"section-body\">"
    echo "$json" | jq -r '.results.http.data.urls[] | select(.reachable == true)' | jq -r '
        "<div style=\"margin-bottom:1rem\"><strong>\(.url)</strong> <span class=\"tag tag-blue\">\(.status_codes | join(" → "))</span>" +
        (if .server then " <span class=\"tag tag-green\">\(.server)</span>" else "" end) +
        "<table style=\"margin-top:0.5rem\"><tr><th>Security Header</th><th>Value</th></tr>" +
        (.security_headers | to_entries | map("<tr><td>\(.key)</td><td>\(.value[:80])</td></tr>") | join("")) +
        "</table></div>"
    ' 2>/dev/null || echo "<p style=\"color:var(--text-muted)\">No HTTP data</p>"
    echo "  </div>"
    echo "</div>"
}

_report_ports_section() {
    local json=$1
    local open_count
    open_count=$(echo "$json" | jq '.results.ports.data.open // [] | length')
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Open Ports (${open_count})</div>"
    echo "  <div class=\"section-body\">"
    if [[ "$open_count" -gt 0 ]]; then
        echo "    <table><tr><th>Port</th><th>Service</th><th>Banner</th></tr>"
        echo "$json" | jq -r '.results.ports.data.open[] | "<tr><td><span class=\"tag tag-green\">\(.port)</span></td><td>\(.service)</td><td>\(.banner // "-")</td></tr>"'
        echo "    </table>"
    else
        echo "    <p style=\"color:var(--text-muted)\">No open ports detected</p>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_cors_section() {
    local json=$1
    local risk
    risk=$(echo "$json" | jq -r '.results.cors.data.risk // "none"')
    local risk_class="tag-green"
    case "$risk" in
        medium) risk_class="tag-yellow" ;;
        high|critical) risk_class="tag-red" ;;
    esac
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">CORS Analysis <span class=\"tag ${risk_class}\">${risk^^}</span></div>"
    echo "  <div class=\"section-body\">"
    local findings_count
    findings_count=$(echo "$json" | jq '.results.cors.data.findings // [] | length')
    if [[ "$findings_count" -gt 0 ]]; then
        echo "$json" | jq -r '.results.cors.data.findings[] | "<div class=\"list-item\"><span class=\"tag tag-\(if .severity == "high" or .severity == "critical" then "red" elif .severity == "medium" then "yellow" else "green" end)\">\(.severity | ascii_upcase)</span> \(.detail)</div>"'
    else
        echo "    <p class=\"pass\">No CORS misconfigurations detected</p>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_whois_section() {
    local json=$1
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">WHOIS Information</div>"
    echo "  <div class=\"section-body\">"
    echo "$json" | jq -r '.results.whois.data.lookups[] | select(.found == true) | "<div style=\"margin-bottom:0.5rem\"><strong>IP: \(.ip)</strong></div>" + (.data | to_entries | map("<div class=\"kv\"><span class=\"key\">\(.key):</span> <span class=\"val\">\(.value)</span></div>") | join(""))' 2>/dev/null || echo "<p style=\"color:var(--text-muted)\">No WHOIS data</p>"
    echo "  </div>"
    echo "</div>"
}

_report_tech_section() {
    local json=$1
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Technology Stack</div>"
    echo "  <div class=\"section-body\">"

    local frontend
    frontend=$(echo "$json" | jq -r '.results.tech.data.frontend // [] | join(", ")')
    local analytics
    analytics=$(echo "$json" | jq -r '.results.tech.data.analytics // [] | join(", ")')
    local infra
    infra=$(echo "$json" | jq -r '.results.tech.data.infrastructure // [] | join(", ")')

    [[ -n "$frontend" ]] && echo "    <div class=\"kv\"><span class=\"key\">Frontend:</span> <span class=\"val\">${frontend}</span></div>"
    [[ -n "$analytics" ]] && echo "    <div class=\"kv\"><span class=\"key\">Analytics:</span> <span class=\"val\">${analytics}</span></div>"
    [[ -n "$infra" ]] && echo "    <div class=\"kv\"><span class=\"key\">Infrastructure:</span> <span class=\"val\">${infra}</span></div>"

    if [[ -z "$frontend" ]] && [[ -z "$analytics" ]] && [[ -z "$infra" ]]; then
        echo "    <p style=\"color:var(--text-muted)\">No technologies detected</p>"
    fi

    echo "  </div>"
    echo "</div>"
}

_report_crt_section() {
    local json=$1
    local sub_count
    sub_count=$(echo "$json" | jq '.results.crt.data.subdomains // [] | length')
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Certificate Transparency (${sub_count} subdomains)</div>"
    echo "  <div class=\"section-body\">"
    if [[ "$sub_count" -gt 0 ]]; then
        echo "    <table><tr><th>#</th><th>Subdomain</th></tr>"
        echo "$json" | jq -r '.results.crt.data.subdomains // [] | to_entries[] | "<tr><td>\(.key + 1)</td><td>\(.value)</td></tr>"'
        echo "    </table>"
    else
        echo "    <p style=\"color:var(--text-muted)\">No subdomains found in CT logs</p>"
    fi
    echo "    <div class=\"kv\" style=\"margin-top:0.5rem\"><span class=\"key\">Source:</span> <span class=\"val\">crt.sh</span></div>"
    echo "  </div>"
    echo "</div>"
}

_report_waf_section() {
    local json=$1
    local detected
    detected=$(echo "$json" | jq -r '.results.waf.data.detected // false')
    local provider
    provider=$(echo "$json" | jq -r '.results.waf.data.provider // "none"')
    local confidence
    confidence=$(echo "$json" | jq -r '.results.waf.data.confidence // "none"')
    local conf_class="tag-green"
    [[ "$confidence" == "medium" ]] && conf_class="tag-yellow"
    [[ "$confidence" == "high" ]] && conf_class="tag-blue"
    echo "<div class=\"section\">"
    if [[ "$detected" == "true" ]]; then
        echo "  <div class=\"section-title\">WAF/CDN Detection <span class=\"tag ${conf_class}\">${provider^^}</span></div>"
    else
        echo "  <div class=\"section-title\">WAF/CDN Detection <span class=\"tag tag-green\">NONE</span></div>"
    fi
    echo "  <div class=\"section-body\">"
    if [[ "$detected" == "true" ]]; then
        echo "    <div class=\"kv\"><span class=\"key\">Provider:</span> <span class=\"val\">${provider}</span></div>"
        echo "    <div class=\"kv\"><span class=\"key\">Confidence:</span> <span class=\"val\">${confidence}</span></div>"
        local ind_count
        ind_count=$(echo "$json" | jq '.results.waf.data.indicators // [] | length')
        if [[ "$ind_count" -gt 0 ]]; then
            echo "    <table><tr><th>Header</th><th>Value</th></tr>"
            echo "$json" | jq -r '.results.waf.data.indicators[] | "<tr><td>\(.header)</td><td>\(.value[:80])</td></tr>"'
            echo "    </table>"
        fi
    else
        echo "    <p class=\"pass\">No WAF/CDN detected</p>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_dnssec_section() {
    local json=$1
    local enabled
    enabled=$(echo "$json" | jq -r '.results.dnssec.data.enabled // false')
    local valid
    valid=$(echo "$json" | jq -r '.results.dnssec.data.valid // false')
    local status_class="tag-red"
    [[ "$enabled" == "true" ]] && status_class="tag-yellow"
    [[ "$valid" == "true" ]] && status_class="tag-green"
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">DNSSEC Validation <span class=\"tag ${status_class}\">"
    if [[ "$valid" == "true" ]]; then echo "VALID"; elif [[ "$enabled" == "true" ]]; then echo "PARTIAL"; else echo "DISABLED"; fi
    echo "</span></div>"
    echo "  <div class=\"section-body\">"
    echo "    <table><tr><th>Check</th><th>Status</th></tr>"
    for field in dnskey ds rrsig nsec3 ad_flag; do
        local val
        val=$(echo "$json" | jq -r ".results.dnssec.data.${field} // false")
        local label="${field^^}"
        [[ "$field" == "ad_flag" ]] && label="AD Flag"
        [[ "$field" == "dnskey" ]] && label="DNSKEY"
        [[ "$field" == "ds" ]] && label="DS Record"
        [[ "$field" == "rrsig" ]] && label="RRSIG"
        [[ "$field" == "nsec3" ]] && label="NSEC3"
        if [[ "$val" == "true" ]]; then
            echo "      <tr><td>${label}</td><td><span class=\"pass\">PRESENT</span></td></tr>"
        else
            echo "      <tr><td>${label}</td><td><span class=\"fail\">MISSING</span></td></tr>"
        fi
    done
    local algo
    algo=$(echo "$json" | jq -r '.results.dnssec.data.algorithm // "N/A"')
    echo "      <tr><td>Algorithm</td><td>${algo}</td></tr>"
    echo "    </table>"
    echo "  </div>"
    echo "</div>"
}

_report_shodan_section() {
    local json=$1
    local has_error
    has_error=$(echo "$json" | jq -r '.results.shodan.data.error // empty')
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Shodan Intelligence</div>"
    echo "  <div class=\"section-body\">"
    if [[ -n "$has_error" ]]; then
        echo "    <p style=\"color:var(--text-muted)\">Shodan data unavailable (${has_error})</p>"
    else
        local ip org isp country
        ip=$(echo "$json" | jq -r '.results.shodan.data.ip // "N/A"')
        org=$(echo "$json" | jq -r '.results.shodan.data.org // "N/A"')
        isp=$(echo "$json" | jq -r '.results.shodan.data.isp // "N/A"')
        country=$(echo "$json" | jq -r '.results.shodan.data.country // "N/A"')
        echo "    <div class=\"kv\"><span class=\"key\">IP:</span> <span class=\"val\">${ip}</span></div>"
        echo "    <div class=\"kv\"><span class=\"key\">Organization:</span> <span class=\"val\">${org}</span></div>"
        echo "    <div class=\"kv\"><span class=\"key\">ISP:</span> <span class=\"val\">${isp}</span></div>"
        echo "    <div class=\"kv\"><span class=\"key\">Country:</span> <span class=\"val\">${country}</span></div>"
        local port_count
        port_count=$(echo "$json" | jq '.results.shodan.data.ports // [] | length')
        if [[ "$port_count" -gt 0 ]]; then
            echo "    <div style=\"margin-top:0.5rem\"><strong>Open Ports:</strong></div>"
            echo "    <div>"
            echo "$json" | jq -r '.results.shodan.data.ports // [] | .[] | "<span class=\"tag tag-blue\">\(.)</span> "' | tr -d '\n'
            echo "    </div>"
        fi
        local vuln_count
        vuln_count=$(echo "$json" | jq '.results.shodan.data.vulns // [] | length')
        if [[ "$vuln_count" -gt 0 ]]; then
            echo "    <div style=\"margin-top:0.5rem\"><strong>Vulnerabilities:</strong></div>"
            echo "$json" | jq -r '.results.shodan.data.vulns[] | "<div class=\"list-item\"><span class=\"tag tag-red\">\(.)</span></div>"'
        fi
    fi
    echo "  </div>"
    echo "</div>"
}

_report_virustotal_section() {
    local json=$1
    local has_error
    has_error=$(echo "$json" | jq -r '.results.virustotal.data.error // empty')
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">VirusTotal Reputation</div>"
    echo "  <div class=\"section-body\">"
    if [[ -n "$has_error" ]]; then
        echo "    <p style=\"color:var(--text-muted)\">VirusTotal data unavailable (${has_error})</p>"
    else
        local reputation
        reputation=$(echo "$json" | jq -r '.results.virustotal.data.reputation // 0')
        local malicious suspicious harmless undetected
        malicious=$(echo "$json" | jq -r '.results.virustotal.data.detections.malicious // 0')
        suspicious=$(echo "$json" | jq -r '.results.virustotal.data.detections.suspicious // 0')
        harmless=$(echo "$json" | jq -r '.results.virustotal.data.detections.harmless // 0')
        undetected=$(echo "$json" | jq -r '.results.virustotal.data.detections.undetected // 0')
        local rep_class="tag-green"
        [[ "$malicious" -gt 0 ]] && rep_class="tag-red"
        [[ "$suspicious" -gt 0 ]] && [[ "$malicious" -eq 0 ]] && rep_class="tag-yellow"
        echo "    <div class=\"kv\"><span class=\"key\">Reputation:</span> <span class=\"val tag ${rep_class}\">${reputation}</span></div>"
        echo "    <table><tr><th>Category</th><th>Count</th></tr>"
        echo "      <tr><td><span class=\"tag tag-red\">Malicious</span></td><td>${malicious}</td></tr>"
        echo "      <tr><td><span class=\"tag tag-yellow\">Suspicious</span></td><td>${suspicious}</td></tr>"
        echo "      <tr><td><span class=\"tag tag-green\">Harmless</span></td><td>${harmless}</td></tr>"
        echo "      <tr><td><span class=\"tag tag-blue\">Undetected</span></td><td>${undetected}</td></tr>"
        echo "    </table>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_takeover_section() {
    local json=$1
    local vuln_count
    vuln_count=$(echo "$json" | jq '.results.takeover.data.vulnerable // [] | length')
    local checked
    checked=$(echo "$json" | jq -r '.results.takeover.data.checked // 0')
    local risk_class="tag-green"
    [[ "$vuln_count" -gt 0 ]] && risk_class="tag-red"
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Subdomain Takeover <span class=\"tag ${risk_class}\">${vuln_count} VULNERABLE</span></div>"
    echo "  <div class=\"section-body\">"
    if [[ "$vuln_count" -gt 0 ]]; then
        echo "    <table><tr><th>Subdomain</th><th>CNAME</th><th>Service</th><th>Status</th></tr>"
        echo "$json" | jq -r '.results.takeover.data.vulnerable[] | "<tr><td>\(.subdomain)</td><td>\(.cname)</td><td><span class=\"tag tag-yellow\">\(.service)</span></td><td><span class=\"tag tag-red\">\(.status)</span></td></tr>"'
        echo "    </table>"
    else
        echo "    <p class=\"pass\">No vulnerable subdomains detected (${checked} checked)</p>"
    fi
    local findings_count
    findings_count=$(echo "$json" | jq '.results.takeover.data.findings // [] | length')
    if [[ "$findings_count" -gt 0 ]]; then
        echo "    <div style=\"margin-top:0.5rem\"><strong>Additional Findings:</strong></div>"
        echo "$json" | jq -r '.results.takeover.data.findings[] | "<div class=\"list-item\"><span class=\"tag tag-yellow\">\(.service)</span> \(.subdomain) → \(.cname)</div>"'
    fi
    echo "  </div>"
    echo "</div>"
}

_report_wayback_section() {
    local json=$1
    local total
    total=$(echo "$json" | jq -r '.results.wayback.data.total // 0')
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Wayback Machine (${total} URLs)</div>"
    echo "  <div class=\"section-body\">"
    if [[ "$total" -gt 0 ]]; then
        local ext_count
        ext_count=$(echo "$json" | jq '.results.wayback.data.interesting_extensions // {} | to_entries | length')
        if [[ "$ext_count" -gt 0 ]]; then
            echo "    <div style=\"margin-bottom:0.5rem\"><strong>Interesting Extensions:</strong></div>"
            echo "    <div>"
            echo "$json" | jq -r '.results.wayback.data.interesting_extensions // {} | to_entries[] | "<span class=\"tag tag-yellow\">\(.key) (\(.value))</span> "' | tr -d '\n'
            echo "    </div>"
        fi
        local group_count
        group_count=$(echo "$json" | jq '.results.wayback.data.path_groups // {} | to_entries | length')
        if [[ "$group_count" -gt 0 ]]; then
            echo "    <div style=\"margin-top:0.5rem\"><strong>Top Path Groups:</strong></div>"
            echo "    <table><tr><th>Path</th><th>Count</th></tr>"
            echo "$json" | jq -r '.results.wayback.data.path_groups // {} | to_entries | sort_by(-.value) | .[:10][] | "<tr><td>\(.key)</td><td>\(.value)</td></tr>"'
            echo "    </table>"
        fi
    else
        echo "    <p style=\"color:var(--text-muted)\">No archived URLs found</p>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_securitytrails_section() {
    local json=$1
    local has_error
    has_error=$(echo "$json" | jq -r '.results.securitytrails.data.error // empty')
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">SecurityTrails</div>"
    echo "  <div class=\"section-body\">"
    if [[ -n "$has_error" ]]; then
        echo "    <p style=\"color:var(--text-muted)\">SecurityTrails data unavailable (${has_error})</p>"
    else
        local sub_count
        sub_count=$(echo "$json" | jq -r '.results.securitytrails.data.subdomains.total // 0')
        local assoc_count
        assoc_count=$(echo "$json" | jq -r '.results.securitytrails.data.associated_domains.total // 0')
        echo "    <div class=\"kv\"><span class=\"key\">Subdomains:</span> <span class=\"val\">${sub_count}</span></div>"
        echo "    <div class=\"kv\"><span class=\"key\">Associated Domains:</span> <span class=\"val\">${assoc_count}</span></div>"
        if [[ "$sub_count" -gt 0 ]]; then
            echo "    <div style=\"margin-top:0.5rem\"><strong>Subdomains:</strong></div>"
            echo "    <div>"
            echo "$json" | jq -r '.results.securitytrails.data.subdomains.list // [] | .[:20][] | "<span class=\"tag tag-blue\">\(.)</span> "' | tr -d '\n'
            echo "    </div>"
        fi
    fi
    echo "  </div>"
    echo "</div>"
}

_report_reverseip_section() {
    local json=$1
    local has_error
    has_error=$(echo "$json" | jq -r '.results.reverseip.data.error // empty')
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Reverse IP Lookup</div>"
    echo "  <div class=\"section-body\">"
    if [[ -n "$has_error" ]]; then
        echo "    <p style=\"color:var(--text-muted)\">Reverse IP data unavailable (${has_error})</p>"
    else
        local ip
        ip=$(echo "$json" | jq -r '.results.reverseip.data.ip // "N/A"')
        local total
        total=$(echo "$json" | jq -r '.results.reverseip.data.total // 0')
        echo "    <div class=\"kv\"><span class=\"key\">IP:</span> <span class=\"val\">${ip}</span></div>"
        echo "    <div class=\"kv\"><span class=\"key\">Domains on IP:</span> <span class=\"val\">${total}</span></div>"
        if [[ "$total" -gt 0 ]]; then
            echo "    <table><tr><th>#</th><th>Domain</th></tr>"
            echo "$json" | jq -r '.results.reverseip.data.domains // [] | to_entries | .[:30][] | "<tr><td>\(.key + 1)</td><td>\(.value)</td></tr>"'
            echo "    </table>"
        fi
    fi
    echo "  </div>"
    echo "</div>"
}

_report_asn_section() {
    local json=$1
    local has_error
    has_error=$(echo "$json" | jq -r '.results.asn.data.error // empty')
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">ASN Expansion</div>"
    echo "  <div class=\"section-body\">"
    if [[ -n "$has_error" ]]; then
        echo "    <p style=\"color:var(--text-muted)\">ASN data unavailable (${has_error})</p>"
    else
        local asn asn_name asn_country total_prefixes total_ips
        asn=$(echo "$json" | jq -r '.results.asn.data.asn // "N/A"')
        asn_name=$(echo "$json" | jq -r '.results.asn.data.asn_name // "N/A"')
        asn_country=$(echo "$json" | jq -r '.results.asn.data.asn_country // "N/A"')
        total_prefixes=$(echo "$json" | jq -r '.results.asn.data.total_prefixes // 0')
        total_ips=$(echo "$json" | jq -r '.results.asn.data.total_ips_approx // 0')
        echo "    <div class=\"kv\"><span class=\"key\">ASN:</span> <span class=\"val\">${asn}</span></div>"
        echo "    <div class=\"kv\"><span class=\"key\">Name:</span> <span class=\"val\">${asn_name}</span></div>"
        echo "    <div class=\"kv\"><span class=\"key\">Country:</span> <span class=\"val\">${asn_country}</span></div>"
        echo "    <div class=\"kv\"><span class=\"key\">Prefixes:</span> <span class=\"val\">${total_prefixes}</span></div>"
        echo "    <div class=\"kv\"><span class=\"key\">Approx IPs:</span> <span class=\"val\">${total_ips}</span></div>"
        if [[ "$total_prefixes" -gt 0 ]]; then
            echo "    <table><tr><th>Prefix</th><th>Description</th></tr>"
            echo "$json" | jq -r '.results.asn.data.prefixes // [] | .[:20][] | "<tr><td><span class=\"tag tag-blue\">\(.prefix)</span></td><td>\(.description // "-")</td></tr>"'
            echo "    </table>"
        fi
    fi
    echo "  </div>"
    echo "</div>"
}

_report_axfr_section() {
    local json=$1
    local vulnerable
    vulnerable=$(echo "$json" | jq -r '.results.axfr.data.vulnerable // false')
    local ns_tested
    ns_tested=$(echo "$json" | jq -r '.results.axfr.data.nameservers_tested // 0')
    local vuln_class="tag-green"
    [[ "$vulnerable" == "true" ]] && vuln_class="tag-red"
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">DNS Zone Transfer <span class=\"tag ${vuln_class}\">"
    if [[ "$vulnerable" == "true" ]]; then echo "VULNERABLE"; else echo "SECURE"; fi
    echo "</span></div>"
    echo "  <div class=\"section-body\">"
    echo "    <div class=\"kv\"><span class=\"key\">Nameservers Tested:</span> <span class=\"val\">${ns_tested}</span></div>"
    echo "    <table><tr><th>Nameserver</th><th>Result</th><th>Records</th></tr>"
    echo "$json" | jq -r '.results.axfr.data.transfers // [] | .[] | "<tr><td>\(.nameserver)</td><td>\(if .success then "<span class=\"fail\">TRANSFER ALLOWED</span>" else "<span class=\"pass\">REFUSED</span>" end)</td><td>\(.records_count // 0)</td></tr>"'
    echo "    </table>"
    echo "  </div>"
    echo "</div>"
}

_report_methods_section() {
    local json=$1
    local risk
    risk=$(echo "$json" | jq -r '.results.methods.data.risk // "none"')
    local total_dangerous
    total_dangerous=$(echo "$json" | jq -r '.results.methods.data.total_dangerous // 0')
    local risk_class="tag-green"
    case "$risk" in
        medium) risk_class="tag-yellow" ;;
        high|critical) risk_class="tag-red" ;;
    esac
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">HTTP Methods <span class=\"tag ${risk_class}\">${risk^^}</span></div>"
    echo "  <div class=\"section-body\">"
    if [[ "$total_dangerous" -gt 0 ]]; then
        echo "    <table><tr><th>Path</th><th>Dangerous Methods</th></tr>"
        echo "$json" | jq -r '.results.methods.data.findings // [] | .[] | select(.dangerous_methods | length > 0) | "<tr><td>\(.path)</td><td>\(.dangerous_methods | join(", "))</td></tr>"'
        echo "    </table>"
    else
        echo "    <p class=\"pass\">No dangerous HTTP methods detected</p>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_dirs_section() {
    local json=$1
    local risk
    risk=$(echo "$json" | jq -r '.results.dirs.data.risk // "none"')
    local found_count
    found_count=$(echo "$json" | jq '.results.dirs.data.found // [] | length')
    local total_checked
    total_checked=$(echo "$json" | jq -r '.results.dirs.data.total_checked // 0')
    local risk_class="tag-green"
    case "$risk" in
        low) risk_class="tag-blue" ;;
        medium) risk_class="tag-yellow" ;;
        high|critical) risk_class="tag-red" ;;
    esac
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Directory Discovery (${found_count}/${total_checked}) <span class=\"tag ${risk_class}\">${risk^^}</span></div>"
    echo "  <div class=\"section-body\">"
    if [[ "$found_count" -gt 0 ]]; then
        echo "    <table><tr><th>Path</th><th>Status</th><th>Category</th><th>Severity</th></tr>"
        echo "$json" | jq -r '.results.dirs.data.found // [] | sort_by(if .severity == "critical" then 0 elif .severity == "high" then 1 elif .severity == "medium" then 2 else 3 end) | .[] | "<tr><td>\(.path)</td><td>\(.status)</td><td>\(.category)</td><td><span class=\"tag tag-\(if .severity == "critical" or .severity == "high" then "red" elif .severity == "medium" then "yellow" else "blue" end)\">\(.severity | ascii_upcase)</span></td></tr>"'
        echo "    </table>"
    else
        echo "    <p class=\"pass\">No sensitive files or directories found</p>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_jsanalysis_section() {
    local json=$1
    local risk
    risk=$(echo "$json" | jq -r '.results.jsanalysis.data.risk // "none"')
    local scripts_analyzed
    scripts_analyzed=$(echo "$json" | jq -r '.results.jsanalysis.data.scripts_analyzed // 0')
    local risk_class="tag-green"
    case "$risk" in
        medium) risk_class="tag-yellow" ;;
        high|critical) risk_class="tag-red" ;;
    esac
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">JS Analysis (${scripts_analyzed} files) <span class=\"tag ${risk_class}\">${risk^^}</span></div>"
    echo "  <div class=\"section-body\">"
    local key_count
    key_count=$(echo "$json" | jq '.results.jsanalysis.data.api_keys // [] | length')
    if [[ "$key_count" -gt 0 ]]; then
        echo "    <div style=\"margin-bottom:0.5rem\"><strong>API Keys/Secrets Found:</strong></div>"
        echo "    <table><tr><th>Type</th><th>Value (masked)</th><th>File</th></tr>"
        echo "$json" | jq -r '.results.jsanalysis.data.api_keys // [] | .[] | "<tr><td><span class=\"tag tag-red\">\(.type)</span></td><td>\(.value)</td><td>\(.file)</td></tr>"'
        echo "    </table>"
    fi
    local endpoint_count
    endpoint_count=$(echo "$json" | jq '.results.jsanalysis.data.endpoints // [] | length')
    if [[ "$endpoint_count" -gt 0 ]]; then
        echo "    <div style=\"margin-top:0.5rem\"><strong>Endpoints (${endpoint_count}):</strong></div>"
        echo "    <div>"
        echo "$json" | jq -r '.results.jsanalysis.data.endpoints // [] | .[:20][] | "<span class=\"tag tag-blue\">\(.)</span> "' | tr -d '\n'
        echo "    </div>"
    fi
    local smap_count
    smap_count=$(echo "$json" | jq '.results.jsanalysis.data.source_maps // [] | length')
    if [[ "$smap_count" -gt 0 ]]; then
        echo "    <div style=\"margin-top:0.5rem\"><strong>Source Maps (${smap_count}):</strong></div>"
        echo "$json" | jq -r '.results.jsanalysis.data.source_maps // [] | .[] | "<div class=\"list-item\"><span class=\"tag tag-yellow\">MAP</span> \(.)</div>"'
    fi
    if [[ "$key_count" -eq 0 ]] && [[ "$endpoint_count" -eq 0 ]] && [[ "$smap_count" -eq 0 ]]; then
        echo "    <p class=\"pass\">No sensitive data found in JavaScript files</p>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_favicon_section() {
    local json=$1
    local found
    found=$(echo "$json" | jq -r '.results.favicon.data.found // false')
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Favicon Hash</div>"
    echo "  <div class=\"section-body\">"
    if [[ "$found" == "true" ]]; then
        local md5 mmh3 method shodan_url
        md5=$(echo "$json" | jq -r '.results.favicon.data.hashes.md5 // ""')
        mmh3=$(echo "$json" | jq -r '.results.favicon.data.hashes.mmh3 // ""')
        method=$(echo "$json" | jq -r '.results.favicon.data.hash_method // ""')
        shodan_url=$(echo "$json" | jq -r '.results.favicon.data.shodan_url // ""')
        [[ -n "$md5" ]] && echo "    <div class=\"kv\"><span class=\"key\">MD5:</span> <span class=\"val\">${md5}</span></div>"
        [[ -n "$mmh3" ]] && echo "    <div class=\"kv\"><span class=\"key\">MurmurHash3:</span> <span class=\"val\">${mmh3}</span></div>"
        [[ -n "$method" ]] && echo "    <div class=\"kv\"><span class=\"key\">Method:</span> <span class=\"val\">${method}</span></div>"
        [[ -n "$shodan_url" ]] && echo "    <div class=\"kv\"><span class=\"key\">Shodan:</span> <span class=\"val\"><a href=\"${shodan_url}\" style=\"color:var(--blue)\">${shodan_url}</a></span></div>"
    else
        echo "    <p style=\"color:var(--text-muted)\">No favicon found</p>"
    fi
    echo "  </div>"
    echo "</div>"
}

_report_emailsec_section() {
    local json=$1
    local grade
    grade=$(echo "$json" | jq -r '.results.emailsec.data.grade // "N/A"')
    local grade_class="grade-f"
    case "$grade" in
        A) grade_class="grade-a" ;; B) grade_class="grade-b" ;;
        C) grade_class="grade-c" ;; D) grade_class="grade-d" ;;
    esac
    local tag_class="tag-red"
    case "$grade" in A|B) tag_class="tag-blue" ;; C) tag_class="tag-yellow" ;; esac
    echo "<div class=\"section\">"
    echo "  <div class=\"section-title\">Email Security <span class=\"tag ${tag_class}\">${grade}</span></div>"
    echo "  <div class=\"section-body\">"
    echo "    <div style=\"display:flex;align-items:center;margin-bottom:1rem\">"
    echo "      <div class=\"grade ${grade_class}\">${grade}</div>"
    echo "      <div><strong>Email Security Grade</strong></div>"
    echo "    </div>"

    # SPF
    local spf_record
    spf_record=$(echo "$json" | jq -r '.results.emailsec.data.spf.record // ""')
    if [[ -n "$spf_record" ]]; then
        local spf_qual
        spf_qual=$(echo "$json" | jq -r '.results.emailsec.data.spf.all_qualifier // "none"')
        local spf_lookups
        spf_lookups=$(echo "$json" | jq -r '.results.emailsec.data.spf.dns_lookups // 0')
        echo "    <div style=\"margin-bottom:0.5rem\"><strong>SPF</strong> <span class=\"tag tag-blue\">${spf_qual}</span> (${spf_lookups} DNS lookups)</div>"
    else
        echo "    <div style=\"margin-bottom:0.5rem\"><strong>SPF</strong> <span class=\"tag tag-red\">MISSING</span></div>"
    fi

    # DMARC
    local dmarc_policy
    dmarc_policy=$(echo "$json" | jq -r '.results.emailsec.data.dmarc.policy // ""')
    if [[ -n "$dmarc_policy" ]]; then
        echo "    <div style=\"margin-bottom:0.5rem\"><strong>DMARC</strong> <span class=\"tag tag-blue\">p=${dmarc_policy}</span></div>"
    else
        echo "    <div style=\"margin-bottom:0.5rem\"><strong>DMARC</strong> <span class=\"tag tag-red\">MISSING</span></div>"
    fi

    # DKIM
    local dkim_found
    dkim_found=$(echo "$json" | jq '.results.emailsec.data.dkim.selectors_found // [] | length')
    echo "    <div style=\"margin-bottom:0.5rem\"><strong>DKIM</strong> <span class=\"tag tag-blue\">${dkim_found} selectors</span></div>"

    # BIMI
    local bimi_found
    bimi_found=$(echo "$json" | jq -r '.results.emailsec.data.bimi.found // false')
    if [[ "$bimi_found" == "true" ]]; then
        echo "    <div style=\"margin-bottom:0.5rem\"><strong>BIMI</strong> <span class=\"tag tag-green\">FOUND</span></div>"
    fi

    # Recommendations
    local rec_count
    rec_count=$(echo "$json" | jq '.results.emailsec.data.recommendations // [] | length')
    if [[ "$rec_count" -gt 0 ]]; then
        echo "    <div style=\"margin-top:1rem\">"
        echo "$json" | jq -r '.results.emailsec.data.recommendations[] | "      <div class=\"list-item\"><span class=\"tag tag-yellow\">FIX</span> \(.)</div>"'
        echo "    </div>"
    fi
    echo "  </div>"
    echo "</div>"
}
