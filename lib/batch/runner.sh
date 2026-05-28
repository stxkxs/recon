#!/usr/bin/env bash
#
# runner.sh - Batch processing orchestration for recond
#
# Handles running reconnaissance against multiple targets:
# - Parallel execution with xargs
# - Progress tracking
# - Checkpoint/resume support
#

# Prevent multiple sourcing
[[ -n "${_RECOND_BATCH_RUNNER_LOADED:-}" ]] && return 0
_RECOND_BATCH_RUNNER_LOADED=1

# Process a single target (called by xargs)
# Usage: batch_process_target "target" "batch_id" "output_dir" "modules"
batch_process_target() {
    local target=$1
    local batch_id=$2
    local output_dir=$3
    local modules=$4

    # Determine script location for sourcing
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    # Source required libraries (if not already loaded)
    source "${script_dir}/lib/core/common.sh" 2>/dev/null || true
    source "${script_dir}/lib/core/config.sh" 2>/dev/null || true
    source "${script_dir}/lib/core/input.sh" 2>/dev/null || true
    source "${script_dir}/lib/core/output.sh" 2>/dev/null || true
    source "${script_dir}/lib/core/state.sh" 2>/dev/null || true

    # Normalize target
    local normalized
    normalized=$(normalize_target "$target")

    # Generate output filename
    local safe_target
    safe_target=$(echo "$normalized" | tr '/:' '_')
    local output_file="${output_dir}/${safe_target}.json"

    # Run recond (this should call the main recond function)
    # For now, we'll call the bin/recond script
    local result
    if result=$("${script_dir}/bin/recond" --json ${modules:+--modules "$modules"} "$normalized" 2>&1); then
        echo "$result" > "$output_file"
        state_mark_completed "$batch_id" "$target" 2>/dev/null || true
        echo "OK: $target"
    else
        state_mark_failed "$batch_id" "$target" "$result" 2>/dev/null || true
        echo "FAIL: $target"
    fi
}

# Export function for xargs
export -f batch_process_target 2>/dev/null || true

