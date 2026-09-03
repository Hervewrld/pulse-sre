#!/bin/bash
#
# kill-service.sh <dev|prod> <api|scheduler|checker>
# kill-service.sh <dev|prod> <api|scheduler|checker> --restore
#
# Chaos drill: scales a service to zero tasks, simulating it being fully
# down - for api, that means the ALB has no healthy targets at all (the
# closest real equivalent to the roadmap's "throttle the ALB": clients get
# every request rejected, not slowed down, but the ALB-side symptom -
# UnHealthyHostCount alarming, 503s at the ALB itself rather than the app -
# is the same). For scheduler/checker, it means monitors silently stop being
# checked (scheduler) or dispatched checks start failing (checker) - watch
# for the *absence* of expected activity, which is its own kind of signal.
#
# Expect: terraform/modules/observability's alb_unhealthy_hosts alarm (api)
# or ecs_<service>_cpu_high/_memory_high going quiet - not firing, which is
# itself suspicious for a service that's normally never at zero - for
# scheduler/checker. This script does not restore desired_count for you
# automatically; run it again with --restore once you're done observing.

set -euo pipefail

ENVIRONMENT="${1:?Usage: kill-service.sh <dev|prod> <api|scheduler|checker> [--restore]}"
SERVICE="${2:?Usage: kill-service.sh <dev|prod> <api|scheduler|checker> [--restore]}"
RESTORE="${3:-}"
TF_DIR="terraform/environments/${ENVIRONMENT}"

if [[ "${ENVIRONMENT}" == "prod" ]]; then
  echo "This will $( [[ "${RESTORE}" == "--restore" ]] && echo "restore" || echo "take down" ) ${SERVICE} in PRODUCTION."
  read -rp "Type the environment name to confirm: " confirm
  [[ "${confirm}" == "prod" ]] || { echo "Aborted."; exit 1; }
fi

CLUSTER="$(terraform -chdir="${TF_DIR}" output -raw ecs_cluster_name)"
ECS_SERVICE="$(terraform -chdir="${TF_DIR}" output -json ecs_service_names \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['${SERVICE}'])")"

if [[ "${RESTORE}" == "--restore" ]]; then
  echo "== restoring ${ECS_SERVICE} to the desired_count Terraform expects =="
  echo "Reconciling via Terraform (not a hardcoded number here, to avoid drifting from"
  echo "whatever environments/${ENVIRONMENT}/main.tf actually says for this service):"
  echo "  terraform -chdir=${TF_DIR} apply -var image_tag=<current tag>"
  exit 0
fi

echo "== scaling ${ECS_SERVICE} to 0 tasks =="
aws ecs update-service --cluster "${CLUSTER}" --service "${ECS_SERVICE}" --desired-count 0 >/dev/null

cat <<EOF

Triggered. Watch, don't just wait:
  aws ecs describe-services --cluster ${CLUSTER} --services ${ECS_SERVICE} --query 'services[0].runningCount'
  CloudWatch alarms: pulse-${ENVIRONMENT}-alb_unhealthy_hosts (api), pulse-${ENVIRONMENT}-ecs_${SERVICE}_cpu_high (scheduler/checker - watch it go quiet, not fire)

When you're done observing:
  ./scripts/chaos/kill-service.sh ${ENVIRONMENT} ${SERVICE} --restore
EOF
