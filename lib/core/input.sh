#!/usr/bin/env bash
#
# input.sh - Input normalization and validation for recon
#
# Handles various input formats:
#   - URLs with protocols (https://example.com/path)
#   - Domains with/without www prefix
#   - IP addresses (IPv4 and IPv6)
#   - Mixed case inputs
#

# Prevent multiple sourcing
[[ -n "${_RECON_INPUT_LOADED:-}" ]] && return 0
_RECON_INPUT_LOADED=1

# Input type constants
readonly INPUT_TYPE_DOMAIN="domain"
readonly INPUT_TYPE_IPV4="ipv4"
readonly INPUT_TYPE_IPV6="ipv6"
readonly INPUT_TYPE_UNKNOWN="unknown"

# Regex patterns
readonly DOMAIN_REGEX='^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$'
readonly IPV4_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
readonly IPV6_REGEX='^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$|^::([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}$|^[0-9a-fA-F]{1,4}::([0-9a-fA-F]{1,4}:){0,5}[0-9a-fA-F]{1,4}$'

# Normalize input target
# - Strips protocol (http://, https://)
# - Removes trailing slashes and paths
# - Converts to lowercase
# - Removes port numbers
# Usage: normalized=$(normalize_target "https://Example.COM/path/to/page")
normalize_target() {
    local input=$1
    local result

    # Remove leading/trailing whitespace
    result=$(echo "$input" | xargs)

    # Strip protocol
    result=${result#http://}
    result=${result#https://}
    result=${result#ftp://}

    # Remove userinfo (user:pass@)
    result=${result#*@}

    # Remove path, query string, and fragment
    result=${result%%/*}
    result=${result%%\?*}
    result=${result%%#*}

    # Remove port number
    result=${result%%:*}

    # Convert to lowercase
    result=$(echo "$result" | tr '[:upper:]' '[:lower:]')

    # Remove any remaining whitespace
    result=$(echo "$result" | tr -d '[:space:]')

    echo "$result"
}

# Detect input type (domain, ipv4, ipv6)
# Usage: type=$(detect_input_type "example.com")
detect_input_type() {
    local input=$1

    # Check IPv4 first (more specific)
    if [[ $input =~ $IPV4_REGEX ]]; then
        # Validate octet ranges
        IFS='.' read -ra octets <<< "$input"
        local valid=true
        for octet in "${octets[@]}"; do
            if [[ $octet -gt 255 ]]; then
                valid=false
                break
            fi
        done
        if $valid; then
            echo "$INPUT_TYPE_IPV4"
            return 0
        fi
    fi

    # Check IPv6
    if [[ $input =~ $IPV6_REGEX ]]; then
        echo "$INPUT_TYPE_IPV6"
        return 0
    fi

    # Check domain
    if [[ $input =~ $DOMAIN_REGEX ]]; then
        echo "$INPUT_TYPE_DOMAIN"
        return 0
    fi

    echo "$INPUT_TYPE_UNKNOWN"
}

# Validate a domain name
# Usage: if validate_domain "example.com"; then ...
validate_domain() {
    local domain=$1

    # Check regex
    if ! [[ $domain =~ $DOMAIN_REGEX ]]; then
        return 1
    fi

    # Check length constraints
    if [[ ${#domain} -gt 253 ]]; then
        return 1
    fi

    # Check individual label lengths
    IFS='.' read -ra labels <<< "$domain"
    for label in "${labels[@]}"; do
        if [[ ${#label} -gt 63 ]] || [[ ${#label} -eq 0 ]]; then
            return 1
        fi
    done

    return 0
}

# Validate an IPv4 address
# Usage: if validate_ipv4 "192.168.1.1"; then ...
validate_ipv4() {
    local ip=$1

    if ! [[ $ip =~ $IPV4_REGEX ]]; then
        return 1
    fi

    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done

    return 0
}

# Validate an IPv6 address
# Usage: if validate_ipv6 "2001:db8::1"; then ...
validate_ipv6() {
    local ip=$1

    # Basic regex check
    if [[ $ip =~ $IPV6_REGEX ]]; then
        return 0
    fi

    return 1
}

# Validate any target (domain or IP)
# Returns 0 if valid, 1 if invalid
# Usage: if validate_target "example.com"; then ...
validate_target() {
    local target=$1
    local type
    type=$(detect_input_type "$target")

    case "$type" in
        "$INPUT_TYPE_DOMAIN")
            validate_domain "$target"
            ;;
        "$INPUT_TYPE_IPV4")
            validate_ipv4 "$target"
            ;;
        "$INPUT_TYPE_IPV6")
            validate_ipv6 "$target"
            ;;
        *)
            return 1
            ;;
    esac
}

# Check if target is a private/internal IP
# Usage: if is_private_ip "192.168.1.1"; then ...
is_private_ip() {
    local ip=$1
    local type
    type=$(detect_input_type "$ip")

    if [[ "$type" != "$INPUT_TYPE_IPV4" ]]; then
        return 1
    fi

    IFS='.' read -ra octets <<< "$ip"
    local first=${octets[0]}
    local second=${octets[1]}

    # 10.0.0.0/8
    [[ $first -eq 10 ]] && return 0

    # 172.16.0.0/12
    [[ $first -eq 172 ]] && [[ $second -ge 16 ]] && [[ $second -le 31 ]] && return 0

    # 192.168.0.0/16
    [[ $first -eq 192 ]] && [[ $second -eq 168 ]] && return 0

    # 127.0.0.0/8 (loopback)
    [[ $first -eq 127 ]] && return 0

    # 169.254.0.0/16 (link-local)
    [[ $first -eq 169 ]] && [[ $second -eq 254 ]] && return 0

    return 1
}

# Extract the host portion from a URL or authority string
# Strips scheme, userinfo, path, query, fragment, and port
# Usage: host=$(url_host "https://user@example.com:8443/path")
url_host() {
    local url=$1
    url=${url#*://}     # strip scheme
    url=${url#*@}       # strip userinfo
    url=${url%%/*}      # strip path
    url=${url%%\?*}     # strip query
    url=${url%%#*}      # strip fragment
    url=${url%%:*}      # strip port
    echo "$url"
}

# Check whether a host (literal IP or domain) is, or resolves to, a
# private/internal address. Used as an SSRF guard before connecting to
# redirect targets or externally-discovered URLs.
# Returns 0 (true) if private/internal, 1 otherwise.
# Usage: if host_is_private "internal.corp.example"; then ...
host_is_private() {
    local host=$1
    [[ -z "$host" ]] && return 1

    local type
    type=$(detect_input_type "$host")

    case "$type" in
        "$INPUT_TYPE_IPV4")
            is_private_ip "$host"
            return $?
            ;;
        "$INPUT_TYPE_IPV6")
            # Loopback (::1), link-local (fe80::/10), unique-local (fc00::/7)
            case "$host" in
                ::1|[Ff][Ee]8[0-9a-fA-F]:*|[Ff][Ee][9abAB][0-9a-fA-F]:*|[Ff][Cc][0-9a-fA-F][0-9a-fA-F]:*|[Ff][Dd][0-9a-fA-F][0-9a-fA-F]:*)
                    return 0
                    ;;
            esac
            return 1
            ;;
    esac

    # Domain: resolve A records and flag if any point to a private range
    local ips
    ips=$(safe_timeout 5 dig +short "$host" A 2>/dev/null | grep -E '^[0-9.]+$' || true)
    [[ -z "$ips" ]] && return 1

    local ip
    while IFS= read -r ip; do
        [[ -z "$ip" ]] && continue
        if is_private_ip "$ip"; then
            return 0
        fi
    done <<< "$ips"

    return 1
}

# Read targets from a file, one per line
# Normalizes each target and filters invalid ones
# Usage: readarray -t targets < <(read_targets_file "targets.txt")
read_targets_file() {
    local file=$1

    if [[ ! -f "$file" ]]; then
        echo "Error: File not found: $file" >&2
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Normalize and validate
        local normalized
        normalized=$(normalize_target "$line")

        if validate_target "$normalized"; then
            echo "$normalized"
        else
            echo "Warning: Skipping invalid target: $line" >&2
        fi
    done < "$file"
}

# Parse URL and extract components
# Usage: parse_url "https://user:pass@example.com:8080/path?query=1#frag"
# Returns: JSON object with components
parse_url() {
    local url=$1
    local protocol="" userinfo="" host="" port="" path="" query="" fragment=""

    # Extract protocol
    if [[ "$url" =~ ^([a-zA-Z][a-zA-Z0-9+.-]*):// ]]; then
        protocol="${BASH_REMATCH[1]}"
        url="${url#*://}"
    fi

    # Extract fragment
    if [[ "$url" =~ \#(.*)$ ]]; then
        fragment="${BASH_REMATCH[1]}"
        url="${url%#*}"
    fi

    # Extract query
    if [[ "$url" =~ \?(.*)$ ]]; then
        query="${BASH_REMATCH[1]}"
        url="${url%\?*}"
    fi

    # Extract path
    if [[ "$url" =~ /(.*)$ ]]; then
        path="/${BASH_REMATCH[1]}"
        url="${url%%/*}"
    fi

    # Extract userinfo
    if [[ "$url" =~ ^([^@]+)@(.+)$ ]]; then
        userinfo="${BASH_REMATCH[1]}"
        url="${BASH_REMATCH[2]}"
    fi

    # Extract port
    if [[ "$url" =~ :([0-9]+)$ ]]; then
        port="${BASH_REMATCH[1]}"
        url="${url%:*}"
    fi

    # What remains is the host
    host="$url"

    # Output as simple key=value (avoid jq dependency here)
    echo "protocol=$protocol"
    echo "userinfo=$userinfo"
    echo "host=$host"
    echo "port=$port"
    echo "path=$path"
    echo "query=$query"
    echo "fragment=$fragment"
}

# Extract domain from email address
# Usage: domain=$(email_to_domain "user@example.com")
email_to_domain() {
    local email=$1
    echo "${email#*@}"
}

# Get the base/apex domain from a subdomain
# Usage: apex=$(get_apex_domain "www.sub.example.com")
# Note: This is a simple implementation, may not handle all TLDs correctly
get_apex_domain() {
    local domain=$1
    local parts
    IFS='.' read -ra parts <<< "$domain"

    local count=${#parts[@]}

    # Handle common two-part TLDs
    if [[ $count -ge 3 ]]; then
        local tld="${parts[-1]}"
        local sld="${parts[-2]}"

        # Common multi-part TLDs
        case "${sld}.${tld}" in
            co.uk|co.nz|co.za|com.au|com.br|org.uk|net.au)
                if [[ $count -ge 3 ]]; then
                    echo "${parts[-3]}.${sld}.${tld}"
                    return 0
                fi
                ;;
        esac
    fi

    # Default: last two parts
    if [[ $count -ge 2 ]]; then
        echo "${parts[-2]}.${parts[-1]}"
    else
        echo "$domain"
    fi
}
