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
        self.slack_webhook_url = os.environ.get("SLACK_WEBHOOK_URL") or None
        self.alert_failure_threshold = int(os.environ.get("ALERT_FAILURE_THRESHOLD", "3"))
        self.alert_recovery_threshold = int(os.environ.get("ALERT_RECOVERY_THRESHOLD", "1"))


settings = Settings()
