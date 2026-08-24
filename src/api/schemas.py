import datetime

from pydantic import BaseModel, ConfigDict, Field

from src.common.models import MonitorStatus


class MonitorCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    url: str = Field(min_length=1, max_length=2048)
    interval_seconds: int = Field(default=60, ge=5)
    timeout_seconds: float = Field(default=5.0, gt=0)


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


class CheckResultOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    monitor_id: int
    checked_at: datetime.datetime
    success: bool
    status_code: int | None
    response_time_ms: float | None
    error: str | None
