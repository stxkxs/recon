#!/usr/bin/env bash
#
# progress.sh - Progress tracking for batch processing
#
# Provides visual progress indicators and ETA calculations
#

# Prevent multiple sourcing
[[ -n "${_RECON_BATCH_PROGRESS_LOADED:-}" ]] && return 0
_RECON_BATCH_PROGRESS_LOADED=1

# Progress state
_PROGRESS_TOTAL=0
_PROGRESS_CURRENT=0
_PROGRESS_START_TIME=0
_PROGRESS_LAST_UPDATE=0
_PROGRESS_BAR_WIDTH=40

# Initialize progress tracking
# Usage: progress_init 100
progress_init() {
    local total=$1
    _PROGRESS_TOTAL=$total
    _PROGRESS_CURRENT=0
    _PROGRESS_START_TIME=$(date +%s)
    _PROGRESS_LAST_UPDATE=0
}

# Update progress
# Usage: progress_increment ["target_name"]
progress_increment() {
    local target=${1:-""}
    ((_PROGRESS_CURRENT++)) || true

    # Rate limit updates to avoid excessive output
    local now
    now=$(date +%s)
    if [[ $((now - _PROGRESS_LAST_UPDATE)) -lt 1 ]] && [[ $_PROGRESS_CURRENT -lt $_PROGRESS_TOTAL ]]; then
        return 0
    fi
    _PROGRESS_LAST_UPDATE=$now

    progress_display "$target"
}

# Calculate ETA
# Usage: eta=$(progress_eta)
progress_eta() {
    if [[ $_PROGRESS_CURRENT -eq 0 ]]; then
        echo "calculating..."
        return 0
    fi

    local now
    now=$(date +%s)
    local elapsed=$((now - _PROGRESS_START_TIME))
    local rate
    rate=$(echo "scale=2; $_PROGRESS_CURRENT / $elapsed" | bc 2>/dev/null || echo "0")

    if [[ "$rate" == "0" ]] || [[ -z "$rate" ]]; then
        echo "calculating..."
        return 0
    fi

    local remaining=$((_PROGRESS_TOTAL - _PROGRESS_CURRENT))
    local eta_seconds
    eta_seconds=$(echo "scale=0; $remaining / $rate" | bc 2>/dev/null || echo "0")

    if [[ "$eta_seconds" -lt 60 ]]; then
        echo "${eta_seconds}s"
    elif [[ "$eta_seconds" -lt 3600 ]]; then
        echo "$((eta_seconds / 60))m $((eta_seconds % 60))s"
    else
        echo "$((eta_seconds / 3600))h $((eta_seconds % 3600 / 60))m"
    fi
}

# Display progress bar
# Usage: progress_display ["current_target"]
progress_display() {
    local target=${1:-""}

    [[ "$RECON_OUTPUT_FORMAT" == "json" ]] && return 0

    local percent=0
    if [[ $_PROGRESS_TOTAL -gt 0 ]]; then
        percent=$((_PROGRESS_CURRENT * 100 / _PROGRESS_TOTAL))
    fi

    # Build progress bar
    local filled=$((_PROGRESS_BAR_WIDTH * _PROGRESS_CURRENT / _PROGRESS_TOTAL))
    local empty=$((_PROGRESS_BAR_WIDTH - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done

    # Calculate rate
    local now
    now=$(date +%s)
    local elapsed=$((now - _PROGRESS_START_TIME))
    local rate="0.0"
    if [[ $elapsed -gt 0 ]]; then
        rate=$(printf "%.1f" "$(echo "scale=1; $_PROGRESS_CURRENT / $elapsed" | bc 2>/dev/null || echo "0")")
    fi

    # Get ETA
    local eta
    eta=$(progress_eta)

    # Build status line
    local status
    status=$(printf "\r${CYAN}[%s]${NC} %3d%% (%d/%d) | %.1f/s | ETA: %s" \
        "$bar" "$percent" "$_PROGRESS_CURRENT" "$_PROGRESS_TOTAL" "$rate" "$eta")

    # Add current target if provided
    if [[ -n "$target" ]]; then
        # Truncate target if too long
        if [[ ${#target} -gt 30 ]]; then
            target="${target:0:27}..."
        fi
        status+=" | ${target}"
    fi

    # Clear line and print
    echo -ne "\033[2K${status}"

    # Print newline on completion
    if [[ $_PROGRESS_CURRENT -ge $_PROGRESS_TOTAL ]]; then
        echo ""
    fi
}

# Display final summary
# Usage: progress_summary
progress_summary() {
    [[ "$RECON_OUTPUT_FORMAT" == "json" ]] && return 0

    local now
    now=$(date +%s)
    local elapsed=$((now - _PROGRESS_START_TIME))

    echo ""
    echo -e "${BOLD}Progress Summary:${NC}"
    echo -e "  Total: $_PROGRESS_TOTAL targets"
    echo -e "  Time: $(format_duration $elapsed)"

    if [[ $elapsed -gt 0 ]]; then
        local rate
        rate=$(printf "%.2f" "$(echo "scale=2; $_PROGRESS_TOTAL / $elapsed" | bc 2>/dev/null || echo "0")")
        echo -e "  Rate: ${rate} targets/second"
    fi
}

# Format duration in human readable form
# Usage: formatted=$(format_duration 3661)
format_duration() {
    local seconds=$1

    if [[ $seconds -lt 60 ]]; then
        echo "${seconds}s"
    elif [[ $seconds -lt 3600 ]]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m $((seconds % 60))s"
    fi
}

# Spinner for indeterminate progress
# Usage: spinner_start "message" &
#        spinner_pid=$!
#        # do work
#        spinner_stop $spinner_pid
_SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
_SPINNER_PID=""

spinner_start() {
    local message=${1:-"Processing..."}

    [[ "$RECON_OUTPUT_FORMAT" == "json" ]] && return 0

    (
        local i=0
        while true; do
            local char="${_SPINNER_CHARS:$i:1}"
            echo -ne "\r${CYAN}${char}${NC} ${message}"
            ((i = (i + 1) % ${#_SPINNER_CHARS}))
            sleep 0.1
        done
    ) &
    _SPINNER_PID=$!
}

spinner_stop() {
    local pid=${1:-$_SPINNER_PID}

    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        echo -ne "\r\033[2K"
    fi
    _SPINNER_PID=""
}

# Simple counter display (no bar)
# Usage: counter_display 5 100 "Checking subdomains"
counter_display() {
    local current=$1
    local total=$2
    local message=${3:-"Processing"}

    [[ "$RECON_OUTPUT_FORMAT" == "json" ]] && return 0

    local percent=0
    if [[ $total -gt 0 ]]; then
        percent=$((current * 100 / total))
    fi

    echo -ne "\r${CYAN}${message}:${NC} ${current}/${total} (${percent}%)    "
}

# Complete counter display
counter_complete() {
    [[ "$RECON_OUTPUT_FORMAT" == "json" ]] && return 0
    echo -e "\r\033[2K${GREEN}✓${NC} Complete"
}
