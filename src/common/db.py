from sqlalchemy import create_engine
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from src.common.models import Base

_engine: Engine | None = None
_SessionLocal: sessionmaker | None = None


def init_engine(database_url: str, create_tables: bool = True) -> Engine:
    """Creates the engine/session factory for this process.

    Safe to call more than once (e.g. from tests) - re-initializes state each time.

    create_tables=False lets multiple services share one database without racing each
    other's concurrent CREATE TABLE/CREATE TYPE statements - exactly one service (api)
    should own schema creation, and the others should start only once it's healthy.
    """
    global _engine, _SessionLocal

    connect_args = {}
    engine_kwargs = {}
    if database_url.startswith("sqlite"):
        connect_args["check_same_thread"] = False
        if ":memory:" in database_url:
            engine_kwargs["poolclass"] = StaticPool

    _engine = create_engine(database_url, connect_args=connect_args, **engine_kwargs)
    _SessionLocal = sessionmaker(bind=_engine, autoflush=False, autocommit=False)
    if create_tables:
        Base.metadata.create_all(_engine)
    return _engine


def get_sessionmaker() -> sessionmaker:
    if _SessionLocal is None:
        raise RuntimeError("Database engine not initialized - call init_engine() first")
    return _SessionLocal


def session_scope() -> Session:
    """Returns a new Session; caller is responsible for closing it."""
    return get_sessionmaker()()
