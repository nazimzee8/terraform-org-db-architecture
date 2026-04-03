# Stage 1: deps
FROM python:3.11-slim-bookworm AS deps
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/build/site-packages -r requirements.txt

# Stage 2: runtime
FROM python:3.11-slim-bookworm AS runtime
WORKDIR /app
ENV PYTHONPATH=/app/lib \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=0
COPY --from=deps /build/site-packages /app/lib
COPY *.py ./
# Pre-compile all .py to .pyc at build time.
RUN python -m compileall -q /app /app/lib
# Disable runtime .pyc writes (already compiled above).
ENV PYTHONDONTWRITEBYTECODE=1
# Preflight the actual app module graph, not just third-party imports.
RUN python -c "import main; print('[preflight] OK')"
ENTRYPOINT ["python", "main.py"]
