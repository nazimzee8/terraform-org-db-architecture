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
COPY app.py ./
RUN python -m compileall -q /app /app/lib
ENV PYTHONDONTWRITEBYTECODE=1
RUN python -c "import app; print('[preflight] OK')"
ENTRYPOINT ["python", "-m", "streamlit", "run", "app.py", \
            "--server.port=8080", "--server.address=0.0.0.0"]
