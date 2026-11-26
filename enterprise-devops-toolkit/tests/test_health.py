"""
tests/test_health.py
====================
Tests for the three Kubernetes probe endpoints:
  GET /health   – liveness probe
  GET /ready    – readiness probe (checks DB connectivity)
  GET /version  – deployment metadata

Run:
  pytest tests/test_health.py -v
"""

import sys
import os
import json
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

from app import app as flask_app, init_db


# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def client():
    db_dir  = os.path.join(os.path.dirname(__file__), "..", "reports")
    os.makedirs(db_dir, exist_ok=True)
    db_file = os.path.join(db_dir, "_health_test.db")
    flask_app.config.update(
        TESTING=True,
        DATABASE=db_file,
        SECRET_KEY="health-test-secret",
    )
    with flask_app.app_context():
        init_db()
    with flask_app.test_client() as c:
        yield c
    try:
        os.remove(db_file)
    except OSError:
        pass


# ─────────────────────────────────────────────────────────────────────────────
# /health  – liveness probe
# ─────────────────────────────────────────────────────────────────────────────

class TestHealthEndpoint:
    def test_health_status_code_200(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200

    def test_health_content_type_json(self, client):
        resp = client.get("/health")
        assert "application/json" in resp.content_type

    def test_health_status_field_is_healthy(self, client):
        data = json.loads(client.get("/health").data)
        assert data["status"] == "healthy"

    def test_health_contains_app_name(self, client):
        data = json.loads(client.get("/health").data)
        assert data["app"] == "Enterprise TaskFlow"

    def test_health_contains_version(self, client):
        data = json.loads(client.get("/health").data)
        assert "version" in data
        assert isinstance(data["version"], str)

    def test_health_contains_timestamp(self, client):
        data = json.loads(client.get("/health").data)
        assert "timestamp" in data
        assert "T" in data["timestamp"]   # ISO 8601 format

    def test_health_no_post(self, client):
        resp = client.post("/health")
        assert resp.status_code == 405

    def test_health_no_delete(self, client):
        resp = client.delete("/health")
        assert resp.status_code == 405

    def test_health_response_is_valid_json(self, client):
        resp = client.get("/health")
        try:
            json.loads(resp.data)
        except json.JSONDecodeError:
            pytest.fail("/health did not return valid JSON")


# ─────────────────────────────────────────────────────────────────────────────
# /ready  – readiness probe
# ─────────────────────────────────────────────────────────────────────────────

class TestReadinessEndpoint:
    def test_ready_status_code_200_when_db_ok(self, client):
        resp = client.get("/ready")
        assert resp.status_code == 200

    def test_ready_body_has_ready_field(self, client):
        data = json.loads(client.get("/ready").data)
        assert "ready" in data

    def test_ready_field_is_boolean(self, client):
        data = json.loads(client.get("/ready").data)
        assert isinstance(data["ready"], bool)

    def test_ready_body_has_checks_dict(self, client):
        data = json.loads(client.get("/ready").data)
        assert "checks" in data
        assert isinstance(data["checks"], dict)

    def test_ready_database_check_present(self, client):
        data = json.loads(client.get("/ready").data)
        assert "database" in data["checks"]

    def test_ready_database_ok_when_db_accessible(self, client):
        data = json.loads(client.get("/ready").data)
        assert data["checks"]["database"] == "ok"

    def test_ready_true_when_all_checks_pass(self, client):
        data = json.loads(client.get("/ready").data)
        assert data["ready"] is True

    def test_ready_503_when_db_broken(self):
        """Simulate a broken DB path → readiness must return 503."""
        # Save and override
        good_db = flask_app.config["DATABASE"]
        flask_app.config["DATABASE"] = "Z:\\nonexistent\\path\\broken.db"
        with flask_app.test_client() as c:
            resp = c.get("/ready")
        assert resp.status_code == 503
        data = json.loads(resp.data)
        assert data["ready"] is False
        # Restore
        flask_app.config["DATABASE"] = good_db

    def test_ready_no_post(self, client):
        resp = client.post("/ready")
        assert resp.status_code == 405


# ─────────────────────────────────────────────────────────────────────────────
# /version  – deployment metadata
# ─────────────────────────────────────────────────────────────────────────────

class TestVersionEndpoint:
    def test_version_status_code_200(self, client):
        assert client.get("/version").status_code == 200

    def test_version_has_version_field(self, client):
        data = json.loads(client.get("/version").data)
        assert "version" in data

    def test_version_has_environment_field(self, client):
        data = json.loads(client.get("/version").data)
        assert "environment" in data

    def test_version_has_color_field(self, client):
        data = json.loads(client.get("/version").data)
        assert "color" in data
        assert data["color"] in ("blue", "green", "canary", "stable")

    def test_version_has_app_field(self, client):
        data = json.loads(client.get("/version").data)
        assert data["app"] == "Enterprise TaskFlow"

    def test_version_has_timestamp(self, client):
        data = json.loads(client.get("/version").data)
        assert "timestamp" in data

    def test_version_is_valid_json(self, client):
        resp = client.get("/version")
        try:
            json.loads(resp.data)
        except json.JSONDecodeError:
            pytest.fail("/version did not return valid JSON")

    def test_version_no_post(self, client):
        assert client.post("/version").status_code == 405
