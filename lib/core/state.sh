#!/usr/bin/env bash
#
# state.sh - State management for recon
#
# Handles checkpoint/resume functionality for batch processing:
# - Checkpoint files to track progress
# - Lock files to prevent concurrent runs
# - Resume capability for interrupted batches
#

# Prevent multiple sourcing
[[ -n "${_RECON_STATE_LOADED:-}" ]] && return 0
_RECON_STATE_LOADED=1

# Default state directory
STATE_DIR="${RECON_STATE_DIR:-${HOME}/.local/share/recon/state}"

# Initialize state directory
state_init() {
    local dir="${1:-$STATE_DIR}"
    ensure_dir "$dir" || return 1
    STATE_DIR="$dir"
}

# Generate a checkpoint filename for a batch
# Usage: checkpoint_file=$(state_checkpoint_file "batch_id")
state_checkpoint_file() {
    local batch_id=$1
    echo "${STATE_DIR}/checkpoint_${batch_id}.json"
}

# Generate a lock filename for a batch
# Usage: lock_file=$(state_lock_file "batch_id")
state_lock_file() {
    local batch_id=$1
    echo "${STATE_DIR}/lock_${batch_id}"
}

# Create a new checkpoint
# Usage: state_create_checkpoint "batch_id" "targets_file" ["target1" "target2" ...]
state_create_checkpoint() {
    local batch_id=$1
    local targets_file=$2
    shift 2
    local targets=("$@")

    local checkpoint_file
    checkpoint_file=$(state_checkpoint_file "$batch_id")

    local checkpoint
    checkpoint=$(jq -n \
        --arg id "$batch_id" \
        --arg file "$targets_file" \
        --arg started "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '{
            batch_id: $id,
            targets_file: $file,
            started_at: $started,
            updated_at: $started,
            total: 0,
            completed: 0,
            failed: 0,
            targets: [],
            completed_targets: [],
            failed_targets: []
        }')

    # Add targets
    local targets_json='[]'
    for target in "${targets[@]}"; do
        targets_json=$(echo "$targets_json" | jq --arg t "$target" '. += [$t]')
    done

    checkpoint=$(echo "$checkpoint" | jq --argjson t "$targets_json" '.targets = $t | .total = ($t | length)')

    echo "$checkpoint" > "$checkpoint_file"
    echo "$checkpoint_file"
}

# Load existing checkpoint
# Usage: checkpoint_json=$(state_load_checkpoint "batch_id")
state_load_checkpoint() {
    local batch_id=$1

    local checkpoint_file
    checkpoint_file=$(state_checkpoint_file "$batch_id")

    if [[ -f "$checkpoint_file" ]]; then
        cat "$checkpoint_file"
    else
        return 1
    fi
}

