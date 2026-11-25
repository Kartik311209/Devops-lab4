"""
tests/integration/test_integration.py
Integration tests that run against a *live* instance of the application.

Usage:
    # Start app first:  APP_COLOR=blue python app/app.py
    # Then run:         pytest tests/integration/ -v --base-url=http://localhost:5000

The --base-url option is handled via conftest.py / pytest CLI option.
Default: http://localhost:5000
"""

import json
import time
import pytest
import requests

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

def pytest_addoption(parser):
    parser.addoption(
        "--base-url",
        action="store",
        default="http://localhost:5000",
        help="Base URL of the running application under test",
    )


@pytest.fixture(scope="session")
def base_url(request):
    return request.config.getoption("--base-url").rstrip("/")


@pytest.fixture(scope="session", autouse=True)
def wait_for_app(base_url):
    """Block until the app is reachable (up to 30 s)."""
    deadline = time.time() + 30
    while time.time() < deadline:
        try:
            r = requests.get(f"{base_url}/health", timeout=2)
            if r.status_code == 200:
                return
        except requests.exceptions.ConnectionError:
            pass
        time.sleep(1)
    pytest.fail(f"Application at {base_url} never became healthy within 30 s")


# ---------------------------------------------------------------------------
# Health / Readiness
# ---------------------------------------------------------------------------

class TestHealthIntegration:
    def test_health_live(self, base_url):
        r = requests.get(f"{base_url}/health")
        assert r.status_code == 200
        assert r.json()["status"] == "healthy"

    def test_readiness_live(self, base_url):
        r = requests.get(f"{base_url}/ready")
        assert r.status_code in (200, 503)   # 503 OK if deps unavailable in test env
        body = r.json()
        assert "ready" in body

    def test_response_time_health_under_500ms(self, base_url):
        start = time.time()
        requests.get(f"{base_url}/health")
        elapsed = time.time() - start
        assert elapsed < 0.5, f"Health endpoint too slow: {elapsed:.3f} s"


# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------

class TestVersionIntegration:
    def test_version_endpoint_live(self, base_url):
        r = requests.get(f"{base_url}/version")
        assert r.status_code == 200

    def test_version_headers_present(self, base_url):
        r = requests.get(f"{base_url}/version")
        assert "X-App-Version" in r.headers
        assert "X-App-Color" in r.headers

    def test_version_color_is_valid(self, base_url):
        r = requests.get(f"{base_url}/version")
        assert r.json()["color"] in ("blue", "green", "canary", "stable")


# ---------------------------------------------------------------------------
# API endpoints
# ---------------------------------------------------------------------------

class TestAPIIntegration:
    def test_greet_returns_message(self, base_url):
        r = requests.get(f"{base_url}/api/greet?name=IntegrationTest")
        assert r.status_code == 200
        assert "IntegrationTest" in r.json()["message"]

    def test_hash_post(self, base_url):
        payload = {"deployment": "blue-green", "strategy": "advanced"}
        r = requests.post(f"{base_url}/api/hash", json=payload)
        assert r.status_code == 200
        data = r.json()
        assert "hash" in data
        assert len(data["hash"]) == 64

    def test_slow_endpoint_respects_cap(self, base_url):
        # Request 10 s delay – should be capped at 5 s
        start = time.time()
        r = requests.get(f"{base_url}/api/slow?delay=10", timeout=10)
        elapsed = time.time() - start
        assert r.status_code == 200
        assert elapsed < 7   # give 2 s margin


# ---------------------------------------------------------------------------
# Blue-Green verification helper
# ---------------------------------------------------------------------------

class TestBlueGreenSwitching:
    """
    When both blue and green are running behind a service, hitting the
    /version endpoint on the service URL should always return the ACTIVE color.
    Adjust SERVICE_URL env var to point at the K8s Service external IP.
    """

    def test_active_color_is_reported_consistently(self, base_url):
        """All requests within a session should return the same color."""
        colors = {requests.get(f"{base_url}/version").json()["color"] for _ in range(5)}
        assert len(colors) == 1, f"Got multiple colors in one session: {colors}"


# ---------------------------------------------------------------------------
# Canary verification helper
# ---------------------------------------------------------------------------

class TestCanaryDistribution:
    """
    Send N requests to the service and verify that roughly the expected
    fraction hits the canary.  Requires a real K8s cluster with a canary
    deployment at 10% replicas; in unit-test mode this test is skipped.
    """

    @pytest.mark.skip(reason="Requires live K8s cluster with canary deployed")
    def test_canary_traffic_fraction(self, base_url):
        n = 100
        canary_hits = sum(
            1 for _ in range(n)
            if requests.get(f"{base_url}/version").json()["color"] == "canary"
        )
        # Expect roughly 10% ± 8%
        assert 2 <= canary_hits <= 18, f"Unexpected canary fraction: {canary_hits}/{n}"
