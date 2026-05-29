#!/usr/bin/env bash
#
# config.sh - Configuration loading and management for recon
#
# Loads configuration from YAML files using yq, with fallback defaults
# and environment variable overrides.
#

# Prevent multiple sourcing
[[ -n "${_RECON_CONFIG_LOADED:-}" ]] && return 0
_RECON_CONFIG_LOADED=1

# Default configuration values
declare -A RECON_CONFIG

# Initialize defaults
_init_config_defaults() {
    # Global settings
    RECON_CONFIG[global.output_dir]="${HOME}/.local/share/recon/results"
    RECON_CONFIG[global.output_format]="terminal"
    RECON_CONFIG[global.color]="auto"
    RECON_CONFIG[global.retention_days]="30"

    # Timeouts (seconds)
    RECON_CONFIG[timeouts.dns]="5"
    RECON_CONFIG[timeouts.http]="10"
    RECON_CONFIG[timeouts.ssl]="5"
    RECON_CONFIG[timeouts.whois]="15"

    # Batch processing
    RECON_CONFIG[batch.max_parallel]="4"
    RECON_CONFIG[batch.checkpoint_interval]="10"
    RECON_CONFIG[batch.resume_on_start]="true"

    # Rate limits
    RECON_CONFIG[rate_limits.requests_per_second]="2"
    RECON_CONFIG[rate_limits.whois_delay]="1"

    # Module settings
    RECON_CONFIG[modules.dns.enabled]="true"
    RECON_CONFIG[modules.dns.record_types]="A,AAAA,MX,TXT,NS,CAA"
    RECON_CONFIG[modules.subdomain.enabled]="true"
    RECON_CONFIG[modules.subdomain.wordlist]=""
    RECON_CONFIG[modules.ssl.enabled]="true"
    RECON_CONFIG[modules.http.enabled]="true"
    RECON_CONFIG[modules.whois.enabled]="true"
    RECON_CONFIG[modules.files.enabled]="true"
    RECON_CONFIG[modules.tech.enabled]="true"
    RECON_CONFIG[modules.ip.enabled]="true"
    RECON_CONFIG[modules.ports.enabled]="true"
    RECON_CONFIG[modules.cors.enabled]="true"
    RECON_CONFIG[modules.score.enabled]="true"
    RECON_CONFIG[modules.crt.enabled]="true"
    RECON_CONFIG[modules.shodan.enabled]="true"
    RECON_CONFIG[modules.virustotal.enabled]="true"
    RECON_CONFIG[modules.waf.enabled]="true"
    RECON_CONFIG[modules.dnssec.enabled]="true"
    RECON_CONFIG[modules.takeover.enabled]="true"
    RECON_CONFIG[modules.wayback.enabled]="true"
    RECON_CONFIG[modules.securitytrails.enabled]="true"
    RECON_CONFIG[modules.reverseip.enabled]="true"
    RECON_CONFIG[modules.asn.enabled]="true"
    RECON_CONFIG[modules.axfr.enabled]="true"
    RECON_CONFIG[modules.methods.enabled]="true"
    RECON_CONFIG[modules.dirs.enabled]="true"
    RECON_CONFIG[modules.dirs.wordlist]=""
    RECON_CONFIG[modules.dirs.request_delay]="0.2"
    RECON_CONFIG[modules.jsanalysis.enabled]="true"
    RECON_CONFIG[modules.jsanalysis.max_files]="20"
    RECON_CONFIG[modules.jsanalysis.max_file_size]="2097152"
    RECON_CONFIG[modules.favicon.enabled]="true"
    RECON_CONFIG[modules.emailsec.enabled]="true"

    # Timeouts for new modules
    RECON_CONFIG[timeouts.ports]="2"
    RECON_CONFIG[timeouts.crt]="15"
    RECON_CONFIG[timeouts.waf]="10"
    RECON_CONFIG[timeouts.dnssec]="10"
    RECON_CONFIG[timeouts.takeover]="15"
    RECON_CONFIG[timeouts.shodan]="10"
    RECON_CONFIG[timeouts.virustotal]="10"
    RECON_CONFIG[timeouts.wayback]="30"
    RECON_CONFIG[timeouts.securitytrails]="15"
    RECON_CONFIG[timeouts.reverseip]="10"
    RECON_CONFIG[timeouts.asn]="15"
    RECON_CONFIG[timeouts.axfr]="10"
    RECON_CONFIG[timeouts.methods]="10"
    RECON_CONFIG[timeouts.dirs]="10"
    RECON_CONFIG[timeouts.jsanalysis]="15"
    RECON_CONFIG[timeouts.favicon]="10"
    RECON_CONFIG[timeouts.emailsec]="15"

    # API keys (empty by default, use env vars)
    RECON_CONFIG[api_keys.shodan]=""
    RECON_CONFIG[api_keys.securitytrails]=""
    RECON_CONFIG[api_keys.virustotal]=""
}

