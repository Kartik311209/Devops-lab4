"""
app/app.py  –  Enterprise TaskFlow
====================================
A production-style Flask task-management application built for the
Enterprise DevOps Deployment Toolkit (EDDT) lab.

Features
--------
* Full CRUD task management backed by SQLite.
* /health, /ready, /version endpoints for Kubernetes probes.
* Proper error handling and JSON responses.
* Version and environment metadata via environment variables.
* No hard-coded credentials anywhere.
"""

import os
import sqlite3
import logging
from datetime import datetime, timezone
from contextlib import contextmanager

from flask import Flask, request, jsonify, render_template, g, abort

# ---------------------------------------------------------------------------
# Configuration (all values come from environment variables or safe defaults)
# ---------------------------------------------------------------------------
APP_VERSION  = os.getenv("APP_VERSION", "1.0.0")
APP_ENV      = os.getenv("APP_ENV", "development")
APP_COLOR    = os.getenv("APP_COLOR", "blue")       # used for blue-green demo
DATABASE     = os.getenv("DATABASE_PATH", "taskflow.db")
SECRET_KEY   = os.getenv("SECRET_KEY", "dev-only-change-in-production")

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(module)s – %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# App factory
# ---------------------------------------------------------------------------
app = Flask(__name__)
app.config.update(
    SECRET_KEY=SECRET_KEY,
    DATABASE=DATABASE,
    ENV=APP_ENV,
    TESTING=False,
)


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------
def get_db():
    """Return the database connection for the current request context."""
    if "db" not in g:
        g.db = sqlite3.connect(
            app.config["DATABASE"],
            detect_types=sqlite3.PARSE_DECLTYPES,
        )
        g.db.row_factory = sqlite3.Row   # access columns by name
    return g.db


@app.teardown_appcontext
def close_db(error=None):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def init_db():
    """Create the tasks table if it does not already exist."""
    with app.app_context():
        db = get_db()
        db.execute("""
            CREATE TABLE IF NOT EXISTS tasks (
                id          INTEGER PRIMARY KEY AUTOINCREMENT,
                title       TEXT NOT NULL,
                description TEXT,
                status      TEXT NOT NULL DEFAULT 'pending',
                priority    TEXT NOT NULL DEFAULT 'medium',
                created_at  TEXT NOT NULL,
                updated_at  TEXT NOT NULL
            )
        """)
        db.commit()
    logger.info("Database initialised at %s", app.config["DATABASE"])


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------
VALID_STATUSES   = {"pending", "in_progress", "completed", "cancelled"}
VALID_PRIORITIES = {"low", "medium", "high", "critical"}

def utcnow():
    return datetime.now(timezone.utc).isoformat()

def task_to_dict(row):
    return {
        "id":          row["id"],
        "title":       row["title"],
        "description": row["description"],
        "status":      row["status"],
        "priority":    row["priority"],
        "created_at":  row["created_at"],
        "updated_at":  row["updated_at"],
    }


# ---------------------------------------------------------------------------
# UI route
# ---------------------------------------------------------------------------
@app.route("/", methods=["GET"])
def index():
    """Serve the TaskFlow dashboard (HTML)."""
    db    = get_db()
    tasks = db.execute(
        "SELECT * FROM tasks ORDER BY created_at DESC"
    ).fetchall()
    tasks_list = [task_to_dict(t) for t in tasks]
    stats = {
        "total":       len(tasks_list),
        "pending":     sum(1 for t in tasks_list if t["status"] == "pending"),
        "in_progress": sum(1 for t in tasks_list if t["status"] == "in_progress"),
        "completed":   sum(1 for t in tasks_list if t["status"] == "completed"),
    }
    return render_template(
        "index.html",
        tasks=tasks_list,
        stats=stats,
        version=APP_VERSION,
        env=APP_ENV,
        color=APP_COLOR,
    )


# ---------------------------------------------------------------------------
# Health / readiness / version  (Kubernetes probes)
# ---------------------------------------------------------------------------
@app.route("/health", methods=["GET"])
def health():
    """Liveness probe – 200 as long as the process is alive."""
    return jsonify({
        "status":    "healthy",
        "app":       "Enterprise TaskFlow",
        "version":   APP_VERSION,
        "timestamp": utcnow(),
    }), 200


@app.route("/ready", methods=["GET"])
def ready():
    """Readiness probe – also verifies the database is accessible."""
    checks = {}
    try:
        get_db().execute("SELECT 1")
        checks["database"] = "ok"
    except Exception as exc:
        logger.error("DB readiness check failed: %s", exc)
        checks["database"] = "error"

    all_ok = all(v == "ok" for v in checks.values())
    return jsonify({
        "ready":  all_ok,
        "checks": checks,
    }), (200 if all_ok else 503)


@app.route("/version", methods=["GET"])
def version():
    """Returns deployment metadata – useful for blue-green verification."""
    return jsonify({
        "version":     APP_VERSION,
        "environment": APP_ENV,
        "color":       APP_COLOR,
        "app":         "Enterprise TaskFlow",
        "timestamp":   utcnow(),
    }), 200


