from src.common.models import AlertEventType, Monitor


def evaluate_check(
    monitor: Monitor, success: bool, failure_threshold: int, recovery_threshold: int
) -> AlertEventType | None:
    """Updates a monitor's consecutive-check counters for one new result and returns
    the alert event this result should raise, if any.

    Debounced on both ends: `failure_threshold` consecutive failures are required to
    raise a DOWN alert, and `recovery_threshold` consecutive successes to raise
    RECOVERED. Each transition returns an event exactly once - once `monitor.alerting`
    is set, further failures keep it down silently instead of re-raising, and the same
    going the other way for recovery. This is what keeps a monitor that's failing for
    an hour from producing one alert per check.
    """
    if success:
        monitor.consecutive_successes += 1
        monitor.consecutive_failures = 0
    else:
        monitor.consecutive_failures += 1
        monitor.consecutive_successes = 0

    if not monitor.alerting and monitor.consecutive_failures >= failure_threshold:
        monitor.alerting = True
        return AlertEventType.DOWN

    if monitor.alerting and monitor.consecutive_successes >= recovery_threshold:
        monitor.alerting = False
        return AlertEventType.RECOVERED

    return None
