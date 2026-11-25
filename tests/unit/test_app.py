"""
tests/unit/test_app.py
Unit tests for the sample Flask application.
Run: pytest tests/unit/ -v --cov=app --cov-report=term-missing
"""

import json
import pytest
import sys
import os

# Allow importing app from the sibling app/ directory
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../app"))

import app as flask_app_module


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def client():
    """Create a test client with testing mode enabled."""
    flask_app_module.app.config["TESTING"] = True
    flask_app_module.app.config["SECRET_KEY"] = "test-secret"
    with flask_app_module.app.test_client() as c:
        yield c


# ---------------------------------------------------------------------------
# Health & Readiness
# ---------------------------------------------------------------------------

class TestHealthEndpoint:
    def test_health_returns_200(self, client):
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_body_has_status(self, client):
        data = json.loads(client.get("/health").data)
        assert data["status"] == "healthy"

    def test_health_body_has_timestamp(self, client):
        data = json.loads(client.get("/health").data)
        assert "timestamp" in data


class TestReadinessEndpoint:
    def test_ready_returns_200(self, client):
        response = client.get("/ready")
        assert response.status_code == 200

    def test_ready_body_structure(self, client):
        data = json.loads(client.get("/ready").data)
        assert "ready" in data
        assert "checks" in data
        assert isinstance(data["checks"], dict)

    def test_ready_checks_database_key(self, client):
        data = json.loads(client.get("/ready").data)
        assert "database" in data["checks"]

    def test_ready_checks_cache_key(self, client):
        data = json.loads(client.get("/ready").data)
        assert "cache" in data["checks"]


# ---------------------------------------------------------------------------
# Version endpoint
# ---------------------------------------------------------------------------

class TestVersionEndpoint:
    def test_version_returns_200(self, client):
        assert client.get("/version").status_code == 200

    def test_version_has_version_field(self, client):
        data = json.loads(client.get("/version").data)
        assert "version" in data

    def test_version_has_color_field(self, client):
        data = json.loads(client.get("/version").data)
        assert "color" in data

    def test_version_has_uptime(self, client):
        data = json.loads(client.get("/version").data)
        assert "uptime_sec" in data
        assert data["uptime_sec"] >= 0

    def test_response_has_x_app_version_header(self, client):
        resp = client.get("/version")
        assert "X-App-Version" in resp.headers

    def test_response_has_x_app_color_header(self, client):
        resp = client.get("/version")
        assert "X-App-Color" in resp.headers


# ---------------------------------------------------------------------------
# Greet endpoint
# ---------------------------------------------------------------------------

class TestGreetEndpoint:
    def test_greet_default(self, client):
        data = json.loads(client.get("/api/greet").data)
        assert "World" in data["message"]

    def test_greet_custom_name(self, client):
        data = json.loads(client.get("/api/greet?name=Alice").data)
        assert "Alice" in data["message"]

    def test_greet_has_served_by(self, client):
        data = json.loads(client.get("/api/greet").data)
        assert "served_by" in data

    def test_greet_name_too_long_returns_400(self, client):
        long_name = "A" * 101
        resp = client.get(f"/api/greet?name={long_name}")
        assert resp.status_code == 400


# ---------------------------------------------------------------------------
# Hash endpoint
# ---------------------------------------------------------------------------

class TestHashEndpoint:
    def test_hash_returns_200(self, client):
        resp = client.post("/api/hash",
                           data=json.dumps({"key": "value"}),
                           content_type="application/json")
        assert resp.status_code == 200

    def test_hash_returns_hex_string(self, client):
        resp = client.post("/api/hash",
                           data=json.dumps({"x": 1}),
                           content_type="application/json")
        data = json.loads(resp.data)
        assert len(data["hash"]) == 64   # SHA-256 hex digest length
        assert all(c in "0123456789abcdef" for c in data["hash"])

    def test_hash_deterministic(self, client):
        payload = json.dumps({"foo": "bar"})
        h1 = json.loads(client.post("/api/hash", data=payload,
                                    content_type="application/json").data)["hash"]
        h2 = json.loads(client.post("/api/hash", data=payload,
                                    content_type="application/json").data)["hash"]
        assert h1 == h2

    def test_hash_empty_payload(self, client):
        resp = client.post("/api/hash",
                           data=json.dumps({}),
                           content_type="application/json")
        assert resp.status_code == 200
        data = json.loads(resp.data)
        assert data["input_keys"] == []


# ---------------------------------------------------------------------------
# 404 handling
# ---------------------------------------------------------------------------

class TestErrorHandling:
    def test_unknown_route_returns_404(self, client):
        resp = client.get("/this-does-not-exist")
        assert resp.status_code == 404

    def test_404_body_has_error_field(self, client):
        data = json.loads(client.get("/nonexistent").data)
        assert "error" in data
