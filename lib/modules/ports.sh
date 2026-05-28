#!/usr/bin/env bash
#
# ports.sh - TCP port scanning module for recond
#
# Checks common service ports using /dev/tcp or nc:
# - Web servers (80, 443, 8080, 8443)
# - Mail (25, 465, 587, 993, 995)
# - Remote access (22, 3389)
# - Databases (3306, 5432, 6379, 27017)
# - Other services (21, 53, 9200, 9300)
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_PORTS_LOADED:-}" ]] && return 0
_RECOND_MODULE_PORTS_LOADED=1

# Module info
MODULE_PORTS_NAME="ports"
MODULE_PORTS_DESCRIPTION="TCP port scanning"

# Common ports to scan with service names
declare -A PORT_SERVICES=(
    [21]="ftp"
    [22]="ssh"
    [25]="smtp"
    [53]="dns"
    [80]="http"
    [110]="pop3"
    [143]="imap"
    [443]="https"
    [465]="smtps"
    [587]="submission"
    [993]="imaps"
    [995]="pop3s"
    [3306]="mysql"
    [3389]="rdp"
    [5432]="postgresql"
    [6379]="redis"
    [8080]="http-alt"
    [8443]="https-alt"
    [9200]="elasticsearch"
    [27017]="mongodb"
)

# Default ports to scan (ordered by likelihood)
DEFAULT_PORTS=(80 443 22 8080 8443 21 25 53 110 143 465 587 993 995 3306 3389 5432 6379 9200 27017)

# Check if a single TCP port is open
# Usage: port_check "example.com" 443
# Returns: 0 if open, 1 if closed/filtered
port_check() {
    local host=$1
    local port=$2
    local timeout=${3:-2}

    # Background the connection attempt and race it against a sleep timer.
    # /dev/tcp hangs indefinitely on filtered ports without this.
    # Must use bash -c explicitly since /dev/tcp is a bash built-in.
    bash -c "echo >/dev/tcp/$host/$port" &>/dev/null &
    local pid=$!
    (sleep "$timeout" && kill "$pid" 2>/dev/null) &
    local killer=$!
    wait "$pid" 2>/dev/null
    local result=$?
    kill "$killer" 2>/dev/null
    wait "$killer" 2>/dev/null
    return $result
}

# Grab banner from an open port
# Usage: banner=$(port_grab_banner "example.com" 22)
port_grab_banner() {
    local host=$1
    local port=$2
    local timeout=${3:-3}

    local banner=""

    # Use nc if available for banner grabbing
    if command -v nc &>/dev/null; then
        banner=$(echo "" | safe_timeout "$timeout" nc -w "$timeout" "$host" "$port" 2>/dev/null | head -1 | tr -d '\r\n' | head -c 128 || true)
    fi

    echo "$banner"
}

# Run port scan
# Usage: ports_run "example.com"
# Output: JSON object with port scan results
ports_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "ports" 2>/dev/null || echo "2")

    local result_json
    result_json=$(jq -n '{
        open: [],
        closed: [],
        total_scanned: 0
    }')

    local open_json='[]'
    local closed_json='[]'
    local scanned=0

    for port in "${DEFAULT_PORTS[@]}"; do
        ((scanned++))

        if port_check "$target" "$port" "$timeout"; then
            local service="${PORT_SERVICES[$port]:-unknown}"

            # Try banner grab on interesting ports
            local banner=""
            case "$port" in
                22|21|25|110|143|587)
                    banner=$(port_grab_banner "$target" "$port" "$timeout")
                    ;;
            esac

            local entry
            if [[ -n "$banner" ]]; then
                entry=$(jq -n \
                    --argjson port "$port" \
                    --arg service "$service" \
                    --arg banner "$banner" \
                    '{port: $port, service: $service, state: "open", banner: $banner}')
            else
                entry=$(jq -n \
                    --argjson port "$port" \
                    --arg service "$service" \
                    '{port: $port, service: $service, state: "open", banner: null}')
            fi

            open_json=$(echo "$open_json" | jq --argjson e "$entry" '. += [$e]')
        else
            closed_json=$(echo "$closed_json" | jq --argjson p "$port" '. += [$p]')
        fi
    done

    result_json=$(echo "$result_json" | jq \
        --argjson open "$open_json" \
        --argjson closed "$closed_json" \
        --argjson scanned "$scanned" \
        '.open = $open | .closed = $closed | .total_scanned = $scanned')

    echo "$result_json"
}

# Terminal output for port scan results
# Usage: ports_print "$json_result" "example.com"
ports_print() {
    local json=$1
    local target=${2:-""}

    header "PORT SCAN - ${target}"

    local open_count
    open_count=$(echo "$json" | jq '.open | length')
    local total
    total=$(echo "$json" | jq '.total_scanned')

    if [[ "$open_count" -gt 0 ]]; then
        printf "  ${BOLD}%-8s %-15s %-8s %s${NC}\n" "PORT" "SERVICE" "STATE" "BANNER"
        echo "  ────── ─────────────── ──────── ────────────────────"

        echo "$json" | jq -r '.open[] | "\(.port)|\(.service)|\(.state)|\(.banner // "")"' | while IFS='|' read -r port service state banner; do
            if [[ -n "$banner" ]]; then
                printf "  ${GREEN}%-8s${NC} %-15s %-8s ${DIM}%s${NC}\n" "$port" "$service" "$state" "${banner:0:40}"
            else
                printf "  ${GREEN}%-8s${NC} %-15s %-8s\n" "$port" "$service" "$state"
            fi
        done

        echo ""
        echo -e "  ${CYAN}$open_count open ports found (scanned $total)${NC}"
    else
        info "No open ports found (scanned $total)"
    fi
}

# Check if ports module can run
ports_check() {
    # /dev/tcp is a bash built-in, always available in bash 4+
    return 0
}
