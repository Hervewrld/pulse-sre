import datetime

from pydantic import BaseModel, ConfigDict, Field

from src.common.models import AlertEventType, MonitorStatus


class MonitorCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    url: str = Field(min_length=1, max_length=2048)
    interval_seconds: int = Field(default=60, ge=5)
    timeout_seconds: float = Field(default=5.0, gt=0)
    slo_target_percentage: float = Field(default=99.5, gt=0, le=100)
    slo_window_days: float = Field(default=30.0, gt=0)


class MonitorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    url: str
    interval_seconds: int
    timeout_seconds: float
    is_active: bool
    status: MonitorStatus
    created_at: datetime.datetime
    last_checked_at: datetime.datetime | None
    slo_target_percentage: float
    slo_window_days: float


class UptimeOut(BaseModel):
    monitor_id: int
    window_hours: float
    total_checks: int
    successful_checks: int
    uptime_percentage: float | None


class CheckResultOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    monitor_id: int
    checked_at: datetime.datetime
    success: bool
    status_code: int | None
    response_time_ms: float | None
    error: str | None


class AlertEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    monitor_id: int
    event_type: AlertEventType
    created_at: datetime.datetime


class ErrorBudgetOut(BaseModel):
    monitor_id: int
    slo_target_percentage: float
    window_days: float
    total_checks: int
    failed_checks: int
    uptime_percentage: float | None
    error_budget_checks: float | None
    budget_consumed_checks: float | None
    budget_remaining_checks: float | None
    budget_remaining_percentage: float | None
    burn_rate: float | None
