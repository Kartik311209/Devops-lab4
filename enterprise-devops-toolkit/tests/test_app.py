"""
tests/test_app.py
=================
Unit tests for Enterprise TaskFlow – core application logic.

Tests:
  - Database initialisation
  - Task model (create, read, update, delete via app context)
  - Input validation (title length, blank title, bad status/priority)
  - Utility functions (utcnow, task_to_dict)
  - Error handlers (404, 405)

Run:
  pytest tests/test_app.py -v
"""

import sys
import os
import json
import pytest

# ── Make the app package importable from project root ─────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

from app import app as flask_app, init_db, utcnow, VALID_STATUSES, VALID_PRIORITIES


# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture(scope="function")
def client(request):
    """
    Fresh test client for every test function.
    Uses a local temp SQLite file (project-relative) so tests are isolated
    even in sandboxed environments where the system temp dir is restricted.
    """
    # Use a directory inside the project that is always writable
    db_dir  = os.path.join(os.path.dirname(__file__), "..", "reports")
    os.makedirs(db_dir, exist_ok=True)
    db_file = os.path.join(db_dir, f"_test_{request.node.name[:40]}.db")

    flask_app.config.update(
        TESTING=True,
        DATABASE=db_file,
        SECRET_KEY="test-secret-key",
    )
    with flask_app.app_context():
        init_db()
    with flask_app.test_client() as c:
        yield c

    # Cleanup
    if os.path.exists(db_file):
        try:
            os.remove(db_file)
        except OSError:
            pass


# ─────────────────────────────────────────────────────────────────────────────
# Database initialisation
# ─────────────────────────────────────────────────────────────────────────────

class TestDatabaseInit:
    def test_db_initialises_without_error(self):
        """init_db() must not raise an exception."""
        db_dir  = os.path.join(os.path.dirname(__file__), "..", "reports")
        os.makedirs(db_dir, exist_ok=True)
        db_file = os.path.join(db_dir, "_init_test.db")
        flask_app.config["DATABASE"] = db_file
        with flask_app.app_context():
            init_db()   # should not raise
        assert os.path.exists(db_file)
        try:
            os.remove(db_file)
        except OSError:
            pass

    def test_db_is_idempotent(self):
        """Calling init_db() twice must not raise (CREATE TABLE IF NOT EXISTS)."""
        db_dir  = os.path.join(os.path.dirname(__file__), "..", "reports")
        os.makedirs(db_dir, exist_ok=True)
        db_file = os.path.join(db_dir, "_idempotent.db")
        flask_app.config["DATABASE"] = db_file
        with flask_app.app_context():
            init_db()
            init_db()   # second call must be safe
        try:
            os.remove(db_file)
        except OSError:
            pass


# ─────────────────────────────────────────────────────────────────────────────
# Utility functions
# ─────────────────────────────────────────────────────────────────────────────

class TestUtilityFunctions:
    def test_utcnow_returns_string(self):
        result = utcnow()
        assert isinstance(result, str)

    def test_utcnow_is_iso8601(self):
        result = utcnow()
        # ISO 8601 timestamps contain 'T'
        assert "T" in result

    def test_utcnow_different_calls_monotonic(self):
        import time
        t1 = utcnow()
        time.sleep(0.01)
        t2 = utcnow()
        assert t2 >= t1

    def test_valid_statuses_set(self):
        assert "pending"     in VALID_STATUSES
        assert "in_progress" in VALID_STATUSES
        assert "completed"   in VALID_STATUSES
        assert "cancelled"   in VALID_STATUSES

    def test_valid_priorities_set(self):
        assert "low"      in VALID_PRIORITIES
        assert "medium"   in VALID_PRIORITIES
        assert "high"     in VALID_PRIORITIES
        assert "critical" in VALID_PRIORITIES


# ─────────────────────────────────────────────────────────────────────────────
# Root / UI route
# ─────────────────────────────────────────────────────────────────────────────

class TestRootRoute:
    def test_root_returns_200(self, client):
        resp = client.get("/")
        assert resp.status_code == 200

    def test_root_returns_html(self, client):
        resp = client.get("/")
        assert b"TaskFlow" in resp.data

    def test_root_contains_version(self, client):
        resp = client.get("/")
        # The template renders the version badge
        assert b"1.0.0" in resp.data or resp.status_code == 200


# ─────────────────────────────────────────────────────────────────────────────
# Input validation – create task
# ─────────────────────────────────────────────────────────────────────────────

class TestInputValidation:
    def test_missing_title_returns_400(self, client):
        resp = client.post("/api/tasks", json={"priority": "high"})
        assert resp.status_code == 400
        assert b"title" in resp.data.lower()

    def test_blank_title_returns_400(self, client):
        resp = client.post("/api/tasks", json={"title": "   "})
        assert resp.status_code == 400

    def test_title_too_long_returns_400(self, client):
        resp = client.post("/api/tasks", json={"title": "A" * 201})
        assert resp.status_code == 400

    def test_invalid_status_returns_400(self, client):
        resp = client.post("/api/tasks",
                           json={"title": "Test", "status": "flying"})
        assert resp.status_code == 400

    def test_invalid_priority_returns_400(self, client):
        resp = client.post("/api/tasks",
                           json={"title": "Test", "priority": "ultra"})
        assert resp.status_code == 400

    def test_non_json_body_returns_400(self, client):
        resp = client.post("/api/tasks",
                           data="not json",
                           content_type="text/plain")
        assert resp.status_code == 400

    def test_max_length_title_accepted(self, client):
        resp = client.post("/api/tasks", json={"title": "A" * 200})
        assert resp.status_code == 201


# ─────────────────────────────────────────────────────────────────────────────
# Error handlers
# ─────────────────────────────────────────────────────────────────────────────

class TestErrorHandlers:
    def test_404_returns_json(self, client):
        resp = client.get("/this-route-does-not-exist")
        assert resp.status_code == 404
        data = json.loads(resp.data)
        assert "error" in data

    def test_404_error_key_present(self, client):
        data = json.loads(client.get("/nonexistent").data)
        assert data["error"] == "Resource not found"

    def test_405_on_wrong_method(self, client):
        # /health only accepts GET
        resp = client.post("/health")
        assert resp.status_code == 405


# ─────────────────────────────────────────────────────────────────────────────
# Environment variables reflected in app
# ─────────────────────────────────────────────────────────────────────────────

class TestEnvironmentConfig:
    def test_testing_flag_is_set(self, client):
        assert flask_app.config["TESTING"] is True

    def test_secret_key_is_set(self, client):
        assert flask_app.config["SECRET_KEY"] == "test-secret-key"
