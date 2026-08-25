import datetime

import pytest
from fastapi.testclient import TestClient

from src.api.main import app
from src.api.queries import compute_error_budget
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


def test_compute_error_budget_with_no_checks_returns_all_none(session):
    monitor = make_monitor(session)

    budget = compute_error_budget(
        session, monitor.id, utcnow() - datetime.timedelta(days=30), slo_target_percentage=99.5
    )

    assert budget.total_checks == 0
    assert budget.failed_checks == 0
    assert budget.uptime_percentage is None
    assert budget.error_budget_checks is None
    assert budget.budget_remaining_percentage is None
    assert budget.burn_rate is None


def test_compute_error_budget_within_slo_has_remaining_budget(session):
    monitor = make_monitor(session)
    now = utcnow()
    for _ in range(999):
        make_result(session, monitor.id, True, now)
    make_result(session, monitor.id, False, now)

    budget = compute_error_budget(
        session, monitor.id, now - datetime.timedelta(days=1), slo_target_percentage=99.5
    )

    assert budget.total_checks == 1000
    assert budget.failed_checks == 1
    assert budget.uptime_percentage == pytest.approx(99.9)
    # 99.5% SLO over 1000 checks allows 5 failures; only 1 has happened
    assert budget.error_budget_checks == pytest.approx(5.0)
    assert budget.budget_consumed_checks == 1.0
    assert budget.budget_remaining_checks == pytest.approx(4.0)
    assert budget.budget_remaining_percentage == pytest.approx(80.0)
    assert budget.burn_rate == pytest.approx(0.2)


def test_compute_error_budget_exhausted_goes_negative(session):
    monitor = make_monitor(session)
    now = utcnow()
    for _ in range(990):
        make_result(session, monitor.id, True, now)
    for _ in range(10):
        make_result(session, monitor.id, False, now)

    budget = compute_error_budget(
        session, monitor.id, now - datetime.timedelta(days=1), slo_target_percentage=99.5
    )

    assert budget.total_checks == 1000
    assert budget.failed_checks == 10
    # allowed = 5, actual failures = 10 -> budget is blown, burn rate > 1
    assert budget.error_budget_checks == pytest.approx(5.0)
    assert budget.budget_remaining_checks == pytest.approx(-5.0)
    assert budget.budget_remaining_percentage == pytest.approx(-100.0)
    assert budget.burn_rate == pytest.approx(2.0)


def test_compute_error_budget_all_successful_has_full_budget_remaining(session):
    monitor = make_monitor(session)
    now = utcnow()
    for _ in range(100):
        make_result(session, monitor.id, True, now)

    budget = compute_error_budget(
        session, monitor.id, now - datetime.timedelta(days=1), slo_target_percentage=99.5
    )

    assert budget.failed_checks == 0
    assert budget.budget_remaining_percentage == 100.0
    assert budget.burn_rate == 0.0


def test_compute_error_budget_hundred_percent_slo_has_no_error_budget(session):
    monitor = make_monitor(session)
    now = utcnow()
    for _ in range(10):
        make_result(session, monitor.id, True, now)

    budget = compute_error_budget(
        session, monitor.id, now - datetime.timedelta(days=1), slo_target_percentage=100.0
    )

    # 100% SLO means zero allowed failures - the budget-as-a-fraction figures are
    # undefined (division by zero), not zero.
    assert budget.error_budget_checks == 0.0
    assert budget.budget_remaining_percentage is None
    assert budget.burn_rate is None


def test_error_budget_endpoint_uses_monitor_slo_defaults():
    with TestClient(app) as client:
        created = client.post(
            "/monitors",
            json={"name": "budget", "url": "https://budget.example.com"},
        )
        monitor_id = created.json()["id"]
        assert created.json()["slo_target_percentage"] == 99.5
        assert created.json()["slo_window_days"] == 30.0

        from src.common import db

        setup_session = db.session_scope()
        now = utcnow()
        for _ in range(199):
            make_result(setup_session, monitor_id, True, now)
        make_result(setup_session, monitor_id, False, now)
        setup_session.close()

        response = client.get(f"/monitors/{monitor_id}/error-budget")
        assert response.status_code == 200
        body = response.json()
        assert body["slo_target_percentage"] == 99.5
        assert body["window_days"] == 30.0
        assert body["total_checks"] == 200
        assert body["failed_checks"] == 1
        assert round(body["burn_rate"], 4) == 1.0


def test_error_budget_endpoint_days_override():
    with TestClient(app) as client:
        created = client.post(
            "/monitors",
            json={"name": "budget2", "url": "https://budget2.example.com"},
        )
        monitor_id = created.json()["id"]

        from src.common import db

        setup_session = db.session_scope()
        now = utcnow()
        make_result(setup_session, monitor_id, False, now - datetime.timedelta(days=10))
        make_result(setup_session, monitor_id, True, now)
        setup_session.close()

        response = client.get(f"/monitors/{monitor_id}/error-budget?days=1")
        assert response.status_code == 200
        body = response.json()
        assert body["window_days"] == 1.0
        assert body["total_checks"] == 1


def test_error_budget_endpoint_not_found():
    with TestClient(app) as client:
        response = client.get("/monitors/999999/error-budget")
    assert response.status_code == 404


def test_monitor_create_accepts_custom_slo():
    with TestClient(app) as client:
        response = client.post(
            "/monitors",
            json={
                "name": "custom-slo",
                "url": "https://custom.example.com",
                "slo_target_percentage": 99.9,
                "slo_window_days": 7,
            },
        )
        assert response.status_code == 201
        body = response.json()
        assert body["slo_target_percentage"] == 99.9
        assert body["slo_window_days"] == 7.0


def test_monitor_create_rejects_invalid_slo_target():
    with TestClient(app) as client:
        response = client.post(
            "/monitors",
            json={"name": "bad-slo", "url": "https://bad.example.com", "slo_target_percentage": 0},
        )
        assert response.status_code == 422
