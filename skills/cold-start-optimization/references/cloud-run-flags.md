# Cloud Run Deploy Flags — Canonical Reference

This document lists every Cloud Run flag used in JoraFlow deployments with its cold-start rationale. Flags appear in both `cloudbuild.yaml` (CI) and `deploy.sh` (manual).

## Compute & Scaling

| Flag | Value | Rationale |
|------|-------|-----------|
| `--cpu` | `1` (deploy.sh) / `4` (cloudbuild.yaml) | 1 vCPU is sufficient for steady-state; CI uses 4 for build parallelism. Production should use 1 to optimize cost. |
| `--memory` | `2Gi` (deploy.sh) / `4Gi` (cloudbuild.yaml) | Must accommodate Node.js heap + Python subprocess + V8 cache. Floor is 1Gi. |
| `--min-instances` | `1` | Keeps one warm instance to eliminate cold starts for baseline traffic. Non-negotiable for production. |
| `--max-instances` | `10` | Upper scaling bound. Each instance handles 5 concurrent requests. |
| `--concurrency` | `5` | Limits parallel requests per instance. Python subprocess is CPU-heavy; higher values risk OOM. |
| `--cpu-boost` | (flag) | Doubles CPU during startup. Cuts cold-start by 30-50%. Always enable. |
| `--no-cpu-throttling` | (flag) | Keeps CPU allocated between requests. Required for in-memory caches (JWT cache, connection pools). |

## Networking

| Flag | Value | Rationale |
|------|-------|-----------|
| `--network` | `joraflow-network` | VPC for private service communication. |
| `--subnet` | `service-subnet` | Subnet within the VPC. |
| `--vpc-egress` | `all-traffic` | Routes all egress through VPC (required for VPC-SC or private Google APIs). |
| `--port` | `8080` | Must match `PORT` env var and `containerPort` in service.yaml. |

## Security & Access

| Flag | Value | Rationale |
|------|-------|-----------|
| `--allow-unauthenticated` | (flag) | Public endpoint — auth handled at application layer (Supabase JWT). |
| `--service-account` | `joraflow2-server@...` | Least-privilege SA with Cloud Tasks + GCS access. |

## Timeouts

| Flag | Value | Rationale |
|------|-------|-----------|
| `--timeout` | `300s` (cloudbuild.yaml) | Max request duration. Sync jobs can take 5-10 min for large mailboxes. |

## Volume Mounts (deploy.sh only)

| Flag | Value | Rationale |
|------|-------|-----------|
| `--add-volume` | `name=email-models,type=cloud-storage,bucket=...` | Mounts GCS bucket for DeBERTa ONNX model at runtime. |
| `--add-volume-mount` | `volume=email-models,mount-path=/app/models` | Model files available at `/app/models/email_classifier/`. |

## Consistency Check

When updating deploy flags, ensure these files stay in sync:
1. `cloudbuild.yaml` — CI/CD pipeline (step 4: gcloud run deploy)
2. `deploy.sh` — Manual/scripted deployment
3. `service.yaml` — Knative service spec (used by some deploy flows)

**Critical flags that must match across all three:**
- `--port` / `containerPort` / `PORT` env var → `8080`
- `--min-instances` → `1` (never `0` in production)
- `--cpu-boost` → always present
- `--concurrency` → `5`
