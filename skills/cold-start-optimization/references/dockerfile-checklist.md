# Dockerfile Review Checklist

Use this checklist before merging changes to `Dockerfile.api` or `Dockerfile.worker`. Apply only the sections relevant to the image under review.

## Stage 1 — python-deps
- [ ] `requirements.txt` is COPY'd before source code (cache-friendly order).
- [ ] `--no-cache-dir` is passed to `pip install` (no wasted layer space).
- [ ] `--target=/build/site-packages` isolates packages for clean COPY.
- [ ] `build-essential` is installed only in this stage, never in the final stage.
- [ ] No dev/test dependencies in `requirements.txt` (pytest, black, mypy, etc.).

## Stage 2 — node-deps
- [ ] `package.server.json` is COPY'd as `package.json` (not the root frontend `package.json`).
- [ ] `npm install --omit=dev` excludes devDependencies.
- [ ] `npm cache clean --force` removes cache after install.
- [ ] esbuild produces `bundle.cjs` with `--platform=node --target=node22 --format=cjs`.
- [ ] `--external:"*.node"` excludes native addons (prevents build failures).
- [ ] `import.meta.url` polyfill banner is present for CJS compatibility.

## Stage 3 — Final Runtime
- [ ] Base image is `python:3.11-slim-bookworm` (not full, not alpine).
- [ ] `apt-get` installs only: `libstdc++6`, `ca-certificates`, `curl`.
- [ ] `rm -rf /var/lib/apt/lists/*` is chained in the same RUN layer.
- [ ] Node.js binary copied from `node-deps` stage (single file, not full install).
- [ ] Python site-packages copied from `python-deps` stage.
- [ ] Only required application files are COPY'd: API image gets `start.sh` and `server/bundle.cjs`; worker image also gets `src/scraping_engine.py` and `src/scraping_engine_async_patch.py`.
- [ ] `python -m compileall` runs BEFORE `PYTHONDONTWRITEBYTECODE=1` is set.
- [ ] `NODE_COMPILE_CACHE` directory is created (`mkdir -p /app/.v8-cache`).
- [ ] Preflight import check is present and covers all key Python dependencies.
- [ ] `CMD` uses `sh /app/start.sh` (which uses `exec node`).
- [ ] No `.env` files, secrets, or credentials are COPY'd into the image.
- [ ] No `node_modules/` directory exists in the final image.

## Size Validation
- [ ] Final image < 350 MB (run `docker images --format '{{.Size}}'`).
- [ ] If over budget, run `docker history <image-name>` to find the largest layers.

## Startup Validation
- [ ] Container starts and binds port within 3 seconds.
- [ ] `/healthz` returns HTTP 200 within 5 seconds of container start.
- [ ] No Python `ImportError` or Node.js `MODULE_NOT_FOUND` in startup logs.
