#!/bin/bash
# =============================================================================
# archive-s3.sh — Archive Old Logs to AWS S3
# Description: Finds compressed log files older than ARCHIVE_DAYS, uploads
#              them to S3 (STANDARD_IA storage), then deletes local copies.
# Author:      Your Name
# Version:     1.0.0
# Usage:       ./scripts/archive-s3.sh
# Prerequisites: AWS CLI + IAM role with s3:PutObject on your bucket
# =============================================================================

set -euo pipefail

CONFIG_FILE="$(dirname "$0")/../config/.env"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/logs}"
ARCHIVE_LOG="$LOG_DIR/archive-s3.log"

S3_BUCKET="${S3_BUCKET:-}"
S3_PREFIX="${S3_PREFIX:-p1-logs}"
ARCHIVE_DAYS="${ARCHIVE_DAYS:-7}"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$ARCHIVE_LOG"
}

# -----------------------------------------------------------------------------
# preflight_checks() — Validate tools and config before proceeding
# -----------------------------------------------------------------------------
preflight_checks() {
  if ! command -v aws &> /dev/null; then
    log "ERROR: AWS CLI not installed. Run: sudo apt install awscli -y"
    exit 1
  fi

  if [[ -z "$S3_BUCKET" ]]; then
    log "ERROR: S3_BUCKET not set in config/.env"
    exit 1
  fi

  if ! aws s3 ls "s3://$S3_BUCKET" --region "$AWS_REGION" &> /dev/null; then
    log "ERROR: Cannot access s3://$S3_BUCKET — check IAM role or credentials."
    exit 1
  fi

  log "INFO: Preflight checks passed."
}

# -----------------------------------------------------------------------------
# upload_to_s3()
# S3 key: prefix/hostname/YYYY-MM/filename.gz
# --storage-class STANDARD_IA → cheaper for infrequently accessed archives
# -----------------------------------------------------------------------------
upload_to_s3() {
  local file="$1"
  local filename
  filename=$(basename "$file")
  local s3_key="${S3_PREFIX}/$(hostname)/$(date '+%Y-%m')/${filename}"

  log "INFO: Uploading $filename → s3://${S3_BUCKET}/${s3_key}"

  if aws s3 cp "$file" "s3://${S3_BUCKET}/${s3_key}" \
      --storage-class STANDARD_IA \
      --region "$AWS_REGION" \
      --no-progress; then
    log "INFO: Upload successful."
    return 0
  else
    log "ERROR: Upload failed for $file"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# archive_old_logs() — Main archive loop
# Finds .gz files older than ARCHIVE_DAYS, uploads, then deletes local copy
# -----------------------------------------------------------------------------
archive_old_logs() {
  local archived=0 failed=0

  log "INFO: Searching for logs older than ${ARCHIVE_DAYS} days..."

  while IFS= read -r log_file; do
    log "INFO: Found: $log_file"
    if upload_to_s3 "$log_file"; then
      rm -f "$log_file"
      log "INFO: Local copy deleted: $log_file"
      (( archived++ )) || true
    else
      (( failed++ )) || true
    fi
  done < <(find "$LOG_DIR" -name "*.gz" -mtime +"$ARCHIVE_DAYS")

  log "INFO: Archive complete — Uploaded: ${archived}, Failed: ${failed}"
  (( failed > 0 )) && exit 1 || true
}

main() {
  log "========== S3 Archive started =========="
  preflight_checks
  archive_old_logs
  log "========== S3 Archive completed =========="
}

main
