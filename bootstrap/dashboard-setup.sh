#!/bin/bash
# =============================================================================
# bootstrap/dashboard-setup.sh — Dashboard Server Setup
#
# Description: Sets up the Flask monitoring dashboard on a dedicated EC2.
#              Run this ONCE manually on the server you want to host the UI.
#              Monitoring nodes are set up via user-data.sh instead.
#
# Usage: bash bootstrap/dashboard-setup.sh
# Access: http://<this-server-public-ip>:5000
# =============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DASHBOARD_DIR="$PROJECT_DIR/dashboard"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setting up dashboard server..."

# -----------------------------------------------------------------------------
# Install Python dependencies
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing Python packages..."
cd "$DASHBOARD_DIR"
python3 -m pip install -r requirements.txt --quiet
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Python packages installed."

# -----------------------------------------------------------------------------
# Open port 5000 reminder
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  IMPORTANT: Open port 5000 in your Security Group"
echo "  EC2 → Security Groups → Inbound Rules → Add:"
echo "    Type: Custom TCP"
echo "    Port: 5000"
echo "    Source: My IP (or 0.0.0.0/0 for public access)"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------------
# Start the Flask dashboard
# -----------------------------------------------------------------------------
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting dashboard..."
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Access it at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || hostname):5000"
echo ""

cd "$DASHBOARD_DIR"
python3 app.py
