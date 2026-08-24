#!/bin/bash
#
# bootstrap.sh
# Sets up a local dev environment for Pulse and runs tests.

set -euo pipefail

echo "== pulse bootstrap =="

PYTHON_BIN="$(command -v python3.12 || command -v python3 || true)"
if [[ -z "$PYTHON_BIN" ]]; then
  echo "Missing required command: python3.12 or python3" >&2
  exit 1
fi

if [[ ! -d ".venv" ]]; then
  echo "Creating virtualenv with $PYTHON_BIN..."
  "$PYTHON_BIN" -m venv .venv
fi

# shellcheck disable=SC1091
source .venv/bin/activate

echo "Installing dependencies..."
if [[ -f "requirements-dev.txt" ]]; then
  pip3 install -q -r requirements-dev.txt
else
  echo "(no requirements-dev.txt yet - add one in Phase 0)"
fi

if [[ -f "tests/test_api.py" || -n "$(find tests -name 'test_*.py' 2>/dev/null)" ]]; then
  echo "Running tests..."
  pytest -q
fi

echo "== bootstrap complete =="
echo ""
echo "Next: implement src/api, src/scheduler, src/checker (Phase 0)."
echo "Local Postgres: 'docker compose up -d db' once docker/docker-compose.yml exists."
