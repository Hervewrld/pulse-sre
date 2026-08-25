from fastapi.testclient import TestClient

from src.api.main import app


def test_health():
    with TestClient(app) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_create_and_get_monitor():
    with TestClient(app) as client:
        create_response = client.post(
            "/monitors",
            json={"name": "example", "url": "https://example.com", "interval_seconds": 30},
        )
        assert create_response.status_code == 201
        body = create_response.json()
        assert body["name"] == "example"
        assert body["url"] == "https://example.com"
        assert body["interval_seconds"] == 30
        assert body["status"] == "unknown"
        assert body["last_checked_at"] is None

        monitor_id = body["id"]
        get_response = client.get(f"/monitors/{monitor_id}")
        assert get_response.status_code == 200
        assert get_response.json()["id"] == monitor_id


def test_get_monitor_not_found():
    with TestClient(app) as client:
        response = client.get("/monitors/999999")
    assert response.status_code == 404


def test_list_monitors():
    with TestClient(app) as client:
        client.post("/monitors", json={"name": "a", "url": "https://a.example.com"})
        client.post("/monitors", json={"name": "b", "url": "https://b.example.com"})

        response = client.get("/monitors")
        assert response.status_code == 200
        names = [m["name"] for m in response.json()]
        assert names == ["a", "b"]


def test_delete_monitor():
    with TestClient(app) as client:
        created = client.post("/monitors", json={"name": "temp", "url": "https://temp.example.com"})
        monitor_id = created.json()["id"]

        delete_response = client.delete(f"/monitors/{monitor_id}")
        assert delete_response.status_code == 204

        get_response = client.get(f"/monitors/{monitor_id}")
        assert get_response.status_code == 404


def test_monitor_history_empty_for_new_monitor():
    with TestClient(app) as client:
        created = client.post("/monitors", json={"name": "hist", "url": "https://hist.example.com"})
        monitor_id = created.json()["id"]

        response = client.get(f"/monitors/{monitor_id}/history")
        assert response.status_code == 200
        assert response.json() == []


def test_monitor_history_returns_recorded_checks():
    with TestClient(app) as client:
        created = client.post("/monitors", json={"name": "hist2", "url": "https://hist2.example.com"})
        monitor_id = created.json()["id"]

        from src.common import db
        from src.common.models import CheckResult, utcnow

        session = db.session_scope()
        now = utcnow()
        session.add(CheckResult(monitor_id=monitor_id, success=True, checked_at=now, status_code=200))
        session.add(CheckResult(monitor_id=monitor_id, success=False, checked_at=now, error="timeout"))
        session.commit()
        session.close()

        response = client.get(f"/monitors/{monitor_id}/history")
        assert response.status_code == 200
        body = response.json()
        assert len(body) == 2
        assert {r["success"] for r in body} == {True, False}
        assert all(r["monitor_id"] == monitor_id for r in body)


def test_monitor_history_not_found():
    with TestClient(app) as client:
        response = client.get("/monitors/999999/history")
    assert response.status_code == 404


def test_monitor_alerts_returns_recorded_events():
    with TestClient(app) as client:
        created = client.post("/monitors", json={"name": "alerts", "url": "https://alerts.example.com"})
        monitor_id = created.json()["id"]

        from src.common import db
        from src.common.models import AlertEvent, AlertEventType, utcnow

        session = db.session_scope()
        now = utcnow()
        session.add(AlertEvent(monitor_id=monitor_id, event_type=AlertEventType.DOWN, created_at=now))
        session.add(AlertEvent(monitor_id=monitor_id, event_type=AlertEventType.RECOVERED, created_at=now))
        session.commit()
        session.close()

        response = client.get(f"/monitors/{monitor_id}/alerts")
        assert response.status_code == 200
        body = response.json()
        assert len(body) == 2
        assert {e["event_type"] for e in body} == {"down", "recovered"}
        assert all(e["monitor_id"] == monitor_id for e in body)


def test_monitor_alerts_not_found():
    with TestClient(app) as client:
        response = client.get("/monitors/999999/alerts")
    assert response.status_code == 404


def test_invalid_monitor_payload_rejected():
    with TestClient(app) as client:
        response = client.post("/monitors", json={"name": "", "url": "https://example.com"})
    assert response.status_code == 422