# ---------------------------------------------------------------------------
# Task API
# ---------------------------------------------------------------------------
@app.route("/api/tasks", methods=["GET"])
def list_tasks():
    """List all tasks, with optional ?status= and ?priority= filters."""
    status_filter   = request.args.get("status")
    priority_filter = request.args.get("priority")

    query  = "SELECT * FROM tasks WHERE 1=1"
    params = []

    if status_filter:
        if status_filter not in VALID_STATUSES:
            return jsonify({"error": f"Invalid status '{status_filter}'"}), 400
        query += " AND status = ?"
        params.append(status_filter)

    if priority_filter:
        if priority_filter not in VALID_PRIORITIES:
            return jsonify({"error": f"Invalid priority '{priority_filter}'"}), 400
        query += " AND priority = ?"
        params.append(priority_filter)

    query += " ORDER BY created_at DESC"
    rows = get_db().execute(query, params).fetchall()
    return jsonify({"tasks": [task_to_dict(r) for r in rows], "count": len(rows)}), 200


@app.route("/api/tasks/<int:task_id>", methods=["GET"])
def get_task(task_id):
    """Retrieve a single task by ID."""
    row = get_db().execute(
        "SELECT * FROM tasks WHERE id = ?", (task_id,)
    ).fetchone()
    if row is None:
        return jsonify({"error": f"Task {task_id} not found"}), 404
    return jsonify(task_to_dict(row)), 200


@app.route("/api/tasks", methods=["POST"])
def create_task():
    """Create a new task. Body: {title, description?, status?, priority?}"""
    data = request.get_json(silent=True)
    if not data:
        return jsonify({"error": "Request body must be JSON"}), 400

    title = (data.get("title") or "").strip()
    if not title:
        return jsonify({"error": "'title' is required and cannot be blank"}), 400
    if len(title) > 200:
        return jsonify({"error": "'title' must be 200 characters or fewer"}), 400

    status   = data.get("status",   "pending")
    priority = data.get("priority", "medium")

    if status not in VALID_STATUSES:
        return jsonify({"error": f"Invalid status '{status}'"}), 400
    if priority not in VALID_PRIORITIES:
        return jsonify({"error": f"Invalid priority '{priority}'"}), 400

    now = utcnow()
    db  = get_db()
    cur = db.execute(
        "INSERT INTO tasks (title, description, status, priority, created_at, updated_at)"
        " VALUES (?, ?, ?, ?, ?, ?)",
        (title, data.get("description", ""), status, priority, now, now),
    )
    db.commit()
    task_id = cur.lastrowid
    logger.info("Task %d created: %s", task_id, title)

    new_row = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    return jsonify(task_to_dict(new_row)), 201


@app.route("/api/tasks/<int:task_id>", methods=["PUT"])
def update_task(task_id):
    """Update title, description, status, or priority of an existing task."""
    db  = get_db()
    row = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if row is None:
        return jsonify({"error": f"Task {task_id} not found"}), 404

    data = request.get_json(silent=True) or {}
    title       = (data.get("title") or row["title"]).strip()
    description = data.get("description", row["description"])
    status      = data.get("status",      row["status"])
    priority    = data.get("priority",    row["priority"])

    if not title:
        return jsonify({"error": "'title' cannot be blank"}), 400
    if status not in VALID_STATUSES:
        return jsonify({"error": f"Invalid status '{status}'"}), 400
    if priority not in VALID_PRIORITIES:
        return jsonify({"error": f"Invalid priority '{priority}'"}), 400

    now = utcnow()
    db.execute(
        "UPDATE tasks SET title=?, description=?, status=?, priority=?, updated_at=?"
        " WHERE id=?",
        (title, description, status, priority, now, task_id),
    )
    db.commit()
    logger.info("Task %d updated", task_id)

    updated = db.execute("SELECT * FROM tasks WHERE id = ?", (task_id,)).fetchone()
    return jsonify(task_to_dict(updated)), 200


@app.route("/api/tasks/<int:task_id>", methods=["DELETE"])
def delete_task(task_id):
    """Delete a task by ID."""
    db  = get_db()
    row = db.execute("SELECT id FROM tasks WHERE id = ?", (task_id,)).fetchone()
    if row is None:
        return jsonify({"error": f"Task {task_id} not found"}), 404

    db.execute("DELETE FROM tasks WHERE id = ?", (task_id,))
    db.commit()
    logger.info("Task %d deleted", task_id)
    return jsonify({"message": f"Task {task_id} deleted successfully"}), 200


# ---------------------------------------------------------------------------
# Error handlers
# ---------------------------------------------------------------------------
@app.errorhandler(400)
def bad_request(e):
    return jsonify({"error": str(e.description)}), 400

@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Resource not found"}), 404

@app.errorhandler(405)
def method_not_allowed(e):
    return jsonify({"error": "Method not allowed"}), 405

@app.errorhandler(500)
def server_error(e):
    logger.exception("Unhandled server error")
    return jsonify({"error": "Internal server error"}), 500


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    init_db()
    port  = int(os.getenv("PORT", 5000))
    debug = APP_ENV != "production"
    logger.info("Starting Enterprise TaskFlow v%s [%s] on port %d", APP_VERSION, APP_ENV, port)
    app.run(host="0.0.0.0", port=port, debug=debug)
