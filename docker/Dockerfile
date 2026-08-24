# Shared image for all three Pulse services; SERVICE picks which one runs.
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ src/

ARG SERVICE
ENV SERVICE=${SERVICE}

CMD ["sh", "-c", "\
    if [ \"$SERVICE\" = \"api\" ]; then \
        uvicorn src.api.main:app --host 0.0.0.0 --port 8000; \
    elif [ \"$SERVICE\" = \"checker\" ]; then \
        uvicorn src.checker.main:app --host 0.0.0.0 --port 8001; \
    elif [ \"$SERVICE\" = \"scheduler\" ]; then \
        python -m src.scheduler.main; \
    else \
        echo \"Unknown SERVICE: $SERVICE\" >&2; exit 1; \
    fi \
"]
