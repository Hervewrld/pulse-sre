import datetime
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from src.api.queries import compute_error_budget, compute_uptime
from src.api.schemas import (
    AlertEventOut,
    CheckResultOut,
    ErrorBudgetOut,
    MonitorCreate,
    MonitorOut,
    UptimeOut,
)
from src.common import db
from src.common.config import settings
from src.common.logging import setup_logging
from src.common.models import AlertEvent, CheckResult, Monitor, utcnow

logger = setup_logging("api", settings.log_level)


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.init_engine(settings.database_url)
    logger.info("api started")
    yield


app = FastAPI(title="Pulse API", lifespan=lifespan)


def get_db():
    session = db.session_scope()
    try:
        yield session
    finally:
        session.close()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/monitors", response_model=MonitorOut, status_code=201)
def create_monitor(payload: MonitorCreate, session: Session = Depends(get_db)):
    monitor = Monitor(
        name=payload.name,
        url=payload.url,
        interval_seconds=payload.interval_seconds,
        timeout_seconds=payload.timeout_seconds,
        slo_target_percentage=payload.slo_target_percentage,
        slo_window_days=payload.slo_window_days,
    )
    session.add(monitor)
    session.commit()
    session.refresh(monitor)
    logger.info("created monitor id=%s url=%s", monitor.id, monitor.url)
    return monitor


@app.get("/monitors", response_model=list[MonitorOut])
def list_monitors(session: Session = Depends(get_db)):
    return session.scalars(select(Monitor).order_by(Monitor.id)).all()


@app.get("/monitors/{monitor_id}", response_model=MonitorOut)
def get_monitor(monitor_id: int, session: Session = Depends(get_db)):
    monitor = session.get(Monitor, monitor_id)
    if monitor is None:
        raise HTTPException(status_code=404, detail="monitor not found")
    return monitor


@app.delete("/monitors/{monitor_id}", status_code=204)
def delete_monitor(monitor_id: int, session: Session = Depends(get_db)):
    monitor = session.get(Monitor, monitor_id)
    if monitor is None:
        raise HTTPException(status_code=404, detail="monitor not found")
    session.delete(monitor)
    session.commit()


@app.get("/monitors/{monitor_id}/history", response_model=list[CheckResultOut])
def get_monitor_history(monitor_id: int, limit: int = 100, session: Session = Depends(get_db)):
    monitor = session.get(Monitor, monitor_id)
    if monitor is None:
        raise HTTPException(status_code=404, detail="monitor not found")

    results = session.scalars(
        select(CheckResult)
        .where(CheckResult.monitor_id == monitor_id)
        .order_by(CheckResult.checked_at.desc())
        .limit(limit)
    ).all()
    return results


@app.get("/monitors/{monitor_id}/uptime", response_model=UptimeOut)
def get_monitor_uptime(
    monitor_id: int,
    hours: float = Query(default=24.0, gt=0),
    session: Session = Depends(get_db),
):
    monitor = session.get(Monitor, monitor_id)
    if monitor is None:
        raise HTTPException(status_code=404, detail="monitor not found")

    since = utcnow() - datetime.timedelta(hours=hours)
    total, successful, percentage = compute_uptime(session, monitor_id, since)

    return UptimeOut(
        monitor_id=monitor_id,
        window_hours=hours,
        total_checks=total,
        successful_checks=successful,
        uptime_percentage=percentage,
    )


@app.get("/monitors/{monitor_id}/error-budget", response_model=ErrorBudgetOut)
def get_monitor_error_budget(
    monitor_id: int,
    days: float | None = Query(default=None, gt=0),
    session: Session = Depends(get_db),
):
    monitor = session.get(Monitor, monitor_id)
    if monitor is None:
        raise HTTPException(status_code=404, detail="monitor not found")

    window_days = days if days is not None else monitor.slo_window_days
    since = utcnow() - datetime.timedelta(days=window_days)
    budget = compute_error_budget(session, monitor_id, since, monitor.slo_target_percentage)

    return ErrorBudgetOut(
        monitor_id=monitor_id,
        slo_target_percentage=monitor.slo_target_percentage,
        window_days=window_days,
        total_checks=budget.total_checks,
        failed_checks=budget.failed_checks,
        uptime_percentage=budget.uptime_percentage,
        error_budget_checks=budget.error_budget_checks,
        budget_consumed_checks=budget.budget_consumed_checks,
        budget_remaining_checks=budget.budget_remaining_checks,
        budget_remaining_percentage=budget.budget_remaining_percentage,
        burn_rate=budget.burn_rate,
    )


@app.get("/monitors/{monitor_id}/alerts", response_model=list[AlertEventOut])
def get_monitor_alerts(monitor_id: int, limit: int = 100, session: Session = Depends(get_db)):
    monitor = session.get(Monitor, monitor_id)
    if monitor is None:
        raise HTTPException(status_code=404, detail="monitor not found")

    events = session.scalars(
        select(AlertEvent)
        .where(AlertEvent.monitor_id == monitor_id)
        .order_by(AlertEvent.created_at.desc())
        .limit(limit)
    ).all()
    return events
