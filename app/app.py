"""
app.py – Sample Flask application for Lab 4: Advanced Deployment Strategies
Exposes health, readiness, version, and business-logic endpoints used by all
deployment-strategy demonstrations (blue-green, canary, GitOps, DR).
"""

import os
import time
import logging
import hashlib
from datetime import datetime

from flask import Flask, jsonify, request, abort

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
APP_VERSION  = os.getenv("APP_VERSION", "1.0.0")
APP_COLOR    = os.getenv("APP_COLOR", "blue")   # 'blue' | 'green' | 'canary'
APP_ENV      = os.getenv("APP_ENV", "production")
SECRET_KEY   = os.getenv("SECRET_KEY", "change-me-via-vault")  # injected by Vault
START_TIME   = time.time()

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s – %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = Flask(__name__)
app.config["SECRET_KEY"] = SECRET_KEY

# ---------------------------------------------------------------------------
# Middleware: request logging
# ---------------------------------------------------------------------------
@app.before_request
def log_request():
    logger.info("→ %s %s from %s", request.method, request.path, request.remote_addr)


@app.after_request
def log_response(response):
    logger.info("← %s %s %d", request.method, request.path, response.status_code)
    response.headers["X-App-Version"] = APP_VERSION
    response.headers["X-App-Color"]   = APP_COLOR
    return response


# ---------------------------------------------------------------------------
# Health & Readiness (used by Kubernetes probes)
# ---------------------------------------------------------------------------
@app.route("/health", methods=["GET"])
def health():
    """Liveness probe – returns 200 as long as the process is alive."""
    return jsonify({"status": "healthy", "timestamp": datetime.utcnow().isoformat()}), 200


@app.route("/ready", methods=["GET"])
def readiness():
    """Readiness probe – add real dependency checks here."""
    checks = {
        "database": _check_database(),
        "cache":    _check_cache(),
    }
    all_ok = all(v == "ok" for v in checks.values())
    code   = 200 if all_ok else 503
    return jsonify({"ready": all_ok, "checks": checks}), code


def _check_database():
    # Placeholder – replace with real DB ping
    return "ok"


def _check_cache():
    # Placeholder – replace with real Redis ping
    return "ok"


# ---------------------------------------------------------------------------
# Version / Info
# ---------------------------------------------------------------------------
@app.route("/version", methods=["GET"])
def version():
    """Returns current deployment metadata – useful for blue-green verification."""
    uptime = round(time.time() - START_TIME, 2)
    return jsonify({
        "version":    APP_VERSION,
        "color":      APP_COLOR,
        "environment": APP_ENV,
        "uptime_sec": uptime,
        "build_date": os.getenv("BUILD_DATE", "unknown"),
    }), 200


# ---------------------------------------------------------------------------
# Business Logic
# ---------------------------------------------------------------------------
@app.route("/api/greet", methods=["GET"])
def greet():
    name = request.args.get("name", "World")
    if len(name) > 100:
        abort(400, description="Name too long")
    return jsonify({"message": f"Hello, {name}!", "served_by": APP_COLOR}), 200


@app.route("/api/hash", methods=["POST"])
def hash_data():
    """SHA-256 hash of posted JSON payload – dummy compute endpoint."""
    payload = request.get_json(force=True, silent=True) or {}
    digest  = hashlib.sha256(str(payload).encode()).hexdigest()
    return jsonify({"hash": digest, "input_keys": list(payload.keys())}), 200


@app.route("/api/slow", methods=["GET"])
def slow_endpoint():
    """Simulates latency – useful for canary latency comparisons."""
    delay = float(request.args.get("delay", 0.5))
    delay = min(delay, 5.0)   # cap at 5 s
    time.sleep(delay)
    return jsonify({"delayed_by_sec": delay}), 200


# ---------------------------------------------------------------------------
# Error handlers
# ---------------------------------------------------------------------------
@app.errorhandler(400)
def bad_request(e):
    return jsonify({"error": str(e.description)}), 400


@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "not found"}), 404


@app.errorhandler(500)
def server_error(e):
    logger.exception("Unhandled exception")
    return jsonify({"error": "internal server error"}), 500


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    logger.info("Starting %s v%s (%s) on port %d", APP_COLOR, APP_VERSION, APP_ENV, port)
    app.run(host="0.0.0.0", port=port, debug=(APP_ENV != "production"))
