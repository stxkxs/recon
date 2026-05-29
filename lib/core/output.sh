#!/usr/bin/env bash
#
# output.sh - JSON and terminal output formatting for recon
#
# Provides functions to build and output JSON results, and format
# terminal output consistently across modules.
#

# Prevent multiple sourcing
[[ -n "${_RECON_OUTPUT_LOADED:-}" ]] && return 0
_RECON_OUTPUT_LOADED=1

# Ensure jq is available for JSON operations
_check_jq() {
    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required for JSON output" >&2
        return 1
    fi
}

# Initialize a new JSON result object
# Usage: json_init "example.com" "example.com"
# Returns: JSON object with meta section
json_init() {
    local target_original=$1
    local target_normalized=$2
    local run_id
    run_id=$(generate_run_id 2>/dev/null || date '+%Y%m%d-%H%M%S')

    _check_jq || return 1

    jq -n \
        --arg version "$RECON_VERSION" \
        --arg run_id "$run_id" \
        --arg started_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg target_original "$target_original" \
        --arg target_normalized "$target_normalized" \
        '{
            meta: {
                version: $version,
                run_id: $run_id,
                started_at: $started_at,
                target_original: $target_original,
                target_normalized: $target_normalized
            },
            target: $target_normalized,
            results: {},
            errors: [],
            conflicts: [],
            summary: {}
        }'
}

# Add module results to JSON
# Usage: echo "$json" | json_add_result "dns" "success" "$data_json"
json_add_result() {
    local module=$1
    local status=$2
    local data=$3

    _check_jq || return 1

    jq --arg module "$module" \
       --arg status "$status" \
       --argjson data "$data" \
       '.results[$module] = {status: $status, data: $data}'
}

# Add an error to JSON
# Usage: echo "$json" | json_add_error "ssl" "api.example.com" "timeout"
json_add_error() {
    local module=$1
    local target=$2
    local error_msg=$3

    _check_jq || return 1

    jq --arg module "$module" \
       --arg target "$target" \
       --arg error "$error_msg" \
       '.errors += [{module: $module, target: $target, error: $error}]'
}

# Add a conflict to JSON
# Usage: echo "$json" | json_add_conflict "cdn" '{"headers": "cloudflare", "dns": "cloudfront"}'
json_add_conflict() {
    local field=$1
    local evidence=$2

    _check_jq || return 1

    jq --arg field "$field" \
       --argjson evidence "$evidence" \
       '.conflicts += [{field: $field, evidence: $evidence}]'
}

# Finalize JSON with summary and end timestamp
# Usage: echo "$json" | json_finalize
json_finalize() {
    _check_jq || return 1

    jq --arg ended_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
       '.meta.ended_at = $ended_at |
        .summary = {
            modules_run: (.results | keys | length),
            modules_success: ([.results[] | select(.status == "success")] | length),
            modules_partial: ([.results[] | select(.status == "partial")] | length),
            modules_failed: ([.results[] | select(.status == "failed")] | length),
            total_errors: (.errors | length),
            total_conflicts: (.conflicts | length)
        }'
}

# Build a simple JSON object from key-value pairs
# Usage: json_object "key1" "value1" "key2" "value2"
json_object() {
    _check_jq || return 1

    local json='{}'
    while [[ $# -ge 2 ]]; do
        local key=$1
        local value=$2
        shift 2
        json=$(echo "$json" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
    done
    echo "$json"
}

# Build a JSON array from arguments
# Usage: json_array "item1" "item2" "item3"
json_array() {
    _check_jq || return 1

    printf '%s\n' "$@" | jq -R . | jq -s .
}

# Build a JSON array from newline-separated input
# Usage: echo -e "item1\nitem2" | json_array_from_lines
json_array_from_lines() {
    _check_jq || return 1

    jq -R . | jq -s .
}

# Escape a string for JSON
# Usage: escaped=$(json_escape "string with \"quotes\"")
json_escape() {
    _check_jq || return 1

    printf '%s' "$1" | jq -Rs .
}

# Pretty print JSON
# Usage: echo "$json" | json_pretty
json_pretty() {
    _check_jq || return 1

    jq .
}

# Compact JSON (single line)
# Usage: echo "$json" | json_compact
json_compact() {
    _check_jq || return 1

    jq -c .
}

# Output JSON to file or stdout
# Usage: json_output "$json" [filepath]
json_output() {
    local json=$1
    local filepath=${2:-}

    if [[ -n "$filepath" ]]; then
        echo "$json" | jq . > "$filepath"
    else
        echo "$json" | jq .
    fi
}

# Terminal table output helpers
# Print a simple table row
# Usage: table_row "Label" "Value"
table_row() {
    local label=$1
    local value=$2
    printf "  ${BOLD}%-20s${NC} %s\n" "$label:" "$value"
}

# Print a key-value pair with color
# Usage: kv_print "Key" "Value" [color]
kv_print() {
    local key=$1
    local value=$2
    local color=${3:-$NC}
    echo -e "  ${BOLD}${key}:${NC} ${color}${value}${NC}"
}

# Print a list item
# Usage: list_item "text" [prefix_char] [color]
list_item() {
    local text=$1
    local prefix=${2:-•}
    local color=${3:-$NC}
    echo -e "  ${color}${prefix}${NC} ${text}"
}

# Print indented text
# Usage: indent "text" [level]
indent() {
    local text=$1
    local level=${2:-1}
    local spaces=""
    for ((i=0; i<level*2; i++)); do
        spaces+=" "
    done
    echo "${spaces}${text}"
}

# Progress indicator for long operations
# Usage: progress_start "Checking subdomains"
#        progress_update 10 100
#        progress_end
_PROGRESS_ACTIVE=0

progress_start() {
    [[ "$RECON_OUTPUT_FORMAT" == "json" ]] && return 0
    local message=$1
    echo -ne "${CYAN}${message}...${NC} "
    _PROGRESS_ACTIVE=1
}

progress_update() {
    [[ "$RECON_OUTPUT_FORMAT" == "json" ]] && return 0
    [[ $_PROGRESS_ACTIVE -eq 0 ]] && return 0
    local current=$1
    local total=$2
    local percent=$((current * 100 / total))
    echo -ne "\r${CYAN}Progress: ${percent}% (${current}/${total})${NC}    "
}

progress_end() {
    [[ "$RECON_OUTPUT_FORMAT" == "json" ]] && return 0
    [[ $_PROGRESS_ACTIVE -eq 0 ]] && return 0
    echo -e "${GREEN}done${NC}"
    _PROGRESS_ACTIVE=0
}

progress_fail() {
    [[ "$RECON_OUTPUT_FORMAT" == "json" ]] && return 0
    [[ $_PROGRESS_ACTIVE -eq 0 ]] && return 0
    echo -e "${RED}failed${NC}"
    _PROGRESS_ACTIVE=0
}
