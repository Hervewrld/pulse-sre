import os


class Settings:
    """Reads configuration from environment variables, with local-dev defaults."""

    def __init__(self) -> None:
        self.database_url = os.environ.get(
            "DATABASE_URL", "postgresql+psycopg2://pulse:pulse@localhost:5432/pulse"
        )
        self.checker_url = os.environ.get("CHECKER_URL", "http://localhost:8001")
        self.scheduler_poll_interval_seconds = float(
            os.environ.get("SCHEDULER_POLL_INTERVAL_SECONDS", "5")
        )
        self.default_timeout_seconds = float(os.environ.get("DEFAULT_TIMEOUT_SECONDS", "5"))
        self.log_level = os.environ.get("LOG_LEVEL", "INFO")


settings = Settings()
