#!/usr/bin/env bash
#
# common.sh - Shared utilities for recond
#
# Provides: color definitions, logging functions, dependency checking,
#           and common utility functions used across all modules.
#

# Prevent multiple sourcing
[[ -n "${_RECOND_COMMON_LOADED:-}" ]] && return 0
_RECOND_COMMON_LOADED=1

# Version
readonly RECOND_VERSION="2.1.0"

# Colors for output (auto-detect terminal support or force with RECOND_COLOR=always)
if [[ -t 1 ]] || [[ "${RECOND_COLOR:-auto}" == "always" ]]; then
    if [[ "${RECOND_COLOR:-auto}" == "never" ]]; then
        _USE_COLOR=false
    else
        _USE_COLOR=true
    fi
else
    _USE_COLOR=false
fi

if $_USE_COLOR; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly MAGENTA='\033[0;35m'
    readonly BOLD='\033[1m'
    readonly DIM='\033[2m'
    readonly NC='\033[0m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly CYAN=''
    readonly MAGENTA=''
    readonly BOLD=''
    readonly DIM=''
    readonly NC=''
fi

# Output format (terminal or json)
RECOND_OUTPUT_FORMAT="${RECOND_OUTPUT_FORMAT:-terminal}"

# Logging functions for terminal output
header() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    echo -e "\n${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

subheader() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    echo -e "\n${CYAN}─── $1 ───${NC}\n"
}

success() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    echo -e "${GREEN}✓${NC} $1"
}

info() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    echo -e "${YELLOW}→${NC} $1"
}

warn() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    echo -e "${YELLOW}⚠${NC} $1" >&2
}

error() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    echo -e "${RED}✗${NC} $1" >&2
}

debug() {
    [[ "${RECOND_DEBUG:-}" != "1" ]] && return 0
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    echo -e "${DIM}[DEBUG] $1${NC}" >&2
}

# Print banner
print_banner() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    echo -e "${BOLD}${GREEN}"
    cat <<'BANNER'
                                     _
 _ __   ___   ___   ___   _ __    __| |
| '__| / _ \ / __| / _ \ | '_ \  / _` |
| |   |  __/| (__ | (_) || | | || (_| |
|_|    \___| \___| \___/ |_| |_| \__,_|
BANNER
    echo -e "${NC}"
    echo -e "  ${DIM}infrastructure reconnaissance toolkit${NC} ${BOLD}v${RECOND_VERSION}${NC}"
}

# Check for required tools
# Usage: check_dependencies dig curl openssl
check_dependencies() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -ne 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        return 1
    fi
    return 0
}

# Check for optional tools and return which are available
# Usage: available=$(check_optional_tools subfinder httpx shodan)
check_optional_tools() {
    local available=()
    for cmd in "$@"; do
        if command -v "$cmd" &>/dev/null; then
            available+=("$cmd")
        fi
    done
    echo "${available[*]}"
}

# Generate a unique run ID
# Format: YYYYMMDD-HHMMSS-XXXXXX
generate_run_id() {
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    local random_suffix
    random_suffix=$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "${timestamp}-${random_suffix}"
}

# Get ISO 8601 timestamp
get_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Safe timeout wrapper (handles missing timeout command)
safe_timeout() {
    local seconds=$1
    shift
    if command -v timeout &>/dev/null; then
        timeout "$seconds" "$@"
    elif command -v gtimeout &>/dev/null; then
        gtimeout "$seconds" "$@"
    else
        # Fallback: just run without timeout
        "$@"
    fi
}

# Acquire a lock file (for batch processing)
# Usage: acquire_lock /path/to/lockfile
acquire_lock() {
    local lockfile=$1
    local timeout=${2:-10}

    if command -v flock &>/dev/null; then
        exec 200>"$lockfile"
        flock -w "$timeout" 200 || return 1
    else
        # Simple fallback using mkdir
        local attempts=0
        while [[ $attempts -lt $timeout ]]; do
            if mkdir "${lockfile}.lock" 2>/dev/null; then
                trap "rmdir '${lockfile}.lock' 2>/dev/null" EXIT
                return 0
            fi
            sleep 1
            ((attempts++))
        done
        return 1
    fi
}

# Release a lock file
release_lock() {
    local lockfile=$1
    if command -v flock &>/dev/null; then
        exec 200>&-
    else
        rmdir "${lockfile}.lock" 2>/dev/null || true
    fi
}

# Ensure directory exists
ensure_dir() {
    local dir=$1
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir" || {
            error "Failed to create directory: $dir"
            return 1
        }
    fi
}

# Get the script's base directory
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -L "$source" ]]; do
        local dir
        dir=$(cd -P "$(dirname "$source")" && pwd)
        source=$(readlink "$source")
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

# Trim whitespace from string
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

# Join array elements with delimiter
# Usage: join_by ',' "${array[@]}"
join_by() {
    local d=${1-} f=${2-}
    if shift 2; then
        printf %s "$f" "${@/#/$d}"
    fi
}
