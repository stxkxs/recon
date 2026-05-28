#!/usr/bin/env bash
#
# ui.sh - Enhanced terminal UI with optional Charm/gum integration
#
# Uses gum (https://github.com/charmbracelet/gum) when available
# for spinners, styled output, and interactive prompts.
# Falls back to plain output when gum is not installed.
#

# Prevent multiple sourcing
[[ -n "${_RECOND_UI_LOADED:-}" ]] && return 0
_RECOND_UI_LOADED=1

# Check if gum is available
_HAS_GUM=false
if command -v gum &>/dev/null; then
    _HAS_GUM=true
fi

# Check if gum should be used (not in JSON mode, gum available)
_use_gum() {
    $_HAS_GUM && [[ "$RECOND_OUTPUT_FORMAT" != "json" ]]
}

# ─── Styled Banner ───
# Print the banner using gum style if available
ui_banner() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0

    if _use_gum; then
        gum style \
            --foreground 2 \
            --bold \
            --margin "0 1" \
            "  _ __ ___  ___ ___  _ __" \
            " | '__/ _ \/ __/ _ \| '_ \\" \
            " | | |  __/ (_| (_) | | | |" \
            " |_|  \___|\___\___/|_| |_|"
        gum style \
            --foreground 8 \
            --margin "0 2" \
            "infrastructure reconnaissance toolkit v${RECOND_VERSION}"
    else
        print_banner
    fi
}

# ─── Styled Headers ───
ui_header() {
    local title=$1
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0

    if _use_gum; then
        echo ""
        gum style \
            --foreground 4 \
            --bold \
            --border double \
            --border-foreground 4 \
            --padding "0 2" \
            --margin "0 1" \
            "$title"
        echo ""
    else
        header "$title"
    fi
}

ui_subheader() {
    local title=$1
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0

    if _use_gum; then
        echo ""
        gum style \
            --foreground 6 \
            --italic \
            --margin "0 2" \
            "── $title ──"
        echo ""
    else
        subheader "$title"
    fi
}

# ─── Spinners ───
# Run a command with a spinner
# Usage: ui_spin "Scanning ports..." ports_run "$target"
# Returns: The command's stdout (spinner goes to stderr)
ui_spin() {
    local message=$1
    shift

    if _use_gum; then
        gum spin --spinner dot --title "$message" -- "$@"
    else
        # Fallback: just show message and run
        echo -ne "${CYAN}${message}${NC} " >&2
        local result
        result=$("$@" 2>/dev/null)
        echo -e "${GREEN}done${NC}" >&2
        echo "$result"
    fi
}

# ─── Tables ───
# Print data as a formatted table using gum
# Usage: ui_table "PORT,SERVICE,STATE" "80,http,open" "443,https,open"
ui_table() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0

    local header=$1
    shift

    if _use_gum; then
        {
            echo "$header"
            for row in "$@"; do
                echo "$row"
            done
        } | gum table --border rounded
    else
        # Simple fallback table
        echo "  $header" | tr ',' '\t'
        echo "  $(echo "$header" | sed 's/[^,]/-/g; s/,/\t/g')"
        for row in "$@"; do
            echo "  $(echo "$row" | tr ',' '\t')"
        done
    fi
}

# ─── Log Messages ───
ui_log_info() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    if _use_gum; then
        gum log --level info "$1"
    else
        info "$1"
    fi
}

ui_log_warn() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    if _use_gum; then
        gum log --level warn "$1"
    else
        warn "$1"
    fi
}

ui_log_error() {
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    if _use_gum; then
        gum log --level error "$1"
    else
        error "$1"
    fi
}

ui_log_debug() {
    [[ "${RECOND_DEBUG:-}" != "1" ]] && return 0
    [[ "$RECOND_OUTPUT_FORMAT" == "json" ]] && return 0
    if _use_gum; then
        gum log --level debug "$1"
    else
        debug "$1"
    fi
}

# ─── Interactive Prompts ───
# Choose modules interactively
# Usage: selected=$(ui_choose_modules)
ui_choose_modules() {
    if _use_gum; then
        gum choose --no-limit --height 12 \
            --header "Select modules to run:" \
            --selected "dns,subdomain,ssl,http" \
            "dns" "subdomain" "ssl" "http" "whois" "files" "tech" "ports" "cors"
    else
        echo "dns subdomain ssl http whois files tech"
    fi
}

# Confirm an action
# Usage: if ui_confirm "Run full scan?"; then ...
ui_confirm() {
    local message=$1
    if _use_gum; then
        gum confirm "$message"
    else
        read -rp "$message [y/N] " response
        [[ "$response" =~ ^[Yy]$ ]]
    fi
}

# ─── Format Output ───
# Format text as styled output
# Usage: ui_format "# Heading\nSome **bold** text"
ui_format() {
    local text=$1
    if _use_gum; then
        echo "$text" | gum format
    else
        echo -e "$text"
    fi
}

# ─── Progress with gum spin ───
# Wrap a module run with a spinner
# Usage: result=$(ui_module_run "DNS Enumeration" dns_run "$target")
ui_module_run() {
    local label=$1
    local func=$2
    local target=$3

    if _use_gum && [[ "$RECOND_OUTPUT_FORMAT" != "json" ]]; then
        local result
        result=$(gum spin --spinner dot --title "  $label..." -- bash -c "$func '$target'" 2>/dev/null)
        echo "$result"
    else
        $func "$target"
    fi
}

# Print gum availability status
ui_status() {
    if $_HAS_GUM; then
        local gum_version
        gum_version=$(gum --version 2>/dev/null | head -1)
        echo "gum: available ($gum_version)"
    else
        echo "gum: not installed (install with: brew install gum)"
    fi
}
