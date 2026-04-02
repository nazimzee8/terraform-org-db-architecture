# Startup Profiling

How to measure and debug cold-start latency for JoraFlow's Cloud Run service.

## Cloud Run Console Metrics

1. Navigate to **Cloud Run > joraflow-api** or **Cloud Run > joraflow-worker > Metrics**.
2. Check **Container startup latency** (p50, p95, p99).
3. Target: p50 < 3 s, p99 < 8 s.

## Cloud Logging Queries

### Cold-start instances
```
resource.type="cloud_run_revision"
resource.labels.service_name="<service-name>"
textPayload:"Starting container"
```

### Time from container start to port binding
```
resource.type="cloud_run_revision"
resource.labels.service_name="<service-name>"
textPayload:"Sync server listening on port"
```
Compare the timestamp of "Starting container" vs "Sync server listening" for the same instance.

### OOM kills (triggers new cold start)
```
resource.type="cloud_run_revision"
resource.labels.service_name="<service-name>"
textPayload:"Memory limit exceeded"
```

## Local Profiling

### Measure container startup time
```bash
time docker run --rm -p 8080:8080 \
  -e PORT=8080 \
  -e SUPABASE_URL=https://placeholder.supabase.co \
  -e SUPABASE_SERVICE_ROLE_KEY=placeholder \
  -e GOOGLE_CLIENT_ID=placeholder \
  -e GOOGLE_CLIENT_SECRET=placeholder \
  joraflow-api &

# Wait for startup, then hit healthz
until curl -s http://localhost:8080/healthz > /dev/null 2>&1; do sleep 0.1; done
echo "Healthy"
```

### Profile Node.js startup
```bash
docker run --rm joraflow-api \
  node --cpu-prof --cpu-prof-dir=/tmp /app/server/bundle.cjs &
sleep 5 && kill %1
# Copy the .cpuprofile out and open in Chrome DevTools
```

### Measure Python subprocess startup
```bash
docker run --rm joraflow-worker \
  time python -c "import openai; from google.oauth2.credentials import Credentials; \
  from googleapiclient.discovery import build; from supabase import create_client; \
  print('imports done')"
```
Target: < 1.5 s. If over, check which package is slow with individual import timing:
```bash
docker run --rm joraflow-worker \
  python -c "
import time
for mod in ['openai', 'google.oauth2.credentials', 'googleapiclient.discovery', 'supabase', 'pydantic', 'httpx']:
    t0 = time.perf_counter()
    __import__(mod)
    print(f'{mod}: {time.perf_counter()-t0:.3f}s')
"
```

## Interpreting Results

| Metric | Good | Investigate | Critical |
|--------|------|-------------|----------|
| Container start → port bind | < 2 s | 2-5 s | > 5 s |
| Python import time | < 1 s | 1-2 s | > 2 s |
| Image size | < 300 MB | 300-400 MB | > 400 MB |
| Cold start (Cloud Run p50) | < 3 s | 3-6 s | > 6 s |
| Cold start (Cloud Run p99) | < 6 s | 6-10 s | > 10 s |
