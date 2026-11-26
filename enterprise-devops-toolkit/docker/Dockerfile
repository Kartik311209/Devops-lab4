# =============================================================================
# docker/Dockerfile  –  Enterprise TaskFlow
# =============================================================================
#
# Multi-stage build for minimal, secure production image:
#   Stage 1 (builder): Install Python dependencies
#   Stage 2 (runtime): Lean image with only what the app needs
#
# Build:
#   docker build -f docker/Dockerfile -t taskflow:1.0.0 .
#
# Run:
#   docker run -p 5000:5000 -e APP_ENV=production taskflow:1.0.0
# =============================================================================

# ── Stage 1: builder ─────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Copy only requirements first (layer caching – this layer rarely changes)
COPY app/requirements.txt .

# Install into a prefix dir so we can copy cleanly to the runtime stage
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ─────────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

LABEL maintainer="eddt-lab@example.com"
LABEL description="Enterprise TaskFlow – EDDT Lab Application"
LABEL version="1.0.0"

# ── Security: non-root user ───────────────────────────────────────────────────
RUN groupadd --gid 1001 appgroup && \
    useradd  --uid 1001 --gid appgroup --no-create-home --shell /sbin/nologin appuser

WORKDIR /app

# Copy installed packages from builder stage
COPY --from=builder /install /usr/local

# Copy application source code
COPY --chown=appuser:appgroup app/app.py          ./app.py
COPY --chown=appuser:appgroup app/requirements.txt ./requirements.txt
COPY --chown=appuser:appgroup app/templates/       ./templates/

# Create a writable data directory for SQLite
RUN mkdir -p /data && chown appuser:appgroup /data

# ── Build-time metadata (injected by CI pipeline) ─────────────────────────────
ARG APP_VERSION=1.0.0
ARG BUILD_DATE=unknown
ARG GIT_COMMIT=unknown

# ── Runtime environment variables (safe defaults – no credentials here) ───────
ENV APP_VERSION=${APP_VERSION}  \
    BUILD_DATE=${BUILD_DATE}    \
    GIT_COMMIT=${GIT_COMMIT}    \
    APP_ENV=production          \
    APP_COLOR=blue              \
    DATABASE_PATH=/data/taskflow.db \
    PORT=5000                   \
    PYTHONDONTWRITEBYTECODE=1   \
    PYTHONUNBUFFERED=1

USER appuser

EXPOSE 5000

# ── Health check (Docker / Kubernetes will use /health endpoint) ───────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python -c \
    "import urllib.request, sys; \
     r = urllib.request.urlopen('http://localhost:5000/health', timeout=5); \
     sys.exit(0 if r.status == 200 else 1)"

# ── Entrypoint: initialise DB then start Gunicorn ─────────────────────────────
# Gunicorn is used for production; Flask's built-in server is dev-only.
CMD ["sh", "-c", \
     "python -c 'from app import app, init_db; app.config[\"DATABASE\"] = \"/data/taskflow.db\"; \
      __import__(\"flask\").g; \
      import app as m; m.app.config[\"DATABASE\"] = \"/data/taskflow.db\"; m.init_db()' && \
      gunicorn --bind 0.0.0.0:5000 \
               --workers 2 \
               --threads 4 \
               --timeout 30 \
               --access-logfile - \
               --error-logfile  - \
               app:app"]
