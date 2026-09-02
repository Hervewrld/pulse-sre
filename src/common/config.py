import os
from urllib.parse import quote_plus


class Settings:
    """Reads configuration from environment variables, with local-dev defaults."""

    def __init__(self) -> None:
        self.database_url = self._build_database_url()
        self.checker_url = os.environ.get("CHECKER_URL", "http://localhost:8001")
        self.scheduler_poll_interval_seconds = float(
            os.environ.get("SCHEDULER_POLL_INTERVAL_SECONDS", "5")
        )
        self.default_timeout_seconds = float(os.environ.get("DEFAULT_TIMEOUT_SECONDS", "5"))
        self.log_level = os.environ.get("LOG_LEVEL", "INFO")
        self.slack_webhook_url = os.environ.get("SLACK_WEBHOOK_URL") or None
        self.alert_failure_threshold = int(os.environ.get("ALERT_FAILURE_THRESHOLD", "3"))
        self.alert_recovery_threshold = int(os.environ.get("ALERT_RECOVERY_THRESHOLD", "1"))

    @staticmethod
    def _build_database_url() -> str:
        """Builds DATABASE_URL from DB_HOST/DB_PORT/DB_NAME/DB_USER/DB_PASSWORD when DB_HOST is
        set, otherwise falls back to a single DATABASE_URL (or the local-dev default).

        In ECS (terraform/modules/ecs_service), DB_USER/DB_PASSWORD come from the RDS-managed
        Secrets Manager secret via the task definition's `secrets` block - Secrets Manager only
        ever holds those two fields, never a full connection string, so the URL is assembled
        here instead of in Terraform.
        """
        host = os.environ.get("DB_HOST")
        if not host:
            return os.environ.get(
                "DATABASE_URL", "postgresql+psycopg2://pulse:pulse@localhost:5432/pulse"
            )
        try:
            user = quote_plus(os.environ["DB_USER"])
            password = quote_plus(os.environ["DB_PASSWORD"])
        except KeyError as exc:
            raise RuntimeError(
                f"DB_HOST is set but {exc.args[0]} is not - DB_HOST, DB_USER and DB_PASSWORD "
                "must all be set together (see terraform/modules/ecs_service)."
            ) from exc
        port = os.environ.get("DB_PORT", "5432")
        name = os.environ.get("DB_NAME", "pulse")
        return f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{name}"


settings = Settings()
