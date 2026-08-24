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


def test_invalid_monitor_payload_rejected():
    with TestClient(app) as client:
        response = client.post("/monitors", json={"name": "", "url": "https://example.com"})
    assert response.status_code == 422
