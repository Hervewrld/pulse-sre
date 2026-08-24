import datetime

from freezegun import freeze_time

from src.common.models import Monitor
from src.scheduler.main import due_monitors, tick


class FakeClient:
    def __init__(self):
        self.calls = []

    def post(self, url, json):
        self.calls.append((url, json))


def make_monitor(session, **kwargs):
    monitor = Monitor(
        name=kwargs.get("name", "test"),
        url=kwargs.get("url", "https://example.com"),
        interval_seconds=kwargs.get("interval_seconds", 60),
        last_checked_at=kwargs.get("last_checked_at"),
        is_active=kwargs.get("is_active", True),
    )
    session.add(monitor)
    session.commit()
    session.refresh(monitor)
    return monitor


def test_never_checked_monitor_is_due(session):
    monitor = make_monitor(session)
    now = datetime.datetime.now(datetime.timezone.utc)

    assert due_monitors(session, now) == [monitor]


def test_monitor_within_interval_is_not_due(session):
    now = datetime.datetime.now(datetime.timezone.utc)
    make_monitor(session, interval_seconds=60, last_checked_at=now - datetime.timedelta(seconds=10))

    assert due_monitors(session, now) == []


def test_monitor_past_interval_is_due(session):
    now = datetime.datetime.now(datetime.timezone.utc)
    monitor = make_monitor(
        session, interval_seconds=60, last_checked_at=now - datetime.timedelta(seconds=61)
    )

    assert due_monitors(session, now) == [monitor]


def test_inactive_monitor_is_never_due(session):
    make_monitor(session, is_active=False)
    now = datetime.datetime.now(datetime.timezone.utc)

    assert due_monitors(session, now) == []


def test_tick_dispatches_and_stamps_last_checked_at(session):
    monitor = make_monitor(session)
    client = FakeClient()

    with freeze_time("2026-01-01T00:00:00+00:00"):
        dispatched = tick(session, "http://checker:8001", client)

    assert dispatched == [monitor]
    assert len(client.calls) == 1
    url, payload = client.calls[0]
    assert url == "http://checker:8001/check"
    assert payload["monitor_id"] == monitor.id
    assert payload["url"] == monitor.url
    assert monitor.last_checked_at is not None


def test_tick_does_not_redispatch_within_interval(session):
    make_monitor(session, interval_seconds=60)
    client = FakeClient()

    with freeze_time("2026-01-01T00:00:00+00:00"):
        tick(session, "http://checker:8001", client)

    with freeze_time("2026-01-01T00:00:30+00:00"):
        second_dispatch = tick(session, "http://checker:8001", client)

    assert second_dispatch == []
    assert len(client.calls) == 1
