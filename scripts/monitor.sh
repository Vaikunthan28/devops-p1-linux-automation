#!/bin/bash
# =============================================================================
# monitor.sh — System Resource Monitor
# Description: Monitors CPU, Memory, and Disk usage.
#              - Triggers Slack alert if any threshold is breached
#              - Writes a metrics JSON file to S3 for the dashboard to read
# Author:      Your Name
# Version:     2.0.0
# Usage:       ./scripts/monitor.sh
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Load configuration
# -----------------------------------------------------------------------------
CONFIG_FILE="$(dirname "$0")/../config/.env"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# -----------------------------------------------------------------------------
# Configuration — override via .env
# -----------------------------------------------------------------------------
CPU_THRESHOLD="${CPU_THRESHOLD:-80}"
MEM_THRESHOLD="${MEM_THRESHOLD:-80}"
DISK_THRESHOLD="${DISK_THRESHOLD:-85}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
LOG_FILE="$LOG_DIR/monitor.log"
ALERT_SCRIPT="$SCRIPT_DIR/slack-alert.sh"

# S3 settings for metrics (dashboard reads these)
S3_BUCKET="${S3_BUCKET:-}"
S3_METRICS_PREFIX="${S3_METRICS_PREFIX:-metrics}"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"

mkdir -p "$LOG_DIR"

# -----------------------------------------------------------------------------
# Globals — populated during checks, used when writing JSON
# -----------------------------------------------------------------------------
CPU_USAGE=0
MEM_PERCENT=0
MEM_USED_MB=0
MEM_TOTAL_MB=0
DISK_JSON="[]"       # JSON array of disk entries
ALERTS_JSON="[]"     # JSON array of alert messages
STATUS="healthy"     # healthy | warning | critical

# -----------------------------------------------------------------------------
# log() — Timestamped logging
# -----------------------------------------------------------------------------
log() {
  local level="$1"
  local message="$2"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# add_alert() — Adds an alert message to the ALERTS_JSON array
#
# Uses a temp file approach to build the JSON array incrementally.
# Avoids complex string manipulation in bash.
# -----------------------------------------------------------------------------
ALERT_MESSAGES=()

add_alert() {
  local message="$1"
  ALERT_MESSAGES+=("$message")
  STATUS="warning"
}

trigger_alert() {
  local message="$1"
  log "ALERT" "$message"
  add_alert "$message"

  if [[ -x "$ALERT_SCRIPT" ]]; then
    "$ALERT_SCRIPT" "$message"
  else
    log "WARN" "Alert script not found: $ALERT_SCRIPT"
  fi
}

# -----------------------------------------------------------------------------
# check_cpu()
# -----------------------------------------------------------------------------
check_cpu() {
  CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'.' -f1)
  log "INFO" "CPU Usage: ${CPU_USAGE}%  (threshold: ${CPU_THRESHOLD}%)"

  if (( CPU_USAGE > CPU_THRESHOLD )); then
    trigger_alert "⚡ HIGH CPU: ${CPU_USAGE}% on $(hostname) — threshold: ${CPU_THRESHOLD}%"
  fi
}

# -----------------------------------------------------------------------------
# check_memory()
# -----------------------------------------------------------------------------
check_memory() {
  MEM_TOTAL_MB=$(free -m | awk '/^Mem:/ {print $2}')
  MEM_USED_MB=$(free -m  | awk '/^Mem:/ {print $3}')
  MEM_PERCENT=$(( MEM_USED_MB * 100 / MEM_TOTAL_MB ))
  log "INFO" "Memory Usage: ${MEM_PERCENT}%  (${MEM_USED_MB}MB / ${MEM_TOTAL_MB}MB)  (threshold: ${MEM_THRESHOLD}%)"

  if (( MEM_PERCENT > MEM_THRESHOLD )); then
    trigger_alert "🧠 HIGH MEMORY: ${MEM_PERCENT}% (${MEM_USED_MB}MB/${MEM_TOTAL_MB}MB) on $(hostname)"
  fi
}

