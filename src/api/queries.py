import dataclasses
import datetime

from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from src.common.models import CheckResult, to_naive_utc


def compute_uptime(
    session: Session, monitor_id: int, since: datetime.datetime
) -> tuple[int, int, float | None]:
    """Returns (total_checks, successful_checks, uptime_percentage) since the given time.

    uptime_percentage is None when there are no checks in the window - there's no
    meaningful uptime figure to report, and that's different from 0% (all failing).
    """
    total, successful = session.execute(
        select(
            func.count(),
            func.sum(case((CheckResult.success.is_(True), 1), else_=0)),
        ).where(
            CheckResult.monitor_id == monitor_id,
            CheckResult.checked_at >= to_naive_utc(since),
        )
    ).one()

    successful = successful or 0
    percentage = (successful / total * 100) if total else None
    return total, successful, percentage


@dataclasses.dataclass
class ErrorBudget:
    total_checks: int
    failed_checks: int
    uptime_percentage: float | None
    error_budget_checks: float | None
    budget_consumed_checks: float | None
    budget_remaining_checks: float | None
    budget_remaining_percentage: float | None
    burn_rate: float | None


def compute_error_budget(
    session: Session, monitor_id: int, since: datetime.datetime, slo_target_percentage: float
) -> ErrorBudget:
    """Computes error-budget consumption for the SLI "successful checks / total checks"
    against an SLO of `slo_target_percentage` over the window starting at `since`.

    The error budget is expressed in checks: with a 99.5% SLO over a window with 1000
    checks, up to 5 of them are allowed to fail without breaching the SLO. burn_rate is
    consumed-budget / total-budget for that same window - 1.0 means failures are using
    up the budget at exactly the sustainable rate to just meet the SLO by the end of the
    window; above 1.0 means the budget will run out before the window does.

    Everything is None when there's no data yet (total_checks == 0) or the SLO target is
    100% (error_budget_checks == 0, so remaining-percentage/burn-rate are undefined) -
    consistent with compute_uptime's convention of None meaning "no meaningful figure",
    not 0.
    """
    total, successful, uptime_percentage = compute_uptime(session, monitor_id, since)
    failed = total - successful

    if total == 0:
        return ErrorBudget(
            total_checks=0,
            failed_checks=0,
            uptime_percentage=None,
            error_budget_checks=None,
            budget_consumed_checks=None,
            budget_remaining_checks=None,
            budget_remaining_percentage=None,
            burn_rate=None,
        )

    allowed_failure_rate = 1 - (slo_target_percentage / 100)
    error_budget_checks = total * allowed_failure_rate
    budget_consumed_checks = float(failed)
    budget_remaining_checks = error_budget_checks - budget_consumed_checks

    if error_budget_checks > 0:
        budget_remaining_percentage = (budget_remaining_checks / error_budget_checks) * 100
        burn_rate = budget_consumed_checks / error_budget_checks
    else:
        budget_remaining_percentage = None
        burn_rate = None

    return ErrorBudget(
        total_checks=total,
        failed_checks=failed,
        uptime_percentage=uptime_percentage,
        error_budget_checks=error_budget_checks,
        budget_consumed_checks=budget_consumed_checks,
        budget_remaining_checks=budget_remaining_checks,
        budget_remaining_percentage=budget_remaining_percentage,
        burn_rate=burn_rate,
    )
