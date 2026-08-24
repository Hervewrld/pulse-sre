import datetime
import enum

from sqlalchemy import (
    Boolean,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class MonitorStatus(str, enum.Enum):
    UNKNOWN = "unknown"
    UP = "up"
    DOWN = "down"


def utcnow() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def to_naive_utc(value: datetime.datetime) -> datetime.datetime:
    """Strips tzinfo after converting to UTC.

    SQLite drops tzinfo on timezone-aware columns when it round-trips a row through the
    database, so an aware value compared against it in a WHERE clause won't match as
    expected. Postgres's timestamptz columns store an absolute instant regardless of
    the parameter's tzinfo, so a naive-but-UTC value compares correctly there too -
    using it everywhere keeps queries portable across both.
    """
    if value.tzinfo is not None:
        value = value.astimezone(datetime.timezone.utc)
        return value.replace(tzinfo=None)
    return value


class Monitor(Base):
    __tablename__ = "monitors"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    url: Mapped[str] = mapped_column(String(2048), nullable=False)
    interval_seconds: Mapped[int] = mapped_column(Integer, nullable=False, default=60)
    timeout_seconds: Mapped[float] = mapped_column(Float, nullable=False, default=5.0)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    status: Mapped[MonitorStatus] = mapped_column(
        Enum(MonitorStatus), nullable=False, default=MonitorStatus.UNKNOWN
    )
    created_at: Mapped[datetime.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    last_checked_at: Mapped[datetime.datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    check_results: Mapped[list["CheckResult"]] = relationship(
        back_populates="monitor", cascade="all, delete-orphan"
    )


class CheckResult(Base):
    __tablename__ = "check_results"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    monitor_id: Mapped[int] = mapped_column(ForeignKey("monitors.id"), nullable=False, index=True)
    checked_at: Mapped[datetime.datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, index=True
    )
    success: Mapped[bool] = mapped_column(Boolean, nullable=False)
    status_code: Mapped[int | None] = mapped_column(Integer, nullable=True)
    response_time_ms: Mapped[float | None] = mapped_column(Float, nullable=True)
    error: Mapped[str | None] = mapped_column(Text, nullable=True)

    monitor: Mapped["Monitor"] = relationship(back_populates="check_results")
