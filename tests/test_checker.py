import httpx
from fastapi.testclient import TestClient

import src.checker.main as checker_main
from src.checker.main import app, perform_check
from src.common import db
from src.common.models import AlertEvent, AlertEventType, CheckResult, Monitor, MonitorStatus


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


class FakeNotifier:
    def __init__(self):
        self.calls = []

    def notify(self, monitor_name, monitor_url, event_type):
        self.calls.append((monitor_name, monitor_url, event_type))


def test_repeated_failures_then_recovery_alert_exactly_once(monkeypatch):
    fake_notifier = FakeNotifier()
    monkeypatch.setattr(checker_main, "notifier", fake_notifier)

    with TestClient(app) as client:
        db.init_engine("sqlite:///:memory:", create_tables=True)

        setup_session = db.session_scope()
        monitor = Monitor(name="flaky", url="https://flaky.example.com", interval_seconds=60)
        setup_session.add(monitor)
        setup_session.commit()
        monitor_id = monitor.id
        setup_session.close()

        def raise_error(url, timeout, follow_redirects):
            raise httpx.ConnectError("connection refused")

        monkeypatch.setattr(httpx, "get", raise_error)

        # Default failure_threshold is 3 - killing the target should produce exactly
        # one DOWN alert, not one per failing check.
        for _ in range(5):
            response = client.post(
                "/check",
                json={"monitor_id": monitor_id, "url": "https://flaky.example.com"},
            )
            assert response.status_code == 200

        assert fake_notifier.calls == [("flaky", "https://flaky.example.com", AlertEventType.DOWN)]

        verify_session = db.session_scope()
        down_events = (
            verify_session.query(AlertEvent)
            .filter_by(monitor_id=monitor_id, event_type=AlertEventType.DOWN)
            .all()
        )
        assert len(down_events) == 1
        verify_session.close()

        monkeypatch.setattr(
            httpx, "get", lambda url, timeout, follow_redirects: FakeResponse(200)
        )

        # Recovery: exactly one RECOVERED alert, even across further successful checks.
        for _ in range(3):
            response = client.post(
                "/check",
                json={"monitor_id": monitor_id, "url": "https://flaky.example.com"},
            )
            assert response.status_code == 200

        assert fake_notifier.calls == [
            ("flaky", "https://flaky.example.com", AlertEventType.DOWN),
            ("flaky", "https://flaky.example.com", AlertEventType.RECOVERED),
        ]

        verify_session = db.session_scope()
        recovered_events = (
            verify_session.query(AlertEvent)
            .filter_by(monitor_id=monitor_id, event_type=AlertEventType.RECOVERED)
            .all()
        )
        assert len(recovered_events) == 1
        verify_session.close()
