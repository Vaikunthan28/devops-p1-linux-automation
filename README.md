# 🖥️ P1 — Linux & Shell Scripting Automation

![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20Ubuntu%2022.04-orange?logo=linux)
![Shell](https://img.shields.io/badge/Shell-Bash%205.x-green?logo=gnu-bash)
![Python](https://img.shields.io/badge/Python-3.10+-blue?logo=python)
![AWS](https://img.shields.io/badge/AWS-S3%20%7C%20EC2-yellow?logo=amazon-aws)
![Flask](https://img.shields.io/badge/Flask-3.0-lightgrey?logo=flask)
![License](https://img.shields.io/badge/License-MIT-blue)

> **DevOps Project 1 of 12** — A production-grade Linux automation suite that monitors multiple servers, sends real-time Slack alerts, manages log lifecycle, archives to AWS S3, and displays a live multi-node web dashboard.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Adding More Nodes](#adding-more-nodes)
- [Dashboard](#dashboard)
- [Configuration](#configuration)
- [Security](#security)

---

## Overview

| Problem | Solution |
|---------|----------|
| How do I know when any server is struggling? | `monitor.sh` checks CPU/mem/disk every 5 min on every node |
| How do I see all my servers at once? | Live web dashboard reads real-time metrics from S3 |
| How do I scale to 100 servers without manual setup? | EC2 User Data auto-configures every new node on launch |
| How do I prevent logs filling the disk? | `log-rotate.sh` compresses and rotates logs daily |
| How do I retain logs cheaply? | `archive-s3.sh` moves old logs to S3 STANDARD_IA weekly |
| How do I harden a new server's SSH? | `ssh-hardening.sh` applies CIS-aligned config in one command |

**Runs on:** AWS EC2 (Ubuntu 22.04 LTS)

---

## Features

- ✅ **Multi-node monitoring** — Any number of EC2 instances, each self-reporting
- ✅ **Live web dashboard** — Real-time view of all nodes, auto-refreshes every 30s
- ✅ **Slack alerts** — Rich Block Kit notifications on threshold breach
- ✅ **Zero-touch node setup** — EC2 User Data bootstraps any node automatically
- ✅ **Log rotation** — Compress logs when they exceed a configurable size
- ✅ **S3 archiving** — Upload old logs to S3, delete local copies
- ✅ **SSH hardening** — CIS-aligned SSH security in one script
- ✅ **Stale node detection** — Dashboard flags nodes silent for 10+ minutes
- ✅ **Fully configurable** — All thresholds and settings via `.env`
- ✅ **Idempotent** — All scripts are safe to run multiple times

---

## Architecture

```
EC2 Node 1 ──▶ metrics/node1.json ──▶ ┐
EC2 Node 2 ──▶ metrics/node2.json ──▶ ├──▶ S3 Bucket ──▶ Dashboard (Flask)
EC2 Node N ──▶ metrics/nodeN.json ──▶ ┘
                                              │
                  threshold breach?           ▼
                        │              Browser (live UI)
                        ▼
                  Slack Alert
```

See [`docs/architecture.md`](docs/architecture.md) for the full system diagram.

---

## Project Structure

```
devops-p1-linux-automation/
├── scripts/
│   ├── monitor.sh          # CPU / Memory / Disk checks + S3 metrics write
│   ├── slack-alert.sh      # Slack Block Kit webhook notifications
│   ├── log-rotate.sh       # Log compression and rotation
│   └── archive-s3.sh       # Archive old logs to AWS S3
├── dashboard/
│   ├── app.py              # Flask app — reads S3 metrics, serves UI
│   ├── templates/
│   │   └── index.html      # Live multi-node monitoring dashboard
│   └── requirements.txt    # Python dependencies
├── bootstrap/
│   ├── user-data.sh        # EC2 launch script — auto-configures any node
│   └── dashboard-setup.sh  # One-time setup for the dashboard server
├── security/
│   └── ssh-hardening.sh    # SSH lockdown (CIS-aligned)
├── cron/
│   └── crontab.example     # Cron schedule (auto-installed by user-data.sh)
├── config/
│   └── .env.example        # All config variables documented
├── docs/
│   └── architecture.md     # Full system diagram + design decisions
├── logs/                   # Runtime logs (gitignored)
├── .gitignore
└── README.md
```

---

## Prerequisites

- AWS account with an EC2 IAM role that has:
  - `s3:PutObject` — for nodes to write metrics
  - `s3:GetObject`, `s3:ListBucket` — for dashboard to read metrics
- An S3 bucket (create one named `your-devops-logs-bucket`)
- A Slack workspace with an Incoming Webhook URL

---

## Quick Start

### 1. Fork & clone this repo

```bash
git clone https://github.com/YOUR_USERNAME/devops-p1-linux-automation.git
cd devops-p1-linux-automation
```

### 2. Launch EC2 monitoring nodes (repeat for each node)

1. Go to **EC2 → Launch Instance**
2. Choose **Ubuntu 22.04 LTS**, `t2.micro`
3. Attach an **IAM role** with S3 access
4. Under **Advanced Details → User Data**, paste `bootstrap/user-data.sh`
5. **Update the config variables at the top of user-data.sh** before pasting
6. Launch — the node configures itself automatically ✅

### 3. Launch the dashboard server

On a dedicated EC2 (or your existing node):

```bash
# Clone repo
git clone https://github.com/YOUR_USERNAME/devops-p1-linux-automation.git
cd devops-p1-linux-automation

# Configure
cp config/.env.example config/.env
nano config/.env   # Set S3_BUCKET and other values

# Start dashboard (opens port 5000)
bash bootstrap/dashboard-setup.sh
```

Open `http://<dashboard-ec2-public-ip>:5000` in your browser.

---

## Adding More Nodes

Scaling is zero-touch — just launch a new EC2 with the same `user-data.sh`:

```
Launch EC2 with user-data.sh
         ↓
Node self-configures in ~2 minutes
         ↓
Node appears in dashboard automatically
```

To scale to 100 nodes: use an **AWS Auto Scaling Group** with the same User Data.
This is the foundation that gets replaced with **Ansible** in Project 6.

---

## Dashboard

The live dashboard shows all reporting nodes with:

- **Status badge** — Healthy / Warning / Critical / Stale
- **CPU, Memory, Disk gauges** with colour-coded progress bars
- **Active alerts** highlighted per node
- **Last seen** — how recently each node reported
- **Fleet summary** — total nodes, health breakdown, average CPU/memory
- **Auto-refresh** every 30 seconds

> Stale = node hasn't reported in 10+ minutes (crashed, stopped, or network issue)

---

## Configuration

All configuration in `config/.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `SLACK_WEBHOOK_URL` | — | Slack Incoming Webhook URL |
| `CPU_THRESHOLD` | `80` | Alert threshold % |
| `MEM_THRESHOLD` | `80` | Alert threshold % |
| `DISK_THRESHOLD` | `85` | Alert threshold % |
| `S3_BUCKET` | — | S3 bucket name (required) |
| `S3_METRICS_PREFIX` | `metrics` | S3 prefix for node metrics JSON |
| `S3_PREFIX` | `p1-logs` | S3 prefix for archived logs |
| `AWS_REGION` | `ap-southeast-2` | AWS region (Sydney) |
| `MAX_LOG_SIZE_MB` | `10` | Rotate log when it exceeds this |
| `LOG_RETAIN_DAYS` | `30` | Delete old compressed logs after N days |
| `ARCHIVE_DAYS` | `7` | Archive .gz files older than N days |
| `DASHBOARD_PORT` | `5000` | Dashboard server port |
| `DASHBOARD_REFRESH_SECONDS` | `30` | Dashboard auto-refresh interval |

---

## Security

- **No secrets in code** — all credentials in `config/.env` (gitignored)
- **IAM roles** — EC2 instances use roles, not access keys
- **`set -euo pipefail`** — all scripts fail fast on errors
- **Idempotent SSH hardening** — safe to re-run
- **Config validation** — `sshd -t` check before SSH restart
- **S3 STANDARD_IA** — cost-optimised archival storage

---

## Part of the DevOps Portfolio Series

| # | Project | Tech |
|---|---------|------|
| **P1** | **Linux & Shell Scripting Automation** ← *You are here* | Bash, Flask, S3 |
| P2 | Git Workflows & Branching Strategies | Git, GitHub |
| P3 | Containerise Everything | Docker, Compose |
| P4 | CI/CD Pipeline | GitHub Actions, ECS |
| P5 | Infrastructure as Code | Terraform, AWS |
| P6 | Configuration Management | Ansible |
| P7 | Kubernetes Core | k8s, kind |
| P8 | Kubernetes on EKS | EKS, Helm |
| P9 | GitOps with ArgoCD | ArgoCD, Flux |
| P10 | Observability Stack | Prometheus, Grafana |
| P11 | DevSecOps | Trivy, OPA, Checkov |
| P12 | Platform Engineering Capstone | Backstage, Crossplane |