# -----------------------------------------------------------------------------
# check_disk() — Builds a JSON array of disk partition stats
# -----------------------------------------------------------------------------
check_disk() {
  local disk_entries=()
  local usage mount line

  while IFS= read -r line; do
    usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $6}')

    log "INFO" "Disk Usage: ${usage}% on ${mount}  (threshold: ${DISK_THRESHOLD}%)"
    disk_entries+=("{\"mount\":\"${mount}\",\"percent\":${usage}}")

    if (( usage > DISK_THRESHOLD )); then
      trigger_alert "💾 HIGH DISK: ${usage}% on ${mount} on $(hostname)"
    fi
  done < <(df -h | grep '^/dev/' | grep -v 'tmpfs')

  # Build JSON array from collected entries
  local joined
  joined=$(printf '%s,' "${disk_entries[@]}")
  DISK_JSON="[${joined%,}]"
}

# -----------------------------------------------------------------------------
# build_alerts_json() — Converts ALERT_MESSAGES array to a JSON array string
# -----------------------------------------------------------------------------
build_alerts_json() {
  if [[ ${#ALERT_MESSAGES[@]} -eq 0 ]]; then
    ALERTS_JSON="[]"
    return
  fi

  local entries=()
  for msg in "${ALERT_MESSAGES[@]}"; do
    # Escape double quotes in the message
    local escaped="${msg//\"/\\\"}"
    entries+=("\"${escaped}\"")
  done

  local joined
  joined=$(printf '%s,' "${entries[@]}")
  ALERTS_JSON="[${joined%,}]"
}

# -----------------------------------------------------------------------------
# write_metrics_to_s3()
#
# Writes a JSON metrics snapshot to S3 so the dashboard can read it.
# Each node writes to its own file keyed by hostname:
#   s3://bucket/metrics/hostname.json
#
# JSON structure:
# {
#   "hostname": "ip-172-31-xx-xx",
#   "timestamp": "2024-01-15T10:23:01+00:00",
#   "status": "healthy",
#   "cpu": { "percent": 12 },
#   "memory": { "percent": 45, "used_mb": 442, "total_mb": 983 },
#   "disk": [{ "mount": "/", "percent": 28 }],
#   "alerts": []
# }
# -----------------------------------------------------------------------------
write_metrics_to_s3() {
  if [[ -z "$S3_BUCKET" ]]; then
    log "WARN" "S3_BUCKET not set — skipping metrics upload. Dashboard won't show this node."
    return 0
  fi

  if ! command -v aws &> /dev/null; then
    log "WARN" "AWS CLI not installed — skipping metrics upload."
    return 0
  fi

  build_alerts_json

  local hostname
  hostname=$(hostname)
  local timestamp
  timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S+00:00')
  local tmp_file="/tmp/metrics-${hostname}.json"
  local s3_key="${S3_METRICS_PREFIX}/${hostname}.json"

  # Write JSON to temp file
  cat > "$tmp_file" <<EOF
{
  "hostname": "${hostname}",
  "timestamp": "${timestamp}",
  "status": "${STATUS}",
  "cpu": {
    "percent": ${CPU_USAGE},
    "threshold": ${CPU_THRESHOLD}
  },
  "memory": {
    "percent": ${MEM_PERCENT},
    "used_mb": ${MEM_USED_MB},
    "total_mb": ${MEM_TOTAL_MB},
    "threshold": ${MEM_THRESHOLD}
  },
  "disk": ${DISK_JSON},
  "alerts": ${ALERTS_JSON}
}
EOF

  log "INFO" "Uploading metrics → s3://${S3_BUCKET}/${s3_key}"

  if aws s3 cp "$tmp_file" "s3://${S3_BUCKET}/${s3_key}" \
      --region "$AWS_REGION" \
      --no-progress \
      --content-type "application/json"; then
    log "INFO" "Metrics uploaded successfully."
  else
    log "ERROR" "Failed to upload metrics to S3."
  fi

  rm -f "$tmp_file"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  log "INFO" "========== Monitor run started =========="
  check_cpu
  check_memory
  check_disk
  write_metrics_to_s3
  log "INFO" "Status: ${STATUS}"
  log "INFO" "========== Monitor run completed =========="
}

main
