import datetime
import time

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from src.common import db
from src.common.config import settings
from src.common.logging import setup_logging
from src.common.models import Monitor, utcnow

logger = setup_logging("scheduler", settings.log_level)


def _as_utc(value: datetime.datetime) -> datetime.datetime:
    """SQLite drops tzinfo on round-trip even for timezone-aware columns; Postgres doesn't.

    Treat a naive value as UTC so due-monitor comparisons work the same on both.
    """
    if value.tzinfo is None:
        return value.replace(tzinfo=datetime.timezone.utc)
    return value


def due_monitors(session: Session, now: datetime.datetime) -> list[Monitor]:
    """Returns active monitors that have never been checked, or are past their interval."""
    all_active = session.scalars(select(Monitor).where(Monitor.is_active.is_(True))).all()
    due = []
    for monitor in all_active:
        if monitor.last_checked_at is None:
            due.append(monitor)
            continue
        elapsed = (now - _as_utc(monitor.last_checked_at)).total_seconds()
        if elapsed >= monitor.interval_seconds:
            due.append(monitor)
    return due


def dispatch_check(monitor: Monitor, checker_url: str, client: httpx.Client) -> None:
    client.post(
        f"{checker_url}/check",
        json={
            "monitor_id": monitor.id,
            "url": monitor.url,
            "timeout_seconds": monitor.timeout_seconds,
        },
    )


def tick(session: Session, checker_url: str, client: httpx.Client) -> list[Monitor]:
    """Finds due monitors, dispatches a check for each, and marks them as checked.

    last_checked_at is stamped before the check result is known, so a slow or failing
    checker call can't cause the same monitor to be redispatched on the next tick.
    """
    now = utcnow()
    monitors = due_monitors(session, now)

    for monitor in monitors:
        monitor.last_checked_at = now
        session.commit()

        try:
            dispatch_check(monitor, checker_url, client)
        except httpx.HTTPError as exc:
            logger.warning("dispatch failed monitor_id=%s error=%s", monitor.id, exc)

    return monitors


def run_forever() -> None:
    db.init_engine(settings.database_url, create_tables=False)
    logger.info("scheduler started, polling every %ss", settings.scheduler_poll_interval_seconds)

    with httpx.Client() as client:
        while True:
            session = db.session_scope()
            try:
                dispatched = tick(session, settings.checker_url, client)
                if dispatched:
                    logger.info("dispatched %d check(s)", len(dispatched))
            finally:
                session.close()

            time.sleep(settings.scheduler_poll_interval_seconds)


if __name__ == "__main__":
    run_forever()
