import pytest

from src.common.config import Settings


def test_database_url_falls_back_to_database_url_env(monkeypatch):
    monkeypatch.delenv("DB_HOST", raising=False)
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg2://pulse:pulse@example:5432/pulse")

    assert Settings._build_database_url() == "postgresql+psycopg2://pulse:pulse@example:5432/pulse"


def test_database_url_falls_back_to_local_dev_default(monkeypatch):
    monkeypatch.delenv("DB_HOST", raising=False)
    monkeypatch.delenv("DATABASE_URL", raising=False)

    assert Settings._build_database_url() == "postgresql+psycopg2://pulse:pulse@localhost:5432/pulse"


def test_database_url_built_from_parts_when_db_host_set(monkeypatch):
    monkeypatch.setenv("DB_HOST", "pulse-dev-db.abc123.us-east-1.rds.amazonaws.com")
    monkeypatch.setenv("DB_PORT", "5432")
    monkeypatch.setenv("DB_NAME", "pulse")
    monkeypatch.setenv("DB_USER", "pulse")
    monkeypatch.setenv("DB_PASSWORD", "s3cr3t")

    assert Settings._build_database_url() == (
        "postgresql+psycopg2://pulse:s3cr3t@"
        "pulse-dev-db.abc123.us-east-1.rds.amazonaws.com:5432/pulse"
    )


def test_database_url_encodes_special_characters_in_credentials(monkeypatch):
    monkeypatch.setenv("DB_HOST", "db.internal")
    monkeypatch.setenv("DB_USER", "pulse")
    monkeypatch.setenv("DB_PASSWORD", "p@ss/w:rd?")

    url = Settings._build_database_url()

    assert url == "postgresql+psycopg2://pulse:p%40ss%2Fw%3Ard%3F@db.internal:5432/pulse"


def test_database_url_raises_clear_error_when_db_host_set_without_credentials(monkeypatch):
    monkeypatch.setenv("DB_HOST", "db.internal")
    monkeypatch.delenv("DB_USER", raising=False)
    monkeypatch.delenv("DB_PASSWORD", raising=False)

    with pytest.raises(RuntimeError, match="DB_HOST is set but"):
        Settings._build_database_url()