# Update checkpoint with completed target
# Usage: state_mark_completed "batch_id" "target"
state_mark_completed() {
    local batch_id=$1
    local target=$2

    local checkpoint_file
    checkpoint_file=$(state_checkpoint_file "$batch_id")

    if [[ ! -f "$checkpoint_file" ]]; then
        return 1
    fi

    local checkpoint
    checkpoint=$(cat "$checkpoint_file")

    checkpoint=$(echo "$checkpoint" | jq \
        --arg target "$target" \
        --arg updated "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '.completed_targets += [$target] |
         .completed = (.completed + 1) |
         .updated_at = $updated')

    echo "$checkpoint" > "$checkpoint_file"
}

# Update checkpoint with failed target
# Usage: state_mark_failed "batch_id" "target" "error_message"
state_mark_failed() {
    local batch_id=$1
    local target=$2
    local error_msg=${3:-"unknown error"}

    local checkpoint_file
    checkpoint_file=$(state_checkpoint_file "$batch_id")

    if [[ ! -f "$checkpoint_file" ]]; then
        return 1
    fi

    local checkpoint
    checkpoint=$(cat "$checkpoint_file")

    checkpoint=$(echo "$checkpoint" | jq \
        --arg target "$target" \
        --arg error "$error_msg" \
        --arg updated "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '.failed_targets += [{target: $target, error: $error}] |
         .failed = (.failed + 1) |
         .updated_at = $updated')

    echo "$checkpoint" > "$checkpoint_file"
}

# Get remaining targets from checkpoint
# Usage: readarray -t remaining < <(state_get_remaining "batch_id")
state_get_remaining() {
    local batch_id=$1

    local checkpoint
    checkpoint=$(state_load_checkpoint "$batch_id") || return 1

    # Get all targets minus completed and failed
    echo "$checkpoint" | jq -r '
        .targets as $all |
        .completed_targets as $completed |
        (.failed_targets | map(.target)) as $failed |
        $all | map(select(. as $t | ($completed + $failed) | index($t) | not)) | .[]'
}

# Check if checkpoint exists and has remaining work
# Usage: if state_has_remaining "batch_id"; then ...
state_has_remaining() {
    local batch_id=$1

    local remaining
    remaining=$(state_get_remaining "$batch_id" 2>/dev/null | wc -l)
    [[ "$remaining" -gt 0 ]]
}

# Finalize checkpoint (mark as complete)
# Usage: state_finalize_checkpoint "batch_id"
state_finalize_checkpoint() {
    local batch_id=$1

    local checkpoint_file
    checkpoint_file=$(state_checkpoint_file "$batch_id")

    if [[ ! -f "$checkpoint_file" ]]; then
        return 1
    fi

    local checkpoint
    checkpoint=$(cat "$checkpoint_file")

    checkpoint=$(echo "$checkpoint" | jq \
        --arg finished "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        '.finished_at = $finished | .status = "completed"')

    echo "$checkpoint" > "$checkpoint_file"
}

# Acquire batch lock
# Usage: if state_acquire_lock "batch_id"; then ...
state_acquire_lock() {
    local batch_id=$1
    local timeout=${2:-10}

    local lock_file
    lock_file=$(state_lock_file "$batch_id")

    acquire_lock "$lock_file" "$timeout"
}

# Release batch lock
# Usage: state_release_lock "batch_id"
state_release_lock() {
    local batch_id=$1

    local lock_file
    lock_file=$(state_lock_file "$batch_id")

    release_lock "$lock_file"
}

# Check if batch is locked
# Usage: if state_is_locked "batch_id"; then ...
state_is_locked() {
    local batch_id=$1

    local lock_file
    lock_file=$(state_lock_file "$batch_id")

    if command -v flock &>/dev/null; then
        # Try non-blocking lock
        exec 200>"$lock_file"
        if flock -n 200 2>/dev/null; then
            # Got lock, release it
            exec 200>&-
            return 1
        else
            return 0
        fi
    else
        # Simple fallback
        [[ -d "${lock_file}.lock" ]]
    fi
}

# List all checkpoints
# Usage: state_list_checkpoints
state_list_checkpoints() {
    if [[ ! -d "$STATE_DIR" ]]; then
        return 0
    fi

    for file in "${STATE_DIR}"/checkpoint_*.json; do
        [[ -f "$file" ]] || continue

        local checkpoint
        checkpoint=$(cat "$file")

        local batch_id
        batch_id=$(echo "$checkpoint" | jq -r '.batch_id')
        local total
        total=$(echo "$checkpoint" | jq -r '.total')
        local completed
        completed=$(echo "$checkpoint" | jq -r '.completed')
        local failed
        failed=$(echo "$checkpoint" | jq -r '.failed')
        local status
        status=$(echo "$checkpoint" | jq -r '.status // "in_progress"')

        echo "$batch_id|$completed/$total|$failed failed|$status"
    done
}

# Clean old checkpoints
# Usage: state_cleanup [days]
state_cleanup() {
    local days=${1:-7}

    if [[ ! -d "$STATE_DIR" ]]; then
        return 0
    fi

    # Find and remove old checkpoint files
    find "$STATE_DIR" -name "checkpoint_*.json" -mtime +"$days" -delete 2>/dev/null || true

    # Remove orphaned lock directories
    for lock in "${STATE_DIR}"/lock_*.lock; do
        [[ -d "$lock" ]] || continue
        # Remove if older than 1 day (stale locks)
        find "$lock" -maxdepth 0 -mtime +1 -exec rmdir {} \; 2>/dev/null || true
    done
}

# Get checkpoint progress as percentage
# Usage: progress=$(state_get_progress "batch_id")
state_get_progress() {
    local batch_id=$1

    local checkpoint
    checkpoint=$(state_load_checkpoint "$batch_id") || return 1

    local total
    total=$(echo "$checkpoint" | jq -r '.total')
    local completed
    completed=$(echo "$checkpoint" | jq -r '.completed')
    local failed
    failed=$(echo "$checkpoint" | jq -r '.failed')

    if [[ "$total" -eq 0 ]]; then
        echo "0"
        return 0
    fi

    local processed=$((completed + failed))
    local percent=$((processed * 100 / total))
    echo "$percent"
}
