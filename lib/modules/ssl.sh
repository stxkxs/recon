#!/usr/bin/env bash
#
# ssl.sh - SSL/TLS certificate analysis module for recond
#
# Analyzes SSL certificates including:
# - Subject and issuer information
# - Validity dates
# - Subject Alternative Names (SANs)
# - TLS version
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_SSL_LOADED:-}" ]] && return 0
_RECOND_MODULE_SSL_LOADED=1

# Module info
MODULE_SSL_NAME="ssl"
MODULE_SSL_DESCRIPTION="SSL/TLS certificate analysis"

# Default subdomains to check for SSL
DEFAULT_SSL_SUBDOMAINS=(www app api)

# Analyze SSL certificate for a single host
# Usage: ssl_analyze_host "example.com"
# Returns: JSON object with certificate details
ssl_analyze_host() {
    local host=$1
    local port=${2:-443}
    local timeout
    timeout=$(get_timeout "ssl" 2>/dev/null || echo "5")

    local result
    result=$(jq -n '{
        host: "",
        connected: false,
        subject: null,
        issuer: null,
        not_before: null,
        not_after: null,
        sans: [],
        tls_version: null
    }' | jq --arg host "$host" '.host = $host')

    # Get certificate info
    local cert_info
    cert_info=$(echo | safe_timeout "$timeout" openssl s_client -servername "$host" -connect "${host}:${port}" 2>/dev/null)

    if [[ -z "$cert_info" ]]; then
        echo "$result"
        return 0
    fi

    result=$(echo "$result" | jq '.connected = true')

    # Parse certificate details
    local cert_details
    cert_details=$(echo "$cert_info" | openssl x509 -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null || true)

    if [[ -n "$cert_details" ]]; then
        # Extract subject
        local subject
        subject=$(echo "$cert_details" | grep '^subject=' | sed 's/^subject=//' | xargs)
        if [[ -n "$subject" ]]; then
            result=$(echo "$result" | jq --arg v "$subject" '.subject = $v')
        fi

        # Extract issuer
        local issuer
        issuer=$(echo "$cert_details" | grep '^issuer=' | sed 's/^issuer=//' | xargs)
        if [[ -n "$issuer" ]]; then
            result=$(echo "$result" | jq --arg v "$issuer" '.issuer = $v')
        fi

        # Extract dates
        local not_before
        not_before=$(echo "$cert_details" | grep '^notBefore=' | sed 's/^notBefore=//' | xargs)
        if [[ -n "$not_before" ]]; then
            result=$(echo "$result" | jq --arg v "$not_before" '.not_before = $v')
        fi

        local not_after
        not_after=$(echo "$cert_details" | grep '^notAfter=' | sed 's/^notAfter=//' | xargs)
        if [[ -n "$not_after" ]]; then
            result=$(echo "$result" | jq --arg v "$not_after" '.not_after = $v')
        fi

        # Extract SANs
        local sans
        sans=$(echo "$cert_details" | grep -oE 'DNS:[^,]+' | sed 's/DNS://' | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$sans" ]]; then
            result=$(echo "$result" | jq --arg v "$sans" '.sans = ($v | split(",") | map(select(length > 0)))')
        fi
    fi

    # Get TLS version
    local tls_version
    tls_version=$(echo "$cert_info" | grep 'Protocol' | awk '{print $NF}' | head -1)
    if [[ -n "$tls_version" ]]; then
        result=$(echo "$result" | jq --arg v "$tls_version" '.tls_version = $v')
    fi

    echo "$result"
}

# Run SSL analysis on domain and subdomains
# Usage: ssl_run "example.com"
# Output: JSON object with all SSL results
ssl_run() {
    local domain=$1
    local timeout
    timeout=$(get_timeout "dns" 2>/dev/null || echo "5")

    local result_json
    result_json=$(jq -n '{
        certificates: []
    }')

    # Build list of hosts to check
    local hosts=("$domain")

    # Add subdomains that resolve
    for sub in "${DEFAULT_SSL_SUBDOMAINS[@]}"; do
        local ip
        ip=$(safe_timeout "$timeout" dig +short "${sub}.${domain}" A 2>/dev/null | head -1 || true)
        if [[ -n "$ip" ]] && [[ "$ip" =~ ^[0-9.]+$ ]]; then
            hosts+=("${sub}.${domain}")
        fi
    done

    # Analyze each host
    local certs_json='[]'
    for host in "${hosts[@]}"; do
        local cert_result
        cert_result=$(ssl_analyze_host "$host")
        certs_json=$(echo "$certs_json" | jq --argjson cert "$cert_result" '. += [$cert]')
    done

    result_json=$(echo "$result_json" | jq --argjson certs "$certs_json" '.certificates = $certs')
    echo "$result_json"
}

# Terminal output for SSL results
# Usage: ssl_print "$json_result"
ssl_print() {
    local json=$1

    header "SSL/TLS CERTIFICATE ANALYSIS"

    echo "$json" | jq -r '.certificates[] | @base64' | while read -r cert_b64; do
        local cert
        cert=$(echo "$cert_b64" | base64 -d)

        local host
        host=$(echo "$cert" | jq -r '.host')
        local connected
        connected=$(echo "$cert" | jq -r '.connected')

        subheader "$host"

        if [[ "$connected" != "true" ]]; then
            info "Could not connect to $host:443"
            continue
        fi

        local subject
        subject=$(echo "$cert" | jq -r '.subject // empty')
        [[ -n "$subject" ]] && success "Subject: $subject"

        local issuer
        issuer=$(echo "$cert" | jq -r '.issuer // empty')
        [[ -n "$issuer" ]] && success "Issuer: $issuer"

        local not_before
        not_before=$(echo "$cert" | jq -r '.not_before // empty')
        [[ -n "$not_before" ]] && info "Valid From: $not_before"

        local not_after
        not_after=$(echo "$cert" | jq -r '.not_after // empty')
        [[ -n "$not_after" ]] && info "Valid Until: $not_after"

        local tls_version
        tls_version=$(echo "$cert" | jq -r '.tls_version // empty')
        [[ -n "$tls_version" ]] && info "TLS Version: $tls_version"

        local sans
        sans=$(echo "$cert" | jq -r '.sans | join(", ")' 2>/dev/null || echo "")
        if [[ -n "$sans" ]] && [[ "$sans" != "null" ]]; then
            echo "  SANs: $sans"
        fi
    done
}

# Check if SSL module can run
ssl_check() {
    check_dependencies openssl dig
}
