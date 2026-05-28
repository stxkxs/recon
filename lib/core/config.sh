#!/usr/bin/env bash
#
# config.sh - Configuration loading and management for recond
#
# Loads configuration from YAML files using yq, with fallback defaults
# and environment variable overrides.
#

# Prevent multiple sourcing
[[ -n "${_RECOND_CONFIG_LOADED:-}" ]] && return 0
_RECOND_CONFIG_LOADED=1

# Default configuration values
declare -A RECOND_CONFIG

# Initialize defaults
_init_config_defaults() {
    # Global settings
    RECOND_CONFIG[global.output_dir]="${HOME}/.local/share/recond/results"
    RECOND_CONFIG[global.output_format]="terminal"
    RECOND_CONFIG[global.color]="auto"
    RECOND_CONFIG[global.retention_days]="30"

    # Timeouts (seconds)
    RECOND_CONFIG[timeouts.dns]="5"
    RECOND_CONFIG[timeouts.http]="10"
    RECOND_CONFIG[timeouts.ssl]="5"
    RECOND_CONFIG[timeouts.whois]="15"

    # Batch processing
    RECOND_CONFIG[batch.max_parallel]="4"
    RECOND_CONFIG[batch.checkpoint_interval]="10"
    RECOND_CONFIG[batch.resume_on_start]="true"

    # Rate limits
    RECOND_CONFIG[rate_limits.requests_per_second]="2"
    RECOND_CONFIG[rate_limits.whois_delay]="1"

    # Module settings
    RECOND_CONFIG[modules.dns.enabled]="true"
    RECOND_CONFIG[modules.dns.record_types]="A,AAAA,MX,TXT,NS,CAA"
    RECOND_CONFIG[modules.subdomain.enabled]="true"
    RECOND_CONFIG[modules.subdomain.wordlist]=""
    RECOND_CONFIG[modules.ssl.enabled]="true"
    RECOND_CONFIG[modules.http.enabled]="true"
    RECOND_CONFIG[modules.whois.enabled]="true"
    RECOND_CONFIG[modules.files.enabled]="true"
    RECOND_CONFIG[modules.tech.enabled]="true"
    RECOND_CONFIG[modules.ip.enabled]="true"
    RECOND_CONFIG[modules.ports.enabled]="true"
    RECOND_CONFIG[modules.cors.enabled]="true"
    RECOND_CONFIG[modules.score.enabled]="true"
    RECOND_CONFIG[modules.crt.enabled]="true"
    RECOND_CONFIG[modules.shodan.enabled]="true"
    RECOND_CONFIG[modules.virustotal.enabled]="true"
    RECOND_CONFIG[modules.waf.enabled]="true"
    RECOND_CONFIG[modules.dnssec.enabled]="true"
    RECOND_CONFIG[modules.takeover.enabled]="true"
    RECOND_CONFIG[modules.wayback.enabled]="true"
    RECOND_CONFIG[modules.securitytrails.enabled]="true"
    RECOND_CONFIG[modules.reverseip.enabled]="true"
    RECOND_CONFIG[modules.asn.enabled]="true"
    RECOND_CONFIG[modules.axfr.enabled]="true"
    RECOND_CONFIG[modules.methods.enabled]="true"
    RECOND_CONFIG[modules.dirs.enabled]="true"
    RECOND_CONFIG[modules.dirs.wordlist]=""
    RECOND_CONFIG[modules.dirs.request_delay]="0.2"
    RECOND_CONFIG[modules.jsanalysis.enabled]="true"
    RECOND_CONFIG[modules.jsanalysis.max_files]="20"
    RECOND_CONFIG[modules.jsanalysis.max_file_size]="2097152"
    RECOND_CONFIG[modules.favicon.enabled]="true"
    RECOND_CONFIG[modules.emailsec.enabled]="true"

    # Timeouts for new modules
    RECOND_CONFIG[timeouts.ports]="2"
    RECOND_CONFIG[timeouts.crt]="15"
    RECOND_CONFIG[timeouts.waf]="10"
    RECOND_CONFIG[timeouts.dnssec]="10"
    RECOND_CONFIG[timeouts.takeover]="15"
    RECOND_CONFIG[timeouts.shodan]="10"
    RECOND_CONFIG[timeouts.virustotal]="10"
    RECOND_CONFIG[timeouts.wayback]="30"
    RECOND_CONFIG[timeouts.securitytrails]="15"
    RECOND_CONFIG[timeouts.reverseip]="10"
    RECOND_CONFIG[timeouts.asn]="15"
    RECOND_CONFIG[timeouts.axfr]="10"
    RECOND_CONFIG[timeouts.methods]="10"
    RECOND_CONFIG[timeouts.dirs]="10"
    RECOND_CONFIG[timeouts.jsanalysis]="15"
    RECOND_CONFIG[timeouts.favicon]="10"
    RECOND_CONFIG[timeouts.emailsec]="15"

    # API keys (empty by default, use env vars)
    RECOND_CONFIG[api_keys.shodan]=""
    RECOND_CONFIG[api_keys.securitytrails]=""
    RECOND_CONFIG[api_keys.virustotal]=""
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
    local custom_config="${RECOND_CONFIG_FILE:-}"

    # Check custom path first
    if [[ -n "$custom_config" ]] && [[ -f "$custom_config" ]]; then
        echo "$custom_config"
        return 0
    fi

    # Standard locations
    local locations=(
        "./recond.yaml"
        "./recond.yml"
        "./.recond.yaml"
        "./.recond.yml"
        "${XDG_CONFIG_HOME:-$HOME/.config}/recond/recond.yaml"
        "${HOME}/.recond.yaml"
        "/etc/recond/recond.yaml"
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
        for key in "${!RECOND_CONFIG[@]}"; do
            local value
            if value=$(_yaml_get "$key" "$config_file"); then
                RECOND_CONFIG[$key]="$value"
            fi
        done
    fi

    # Apply environment variable overrides
    _apply_env_overrides
}

# Apply environment variable overrides
# Env vars use RECOND_ prefix with underscores
# e.g., RECOND_GLOBAL_OUTPUT_FORMAT, RECOND_TIMEOUTS_DNS
_apply_env_overrides() {
    # Global settings
    [[ -n "${RECOND_OUTPUT_DIR:-}" ]] && RECOND_CONFIG[global.output_dir]="$RECOND_OUTPUT_DIR" || true
    [[ -n "${RECOND_OUTPUT_FORMAT:-}" ]] && RECOND_CONFIG[global.output_format]="$RECOND_OUTPUT_FORMAT" || true
    [[ -n "${RECOND_COLOR:-}" ]] && RECOND_CONFIG[global.color]="$RECOND_COLOR" || true

    # Timeouts
    [[ -n "${RECOND_TIMEOUT_DNS:-}" ]] && RECOND_CONFIG[timeouts.dns]="$RECOND_TIMEOUT_DNS" || true
    [[ -n "${RECOND_TIMEOUT_HTTP:-}" ]] && RECOND_CONFIG[timeouts.http]="$RECOND_TIMEOUT_HTTP" || true
    [[ -n "${RECOND_TIMEOUT_SSL:-}" ]] && RECOND_CONFIG[timeouts.ssl]="$RECOND_TIMEOUT_SSL" || true
    [[ -n "${RECOND_TIMEOUT_WHOIS:-}" ]] && RECOND_CONFIG[timeouts.whois]="$RECOND_TIMEOUT_WHOIS" || true

    # Batch settings
    [[ -n "${RECOND_PARALLEL:-}" ]] && RECOND_CONFIG[batch.max_parallel]="$RECOND_PARALLEL" || true

    # API keys
    [[ -n "${RECOND_API_SHODAN:-}" ]] && RECOND_CONFIG[api_keys.shodan]="$RECOND_API_SHODAN" || true
    [[ -n "${RECOND_API_SECURITYTRAILS:-}" ]] && RECOND_CONFIG[api_keys.securitytrails]="$RECOND_API_SECURITYTRAILS" || true
    [[ -n "${RECOND_API_VIRUSTOTAL:-}" ]] && RECOND_CONFIG[api_keys.virustotal]="$RECOND_API_VIRUSTOTAL" || true

    # Timeout overrides for new modules
    [[ -n "${RECOND_TIMEOUT_CRT:-}" ]] && RECOND_CONFIG[timeouts.crt]="$RECOND_TIMEOUT_CRT" || true
    [[ -n "${RECOND_TIMEOUT_WAF:-}" ]] && RECOND_CONFIG[timeouts.waf]="$RECOND_TIMEOUT_WAF" || true
    [[ -n "${RECOND_TIMEOUT_DNSSEC:-}" ]] && RECOND_CONFIG[timeouts.dnssec]="$RECOND_TIMEOUT_DNSSEC" || true
    [[ -n "${RECOND_TIMEOUT_TAKEOVER:-}" ]] && RECOND_CONFIG[timeouts.takeover]="$RECOND_TIMEOUT_TAKEOVER" || true
    [[ -n "${RECOND_TIMEOUT_SHODAN:-}" ]] && RECOND_CONFIG[timeouts.shodan]="$RECOND_TIMEOUT_SHODAN" || true
    [[ -n "${RECOND_TIMEOUT_VIRUSTOTAL:-}" ]] && RECOND_CONFIG[timeouts.virustotal]="$RECOND_TIMEOUT_VIRUSTOTAL" || true
    [[ -n "${RECOND_TIMEOUT_WAYBACK:-}" ]] && RECOND_CONFIG[timeouts.wayback]="$RECOND_TIMEOUT_WAYBACK" || true
    [[ -n "${RECOND_TIMEOUT_SECURITYTRAILS:-}" ]] && RECOND_CONFIG[timeouts.securitytrails]="$RECOND_TIMEOUT_SECURITYTRAILS" || true
    [[ -n "${RECOND_TIMEOUT_REVERSEIP:-}" ]] && RECOND_CONFIG[timeouts.reverseip]="$RECOND_TIMEOUT_REVERSEIP" || true
    [[ -n "${RECOND_TIMEOUT_ASN:-}" ]] && RECOND_CONFIG[timeouts.asn]="$RECOND_TIMEOUT_ASN" || true
    [[ -n "${RECOND_TIMEOUT_AXFR:-}" ]] && RECOND_CONFIG[timeouts.axfr]="$RECOND_TIMEOUT_AXFR" || true
    [[ -n "${RECOND_TIMEOUT_METHODS:-}" ]] && RECOND_CONFIG[timeouts.methods]="$RECOND_TIMEOUT_METHODS" || true
    [[ -n "${RECOND_TIMEOUT_DIRS:-}" ]] && RECOND_CONFIG[timeouts.dirs]="$RECOND_TIMEOUT_DIRS" || true
    [[ -n "${RECOND_TIMEOUT_JSANALYSIS:-}" ]] && RECOND_CONFIG[timeouts.jsanalysis]="$RECOND_TIMEOUT_JSANALYSIS" || true
    [[ -n "${RECOND_TIMEOUT_FAVICON:-}" ]] && RECOND_CONFIG[timeouts.favicon]="$RECOND_TIMEOUT_FAVICON" || true
    [[ -n "${RECOND_TIMEOUT_EMAILSEC:-}" ]] && RECOND_CONFIG[timeouts.emailsec]="$RECOND_TIMEOUT_EMAILSEC" || true
}

# Get a config value
# Usage: value=$(config_get "global.output_format")
config_get() {
    local key=$1
    local default=${2:-}

    if [[ -v "RECOND_CONFIG[$key]" ]]; then
        echo "${RECOND_CONFIG[$key]}"
    else
        echo "$default"
    fi
}

# Set a config value at runtime
# Usage: config_set "global.output_format" "json"
config_set() {
    local key=$1
    local value=$2
    RECOND_CONFIG[$key]="$value"
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
        local env_var="RECOND_API_${service^^}"
        key="${!env_var:-}"
    fi

    echo "$key"
}

# Print current configuration (for debugging)
print_config() {
    echo "Current Configuration:"
    echo "====================="
    for key in $(echo "${!RECOND_CONFIG[@]}" | tr ' ' '\n' | sort); do
        # Mask API keys
        if [[ "$key" == api_keys.* ]] && [[ -n "${RECOND_CONFIG[$key]}" ]]; then
            echo "  $key = [REDACTED]"
        else
            echo "  $key = ${RECOND_CONFIG[$key]}"
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
    export RECOND_OUTPUT_FORMAT="${RECOND_CONFIG[global.output_format]}"
    export RECOND_COLOR="${RECOND_CONFIG[global.color]}"
    export RECOND_OUTPUT_DIR="${RECOND_CONFIG[global.output_dir]}"
}
