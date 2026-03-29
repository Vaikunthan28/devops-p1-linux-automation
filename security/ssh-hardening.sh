#!/bin/bash
# =============================================================================
# ssh-hardening.sh — SSH Security Hardening
# Description: Hardens SSH config — disables root login, enforces key-only
#              auth, sets idle timeouts, validates config before restart.
# Author:      Your Name
# Version:     1.0.0
# Usage:       sudo ./security/ssh-hardening.sh
# WARNING:     Only run AFTER confirming key-based SSH access works.
#              Locking password auth without a working key = lockout!
# =============================================================================

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "[ERROR] Must run as root: sudo $0"
  exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.backup.$(date '+%Y%m%d_%H%M%S')"
LOG_FILE="/var/log/ssh-hardening.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# backup_config() — Always backup before changes
# -----------------------------------------------------------------------------
backup_config() {
  log "INFO: Backing up $SSHD_CONFIG → $BACKUP_FILE"
  cp "$SSHD_CONFIG" "$BACKUP_FILE"
  log "INFO: To restore: sudo cp $BACKUP_FILE $SSHD_CONFIG"
}

# -----------------------------------------------------------------------------
# set_sshd_option() — Idempotent directive setter
# Replaces existing directive (commented or active), appends if not found.
# Args: $1 = key (e.g. "PermitRootLogin"), $2 = value (e.g. "no")
# -----------------------------------------------------------------------------
set_sshd_option() {
  local key="$1" value="$2"

  if grep -qE "^#?${key}" "$SSHD_CONFIG"; then
    sed -i "s|^#\?${key}.*|${key} ${value}|" "$SSHD_CONFIG"
    log "INFO: Set   ${key} = ${value}"
  else
    echo "${key} ${value}" >> "$SSHD_CONFIG"
    log "INFO: Added ${key} = ${value}"
  fi
}

# -----------------------------------------------------------------------------
# apply_hardening() — CIS Benchmark aligned SSH settings
# -----------------------------------------------------------------------------
apply_hardening() {
  log "INFO: Applying SSH hardening..."

  set_sshd_option "PermitRootLogin"          "no"         # No direct root SSH
  set_sshd_option "PasswordAuthentication"   "no"         # Keys only
  set_sshd_option "PermitEmptyPasswords"     "no"         # No empty passwords
  set_sshd_option "Protocol"                 "2"          # SSHv2 only
  set_sshd_option "ClientAliveInterval"      "300"        # 5 min idle timeout
  set_sshd_option "ClientAliveCountMax"      "2"          # 2 retries then disconnect
  set_sshd_option "MaxAuthTries"             "3"          # 3 attempts max
  set_sshd_option "X11Forwarding"            "no"         # No GUI forwarding
  set_sshd_option "AllowTcpForwarding"       "no"         # No port forwarding
  set_sshd_option "IgnoreRhosts"             "yes"        # Ignore .rhosts
  set_sshd_option "HostbasedAuthentication"  "no"         # No host-based auth

  log "INFO: All settings applied."
}

# -----------------------------------------------------------------------------
# validate_config() — Test syntax BEFORE restarting
# sshd -t = test mode (validates config, doesn't start daemon)
# A bad config + restart = you're locked out. This prevents that.
# -----------------------------------------------------------------------------
validate_config() {
  log "INFO: Validating config syntax..."
  if sshd -t; then
    log "INFO: Config valid."
  else
    log "ERROR: Invalid config — restoring backup..."
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    log "INFO: Backup restored. No changes applied."
    exit 1
  fi
}

restart_ssh() {
  log "INFO: Restarting SSH..."
  systemctl restart sshd
  log "INFO: SSH restarted."
}

print_summary() {
  log "INFO: ============================================"
  log "INFO:  SSH Hardening Summary"
  log "INFO: ============================================"
  log "INFO:  ✅ Root login          → DISABLED"
  log "INFO:  ✅ Password auth       → DISABLED (key-only)"
  log "INFO:  ✅ Idle timeout        → 5 minutes"
  log "INFO:  ✅ Max auth tries      → 3"
  log "INFO:  ✅ X11 + TCP forward   → DISABLED"
  log "INFO:  📄 Backup              → $BACKUP_FILE"
  log "INFO: ============================================"
}

main() {
  log "========== SSH Hardening started =========="
  backup_config
  apply_hardening
  validate_config
  restart_ssh
  print_summary
  log "========== SSH Hardening completed =========="
}

main
