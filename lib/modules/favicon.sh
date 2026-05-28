#!/usr/bin/env bash
#
# favicon.sh - Favicon hash fingerprinting module for recond
#
# Fetches a target's favicon and computes hashes for fingerprinting:
# MD5 hash for general identification and MurmurHash3 (Shodan-compatible)
# for cross-referencing hosts on Shodan by favicon hash.
#

# Prevent multiple sourcing
[[ -n "${_RECOND_MODULE_FAVICON_LOADED:-}" ]] && return 0
_RECOND_MODULE_FAVICON_LOADED=1

# Module info
MODULE_FAVICON_NAME="favicon"
MODULE_FAVICON_DESCRIPTION="Favicon hash fingerprinting"

# Run favicon hash fingerprinting
# Usage: favicon_run "example.com"
# Output: JSON object with favicon hash results
favicon_run() {
    local target=$1
    local timeout
    timeout=$(get_timeout "favicon" 2>/dev/null || echo "10")

    local tmp_file="/tmp/recon_favicon_$$"
    local favicon_url="https://$target/favicon.ico"
    local found=false

    # Step 1: Try fetching favicon from /favicon.ico
    safe_timeout "$timeout" curl -s -L --max-time "$timeout" -o "$tmp_file" "$favicon_url" 2>/dev/null || true

    # Check if file exists and is non-empty
    if [[ ! -s "$tmp_file" ]]; then
        # Try fetching the main page and looking for a <link> tag with favicon
        local html
        html=$(safe_timeout "$timeout" curl -s -L --max-time "$timeout" "https://$target" 2>/dev/null || true)

        if [[ -n "$html" ]]; then
            # Look for <link rel="icon" or <link rel="shortcut icon"
            local alt_href
            alt_href=$(echo "$html" | grep -ioE '<link[^>]+(rel="(icon|shortcut icon)")[^>]*>' | head -1 | grep -ioE 'href="[^"]*"' | head -1 | sed 's/href="//;s/"$//' || true)

            if [[ -n "$alt_href" ]]; then
                # Handle relative URLs
                case "$alt_href" in
                    http://*|https://*)
                        favicon_url="$alt_href"
                        ;;
                    //*)
                        favicon_url="https:$alt_href"
                        ;;
                    /*)
                        favicon_url="https://$target$alt_href"
                        ;;
                    *)
                        favicon_url="https://$target/$alt_href"
                        ;;
                esac

                safe_timeout "$timeout" curl -s -L --max-time "$timeout" -o "$tmp_file" "$favicon_url" 2>/dev/null || true
            fi
        fi
    fi

    # Check again if we have a valid favicon file
    if [[ -s "$tmp_file" ]]; then
        found=true
    fi

    if [[ "$found" == "false" ]]; then
        # Clean up temp file
        rm -f "$tmp_file" 2>/dev/null || true

        jq -n '{
            found: false,
            url: "",
            hashes: {mmh3: "", md5: ""},
            hash_method: "",
            shodan_query: "",
            shodan_url: ""
        }'
        return 0
    fi

    # Step 2: Compute hashes
    local md5_hash=""
    if command -v md5sum &>/dev/null; then
        md5_hash=$(md5sum "$tmp_file" | awk '{print $1}')
    elif command -v md5 &>/dev/null; then
        md5_hash=$(md5 -q "$tmp_file")
    fi

    local mmh3_hash=""
    if command -v python3 &>/dev/null && python3 -c "import mmh3" 2>/dev/null; then
        # Shodan-compatible: mmh3.hash(base64.encodebytes(raw_bytes))
        # base64.encodebytes adds newlines every 76 chars, matching Shodan's method
        mmh3_hash=$(python3 -c "
import mmh3, base64, sys
with open(sys.argv[1], 'rb') as f:
    print(mmh3.hash(base64.encodebytes(f.read())))
" "$tmp_file" 2>/dev/null || echo "")
    fi

    # Clean up temp file
    rm -f "$tmp_file" 2>/dev/null || true

    # Step 3: Determine hash method and build Shodan query
    local hash_method=""
    local shodan_query=""
    local shodan_url=""

    if [[ -n "$mmh3_hash" ]] && [[ -n "$md5_hash" ]]; then
        hash_method="mmh3+md5"
    elif [[ -n "$md5_hash" ]]; then
        hash_method="md5"
    fi

    if [[ -n "$mmh3_hash" ]]; then
        shodan_query="http.favicon.hash:$mmh3_hash"
        shodan_url="https://www.shodan.io/search?query=http.favicon.hash:$mmh3_hash"
    fi

    jq -n \
        --argjson found true \
        --arg url "$favicon_url" \
        --arg mmh3 "$mmh3_hash" \
        --arg md5 "$md5_hash" \
        --arg hash_method "$hash_method" \
        --arg shodan_query "$shodan_query" \
        --arg shodan_url "$shodan_url" \
        '{
            found: $found,
            url: $url,
            hashes: {mmh3: $mmh3, md5: $md5},
            hash_method: $hash_method,
            shodan_query: $shodan_query,
            shodan_url: $shodan_url
        }'
}

# Terminal output for favicon hash results
# Usage: favicon_print "$json_result" "example.com"
favicon_print() {
    local json=$1
    local target=$2

    header "FAVICON HASH - $target"

    local found
    found=$(echo "$json" | jq -r '.found')

    if [[ "$found" != "true" ]]; then
        warn "No favicon found for $target"
        return 0
    fi

    local url
    url=$(echo "$json" | jq -r '.url // empty')
    if [[ -n "$url" ]]; then
        success "Favicon URL: $url"
    fi

    local md5_hash
    md5_hash=$(echo "$json" | jq -r '.hashes.md5 // empty')
    if [[ -n "$md5_hash" ]]; then
        info "MD5: $md5_hash"
    fi

    local mmh3_hash
    mmh3_hash=$(echo "$json" | jq -r '.hashes.mmh3 // empty')
    if [[ -n "$mmh3_hash" ]]; then
        info "MurmurHash3 (Shodan): $mmh3_hash"
    fi

    local shodan_url
    shodan_url=$(echo "$json" | jq -r '.shodan_url // empty')
    if [[ -n "$shodan_url" ]]; then
        subheader "Shodan Search"
        success "URL: $shodan_url"
    fi

    local hash_method
    hash_method=$(echo "$json" | jq -r '.hash_method // empty')
    if [[ -n "$hash_method" ]]; then
        info "Hash method: $hash_method"
    fi
}

# Check if favicon module can run
# Returns 0 if dependencies are met
favicon_check() {
    check_dependencies curl jq
}
