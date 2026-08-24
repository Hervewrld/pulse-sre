import httpx
import pytest
from fastapi.testclient import TestClient

from src.checker.main import app, perform_check
from src.common import db
from src.common.models import CheckResult, Monitor, MonitorStatus


class FakeResponse:
    def __init__(self, status_code):
        self.status_code = status_code


def test_perform_check_success(monkeypatch):
    monkeypatch.setattr(httpx, "get", lambda url, timeout, follow_redirects: FakeResponse(200))

    success, status_code, response_time_ms, error = perform_check("https://example.com", 5.0)

    assert success is True
    assert status_code == 200
    assert response_time_ms is not None
    assert error is None


def test_perform_check_http_error_status(monkeypatch):
    monkeypatch.setattr(httpx, "get", lambda url, timeout, follow_redirects: FakeResponse(500))

    success, status_code, _, error = perform_check("https://example.com", 5.0)

    assert success is False
    assert status_code == 500
    assert error is None


def test_perform_check_connection_error(monkeypatch):
    def raise_error(url, timeout, follow_redirects):
        raise httpx.ConnectError("connection refused")

    monkeypatch.setattr(httpx, "get", raise_error)

    success, status_code, _, error = perform_check("https://example.com", 5.0)

    assert success is False
    assert status_code is None
    assert "connection refused" in error


def test_check_endpoint_records_result_and_updates_monitor_status(monkeypatch):
    monkeypatch.setattr(httpx, "get", lambda url, timeout, follow_redirects: FakeResponse(200))

    with TestClient(app) as client:
        # In production, api owns schema creation and checker just connects to
        # an already-migrated database (see create_tables=False in checker/main.py).
        # Recreate that here since the in-memory db checker's lifespan just opened
        # has no tables yet.
        db.init_engine("sqlite:///:memory:", create_tables=True)

        setup_session = db.session_scope()
        monitor = Monitor(name="test", url="https://example.com", interval_seconds=60)
        setup_session.add(monitor)
        setup_session.commit()
        monitor_id = monitor.id
        setup_session.close()

        response = client.post(
            "/check",
            json={"monitor_id": monitor_id, "url": "https://example.com", "timeout_seconds": 5.0},
        )

        assert response.status_code == 200
        body = response.json()
        assert body["success"] is True
        assert body["status_code"] == 200

        verify_session = db.session_scope()
        stored = verify_session.query(CheckResult).filter_by(monitor_id=monitor_id).one()
        assert stored.success is True

        refreshed_monitor = verify_session.get(Monitor, monitor_id)
        assert refreshed_monitor.status == MonitorStatus.UP
        verify_session.close()