# Run batch processing
# Usage: batch_run "targets_file" [options]
batch_run() {
    local targets_file=$1
    local parallel=${2:-4}
    local output_dir=${3:-"./results"}
    local modules=${4:-""}
    local resume=${5:-false}

    # Validate targets file
    if [[ ! -f "$targets_file" ]]; then
        error "Targets file not found: $targets_file"
        return 1
    fi

    # Initialize state
    state_init || return 1

    # Generate batch ID
    local batch_id
    batch_id=$(basename "$targets_file" | sed 's/\.[^.]*$//')_$(date '+%Y%m%d_%H%M%S')

    # Ensure output directory exists
    ensure_dir "$output_dir" || return 1

    # Read and normalize targets
    local targets=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        local normalized
        normalized=$(normalize_target "$line")
        if validate_target "$normalized"; then
            targets+=("$normalized")
        else
            warn "Skipping invalid target: $line"
        fi
    done < "$targets_file"

    local total=${#targets[@]}

    if [[ $total -eq 0 ]]; then
        error "No valid targets found in file"
        return 1
    fi

    # Check for resume
    if [[ "$resume" == "true" ]]; then
        # Find latest checkpoint for this file
        local latest_checkpoint=""
        for cp_file in "${STATE_DIR}"/checkpoint_$(basename "$targets_file" | sed 's/\.[^.]*$//')_*.json; do
            [[ -f "$cp_file" ]] || continue
            latest_checkpoint="$cp_file"
        done

        if [[ -n "$latest_checkpoint" ]]; then
            batch_id=$(jq -r '.batch_id' "$latest_checkpoint")
            info "Resuming batch: $batch_id"

            # Get remaining targets
            readarray -t targets < <(state_get_remaining "$batch_id")
            total=${#targets[@]}

            if [[ $total -eq 0 ]]; then
                success "Batch already complete"
                return 0
            fi

            info "Remaining targets: $total"
        fi
    else
        # Create new checkpoint
        state_create_checkpoint "$batch_id" "$targets_file" "${targets[@]}" >/dev/null
    fi

    # Try to acquire lock
    if ! state_acquire_lock "$batch_id" 5; then
        error "Another batch process is running for this file"
        return 1
    fi

    # Ensure lock is released on exit
    trap 'state_release_lock "$batch_id"' EXIT

    info "Starting batch: $batch_id"
    info "Total targets: $total"
    info "Parallel workers: $parallel"
    info "Output directory: $output_dir"

    # Get script directory for xargs
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    # Run batch with xargs
    # Note: Using a helper script approach for better portability
    local helper_script
    helper_script=$(mktemp)
    chmod +x "$helper_script"

    cat > "$helper_script" << 'HELPER_EOF'
#!/usr/bin/env bash
target=$1
batch_id=$2
output_dir=$3
modules=$4
script_dir=$5

# Normalize target
normalized=$(echo "$target" | tr '[:upper:]' '[:lower:]' | sed 's|^https\?://||' | sed 's|/.*||')

# Generate output filename
safe_target=$(echo "$normalized" | tr '/:' '_')
output_file="${output_dir}/${safe_target}.json"

# Run recond
if result=$("${script_dir}/bin/recond" --json ${modules:+--modules "$modules"} "$normalized" 2>&1); then
    echo "$result" > "$output_file"
    echo "OK: $target"
else
    echo "FAIL: $target - $result" >&2
fi
HELPER_EOF

    # Process targets
    local completed=0
    local failed=0

    printf '%s\n' "${targets[@]}" | xargs -P "$parallel" -I {} bash "$helper_script" {} "$batch_id" "$output_dir" "$modules" "$script_dir" 2>&1 | while read -r line; do
        if [[ "$line" == OK:* ]]; then
            ((completed++)) || true
            local target="${line#OK: }"
            state_mark_completed "$batch_id" "$target" 2>/dev/null || true
            echo -e "${GREEN}✓${NC} $target"
        elif [[ "$line" == FAIL:* ]]; then
            ((failed++)) || true
            local target="${line#FAIL: }"
            target="${target%% -*}"
            state_mark_failed "$batch_id" "$target" 2>/dev/null || true
            echo -e "${RED}✗${NC} $target"
        fi

        # Show progress
        local processed=$((completed + failed))
        if [[ $((processed % 10)) -eq 0 ]]; then
            local percent=$((processed * 100 / total))
            echo -e "${CYAN}Progress: ${processed}/${total} (${percent}%)${NC}"
        fi
    done

    # Cleanup
    rm -f "$helper_script"

    # Finalize checkpoint
    state_finalize_checkpoint "$batch_id"

    # Summary
    echo ""
    header "BATCH COMPLETE"
    info "Batch ID: $batch_id"
    info "Total: $total"

    local checkpoint
    checkpoint=$(state_load_checkpoint "$batch_id")
    local final_completed
    final_completed=$(echo "$checkpoint" | jq -r '.completed')
    local final_failed
    final_failed=$(echo "$checkpoint" | jq -r '.failed')

    success "Completed: $final_completed"
    [[ "$final_failed" -gt 0 ]] && error "Failed: $final_failed"

    info "Results saved to: $output_dir"

    # Release lock
    state_release_lock "$batch_id"
    trap - EXIT

    return 0
}

# List recent batches
batch_list() {
    header "RECENT BATCHES"

    state_init 2>/dev/null || true

    local found=false
    while IFS='|' read -r batch_id progress failed status; do
        [[ -z "$batch_id" ]] && continue
        found=true
        echo -e "  ${BOLD}$batch_id${NC}"
        echo -e "    Progress: $progress"
        echo -e "    Failed: $failed"
        echo -e "    Status: $status"
        echo ""
    done < <(state_list_checkpoints)

    if ! $found; then
        info "No batch history found"
    fi
}

# Resume most recent interrupted batch
batch_resume() {
    state_init 2>/dev/null || return 1

    # Find most recent incomplete batch
    local latest=""
    local latest_file=""

    for file in "${STATE_DIR}"/checkpoint_*.json; do
        [[ -f "$file" ]] || continue

        local status
        status=$(jq -r '.status // "in_progress"' "$file")

        if [[ "$status" != "completed" ]]; then
            latest_file="$file"
            latest=$(jq -r '.batch_id' "$file")
        fi
    done

    if [[ -z "$latest" ]]; then
        info "No interrupted batches found"
        return 0
    fi

    info "Found interrupted batch: $latest"

    local targets_file
    targets_file=$(jq -r '.targets_file' "$latest_file")

    if [[ ! -f "$targets_file" ]]; then
        error "Original targets file not found: $targets_file"
        return 1
    fi

    # Get settings from checkpoint or use defaults
    local parallel
    parallel=$(config_get "batch.max_parallel" "4")

    local output_dir
    output_dir=$(config_get "global.output_dir" "./results")

    batch_run "$targets_file" "$parallel" "$output_dir" "" true
}
