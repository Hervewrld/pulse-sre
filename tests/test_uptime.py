import datetime

from fastapi.testclient import TestClient

from src.api.main import app
from src.api.queries import compute_uptime
from src.common.models import CheckResult, Monitor, utcnow


def make_monitor(session):
    monitor = Monitor(name="test", url="https://example.com", interval_seconds=60)
    session.add(monitor)
    session.commit()
    session.refresh(monitor)
    return monitor


def make_result(session, monitor_id, success, checked_at):
    result = CheckResult(monitor_id=monitor_id, success=success, checked_at=checked_at)
    session.add(result)
    session.commit()
    return result


def test_compute_uptime_with_no_checks_returns_none_percentage(session):
    monitor = make_monitor(session)

    total, successful, percentage = compute_uptime(session, monitor.id, utcnow() - datetime.timedelta(hours=24))

    assert total == 0
    assert successful == 0
    assert percentage is None


def test_compute_uptime_all_successful(session):
    monitor = make_monitor(session)
    now = utcnow()
    for _ in range(5):
        make_result(session, monitor.id, True, now)

    total, successful, percentage = compute_uptime(session, monitor.id, now - datetime.timedelta(hours=1))

    assert total == 5
    assert successful == 5
    assert percentage == 100.0


def test_compute_uptime_mixed_results(session):
    monitor = make_monitor(session)
    now = utcnow()
    for _ in range(3):
        make_result(session, monitor.id, True, now)
    for _ in range(1):
        make_result(session, monitor.id, False, now)

    total, successful, percentage = compute_uptime(session, monitor.id, now - datetime.timedelta(hours=1))

    assert total == 4
    assert successful == 3
    assert percentage == 75.0


def test_compute_uptime_excludes_checks_outside_window(session):
    monitor = make_monitor(session)
    now = utcnow()
    make_result(session, monitor.id, False, now - datetime.timedelta(days=2))
    make_result(session, monitor.id, True, now)

    total, successful, percentage = compute_uptime(session, monitor.id, now - datetime.timedelta(hours=24))

    assert total == 1
    assert successful == 1
    assert percentage == 100.0


def test_uptime_endpoint_not_found():
    with TestClient(app) as client:
        response = client.get("/monitors/999999/uptime")
    assert response.status_code == 404


def test_uptime_endpoint_returns_computed_percentage():
    with TestClient(app) as client:
        created = client.post("/monitors", json={"name": "up", "url": "https://example.com"})
        monitor_id = created.json()["id"]

        from src.common import db

        setup_session = db.session_scope()
        now = utcnow()
        make_result(setup_session, monitor_id, True, now)
        make_result(setup_session, monitor_id, True, now)
        make_result(setup_session, monitor_id, False, now)
        setup_session.close()

        response = client.get(f"/monitors/{monitor_id}/uptime?hours=1")
        assert response.status_code == 200
        body = response.json()
        assert body["total_checks"] == 3
        assert body["successful_checks"] == 2
        assert round(body["uptime_percentage"], 2) == 66.67
