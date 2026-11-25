"""
tests/performance/locustfile.py
Performance / load tests for Lab 4 using Locust.

Usage:
    locust -f tests/performance/locustfile.py \
           --host=http://localhost:5000       \
           --users=50 --spawn-rate=5          \
           --run-time=2m --headless           \
           --html=reports/perf_report.html

Thresholds (checked in CI via --exit-code-on-error):
    - 95th percentile response time < 500 ms
    - Error rate < 1%
"""

import json
import random

from locust import HttpUser, TaskSet, task, between, events
from locust.runners import MasterRunner


# ---------------------------------------------------------------------------
# Task Sets
# ---------------------------------------------------------------------------

class ReadOnlyTasks(TaskSet):
    """Simulate read-heavy traffic – 70% of virtual users."""

    @task(5)
    def health_check(self):
        with self.client.get("/health", name="/health", catch_response=True) as resp:
            if resp.status_code != 200:
                resp.failure(f"Health check failed: {resp.status_code}")

    @task(3)
    def get_version(self):
        with self.client.get("/version", name="/version", catch_response=True) as resp:
            if resp.status_code != 200:
                resp.failure(f"Version endpoint failed: {resp.status_code}")
            else:
                data = resp.json()
                if "version" not in data:
                    resp.failure("Missing 'version' key in response")

    @task(2)
    def greet(self):
        names = ["Alice", "Bob", "Carol", "DevOps", "Kubernetes"]
        name  = random.choice(names)
        self.client.get(f"/api/greet?name={name}", name="/api/greet")

    @task(1)
    def ready_check(self):
        self.client.get("/ready", name="/ready")


class WriteHeavyTasks(TaskSet):
    """Simulate write / compute traffic – 30% of virtual users."""

    @task(3)
    def hash_post(self):
        payload = {
            "user_id":    random.randint(1, 10000),
            "action":     random.choice(["login", "purchase", "view"]),
            "timestamp":  "2026-11-18T10:00:00Z",
        }
        with self.client.post(
            "/api/hash",
            json=payload,
            name="/api/hash",
            catch_response=True,
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"Hash endpoint failed: {resp.status_code}")
            else:
                data = resp.json()
                if len(data.get("hash", "")) != 64:
                    resp.failure("Invalid hash length")

    @task(1)
    def slow_endpoint(self):
        # Simulate realistic 50-200 ms backend latency
        delay = round(random.uniform(0.05, 0.2), 2)
        with self.client.get(
            f"/api/slow?delay={delay}",
            name="/api/slow",
            catch_response=True,
            timeout=5,
        ) as resp:
            if resp.status_code != 200:
                resp.failure(f"Slow endpoint failed: {resp.status_code}")


# ---------------------------------------------------------------------------
# User Classes
# ---------------------------------------------------------------------------

class ReadUser(HttpUser):
    """Models a typical read-only consumer (e.g., monitoring, dashboard)."""
    weight      = 7
    wait_time   = between(0.5, 2.0)
    tasks       = [ReadOnlyTasks]


class WriteUser(HttpUser):
    """Models a compute-intensive client."""
    weight      = 3
    wait_time   = between(1.0, 3.0)
    tasks       = [WriteHeavyTasks]


# ---------------------------------------------------------------------------
# Custom Listeners – CI threshold enforcement
# ---------------------------------------------------------------------------

THRESHOLD_P95_MS   = 500   # ms
THRESHOLD_ERROR_PCT = 1.0  # %


@events.quitting.add_listener
def on_quitting(environment, **kwargs):
    """Fail the CI step if performance thresholds are breached."""
    stats = environment.runner.stats.total
    if stats.num_requests == 0:
        return

    p95       = stats.get_response_time_percentile(0.95)
    error_pct = (stats.num_failures / stats.num_requests) * 100

    failures = []
    if p95 > THRESHOLD_P95_MS:
        failures.append(f"P95 latency {p95:.0f} ms > threshold {THRESHOLD_P95_MS} ms")
    if error_pct > THRESHOLD_ERROR_PCT:
        failures.append(f"Error rate {error_pct:.2f}% > threshold {THRESHOLD_ERROR_PCT}%")

    if failures:
        print("\n[PERF] THRESHOLD BREACH:")
        for f in failures:
            print(f"  ✗ {f}")
        environment.process_exit_code = 1
    else:
        print(f"\n[PERF] All thresholds passed – P95={p95:.0f}ms, errors={error_pct:.2f}%")
