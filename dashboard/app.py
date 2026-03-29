#!/usr/bin/env python3
"""
dashboard/app.py — Multi-Node Monitoring Dashboard
Description: Flask web app that reads metrics JSON files from S3
             and displays a live dashboard for all monitored nodes.
Author:      Your Name
Version:     1.0.0
Usage:       python3 app.py
             Then open http://<your-ec2-ip>:5000 in your browser
"""

import os
import json
import logging
from datetime import datetime, timezone
from flask import Flask, render_template, jsonify
import boto3
from botocore.exceptions import ClientError, NoCredentialsError
from dotenv import load_dotenv

# ---------------------------------------------------------------------------
# Load environment variables from config/.env
# ---------------------------------------------------------------------------
env_path = os.path.join(os.path.dirname(__file__), '..', 'config', '.env')
load_dotenv(env_path)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
S3_BUCKET          = os.getenv('S3_BUCKET', '')
S3_METRICS_PREFIX  = os.getenv('S3_METRICS_PREFIX', 'metrics')
AWS_REGION         = os.getenv('AWS_REGION', 'ap-southeast-2')
DASHBOARD_PORT     = int(os.getenv('DASHBOARD_PORT', 5000))
REFRESH_INTERVAL   = int(os.getenv('DASHBOARD_REFRESH_SECONDS', 30))

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Flask app
# ---------------------------------------------------------------------------
app = Flask(__name__)

# ---------------------------------------------------------------------------
# S3 client — uses IAM role on EC2 automatically (no keys needed)
# ---------------------------------------------------------------------------
try:
    s3_client = boto3.client('s3', region_name=AWS_REGION)
    logger.info(f"S3 client initialised — region: {AWS_REGION}")
except Exception as e:
    logger.error(f"Failed to initialise S3 client: {e}")
    s3_client = None


def get_all_node_metrics() -> list[dict]:
    """
    Reads all metrics JSON files from S3 and returns them as a list.

    How it works:
      1. Lists all objects in s3://bucket/metrics/
      2. Downloads each .json file
      3. Parses and enriches each with a 'last_seen_seconds' field
      4. Returns sorted list (critical first, then warning, then healthy)

    Returns:
        list of node metric dicts, or empty list on error
    """
    if not s3_client or not S3_BUCKET:
        logger.warning("S3 not configured — returning empty node list")
        return []

    nodes = []

    try:
        # List all metric files in the prefix
        response = s3_client.list_objects_v2(
            Bucket=S3_BUCKET,
            Prefix=f"{S3_METRICS_PREFIX}/"
        )

        if 'Contents' not in response:
            logger.info("No metric files found in S3 yet.")
            return []

        for obj in response['Contents']:
            key = obj['Key']
            if not key.endswith('.json'):
                continue

            try:
                # Download and parse each node's metrics file
                file_response = s3_client.get_object(Bucket=S3_BUCKET, Key=key)
                raw = file_response['Body'].read().decode('utf-8')
                metrics = json.loads(raw)

                # Calculate how many seconds ago this node last reported
                metrics['last_seen_seconds'] = _seconds_since(metrics.get('timestamp', ''))
                metrics['last_seen_label']   = _format_last_seen(metrics['last_seen_seconds'])

                # Mark node as stale if it hasn't reported in 10+ minutes
                if metrics['last_seen_seconds'] > 600:
                    metrics['status'] = 'stale'

                nodes.append(metrics)
                logger.info(f"Loaded metrics for: {metrics.get('hostname', key)}")

            except (json.JSONDecodeError, KeyError) as e:
                logger.error(f"Failed to parse metrics file {key}: {e}")
                continue

    except (ClientError, NoCredentialsError) as e:
        logger.error(f"S3 access error: {e}")
        return []

    # Sort: critical → warning → stale → healthy
    status_order = {'critical': 0, 'warning': 1, 'stale': 2, 'healthy': 3}
    nodes.sort(key=lambda n: status_order.get(n.get('status', 'healthy'), 99))

    return nodes


def _seconds_since(timestamp_str: str) -> int:
    """
    Calculates how many seconds have passed since the given ISO timestamp.

    Args:
        timestamp_str: ISO 8601 string e.g. "2024-01-15T10:23:01+00:00"

    Returns:
        Number of seconds elapsed, or 9999 if the timestamp can't be parsed
    """
    try:
        ts = datetime.fromisoformat(timestamp_str)
        now = datetime.now(timezone.utc)
        return int((now - ts).total_seconds())
    except (ValueError, TypeError):
        return 9999


def _format_last_seen(seconds: int) -> str:
    """
    Converts elapsed seconds to a human-readable string.

    Examples:
        30  → "30s ago"
        90  → "1m 30s ago"
        3700 → "1h 1m ago"
    """
    if seconds > 3600:
        h = seconds // 3600
        m = (seconds % 3600) // 60
        return f"{h}h {m}m ago"
    elif seconds > 60:
        m = seconds // 60
        s = seconds % 60
        return f"{m}m {s}s ago"
    else:
        return f"{seconds}s ago"


def get_summary(nodes: list[dict]) -> dict:
    """
    Calculates fleet-wide summary statistics.

    Args:
        nodes: list of node metric dicts

    Returns:
        dict with total, healthy, warning, critical, stale counts
        and average CPU/memory across healthy nodes
    """
    total    = len(nodes)
    healthy  = sum(1 for n in nodes if n.get('status') == 'healthy')
    warning  = sum(1 for n in nodes if n.get('status') == 'warning')
    critical = sum(1 for n in nodes if n.get('status') == 'critical')
    stale    = sum(1 for n in nodes if n.get('status') == 'stale')

    active_nodes = [n for n in nodes if n.get('status') in ('healthy', 'warning', 'critical')]
    avg_cpu = 0
    avg_mem = 0
    if active_nodes:
        avg_cpu = round(sum(n.get('cpu', {}).get('percent', 0) for n in active_nodes) / len(active_nodes))
        avg_mem = round(sum(n.get('memory', {}).get('percent', 0) for n in active_nodes) / len(active_nodes))

    return {
        'total':    total,
        'healthy':  healthy,
        'warning':  warning,
        'critical': critical,
        'stale':    stale,
        'avg_cpu':  avg_cpu,
        'avg_mem':  avg_mem,
    }


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route('/')
def index():
    """Renders the main dashboard page."""
    return render_template(
        'index.html',
        refresh_interval=REFRESH_INTERVAL
    )


@app.route('/api/nodes')
def api_nodes():
    """
    JSON API endpoint — called by the dashboard every REFRESH_INTERVAL seconds.

    Returns:
        JSON with nodes list and summary stats
    """
    nodes = get_all_node_metrics()
    summary = get_summary(nodes)

    return jsonify({
        'nodes':      nodes,
        'summary':    summary,
        'fetched_at': datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC'),
        'bucket':     S3_BUCKET,
    })


@app.route('/health')
def health():
    """Health check endpoint — useful for load balancer checks."""
    return jsonify({'status': 'ok', 'service': 'devops-p1-dashboard'})


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if __name__ == '__main__':
    if not S3_BUCKET:
        logger.warning("S3_BUCKET is not set in config/.env — dashboard will show no nodes")
    logger.info(f"Starting dashboard on port {DASHBOARD_PORT}")
    logger.info(f"Reading metrics from s3://{S3_BUCKET}/{S3_METRICS_PREFIX}/")
    app.run(host='0.0.0.0', port=DASHBOARD_PORT, debug=False)
