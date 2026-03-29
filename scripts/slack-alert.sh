#!/bin/bash
# =============================================================================
# slack-alert.sh — Slack Webhook Notifier
# Description: Sends a formatted alert message to a Slack channel
#              via an Incoming Webhook URL using Block Kit formatting.
# Author:      Your Name
# Version:     1.0.0
# Usage:       ./scripts/slack-alert.sh "Your alert message here"
# =============================================================================

set -euo pipefail

CONFIG_FILE="$(dirname "$0")/../config/.env"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
fi

SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"Alert message\""
  exit 1
fi

if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
  echo "[ERROR] SLACK_WEBHOOK_URL is not set. Please configure it in config/.env"
  exit 1
fi

MESSAGE="$1"
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')

# -----------------------------------------------------------------------------
# build_payload() — Slack Block Kit JSON
# Rich formatting: header, message, divider, fields for host + time
# -----------------------------------------------------------------------------
build_payload() {
  cat <<EOF
{
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "🚨 DevOps Infrastructure Alert",
        "emoji": true
      }
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Message:* ${MESSAGE}"
      }
    },
    {
      "type": "divider"
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*Host:*\n${HOSTNAME}"
        },
        {
          "type": "mrkdwn",
          "text": "*Time:*\n${TIMESTAMP}"
        }
      ]
    }
  ]
}
EOF
}

# -----------------------------------------------------------------------------
# send_alert()
# curl flags:
#   -s           → silent (no progress bar)
#   -o /dev/null → discard response body
#   -w "%{http_code}" → capture HTTP status code
# -----------------------------------------------------------------------------
send_alert() {
  local payload
  payload=$(build_payload)

  local http_status
  http_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$SLACK_WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    --data "$payload")

  if [[ "$http_status" == "200" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] Slack alert sent (HTTP $http_status)"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] Slack alert failed (HTTP $http_status)"
    exit 1
  fi
}

send_alert
