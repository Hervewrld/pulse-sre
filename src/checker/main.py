import time
from contextlib import asynccontextmanager

import httpx
from aws_xray_sdk.core import xray_recorder
from fastapi import FastAPI, Request
from pydantic import BaseModel

from src.alerting.notifier import build_notifier
from src.alerting.rules import evaluate_check
from src.common import db
from src.common.config import settings
from src.common.logging import setup_logging
from src.common.models import AlertEvent, CheckResult, Monitor, MonitorStatus
from src.common.tracing import setup_tracing

logger = setup_logging("checker", settings.log_level)
notifier = build_notifier(settings.slack_webhook_url, logger)


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_tracing("checker", asgi=True)
    db.init_engine(settings.database_url, create_tables=False)
    logger.info("checker started")
    yield


app = FastAPI(title="Pulse Checker", lifespan=lifespan)


@app.middleware("http")
async def xray_middleware(request: Request, call_next):
    # /health is hit every ~30s by the ECS container health check (modules/ecs_service) -
    # tracing it would drown real request traces in noise.
    if not settings.xray_enabled or request.url.path == "/health":
        return await call_next(request)

    async with xray_recorder.in_segment_async(name=f"checker {request.url.path}") as segment:
        segment.put_http_meta("method", request.method)
        segment.put_http_meta("url", str(request.url))
        try:
            response = await call_next(request)
        except Exception as exc:
            segment.add_exception(exc, [])
            raise
        segment.put_http_meta("status", response.status_code)
        return response


class CheckRequest(BaseModel):
    monitor_id: int
    url: str
    timeout_seconds: float = 5.0


class CheckResponse(BaseModel):
    monitor_id: int
    success: bool
    status_code: int | None
    response_time_ms: float | None
    error: str | None


@app.get("/health")
def health():
    return {"status": "ok"}


def perform_check(url: str, timeout_seconds: float) -> tuple[bool, int | None, float | None, str | None]:
    start = time.monotonic()
    try:
        response = httpx.get(url, timeout=timeout_seconds, follow_redirects=True)
        elapsed_ms = (time.monotonic() - start) * 1000
        success = response.status_code < 400
        return success, response.status_code, elapsed_ms, None
    except httpx.HTTPError as exc:
        elapsed_ms = (time.monotonic() - start) * 1000
        return False, None, elapsed_ms, str(exc)


@app.post("/check", response_model=CheckResponse)
def check(payload: CheckRequest):
    success, status_code, response_time_ms, error = perform_check(
        payload.url, payload.timeout_seconds
    )

    event_type = None
    monitor_snapshot = None

    session = db.session_scope()
    try:
        result = CheckResult(
            monitor_id=payload.monitor_id,
            success=success,
            status_code=status_code,
            response_time_ms=response_time_ms,
            error=error,
        )
        session.add(result)

        monitor = session.get(Monitor, payload.monitor_id)
        if monitor is not None:
            monitor.status = MonitorStatus.UP if success else MonitorStatus.DOWN
            event_type = evaluate_check(
                monitor, success, settings.alert_failure_threshold, settings.alert_recovery_threshold
            )
            if event_type is not None:
                session.add(AlertEvent(monitor_id=monitor.id, event_type=event_type))
                # captured now - monitor's attributes are expired once the session
                # below closes, and the notify call happens after that
                monitor_snapshot = (monitor.name, monitor.url)

        session.commit()
    finally:
        session.close()

    logger.info(
        "checked monitor_id=%s success=%s status_code=%s response_time_ms=%s",
        payload.monitor_id,
        success,
        status_code,
        response_time_ms,
    )

    if monitor_snapshot is not None:
        monitor_name, monitor_url = monitor_snapshot
        try:
            notifier.notify(monitor_name, monitor_url, event_type)
        except httpx.HTTPError as exc:
            logger.warning("alert notify failed monitor_id=%s error=%s", payload.monitor_id, exc)

    return CheckResponse(
        monitor_id=payload.monitor_id,
        success=success,
        status_code=status_code,
        response_time_ms=response_time_ms,
        error=error,
    )
