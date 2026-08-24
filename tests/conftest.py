import os

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
