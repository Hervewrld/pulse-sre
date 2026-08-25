import logging
from abc import ABC, abstractmethod

import httpx

from src.common.models import AlertEventType


class Notifier(ABC):
    @abstractmethod
    def notify(self, monitor_name: str, monitor_url: str, event_type: AlertEventType) -> None: ...


def _message(monitor_name: str, monitor_url: str, event_type: AlertEventType) -> str:
    if event_type == AlertEventType.DOWN:
        return f":red_circle: *{monitor_name}* is DOWN ({monitor_url})"
    return f":large_green_circle: *{monitor_name}* has RECOVERED ({monitor_url})"


class SlackNotifier(Notifier):
    def __init__(self, webhook_url: str):
        self._webhook_url = webhook_url

    def notify(self, monitor_name: str, monitor_url: str, event_type: AlertEventType) -> None:
        response = httpx.post(
            self._webhook_url,
            json={"text": _message(monitor_name, monitor_url, event_type)},
            timeout=5.0,
        )
        response.raise_for_status()


class LoggingNotifier(Notifier):
    """Fallback used when no Slack webhook is configured - logs instead of sending."""

    def __init__(self, logger: logging.Logger):
        self._logger = logger

    def notify(self, monitor_name: str, monitor_url: str, event_type: AlertEventType) -> None:
        self._logger.warning(
            "ALERT %s (no SLACK_WEBHOOK_URL configured): %s",
            event_type.value,
            _message(monitor_name, monitor_url, event_type),
        )


def build_notifier(webhook_url: str | None, logger: logging.Logger) -> Notifier:
    if webhook_url:
        return SlackNotifier(webhook_url)
    return LoggingNotifier(logger)
