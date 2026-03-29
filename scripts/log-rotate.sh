#!/bin/bash
# =============================================================================
# log-rotate.sh — Log Rotation & Cleanup
# Description: Rotates the monitor log file when it exceeds a size limit.
#              Compresses old logs and deletes logs older than retention days.
# Author:      Your Name
# Version:     1.0.0
# Usage:       ./scripts/log-rotate.sh
# =============================================================================

set -euo pipefail

CONFIG_FILE="$(dirname "$0")/../config/.env"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
LOG_FILE="$LOG_DIR/monitor.log"
ROTATE_LOG="$LOG_DIR/log-rotate.log"

MAX_SIZE_MB="${MAX_LOG_SIZE_MB:-10}"
RETAIN_DAYS="${LOG_RETAIN_DAYS:-30}"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ROTATE_LOG"
}

# -----------------------------------------------------------------------------
# get_file_size_mb() — Returns file size in MB
#   `du -m file` → disk usage in megabytes
# -----------------------------------------------------------------------------
get_file_size_mb() {
  du -m "$1" | awk '{print $1}'
}

# -----------------------------------------------------------------------------
# rotate_log()
# Rotation strategy:
#   monitor.log                    → always the active log name
#   monitor.log.TIMESTAMP          → renamed rotated copy
#   monitor.log.TIMESTAMP.gz       → compressed rotated copy
# Idempotent: only rotates when size limit is exceeded
# -----------------------------------------------------------------------------
rotate_log() {
  if [[ ! -f "$LOG_FILE" ]]; then
    log "INFO: No log file found at $LOG_FILE — nothing to rotate."
    return 0
  fi

  local file_size_mb
  file_size_mb=$(get_file_size_mb "$LOG_FILE")
  log "INFO: Current log size: ${file_size_mb}MB (limit: ${MAX_SIZE_MB}MB)"

  if (( file_size_mb >= MAX_SIZE_MB )); then
    local rotated_file="$LOG_FILE.$(date '+%Y-%m-%d_%H-%M-%S')"
    log "INFO: Rotating log → $rotated_file"
    mv "$LOG_FILE" "$rotated_file"
    gzip "$rotated_file"
    touch "$LOG_FILE"
    log "INFO: Rotation complete: ${rotated_file}.gz"
  else
    log "INFO: Log size within limit. No rotation needed."
  fi
}

# -----------------------------------------------------------------------------
# cleanup_old_logs()
# `find -mtime +N` → files modified more than N days ago
# `-name "*.gz"`   → compressed logs only
# -----------------------------------------------------------------------------
cleanup_old_logs() {
  log "INFO: Cleaning up logs older than ${RETAIN_DAYS} days..."

  local deleted_count=0
  while IFS= read -r old_log; do
    log "INFO: Deleting: $old_log"
    rm -f "$old_log"
    (( deleted_count++ )) || true
  done < <(find "$LOG_DIR" -name "*.gz" -mtime +"$RETAIN_DAYS")

  log "INFO: Deleted ${deleted_count} old log file(s)."
}

main() {
  log "========== Log rotation started =========="
  rotate_log
  cleanup_old_logs
  log "========== Log rotation completed =========="
}

main
