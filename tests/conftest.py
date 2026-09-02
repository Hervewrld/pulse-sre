import os

# DB_HOST (if a dev/CI shell happens to have it exported, e.g. left over from
# testing against real infra) would otherwise make Settings._build_database_url()
# require DB_USER/DB_PASSWORD too and raise during collection, before any test
# gets to run - tests always mean the local sqlite default below.
os.environ.pop("DB_HOST", None)
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

import pytest

from src.common import db


@pytest.fixture()
def session():
    """A fresh in-memory sqlite database, isolated per test."""
    db.init_engine("sqlite:///:memory:")
    s = db.session_scope()
    yield s
    s.close()
