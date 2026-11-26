"""
tests/test_api.py
=================
Full API tests for the Task CRUD endpoints.

Tests:
  - List tasks (empty, filtered, with data)
  - Create tasks (all fields, defaults, edge cases)
  - Get single task (found, not found)
  - Update task (partial, full, bad input)
  - Delete task (found, not found)
  - Query string filters (?status=, ?priority=)
  - JSON response structure validation
  - HTTP status codes for every branch

Run:
  pytest tests/test_api.py -v
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

@pytest.fixture(scope="function")
def client(request):
    """Isolated test client + fresh DB per test function (project-local temp dir)."""
    db_dir  = os.path.join(os.path.dirname(__file__), "..", "reports")
    os.makedirs(db_dir, exist_ok=True)
    db_file = os.path.join(db_dir, f"_api_{request.node.name[:40]}.db")

    flask_app.config.update(
        TESTING=True,
        DATABASE=db_file,
        SECRET_KEY="api-test-secret",
    )
    with flask_app.app_context():
        init_db()
    with flask_app.test_client() as c:
        yield c

    if os.path.exists(db_file):
        try:
            os.remove(db_file)
        except OSError:
            pass


def _create_task(client, title="Test Task", **kwargs):
    """Helper: POST a task and return the parsed JSON response."""
    payload = {"title": title, **kwargs}
    resp    = client.post("/api/tasks", json=payload)
    return resp, json.loads(resp.data)


# ─────────────────────────────────────────────────────────────────────────────
# GET /api/tasks  – list tasks
# ─────────────────────────────────────────────────────────────────────────────

class TestListTasks:
    def test_empty_list_returns_200(self, client):
        resp = client.get("/api/tasks")
        assert resp.status_code == 200

    def test_empty_list_has_tasks_key(self, client):
        data = json.loads(client.get("/api/tasks").data)
        assert "tasks" in data
        assert data["tasks"] == []

    def test_empty_list_count_zero(self, client):
        data = json.loads(client.get("/api/tasks").data)
        assert data["count"] == 0

    def test_created_task_appears_in_list(self, client):
        _create_task(client, "Visible Task")
        data = json.loads(client.get("/api/tasks").data)
        assert data["count"] == 1
        assert data["tasks"][0]["title"] == "Visible Task"

    def test_multiple_tasks_all_returned(self, client):
        for i in range(5):
            _create_task(client, f"Task {i}")
        data = json.loads(client.get("/api/tasks").data)
        assert data["count"] == 5

    def test_list_ordered_newest_first(self, client):
        _create_task(client, "First")
        _create_task(client, "Second")
        tasks = json.loads(client.get("/api/tasks").data)["tasks"]
        assert tasks[0]["title"] == "Second"
        assert tasks[1]["title"] == "First"

    def test_filter_by_valid_status(self, client):
        _create_task(client, "Pending Task", status="pending")
        _create_task(client, "Done Task",    status="completed")
        data = json.loads(client.get("/api/tasks?status=pending").data)
        assert data["count"] == 1
        assert data["tasks"][0]["status"] == "pending"

    def test_filter_by_invalid_status_returns_400(self, client):
        resp = client.get("/api/tasks?status=flying")
        assert resp.status_code == 400

    def test_filter_by_valid_priority(self, client):
        _create_task(client, "High Priority", priority="high")
        _create_task(client, "Low Priority",  priority="low")
        data = json.loads(client.get("/api/tasks?priority=high").data)
        assert data["count"] == 1
        assert data["tasks"][0]["priority"] == "high"

    def test_filter_by_invalid_priority_returns_400(self, client):
        resp = client.get("/api/tasks?priority=ultra")
        assert resp.status_code == 400

    def test_combined_filters(self, client):
        _create_task(client, "Match",   status="pending", priority="high")
        _create_task(client, "No Match",status="completed", priority="high")
        _create_task(client, "No Match2",status="pending",  priority="low")
        data = json.loads(
            client.get("/api/tasks?status=pending&priority=high").data
        )
        assert data["count"] == 1
        assert data["tasks"][0]["title"] == "Match"


# ─────────────────────────────────────────────────────────────────────────────
# POST /api/tasks  – create task
# ─────────────────────────────────────────────────────────────────────────────

class TestCreateTask:
    def test_create_returns_201(self, client):
        resp, _ = _create_task(client, "New Task")
        assert resp.status_code == 201

    def test_create_returns_task_id(self, client):
        _, data = _create_task(client, "Task With ID")
        assert "id" in data
        assert isinstance(data["id"], int)
        assert data["id"] > 0

    def test_create_returns_correct_title(self, client):
        _, data = _create_task(client, "My Title")
        assert data["title"] == "My Title"

    def test_create_default_status_is_pending(self, client):
        _, data = _create_task(client, "Default Status")
        assert data["status"] == "pending"

    def test_create_default_priority_is_medium(self, client):
        _, data = _create_task(client, "Default Priority")
        assert data["priority"] == "medium"

    def test_create_with_all_fields(self, client):
        resp, data = _create_task(
            client,
            title="Full Task",
            description="Full description",
            status="in_progress",
            priority="critical",
        )
        assert resp.status_code == 201
        assert data["description"] == "Full description"
        assert data["status"] == "in_progress"
        assert data["priority"] == "critical"

    def test_create_stores_created_at(self, client):
        _, data = _create_task(client, "Timestamps")
        assert "created_at" in data
        assert "T" in data["created_at"]

    def test_create_stores_updated_at(self, client):
        _, data = _create_task(client, "Updated At")
        assert "updated_at" in data

    def test_create_increments_ids(self, client):
        _, d1 = _create_task(client, "First")
        _, d2 = _create_task(client, "Second")
        assert d2["id"] == d1["id"] + 1

    def test_create_all_valid_statuses(self, client):
        from app import VALID_STATUSES
        for status in VALID_STATUSES:
            resp, data = _create_task(client, f"Task {status}", status=status)
            assert resp.status_code == 201
            assert data["status"] == status

    def test_create_all_valid_priorities(self, client):
        from app import VALID_PRIORITIES
        for priority in VALID_PRIORITIES:
            resp, data = _create_task(client, f"Task {priority}", priority=priority)
            assert resp.status_code == 201
            assert data["priority"] == priority

    def test_create_strips_whitespace_title(self, client):
        _, data = _create_task(client, "  Trimmed Title  ")
        assert data["title"] == "Trimmed Title"


# ─────────────────────────────────────────────────────────────────────────────
# GET /api/tasks/{id}  – get single task
# ─────────────────────────────────────────────────────────────────────────────

class TestGetTask:
    def test_get_existing_task_returns_200(self, client):
        _, created = _create_task(client, "Retrieve Me")
        resp = client.get(f"/api/tasks/{created['id']}")
        assert resp.status_code == 200

    def test_get_returns_correct_task(self, client):
        _, created = _create_task(client, "Specific Task")
        data = json.loads(client.get(f"/api/tasks/{created['id']}").data)
        assert data["title"] == "Specific Task"
        assert data["id"] == created["id"]

    def test_get_nonexistent_task_returns_404(self, client):
        resp = client.get("/api/tasks/99999")
        assert resp.status_code == 404

    def test_get_404_response_has_error_key(self, client):
        data = json.loads(client.get("/api/tasks/99999").data)
        assert "error" in data

    def test_get_task_has_all_fields(self, client):
        _, created = _create_task(client, "Full Fields")
        data = json.loads(client.get(f"/api/tasks/{created['id']}").data)
        for field in ("id", "title", "description", "status", "priority",
                      "created_at", "updated_at"):
            assert field in data, f"Missing field: {field}"

    def test_get_task_id_zero_returns_404(self, client):
        resp = client.get("/api/tasks/0")
        assert resp.status_code == 404


# ─────────────────────────────────────────────────────────────────────────────
# PUT /api/tasks/{id}  – update task
# ─────────────────────────────────────────────────────────────────────────────

class TestUpdateTask:
    def test_update_status_returns_200(self, client):
        _, created = _create_task(client, "To Update")
        resp = client.put(f"/api/tasks/{created['id']}",
                          json={"status": "completed"})
        assert resp.status_code == 200

    def test_update_status_reflected_in_response(self, client):
        _, created = _create_task(client, "Status Check")
        data = json.loads(
            client.put(f"/api/tasks/{created['id']}",
                       json={"status": "in_progress"}).data
        )
        assert data["status"] == "in_progress"

    def test_update_title(self, client):
        _, created = _create_task(client, "Old Title")
        data = json.loads(
            client.put(f"/api/tasks/{created['id']}",
                       json={"title": "New Title"}).data
        )
        assert data["title"] == "New Title"

    def test_update_priority(self, client):
        _, created = _create_task(client, "Priority Test")
        data = json.loads(
            client.put(f"/api/tasks/{created['id']}",
                       json={"priority": "critical"}).data
        )
        assert data["priority"] == "critical"

    def test_update_description(self, client):
        _, created = _create_task(client, "Desc Test")
        data = json.loads(
            client.put(f"/api/tasks/{created['id']}",
                       json={"description": "Updated desc"}).data
        )
        assert data["description"] == "Updated desc"

    def test_update_nonexistent_returns_404(self, client):
        resp = client.put("/api/tasks/99999", json={"status": "completed"})
        assert resp.status_code == 404

    def test_update_invalid_status_returns_400(self, client):
        _, created = _create_task(client, "Bad Status")
        resp = client.put(f"/api/tasks/{created['id']}",
                          json={"status": "flying"})
        assert resp.status_code == 400

    def test_update_invalid_priority_returns_400(self, client):
        _, created = _create_task(client, "Bad Priority")
        resp = client.put(f"/api/tasks/{created['id']}",
                          json={"priority": "mega"})
        assert resp.status_code == 400

    def test_update_persists_through_get(self, client):
        _, created = _create_task(client, "Persist Check")
        tid = created["id"]
        client.put(f"/api/tasks/{tid}", json={"status": "cancelled"})
        data = json.loads(client.get(f"/api/tasks/{tid}").data)
        assert data["status"] == "cancelled"

    def test_update_updates_updated_at(self, client):
        import time
        _, created = _create_task(client, "Timestamp Update")
        tid = created["id"]
        old_ts = created["updated_at"]
        time.sleep(0.05)
        data = json.loads(
            client.put(f"/api/tasks/{tid}",
                       json={"status": "in_progress"}).data
        )
        assert data["updated_at"] >= old_ts

    def test_update_partial_keeps_other_fields(self, client):
        _, created = _create_task(client, "Partial", priority="high",
                                  description="Keep me")
        tid = created["id"]
        data = json.loads(
            client.put(f"/api/tasks/{tid}", json={"status": "completed"}).data
        )
        assert data["priority"] == "high"
        assert data["description"] == "Keep me"


# ─────────────────────────────────────────────────────────────────────────────
# DELETE /api/tasks/{id}  – delete task
# ─────────────────────────────────────────────────────────────────────────────

class TestDeleteTask:
    def test_delete_returns_200(self, client):
        _, created = _create_task(client, "To Delete")
        resp = client.delete(f"/api/tasks/{created['id']}")
        assert resp.status_code == 200

    def test_delete_returns_message(self, client):
        _, created = _create_task(client, "Delete Me")
        data = json.loads(client.delete(f"/api/tasks/{created['id']}").data)
        assert "message" in data
        assert "deleted" in data["message"].lower()

    def test_delete_removes_task_from_list(self, client):
        _, created = _create_task(client, "Gone Soon")
        tid = created["id"]
        client.delete(f"/api/tasks/{tid}")
        data = json.loads(client.get("/api/tasks").data)
        assert all(t["id"] != tid for t in data["tasks"])

    def test_delete_makes_task_unreachable(self, client):
        _, created = _create_task(client, "Unreachable")
        tid = created["id"]
        client.delete(f"/api/tasks/{tid}")
        resp = client.get(f"/api/tasks/{tid}")
        assert resp.status_code == 404

    def test_delete_nonexistent_returns_404(self, client):
        resp = client.delete("/api/tasks/99999")
        assert resp.status_code == 404

    def test_delete_does_not_affect_other_tasks(self, client):
        _, t1 = _create_task(client, "Keep Me")
        _, t2 = _create_task(client, "Delete Me")
        client.delete(f"/api/tasks/{t2['id']}")
        resp = client.get(f"/api/tasks/{t1['id']}")
        assert resp.status_code == 200
