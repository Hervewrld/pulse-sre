#!/bin/bash
#
# kill-database.sh <dev|prod>
#
# Chaos drill: forces an RDS failover (prod, Multi-AZ) or a full instance
# reboot (dev, single-AZ - there's no standby to fail over to) to simulate a
# database outage. Detection should come from
# terraform/modules/observability's rds_cpu_high/rds_connections_high alarms
# and api/scheduler/checker's own logs showing DB connection errors - not
# from watching this script's output. That's the point of the drill.
#
# Expect: app-level errors and failing container health checks for the
# ~30-90s RDS takes to fail over/restart, and (Multi-AZ prod only) zero data
# loss - that's what Multi-AZ is for. Write up what actually happened in
# docs/postmortems/ (copy TEMPLATE.md) - this script does not do that for you.

set -euo pipefail

ENVIRONMENT="${1:?Usage: kill-database.sh <dev|prod>}"
DB_IDENTIFIER="pulse-${ENVIRONMENT}-db"

if [[ "${ENVIRONMENT}" == "prod" ]]; then
  echo "This will force-failover the PRODUCTION database (${DB_IDENTIFIER})."
  read -rp "Type the environment name to confirm: " confirm
  [[ "${confirm}" == "prod" ]] || { echo "Aborted."; exit 1; }
fi

if [[ "${ENVIRONMENT}" == "prod" ]]; then
  echo "== ${DB_IDENTIFIER}: forcing Multi-AZ failover =="
  aws rds reboot-db-instance --db-instance-identifier "${DB_IDENTIFIER}" --force-failover
else
  echo "== ${DB_IDENTIFIER}: rebooting (single-AZ - this is downtime, not a failover) =="
  aws rds reboot-db-instance --db-instance-identifier "${DB_IDENTIFIER}"
fi

cat <<EOF

Triggered. Watch, don't just wait:
  - CloudWatch alarms: pulse-${ENVIRONMENT}-rds_cpu_high, pulse-${ENVIRONMENT}-rds_connections_high
  - Logs Insights saved query: pulse-${ENVIRONMENT}/api/errors (and scheduler/checker)
  - aws rds describe-db-instances --db-instance-identifier ${DB_IDENTIFIER} --query 'DBInstances[0].DBInstanceStatus'
EOF
