import httpx
import pytest

from src.alerting.notifier import LoggingNotifier, SlackNotifier, build_notifier
from src.alerting.rules import evaluate_check
from src.common.models import AlertEventType, Monitor


def make_monitor():
    # SQLAlchemy column defaults apply on INSERT, not on a bare instance - set them
    # explicitly since these tests use evaluate_check() directly, without a session.
    return Monitor(
        name="test",
        url="https://example.com",
        consecutive_failures=0,
        consecutive_successes=0,
        alerting=False,
    )


def test_failures_below_threshold_do_not_alert():
    monitor = make_monitor()

    assert evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1) is None
    assert evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1) is None
    assert monitor.alerting is False


def test_reaching_failure_threshold_raises_down_once():
    monitor = make_monitor()

    evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1)
    evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1)
    event = evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1)

    assert event == AlertEventType.DOWN
    assert monitor.alerting is True


def test_further_failures_after_down_do_not_re_alert():
    monitor = make_monitor()
    for _ in range(3):
        evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1)

    event = evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1)

    assert event is None
    assert monitor.alerting is True


def test_success_after_down_raises_recovered_once():
    monitor = make_monitor()
    for _ in range(3):
        evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1)

    event = evaluate_check(monitor, True, failure_threshold=3, recovery_threshold=1)

    assert event == AlertEventType.RECOVERED
    assert monitor.alerting is False


def test_further_successes_after_recovered_do_not_re_alert():
    monitor = make_monitor()
    for _ in range(3):
        evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1)
    evaluate_check(monitor, True, failure_threshold=3, recovery_threshold=1)

    event = evaluate_check(monitor, True, failure_threshold=3, recovery_threshold=1)

    assert event is None
    assert monitor.alerting is False


def test_recovery_threshold_debounces_flaky_success():
    monitor = make_monitor()
    for _ in range(3):
        evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=2)

    first_success = evaluate_check(monitor, True, failure_threshold=3, recovery_threshold=2)
    assert first_success is None
    assert monitor.alerting is True

    second_success = evaluate_check(monitor, True, failure_threshold=3, recovery_threshold=2)
    assert second_success == AlertEventType.RECOVERED


def test_intermittent_failure_does_not_alert_if_it_never_reaches_threshold():
    monitor = make_monitor()

    evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1)
    evaluate_check(monitor, False, failure_threshold=3, recovery_threshold=1)
    event = evaluate_check(monitor, True, failure_threshold=3, recovery_threshold=1)

    assert event is None
    assert monitor.alerting is False
    assert monitor.consecutive_failures == 0


class FakeSlackResponse:
    def raise_for_status(self):
        pass


def test_slack_notifier_posts_message(monkeypatch):
    calls = []

    def fake_post(url, json, timeout):
        calls.append((url, json, timeout))
        return FakeSlackResponse()

    monkeypatch.setattr("httpx.post", fake_post)

    notifier = SlackNotifier("https://hooks.slack.example/webhook")
    notifier.notify("api", "https://api.example.com", AlertEventType.DOWN)

    assert len(calls) == 1
    url, payload, timeout = calls[0]
    assert url == "https://hooks.slack.example/webhook"
    assert "DOWN" in payload["text"]
    assert "api" in payload["text"]


def test_slack_notifier_raises_on_failed_delivery(monkeypatch):
    class FailingResponse:
        def raise_for_status(self):
            raise httpx.HTTPStatusError("bad webhook", request=None, response=None)

    monkeypatch.setattr("httpx.post", lambda url, json, timeout: FailingResponse())

    notifier = SlackNotifier("https://hooks.slack.example/webhook")
    with pytest.raises(httpx.HTTPStatusError):
        notifier.notify("api", "https://api.example.com", AlertEventType.DOWN)


def test_logging_notifier_logs_instead_of_sending(caplog):
    import logging

    logger = logging.getLogger("test-alerting")
    notifier = LoggingNotifier(logger)

    with caplog.at_level(logging.WARNING, logger="test-alerting"):
        notifier.notify("api", "https://api.example.com", AlertEventType.RECOVERED)

    assert "RECOVERED" in caplog.text
    assert "api" in caplog.text


def test_build_notifier_picks_slack_when_webhook_configured():
    assert isinstance(build_notifier("https://hooks.slack.example/x", None), SlackNotifier)


def test_build_notifier_falls_back_to_logging_when_no_webhook():
    import logging

    logger = logging.getLogger("test-alerting")
    assert isinstance(build_notifier(None, logger), LoggingNotifier)