# Check if yq is available
_has_yq() {
    command -v yq &>/dev/null
}

# Load a value from YAML file
# Usage: value=$(_yaml_get "path.to.key" "/path/to/config.yaml")
_yaml_get() {
    local path=$1
    local file=$2

    if ! _has_yq; then
        return 1
    fi

    # Convert dot notation to yq path
    local yq_path
    yq_path=$(echo "$path" | sed 's/\./\./g')

    local value
    value=$(yq -r ".$yq_path // empty" "$file" 2>/dev/null)

    if [[ -n "$value" ]] && [[ "$value" != "null" ]]; then
        echo "$value"
        return 0
    fi

    return 1
}

# Find config file in standard locations
# Usage: config_file=$(find_config_file)
find_config_file() {
    local custom_config="${RECON_CONFIG_FILE:-}"

    # Check custom path first
    if [[ -n "$custom_config" ]] && [[ -f "$custom_config" ]]; then
        echo "$custom_config"
        return 0
    fi

    # Standard locations
    local locations=(
        "./recon.yaml"
        "./recon.yml"
        "./.recon.yaml"
        "./.recon.yml"
        "${XDG_CONFIG_HOME:-$HOME/.config}/recon/recon.yaml"
        "${HOME}/.recon.yaml"
        "/etc/recon/recon.yaml"
    )

    for loc in "${locations[@]}"; do
        if [[ -f "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done

    return 1
}

# Load configuration from file
# Usage: load_config [/path/to/config.yaml]
load_config() {
    local config_file="${1:-}"

    # Initialize defaults first
    _init_config_defaults

    # Find config file if not specified
    if [[ -z "$config_file" ]]; then
        config_file=$(find_config_file) || true
    fi

    # Load from file if available and yq is present
    if [[ -n "$config_file" ]] && [[ -f "$config_file" ]] && _has_yq; then
        debug "Loading config from: $config_file"

        # Load each known config key
        for key in "${!RECON_CONFIG[@]}"; do
            local value
            if value=$(_yaml_get "$key" "$config_file"); then
                RECON_CONFIG[$key]="$value"
            fi
        done
    fi

    # Apply environment variable overrides
    _apply_env_overrides
}

# Apply environment variable overrides
# Env vars use RECON_ prefix with underscores
# e.g., RECON_GLOBAL_OUTPUT_FORMAT, RECON_TIMEOUTS_DNS
_apply_env_overrides() {
    # Global settings
    [[ -n "${RECON_OUTPUT_DIR:-}" ]] && RECON_CONFIG[global.output_dir]="$RECON_OUTPUT_DIR" || true
    [[ -n "${RECON_OUTPUT_FORMAT:-}" ]] && RECON_CONFIG[global.output_format]="$RECON_OUTPUT_FORMAT" || true
    [[ -n "${RECON_COLOR:-}" ]] && RECON_CONFIG[global.color]="$RECON_COLOR" || true

    # Timeouts
    [[ -n "${RECON_TIMEOUT_DNS:-}" ]] && RECON_CONFIG[timeouts.dns]="$RECON_TIMEOUT_DNS" || true
    [[ -n "${RECON_TIMEOUT_HTTP:-}" ]] && RECON_CONFIG[timeouts.http]="$RECON_TIMEOUT_HTTP" || true
    [[ -n "${RECON_TIMEOUT_SSL:-}" ]] && RECON_CONFIG[timeouts.ssl]="$RECON_TIMEOUT_SSL" || true
    [[ -n "${RECON_TIMEOUT_WHOIS:-}" ]] && RECON_CONFIG[timeouts.whois]="$RECON_TIMEOUT_WHOIS" || true

    # Batch settings
    [[ -n "${RECON_PARALLEL:-}" ]] && RECON_CONFIG[batch.max_parallel]="$RECON_PARALLEL" || true

    # API keys
    [[ -n "${RECON_API_SHODAN:-}" ]] && RECON_CONFIG[api_keys.shodan]="$RECON_API_SHODAN" || true
    [[ -n "${RECON_API_SECURITYTRAILS:-}" ]] && RECON_CONFIG[api_keys.securitytrails]="$RECON_API_SECURITYTRAILS" || true
    [[ -n "${RECON_API_VIRUSTOTAL:-}" ]] && RECON_CONFIG[api_keys.virustotal]="$RECON_API_VIRUSTOTAL" || true

    # Timeout overrides for new modules
    [[ -n "${RECON_TIMEOUT_CRT:-}" ]] && RECON_CONFIG[timeouts.crt]="$RECON_TIMEOUT_CRT" || true
    [[ -n "${RECON_TIMEOUT_WAF:-}" ]] && RECON_CONFIG[timeouts.waf]="$RECON_TIMEOUT_WAF" || true
    [[ -n "${RECON_TIMEOUT_DNSSEC:-}" ]] && RECON_CONFIG[timeouts.dnssec]="$RECON_TIMEOUT_DNSSEC" || true
    [[ -n "${RECON_TIMEOUT_TAKEOVER:-}" ]] && RECON_CONFIG[timeouts.takeover]="$RECON_TIMEOUT_TAKEOVER" || true
    [[ -n "${RECON_TIMEOUT_SHODAN:-}" ]] && RECON_CONFIG[timeouts.shodan]="$RECON_TIMEOUT_SHODAN" || true
    [[ -n "${RECON_TIMEOUT_VIRUSTOTAL:-}" ]] && RECON_CONFIG[timeouts.virustotal]="$RECON_TIMEOUT_VIRUSTOTAL" || true
    [[ -n "${RECON_TIMEOUT_WAYBACK:-}" ]] && RECON_CONFIG[timeouts.wayback]="$RECON_TIMEOUT_WAYBACK" || true
    [[ -n "${RECON_TIMEOUT_SECURITYTRAILS:-}" ]] && RECON_CONFIG[timeouts.securitytrails]="$RECON_TIMEOUT_SECURITYTRAILS" || true
    [[ -n "${RECON_TIMEOUT_REVERSEIP:-}" ]] && RECON_CONFIG[timeouts.reverseip]="$RECON_TIMEOUT_REVERSEIP" || true
    [[ -n "${RECON_TIMEOUT_ASN:-}" ]] && RECON_CONFIG[timeouts.asn]="$RECON_TIMEOUT_ASN" || true
    [[ -n "${RECON_TIMEOUT_AXFR:-}" ]] && RECON_CONFIG[timeouts.axfr]="$RECON_TIMEOUT_AXFR" || true
    [[ -n "${RECON_TIMEOUT_METHODS:-}" ]] && RECON_CONFIG[timeouts.methods]="$RECON_TIMEOUT_METHODS" || true
    [[ -n "${RECON_TIMEOUT_DIRS:-}" ]] && RECON_CONFIG[timeouts.dirs]="$RECON_TIMEOUT_DIRS" || true
    [[ -n "${RECON_TIMEOUT_JSANALYSIS:-}" ]] && RECON_CONFIG[timeouts.jsanalysis]="$RECON_TIMEOUT_JSANALYSIS" || true
    [[ -n "${RECON_TIMEOUT_FAVICON:-}" ]] && RECON_CONFIG[timeouts.favicon]="$RECON_TIMEOUT_FAVICON" || true
    [[ -n "${RECON_TIMEOUT_EMAILSEC:-}" ]] && RECON_CONFIG[timeouts.emailsec]="$RECON_TIMEOUT_EMAILSEC" || true
}

# Get a config value
# Usage: value=$(config_get "global.output_format")
config_get() {
    local key=$1
    local default=${2:-}

    if [[ -v "RECON_CONFIG[$key]" ]]; then
        echo "${RECON_CONFIG[$key]}"
    else
        echo "$default"
    fi
}

# Set a config value at runtime
# Usage: config_set "global.output_format" "json"
config_set() {
    local key=$1
    local value=$2
    RECON_CONFIG[$key]="$value"
}

# Check if a module is enabled
# Usage: if module_enabled "dns"; then ...
module_enabled() {
    local module=$1
    local enabled
    enabled=$(config_get "modules.${module}.enabled" "true")
    [[ "$enabled" == "true" ]]
}

# Get timeout for a module/operation
# Usage: timeout=$(get_timeout "dns")
get_timeout() {
    local operation=$1
    config_get "timeouts.${operation}" "10"
}

# Get API key (checks config, then env var)
# Usage: key=$(get_api_key "shodan")
get_api_key() {
    local service=$1
    local key
    key=$(config_get "api_keys.${service}" "")

    # Check env var as fallback
    if [[ -z "$key" ]]; then
        local env_var="RECON_API_${service^^}"
        key="${!env_var:-}"
    fi

    echo "$key"
}

# Print current configuration (for debugging)
print_config() {
    echo "Current Configuration:"
    echo "====================="
    for key in $(echo "${!RECON_CONFIG[@]}" | tr ' ' '\n' | sort); do
        # Mask API keys
        if [[ "$key" == api_keys.* ]] && [[ -n "${RECON_CONFIG[$key]}" ]]; then
            echo "  $key = [REDACTED]"
        else
            echo "  $key = ${RECON_CONFIG[$key]}"
        fi
    done
}

# Validate configuration
# Returns 0 if valid, 1 otherwise
validate_config() {
    local errors=0

    # Check output_format
    local format
    format=$(config_get "global.output_format")
    case "$format" in
        terminal|json|both) ;;
        *)
            error "Invalid output_format: $format (must be: terminal, json, both)"
            ((errors++))
            ;;
    esac

    # Check color setting
    local color
    color=$(config_get "global.color")
    case "$color" in
        auto|always|never) ;;
        *)
            error "Invalid color setting: $color (must be: auto, always, never)"
            ((errors++))
            ;;
    esac

    # Check parallel count
    local parallel
    parallel=$(config_get "batch.max_parallel")
    if ! [[ "$parallel" =~ ^[0-9]+$ ]] || [[ "$parallel" -lt 1 ]] || [[ "$parallel" -gt 32 ]]; then
        error "Invalid max_parallel: $parallel (must be 1-32)"
        ((errors++))
    fi

    return $errors
}

# Export config to environment for subprocesses
export_config_to_env() {
    export RECON_OUTPUT_FORMAT="${RECON_CONFIG[global.output_format]}"
    export RECON_COLOR="${RECON_CONFIG[global.color]}"
    export RECON_OUTPUT_DIR="${RECON_CONFIG[global.output_dir]}"
}
