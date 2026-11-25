# =============================================================================
# Multi-stage Dockerfile for sample-app
# Lab 4 – Advanced Deployment Strategies & Enterprise DevOps
# =============================================================================

# ── Stage 1: builder ─────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

LABEL maintainer="devops-lab@example.com"
LABEL description="Lab 4 sample Flask application"

# Security: do NOT run pip as root in production
WORKDIR /build

# Copy dependency manifest first (better layer caching)
COPY requirements.txt .

# Install into a local directory so we can copy only what's needed
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ─────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

# Non-root user for security hardening
RUN groupadd --gid 1001 appgroup && \
    useradd  --uid 1001 --gid appgroup --no-create-home appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY --chown=appuser:appgroup app.py .

# Build-time metadata (injected by CI pipeline)
ARG APP_VERSION=1.0.0
ARG BUILD_DATE=unknown
ARG GIT_COMMIT=unknown

ENV APP_VERSION=${APP_VERSION} \
    BUILD_DATE=${BUILD_DATE}   \
    GIT_COMMIT=${GIT_COMMIT}   \
    APP_ENV=production         \
    PORT=5000                  \
    PYTHONDONTWRITEBYTECODE=1  \
    PYTHONUNBUFFERED=1

USER appuser

EXPOSE 5000

# Healthcheck so Docker / Kubernetes knows the app is alive
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"

# Gunicorn for production; workers auto-tuned to CPU count
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", \
     "--threads", "4", "--timeout", "30", "--access-logfile", "-", \
     "--error-logfile", "-", "app:app"]
