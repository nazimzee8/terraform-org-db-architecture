---
name: cold-start-optimization
description: Minimize Cloud Run cold-start time and container latency for JoraFlow's Node.js + Python sync server; use when modifying the Dockerfile, service.yaml, cloudbuild.yaml, deploy.sh, start.sh, or any container-startup code path.
---
# Cold-Start Optimization

## Overview
Apply these rules whenever touching the container build pipeline, Cloud Run service configuration, or application startup code paths. The goal is to keep the **time-to-first-request** under 2 seconds on a warm instance and under 5 seconds on a cold start, without introducing dependency or module errors.

Source: [3 Ways to Optimize Cloud Run Response Times](https://cloud.google.com/blog/topics/developers-practitioners/3-ways-optimize-cloud-run-response-times) and [General Cloud Run Tips](https://cloud.google.com/run/docs/tips/general).

---

## Pillar 1 — Lean Container Image

### Base Image Selection
- Final stage **must** use `python:3.11-slim-bookworm` (current baseline). Never switch to `alpine` for the Python stage — musl libc causes silent C-extension failures with `google-api-python-client` and `pydantic`.
- Node.js is copied as a single static binary from `node:22-slim`; do **not** install the full Node.js runtime in the final stage.

### Multi-Stage Build Discipline
The Dockerfile uses a **three-stage** build. Respect stage boundaries:

| Stage | Base | Purpose | Artifacts Copied Forward |
|-------|------|---------|--------------------------|
| `python-deps` | `python:3.11-slim-bookworm` | Compile Python wheels | `/build/site-packages` |
| `node-deps` | `node:22-slim` | npm install + esbuild bundle | `server/bundle.cjs` (~1-2 MB) |
| Final | `python:3.11-slim-bookworm` | Runtime only | Python packages, bundled server, `scraping_engine.py` |

**Rules:**
- Never copy `node_modules/` into the final stage. The esbuild bundle (`bundle.cjs`) replaces it entirely.
- Never install `build-essential`, `gcc`, or other compilers in the final stage.
- Keep `apt-get install` in the final stage limited to: `libstdc++6` (Node.js runtime dep), `ca-certificates`, `curl` (health-check probe).
- Always chain `apt-get update && apt-get install && rm -rf /var/lib/apt/lists/*` in a single `RUN` to avoid layer bloat.

### Layer Ordering (Cache Optimization)
Order COPY instructions from least-frequently-changed to most-frequently-changed:
1. `requirements.txt` / `package.server.json` (dependency manifests — rarely change)
2. `server/sync-server.js` (server source)
3. `src/scraping_engine.py` (scraping engine)
4. `start.sh` (entrypoint)

Reordering these layers incorrectly busts the Docker layer cache and forces full rebuilds on Cloud Build, adding 2-4 minutes to deploy.

### Image Size Budget
- Target final image size: **< 350 MB** (uncompressed).
- Run `docker images --format '{{.Repository}} {{.Size}}' | grep -E '^joraflow-(api|worker)'` after Dockerfile changes.
- If the image exceeds 350 MB, audit `requirements.txt` for heavy transitive deps (e.g., `torch`, `scipy`).

---

## Pillar 2 — Fast Application Startup

### Python Bytecode Pre-Compilation
The Dockerfile pre-compiles all `.py` → `.pyc` at build time:
```dockerfile
RUN python -m compileall -q /app/src /usr/local/lib/python3.11/site-packages
```
- This **must** run before `PYTHONDONTWRITEBYTECODE=1` is set.
- When adding new Python source files, ensure they are included in the `compileall` path.
- Never remove this step — it saves 200-400 ms on the first Python subprocess spawn.

### Node.js V8 Code Cache
```dockerfile
ENV NODE_COMPILE_CACHE=/app/.v8-cache
RUN mkdir -p /app/.v8-cache
```
- Node.js 22+ writes compiled bytecode to this directory on first run.
- On subsequent container reuses (warm instances), the V8 cache eliminates JS parse + compile overhead.
- Do **not** set `--max-old-space-size` below 256 MB — it starves the V8 cache and increases GC pauses during startup.

### esbuild Bundling
The server is bundled into a single `bundle.cjs` via esbuild:
```
npx esbuild server/sync-server.js --bundle --platform=node --target=node22 --format=cjs
```
- This eliminates Node.js module resolution overhead (~50-100 `require()` calls → 1 file load).
- When adding new server-side npm dependencies to `package.server.json`, verify they are bundleable:
  - Native `.node` addons must be `--external` (already handled by `--external:"*.node"`).
  - If a dependency uses dynamic `require()` or `__dirname`-relative file reads, test the bundle locally before pushing.

### Lazy Initialization Pattern
Global objects that require network I/O or heavy computation must use lazy singletons:
```javascript
// CORRECT — lazy, deferred until first use
let _auth = null;
function getAuth() {
  if (!_auth) _auth = new GoogleAuth({ scopes: "..." });
  return _auth;
}

// WRONG — blocks startup with network round-trip
const auth = new GoogleAuth({ scopes: "..." });
```
**Already lazy in `sync-server.js`:**
- `GoogleAuth` (line 74-78) — deferred via `getAuth()`
- Supabase client — initialized from env vars (no network call at import time)
- `OAuth2Client` — constructed from static config strings

**Must remain eager (required for health probe):**
- `express()` app creation
- `http.createServer(app)` and `.listen(PORT)`
- `/healthz` and `/health` route registration

When adding new integrations, follow the lazy pattern. Never call `await fetch()` or `await client.connect()` at module top-level.

### Preflight Import Check
```dockerfile
RUN python -c "import openai; from google.oauth2.credentials import Credentials; \
    from googleapiclient.discovery import build; from supabase import create_client; \
    print('[preflight] all imports OK')"
```
- This catches missing or broken Python packages **at build time**, not at runtime.
- When adding a new Python dependency: add it to `requirements.txt` **and** add its key import to the preflight check.
- If the preflight fails, the Docker build fails — preventing a broken image from reaching Cloud Run.

---

## Pillar 3 — Cloud Run Service Configuration

### Minimum Instances (Warm Pool)
```yaml
--min-instances 1
```
- **Always** keep at least 1 warm instance. This eliminates cold starts for baseline traffic.
- The warm instance costs ~$0.50/day on 1 vCPU. This is non-negotiable for production.
- In `cloudbuild.yaml` and `deploy.sh`, `min-instances` is set to `1`. Never set it to `0` in production.

### Startup CPU Boost
```yaml
--cpu-boost
```
- Cloud Run temporarily doubles the CPU allocation during container startup.
- This cuts cold-start time by 30-50% for CPU-bound initialization (V8 compilation, Python bytecode loading).
- Enabled in both `cloudbuild.yaml` and `deploy.sh`. Do not remove.

### CPU Always-Allocated (No Throttling)
```yaml
--no-cpu-throttling
```
- Prevents Cloud Run from throttling CPU between requests.
- Critical for the sync server which maintains in-memory JWT cache, in-flight subprocess state, and connection pools.
- Enabled in `cloudbuild.yaml`. Ensure `deploy.sh` also includes it when updating deploy flags.

### Startup Probe Tuning
```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 24   # 125 s total window
```
- The `/healthz` endpoint returns `200 "ok"` immediately (no dependency checks).
- `initialDelaySeconds: 5` gives Node.js time to parse `bundle.cjs` and bind the port.
- Total startup window: `5 + (5 * 24) = 125 s`. This accommodates worst-case cold starts but does **not** mean startup should take that long.
- If startup consistently completes in < 3 s, tighten `failureThreshold` to `6` (35 s window) to detect hangs faster.

### Liveness Probe
```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 30
  failureThreshold: 3
```
- Lightweight — returns `200` with no DB or external service checks.
- Do **not** add dependency health checks (Supabase ping, Gmail API ping) to `/healthz`. If an external service is down, the container itself is still healthy and can serve cached responses or return appropriate errors.

### Concurrency
- `cloudbuild.yaml` and `deploy.sh` set `--concurrency 5`.
- `service.yaml` sets `containerConcurrency: 80` (Knative default).
- **Use `5` for production** — the Python subprocess pipeline is CPU/memory-intensive.
- Higher concurrency risks OOM kills during parallel LLM extraction, which triggers a restart and a new cold start.

### Memory Allocation
- Production: `--memory 2Gi` (deploy.sh) or `4Gi` (cloudbuild.yaml for CI builds).
- Do not drop below `1Gi` — Python subprocess + Node.js + V8 cache need headroom.
- If OOM kills appear in Cloud Run logs, increase memory before increasing max-instances.

---

## Pillar 4 — Entrypoint & Process Model

### PID 1 Signal Handling
```bash
exec node /app/server/bundle.cjs
```
- `exec` replaces the shell process so Node.js runs as PID 1 and receives `SIGTERM` directly from Cloud Run.
- Without `exec`, the shell traps `SIGTERM` and Node.js never gracefully shuts down, causing request drops during scale-down.
- Never wrap the entrypoint in a process manager (pm2, supervisord). Cloud Run expects a single process.

### Python Subprocess Model
- `scraping_engine.py` is spawned on-demand via `child_process.spawn()`, not as a persistent daemon.
- Each sync job spawns a fresh Python process. This avoids memory leaks from long-running Python processes.
- The Python startup cost is mitigated by `.pyc` pre-compilation (Pillar 2).

---

## Verification Checklist

Run these checks before merging any change to the container pipeline:

| Check | Command / Method | Pass Criteria |
|-------|------------------|---------------|
| Image builds | `docker build -f Dockerfile.api -t joraflow-api .` and `docker build -f Dockerfile.worker -t joraflow-worker .` | Exit 0; worker preflight prints `all imports OK` |
| Image size | `docker images --format '{{.Repository}} {{.Size}}' | grep -E '^joraflow-(api|worker)'` | API and worker images stay within target budgets |
| Server starts | `docker run -p 8080:8080 -e PORT=8080 joraflow-api` | `Sync server listening on port 8080 as api` within 3 s |
| Health probe | `curl -s http://localhost:8080/healthz` | Returns `ok` with HTTP 200 |
| No missing modules | `docker run joraflow-worker python -c "import openai; ..."` | Exit 0 |
| Bundle integrity | `docker run joraflow-api node -e "require('/app/server/bundle.cjs')"` | Exit 0, no module errors |

---

## Anti-Patterns (Never Do This)

| Anti-Pattern | Why It Hurts | Correct Approach |
|-------------|-------------|------------------|
| Install `node_modules` in final stage | +200 MB image, 10k+ files to scan at startup | Use esbuild bundle |
| Top-level `await fetch()` in server | Blocks port binding, health probe fails | Lazy initialization |
| `ENTRYPOINT ["sh", "-c", "node ..."]` without `exec` | Node.js is PID 2, misses SIGTERM | `exec node ...` in start.sh |
| Add Supabase/Gmail ping to `/healthz` | External outage → container killed → cold start cascade | Keep probes dependency-free |
| Set `min-instances 0` in production | Every first request after idle triggers a cold start | Keep `min-instances 1` |
| Remove `--cpu-boost` | Cold start takes 2x longer under CPU starvation | Always enable CPU boost |
| Copy full source tree into container | Bloats image, leaks secrets, busts cache | Copy only needed files |
| Use `FROM python:3.11` (full image) | +500 MB base image vs slim | Use `python:3.11-slim-bookworm` |

---

## References
- `references/dockerfile-checklist.md`: Step-by-step Dockerfile review checklist.
- `references/cloud-run-flags.md`: Canonical Cloud Run deploy flags with rationale.
- `references/startup-profiling.md`: How to profile and measure cold-start time.

## Required References
- `references/dockerfile-checklist.md`
- `references/cloud-run-flags.md`
