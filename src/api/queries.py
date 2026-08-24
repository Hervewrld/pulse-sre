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
