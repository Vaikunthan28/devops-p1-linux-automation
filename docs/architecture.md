# Architecture — P1 Linux & Shell Scripting Automation (v2)

## Overview

A production-grade automation suite that monitors multiple Linux servers,
sends real-time Slack alerts, manages log lifecycle, archives to AWS S3,
and displays a live multi-node web dashboard.

## Full System Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              AWS Account                                │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                    EC2 Monitoring Nodes                        │     │
│  │                                                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐  │     │
│  │  │  Node 1 (bootstrapped via user-data.sh)                  │  │     │
│  │  │  ├── monitor.sh (cron every 5 min)                       │  │     │
│  │  │  │     ├── check_cpu()    → alert if > 80%               │  │     │
│  │  │  │     ├── check_memory() → alert if > 80%               │  │     │
│  │  │  │     ├── check_disk()   → alert if > 85%               │  │     │
│  │  │  │     └── write_metrics_to_s3() → metrics/node1.json    │  │     │
│  │  │  ├── log-rotate.sh (cron daily midnight)                  │  │     │
│  │  │  └── archive-s3.sh (cron weekly Sunday 2am)              │  │     │
│  │  └──────────────────────────────────────────────────────────┘  │     │
│  │                                                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐  │     │
│  │  │  Node 2 (identical config, different hostname)           │  │     │
│  │  │  └── same scripts → metrics/node2.json                   │  │     │
│  │  └──────────────────────────────────────────────────────────┘  │     │
│  │                                                                │     │
│  │  ┌──────────────────────────────────────────────────────────┐  │     │
│  │  │  Node N (scale to 100+ — just launch with user-data.sh)  │  │     │
│  │  └──────────────────────────────────────────────────────────┘  │     │
│  └────────────────────────────────┬───────────────────────────────┘     │
│                                   │ writes JSON                         │
│                                   ▼                                     │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │                        AWS S3 Bucket                           │     │
│  │  ├── metrics/                                                  │     │
│  │  │   ├── node1-hostname.json   ← current metrics per node     │     │
│  │  │   ├── node2-hostname.json                                   │     │
│  │  │   └── nodeN-hostname.json                                   │     │
│  │  └── p1-logs/                                                  │     │
│  │      └── hostname/YYYY-MM/*.log.gz  ← archived logs           │     │
│  └──────────────────────┬─────────────────────────────────────────┘     │
│                         │ reads every 30s                               │
│                         ▼                                               │
│  ┌────────────────────────────────────────────────────────────────┐     │
│  │              EC2 Dashboard Server                              │     │
│  │  Flask app (port 5000)                                         │     │
│  │  ├── GET /          → renders index.html                       │     │
│  │  ├── GET /api/nodes → reads all metrics/*.json from S3         │     │
│  │  └── GET /health    → health check endpoint                    │     │
│  └────────────────────────────────────────────────────────────────┘     │
│                         │                                               │
└─────────────────────────┼───────────────────────────────────────────────┘
                          │ HTTP browser
                          ▼
              ┌───────────────────────┐
              │   Browser Dashboard   │
              │  Live multi-node UI   │
              │  Auto-refreshes 30s   │
              └───────────────────────┘

                          │ alert (threshold breached)
                          ▼
              ┌───────────────────────┐
              │      Slack Channel    │
              │  Rich Block Kit alert │
              └───────────────────────┘
```

## Component Responsibilities

| Component | Type | Trigger | Responsibility |
|-----------|------|---------|----------------|
| `monitor.sh` | Script | Cron 5 min | Check CPU/mem/disk, alert, write S3 JSON |
| `slack-alert.sh` | Script | Called by monitor | Send Block Kit alert to Slack |
| `log-rotate.sh` | Script | Cron daily | Compress monitor.log when > size limit |
| `archive-s3.sh` | Script | Cron weekly | Upload old .gz logs to S3 |
| `ssh-hardening.sh` | Script | Manual once | Lock down SSH on new nodes |
| `user-data.sh` | Bootstrap | EC2 launch | Auto-configure any new node |
| `dashboard-setup.sh` | Bootstrap | Manual once | Install and start Flask dashboard |
| `app.py` | Flask app | HTTP requests | Read S3 metrics, serve dashboard |
| `index.html` | Frontend | Browser | Live multi-node monitoring UI |

## Scaling Model

```
Launch 1 node:    paste user-data.sh in EC2 console → done
Launch 100 nodes: use AWS Auto Scaling Group with same user-data.sh → done
```

Each node:
1. Self-configures on first boot (no SSH needed)
2. Writes metrics to its own S3 key (`metrics/hostname.json`)
3. Dashboard auto-discovers all nodes by listing `metrics/` in S3

## Security Decisions

| Decision | Reason |
|----------|--------|
| No secrets in scripts or code | All credentials in `config/.env` (gitignored) |
| IAM role on EC2 for S3 access | No access keys stored on instances |
| `set -euo pipefail` everywhere | Fail fast, no silent errors |
| SSH hardening script | CIS-aligned, idempotent, validates before restart |
| S3 STANDARD_IA for archives | Cost-optimised for infrequent-access data |
| Node stale detection (10 min) | Dashboard flags nodes that stop reporting |

## Evolution Path (P6 — Ansible)

> In P6, `user-data.sh` is replaced with Ansible playbooks.
> The scripts themselves don't change — only the delivery mechanism does.

```
P1 (now):  user-data.sh → bootstrap on launch
P6 (later): ansible-playbook site.yml -i inventory → manage 100+ nodes
```

This is a common real-world pattern: start with User Data for simplicity,
migrate to Ansible as the fleet grows and configuration management needs increase.
